import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../domain/models.dart';
import 'database.dart';

class PosRepository {
  PosRepository(this.db, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  final PosDatabase db;
  final DateTime Function() now;
  static const uuid = Uuid();

  Future<void> initialize() => db.transaction(() async {
    if (await db.select(db.terminalStates).getSingleOrNull() != null) return;
    final id = uuid.v4();
    await db
        .into(db.terminalStates)
        .insert(
          TerminalStatesCompanion.insert(
            terminalId: id,
            prefix: 'T${id.replaceAll('-', '').substring(0, 8).toUpperCase()}',
          ),
        );
  });

  Future<TerminalState> terminal() => db.select(db.terminalStates).getSingle();

  /// Sellable variants only.
  Future<List<CatalogItem>> catalog() => _items(activeOnly: true);

  /// Every variant, including deactivated ones, for stock management.
  Future<List<CatalogItem>> inventory() => _items(activeOnly: false);

  Future<List<CatalogItem>> _items({required bool activeOnly}) async {
    final photos = <String, List<String>>{};
    for (final row
        in await db
            .customSelect(
              'SELECT product_id, path FROM local_product_photos ORDER BY position',
            )
            .get()) {
      photos
          .putIfAbsent(row.read<String>('product_id'), () => [])
          .add(row.read<String>('path'));
    }
    final query = db.select(db.variants).join([
      innerJoin(db.products, db.products.id.equalsExp(db.variants.productId)),
      innerJoin(
        db.categories,
        db.categories.id.equalsExp(db.products.categoryId),
      ),
    ]);
    if (activeOnly) query.where(db.variants.active.equals(true));
    final rows = await query.get();
    return rows.map((row) {
      final v = row.readTable(db.variants);
      return CatalogItem(
        id: v.id,
        productId: v.productId,
        category: row.readTable(db.categories).name,
        name: row.readTable(db.products).name,
        sku: v.sku,
        label: v.label,
        price: v.price,
        stock: v.stock,
        photoPaths: List.unmodifiable(photos[v.productId] ?? const <String>[]),
        color: v.color,
        size: v.size,
        threshold: v.threshold,
        active: v.active,
      );
    }).toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  static String _motive(String reason) {
    final motive = reason.trim();
    if (motive.length < 3 || motive.length > 200) {
      throw const BusinessException('Indiquez un motif de 3 à 200 caractères.');
    }
    return motive;
  }

  /// Reception (+), loss (−) or signed correction, administrator only.
  /// Negative stock is refused in SQL, inside the same transaction as the
  /// movement and its outbox event.
  Future<void> moveStock(
    Actor actor,
    String variantId, {
    required StockKind kind,
    required int quantity,
    required String reason,
  }) async {
    actor.requireAdmin();
    final motive = _motive(reason);
    if (quantity == 0 || quantity.abs() > maxQuantity) {
      throw const BusinessException('Quantité invalide.');
    }
    if (kind != StockKind.adjustment && quantity < 0) {
      throw const BusinessException('Saisissez une quantité positive.');
    }
    final delta = kind == StockKind.loss ? -quantity : quantity;
    await db.transaction(
      () => _applyMovement(actor, variantId, kind, delta, motive),
    );
  }

  /// Inventory: counted quantities replace the stock through ADJUSTMENT
  /// movements recording the count and the difference. Unchanged counts
  /// create nothing. Returns the number of corrected variants.
  Future<int> countInventory(
    Actor actor,
    Map<String, int> counted, {
    String reason = 'Inventaire',
  }) async {
    actor.requireAdmin();
    final motive = _motive(reason);
    if (counted.isEmpty || counted.length > 500) {
      throw const BusinessException('Aucune quantité comptée.');
    }
    if (counted.values.any((q) => q < 0 || q > maxQuantity)) {
      throw const BusinessException('Quantité comptée invalide.');
    }
    return db.transaction(() async {
      var changed = 0;
      for (final entry in counted.entries) {
        final variant = await _variant(entry.key);
        final delta = entry.value - variant.stock;
        if (delta == 0) continue;
        await _applyMovement(
          actor,
          entry.key,
          StockKind.adjustment,
          delta,
          motive,
          counted: entry.value,
        );
        changed++;
      }
      return changed;
    });
  }

  Future<Variant> _variant(String id) async =>
      await (db.select(
        db.variants,
      )..where((v) => v.id.equals(id))).getSingleOrNull() ??
      (throw const BusinessException('Variante introuvable.'));

  Future<void> _applyMovement(
    Actor actor,
    String variantId,
    StockKind kind,
    int delta,
    String reason, {
    int? counted,
  }) async {
    await _variant(variantId);
    final changed = await db.customUpdate(
      'UPDATE variants SET stock = stock + ? WHERE id = ? AND stock + ? >= 0',
      variables: [Variable(delta), Variable(variantId), Variable(delta)],
      updates: {db.variants},
    );
    if (changed != 1) {
      throw const BusinessException(
        'Stock insuffisant : le stock ne peut pas devenir négatif.',
      );
    }
    final id = uuid.v4();
    final timestamp = now().toUtc().toIso8601String();
    await db
        .into(db.stockMovements)
        .insert(
          StockMovementsCompanion.insert(
            id: id,
            variantId: variantId,
            kind: kind.code,
            quantity: delta,
            actorId: actor.id,
            reason: reason,
            originId: id,
            occurredAt: timestamp,
            counted: Value(counted),
          ),
        );
    await appendEvent(id, 'stock.moved', actor, timestamp, {
      'variant_id': variantId,
      'kind': kind.code,
      'quantity': delta,
      'reason': reason,
      'counted': ?counted,
    });
  }

  /// Alert threshold and sale status; history and past sales are untouched.
  Future<void> updateVariant(
    Actor actor,
    String variantId, {
    int? threshold,
    bool? active,
  }) async {
    actor.requireAdmin();
    if (threshold == null && active == null) return;
    if (threshold != null && (threshold < 0 || threshold > maxQuantity)) {
      throw const BusinessException('Seuil invalide.');
    }
    await db.transaction(() async {
      final variant = await _variant(variantId);
      if ((threshold ?? variant.threshold) == variant.threshold &&
          (active ?? variant.active) == variant.active) {
        return;
      }
      await (db.update(
        db.variants,
      )..where((v) => v.id.equals(variantId))).write(
        VariantsCompanion(
          threshold: threshold == null
              ? const Value.absent()
              : Value(threshold),
          active: active == null ? const Value.absent() : Value(active),
        ),
      );
      await appendEvent(
        uuid.v4(),
        'variant.updated',
        actor,
        now().toUtc().toIso8601String(),
        {'variant_id': variantId, 'threshold': ?threshold, 'active': ?active},
      );
    });
  }

  /// Stock history of a variant, newest first, with operator names.
  Future<List<StockMovementView>> movements(String variantId) async {
    final rows = await db
        .customSelect(
          'SELECT m.kind, m.quantity, m.reason, m.occurred_at, m.counted, '
          'COALESCE(u.name, m.actor_id) AS actor FROM stock_movements m '
          'LEFT JOIN users u ON u.id = m.actor_id WHERE m.variant_id = ? '
          'ORDER BY m.occurred_at DESC, m.rowid DESC LIMIT 200',
          variables: [Variable(variantId)],
        )
        .get();
    return [
      for (final r in rows)
        StockMovementView(
          kind: r.read<String>('kind'),
          quantity: r.read<int>('quantity'),
          reason: r.read<String>('reason'),
          actor: r.read<String>('actor'),
          occurredAt: r.read<String>('occurred_at'),
          counted: r.readNullable<int>('counted'),
        ),
    ];
  }

  /// Single-variant shortcut kept for the existing flows and tests.
  Future<String> createItem({
    required Actor actor,
    required String category,
    required String name,
    required String sku,
    required String label,
    required int price,
    required int stock,
    List<String> photoPaths = const [],
  }) async => (await createProduct(
    actor: actor,
    category: category,
    name: name,
    variants: [
      VariantDraft(sku: sku, label: label, price: price, stock: stock),
    ],
    photoPaths: photoPaths,
  )).single;

  /// Creates one article with its variants (sizes), initial stock movements
  /// and one `catalog.created` event per variant, atomically. Returns the
  /// variant ids in the given order.
  Future<List<String>> createProduct({
    required Actor actor,
    required String category,
    required String name,
    required List<VariantDraft> variants,
    List<String> photoPaths = const [],
  }) async {
    actor.requireAdmin();
    if (photoPaths.length > 3 ||
        photoPaths.toSet().length != photoPaths.length) {
      throw const BusinessException(
        'Ajoutez au maximum trois photos différentes.',
      );
    }
    for (final path in photoPaths) {
      final file = File(path);
      if (!RegExp(r'[/\\]catalog_images[/\\][a-f0-9-]{36}\.jpg$')
              .hasMatch(path) ||
          !file.isAbsolute ||
          !await file.exists() ||
          await file.length() > 2 * 1024 * 1024) {
        throw const BusinessException(
          'Une photo est indisponible. Sélectionnez-la à nouveau.',
        );
      }
    }
    final references = _validateDrafts(category, name, variants);
    return db.transaction(() async {
      await _requireFreeReferences(references);
      final existing = await (db.select(
        db.categories,
      )..where((c) => c.name.equals(category.trim()))).getSingleOrNull();
      final categoryId = existing?.id ?? uuid.v4();
      if (existing == null) {
        await db
            .into(db.categories)
            .insert(
              CategoriesCompanion.insert(id: categoryId, name: category.trim()),
            );
      }
      final productId = uuid.v4();
      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              id: productId,
              categoryId: categoryId,
              name: name.trim(),
            ),
          );
      for (var index = 0; index < photoPaths.length; index++) {
        await db.customInsert(
          'INSERT INTO local_product_photos (product_id, position, path) VALUES (?, ?, ?)',
          variables: [
            Variable(productId),
            Variable(index),
            Variable(photoPaths[index]),
          ],
        );
      }
      return _insertVariants(
        actor,
        categoryId: categoryId,
        category: category.trim(),
        productId: productId,
        name: name.trim(),
        variants: variants,
        references: references,
      );
    });
  }

