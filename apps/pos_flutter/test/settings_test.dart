import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mono_pos/data/database.dart';
import 'package:mono_pos/data/pos_repository.dart';
import 'package:mono_pos/data/settings_repository.dart';
import 'package:mono_pos/domain/models.dart';
import 'package:mono_pos/printing/receipt.dart';

void main() {
  const admin = Actor('a', 'Admin', Role.admin);
  const seller = Actor('s', 'Vendeur', Role.seller);
  late PosDatabase db;
  late SettingsRepository settings;

  setUp(() async {
    db = PosDatabase(NativeDatabase.memory());
    final pos = PosRepository(db);
    await pos.initialize();
    settings = SettingsRepository(pos);
  });
  tearDown(() => db.close());

  test('valeurs de l’annexe par défaut puis enregistrement audité', () async {
    final initial = await settings.receiptSettings();
    expect(initial.shopName, 'UNIVERS DU MONO');
    expect(initial.contacts, '0706842586/0152656552');
    expect(initial.logo, LogoChoice.original);
    await expectLater(
      settings.saveReceiptSettings(
        seller,
        const ReceiptSettings(shopName: 'X'),
      ),
      throwsA(isA<BusinessException>()),
    );
    for (final bad in [
      const ReceiptSettings(shopName: '  '),
      const ReceiptSettings(contacts: 'a\nb'),
      ReceiptSettings(footer: 'x' * 81),
      const ReceiptSettings(logo: LogoChoice.custom, logoFile: '/tmp/x.jpg'),
    ]) {
      await expectLater(
        settings.saveReceiptSettings(admin, bad),
        throwsA(isA<BusinessException>()),
      );
    }
    await settings.saveReceiptSettings(
      admin,
      const ReceiptSettings(
        shopName: ' Univers du Mono Plateau ',
        contacts: '0700000000',
        footer: 'Merci',
        logo: LogoChoice.none,
      ),
    );
    final saved = await settings.receiptSettings();
    expect(saved.shopName, 'Univers du Mono Plateau');
    expect(saved.logo, LogoChoice.none);
    final text = buildReceipt({
      'number': 'FACT-2026-00001',
      'occurred_at': '2026-10-06T12:00:00Z',
      'seller': 'Admin',
      'customer': <String, String>{},
      'lines': [],
      'total': 0,
      'payment_mode': 'cash',
      'tendered': 0,
      'change': 0,
    }, settings: saved).toPlainText();
    expect(text, isNot(contains('[LOGO]')));
    expect(text, contains('0700000000'));
    expect(text, contains('Merci'));
    final events = await db.select(db.outboxEntries).get();
    expect(events, hasLength(1));
    final envelope = jsonDecode(events.single.envelope) as Map;
    expect(envelope['kind'], 'settings.receipt_updated');
    expect(envelope['payload'], {
      'shop_name': 'Univers du Mono Plateau',
      'contacts': '0700000000',
      'footer': 'Merci',
      'logo': 'none',
    });
  });

  test('logo personnalisé disparu : retour au logo d’origine', () async {
    final dir = await Directory.systemTemp.createTemp('logo');
    final folder = Directory('${dir.path}/catalog_images')..createSync();
    final file = File('${folder.path}/0b9f6c1e-2d3a-4e5f-8a7b-1c2d3e4f5a6b.jpg')
      ..writeAsBytesSync([0xFF, 0xD8, 0xFF]);
    await settings.saveReceiptSettings(
      admin,
      ReceiptSettings(logo: LogoChoice.custom, logoFile: file.path),
    );
    expect((await settings.receiptSettings()).logo, LogoChoice.custom);
    file.deleteSync();
    expect((await settings.receiptSettings()).logo, LogoChoice.original);
    await dir.delete(recursive: true);
  });
}
