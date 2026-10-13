import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mono_pos/application/pos_controller.dart';
import 'package:mono_pos/application/session_controller.dart';
import 'package:mono_pos/data/database.dart';
import 'package:mono_pos/data/pos_repository.dart';
import 'package:mono_pos/domain/models.dart';
import 'package:uuid/uuid.dart';

const admin = Actor('a', 'Admin', Role.admin);
const awa = Actor('s1', 'Awa', Role.seller);
const koffi = Actor('s2', 'Koffi', Role.seller);

void main() {
  late PosDatabase db;
  late PosRepository repo;

  setUp(() async {
    db = PosDatabase(NativeDatabase.memory());
    repo = PosRepository(db);
    await repo.initialize();
    final id = await repo.createItem(
      actor: admin,
      category: 'TEST',
      name: 'Béret TEST',
      sku: 'BER',
      label: '58',
      price: 5000,
      stock: 10,
    );
    for (final seller in [awa, awa, koffi]) {
      await repo.checkout(
        seller,
        SaleRequest(
          id: const Uuid().v4(),
          quantities: {id: 1},
          paymentMode: PaymentMode.mobileMoney,
        ),
      );
    }
  });
  tearDown(() => db.close());

  ProviderContainer container(Actor actor) {
    final c = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        currentActorProvider.overrideWithValue(actor),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('un vendeur ne voit que ses propres ventes', () async {
    final c = container(awa);
    await c.read(posProvider.notifier).refresh();
    final sales = c.read(posProvider).sales;
    expect(sales, hasLength(2));
    expect(sales.every((s) => s['seller_id'] == awa.id), isTrue);
    expect(c.read(posProvider).sellers, isEmpty);
    // The filter is reserved to the administrator.
    await c.read(posProvider.notifier).filterHistory(koffi.id);
    expect(
      c.read(posProvider).sales.every((s) => s['seller_id'] == awa.id),
      isTrue,
    );

    final k = container(koffi);
    await k.read(posProvider.notifier).refresh();
    expect(k.read(posProvider).sales.single['seller'], 'Koffi');
  });

  test('l’administrateur voit tout et filtre par vendeur', () async {
    final c = container(admin);
    final pos = c.read(posProvider.notifier);
    await pos.refresh();
    expect(c.read(posProvider).sales, hasLength(3));
    expect(c.read(posProvider).sellers, [(awa.id, 'Awa'), (koffi.id, 'Koffi')]);
    await pos.filterHistory(koffi.id);
    expect(c.read(posProvider).sales.single['seller_id'], koffi.id);
    await pos.filterHistory(null);
    expect(c.read(posProvider).sales, hasLength(3));
  });

  test('filtre au niveau des données', () async {
    expect(await repo.history(), hasLength(3));
    expect(await repo.history(sellerId: awa.id), hasLength(2));
    expect(await repo.history(sellerId: 'inconnu'), isEmpty);
  });
}
