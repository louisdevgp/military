import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mono_pos/printing/receipt.dart';
import 'package:mono_pos/ui/receipt_preview.dart';

/// Renders receipts to PNG for visual review, on demand only:
/// flutter test test/receipt_render_test.dart --dart-define=RENDER_RECEIPTS=true
/// Output: .artifacts/receipts/ (git-ignored). Screen rendering, not paper.
const render = bool.fromEnvironment('RENDER_RECEIPTS');

Map<String, dynamic> sale() => {
  'id': 'sale-render',
  'number': 'FACT-2026-00002',
  'occurred_at': '2026-10-12T09:21:00.000Z',
  'seller': 'Awa',
  'customer': {'name': 'Kone', 'first_name': 'Amien', 'unit': 'GSA'},
  'lines': [
    {
      'variant_id': 'v1',
      'name': 'Rangers',
      'label': 'Noir · Pointure 42',
      'quantity': 2,
      'unit_price': 15000,
      'line_total': 30000,
    },
    {
      'variant_id': 'v2',
      'name': 'Bleu',
      'label': 'MO',
      'quantity': 1,
      'unit_price': 25000,
      'line_total': 25000,
    },
  ],
  'total': 55000,
  'payment_mode': 'cash',
  'tendered': 60000,
  'change': 5000,
};

/// Material fonts shipped with the Flutter SDK (FONT_DIR overrides).
Future<void> _loadFonts() async {
  const dir = String.fromEnvironment('FONT_DIR');
  ByteData font(String name) =>
      ByteData.sublistView(File('$dir/$name').readAsBytesSync());
  final loader = FontLoader('Roboto')
    ..addFont(Future.value(font('roboto-regular.ttf')))
    ..addFont(Future.value(font('roboto-bold.ttf')));
  await loader.load();
}

void main() {
  testWidgets('rendu PNG des tickets', (tester) async {
    await tester.runAsync(_loadFonts);
    final out = Directory('../../.artifacts/receipts')
      ..createSync(recursive: true);
    final cancelled = {
      ...sale(),
      'returns': {'refunded': 55000, 'complete': true, 'cancelled': true},
    };
    final refund = {
      'sale_number': 'FACT-2026-00002',
      'kind': 'RETURN',
      'occurred_at': '2026-10-12T10:05:00.000Z',
      'actor': 'Awa',
      'refund_total': 15000,
      'refund_mode': 'cash',
      'reason': 'Taille inadaptée',
      'lines': [
        {
          'name': 'Rangers',
          'label': 'Noir · Pointure 42',
          'quantity': 1,
          'unit_price': 15000,
          'line_total': 15000,
          'resaleable': true,
        },
      ],
    };
    final receipts = {
      'vente': buildReceipt(sale()),
      'duplicata-annulee': buildReceipt(cancelled, duplicate: true),
      'remboursement': buildReturnReceipt(refund),
      'ticket-test': buildTestReceipt(),
    };
    for (final entry in receipts.entries) {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Roboto'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Center(
                child: RepaintBoundary(
                  key: key,
                  child: ReceiptPreview(entry.value),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await precacheImage(
          const AssetImage(originalLogoAsset),
          key.currentContext!,
        );
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File('${out.path}/${entry.key}.png')
            .writeAsBytesSync(png!.buffer.asUint8List());
      });
    }
  }, skip: !render);
}
