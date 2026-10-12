import '../domain/models.dart';

/// Layout follows the customer's paper receipt model (annex of 6 October 2026):
/// centred logo, shop name and contacts; customer and unit; invoice number,
/// date and time; DESIGNATION / P.U / Qte / MONTANT table; TOTAL FACTURE,
/// SOMME REMISE, RENDU; footer. Seller and non-cash payment mode are added
/// discreetly as required by the specification (§9), on the customer's choice.
enum ReceiptAlign { left, center, right }

/// Printable width assumed for the H10 58 mm roll: 384 dots. Consistent with
/// the first paper print (32 characters per line at size 24, 6 October 2026)
/// but not a vendor-confirmed value.
const paperDots = 384;

enum ReceiptSize {
  small(20),
  normal(24),
  large(30);

  const ReceiptSize(this.points);

  /// Text size handed to the printer service. To calibrate on paper.
  final double points;
}

sealed class ReceiptBlock {
  const ReceiptBlock();
  Map<String, Object?> toJson();
}

class ReceiptLogo extends ReceiptBlock {
  const ReceiptLogo(this.source, {this.file = false, this.widthDots = 200});

  /// Bundled asset key, or an absolute path when [file] is true.
  final String source;
  final bool file;

  /// Printed logo width in printer dots.
  final int widthDots;
  @override
  Map<String, Object?> toJson() => {
    'paper': paperDots,
    'type': 'image',
    if (file) 'file': source else 'asset': source,
    'width': widthDots,
  };
}

class ReceiptText extends ReceiptBlock {
  const ReceiptText(
    this.text, {
    this.align = ReceiptAlign.left,
    this.bold = false,
    this.size = ReceiptSize.normal,
  });
  final String text;
  final ReceiptAlign align;
  final bool bold;
  final ReceiptSize size;
  @override
  Map<String, Object?> toJson() => {
    'type': 'text',
    'text': text,
    'align': align.index,
    'bold': bold,
    'size': size.points,
  };
}

class ReceiptRow extends ReceiptBlock {
  ReceiptRow(
    this.cells,
    this.weights,
    this.aligns, {
    this.bold = false,
    this.size = ReceiptSize.normal,
  }) : assert(cells.length == weights.length && cells.length == aligns.length);
  final List<String> cells;
  final List<int> weights;
  final List<ReceiptAlign> aligns;
  final bool bold;
  final ReceiptSize size;
  @override
  Map<String, Object?> toJson() => {
    'type': 'row',
    'cells': cells,
    'weights': weights,
    'aligns': [for (final a in aligns) a.index],
    'bold': bold,
    'size': size.points,
  };
}

class ReceiptFeed extends ReceiptBlock {
  const ReceiptFeed([this.lines = 1]);
  final int lines;
  @override
  Map<String, Object?> toJson() => {'type': 'feed', 'lines': lines};
}

class Receipt {
  Receipt(
    List<ReceiptBlock> blocks, {
    required this.number,
    required this.duplicate,
  }) : blocks = List.unmodifiable(blocks);
  final List<ReceiptBlock> blocks;
  final String number;
  final bool duplicate;

  /// Monospace rendering for tests, logs-free diagnostics and the simulator.
  String toPlainText({int width = 32}) {
    final out = StringBuffer();
    for (final block in blocks) {
      switch (block) {
        case ReceiptLogo():
          out.writeln(_place('[LOGO]', width, ReceiptAlign.center));
        case ReceiptText(:final text, :final align):
          for (final line in _wrap(text, width)) {
            out.writeln(_place(line, width, align));
          }
        case ReceiptRow(:final cells, :final weights, :final aligns):
          final total = weights.fold(0, (a, b) => a + b);
          final widths = [for (final w in weights) (width * w) ~/ total];
          widths[widths.length - 1] += width - widths.fold(0, (a, b) => a + b);
          final line = StringBuffer();
          for (var i = 0; i < cells.length; i++) {
            final cell = cells[i].length > widths[i]
                ? cells[i].substring(0, widths[i])
                : cells[i];
            line.write(_place(cell, widths[i], aligns[i]));
          }
          out.writeln(line.toString().trimRight());
        case ReceiptFeed(:final lines):
          for (var i = 0; i < lines; i++) {
            out.writeln();
          }
      }
    }
    return out.toString();
  }

