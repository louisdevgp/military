import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mono_pos/data/database.dart';
import 'package:mono_pos/data/finance_repository.dart';
import 'package:mono_pos/data/pos_repository.dart';
import 'package:mono_pos/domain/finance.dart';
import 'package:mono_pos/domain/models.dart';
import 'package:uuid/uuid.dart';

void main() {
  const admin = Actor('a', 'Admin', Role.admin);
  const seller = Actor('s', 'Vendeur', Role.seller);
  late PosDatabase db;
  late PosRepository pos;
  late FinanceRepository finance;
  var clock = DateTime.utc(2026, 10, 12, 9);

  setUp(() async {
    clock = DateTime.utc(2026, 10, 12, 9);
    db = PosDatabase(NativeDatabase.memory());
    pos = PosRepository(db, now: () => clock);
    await pos.initialize();
    finance = FinanceRepository(pos);
  });
  tearDown(() => db.close());

  Future<void> refused(Future<void> Function() call) =>
      expectLater(call(), throwsA(isA<BusinessException>()));

  test('périodes métier Abidjan : jour, semaine ISO, mois, période libre', () {
    final t = DateTime.utc(2026, 10, 14, 23, 59); // mercredi
    expect(ReportPeriod.day(t).start, DateTime.utc(2026, 10, 14));
    expect(ReportPeriod.day(t).end, DateTime.utc(2026, 10, 15));
    expect(ReportPeriod.week(t).start, DateTime.utc(2026, 10, 12));
    expect(ReportPeriod.week(t).end, DateTime.utc(2026, 10, 19));
    expect(ReportPeriod.month(t).end, DateTime.utc(2026, 11));
    expect(
      ReportPeriod.month(DateTime.utc(2026, 12, 3)).end,
      DateTime.utc(2027),
    );
    expect(ReportPeriod.year(t).start, DateTime.utc(2026));
    final custom = ReportPeriod.custom(
      DateTime.utc(2026, 10, 1),
      DateTime.utc(2026, 10, 3),
    );
    expect(
      custom.end,
      DateTime.utc(2026, 10, 4),
      reason: 'dernier jour inclus',
    );
  });

  test('dépenses, caisse attendue, clôtures successives et rapport', () async {
    final rangers = await pos.createItem(
      actor: admin,
      category: 'Chaussures',
      name: 'Rangers',
      sku: 'RAN-42',
      label: '42',
      price: 12500,
      stock: 5,
    );
    final beret = await pos.createItem(
      actor: admin,
      category: 'Coiffes',
      name: 'Béret',
      sku: 'BER-58',
      label: '58',
      price: 10000,
      stock: 2,
    );
    await pos.updateVariant(admin, beret, threshold: 1);
    final cashSale = await pos.checkout(
      seller,
      SaleRequest(
        id: const Uuid().v4(),
        quantities: {rangers: 2},
        paymentMode: PaymentMode.cash,
        tendered: 30000,
      ),
    ); // 25 000 espèces
    final mobile = await pos.checkout(
      seller,
      SaleRequest(
        id: const Uuid().v4(),
        quantities: {beret: 1},
        paymentMode: PaymentMode.cash,
        tendered: 10000,
      ),
    );
    // Declared cash, corrected to Mobile Money: no longer in the drawer.
    await pos.correctPayment(
      admin,
      mobile['id'] as String,
      mode: PaymentMode.mobileMoney,
      reason: 'Payé par Mobile Money',
    );
    await pos.returnSale(
      admin,
      ReturnRequest(
        id: const Uuid().v4(),
        saleId: cashSale['id'] as String,
        lines: {rangers: (quantity: 1, resaleable: true)},
        refundMode: PaymentMode.cash,
        reason: 'Taille',
      ),
    );

    await refused(
      () => finance.recordExpense(
        seller,
        kind: ExpenseKind.charge,
        category: 'Transport',
        amount: 2000,
        mode: PaymentMode.cash,
        reason: 'Livraison',
      ),
    );
    await refused(
      () => finance.recordExpense(
        admin,
        kind: ExpenseKind.charge,
        category: 'Transport',
        amount: 0,
        mode: PaymentMode.cash,
        reason: 'Livraison',
      ),
    );
    await refused(
      () => finance.recordExpense(
        admin,
        kind: ExpenseKind.charge,
        category: 'Transport',
        amount: 2000,
        mode: PaymentMode.cash,
        reason: 'Livraison',
        occurredAt: clock.add(const Duration(days: 1)),
      ),
    );
    await finance.recordExpense(
      admin,
      kind: ExpenseKind.charge,
      category: 'Transport',
      amount: 2000,
      mode: PaymentMode.cash,
      reason: 'Livraison',
    );
    await finance.recordExpense(
      admin,
      kind: ExpenseKind.stock,
      category: 'Fournisseur',
      amount: 50000,
      mode: PaymentMode.transfer,
      reason: 'Commande rangers',
    );
    await finance.recordExpense(
      admin,
      kind: ExpenseKind.treasury,
      category: 'Dépôt banque',
      amount: 10000,
      mode: PaymentMode.cash,
      reason: 'Dépôt',
    );
    final mistake = await finance.recordExpense(
      admin,
      kind: ExpenseKind.charge,
      category: 'Transport',
      amount: 999,
      mode: PaymentMode.cash,
      reason: 'Erreur de saisie',
    );
    await finance.cancelExpense(admin, mistake, 'Doublon');
    await refused(() => finance.cancelExpense(admin, mistake, 'Encore'));

    var position = await finance.cashPosition();
    expect(position.firstClosing, isTrue);
    expect(
      (position.cashSales, position.cashRefunds, position.cashExpenses),
      (25000, 12500, 12000),
    );
    expect(position.expected, 500);
    // Gap needs a comment; the kept float cannot exceed the counted cash.
    await refused(
      () => finance.closeCash(
        admin,
        counted: 20000,
        keptFloat: 15000,
        comment: '',
        openingFloat: 20000,
      ),
    );
    await refused(
      () => finance.closeCash(
        admin,
        counted: 20000,
        keptFloat: 25000,
        comment: 'ok',
        openingFloat: 20000,
      ),
    );
    final closing = await finance.closeCash(
      admin,
      counted: 20000,
      keptFloat: 15000,
      comment: 'Pièce de 500 manquante',
      openingFloat: 20000,
    );
    expect((closing['expected'], closing['difference']), (20500, -500));

    clock = clock.add(const Duration(hours: 2));
    position = await finance.cashPosition();
    expect(position.firstClosing, isFalse);
    expect(
      (position.openingFloat, position.cashSales, position.expected),
      (15000, 0, 15000),
    );

    final report = await finance.report(ReportPeriod.day(clock));
    expect(
      (report.saleCount, report.gross, report.refunds, report.net),
      (2, 35000, 12500, 22500),
    );
    expect(
      (report.quantity, report.returnedQuantity, report.netQuantity),
      (3, 1, 2),
    );
    expect(report.payments, {'cash': 25000, 'mobileMoney': 10000});
    expect(report.refundsByMode, {'cash': 12500});
    expect(report.byCategory, {'Chaussures': 25000, 'Coiffes': 10000});
    expect(report.byVariant.first.label, 'Rangers · 42');
    expect(report.expensesByKind, {
      ExpenseKind.charge: 2000,
      ExpenseKind.stock: 50000,
      ExpenseKind.treasury: 10000,
    });
    expect(report.alerts.single, contains('Béret'));
    expect((report.closings, report.closingGap), (1, -500));
    final previousDay = await finance.report(
      ReportPeriod.day(clock.subtract(const Duration(days: 1))),
    );
    expect((previousDay.saleCount, previousDay.gross), (0, 0));

    final kinds = [
      for (final e in await db.select(db.outboxEntries).get())
        (jsonDecode(e.envelope) as Map)['kind'],
    ];
    expect(kinds.where((k) => k == 'expense.recorded'), hasLength(4));
    expect(kinds.where((k) => k == 'expense.cancelled'), hasLength(1));
    expect(kinds.where((k) => k == 'cash.closed'), hasLength(1));
  });
}