  /// New colours or sizes received for an existing article. Only the given
  /// combinations are created, with their real stock; existing variants and
  /// past sales are untouched.
  Future<List<String>> addVariants(
    Actor actor,
    String productId,
    List<VariantDraft> variants,
  ) async {
    actor.requireAdmin();
    final product = await (db.select(
      db.products,
    )..where((p) => p.id.equals(productId))).getSingleOrNull();
    if (product == null) throw const BusinessException('Article introuvable.');
    final category = await (db.select(
      db.categories,
    )..where((c) => c.id.equals(product.categoryId))).getSingle();
    final references = _validateDrafts(category.name, product.name, variants);
    return db.transaction(() async {
      await _requireFreeReferences(references);
      final labels = {
        for (final v in await (db.select(
          db.variants,
        )..where((v) => v.productId.equals(productId))).get())
          v.label.toLowerCase(),
      };
      for (final v in variants) {
        if (labels.contains(v.label.trim().toLowerCase())) {
          throw BusinessException('Cette variante existe déjà : ${v.label}.');
        }
      }
      return _insertVariants(
        actor,
        categoryId: category.id,
        category: category.name,
        productId: productId,
        name: product.name,
        variants: variants,
        references: references,
      );
    });
  }

  List<String> _validateDrafts(
    String category,
    String name,
    List<VariantDraft> variants,
  ) {
    if (variants.isEmpty || variants.length > 60) {
      throw const BusinessException(
        'Saisissez le stock d’au moins une variante (60 au maximum).',
      );
    }
    for (final text in [
      category,
      name,
      for (final v in variants) ...[v.sku, v.label],
    ]) {
      if (text.trim().isEmpty || text.trim().length > 120) {
        throw const BusinessException(
          'Les libellés doivent contenir entre 1 et 120 caractères.',
        );
      }
    }
    for (final v in variants) {
      if (v.price < 0 ||
          v.price > maxMoney ||
          v.stock < 0 ||
          v.stock > maxQuantity) {
        throw const BusinessException('Prix ou stock hors limites.');
      }
      if ((v.color?.length ?? 0) > 40 || (v.size?.length ?? 0) > 20) {
        throw const BusinessException('Couleur ou taille trop longue.');
      }
    }
    final references = [for (final v in variants) v.sku.trim().toUpperCase()];
    final labels = [for (final v in variants) v.label.trim().toLowerCase()];
    if (references.toSet().length != references.length ||
        labels.toSet().length != labels.length) {
      throw const BusinessException(
        'Chaque variante doit avoir sa propre référence et son libellé.',
      );
    }
    return references;
  }

