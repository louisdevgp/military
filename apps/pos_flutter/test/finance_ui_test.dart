import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mono_pos/application/pos_controller.dart';
import 'package:mono_pos/application/session_controller.dart';
import 'package:mono_pos/data/database.dart';
import 'package:mono_pos/data/finance_repository.dart';
import 'package:mono_pos/data/pos_repository.dart';
import 'package:mono_pos/domain/finance.dart';
import 'package:mono_pos/domain/models.dart';
import 'package:mono_pos/main.dart';
import 'package:uuid/uuid.dart';

const admin = Actor('a', 'Admin', Role.admin);

void main() {
  testWidgets('dépense, clôture avec écart et rapport du jour', (tester) async {
    tester.view.physicalSize = const Size(720, 1440);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = PosDatabase(NativeDatabase.memory());
    final repo = PosRepository(db);
    await repo.initialize();
    final id = await repo.createItem(
      actor: admin,
      category: 'Chaussures',
      name: 'Rangers',
      sku: 'RAN-42',
      label: '42',
      price: 15000,
      stock: 4,
    );
    await repo.checkout(
      admin,
      SaleRequest(
        id: const Uuid().v4(),
        quantities: {id: 1},
        paymentMode: PaymentMode.cash,
        tendered: 20000,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        currentActorProvider.overrideWithValue(admin),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MonoApp()),
    );
    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
    }

    Future<void> open(String entry) async {
      await tester.tap(find.byTooltip('Administration'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry));
      await settle();
    }

    await settle();
    // Expense paid in cash.
    await open('Dépenses');
    await tester.tap(find.text('Dépense'));
    await settle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Catégorie'),
      'Transport',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Montant FCFA'),
      '2000',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Motif'),
      'Livraison',
    );
    await tester.tap(find.text('Enregistrer'));
    await settle();
    expect(find.textContaining('Transport · 2 000 FCFA'), findsOneWidget);
    await tester.pageBack();
    await settle();

    // Closing: expected 10 000 + 15 000 − 2 000 = 23 000, counted 22 500.
    await open('Clôture de caisse');
    await tester.enterText(
      find.widgetWithText(TextField, 'Fond de caisse au départ FCFA'),
      '10000',
    );
    await tester.pump();
    expect(find.text('23 000 FCFA'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Espèces comptées FCFA'),
      '22500',
    );
    await tester.pump();
    expect(find.textContaining('Écart : −500 FCFA'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(
        TextField,
        'Fond de caisse conservé pour demain FCFA',
      ),
      '10000',
    );
    await tester.enterText(
      find.widgetWithText(
        TextField,
        'Commentaire (obligatoire en cas d’écart)',
      ),
      'Monnaie rendue en trop',
    );
    await tester.tap(find.text('Clôturer la caisse'));
    await settle();
    final closings = await FinanceRepository(repo).closings();
    expect(
      (closings.single.expected, closings.single.difference),
      (23000, -500),
    );

    // Day report.
    await open('Rapports');
    expect(find.text('Ventes nettes'), findsOneWidget);
    expect(find.text('15 000 FCFA'), findsWidgets);
    expect(find.textContaining('Marge non calculable'), findsOneWidget);
    final report = await FinanceRepository(repo)
        .report(ReportPeriod.day(DateTime.now()));
    expect(
      (report.net, report.expensesByKind[ExpenseKind.charge]),
      (15000, 2000),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await db.close();
  });
}
