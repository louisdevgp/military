import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mono_pos/application/pos_controller.dart';
import 'package:mono_pos/application/session_controller.dart';
import 'package:mono_pos/data/database.dart';
import 'package:mono_pos/data/pos_repository.dart';
import 'package:mono_pos/domain/models.dart';
import 'package:mono_pos/printing/printer_service.dart';

class BrokenPrinter implements PrinterService {
  @override
  String get label => 'Imprimante en panne (test)';
  @override
  Future<PrintOutcome> printReceipt(Receipt receipt) async =>
      throw StateError('paper unknown');
}

const testAdmin = Actor('test-admin', 'Admin test', Role.admin);

void main() {
  test(
    'panne impression : vente conservée, panier vidé et double appui bloqué',
    () async {
      final db = PosDatabase(NativeDatabase.memory());
      final repo = PosRepository(db);
      await repo.initialize();
      final id = await repo.createItem(
        actor: testAdmin,
        category: 'Test',
        name: 'Test',
        sku: 'TEST',
        label: 'Test',
        price: 100,
        stock: 2,
      );
      final container = ProviderContainer(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          currentActorProvider.overrideWithValue(testAdmin),
          printerProvider.overrideWithValue(BrokenPrinter()),
        ],
      );
      final controller = container.read(posProvider.notifier);
      await controller.refresh();
      controller.quantity(id, 1);
      final results = await Future.wait([
        controller.pay(PaymentMode.cash, '200', {}),
        controller.pay(PaymentMode.cash, '200', {}),
      ]);
      expect(results.where((x) => x).length, 1);
      expect(container.read(posProvider).cart, isEmpty);
      expect(
        container.read(posProvider).message,
        contains('Impression non confirmée'),
      );
      final sales = await repo.history();
      expect(sales.length, 1);
      await controller.duplicate(sales.single);
      expect((await repo.catalog()).single.stock, 1);
      expect((await repo.history()).length, 1);
      expect(container.read(posProvider).receipt!.duplicate, isTrue);
      container.dispose();
      await db.close();
    },
  );
}
