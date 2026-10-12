import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/pos_controller.dart';
import '../domain/finance.dart';
import '../domain/models.dart';
import 'mono_theme.dart';

String _mode(String name) =>
    PaymentMode.values.asNameMap()[name]?.label ?? name;

/// Administrator: expenses of the month, new expense, traced cancellation.
class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});
  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  ReportPeriod _period = ReportPeriod.month(DateTime.now());
  List<ExpenseView> _items = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_reload);
  }

  Future<void> _reload() async {
    final items = await ref.read(financeRepositoryProvider).expenses(_period);
    if (mounted) setState(() => _items = items);
  }

  void _shift(int months) {
    final s = _period.start;
    setState(
      () =>
          _period = ReportPeriod.month(DateTime.utc(s.year, s.month + months)),
    );
    _reload();
  }

  Future<void> _add() async {
    final categories = await ref
        .read(financeRepositoryProvider)
        .expenseCategories();
    if (!mounted) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _ExpenseForm(categories)),
    );
    if (saved == true) await _reload();
  }

  Future<void> _cancel(ExpenseView e) async {
    final reason = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler la dépense'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${e.category} · ${fcfa(e.amount)}'),
            const Text(
              'La dépense reste visible, barrée, avec le motif.',
              style: TextStyle(fontSize: 12, color: MonoColors.muted),
            ),
            TextField(
              controller: reason,
              decoration: const InputDecoration(
                labelText: 'Motif (obligatoire)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Retour'),
          ),
          FilledButton(
            onPressed: () async {
              final ok = await ref
                  .read(posProvider.notifier)
                  .cancelExpense(e.id, reason.text);
              if (ok && context.mounted) Navigator.pop(context);
            },
            child: const Text('Annuler la dépense'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    reason.dispose();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(posProvider).busy;
    final total = _items
        .where((e) => !e.cancelled)
        .fold(0, (a, e) => a + e.amount);
    return Scaffold(
      appBar: AppBar(title: const Text('Dépenses')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: busy ? null : _add,
        icon: const Icon(Icons.add),
        label: const Text('Dépense'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Mois précédent',
                onPressed: () => _shift(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  _period.label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Mois suivant',
                onPressed: () => _shift(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Text('Total : ${fcfa(total)}', textAlign: TextAlign.center),
          const SizedBox(height: 8),
          if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Aucune dépense sur ce mois.',
                textAlign: TextAlign.center,
              ),
            ),
          for (final e in _items)
            Card(
              child: ListTile(
                title: Text(
                  '${e.category} · ${fcfa(e.amount)}',
                  style: TextStyle(
                    decoration: e.cancelled ? TextDecoration.lineThrough : null,
                  ),
                ),
                subtitle: Text(
                  '${e.kind.label} · ${_mode(e.paymentMode)} · ${abidjanDate(e.occurredAt)}\n'
                  '${e.reason} · ${e.actor}'
                  '${e.cancelled ? '\nAnnulée : ${e.cancelReason}' : ''}',
                ),
                isThreeLine: true,
                trailing: e.cancelled
                    ? null
                    : IconButton(
                        tooltip: 'Annuler la dépense',
                        onPressed: busy ? null : () => _cancel(e),
                        icon: const Icon(Icons.block),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ExpenseForm extends ConsumerStatefulWidget {
  const _ExpenseForm(this.categories);
  final List<String> categories;
  @override
  ConsumerState<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends ConsumerState<_ExpenseForm> {
  ExpenseKind _kind = ExpenseKind.charge;
  PaymentMode _mode = PaymentMode.cash;
  DateTime _date = DateTime.now();
  final _category = TextEditingController();
  final _amount = TextEditingController();
  final _reason = TextEditingController();

  @override
  void dispose() {
    for (final c in [_category, _amount, _reason]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(posProvider).busy;
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle dépense')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionLabel('Type'),
          Wrap(
            spacing: 6,
            children: [
              for (final k in ExpenseKind.values)
                ChoiceChip(
                  label: Text(k.label),
                  selected: k == _kind,
                  onSelected: (_) => setState(() => _kind = k),
                ),
            ],
          ),
          Text(
            _kind.hint,
            style: const TextStyle(fontSize: 12, color: MonoColors.muted),
          ),
          TextField(
            controller: _category,
            decoration: const InputDecoration(labelText: 'Catégorie'),
          ),
          if (widget.categories.isNotEmpty)
            Wrap(
              spacing: 6,
              children: [
                for (final c in widget.categories)
                  ActionChip(
                    label: Text(c),
                    onPressed: () => setState(() => _category.text = c),
                  ),
              ],
            ),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Montant FCFA'),
          ),
          TextField(
            controller: _reason,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'Motif'),
          ),
          const SectionLabel('Réglée en'),
          Wrap(
            spacing: 6,
            children: [
              for (final m in PaymentMode.values)
                ChoiceChip(
                  label: Text(m.label),
                  selected: m == _mode,
                  onSelected: (_) => setState(() => _mode = m),
                ),
            ],
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text('Date : ${ReportPeriod.day(_date).label}'),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                setState(
                  () => _date = DateTime.utc(
                    picked.year,
                    picked.month,
                    picked.day,
                    12,
                  ),
                );
              }
            },
          ),
          const Text(
            'Une dépense réglée en espèces diminue la caisse attendue à la clôture.',
            style: TextStyle(fontSize: 12, color: MonoColors.muted),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton(
            onPressed: busy
                ? null
                : () async {
                    final today = ReportPeriod.day(DateTime.now()).start;
                    final ok = await ref
                        .read(posProvider.notifier)
                        .recordExpense(
                          kind: _kind,
                          category: _category.text,
                          amount: _amount.text,
                          mode: _mode,
                          reason: _reason.text,
                          occurredAt: _date.isBefore(today) ? _date : null,
                        );
                    if (ok && context.mounted) Navigator.pop(context, true);
                  },
            child: const Text('Enregistrer'),
          ),
        ),
      ),
    );
  }
}

/// Administrator: expected cash since the previous closing, counted cash,
/// gap and the float kept for the next period.
class CashClosingScreen extends ConsumerStatefulWidget {
  const CashClosingScreen({super.key});
  @override
  ConsumerState<CashClosingScreen> createState() => _CashClosingScreenState();
}

class _CashClosingScreenState extends ConsumerState<CashClosingScreen> {
  CashPosition? _position;
  final _opening = TextEditingController();
  final _counted = TextEditingController();
  final _kept = TextEditingController();
  final _comment = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(_reload);
  }

  Future<void> _reload() async {
    final position = await ref.read(financeRepositoryProvider).cashPosition();
    if (mounted) setState(() => _position = position);
  }

  @override
  void dispose() {
    for (final c in [_opening, _counted, _kept, _comment]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _amount(TextEditingController c) => int.tryParse(c.text.trim());

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(posProvider).busy;
    final p = _position;
    if (p == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final opening = p.firstClosing ? (_amount(_opening) ?? 0) : p.openingFloat;
    final expected = opening + p.cashSales - p.cashRefunds - p.cashExpenses;
    final counted = _amount(_counted);
    Widget line(String label, int value, {bool bold = false}) => Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          fcfa(value),
          style: TextStyle(
            fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
          ),
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Clôture de caisse')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Depuis ${p.firstClosing ? 'le début' : 'la clôture du ${abidjanDate(p.periodStart)}'}',
            style: const TextStyle(color: MonoColors.muted),
          ),
          const SizedBox(height: 8),
          if (p.firstClosing)
            TextField(
              controller: _opening,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Fond de caisse au départ FCFA',
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  line('Fond de caisse', opening),
                  line('+ Ventes en espèces', p.cashSales),
                  line('− Remboursements en espèces', p.cashRefunds),
                  line('− Dépenses en espèces', p.cashExpenses),
                  const Divider(),
                  line('Espèces attendues', expected, bold: true),
                ],
              ),
            ),
          ),
          TextField(
            controller: _counted,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Espèces comptées FCFA',
            ),
          ),
          if (counted != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                counted == expected
                    ? 'Aucun écart.'
                    : 'Écart : ${counted > expected ? '+' : '−'}${fcfa((counted - expected).abs())}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: counted == expected
                      ? MonoColors.green
                      : Colors.red.shade800,
                ),
              ),
            ),
          TextField(
            controller: _kept,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Fond de caisse conservé pour demain FCFA',
            ),
          ),
          TextField(
            controller: _comment,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: 'Commentaire (obligatoire en cas d’écart)',
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton(
            onPressed: busy
                ? null
                : () async {
                    final result = await ref
                        .read(posProvider.notifier)
                        .closeCash(
                          counted: _counted.text,
                          keptFloat: _kept.text,
                          comment: _comment.text,
                          openingFloat: p.firstClosing ? _opening.text : null,
                        );
                    if (result != null && context.mounted) {
                      Navigator.pop(context);
                    }
                  },
            child: const Text('Clôturer la caisse'),
          ),
        ),
      ),
    );
  }
}

