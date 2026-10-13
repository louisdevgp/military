import 'dart:convert';

import 'package:crypto/crypto.dart';

const maxMoney = 1000000000000;
const maxQuantity = 1000000;

class BusinessException implements Exception {
  const BusinessException(this.message);
  final String message;
  @override
  String toString() => message;
}

enum Role { admin, seller }

class Actor {
  const Actor(this.id, this.name, this.role);
  final String id;
  final String name;
  final Role role;
  void requireAdmin() {
    if (role != Role.admin) {
      throw const BusinessException(
        'Cette opération est réservée à l’administrateur.',
      );
    }
  }
}

/// Operator as listed on the lock screen; never carries PIN material.
class LocalUser {
  const LocalUser({
    required this.id,
    required this.name,
    required this.role,
    required this.active,
    this.lockedUntil,
  });
  final String id, name;
  final Role role;
  final bool active;
  final DateTime? lockedUntil;
  Actor get actor => Actor(id, name, role);
}

enum PaymentMode {
  cash('Espèces'),
  mobileMoney('Mobile Money déclaré'),
  transfer('Virement déclaré'),
  other('Autre');

  const PaymentMode(this.label);
  final String label;
}

class CatalogItem {
  const CatalogItem({
    required this.id,
    this.productId = '',
    required this.category,
    required this.name,
    required this.sku,
    required this.label,
    required this.price,
    required this.stock,
    this.photoPaths = const [],
    this.color,
    this.size,
    this.threshold = 0,
    this.active = true,
  });
  final String id, productId, category, name, sku, label;
  final int price, stock;
  final List<String> photoPaths;

  /// Structured attributes; null for free single variants.
  final String? color, size;

  /// Low-stock alert level (0 = none) and sale status.
  final int threshold;
  final bool active;
  bool get lowStock => threshold > 0 && stock <= threshold;
}

/// Manual stock operations. Sales and returns have their own flows.
enum StockKind {
  reception('Réception', 'RECEPTION'),
  loss('Perte', 'LOSS'),
  adjustment('Correction', 'ADJUSTMENT');

  const StockKind(this.label, this.code);
  final String label, code;
}

/// One line of a variant's stock history.
class StockMovementView {
  const StockMovementView({
    required this.kind,
    required this.quantity,
    required this.reason,
    required this.actor,
    required this.occurredAt,
    this.counted,
  });
  final String kind, reason, actor, occurredAt;
  final int quantity;
  final int? counted;
}

/// Size grids given by the customer on 6 October 2026. Other articles keep a
/// free variant label until the shop specifies their sizes.
enum SizeGrid {
  single('Variante unique', '', []),
  clothing('Tailles treillis', 'Taille', ['M', 'L', 'XL', 'XXL', 'XXXL']),
  shoes('Pointures rangers', 'Pointure', [
    '38',
    '39',
    '40',
    '41',
    '42',
    '43',
    '44',
    '45',
    '46',
  ]);

  const SizeGrid(this.title, this.prefix, this.sizes);
  final String title, prefix;
  final List<String> sizes;

  /// « Noir · Pointure 42 » or « Taille XL » when no colour is given.
  String label(String size, String color) {
    final base = '$prefix $size';
    return color.trim().isEmpty ? base : '${color.trim()} · $base';
  }

  /// Reference plus colour and size, e.g. RAN-NOIR-42 or TRE-VERT-OLIVE-XL.
  String sku(String reference, String size, {String color = ''}) => [
    reference.trim().toUpperCase(),
    if (colorCode(color).isNotEmpty) colorCode(color),
    size,
  ].join('-');
}

/// Colour as written by the administrator: trimmed, first letter upper case.
String normalizeColor(String color) {
  final c = color.trim().replaceAll(RegExp(r'\s+'), ' ');
  return c.isEmpty ? '' : '${c[0].toUpperCase()}${c.substring(1)}';
}

