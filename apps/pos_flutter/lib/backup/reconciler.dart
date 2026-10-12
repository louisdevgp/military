import 'dart:convert';

import 'package:drift/drift.dart';

import '../data/database.dart';
import '../data/pos_repository.dart';
import '../domain/models.dart';
import '../sync/sync_service.dart';
import 'backup_service.dart';

class ReconcileResult {
  const ReconcileResult({
    required this.applied,
    required this.confirmed,
    required this.pending,
    required this.usersWithoutPin,
  });

  /// Server operations missing from the backup, replayed locally.
  final int applied;

  /// Local operations the server already had.
  final int confirmed;

  /// Local operations still to send.
  final int pending;

  /// Accounts created after the backup: their PIN never leaves a terminal,
  /// so an administrator must give them a new one.
  final List<String> usersWithoutPin;
}

/// Brings a restored terminal up to the server: each operation the server
/// holds and the backup lacks is replayed with the exact local effects of
/// the original one, then counters resume after the server's.
class Reconciler {
  Reconciler(this.pos, this.transport);
  final PosRepository pos;
  final SyncTransport transport;
  PosDatabase get db => pos.db;
  final _users = <String>[];

  Future<ReconcileResult> run() async {
    final terminal = await pos.terminal();
    final server = await transport.state();
    if (server['terminal_id'] != terminal.terminalId) {
      throw const BusinessException(
        'Ce serveur connaît un autre terminal : réconciliation impossible.',
      );
    }
    final serverLast = server['last_sequence'] as int;
    final local = {
      for (final e in await db.select(db.outboxEntries).get()) e.sequence: e,
    };
    var after = 0;
    for (final e in local.values) {
      if (e.status == 'synced' && e.sequence > after) after = e.sequence;
    }
    var applied = 0, confirmed = 0;
    while (after < serverLast) {
      final page = (await transport.events(after))['events'] as List;
      if (page.isEmpty) break;
      for (final raw in page) {
        final envelope = (raw as Map).cast<String, dynamic>();
        final sequence = envelope['sequence'] as int;
        final mine = local[sequence];
        if (mine != null) {
          if (mine.id != envelope['id']) {
            throw BusinessException(
              'Conflit à l’opération $sequence : le serveur détient une autre opération. '
              'Conservez cette sauvegarde et contactez le support.',
            );
          }
          await (db.update(db.outboxEntries)
                ..where((o) => o.id.equals(mine.id)))
              .write(const OutboxEntriesCompanion(status: Value('synced')));
          confirmed++;
        } else {
          await db.transaction(() async {
            await _apply(envelope);
            await db
                .into(db.outboxEntries)
                .insert(
                  OutboxEntriesCompanion.insert(
                    id: envelope['id'] as String,
                    sequence: sequence,
                    envelope: jsonEncode(envelope),
                    status: const Value('synced'),
                  ),
                );
          });
          applied++;
        }
        after = sequence;
      }
    }
    if (after < serverLast) {
      throw const BusinessException(
        'Réconciliation incomplète : réessayez avec une connexion stable.',
      );
    }
    await db.transaction(() async {
      final state = await pos.terminal();
      final localSales = state.saleSequence;
      await (db.update(
        db.terminalStates,
      )..where((t) => t.singleton.equals(1))).write(
        TerminalStatesCompanion(
          eventSequence: Value(
            state.eventSequence > serverLast ? state.eventSequence : serverLast,
          ),
          saleSequence: Value(
            localSales > (server['sale_sequence'] as int)
                ? localSales
                : server['sale_sequence'] as int,
          ),
        ),
      );
      await (db.delete(
        db.shopSettings,
      )..where((s) => s.key.equals(reconcileKey))).go();
    });
    return ReconcileResult(
      applied: applied,
      confirmed: confirmed,
      pending: await pos.pendingCount(),
      usersWithoutPin: List.unmodifiable(_users),
    );
  }

  Future<String> _actorName(String id) async =>
      (await (db.select(
        db.users,
      )..where((u) => u.id.equals(id))).getSingleOrNull())?.name ??
      'Opérateur';