  Future<void> _requireFreeReferences(List<String> references) async {
    final taken = await (db.select(
      db.variants,
    )..where((v) => v.sku.isIn(references))).get();
    if (taken.isNotEmpty) {
      throw BusinessException(
        'Cette référence existe déjà : ${taken.first.sku}.',
      );
    }
  }

  /// Must run inside the caller's transaction.
  Future<List<String>> _insertVariants(
    Actor actor, {
    required String categoryId,
    required String category,
    required String productId,
    required String name,
    required List<VariantDraft> variants,
    required List<String> references,
  }) async {
    final timestamp = now().toUtc().toIso8601String();
    final ids = <String>[];
    for (var i = 0; i < variants.length; i++) {
      final v = variants[i];
      final variantId = uuid.v4(), operationId = uuid.v4();
      await db
          .into(db.variants)
          .insert(
            VariantsCompanion.insert(
              id: variantId,
              productId: productId,
              sku: references[i],
              label: v.label.trim(),
              price: v.price,
              stock: v.stock,
              color: Value(v.color),
              size: Value(v.size),
            ),
          );
      if (v.stock != 0) {
        await _movement(
          variantId,
          'INITIAL',
          v.stock,
          actor,
          'Stock initial',
          operationId,
          timestamp,
        );
      }
      await appendEvent(operationId, 'catalog.created', actor, timestamp, {
        'category_id': categoryId,
        'category': category,
        'product_id': productId,
        'name': name,
        'variant_id': variantId,
        'sku': references[i],
        'label': v.label.trim(),
        'price': v.price,
        'initial_stock': v.stock,
        'published': false,
        // Optional attributes, absent from free single variants.
        'color': ?v.color,
        'size': ?v.size,
      });
      ids.add(variantId);
    }
    return ids;
  }