/// Reference fragment for a colour: « Vert olive » → VERT-OLIVE.
String colorCode(String color) {
  const accents = {
    'À': 'A',
    'Â': 'A',
    'Ç': 'C',
    'É': 'E',
    'È': 'E',
    'Ê': 'E',
    'Ë': 'E',
    'Î': 'I',
    'Ï': 'I',
    'Ô': 'O',
    'Ù': 'U',
    'Û': 'U',
    'Ü': 'U',
  };
  final upper = color
      .trim()
      .toUpperCase()
      .split('')
      .map((ch) => accents[ch] ?? ch)
      .join();
  return upper
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

/// One sellable variant to create with its product.
class VariantDraft {
  const VariantDraft({
    required this.sku,
    required this.label,
    required this.price,
    required this.stock,
    this.color,
    this.size,
  });
  final String sku, label;
  final int price, stock;
  final String? color, size;
}

/// Real stock typed for each colour × size that exists in the shop. Only the
/// combinations with a typed quantity become variants (0 = exists, sold out).
List<VariantDraft> matrixVariants({
  required SizeGrid grid,
  required String reference,
  required List<String> colors,
  required int price,
  required Map<(String, String), int> stock,
}) => [
  for (final color in colors.isEmpty ? [''] : colors)
    for (final size in grid.sizes)
      if (stock[(color, size)] case final qty?)
        VariantDraft(
          sku: grid.sku(reference, size, color: color),
          label: grid.label(size, color),
          price: price,
          stock: qty,
          color: color.isEmpty ? null : color,
          size: size,
        ),
];

class CashPreview {
  const CashPreview(this.tendered, this.change);
  final int tendered, change;
}

CashPreview? previewCash(int total, String input) {
  try {
    final tendered = moneyInput(input);
    return tendered < total ? null : CashPreview(tendered, tendered - total);
  } on BusinessException {
    return null;
  }
}

/// Change above this amount, or at least equal to the sale total, asks the
/// cashier to confirm the tendered amount (typing errors such as 600 000
/// instead of 60 000).
const changeConfirmationThreshold = 50000;

bool needsChangeConfirmation(int total, int tendered) {
  final change = tendered - total;
  return change > 0 &&
      (change >= total || change >= changeConfirmationThreshold);
}

/// Exact amount, then the next round banknote totals above it.
List<int> quickTenders(int total) {
  int ceilTo(int step) => ((total + step - 1) ~/ step) * step;
  final amounts = <int>{total};
  for (final step in [5000, 10000, 50000]) {
    final rounded = ceilTo(step);
    if (rounded > total && rounded <= maxMoney) amounts.add(rounded);
  }
  return amounts.toList()..sort();
}

class SaleRequest {
  SaleRequest({
    required this.id,
    required Map<String, int> quantities,
    required this.paymentMode,
    this.tendered,
    Map<String, String> customer = const {},
  }) : quantities = Map.unmodifiable(quantities),
       customer = Map.unmodifiable(customer);
  final String id;
  final Map<String, int> quantities;
  final PaymentMode paymentMode;
  final int? tendered;
  final Map<String, String> customer;

  Map<String, Object?> toJson() => {
    'quantities': quantities,
    'payment_mode': paymentMode.name,
    'tendered': tendered,
    'customer': customer,
  };
}

class SyncStatus {
  const SyncStatus({
    this.pending = 0,
    this.lastSyncAt,
    this.errorCode,
    this.attempts = 0,
    this.nextAttemptAt,
  });
  final int pending, attempts;
  final String? lastSyncAt, errorCode, nextAttemptAt;
}

/// Operator-facing explanation of a sync error code (HTTP status and the
/// server's technical code). Data always stays on the terminal.
String syncErrorLabel(String code) {
  final status = code.split(':').first;
  final detail = code.contains(':') ? code.split(':').last : '';
  final text = switch (status) {
    'HTTP_401' => switch (detail) {
      'CREDENTIAL_REVOKED' || 'CREDENTIAL_EXPIRED' =>
        'Terminal désactivé côté serveur : réactivez-le avec un nouveau code.',
      _ => 'Accès refusé : réactivez le terminal avec un nouveau code.',
    },
    'HTTP_403' =>
      detail == 'ADMIN_REQUIRED'
          ? 'Opération réservée à un administrateur côté serveur.'
          : 'Terminal ou utilisateur non autorisé par le serveur.',
    'HTTP_409' => 'Opération refusée par le serveur (incohérence).',
    'HTTP_422' => 'Données refusées par le serveur.',
    'HTTP_413' => 'Opération trop volumineuse.',
    'INVALID_ACK' => 'Réponse du serveur invalide.',
    'HTTP_503' when detail == 'AUTH_NOT_CONFIGURED' =>
      'Serveur pas encore configuré pour l’activation.',
    _ when status.startsWith('HTTP_5') => 'Serveur momentanément indisponible.',
    _ => 'Réseau ou serveur injoignable.',
  };
  return detail.isEmpty ? text : '$text ($detail)';
}

/// Return or full cancellation of a recorded sale. [id] is the operation
/// UUID: a repeated request with the same content refunds only once.
class ReturnRequest {
  ReturnRequest({
    required this.id,
    required this.saleId,
    required Map<String, ({int quantity, bool resaleable})> lines,
    required this.refundMode,
    required this.reason,
    this.cancel = false,
  }) : lines = Map.unmodifiable(lines);
  final String id, saleId, reason;
  final Map<String, ({int quantity, bool resaleable})> lines;
  final PaymentMode refundMode;

  /// Cancels every quantity not returned yet; [lines] then only carries the
  /// resaleable flags.
  final bool cancel;

  Map<String, Object?> toJson() => {
    'sale_id': saleId,
    'cancel': cancel,
    'refund_mode': refundMode.name,
    'reason': reason.trim(),
    'lines': {
      for (final e in lines.entries)
        e.key: {'quantity': e.value.quantity, 'resaleable': e.value.resaleable},
    },
  };
}

/// Customer fields of a sale (§7). Each one can be made mandatory by the
/// administrator; all are optional by default.
const customerFields = {
  'name': 'Nom',
  'first_name': 'Prénoms',
  'unit': 'Unité',
  'phone': 'Téléphone',
};

/// Settings key holding the mandatory fields, comma separated.
const customerRequiredKey = 'customer_required';

final _phone = RegExp(r'^\+?[0-9 ]{8,20}$');

void validateCustomer(Map<String, String> customer, Set<String> required) {
  for (final field in required) {
    if ((customer[field] ?? '').trim().isEmpty) {
      throw BusinessException(
        'Information client obligatoire : ${customerFields[field]}.',
      );
    }
  }
  final phone = (customer['phone'] ?? '').trim();
  if (phone.isNotEmpty &&
      (!_phone.hasMatch(phone) ||
          phone.replaceAll(RegExp(r'[^0-9]'), '').length < 8 ||
          phone.replaceAll(RegExp(r'[^0-9]'), '').length > 15)) {
    throw const BusinessException(
      'Téléphone invalide : 8 à 15 chiffres (le « + » et les espaces sont acceptés).',
    );
  }
}

Object? canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: canonical(value[key])};
  }
  if (value is List) return value.map(canonical).toList();
  return value;
}

String fingerprint(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(canonical(value)))).toString();

int moneyInput(String value) {
  if (!RegExp(r'^\d{1,13}$').hasMatch(value.trim())) {
    throw const BusinessException(
      'Saisissez un montant entier en FCFA, sans décimales.',
    );
  }
  final amount = int.parse(value.trim());
  if (amount > maxMoney) throw const BusinessException('Montant trop élevé.');
  return amount;
}

/// Customer format `FACT-<year>-<sequence>` (receipt annex). The sequence is the
/// terminal's persistent sale counter and never restarts, so numbers stay
/// unique across years; the operation UUID remains the technical identity.
String saleNumber(int year, int sequence) =>
    'FACT-$year-${sequence.toString().padLeft(5, '0')}';

String fcfa(int amount) =>
    '${amount.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ')} FCFA';

String abidjanDate(String iso) {
  // Africa/Abidjan is UTC+00, without DST for all dates accepted by this V1.
  final d = DateTime.parse(iso).toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}