  static String _place(String text, int width, ReceiptAlign align) {
    if (text.length >= width) return text;
    final gap = width - text.length;
    return switch (align) {
      ReceiptAlign.left => text.padRight(width),
      ReceiptAlign.right => text.padLeft(width),
      ReceiptAlign.center =>
        '${' ' * (gap ~/ 2)}$text${' ' * (gap - gap ~/ 2)}',
    };
  }

  static List<String> _wrap(String text, int width) {
    final lines = <String>[];
    var current = '';
    for (final word in text.split(' ')) {
      final candidate = current.isEmpty ? word : '$current $word';
      if (candidate.length <= width) {
        current = candidate;
      } else {
        if (current.isNotEmpty) lines.add(current);
        current = word;
      }
    }
    lines.add(current);
    return lines;
  }
}

enum LogoChoice { original, custom, none }

const originalLogoAsset = 'assets/branding/logo.png';

/// Shop identity printed on receipts. Defaults come from the customer's
/// annex; the administrator edits them in « Ticket et boutique ».
class ReceiptSettings {
  const ReceiptSettings({
    this.shopName = 'UNIVERS DU MONO',
    this.contacts = '0706842586/0152656552',
    this.footer = 'Votre satisfaction, notre motivation.',
    this.logo = LogoChoice.original,
    this.logoFile,
    this.recette = true,
  });
  final String shopName, contacts, footer;
  final LogoChoice logo;

  /// Private image chosen by the administrator (used when [logo] is custom).
  final String? logoFile;

  /// Recette builds must never produce a receipt usable as a real one.
  final bool recette;
}

/// DESIGNATION / P.U / Qte / MONTANT column weights: 11, 7, 4 and 10
/// characters on a 32-character line (58 mm paper assumed, to calibrate on
/// the H10). Longer designations are printed on their own line.
const tableWeights = [11, 7, 4, 10];
const designationChars = 11;

/// At size 24 the H10 cut « DESIGNATION » after ten characters (first paper
/// print); the smaller size gives each column about 20 % more room.
const tableSize = ReceiptSize.small;
const tableAligns = [
  ReceiptAlign.left,
  ReceiptAlign.right,
  ReceiptAlign.right,
  ReceiptAlign.right,
];

String amount(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (m) => '${m[1]} ',
);

String amountCfa(int value) => '${amount(value)} F CFA';

String ticketPaymentLabel(PaymentMode mode) => switch (mode) {
  PaymentMode.cash => 'ESPÈCES',
  PaymentMode.mobileMoney => 'MOBILE MONEY',
  PaymentMode.transfer => 'VIREMENT',
  PaymentMode.other => 'AUTRE',
};