  /// Replaces an article's photos (cover first, three at most). Photos stay
  /// on this terminal and are not part of any event. Returns the paths no
  /// longer referenced, for deletion after commit.
  Future<List<String>> replacePhotos(
    Actor actor,
    String productId,
    List<String> paths,
  ) async {
    actor.requireAdmin();
    if (paths.length > 3 || paths.toSet().length != paths.length) {
      throw const BusinessException(
        'Ajoutez au maximum trois photos différentes.',
      );
    }
    for (final path in paths) {
      final file = File(path);
      if (!RegExp(r'[/\\]catalog_images[/\\][a-f0-9-]{36}\.jpg$')
              .hasMatch(path) ||
          !file.isAbsolute ||
          !await file.exists() ||
          await file.length() > 2 * 1024 * 1024) {
        throw const BusinessException(
          'Une photo est indisponible. Sélectionnez-la à nouveau.',
        );
      }
    }
    return db.transaction(() async {
      final product = await (db.select(
        db.products,
      )..where((p) => p.id.equals(productId))).getSingleOrNull();
      if (product == null) {
        throw const BusinessException('Article introuvable.');
      }
      final previous = [
        for (final row
            in await db
                .customSelect(
                  'SELECT path FROM local_product_photos WHERE product_id = ?',
                  variables: [Variable(productId)],
                )
                .get())
          row.read<String>('path'),
      ];
      await db.customStatement(
        'DELETE FROM local_product_photos WHERE product_id = ?',
        [productId],
      );
      for (var index = 0; index < paths.length; index++) {
        await db.customInsert(
          'INSERT INTO local_product_photos (product_id, position, path) VALUES (?, ?, ?)',
          variables: [
            Variable(productId),
            Variable(index),
            Variable(paths[index]),
          ],
        );
      }
      return [
        for (final p in previous)
          if (!paths.contains(p)) p,
      ];
    });
  }

  Future<void> changePrice(Actor actor, String variantId, int price) =>
      changePrices(actor, {variantId: price});

  /// New selling prices for future sales, all or nothing. Unchanged prices are
  /// skipped; past sales keep their snapshot. Returns the number changed.
  Future<int> changePrices(Actor actor, Map<String, int> prices) async {
    actor.requireAdmin();
    if (prices.isEmpty || prices.length > 30) {
      throw const BusinessException('Aucun prix à modifier.');
    }
    if (prices.values.any((p) => p < 0 || p > maxMoney)) {
      throw const BusinessException('Prix hors limites.');
    }
    return db.transaction(() async {
      final timestamp = now().toUtc().toIso8601String();
      var changed = 0;
      for (final entry in prices.entries) {
        final variant = await (db.select(
          db.variants,
        )..where((v) => v.id.equals(entry.key))).getSingleOrNull();
        if (variant == null) {
          throw const BusinessException('Variante introuvable.');
        }
        if (variant.price == entry.value) continue;
        await (db.update(db.variants)..where((v) => v.id.equals(entry.key)))
            .write(VariantsCompanion(price: Value(entry.value)));
        await appendEvent(
          uuid.v4(),
          'variant.price_changed',
          actor,
          timestamp,
          {'variant_id': entry.key, 'price': entry.value},
        );
        changed++;
      }
      return changed;
    });
  }