  Future<void> _stock(String variantId, int delta) async {
    final changed = await db.customUpdate(
      'UPDATE variants SET stock = stock + ? WHERE id = ? AND stock + ? >= 0',
      variables: [Variable(delta), Variable(variantId), Variable(delta)],
      updates: {db.variants},
    );
    if (changed != 1) {
      throw const BusinessException('Réconciliation : stock incohérent.');
    }
  }

  Future<void> _movement(
    String variantId,
    String kind,
    int quantity,
    Map<String, dynamic> envelope,
    String reason, {
    String? id,
    String? origin,
    int? counted,
  }) => db
      .into(db.stockMovements)
      .insert(
        StockMovementsCompanion.insert(
          id: id ?? PosRepository.uuid.v4(),
          variantId: variantId,
          kind: kind,
          quantity: quantity,
          actorId: envelope['actor_id'] as String,
          reason: reason,
          originId: origin ?? envelope['id'] as String,
          occurredAt: envelope['occurred_at'] as String,
          counted: Value(counted),
        ),
      );

  Future<void> _apply(Map<String, dynamic> e) async {
    final p = (e['payload'] as Map).cast<String, dynamic>();
    final at = e['occurred_at'] as String;
    final actorId = e['actor_id'] as String;
    switch (e['kind']) {
      case 'user.created':
        final known = await (db.select(
          db.users,
        )..where((u) => u.id.equals(p['user_id'] as String))).getSingleOrNull();
        if (known != null) break;
        _users.add(p['name'] as String);
        await db
            .into(db.users)
            .insert(
              UsersCompanion.insert(
                id: p['user_id'] as String,
                name: p['name'] as String,
                role: p['role'] as String,
                pinHash: '',
                pinSalt: '',
                pinIterations: 0,
                createdAt: at,
              ),
            );
      case 'user.updated':
        await (db.update(db.users)
              ..where((u) => u.id.equals(p['user_id'] as String)))
            .write(UsersCompanion(active: Value(p['active'] as bool)));
      case 'user.pin_reset' || 'backup.created':
        break; // audit only
      case 'catalog.created':
        await db
            .into(db.categories)
            .insert(
              CategoriesCompanion.insert(
                id: p['category_id'] as String,
                name: p['category'] as String,
              ),
              mode: InsertMode.insertOrIgnore,
            );
        await db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                id: p['product_id'] as String,
                categoryId: p['category_id'] as String,
                name: p['name'] as String,
              ),
              mode: InsertMode.insertOrIgnore,
            );
        final stock = p['initial_stock'] as int;
        await db
            .into(db.variants)
            .insert(
              VariantsCompanion.insert(
                id: p['variant_id'] as String,
                productId: p['product_id'] as String,
                sku: p['sku'] as String,
                label: p['label'] as String,
                price: p['price'] as int,
                stock: stock,
                color: Value(p['color'] as String?),
                size: Value(p['size'] as String?),
              ),
            );
        if (stock != 0) {
          await _movement(
            p['variant_id'] as String,
            'INITIAL',
            stock,
            e,
            'Stock initial',
          );
        }
      case 'variant.price_changed':
        await (db.update(db.variants)
              ..where((v) => v.id.equals(p['variant_id'] as String)))
            .write(VariantsCompanion(price: Value(p['price'] as int)));
      case 'variant.updated':
        await (db.update(
          db.variants,
        )..where((v) => v.id.equals(p['variant_id'] as String))).write(
          VariantsCompanion(
            threshold: p.containsKey('threshold')
                ? Value(p['threshold'] as int)
                : const Value.absent(),
            active: p.containsKey('active')
                ? Value(p['active'] as bool)
                : const Value.absent(),
          ),
        );
      case 'sale.completed':
        for (final line in p['lines'] as List) {
          await _stock(
            line['variant_id'] as String,
            -(line['quantity'] as int),
          );
          await _movement(
            line['variant_id'] as String,
            'SALE',
            -(line['quantity'] as int),
            e,
            'Vente ${p['number']}',
            origin: p['id'] as String,
          );
        }
        await db
            .into(db.sales)
            .insert(
              SalesCompanion.insert(
                id: p['id'] as String,
                number: p['number'] as String,
                requestHash: 'restauré:${p['id']}',
                occurredAt: p['occurred_at'] as String,
                snapshot: jsonEncode(p),
                total: p['total'] as int,
              ),
            );
      case 'sale.payment_corrected':
        await db
            .into(db.saleCorrections)
            .insert(
              SaleCorrectionsCompanion.insert(
                id: e['id'] as String,
                saleId: p['sale_id'] as String,
                paymentMode: p['payment_mode'] as String,
                tendered: Value(p['tendered'] as int?),
                changeGiven: p['change'] as int,
                reason: p['reason'] as String,
                actorId: actorId,
                actorName: await _actorName(actorId),
                occurredAt: at,
              ),
            );
      case 'sale.returned':
        await db
            .into(db.saleReturns)
            .insert(
              SaleReturnsCompanion.insert(
                id: p['id'] as String,
                saleId: p['sale_id'] as String,
                kind: p['kind'] as String,
                refundTotal: p['refund_total'] as int,
                refundMode: p['refund_mode'] as String,
                reason: p['reason'] as String,
                requestHash: 'restauré:${p['id']}',
                actorId: actorId,
                actorName: await _actorName(actorId),
                occurredAt: at,
              ),
            );
        for (final line in p['lines'] as List) {
          await db
              .into(db.saleReturnLines)
              .insert(
                SaleReturnLinesCompanion.insert(
                  returnId: p['id'] as String,
                  variantId: line['variant_id'] as String,
                  quantity: line['quantity'] as int,
                  unitPrice: line['unit_price'] as int,
                  lineTotal: line['line_total'] as int,
                  resaleable: line['resaleable'] as bool,
                ),
              );
          if (line['resaleable'] as bool) {
            await _stock(line['variant_id'] as String, line['quantity'] as int);
            await _movement(
              line['variant_id'] as String,
              'RETURN',
              line['quantity'] as int,
              e,
              'Retour ${p['sale_number']}',
              origin: p['id'] as String,
            );
          }
        }
      case 'stock.moved':
        await _stock(p['variant_id'] as String, p['quantity'] as int);
        await _movement(
          p['variant_id'] as String,
          p['kind'] as String,
          p['quantity'] as int,
          e,
          p['reason'] as String,
          id: e['id'] as String,
          counted: p['counted'] as int?,
        );
      case 'expense.recorded':
        await db
            .into(db.expenses)
            .insert(
              ExpensesCompanion.insert(
                id: e['id'] as String,
                kind: p['kind'] as String,
                category: p['category'] as String,
                amount: p['amount'] as int,
                paymentMode: p['payment_mode'] as String,
                reason: p['reason'] as String,
                occurredAt: p['occurred_at'] as String,
                actorId: actorId,
                actorName: await _actorName(actorId),
                recordedAt: at,
              ),
            );
      case 'expense.cancelled':
        await (db.update(
          db.expenses,
        )..where((x) => x.id.equals(p['expense_id'] as String))).write(
          ExpensesCompanion(
            cancelledAt: Value(at),
            cancelReason: Value(p['reason'] as String),
            cancelledBy: Value(await _actorName(actorId)),
          ),
        );
      case 'cash.closed':
        await db
            .into(db.cashClosings)
            .insert(
              CashClosingsCompanion.insert(
                id: e['id'] as String,
                periodStart: p['period_start'] as String,
                closedAt: at,
                openingFloat: p['opening_float'] as int,
                cashSales: p['cash_sales'] as int,
                cashRefunds: p['cash_refunds'] as int,
                cashExpenses: p['cash_expenses'] as int,
                expected: p['expected'] as int,
                counted: p['counted'] as int,
                difference: p['difference'] as int,
                keptFloat: p['kept_float'] as int,
                comment: p['comment'] as String,
                actorId: actorId,
                actorName: await _actorName(actorId),
              ),
            );
      case 'settings.receipt_updated':
        for (final entry in {
          'shop_name': p['shop_name'],
          'contacts': p['contacts'],
          'footer': p['footer'],
          'logo': p['logo'],
        }.entries) {
          await db
              .into(db.shopSettings)
              .insertOnConflictUpdate(
                ShopSettingsCompanion.insert(
                  key: entry.key,
                  value: entry.value as String,
                ),
              );
        }
      default:
        throw BusinessException(
          'Opération inconnue à réconcilier : ${e['kind']}.',
        );
    }
  }
}
