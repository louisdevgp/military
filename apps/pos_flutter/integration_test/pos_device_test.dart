import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mono_pos/application/pos_controller.dart';
import 'package:mono_pos/application/session_controller.dart';
import 'package:mono_pos/data/database.dart';
import 'package:mono_pos/data/pos_repository.dart';
import 'package:mono_pos/domain/models.dart';
import 'package:mono_pos/main.dart';
import 'package:mono_pos/printing/printer_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'H10 : parcours local persistant, ticket simulé et passerelle fermée',
    (tester) async {
      // A separate temporary database keeps test products out of the installed catalogue.
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/integration_${DateTime.now().microsecondsSinceEpoch}.sqlite',
      );
      final db = PosDatabase(NativeDatabase(file));
      final repo = PosRepository(db);
      await repo.initialize();
      final terminal = await repo.terminal();
      final container = ProviderContainer(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          currentActorProvider.overrideWithValue(
            const Actor('device-test-admin', 'Admin test', Role.admin),
          ),
        ],
      );
      final controller = container.read(posProvider.notifier);
      await controller.createItem(
        category: 'RECETTE',
        name: 'Article TEST',
        sku: 'TEST-42',
        label: 'Noir / 42',
        price: '12500',
        stock: '3',
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const MonoApp()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Article TEST'), findsOneWidget);
      await tester.ensureVisible(
        find.byTooltip('Ajouter Article TEST au panier'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Ajouter Article TEST au panier'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Panier'));
      await tester.pumpAndSettle();
      expect(find.text('Passer au paiement'), findsOneWidget);
      expect(await controller.pay(PaymentMode.cash, '15000', {}), isTrue);
      await tester.pumpAndSettle();
      final sale = (await repo.history()).single;
      expect(sale['change'], 2500);
      expect((await repo.catalog()).single.stock, 2);
      expect(
        container.read(posProvider).message,
        contains('aucun papier imprimé'),
      );
      await controller.duplicate(sale);
      expect(container.read(posProvider).receipt!.duplicate, isTrue);
      expect((await repo.history()).length, 1);
      // Binds the SRPrinter service without printing: no paper is used here.
      expect(await PlatformPrinter.probe(), isNotEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await db.close();

      final reopened = PosDatabase(NativeDatabase(file));
      final afterRestart = PosRepository(reopened);
      await afterRestart.initialize();
      expect((await afterRestart.terminal()).terminalId, terminal.terminalId);
      expect((await afterRestart.terminal()).saleSequence, 1);
      expect((await afterRestart.catalog()).single.stock, 2);
      expect((await afterRestart.history()).single['id'], sale['id']);
      expect(await afterRestart.pendingCount(), 2);
      final integrity = await reopened
          .customSelect('PRAGMA integrity_check')
          .getSingle();
      expect(integrity.data.values.single, 'ok');
      await reopened.close();
      await file.delete();
    },
  );
}
