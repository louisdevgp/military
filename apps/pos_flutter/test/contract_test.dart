import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mono_pos/auth/pin.dart';
import 'package:mono_pos/data/database.dart';
import 'package:mono_pos/data/pos_repository.dart';
import 'package:mono_pos/data/settings_repository.dart';
import 'package:mono_pos/printing/receipt.dart';
import 'package:mono_pos/data/user_repository.dart';
import 'package:mono_pos/domain/models.dart';
import 'package:uuid/uuid.dart';

void main() {
  test('export du contrat réel Flutter pour la recette Python', () async {
    final db = PosDatabase(NativeDatabase.memory());
    final repo = PosRepository(db, now: () => DateTime.utc(2026, 10, 6, 12));
    await repo.initialize();
    final users = UserRepository(
      repo,
      hasher: const Pbkdf2PinHasher(iterations: 10),
    );
    final actor = await users.createFirstAdmin(
      'Admin TEST',
      '481516',
      '481516',
    );
    await users.createUser(
      actor,
      name: 'Vendeur TEST',
      role: Role.seller,
      pin: '927384',
      confirmation: '927384',
    );
    final seller = (await users.users()).firstWhere(
      (u) => u.role == Role.seller,
    );
    final id = await repo.createItem(
      actor: actor,
      category: 'Catégorie TEST',
      name: 'Article TEST',
      sku: 'TEST-42',
      label: 'Noir / 42',
      price: 12500,
      stock: 5,
    );
    // Two sizes of one article: the server must accept the shared product.
    await repo.createProduct(
      actor: actor,
      category: 'Treillis TEST',
      name: 'Treillis TEST',
      variants: matrixVariants(
        grid: SizeGrid.clothing,
        reference: 'TRE-TEST',
        colors: ['Vert olive'],
        price: 20000,
        stock: {('Vert olive', 'M'): 1, ('Vert olive', 'L'): 0},
      ),
    );
    final sale = await repo.checkout(
      seller.actor,
      SaleRequest(
        id: const Uuid().v4(),
        quantities: {id: 2},
        paymentMode: PaymentMode.cash,
        tendered: 30000,
      ),
    );
    await repo.changePrice(actor, id, 14000);
    await repo.returnSale(
      actor,
      ReturnRequest(
        id: const Uuid().v4(),
        saleId: sale['id'] as String,
        lines: {id: (quantity: 1, resaleable: true)},
        refundMode: PaymentMode.cash,
        reason: 'Retour TEST',
      ),
    );
    await repo.moveStock(
      actor,
      id,
      kind: StockKind.reception,
      quantity: 2,
      reason: 'Réception TEST',
    );
    await repo.countInventory(actor, {id: 4});
    await repo.updateVariant(actor, id, threshold: 2);
    await SettingsRepository(repo).saveReceiptSettings(
      actor,
      const ReceiptSettings(contacts: '0700000000', logo: LogoChoice.none),
    );
    await repo.correctPayment(
      actor,
      sale['id'] as String,
      mode: PaymentMode.cash,
      tendered: 25000,
      reason: 'Somme remise TEST corrigée',
    );
    final events = await db.select(db.outboxEntries).get();
    final fixture = {
      'terminal_id': (await repo.terminal()).terminalId,
      'events': events.map((e) => jsonDecode(e.envelope)).toList(),
      'expected': {
        'stock': 4,
        'total': 25000,
        'current_price': 14000,
        'sale_count': 1,
        'corrections': 1,
        'actors': 2,
        'variants': 3,
        'refunded': 12500,
      },
    };
    expect(fixture['events'], hasLength(13));
    if (const bool.fromEnvironment('EXPORT_CONTRACT')) {
      final file = File('../../contracts/vertical_v1.json');
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(fixture)}\n',
      );
      final schema = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY CASE WHEN type = 'table' THEN 0 ELSE 1 END, name",
          )
          .get();
      final snapshot = File('drift_schemas/schema_v${db.schemaVersion}.sql');
      await snapshot.parent.create(recursive: true);
      await snapshot.writeAsString(
        '-- SQLite / Drift schema version ${db.schemaVersion}. Exported from the tested database.\n${schema.map((row) => '${row.read<String>('sql')};').join('\n')}\nPRAGMA user_version = ${db.schemaVersion};\n',
      );
    }
    await db.close();
  });
}
