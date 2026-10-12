import 'dart:convert';

import 'package:drift/drift.dart';

import '../domain/finance.dart';
import '../domain/models.dart';
import 'database.dart';
import 'pos_repository.dart';

/// Expenses, cash closings and reports, computed from the local database so
/// that they work offline. Mutations write their outbox event in the same
/// transaction.
class FinanceRepository {
  FinanceRepository(this.pos);
  final PosRepository pos;
  PosDatabase get db => pos.db;
  String _now() => pos.now().toUtc().toIso8601String();

  static String _text(String value, int min, int max, String field) {
    final v = value.trim();
    if (v.length < min || v.length > max || v.contains('\n')) {
      throw BusinessException('$field : $min à $max caractères.');
    }
    return v;
  }

  Future<String> recordExpense(
    Actor actor, {
    required ExpenseKind kind,
    required String category,
    required int amount,
    required PaymentMode mode,
    required String reason,
    DateTime? occurredAt,
  }) async {
    actor.requireAdmin();
    final cat = _text(category, 1, 60, 'Catégorie');
    final motive = _text(reason, 3, 200, 'Motif');
    if (amount <= 0 || amount > maxMoney) {
      throw const BusinessException('Montant invalide.');
    }
    final now = pos.now().toUtc();
    final when = (occurredAt ?? now).toUtc();
    if (when.isAfter(now.add(const Duration(minutes: 5))) ||
        when.isBefore(DateTime.utc(2020))) {
      throw const BusinessException('Date de dépense invalide.');
    }
    final id = PosRepository.uuid.v4();
    final recorded = now.toIso8601String();
    await db.transaction(() async {
      await db
          .into(db.expenses)
          .insert(
            ExpensesCompanion.insert(
              id: id,
              kind: kind.code,
              category: cat,
              amount: amount,
              paymentMode: mode.name,
              reason: motive,
              occurredAt: when.toIso8601String(),
              actorId: actor.id,
              actorName: actor.name,
              recordedAt: recorded,
            ),
          );
      await pos.appendEvent(id, 'expense.recorded', actor, recorded, {
        'kind': kind.code,
        'category': cat,
        'amount': amount,
        'payment_mode': mode.name,
        'reason': motive,
        'occurred_at': when.toIso8601String(),
      });
    });
    return id;
  }

  /// Expenses are never edited: a mistake is cancelled with a reason.
  Future<void> cancelExpense(Actor actor, String id, String reason) async {
    actor.requireAdmin();
    final motive = _text(reason, 3, 200, 'Motif');
    await db.transaction(() async {
      final expense = await (db.select(
        db.expenses,
      )..where((e) => e.id.equals(id))).getSingleOrNull();
      if (expense == null) {
        throw const BusinessException('Dépense introuvable.');
      }
      if (expense.cancelledAt != null) {
        throw const BusinessException('Dépense déjà annulée.');
      }
      final at = _now();
      await (db.update(db.expenses)..where((e) => e.id.equals(id))).write(
        ExpensesCompanion(
          cancelledAt: Value(at),
          cancelReason: Value(motive),
          cancelledBy: Value(actor.name),
        ),
      );
      await pos.appendEvent(
        PosRepository.uuid.v4(),
        'expense.cancelled',
        actor,
        at,
        {'expense_id': id, 'reason': motive},
      );
    });
  }

  Future<List<ExpenseView>> expenses(ReportPeriod period) async {
    final rows =
        await (db.select(db.expenses)
              ..where(
                (e) =>
                    e.occurredAt.isBiggerOrEqualValue(period.startIso) &
                    e.occurredAt.isSmallerThanValue(period.endIso),
              )
              ..orderBy([(e) => OrderingTerm.desc(e.occurredAt)]))
            .get();
    return [
      for (final e in rows)
        ExpenseView(
          id: e.id,
          kind: ExpenseKind.byCode(e.kind),
          category: e.category,
          amount: e.amount,
          paymentMode: e.paymentMode,
          reason: e.reason,
          occurredAt: e.occurredAt,
          actor: e.actorName,
          cancelledAt: e.cancelledAt,
          cancelReason: e.cancelReason,
        ),
    ];
  }