/// Reports by day, week, month, year or custom period (Africa/Abidjan).
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String _kind = 'day';
  ReportPeriod _period = ReportPeriod.day(DateTime.now());
  SalesReport? _report;

  @override
  void initState() {
    super.initState();
    Future.microtask(_reload);
  }

  Future<void> _reload() async {
    final report = await ref.read(financeRepositoryProvider).report(_period);
    if (mounted) setState(() => _report = report);
  }

  ReportPeriod _build(String kind, DateTime anchor) => switch (kind) {
    'week' => ReportPeriod.week(anchor),
    'month' => ReportPeriod.month(anchor),
    'year' => ReportPeriod.year(anchor),
    _ => ReportPeriod.day(anchor),
  };

  void _select(String kind) {
    setState(() {
      _kind = kind;
      _period = _build(kind, DateTime.now());
      _report = null;
    });
    _reload();
  }

  void _shift(int step) {
    final s = _period.start;
    final anchor = switch (_kind) {
      'week' => s.add(Duration(days: 7 * step)),
      'month' => DateTime.utc(s.year, s.month + step),
      'year' => DateTime.utc(s.year + step),
      _ => s.add(Duration(days: step)),
    };
    setState(() {
      _period = _build(_kind, anchor);
      _report = null;
    });
    _reload();
  }

  Future<void> _custom() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (range == null) return;
    setState(() {
      _kind = 'custom';
      _period = ReportPeriod.custom(range.start, range.end);
      _report = null;
    });
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    Widget line(String label, int value, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            fcfa(value),
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rapports'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Exporter en CSV',
            icon: const Icon(Icons.file_download_outlined),
            onSelected: (kind) =>
                ref.read(posProvider.notifier).exportCsv(kind, _period),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'summary', child: Text('Synthèse (CSV)')),
              PopupMenuItem(
                value: 'sales',
                child: Text('Lignes de vente (CSV)'),
              ),
              PopupMenuItem(value: 'expenses', child: Text('Dépenses (CSV)')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Wrap(
            spacing: 6,
            children: [
              for (final (k, label) in [
                ('day', 'Jour'),
                ('week', 'Semaine'),
                ('month', 'Mois'),
                ('year', 'Année'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _kind == k,
                  onSelected: (_) => _select(k),
                ),
              ChoiceChip(
                label: const Text('Période'),
                selected: _kind == 'custom',
                onSelected: (_) => _custom(),
              ),
            ],
          ),
          Row(
            children: [
              if (_kind != 'custom')
                IconButton(
                  tooltip: 'Précédent',
                  onPressed: () => _shift(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
              Expanded(
                child: Text(
                  _period.label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (_kind != 'custom')
                IconButton(
                  tooltip: 'Suivant',
                  onPressed: () => _shift(1),
                  icon: const Icon(Icons.chevron_right),
                ),
            ],
          ),
          if (r == null)
            const LinearProgressIndicator(minHeight: 2)
          else ...[
            const SectionLabel('Ventes'),
            line('Ventes brutes (${r.saleCount})', r.gross),
            line('− Retours et remboursements', r.refunds),
            line('Ventes nettes', r.net, bold: true),
            Text(
              'Articles vendus : ${r.quantity} · rendus : ${r.returnedQuantity} · net : ${r.netQuantity}',
            ),
            const SizedBox(height: 4),
            const InlineNotice(
              'Marge non calculable : les prix d’achat ne sont pas enregistrés. '
              'Les ventes moins les dépenses ne constituent pas un bénéfice.',
            ),
            const SectionLabel('Paiements'),
            for (final e in r.payments.entries) line(_mode(e.key), e.value),
            for (final e in r.refundsByMode.entries)
              line('Remboursé · ${_mode(e.key)}', -e.value),
            const SectionLabel('Par catégorie'),
            for (final e in r.byCategory.entries) line(e.key, e.value),
            const SectionLabel('Par variante'),
            for (final v in r.byVariant)
              line('${v.label} × ${v.quantity}', v.amount),
            const SectionLabel('Dépenses'),
            for (final k in ExpenseKind.values)
              line(k.label, r.expensesByKind[k] ?? 0),
            for (final e in r.expensesByCategory.entries)
              line('  ${e.key}', e.value),
            const SectionLabel('Caisse'),
            Text(
              '${r.closings} clôture(s), écart cumulé : ${r.closingGap >= 0 ? '+' : '−'}${fcfa(r.closingGap.abs())}',
            ),
            const SectionLabel('Stock actuel'),
            Text(
              '${r.stockUnits} articles en stock · valeur au prix de vente ${fcfa(r.stockValueAtPrice)}',
            ),
            for (final a in r.alerts)
              Text('⚠ $a', style: TextStyle(color: Colors.red.shade800)),
          ],
        ],
      ),
    );
  }
}