String _date(String iso) {
  final d = DateTime.parse(iso).toUtc(); // Africa/Abidjan = UTC+0
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

List<ReceiptBlock> _header(
  ReceiptSettings settings, {
  bool duplicate = false,
  String? title,
}) {
  const c = ReceiptAlign.center;
  return [
    if (settings.logo == LogoChoice.original)
      const ReceiptLogo(originalLogoAsset)
    else if (settings.logo == LogoChoice.custom && settings.logoFile != null)
      ReceiptLogo(settings.logoFile!, file: true),
    ReceiptText(
      settings.shopName,
      align: c,
      bold: true,
      size: ReceiptSize.large,
    ),
    if (settings.contacts.isNotEmpty) ReceiptText(settings.contacts, align: c),
    if (settings.recette)
      const ReceiptText(
        'TEST - SANS VALEUR COMMERCIALE',
        align: c,
        bold: true,
        size: ReceiptSize.small,
      ),
    if (duplicate)
      const ReceiptText(
        'DUPLICATA',
        align: c,
        bold: true,
        size: ReceiptSize.large,
      ),
    if (title != null)
      ReceiptText(title, align: c, bold: true, size: ReceiptSize.large),
  ];
}

List<ReceiptBlock> _table(List lines) => [
  ReceiptRow(
    ['DESIGNATION', 'P.U', 'Qte', 'MONTANT'],
    tableWeights,
    tableAligns,
    bold: true,
    size: tableSize,
  ),
  for (final line in lines)
    ...() {
      // No « · » on paper: unverified in the printer's character set.
      final designation = '${line['name']} ${line['label']}'
          .replaceAll(' · ', ' ')
          .toUpperCase();
      final values = [
        amount(line['unit_price'] as int),
        '${line['quantity']}',
        amount(line['line_total'] as int),
      ];
      return designation.length <= designationChars
          ? [
              ReceiptRow(
                [designation, ...values],
                tableWeights,
                tableAligns,
                size: tableSize,
              ),
            ]
          : [
              ReceiptText(designation, size: tableSize),
              ReceiptRow(
                ['', ...values],
                tableWeights,
                tableAligns,
                size: tableSize,
              ),
            ];
    }(),
];

Receipt buildReceipt(
  Map<String, dynamic> sale, {
  bool duplicate = false,
  ReceiptSettings settings = const ReceiptSettings(),
}) {
  const l = ReceiptAlign.left, c = ReceiptAlign.center, r = ReceiptAlign.right;
  final customer = (sale['customer'] as Map).cast<String, String>();
  // A corrected payment replaces the declared one on duplicates.
  final correction = sale['correction'] as Map<String, dynamic>?;
  final payment = correction ?? sale;
  final mode = PaymentMode.values.byName(payment['payment_mode'] as String);
  final local = DateTime.parse(sale['occurred_at'] as String)
      .toUtc(); // Africa/Abidjan = UTC+0
  String two(int n) => n.toString().padLeft(2, '0');
  final date = '${two(local.day)}/${two(local.month)}/${local.year}';
  final time = '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  final who = [
    customer['name'],
    customer['first_name'],
  ].whereType<String>().where((s) => s.isNotEmpty).join(' ').toUpperCase();
  final unit = (customer['unit'] ?? '').toUpperCase();
  final phone = customer['phone'] ?? '';

  final blocks = <ReceiptBlock>[
    ..._header(settings, duplicate: duplicate),
    const ReceiptFeed(),
    if (who.isNotEmpty || unit.isNotEmpty)
      ReceiptRow([who, unit], [3, 2], [l, r]),
    if (phone.isNotEmpty) ReceiptText('Tél : $phone', size: ReceiptSize.small),
    ReceiptText('N° FACTURE : ${sale['number']}'),
    ReceiptRow([date, time], [1, 1], [l, r]),
    ReceiptText('Vendeur : ${sale['seller']}', size: ReceiptSize.small),
    const ReceiptFeed(),
    ..._table(sale['lines'] as List),
    const ReceiptFeed(),
    ReceiptRow(['TOTAL FACTURE', amountCfa(sale['total'] as int)], [1, 1], [
      r,
      r,
    ], bold: true),
    if (mode == PaymentMode.cash) ...[
      ReceiptRow(
        ['SOMME REMISE', amountCfa(payment['tendered'] as int)],
        [1, 1],
        [r, r],
        bold: true,
      ),
      ReceiptRow(['RENDU', amountCfa(payment['change'] as int)], [1, 1], [
        r,
        r,
      ], bold: true),
    ] else
      ReceiptRow(['PAIEMENT', ticketPaymentLabel(mode)], [1, 1], [
        r,
        r,
      ], bold: true),
    if (correction != null)
      ReceiptText(
        'Paiement corrigé le ${_date(correction['corrected_at'] as String)}',
        align: r,
        size: ReceiptSize.small,
      ),
    if (sale['returns'] case final Map<String, dynamic> returns) ...[
      const ReceiptFeed(),
      ReceiptText(
        returns['complete'] == true
            ? (returns['cancelled'] == true
                  ? 'VENTE ANNULÉE'
                  : 'VENTE ENTIÈREMENT RETOURNÉE')
            : 'RETOUR PARTIEL',
        align: c,
        bold: true,
      ),
      ReceiptRow(['REMBOURSÉ', amountCfa(returns['refunded'] as int)], [1, 1], [
        r,
        r,
      ], bold: true),
    ],
    const ReceiptFeed(),
    if (settings.footer.isNotEmpty)
      ReceiptText(settings.footer, align: c, size: ReceiptSize.small),
    const ReceiptFeed(3),
  ];
  return Receipt(
    blocks,
    number: sale['number'] as String,
    duplicate: duplicate,
  );
}

