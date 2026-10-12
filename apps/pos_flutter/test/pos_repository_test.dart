import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mono_pos/data/database.dart';
import 'package:mono_pos/data/pos_repository.dart';
import 'package:mono_pos/domain/models.dart';
import 'package:mono_pos/printing/printer_service.dart';
import 'package:uuid/uuid.dart';

void main() {
  const admin = Actor('admin-recette', 'Administrateur recette', Role.admin);
  const seller = Actor('seller-recette', 'Vendeur recette', Role.seller);
  late PosDatabase db;
  late PosRepository repo;
  Future<String> item({String sku = 'R42', int stock = 5, int price = 12500}) =>
      repo.createItem(
        actor: admin,
        category: 'Chaussures',
        name: 'Rangers noirs',
        sku: sku,
        label: 'Pointure 42',
        price: price,
        stock: stock,
      );
  SaleRequest request(
    String id, {
    int quantity = 2,
    int tendered = 30000,
    String? operation,
  }) => SaleRequest(
    id: operation ?? const Uuid().v4(),
    quantities: {id: quantity},
    paymentMode: PaymentMode.cash,
    tendered: tendered,
  );

  setUp(() async {
    db = PosDatabase(NativeDatabase.memory());
    repo = PosRepository(db, now: () => DateTime.utc(2026, 10, 6, 12));
    await repo.initialize();
  });
  tearDown(() => db.close());

  test('montants entiers, monnaie et ticket duplicata', () async {
    final id = await item();
    final sale = await repo.checkout(seller, request(id));
    expect(sale['total'], 25000);
    expect(sale['tendered'], 30000);
    expect(sale['change'], 5000);
    expect(sale['collected'], 25000);
    expect((await repo.catalog()).single.stock, 3);
    expect(await repo.pendingCount(), 2);
    final movements = await db.select(db.stockMovements).get();
    expect(movements.map((m) => m.quantity), [5, -2]);
    expect(sale['number'], 'FACT-2026-00001');
    final receipt = buildReceipt(sale, duplicate: true);
    final ticket = receipt.toPlainText();
    expect(ticket, contains('DUPLICATA'));
    expect(ticket, contains('N° FACTURE : FACT-2026-00001'));
    expect(ticket, contains('TOTAL FACTURE'));
    expect(ticket, contains('25 000 F CFA'));
    expect(
      await SimulatedPrinter().printReceipt(receipt),
      PrintOutcome.simulated,
    );
    expect((await repo.history()).length, 1);
  });

  test(
    'échec de paiement et stock insuffisant ne laissent aucune vente',
    () async {
      final id = await item(stock: 1);
      await expectLater(
        repo.checkout(seller, request(id)),
        throwsA(isA<BusinessException>()),
      );
      await expectLater(
        repo.checkout(seller, request(id, quantity: 1, tendered: 1)),
        throwsA(isA<BusinessException>()),
      );
      expect((await repo.catalog()).single.stock, 1);
      expect(await repo.history(), isEmpty);
      expect(await repo.pendingCount(), 1);
      expect((await repo.terminal()).saleSequence, 0);
    },
  );

  test(
    'rollback complet si écriture outbox échoue après les mouvements',
    () async {
      final id = await item();
      await db.customStatement(
        "CREATE TRIGGER fail_event BEFORE INSERT ON outbox_entries BEGIN SELECT RAISE(ABORT, 'injected failure'); END",
      );
      await expectLater(repo.checkout(seller, request(id)), throwsA(anything));
      expect((await repo.catalog()).single.stock, 5);
      expect(await repo.history(), isEmpty);
      expect((await db.select(db.stockMovements).get()).length, 1);
      expect((await repo.terminal()).saleSequence, 0);
      expect((await repo.terminal()).eventSequence, 1);
    },
  );

  test('double validation concurrente applique une seule vente', () async {
    final id = await item();
    final r = request(id);
    final sales = await Future.wait([
      repo.checkout(seller, r),
      repo.checkout(seller, r),
    ]);
    expect(sales[0]['number'], sales[1]['number']);
    expect((await repo.catalog()).single.stock, 3);
    expect(await repo.pendingCount(), 2);
    expect((await repo.history()).length, 1);
    await expectLater(
      repo.checkout(seller, request(id, quantity: 1, operation: r.id)),
      throwsA(isA<BusinessException>()),
    );
  });

  test('deux ventes concurrentes ne rendent pas le stock négatif', () async {
    final id = await item(stock: 1);
    final outcomes = await Future.wait(
      List.generate(2, (_) async {
        try {
          await repo.checkout(seller, request(id, quantity: 1));
          return true;
        } on BusinessException {
          return false;
        }
      }),
    );
    expect(outcomes.where((x) => x).length, 1);
    expect((await repo.catalog()).single.stock, 0);
  });

  test('prix historique immuable et permission vendeur', () async {
    final id = await item();
    await repo.checkout(seller, request(id));
    await expectLater(
      repo.changePrice(seller, id, 10),
      throwsA(isA<BusinessException>()),
    );
    await repo.changePrice(admin, id, 20000);
    expect((await repo.history()).single['total'], 25000);
    expect((await repo.catalog()).single.price, 20000);
    expect(await repo.pendingCount(), 3);
  });

  test('contraintes SQL uniques et prix/stock négatifs', () async {
    final id = await item();
    await expectLater(item(), throwsA(isA<BusinessException>()));
    await expectLater(
      db.customStatement('UPDATE variants SET stock = -1 WHERE id = ?', [id]),
      throwsA(anything),
    );
    await expectLater(
      db.customStatement('UPDATE variants SET price = -1 WHERE id = ?', [id]),
      throwsA(anything),
    );
  });

  test(
    'identité, numérotation, historique et outbox survivent à la réouverture',
    () async {
      final dir = await Directory.systemTemp.createTemp('mono-persistence-');
      final file = File('${dir.path}/pos.sqlite');
      final disk = PosDatabase(NativeDatabase(file));
      final first = PosRepository(disk);
      await first.initialize();
      final terminal = await first.terminal();
      final variant = await first.createItem(
        actor: admin,
        category: 'Test',
        name: 'Test',
        sku: 'TEST',
        label: 'Test',
        price: 10,
        stock: 3,
      );
      final sale = await first.checkout(
        seller,
        request(variant, tendered: 100),
      );
      await disk.close();
      final reopened = PosDatabase(NativeDatabase(file));
      final second = PosRepository(reopened);
      await second.initialize();
      expect((await second.terminal()).terminalId, terminal.terminalId);
      expect((await second.terminal()).saleSequence, 1);
      expect((await second.catalog()).single.stock, 1);
      expect((await second.history()).single['number'], sale['number']);
      expect(await second.pendingCount(), 2);
      final check = await reopened
          .customSelect('PRAGMA integrity_check')
          .getSingle();
      expect(check.data.values.single, 'ok');
      await reopened.close();
      await dir.delete(recursive: true);
    },
  );

  test('contrat JSON sérialisable et bornes monétaires', () async {
    expect(moneyInput('12500'), 12500);
    for (final input in ['12.50', '-10', 'NaN', '1e4', '1000000000001']) {
      expect(() => moneyInput(input), throwsA(isA<BusinessException>()));
    }
    final id = await item();
    await repo.checkout(seller, request(id));
    final events = await db.select(db.outboxEntries).get();
    final event = jsonDecode(events.last.envelope) as Map;
    expect(event['version'], 1);
    expect(event['sequence'], 2);
    expect(event['kind'], 'sale.completed');
  });

  test('aide à l’encaissement : montants rapides et confirmation', () {
    expect(quickTenders(55000), [55000, 60000, 100000]);
    expect(quickTenders(12500), [12500, 15000, 20000, 50000]);
    expect(quickTenders(50000), [50000]);
    expect(needsChangeConfirmation(55000, 60000), isFalse);
    expect(needsChangeConfirmation(55000, 55000), isFalse);
    // 600 000 typed instead of 60 000.
    expect(needsChangeConfirmation(55000, 600000), isTrue);
    expect(needsChangeConfirmation(12500, 25000), isTrue);
    expect(needsChangeConfirmation(200000, 260000), isTrue);
    expect(needsChangeConfirmation(200000, 240000), isFalse);
  });

  test(
    'correction de paiement : admin, motif, vente et stock inchangés',
    () async {
      final id = await item();
      final sale = await repo.checkout(seller, request(id, tendered: 50000));
      expect(sale['change'], 25000);
      Future<void> refused(Future<void> Function() call) =>
          expectLater(call(), throwsA(isA<BusinessException>()));
      await refused(
        () => repo.correctPayment(
          seller,
          sale['id'] as String,
          mode: PaymentMode.cash,
          tendered: 30000,
          reason: 'Erreur de saisie',
        ),
      );
      await refused(
        () => repo.correctPayment(
          admin,
          sale['id'] as String,
          mode: PaymentMode.cash,
          tendered: 30000,
          reason: '',
        ),
      );
      await refused(
        () => repo.correctPayment(
          admin,
          sale['id'] as String,
          mode: PaymentMode.cash,
          tendered: 20000,
          reason: 'Somme insuffisante',
        ),
      );
      await refused(
        () => repo.correctPayment(
          admin,
          sale['id'] as String,
          mode: PaymentMode.cash,
          tendered: 50000,
          reason: 'Identique',
        ),
      );
      await repo.correctPayment(
        admin,
        sale['id'] as String,
        mode: PaymentMode.cash,
        tendered: 30000,
        reason: 'Le client a remis 30 000',
      );
      var history = (await repo.history()).single;
      expect(history['tendered'], 50000, reason: 'snapshot immuable');
      expect(history['correction']['tendered'], 30000);
      expect(history['correction']['change'], 5000);
      await repo.correctPayment(
        admin,
        sale['id'] as String,
        mode: PaymentMode.mobileMoney,
        reason: 'Payé en Mobile Money',
      );
      history = (await repo.history()).single;
      expect(history['correction']['payment_mode'], 'mobileMoney');
      expect(history['correction']['tendered'], isNull);
      expect(history['total'], 25000);
      expect((await repo.catalog()).single.stock, 3);
      final ticket = buildReceipt(history, duplicate: true).toPlainText();
      expect(ticket, contains('MOBILE MONEY'));
      expect(ticket, contains('Paiement corrigé le'));
      expect(ticket, isNot(contains('SOMME REMISE')));
      final kinds = [
        for (final e in await db.select(db.outboxEntries).get())
          (jsonDecode(e.envelope) as Map)['kind'],
      ];
      expect(kinds.where((k) => k == 'sale.payment_corrected'), hasLength(2));
      expect(await db.select(db.saleCorrections).get(), hasLength(2));
    },
  );

  test('grille de pointures : un article, 9 variantes, atomique', () async {
    const grid = SizeGrid.shoes;
    final drafts = [
      for (final size in grid.sizes)
        VariantDraft(
          sku: grid.sku('ran-noir', size),
          label: grid.label(size, 'Noir'),
          price: size == '46' ? 17000 : 15000,
          stock: size == '38' ? 0 : 2,
        ),
    ];
    Future<void> refused(List<VariantDraft> variants, {Actor actor = admin}) =>
        expectLater(
          repo.createProduct(
            actor: actor,
            category: 'Chaussures',
            name: 'Rangers',
            variants: variants,
          ),
          throwsA(isA<BusinessException>()),
        );
    await refused(drafts, actor: seller);
    await refused([drafts.first, drafts.first]);
    await refused([]);
    final ids = await repo.createProduct(
      actor: admin,
      category: 'Chaussures',
      name: 'Rangers',
      variants: drafts,
    );
    expect(ids, hasLength(9));
    final catalog = await repo.catalog();
    expect(catalog.map((i) => i.productId).toSet(), hasLength(1));
    expect(
      catalog.map((i) => i.sku),
      containsAll(['RAN-NOIR-38', 'RAN-NOIR-46']),
    );
    expect(
      catalog.firstWhere((i) => i.sku == 'RAN-NOIR-42').label,
      'Noir · Pointure 42',
    );
    expect(catalog.firstWhere((i) => i.sku == 'RAN-NOIR-46').price, 17000);
    // No INITIAL movement for a size created at zero stock.
    expect(await db.select(db.stockMovements).get(), hasLength(8));
    final events = [
      for (final e in await db.select(db.outboxEntries).get())
        jsonDecode(e.envelope) as Map,
    ];
    expect(events, hasLength(9));
    expect(events.map((e) => e['payload']['product_id']).toSet(), hasLength(1));
    // A clash with an existing reference creates nothing at all.
    await refused([
      VariantDraft(sku: 'NEW-1', label: 'Taille M', price: 1, stock: 1),
      VariantDraft(sku: 'RAN-NOIR-42', label: 'Taille L', price: 1, stock: 1),
    ]);
    expect(await repo.catalog(), hasLength(9));
    expect(await db.select(db.outboxEntries).get(), hasLength(9));
    expect(SizeGrid.clothing.sizes, ['M', 'L', 'XL', 'XXL', 'XXXL']);
    expect(SizeGrid.clothing.label('XL', ''), 'Taille XL');
  });

  test(
    'changement de prix groupé : admin, tout ou rien, historique intact',
    () async {
      final ids = await repo.createProduct(
        actor: admin,
        category: 'Treillis',
        name: 'Treillis MO',
        variants: [
          for (final size in ['M', 'L', 'XL'])
            VariantDraft(
              sku: SizeGrid.clothing.sku('TRE', size),
              label: SizeGrid.clothing.label(size, ''),
              price: 20000,
              stock: 3,
            ),
        ],
      );
      final sale = await repo.checkout(
        seller,
        SaleRequest(
          id: const Uuid().v4(),
          quantities: {ids[0]: 1},
          paymentMode: PaymentMode.mobileMoney,
        ),
      );
      final before = (await db.select(db.outboxEntries).get()).length;
      await expectLater(
        repo.changePrices(seller, {ids[0]: 1}),
        throwsA(isA<BusinessException>()),
      );
      await expectLater(
        repo.changePrices(admin, {ids[0]: 25000, 'inconnue': 1}),
        throwsA(isA<BusinessException>()),
      );
      expect((await repo.catalog()).every((i) => i.price == 20000), isTrue);
      final changed = await repo.changePrices(admin, {
        ids[0]: 22000,
        ids[1]: 20000, // unchanged: no event
        ids[2]: 24000,
      });
      expect(changed, 2);
      expect((await db.select(db.outboxEntries).get()).length, before + 2);
      final prices = {for (final i in await repo.catalog()) i.sku: i.price};
      expect(prices, {'TRE-M': 22000, 'TRE-L': 20000, 'TRE-XL': 24000});
      final past = (await repo.history()).single;
      expect(past['id'], sale['id']);
      expect((past['lines'] as List).single['unit_price'], 20000);
      expect(past['total'], 20000);
    },
  );

  test(
    'couleurs × tailles : seules les combinaisons réelles, ajout ultérieur',
    () async {
      expect(colorCode('Vert olive'), 'VERT-OLIVE');
      expect(colorCode(' Kaki éclair '), 'KAKI-ECLAIR');
      expect(normalizeColor('  noir   mat '), 'Noir mat');
      final drafts = matrixVariants(
        grid: SizeGrid.shoes,
        reference: 'ran',
        colors: ['Noir', 'Marron'],
        price: 15000,
        // Reality: 3 black sizes (one sold out), only one brown size.
        stock: {
          ('Noir', '41'): 2,
          ('Noir', '42'): 5,
          ('Noir', '43'): 0,
          ('Marron', '42'): 1,
        },
      );
      expect(drafts.map((d) => d.sku), [
        'RAN-NOIR-41',
        'RAN-NOIR-42',
        'RAN-NOIR-43',
        'RAN-MARRON-42',
      ]);
      expect(drafts.last.label, 'Marron · Pointure 42');
      await repo.createProduct(
        actor: admin,
        category: 'Chaussures',
        name: 'Rangers',
        variants: drafts,
      );
      var catalog = await repo.catalog();
      expect(catalog, hasLength(4));
      final brown = catalog.firstWhere((i) => i.sku == 'RAN-MARRON-42');
      expect((brown.color, brown.size, brown.stock), ('Marron', '42', 1));
      // Only 3 INITIAL movements: the sold-out size exists without stock.
      expect(await db.select(db.stockMovements).get(), hasLength(3));
      final created = [
        for (final e in await db.select(db.outboxEntries).get())
          (jsonDecode(e.envelope) as Map)['payload'] as Map,
      ];
      expect(created.last['color'], 'Marron');
      expect(created.last['size'], '42');

      final productId = brown.productId;
      // A new colour and a new brown size arrive later.
      await repo.addVariants(
        admin,
        productId,
        matrixVariants(
          grid: SizeGrid.shoes,
          reference: 'RAN',
          colors: ['Marron', 'Sable'],
          price: 16000,
          stock: {('Marron', '44'): 3, ('Sable', '42'): 2},
        ),
      );
      catalog = await repo.catalog();
      expect(catalog, hasLength(6));
      expect(catalog.map((i) => i.productId).toSet(), {productId});
      expect(catalog.firstWhere((i) => i.sku == 'RAN-SABLE-42').price, 16000);
      // An existing combination or a seller is refused, nothing is created.
      final again = matrixVariants(
        grid: SizeGrid.shoes,
        reference: 'RAN',
        colors: ['Sable', 'Noir'],
        price: 1,
        stock: {('Sable', '43'): 1, ('Noir', '42'): 1},
      );
      await expectLater(
        repo.addVariants(admin, productId, again),
        throwsA(isA<BusinessException>()),
      );
      await expectLater(
        repo.addVariants(seller, productId, again.take(1).toList()),
        throwsA(isA<BusinessException>()),
      );
      expect(await repo.catalog(), hasLength(6));
    },
  );

  test(
    'mouvements de stock : réception, perte, correction, inventaire, statut',
    () async {
      final id = await item(); // stock 5
      Future<void> refused(Future<void> Function() call) =>
          expectLater(call(), throwsA(isA<BusinessException>()));
      final eventsBefore = (await db.select(db.outboxEntries).get()).length;
      await refused(
        () => repo.moveStock(
          seller,
          id,
          kind: StockKind.reception,
          quantity: 2,
          reason: 'Livraison',
        ),
      );
      await refused(
        () => repo.moveStock(
          admin,
          id,
          kind: StockKind.loss,
          quantity: 2,
          reason: '',
        ),
      );
      await refused(
        () => repo.moveStock(
          admin,
          id,
          kind: StockKind.loss,
          quantity: -2,
          reason: 'Vol',
        ),
      );
      // Negative stock refused: nothing written.
      await refused(
        () => repo.moveStock(
          admin,
          id,
          kind: StockKind.loss,
          quantity: 6,
          reason: 'Casse',
        ),
      );
      expect((await db.select(db.outboxEntries).get()).length, eventsBefore);
      await repo.moveStock(
        admin,
        id,
        kind: StockKind.reception,
        quantity: 4,
        reason: 'Livraison',
      ); // 9
      await repo.moveStock(
        admin,
        id,
        kind: StockKind.loss,
        quantity: 2,
        reason: 'Casse',
      ); // 7
      await repo.moveStock(
        admin,
        id,
        kind: StockKind.adjustment,
        quantity: -1,
        reason: 'Erreur',
      ); // 6
      expect((await repo.catalog()).single.stock, 6);
      // Inventory: counted 4 → correction −2 with the count; same count → nothing.
      expect(await repo.countInventory(admin, {id: 4}), 1);
      expect(await repo.countInventory(admin, {id: 4}), 0);
      await refused(() => repo.countInventory(admin, {id: -1}));
      expect((await repo.catalog()).single.stock, 4);
      final history = await repo.movements(id);
      expect(history.map((m) => (m.kind, m.quantity)).toList(), [
        ('ADJUSTMENT', -2),
        ('ADJUSTMENT', -1),
        ('LOSS', -2),
        ('RECEPTION', 4),
        ('INITIAL', 5),
      ]);
      expect(history.first.counted, 4);
      expect(history.first.reason, 'Inventaire');
      final events = [
        for (final e in await db.select(db.outboxEntries).get())
          jsonDecode(e.envelope) as Map,
      ];
      final moved = events.where((e) => e['kind'] == 'stock.moved').toList();
      expect(moved, hasLength(4));
      expect(moved.last['payload'], {
        'variant_id': id,
        'kind': 'ADJUSTMENT',
        'quantity': -2,
        'reason': 'Inventaire',
        'counted': 4,
      });
      // Threshold and deactivation.
      await repo.updateVariant(admin, id, threshold: 4);
      expect((await repo.catalog()).single.lowStock, isTrue);
      await refused(() => repo.updateVariant(seller, id, active: false));
      await repo.updateVariant(admin, id, active: false);
      expect(await repo.catalog(), isEmpty);
      final all = await repo.inventory();
      expect((all.single.active, all.single.threshold), (false, 4));
      await refused(
        () => repo.checkout(seller, request(id, quantity: 1, tendered: 20000)),
      );
      await repo.updateVariant(admin, id, active: true);
      expect(await repo.catalog(), hasLength(1));
    },
  );

  test(
    'retours et annulation : bornes, revendable/endommagé, idempotence',
    () async {
      final a = await item(); // R42, 12 500, stock 5
      final b = await item(sku: 'R43', price: 10000); // stock 5
      final sale = await repo.checkout(
        seller,
        SaleRequest(
          id: const Uuid().v4(),
          quantities: {a: 2, b: 1},
          paymentMode: PaymentMode.cash,
          tendered: 40000,
        ),
      ); // total 35 000 ; stocks 3 / 4
      final saleId = sale['id'] as String;
      ReturnRequest ret(
        String id,
        Map<String, ({int quantity, bool resaleable})> lines, {
        bool cancel = false,
      }) => ReturnRequest(
        id: id,
        saleId: saleId,
        lines: lines,
        refundMode: PaymentMode.cash,
        reason: 'Taille inadaptée',
        cancel: cancel,
      );
      Future<void> refused(Future<void> Function() call) =>
          expectLater(call(), throwsA(isA<BusinessException>()));
      final first = const Uuid().v4();
      await refused(
        () => repo.returnSale(
          seller,
          ret(first, {a: (quantity: 1, resaleable: true)}),
        ),
      );
      await refused(
        () => repo.returnSale(
          admin,
          ret(first, {a: (quantity: 3, resaleable: true)}),
        ),
      );
      final r1 = await repo.returnSale(
        admin,
        ret(first, {a: (quantity: 1, resaleable: true)}),
      );
      expect(r1['refund_total'], 12500);
      // Same id and content: same result, no second refund or stock change.
      final again = await repo.returnSale(
        admin,
        ret(first, {a: (quantity: 1, resaleable: true)}),
      );
      expect(again['refund_total'], 12500);
      await refused(
        () => repo.returnSale(
          admin,
          ret(first, {a: (quantity: 1, resaleable: false)}),
        ),
      );
      // Damaged item: refunded but not back in stock.
      await repo.returnSale(
        admin,
        ret(const Uuid().v4(), {b: (quantity: 1, resaleable: false)}),
      );
      var stock = {for (final i in await repo.catalog()) i.id: i.stock};
      expect((stock[a], stock[b]), (4, 4));
      await refused(
        () => repo.returnSale(
          admin,
          ret(const Uuid().v4(), {b: (quantity: 1, resaleable: true)}),
        ),
      );
      var history = (await repo.history()).single;
      expect(history['returns']['refunded'], 22500);
      expect(history['returns']['complete'], isFalse);
      expect(
        buildReceipt(history, duplicate: true).toPlainText(),
        contains('RETOUR PARTIEL'),
      );
      // Cancellation refunds what is left (1 × A), then nothing remains.
      final cancel = await repo.returnSale(
        admin,
        ret(const Uuid().v4(), {}, cancel: true),
      );
      expect(cancel['refund_total'], 12500);
      expect(cancel['kind'], 'CANCEL');
      await refused(
        () => repo.returnSale(admin, ret(const Uuid().v4(), {}, cancel: true)),
      );
      stock = {for (final i in await repo.catalog()) i.id: i.stock};
      expect(stock[a], 5);
      history = (await repo.history()).single;
      expect(history['returns']['refunded'], 35000);
      expect(
        (history['returns']['complete'], history['returns']['cancelled']),
        (true, true),
      );
      expect(history['total'], 35000, reason: 'la vente n’est pas modifiée');
      final ticket = buildReturnReceipt(cancel).toPlainText();
      expect(ticket, contains('ANNULATION'));
      expect(ticket, contains('TOTAL REMBOURSÉ'));
      expect(ticket, contains('12 500 F CFA'));
      expect(
        buildReceipt(history, duplicate: true).toPlainText(),
        contains('VENTE ANNULÉE'),
      );
      final returnsEvents = [
        for (final e in await db.select(db.outboxEntries).get())
          if ((jsonDecode(e.envelope) as Map)['kind'] == 'sale.returned')
            (jsonDecode(e.envelope) as Map)['payload'] as Map,
      ];
      expect(returnsEvents.map((p) => p['refund_total']), [
        12500,
        10000,
        12500,
      ]);
      expect((returnsEvents[1]['lines'] as List).single['resaleable'], isFalse);
      final movements = await repo.movements(a);
      expect(
        movements.where((m) => m.kind == 'RETURN').map((m) => m.quantity),
        [1, 1],
      );
    },
  );
}
