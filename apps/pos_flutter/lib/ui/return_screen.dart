import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../application/pos_controller.dart';
import '../domain/models.dart';
import 'mono_theme.dart';

/// Administrator: partial return or full cancellation of a recorded sale.
class ReturnScreen extends ConsumerStatefulWidget {
  const ReturnScreen(this.sale, {super.key});
  final Map<String, dynamic> sale;
  @override
  ConsumerState<ReturnScreen> createState() => _ReturnScreenState();
}

class _ReturnScreenState extends ConsumerState<ReturnScreen> {
  // Kept for the whole visit: a retry after an unconfirmed result reuses it.
  final _returnId = const Uuid().v4();
  final _cancelId = const Uuid().v4();
  final _reason = TextEditingController();
  late final Map<String, int> _returned = {
    for (final e
        in ((widget.sale['returns'] as Map?)?['quantities'] as Map? ?? {})
            .entries)
      e.key as String: e.value as int,
  };
  final _quantities = <String, int>{};
  final _resaleable = <String, bool>{};
  late PaymentMode _mode = PaymentMode.values.byName(
    ((widget.sale['correction'] ?? widget.sale) as Map)['payment_mode']
        as String,
  );

  List<Map<String, dynamic>> get _lines => [
    for (final l in widget.sale['lines'] as List) l as Map<String, dynamic>,
  ];

  int _left(Map<String, dynamic> line) =>
      (line['quantity'] as int) - (_returned[line['variant_id']] ?? 0);

  int get _refund => _lines.fold(
    0,
    (sum, l) =>
        sum + (_quantities[l['variant_id']] ?? 0) * (l['unit_price'] as int),
  );

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Map<String, ({int quantity, bool resaleable})> _selection({
    bool all = false,
  }) => {
    for (final l in _lines)
      if (all || (_quantities[l['variant_id']] ?? 0) > 0)
        l['variant_id'] as String: (
          quantity: all ? _left(l) : _quantities[l['variant_id']]!,
          resaleable: _resaleable[l['variant_id']] ?? true,
        ),
  };

  Future<void> _submit({required bool cancel}) async {
    if (cancel) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Annuler toute la vente ?'),
          content: Text(
            'Tous les articles non encore rendus seront remboursés '
            '(${fcfa(_lines.fold(0, (s, l) => s + _left(l) * (l['unit_price'] as int)))}). '
            'La vente reste dans l’historique.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Non'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Oui, annuler'),
            ),
          ],
        ),
      );
      if (sure != true) return;
    }
    final ok = await ref
        .read(posProvider.notifier)
        .returnSale(
          ReturnRequest(
            id: cancel ? _cancelId : _returnId,
            saleId: widget.sale['id'] as String,
            lines: _selection(all: cancel),
            refundMode: _mode,
            reason: _reason.text,
            cancel: cancel,
          ),
        );
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(posProvider).busy;
    final anyLeft = _lines.any((l) => _left(l) > 0);
    return Scaffold(
      appBar: AppBar(title: Text('Retour · ${widget.sale['number']}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const InlineNotice(
            'La vente n’est jamais modifiée : le retour est une opération liée, tracée avec votre nom, la date et le motif.',
          ),
          const SizedBox(height: 12),
          for (final line in _lines)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${line['name']} · ${line['label']}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'Vendu : ${line['quantity']} × ${fcfa(line['unit_price'] as int)} · déjà rendu : ${_returned[line['variant_id']] ?? 0}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: MonoColors.muted,
                      ),
                    ),
                    if (_left(line) > 0)
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Moins',
                            onPressed:
                                busy ||
                                    (_quantities[line['variant_id']] ?? 0) == 0
                                ? null
                                : () => setState(
                                    () => _quantities[line['variant_id']] =
                                        _quantities[line['variant_id']]! - 1,
                                  ),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text(
                            '${_quantities[line['variant_id']] ?? 0} / ${_left(line)}',
                            style: const TextStyle(fontSize: 16),
                          ),
                          IconButton(
                            tooltip: 'Plus',
                            onPressed:
                                busy ||
                                    (_quantities[line['variant_id']] ?? 0) >=
                                        _left(line)
                                ? null
                                : () => setState(
                                    () => _quantities[line['variant_id']] =
                                        (_quantities[line['variant_id']] ?? 0) +
                                        1,
                                  ),
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                    if (_left(line) > 0)
                      ChoiceChip(
                        label: Text(
                          (_resaleable[line['variant_id']] ?? true)
                              ? 'Revendable'
                              : 'Endommagé',
                        ),
                        selected: !(_resaleable[line['variant_id']] ?? true),
                        onSelected: busy
                            ? null
                            : (_) => setState(
                                () =>
                                    _resaleable[line['variant_id'] as String] =
                                        !(_resaleable[line['variant_id']] ??
                                            true),
                              ),
                      ),
                    if (_left(line) <= 0) const Text('Entièrement rendu.'),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          const SectionLabel('Remboursement'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in PaymentMode.values)
                ChoiceChip(
                  label: Text(m.label),
                  selected: m == _mode,
                  onSelected: busy ? null : (_) => setState(() => _mode = m),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _reason,
            enabled: !busy,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'Motif (obligatoire)'),
          ),
          Text(
            'À rembourser pour la sélection : ${fcfa(_refund)}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Revendable : remis en stock. Endommagé : non remis en vente.',
            style: TextStyle(fontSize: 12, color: MonoColors.muted),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy || !anyLeft
                      ? null
                      : () => _submit(cancel: true),
                  child: const Text('Annuler la vente'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: busy || _refund == 0
                      ? null
                      : () => _submit(cancel: false),
                  child: const Text('Rembourser'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
