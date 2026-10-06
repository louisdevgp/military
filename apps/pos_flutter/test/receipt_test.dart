import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mono_pos/printing/printer_service.dart';

Map<String, dynamic> sale({
  String mode = 'cash',
  Map<String, String> customer = const {},
  String name = 'Rangers',
  String label = '42',
}) => {
  'id': '7f1f2c1e-1a1b-4c4d-8e8f-000000000001',
  'number': 'FACT-2026-00002',
  'occurred_at': '2026-03-21T09:21:00.000Z',
  'seller_id': 'u1',
  'seller': 'Awa',
  'customer': customer,
  'lines': [
    {
      'name': name,
      'label': label,
      'sku': 'R42',
      'quantity': 2,
      'unit_price': 15000,
      'line_total': 30000,
    },
    {
      'name': 'Bleu',
      'label': 'MO',
      'sku': 'BMO',
      'quantity': 1,
      'unit_price': 25000,
      'line_total': 25000,
    },
  ],
  'total': 55000,
  'payment_mode': mode,
  'tendered': mode == 'cash' ? 60000 : null,
  'change': mode == 'cash' ? 5000 : 0,
  'collected': 55000,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ticket conforme au modèle client, espèces', () {
    final text = buildReceipt(
      sale(customer: {'name': 'Kone', 'first_name': 'Amien', 'unit': 'GSA'}),
    ).toPlainText();
    final order = [
      '[LOGO]',
      'UNIVERS DU MONO',
      '0706842586/0152656552',
      'TEST - SANS VALEUR COMMERCIALE',
      'KONE AMIEN',
      'N° FACTURE : FACT-2026-00002',
      '21/03/2026',
      '09:21:00',
      'Vendeur : Awa',
      'DESIGNATION',
      'RANGERS 42',
      '15 000',
      '30 000',
      'BLEU MO',
      'TOTAL FACTURE',
      '55 000 F CFA',
      'SOMME REMISE',
      '60 000 F CFA',
      'RENDU',
      '5 000 F CFA',
      'Votre satisfaction',
    ];
    var from = 0;
    for (final piece in order) {
      final at = text.indexOf(piece, from);
      expect(
        at,
        greaterThanOrEqualTo(0),
        reason: '« $piece » absent ou mal placé\n$text',
      );
      from = at + piece.length;
    }
    expect(text, contains('GSA'));
    expect(text, contains('DESIGNATION    P.U Qte   MONTANT'));
    // Columns never touch: amounts and quantity stay separated.
    expect(text, contains('RANGERS 42  15 000   2    30 000'));
    expect(text, isNot(contains('DUPLICATA')));
    expect(text, isNot(contains('PAIEMENT')));
  });

  test('mode non espèces, duplicata et désignation longue', () {
    final receipt = buildReceipt(
      sale(mode: 'mobileMoney', name: 'Treillis camouflage', label: 'Taille L'),
      duplicate: true,
    );
    final text = receipt.toPlainText();
    expect(receipt.duplicate, isTrue);
    expect(text, contains('DUPLICATA'));
    expect(text, contains('PAIEMENT'));
    expect(text, contains('MOBILE MONEY'));
    expect(text, isNot(contains('SOMME REMISE')));
    expect(text, isNot(contains('RENDU')));
    // Long designation printed alone, amounts on the next row.
    expect(text, contains('TREILLIS CAMOUFLAGE TAILLE L'));
    expect(text, isNot(contains('Tél')));
  });

  test(
    'impression intégrée : blocs validables et logo transmis en PNG',
    () async {
      const channel = MethodChannel('ci.universdumono/printer');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final outcome = await PlatformPrinter().printReceipt(
        buildReceipt(sale()),
      );
      expect(outcome, PrintOutcome.submittedUnconfirmed);
      final blocks = (calls.single.arguments as Map)['blocks'] as List;
      final logo = blocks.first as Map;
      expect(logo['type'], 'image');
      expect(logo.containsKey('asset'), isFalse);
      final png = logo['png'] as Uint8List;
      expect(png.sublist(1, 4), 'PNG'.codeUnits);
      for (final block in blocks.cast<Map>()) {
        expect(['image', 'text', 'row', 'feed'], contains(block['type']));
        if (block['type'] == 'text') {
          expect(block['text'], isNot(contains('\n')));
          expect((block['text'] as String).length, lessThanOrEqualTo(256));
        }
        if (block['type'] == 'row') {
          expect(
            (block['cells'] as List).length,
            (block['weights'] as List).length,
          );
        }
      }
    },
  );

  test(
    'refus du service : erreur remontée, jamais de succès annoncé',
    () async {
      const channel = MethodChannel('ci.universdumono/printer');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => throw PlatformException(code: 'SERVICE_TIMEOUT'),
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await expectLater(
        PlatformPrinter().printReceipt(buildReceipt(sale())),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}