  Future<List<String>> expenseCategories() async => [
    for (final r
        in await db
            .customSelect(
              'SELECT category, COUNT(*) AS n FROM expenses GROUP BY category '
              'ORDER BY n DESC, category LIMIT 20',
            )
            .get())
      r.read<String>('category'),
  ];

  /// Effective payment mode of each sale (latest correction wins).
  Future<Map<String, String>> _effectiveModes(Iterable<String> saleIds) async {
    final ids = saleIds.toList();
    final modes = <String, String>{};
    if (ids.isEmpty) return modes;
    final corrections =
        await (db.select(db.saleCorrections)
              ..where((c) => c.saleId.isIn(ids))
              ..orderBy([(c) => OrderingTerm.asc(c.occurredAt)]))
            .get();
    for (final c in corrections) {
      modes[c.saleId] = c.paymentMode;
    }
    return modes;
  }

  Future<List<Sale>> _salesBetween(String start, String end) =>
      (db.select(db.sales)..where(
            (s) =>
                s.occurredAt.isBiggerOrEqualValue(start) &
                s.occurredAt.isSmallerThanValue(end),
          ))
          .get();

  /// Cash expected since the previous closing. Expenses count from when they
  /// were recorded (the money left the drawer then), whatever their date.
  Future<CashPosition> cashPosition() async {
    final last =
        await (db.select(db.cashClosings)
              ..orderBy([(c) => OrderingTerm.desc(c.closedAt)])
              ..limit(1))
            .getSingleOrNull();
    final start = last?.closedAt ?? DateTime.utc(2020).toIso8601String();
    // Strictly after the previous closing: an operation stamped at the very
    // instant of a closing belongs to the closed period.
    final sales = await (db.select(
      db.sales,
    )..where((s) => s.occurredAt.isBiggerThanValue(start))).get();
    final modes = await _effectiveModes(sales.map((s) => s.id));
    var cashSales = 0;
    for (final s in sales) {
      final mode =
          modes[s.id] ?? (jsonDecode(s.snapshot) as Map)['payment_mode'];
      if (mode == PaymentMode.cash.name) cashSales += s.total;
    }
    final refunds = await db
        .customSelect(
          "SELECT COALESCE(SUM(refund_total), 0) AS t FROM sale_returns "
          "WHERE refund_mode = 'cash' AND occurred_at > ?",
          variables: [Variable(start)],
        )
        .getSingle();
    final spent = await db
        .customSelect(
          "SELECT COALESCE(SUM(amount), 0) AS t FROM expenses "
          "WHERE payment_mode = 'cash' AND cancelled_at IS NULL "
          "AND recorded_at > ?",
          variables: [Variable(start)],
        )
        .getSingle();
    return CashPosition(
      periodStart: start,
      openingFloat: last?.keptFloat ?? 0,
      cashSales: cashSales,
      cashRefunds: refunds.read<int>('t'),
      cashExpenses: spent.read<int>('t'),
      firstClosing: last == null,
    );
  }