  Future<Map<String, dynamic>> checkout(
    Actor actor,
    SaleRequest request,
  ) async {
    if (!Uuid.isValidUUID(fromString: request.id)) {
      throw const BusinessException('Identifiant de vente invalide.');
    }
    if (request.quantities.isEmpty || request.quantities.length > 100) {
      throw const BusinessException('Panier vide ou trop volumineux.');
    }
    if (request.customer.keys.any(
          (k) => !['name', 'first_name', 'unit', 'phone'].contains(k),
        ) ||
        request.customer.values.any((v) => v.length > 120)) {
      throw const BusinessException('Informations client invalides.');
    }
    final hash = fingerprint({...request.toJson(), 'actor_id': actor.id});
    return db.transaction(() async {
      final previous = await (db.select(
        db.sales,
      )..where((s) => s.id.equals(request.id))).getSingleOrNull();
      if (previous != null) {
        if (previous.requestHash != hash) {
          throw const BusinessException(
            'Conflit : cet identifiant correspond à une autre vente.',
          );
        }
        return jsonDecode(previous.snapshot) as Map<String, dynamic>;
      }
      final items = {for (final v in await catalog()) v.id: v};
      final lines = <Map<String, Object?>>[];
      var total = 0;
      for (final entry in request.quantities.entries) {
        final item = items[entry.key];
        if (item == null) {
          throw const BusinessException(
            'Une variante est introuvable ou inactive.',
          );
        }
        final qty = entry.value;
        if (qty <= 0 || qty > maxQuantity) {
          throw const BusinessException('Quantité invalide.');
        }
        if (item.stock < qty) {
          throw BusinessException(
            'Stock insuffisant : ${item.name} (${item.label}).',
          );
        }
        final lineTotal = item.price * qty;
        total += lineTotal;
        if (total > maxMoney) {
          throw const BusinessException('Total de vente trop élevé.');
        }
        lines.add({
          'variant_id': item.id,
          'category': item.category,
          'name': item.name,
          'sku': item.sku,
          'label': item.label,
          'quantity': qty,
          'unit_price': item.price,
          'line_total': lineTotal,
          'unit_cost': null,
        });
      }
      final cash = request.paymentMode == PaymentMode.cash;
      if (cash &&
          (request.tendered == null ||
              request.tendered! < total ||
              request.tendered! > maxMoney)) {
        throw const BusinessException('La somme remise doit couvrir le total.');
      }
      if (!cash && request.tendered != null) {
        throw const BusinessException('Somme remise réservée aux espèces.');
      }
      final state = await terminal();
      final timestamp = now().toUtc().toIso8601String();
      final sequence = state.saleSequence + 1;
      final number = saleNumber(DateTime.parse(timestamp).year, sequence);
      final sale = <String, Object?>{
        'id': request.id,
        'number': number,
        'occurred_at': timestamp,
        'seller_id': actor.id,
        'seller': actor.name,
        'customer': request.customer,
        'lines': lines,
        'total': total,
        'payment_mode': request.paymentMode.name,
        'tendered': cash ? request.tendered : null,
        'change': cash ? request.tendered! - total : 0,
        'collected': total,
      };
      for (final entry in request.quantities.entries) {
        // Guard again in SQL: concurrent validation cannot make stock negative.
        final changed = await db.customUpdate(
          'UPDATE variants SET stock = stock - ? WHERE id = ? AND active = 1 AND stock >= ?',
          variables: [
            Variable(entry.value),
            Variable(entry.key),
            Variable(entry.value),
          ],
          updates: {db.variants},
        );
        if (changed != 1) {
          throw const BusinessException(
            'Stock modifié : vérifiez à nouveau le panier.',
          );
        }
        await _movement(
          entry.key,
          'SALE',
          -entry.value,
          actor,
          'Vente $number',
          request.id,
          timestamp,
        );
      }
      await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              id: request.id,
              number: number,
              requestHash: hash,
              occurredAt: timestamp,
              snapshot: jsonEncode(sale),
              total: total,
            ),
          );
      await (db.update(db.terminalStates)..where((t) => t.singleton.equals(1)))
          .write(TerminalStatesCompanion(saleSequence: Value(sequence)));
      await appendEvent(request.id, 'sale.completed', actor, timestamp, sale);
      return sale;
    });
  }

  Future<void> _movement(
    String variantId,
    String kind,
    int qty,
    Actor actor,
    String reason,
    String origin,
    String at,
  ) => db
      .into(db.stockMovements)
      .insert(
        StockMovementsCompanion.insert(
          id: uuid.v4(),
          variantId: variantId,
          kind: kind,
          quantity: qty,
          actorId: actor.id,
          reason: reason,
          originId: origin,
          occurredAt: at,
        ),
      );

  /// Appends an outbox event. Callers must already be inside the transaction
  /// that writes the business change, so both commit or roll back together.
  Future<void> appendEvent(
    String id,
    String kind,
    Actor actor,
    String at,
    Map<String, Object?> payload,
  ) async {
    // After a restore, nothing new may be numbered before the terminal has
    // caught up with the operations the server already holds.
    final blocked = await (db.select(
      db.shopSettings,
    )..where((s) => s.key.equals('reconcile_required'))).getSingleOrNull();
    if (blocked != null) {
      throw const BusinessException(
        'Restauration à terminer : Administration → Synchronisation → Réconcilier.',
      );
    }
    final state = await terminal();
    final seq = state.eventSequence + 1;
    final envelope = {
      'id': id,
      'terminal_id': state.terminalId,
      'sequence': seq,
      'version': 1,
      'kind': kind,
      'occurred_at': at,
      'actor_id': actor.id,
      'payload': payload,
    };
    await db
        .into(db.outboxEntries)
        .insert(
          OutboxEntriesCompanion.insert(
            id: id,
            sequence: seq,
            envelope: jsonEncode(envelope),
          ),
        );
    await (db.update(db.terminalStates)..where((t) => t.singleton.equals(1)))
        .write(TerminalStatesCompanion(eventSequence: Value(seq)));
  }

  /// Latest 100 sales. A sale whose payment was corrected carries the
  /// effective payment under `correction`; its snapshot is left unchanged.
  Future<List<Map<String, dynamic>>> history() async {
    final rows =
        await (db.select(db.sales)
              ..orderBy([(s) => OrderingTerm.desc(s.occurredAt)])
              ..limit(100))
            .get();
    final latest = <String, SaleCorrection>{};
    if (rows.isNotEmpty) {
      final corrections =
          await (db.select(db.saleCorrections)
                ..where((c) => c.saleId.isIn([for (final r in rows) r.id]))
                ..orderBy([(c) => OrderingTerm.asc(c.occurredAt)]))
              .get();
      for (final c in corrections) {
        latest[c.saleId] = c;
      }
    }
    final returned = <String, Map<String, Object?>>{};
    for (final row in rows) {
      final summary = await _returnSummary(row.id);
      if (summary != null) returned[row.id] = summary;
    }
    return [
      for (final row in rows)
        {
          ...jsonDecode(row.snapshot) as Map<String, dynamic>,
          if (latest[row.id] case final c?) 'correction': _correction(c),
          'returns': ?returned[row.id],
        },
    ];
  }

  /// Quantities already returned per variant for a sale.
  Future<Map<String, int>> returnedQuantities(String saleId) async {
    final rows = await db
        .customSelect(
          'SELECT l.variant_id, SUM(l.quantity) AS qty FROM sale_return_lines l '
          'JOIN sale_returns r ON r.id = l.return_id WHERE r.sale_id = ? '
          'GROUP BY l.variant_id',
          variables: [Variable(saleId)],
        )
        .get();
    return {
      for (final r in rows) r.read<String>('variant_id'): r.read<int>('qty'),
    };
  }

  /// Refunded total and whether every sold quantity came back.
  Future<Map<String, Object?>?> _returnSummary(String saleId) async {
    final ops = await (db.select(
      db.saleReturns,
    )..where((r) => r.saleId.equals(saleId))).get();
    if (ops.isEmpty) return null;
    final sale = await (db.select(
      db.sales,
    )..where((s) => s.id.equals(saleId))).getSingle();
    final sold = _soldQuantities(
      jsonDecode(sale.snapshot) as Map<String, dynamic>,
    );
    final back = await returnedQuantities(saleId);
    return {
      'refunded': ops.fold<int>(0, (sum, r) => sum + r.refundTotal),
      'complete': sold.entries.every((e) => (back[e.key] ?? 0) >= e.value),
      'cancelled': ops.any((r) => r.kind == 'CANCEL'),
      'quantities': back,
    };
  }

  static Map<String, int> _soldQuantities(Map<String, dynamic> sale) => {
    for (final line in sale['lines'] as List)
      line['variant_id'] as String: line['quantity'] as int,
  };

  /// Return (partial or complete) or cancellation of a recorded sale,
  /// administrator only. Refund = sale price of the returned items, bounded
  /// cumulatively by what was sold; resaleable items go back to stock with a
  /// RETURN movement, damaged ones do not. Idempotent on the operation id.
  Future<Map<String, dynamic>> returnSale(
    Actor actor,
    ReturnRequest request,
  ) async {
    actor.requireAdmin();
    if (!Uuid.isValidUUID(fromString: request.id)) {
      throw const BusinessException('Identifiant de retour invalide.');
    }
    final motive = _motive(request.reason);
    final hash = fingerprint({...request.toJson(), 'actor_id': actor.id});
    return db.transaction(() async {
      final previous = await (db.select(
        db.saleReturns,
      )..where((r) => r.id.equals(request.id))).getSingleOrNull();
      if (previous != null) {
        if (previous.requestHash != hash) {
          throw const BusinessException(
            'Conflit : cet identifiant correspond à un autre retour.',
          );
        }
        return _returnView(previous);
      }
      final sale = await (db.select(
        db.sales,
      )..where((s) => s.id.equals(request.saleId))).getSingleOrNull();
      if (sale == null) throw const BusinessException('Vente introuvable.');
      final snapshot = jsonDecode(sale.snapshot) as Map<String, dynamic>;
      final soldLines = {
        for (final line in snapshot['lines'] as List)
          line['variant_id'] as String: line as Map<String, dynamic>,
      };
      final back = await returnedQuantities(sale.id);
      final wanted = <String, ({int quantity, bool resaleable})>{};
      if (request.cancel) {
        for (final e in soldLines.entries) {
          final left = (e.value['quantity'] as int) - (back[e.key] ?? 0);
          if (left > 0) {
            wanted[e.key] = (
              quantity: left,
              resaleable: request.lines[e.key]?.resaleable ?? true,
            );
          }
        }
        if (wanted.isEmpty) {
          throw const BusinessException(
            'Cette vente est déjà entièrement annulée ou remboursée.',
          );
        }
      } else {
        for (final e in request.lines.entries) {
          if (e.value.quantity == 0) continue;
          final line = soldLines[e.key];
          if (line == null) {
            throw const BusinessException('Article absent de cette vente.');
          }
          final left = (line['quantity'] as int) - (back[e.key] ?? 0);
          if (e.value.quantity < 0 || e.value.quantity > left) {
            throw BusinessException(
              'Retour impossible : ${line['name']} (${line['label']}), $left restant(s) sur cette vente.',
            );
          }
          wanted[e.key] = e.value;
        }
        if (wanted.isEmpty) {
          throw const BusinessException('Indiquez au moins un article rendu.');
        }
      }
      final timestamp = now().toUtc().toIso8601String();
      final lines = [
        for (final e in wanted.entries)
          {
            'variant_id': e.key,
            'name': soldLines[e.key]!['name'],
            'label': soldLines[e.key]!['label'],
            'sku': soldLines[e.key]!['sku'],
            'quantity': e.value.quantity,
            'unit_price': soldLines[e.key]!['unit_price'] as int,
            'line_total':
                (soldLines[e.key]!['unit_price'] as int) * e.value.quantity,
            'resaleable': e.value.resaleable,
          },
      ];
      final refund = lines.fold<int>(
        0,
        (sum, l) => sum + (l['line_total'] as int),
      );
      final kind = request.cancel ? 'CANCEL' : 'RETURN';
      // Header first: return lines reference it.
      await db
          .into(db.saleReturns)
          .insert(
            SaleReturnsCompanion.insert(
              id: request.id,
              saleId: sale.id,
              kind: kind,
              refundTotal: refund,
              refundMode: request.refundMode.name,
              reason: motive,
              requestHash: hash,
              actorId: actor.id,
              actorName: actor.name,
              occurredAt: timestamp,
            ),
          );
      for (final l in lines) {
        final variantId = l['variant_id'] as String;
        final quantity = l['quantity'] as int;
        final resaleable = l['resaleable'] as bool;
        await db
            .into(db.saleReturnLines)
            .insert(
              SaleReturnLinesCompanion.insert(
                returnId: request.id,
                variantId: variantId,
                quantity: quantity,
                unitPrice: l['unit_price'] as int,
                lineTotal: l['line_total'] as int,
                resaleable: resaleable,
              ),
            );
        if (resaleable) {
          await db.customUpdate(
            'UPDATE variants SET stock = stock + ? WHERE id = ?',
            variables: [Variable(quantity), Variable(variantId)],
            updates: {db.variants},
          );
          await _movement(
            variantId,
            'RETURN',
            quantity,
            actor,
            'Retour ${sale.number}',
            request.id,
            timestamp,
          );
        }
      }
      final payload = {
        'id': request.id,
        'sale_id': sale.id,
        'sale_number': sale.number,
        'kind': kind,
        'lines': [
          for (final l in lines)
            {
              'variant_id': l['variant_id'],
              'quantity': l['quantity'],
              'unit_price': l['unit_price'],
              'line_total': l['line_total'],
              'resaleable': l['resaleable'],
            },
        ],
        'refund_total': refund,
        'refund_mode': request.refundMode.name,
        'reason': motive,
      };
      await appendEvent(request.id, 'sale.returned', actor, timestamp, payload);
      return {
        ...payload,
        'lines': lines,
        'occurred_at': timestamp,
        'actor': actor.name,
      };
    });
  }

  Future<Map<String, dynamic>> _returnView(SaleReturn r) async {
    final sale = await (db.select(
      db.sales,
    )..where((s) => s.id.equals(r.saleId))).getSingle();
    final soldLines = {
      for (final line in (jsonDecode(sale.snapshot) as Map)['lines'] as List)
        line['variant_id'] as String: line as Map,
    };
    final rows = await (db.select(
      db.saleReturnLines,
    )..where((l) => l.returnId.equals(r.id))).get();
    return {
      'id': r.id,
      'sale_id': r.saleId,
      'sale_number': sale.number,
      'kind': r.kind,
      'lines': [
        for (final l in rows)
          {
            'variant_id': l.variantId,
            'name': soldLines[l.variantId]?['name'],
            'label': soldLines[l.variantId]?['label'],
            'sku': soldLines[l.variantId]?['sku'],
            'quantity': l.quantity,
            'unit_price': l.unitPrice,
            'line_total': l.lineTotal,
            'resaleable': l.resaleable,
          },
      ],
      'refund_total': r.refundTotal,
      'refund_mode': r.refundMode,
      'reason': r.reason,
      'occurred_at': r.occurredAt,
      'actor': r.actorName,
    };
  }

  static Map<String, Object?> _correction(SaleCorrection c) => {
    'id': c.id,
    'payment_mode': c.paymentMode,
    'tendered': c.tendered,
    'change': c.changeGiven,
    'reason': c.reason,
    'corrected_by': c.actorName,
    'corrected_at': c.occurredAt,
  };

  /// Administrator correction of the declared payment (mode or tendered
  /// amount). Total, lines and stock are untouched; cancellations and returns
  /// are separate operations.
  Future<Map<String, Object?>> correctPayment(
    Actor actor,
    String saleId, {
    required PaymentMode mode,
    int? tendered,
    required String reason,
  }) async {
    actor.requireAdmin();
    final motive = reason.trim();
    if (motive.length < 3 || motive.length > 200) {
      throw const BusinessException('Indiquez un motif de 3 à 200 caractères.');
    }
    return db.transaction(() async {
      final sale = await (db.select(
        db.sales,
      )..where((s) => s.id.equals(saleId))).getSingleOrNull();
      if (sale == null) throw const BusinessException('Vente introuvable.');
      final snapshot = jsonDecode(sale.snapshot) as Map<String, dynamic>;
      final previous =
          await (db.select(db.saleCorrections)
                ..where((c) => c.saleId.equals(saleId))
                ..orderBy([(c) => OrderingTerm.desc(c.occurredAt)])
                ..limit(1))
              .getSingleOrNull();
      final current = previous == null ? snapshot : _correction(previous);
      final total = sale.total;
      final cash = mode == PaymentMode.cash;
      if (cash &&
          (tendered == null || tendered < total || tendered > maxMoney)) {
        throw const BusinessException('La somme remise doit couvrir le total.');
      }
      if (!cash && tendered != null) {
        throw const BusinessException('Somme remise réservée aux espèces.');
      }
      if (current['payment_mode'] == mode.name &&
          current['tendered'] == tendered) {
        throw const BusinessException('Aucune modification à enregistrer.');
      }
      final id = uuid.v4();
      final timestamp = now().toUtc().toIso8601String();
      final change = cash ? tendered! - total : 0;
      await db
          .into(db.saleCorrections)
          .insert(
            SaleCorrectionsCompanion.insert(
              id: id,
              saleId: saleId,
              paymentMode: mode.name,
              tendered: Value(tendered),
              changeGiven: change,
              reason: motive,
              actorId: actor.id,
              actorName: actor.name,
              occurredAt: timestamp,
            ),
          );
      await appendEvent(id, 'sale.payment_corrected', actor, timestamp, {
        'sale_id': saleId,
        'sale_number': sale.number,
        'payment_mode': mode.name,
        'tendered': tendered,
        'change': change,
        'reason': motive,
      });
      return {
        'payment_mode': mode.name,
        'tendered': tendered,
        'change': change,
      };
    });
  }

  /// First blocked operation (error code, attempts, next try) and totals.
  Future<SyncStatus> syncStatus() async {
    final blocked =
        await (db.select(db.outboxEntries)
              ..where((e) => e.status.equals('synced').not())
              ..orderBy([(e) => OrderingTerm.asc(e.sequence)])
              ..limit(1))
            .getSingleOrNull();
    final terminal = await this.terminal();
    return SyncStatus(
      pending: await pendingCount(),
      lastSyncAt: terminal.lastSyncAt,
      errorCode: blocked?.errorCode,
      attempts: blocked?.attempts ?? 0,
      nextAttemptAt: blocked?.nextAttemptAt,
    );
  }

  Future<int> pendingCount() async {
    final count = db.outboxEntries.id.count();
    final query = db.selectOnly(db.outboxEntries)
      ..addColumns([count])
      ..where(db.outboxEntries.status.equals('synced').not());
    return (await query.getSingle()).read(count) ?? 0;
  }
}