/// Paper calibration ticket: accents, amounts, logo and a long designation.
/// Built from a fabricated sale clearly numbered TEST; nothing is recorded.
Receipt buildTestReceipt({
  ReceiptSettings settings = const ReceiptSettings(),
}) => buildReceipt({
  'number': 'TEST-IMPRESSION',
  'occurred_at': DateTime.now().toUtc().toIso8601String(),
  'seller': 'Essai imprimante',
  'customer': {
    'name': 'Équipement',
    'first_name': 'béret reçu',
    'unit': 'TEST',
  },
  'lines': [
    {
      'name': 'Rangers',
      'label': '42',
      'quantity': 2,
      'unit_price': 12500,
      'line_total': 25000,
    },
    {
      'name': 'Treillis camouflage forêt',
      'label': 'Taille XL',
      'quantity': 1,
      'unit_price': 1250000,
      'line_total': 1250000,
    },
  ],
  'total': 1275000,
  'payment_mode': 'cash',
  'tendered': 1300000,
  'change': 25000,
}, settings: settings);

/// Refund ticket for a return or a cancellation.
Receipt buildReturnReceipt(
  Map<String, dynamic> operation, {
  ReceiptSettings settings = const ReceiptSettings(),
}) {
  const l = ReceiptAlign.left, c = ReceiptAlign.center, r = ReceiptAlign.right;
  final cancel = operation['kind'] == 'CANCEL';
  final mode = PaymentMode.values.byName(operation['refund_mode'] as String);
  final lines = operation['lines'] as List;
  final blocks = <ReceiptBlock>[
    ..._header(settings, title: cancel ? 'ANNULATION' : 'REMBOURSEMENT'),
    const ReceiptFeed(),
    ReceiptText('N° FACTURE : ${operation['sale_number']}'),
    ReceiptText(_date(operation['occurred_at'] as String)),
    ReceiptText('Opérateur : ${operation['actor']}', size: ReceiptSize.small),
    const ReceiptFeed(),
    ..._table(lines),
    for (final line in lines)
      if (line['resaleable'] == false)
        ReceiptText(
          'Endommagé : ${line['name']} ${line['label']}'
              .replaceAll(' · ', ' ')
              .toUpperCase(),
          size: ReceiptSize.small,
        ),
    const ReceiptFeed(),
    ReceiptRow(
      ['TOTAL REMBOURSÉ', amountCfa(operation['refund_total'] as int)],
      [1, 1],
      [r, r],
      bold: true,
    ),
    ReceiptRow(['MODE', ticketPaymentLabel(mode)], [1, 1], [r, r], bold: true),
    ReceiptText(
      'Motif : ${operation['reason']}',
      align: l,
      size: ReceiptSize.small,
    ),
    const ReceiptFeed(),
    if (settings.footer.isNotEmpty)
      ReceiptText(settings.footer, align: c, size: ReceiptSize.small),
    const ReceiptFeed(3),
  ];
  return Receipt(
    blocks,
    number: operation['sale_number'] as String,
    duplicate: false,
  );
}