  /// Records the counted cash and the float kept for the next period.
  Future<Map<String, Object?>> closeCash(
    Actor actor, {
    required int counted,
    required int keptFloat,
    required String comment,
    int? openingFloat,
  }) async {
    actor.requireAdmin();
    if (counted < 0 || counted > maxMoney) {
      throw const BusinessException('Montant compté invalide.');
    }
    if (keptFloat < 0 || keptFloat > counted) {
      throw const BusinessException(
        'Le fond de caisse conservé ne peut pas dépasser le montant compté.',
      );
    }
    final note = comment.trim();
    if (note.length > 200) {
      throw const BusinessException('Commentaire trop long.');
    }
    return db.transaction(() async {
      var position = await cashPosition();
      if (position.firstClosing && openingFloat != null) {
        if (openingFloat < 0 || openingFloat > maxMoney) {
          throw const BusinessException('Fond de caisse initial invalide.');
        }
        position = CashPosition(
          periodStart: position.periodStart,
          openingFloat: openingFloat,
          cashSales: position.cashSales,
          cashRefunds: position.cashRefunds,
          cashExpenses: position.cashExpenses,
          firstClosing: true,
        );
      }
      final id = PosRepository.uuid.v4();
      final at = _now();
      final difference = counted - position.expected;
      if (difference != 0 && note.length < 3) {
        throw const BusinessException(
          'Écart de caisse : indiquez un commentaire (3 caractères minimum).',
        );
      }
      final payload = <String, Object?>{
        'period_start': position.periodStart,
        'opening_float': position.openingFloat,
        'cash_sales': position.cashSales,
        'cash_refunds': position.cashRefunds,
        'cash_expenses': position.cashExpenses,
        'expected': position.expected,
        'counted': counted,
        'difference': difference,
        'kept_float': keptFloat,
        'comment': note,
      };
      await db
          .into(db.cashClosings)
          .insert(
            CashClosingsCompanion.insert(
              id: id,
              periodStart: position.periodStart,
              closedAt: at,
              openingFloat: position.openingFloat,
              cashSales: position.cashSales,
              cashRefunds: position.cashRefunds,
              cashExpenses: position.cashExpenses,
              expected: position.expected,
              counted: counted,
              difference: difference,
              keptFloat: keptFloat,
              comment: note,
              actorId: actor.id,
              actorName: actor.name,
            ),
          );
      await pos.appendEvent(id, 'cash.closed', actor, at, payload);
      return {...payload, 'closed_at': at, 'actor': actor.name};
    });
  }

  Future<List<CashClosing>> closings({int limit = 30}) =>
      (db.select(db.cashClosings)
            ..orderBy([(c) => OrderingTerm.desc(c.closedAt)])
            ..limit(limit))
          .get();

  /// One row per sold line, with the effective payment mode.
  Future<String> salesCsv(ReportPeriod period) async {
    final sales = await _salesBetween(period.startIso, period.endIso)
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    final modes = await _effectiveModes(sales.map((s) => s.id));
    return toCsv([
      [
        'date (Abidjan)',
        'numéro',
        'vendeur',
        'catégorie',
        'article',
        'variante',
        'référence',
        'quantité',
        'prix unitaire FCFA',
        'montant FCFA',
        'mode de paiement',
      ],
      for (final sale in sales)
        for (final line
            in (jsonDecode(sale.snapshot) as Map<String, dynamic>)['lines']
                as List)
          [
            abidjanDate(sale.occurredAt),
            sale.number,
            (jsonDecode(sale.snapshot) as Map)['seller'],
            line['category'],
            line['name'],
            line['label'],
            line['sku'],
            line['quantity'],
            line['unit_price'],
            line['line_total'],
            PaymentMode.values
                .byName(
                  modes[sale.id] ??
                      (jsonDecode(sale.snapshot) as Map)['payment_mode']
                          as String,
                )
                .label,
          ],
    ]);
  }

  Future<String> expensesCsv(ReportPeriod period) async {
    final items = (await expenses(period)).reversed;
    return toCsv([
      [
        'date (Abidjan)',
        'type',
        'catégorie',
        'montant FCFA',
        'réglée en',
        'motif',
        'auteur',
        'statut',
        'motif d’annulation',
      ],
      for (final e in items)
        [
          abidjanDate(e.occurredAt),
          e.kind.label,
          e.category,
          e.amount,
          PaymentMode.values.byName(e.paymentMode).label,
          e.reason,
          e.actor,
          e.cancelled ? 'annulée' : 'valide',
          e.cancelReason,
        ],
    ]);
  }

  Future<String> summaryCsv(ReportPeriod period) async {
    final r = await report(period);
    String mode(String name) => PaymentMode.values.byName(name).label;
    return toCsv([
      ['rubrique', 'détail', 'valeur'],
      ['période', r.period.label, ''],
      ['ventes', 'nombre', r.saleCount],
      ['ventes', 'brutes FCFA', r.gross],
      ['ventes', 'retours et remboursements FCFA', r.refunds],
      ['ventes', 'nettes FCFA', r.net],
      ['quantités', 'vendues', r.quantity],
      ['quantités', 'rendues', r.returnedQuantity],
      for (final e in r.payments.entries) ['paiements', mode(e.key), e.value],
      for (final e in r.refundsByMode.entries)
        ['remboursements', mode(e.key), e.value],
      for (final e in r.byCategory.entries) ['catégories', e.key, e.value],
      for (final k in ExpenseKind.values)
        ['dépenses', k.label, r.expensesByKind[k] ?? 0],
      ['caisse', 'clôtures', r.closings],
      ['caisse', 'écart cumulé FCFA', r.closingGap],
      ['stock', 'articles en stock', r.stockUnits],
      ['stock', 'valeur au prix de vente FCFA', r.stockValueAtPrice],
      ['marge', 'non calculable', 'prix d’achat non enregistrés'],
    ]);
  }

