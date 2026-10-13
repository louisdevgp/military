import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mono_pos/data/database.dart';
import 'package:mono_pos/data/pos_repository.dart';
import 'package:mono_pos/domain/models.dart';
import 'package:uuid/uuid.dart';

const admin = Actor('a', 'Admin', Role.admin);
const seller = Actor('s', 'Vendeur', Role.seller);

void main() {
  late PosDatabase db;
  late PosRepository repo;

  setUp(() async {
    db = PosDatabase(NativeDatabase.memory());
    repo = PosRepository(db);
    await repo.initialize();
  });
  tearDown(() => db.close());

  test('retirer tout un article sans rien effacer, puis le remettre', () async {
    await repo.createProduct(
      actor: admin,
      category: 'Treillis TEST',
      name: 'Treillis TEST',
      variants: matrixVariants(
        grid: SizeGrid.clothing,
        reference: 'TRE-TEST',
        colors: ['Vert olive'],
        price: 20000,
        stock: {('Vert olive', 'M'): 2, ('Vert olive', 'L'): 1},
      ),
    );
    final variants = await repo.inventory();
    final product = variants.first.productId;
    final sold = variants.firstWhere((v) => v.stock == 2);
    await repo.checkout(
      seller,
      SaleRequest(
        id: const Uuid().v4(),
        quantities: {sold.id: 1},
        paymentMode: PaymentMode.mobileMoney,
      ),
    );
    await expectLater(
      repo.setProductActive(seller, product, false),
      throwsA(isA<BusinessException>()),
    );
    // One variant already deactivated: only the others change.
    await repo.updateVariant(admin, sold.id, active: false);
    expect(await repo.setProductActive(admin, product, false), 1);
    expect(await repo.setProductActive(admin, product, false), 0);
    expect(
      (await repo.catalog()).where((v) => v.productId == product),
      isEmpty,
    );
    final kept = (await repo.inventory()).where((v) => v.productId == product);
    expect(kept, hasLength(2));
    expect(kept.every((v) => !v.active), isTrue);
    expect(kept.map((v) => v.stock).reduce((a, b) => a + b), 2);
    expect(await repo.history(), hasLength(1), reason: 'vente conservée');
    await expectLater(
      repo.checkout(
        seller,
        SaleRequest(
          id: const Uuid().v4(),
          quantities: {kept.firstWhere((v) => v.stock == 1).id: 1},
          paymentMode: PaymentMode.mobileMoney,
        ),
      ),
      throwsA(isA<BusinessException>()),
    );
    final events = [
      for (final e in await db.select(db.outboxEntries).get())
        jsonDecode(e.envelope) as Map<String, dynamic>,
    ].where((e) => e['kind'] == 'variant.updated');
    expect(events, hasLength(2));
    expect(events.last['payload'], containsPair('active', false));

    expect(await repo.setProductActive(admin, product, true), 2);
    expect(
      (await repo.catalog()).where((v) => v.productId == product),
      hasLength(2),
    );
    await expectLater(
      repo.setProductActive(admin, 'inconnu', false),
      throwsA(isA<BusinessException>()),
    );
  });
}
