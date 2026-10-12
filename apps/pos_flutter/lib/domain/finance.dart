/// Expenses, cash closing and reports. Amounts are integer FCFA. Business
/// periods use Africa/Abidjan, which is UTC+0 without daylight saving: day
/// bounds are UTC midnights. A period is [start, end).
library;

enum ExpenseKind {
  charge('CHARGE', 'Charge', 'Loyer, transport, salaires, électricité…'),
  stock('STOCK', 'Achat de stock', 'Marchandise achetée pour la revente'),
  treasury(
    'TREASURY',
    'Mouvement de trésorerie',
    'Retrait, dépôt en banque : ni charge ni achat',
  );

  const ExpenseKind(this.code, this.label, this.hint);
  final String code, label, hint;
  static ExpenseKind byCode(String code) =>
      values.firstWhere((k) => k.code == code);
}

class ExpenseView {
  const ExpenseView({
    required this.id,
    required this.kind,
    required this.category,
    required this.amount,
    required this.paymentMode,
    required this.reason,
    required this.occurredAt,
    required this.actor,
    this.cancelledAt,
    this.cancelReason,
  });
  final String id, category, paymentMode, reason, occurredAt, actor;
  final ExpenseKind kind;
  final int amount;
  final String? cancelledAt, cancelReason;
  bool get cancelled => cancelledAt != null;
}

/// Cash expected in the drawer since the previous closing.
class CashPosition {
  const CashPosition({
    required this.periodStart,
    required this.openingFloat,
    required this.cashSales,
    required this.cashRefunds,
    required this.cashExpenses,
    required this.firstClosing,
  });
  final String periodStart;
  final int openingFloat, cashSales, cashRefunds, cashExpenses;

  /// No previous closing: the opening float is typed by the administrator.
  final bool firstClosing;
  int get expected => openingFloat + cashSales - cashRefunds - cashExpenses;
}

class ReportPeriod {
  ReportPeriod(this.start, this.end, this.label) : assert(end.isAfter(start));
  final DateTime start, end;
  final String label;

  static DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);
  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _date(DateTime d) =>
      '${_two(d.day)}/${_two(d.month)}/${d.year}';

  factory ReportPeriod.day(DateTime anchor) {
    final start = _day(anchor.toUtc());
    return ReportPeriod(
      start,
      start.add(const Duration(days: 1)),
      _date(start),
    );
  }

  /// ISO week, Monday to Sunday.
  factory ReportPeriod.week(DateTime anchor) {
    final day = _day(anchor.toUtc());
    final start = day.subtract(Duration(days: day.weekday - 1));
    final end = start.add(const Duration(days: 7));
    return ReportPeriod(
      start,
      end,
      'Semaine du ${_date(start)} au ${_date(end.subtract(const Duration(days: 1)))}',
    );
  }

  factory ReportPeriod.month(DateTime anchor) {
    final a = anchor.toUtc();
    final start = DateTime.utc(a.year, a.month);
    const months = [
      'janvier',
      'février',
      'mars',
      'avril',
      'mai',
      'juin',
      'juillet',
      'août',
      'septembre',
      'octobre',
      'novembre',
      'décembre',
    ];
    return ReportPeriod(
      start,
      DateTime.utc(a.year, a.month + 1),
      '${months[a.month - 1]} ${a.year}',
    );
  }

  factory ReportPeriod.year(DateTime anchor) {
    final y = anchor.toUtc().year;
    return ReportPeriod(DateTime.utc(y), DateTime.utc(y + 1), 'Année $y');
  }

  /// Both days included.
  factory ReportPeriod.custom(DateTime from, DateTime to) {
    final start = _day(from.toUtc());
    final last = _day(to.toUtc());
    return ReportPeriod(
      start,
      last.add(const Duration(days: 1)),
      'Du ${_date(start)} au ${_date(last)}',
    );
  }

  String get startIso => start.toIso8601String();
  String get endIso => end.toIso8601String();
}

class VariantSales {
  const VariantSales(this.label, this.quantity, this.amount);
  final String label;
  final int quantity, amount;
}

/// Report figures. There is deliberately no « profit »: purchase costs are
/// not recorded, so the margin cannot be computed.
class SalesReport {
  const SalesReport({
    required this.period,
    required this.saleCount,
    required this.gross,
    required this.quantity,
    required this.refunds,
    required this.returnedQuantity,
    required this.byCategory,
    required this.byVariant,
    required this.payments,
    required this.refundsByMode,
    required this.expensesByKind,
    required this.expensesByCategory,
    required this.stockUnits,
    required this.stockValueAtPrice,
    required this.alerts,
    required this.closings,
    required this.closingGap,
  });
  final ReportPeriod period;
  final int saleCount, gross, quantity, refunds, returnedQuantity;
  final Map<String, int> byCategory, payments, refundsByMode;
  final List<VariantSales> byVariant;
  final Map<ExpenseKind, int> expensesByKind;
  final Map<String, int> expensesByCategory;
  final int stockUnits, stockValueAtPrice;
  final List<String> alerts;
  final int closings, closingGap;
  int get net => gross - refunds;
  int get netQuantity => quantity - returnedQuantity;
}

/// CSV for French spreadsheets: « ; » separator, UTF-8 byte order mark,
/// CRLF lines. Text starting with = + - @ is prefixed with « ' » so that a
/// typed value can never run as a spreadsheet formula.
String toCsv(List<List<Object?>> rows) {
  String cell(Object? value) {
    if (value == null) return '';
    var text = value.toString();
    if (value is String && RegExp(r'^[=+\-@\t\r]').hasMatch(text)) {
      text = "'$text";
    }
    if (text.contains(RegExp(r'[;"\n\r]'))) {
      text = '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }

  final body = rows.map((r) => r.map(cell).join(';')).join('\r\n');
  return '﻿$body\r\n';
}