  Future<SalesReport> report(ReportPeriod period) async {
    final sales = await _salesBetween(period.startIso, period.endIso);
    final modes = await _effectiveModes(sales.map((s) => s.id));
    var gross = 0, quantity = 0;
    final byCategory = <String, int>{}, payments = <String, int>{};
    final variants = <String, (String, int, int)>{};
    for (final sale in sales) {
      final snapshot = jsonDecode(sale.snapshot) as Map<String, dynamic>;
      gross += sale.total;
      final mode = modes[sale.id] ?? snapshot['payment_mode'] as String;
      payments[mode] = (payments[mode] ?? 0) + sale.total;
      for (final line in snapshot['lines'] as List) {
        final qty = line['quantity'] as int, amount = line['line_total'] as int;
        quantity += qty;
        final cat = line['category'] as String;
        byCategory[cat] = (byCategory[cat] ?? 0) + amount;
        final key = line['variant_id'] as String;
        final previous = variants[key];
        variants[key] = (
          '${line['name']} · ${line['label']}',
          (previous?.$2 ?? 0) + qty,
          (previous?.$3 ?? 0) + amount,
        );
      }
    }
    final returns = await db
        .customSelect(
          'SELECT r.refund_mode AS mode, SUM(l.quantity) AS qty, '
          'SUM(l.line_total) AS total FROM sale_returns r '
          'JOIN sale_return_lines l ON l.return_id = r.id '
          'WHERE r.occurred_at >= ? AND r.occurred_at < ? GROUP BY r.refund_mode',
          variables: [Variable(period.startIso), Variable(period.endIso)],
        )
        .get();
    final refundsByMode = {
      for (final r in returns) r.read<String>('mode'): r.read<int>('total'),
    };
    final expenses = [
      for (final e in await this.expenses(period))
        if (!e.cancelled) e,
    ];
    final byKind = <ExpenseKind, int>{};
    final byExpenseCategory = <String, int>{};
    for (final e in expenses) {
      byKind[e.kind] = (byKind[e.kind] ?? 0) + e.amount;
      byExpenseCategory[e.category] =
          (byExpenseCategory[e.category] ?? 0) + e.amount;
    }
    final stock = await pos.inventory();
    final closings =
        await (db.select(db.cashClosings)..where(
              (c) =>
                  c.closedAt.isBiggerOrEqualValue(period.startIso) &
                  c.closedAt.isSmallerThanValue(period.endIso),
            ))
            .get();
    return SalesReport(
      period: period,
      saleCount: sales.length,
      gross: gross,
      quantity: quantity,
      refunds: refundsByMode.values.fold(0, (a, b) => a + b),
      returnedQuantity: returns.fold(0, (a, r) => a + r.read<int>('qty')),
      byCategory: byCategory,
      byVariant: [
        for (final v in variants.values) VariantSales(v.$1, v.$2, v.$3),
      ]..sort((a, b) => b.amount.compareTo(a.amount)),
      payments: payments,
      refundsByMode: refundsByMode,
      expensesByKind: byKind,
      expensesByCategory: byExpenseCategory,
      stockUnits: stock.where((v) => v.active).fold(0, (a, v) => a + v.stock),
      stockValueAtPrice: stock
          .where((v) => v.active)
          .fold(0, (a, v) => a + v.stock * v.price),
      alerts: [
        for (final v in stock)
          if (v.active && (v.stock == 0 || v.lowStock))
            '${v.name} · ${v.label} : ${v.stock == 0 ? 'épuisé' : 'stock ${v.stock} (seuil ${v.threshold})'}',
      ],
      closings: closings.length,
      closingGap: closings.fold(0, (a, c) => a + c.difference),
    );
  }
}
