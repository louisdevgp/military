import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mono_pos/application/pos_controller.dart';
import 'package:mono_pos/application/session_controller.dart';
import 'package:mono_pos/data/database.dart';
import 'package:mono_pos/data/finance_repository.dart';
import 'package:mono_pos/data/pos_repository.dart';
import 'package:mono_pos/domain/finance.dart';
import 'package:mono_pos/domain/models.dart';
import 'package:mono_pos/media/export_service.dart';
import 'package:uuid/uuid.dart';

class FakeExport implements ExportService {
  final saved = <String, String>{};
  bool cancel = false;
  @override
  Future<bool> saveCsv(String name, String content) async {
    if (cancel) return false;
    saved[name] = content;
    return true;
  }
}

void main() {
  const admin = Actor('a', 'Admin', Role.admin);

  test('CSV : séparateur, guillemets, BOM et formules neutralisées', () {
    final csv = toCsv([
      ['a', 'b;c', 'd"e', 12500, null],
      ['=SOMME(A1)', '+33', '-x', '@cmd', -500],
    ]);
    expect(csv.startsWith('﻿'), isTrue);
    final lines = csv.substring(1).split('\r\n');
    expect(lines[0], 'a;"b;c";"d""e";12500;');
    expect(lines[1], "'=SOMME(A1);'+33;'-x;'@cmd;-500");
  });

  test('exports ventes, dépenses et synthèse enregistrés', () async {
    final db = PosDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final clock = DateTime.utc(2026, 10, 12, 10);
    final pos = PosRepository(db, now: () => clock);
    await pos.initialize();
    final id = await pos.createItem(
      actor: admin,
      category: 'Chaussures',
      name: 'Rangers',
      sku: 'RAN-42',
      label: 'Noir · 42',
      price: 15000,
      stock: 3,
    );
    final sale = await pos.checkout(
      admin,
      SaleRequest(
        id: const Uuid().v4(),
        quantities: {id: 2},
        paymentMode: PaymentMode.cash,
        tendered: 30000,
        customer: {'name': '=HACK()'},
      ),
    );
    await pos.correctPayment(
      admin,
      sale['id'] as String,
      mode: PaymentMode.mobileMoney,
      reason: 'Mobile Money',
    );
    final finance = FinanceRepository(pos);
    final expense = await finance.recordExpense(
      admin,
      kind: ExpenseKind.charge,
      category: 'Transport',
      amount: 2000,
      mode: PaymentMode.cash,
      reason: 'Livraison; urgente',
    );
    await finance.cancelExpense(admin, expense, 'Doublon');
    final period = ReportPeriod.day(clock);
    final sales = await finance.salesCsv(period);
    expect(sales, contains('FACT-2026-00001'));
    expect(sales, contains('Noir · 42'));
    expect(sales, contains('15000;30000;Mobile Money déclaré'));
    final expenses = await finance.expensesCsv(period);
    expect(expenses, contains('"Livraison; urgente"'));
    expect(expenses, contains('annulée;Doublon'));
    final summary = await finance.summaryCsv(period);
    expect(summary, contains('ventes;nettes FCFA;30000'));
    expect(summary, contains('marge;non calculable'));

    final export = FakeExport();
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(pos),
        currentActorProvider.overrideWithValue(admin),
        exportProvider.overrideWithValue(export),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(posProvider.notifier);
    await controller.exportCsv('sales', period);
    expect(export.saved.keys.single, 'mono-sales-2026-10-12.csv');
    expect(container.read(posProvider).message, 'Fichier CSV enregistré.');
    export.cancel = true;
    await controller.exportCsv('summary', period);
    expect(container.read(posProvider).message, 'Export annulé.');
  });
}
