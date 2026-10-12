import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/pos_controller.dart';
import '../domain/models.dart';
import 'mono_theme.dart';

class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});
  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  PaymentMode _mode = PaymentMode.cash;
  final _cash = TextEditingController();
  final _customer = {
    for (final key in ['name', 'first_name', 'unit', 'phone'])
      key: TextEditingController(),
  };
  String? _error;
  bool _submitted = false;
  bool _completed = false;

  @override
  void dispose() {
    _cash.dispose();
    for (final controller in _customer.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Second look at an unusual change before the sale is recorded.
  Future<bool> _confirmChange(int total) async {
    final preview = previewCash(total, _cash.text);
    if (_mode != PaymentMode.cash ||
        preview == null ||
        !needsChangeConfirmation(total, preview.tendered)) {
      return true;
    }
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Vérifiez la somme remise'),
            content: Text(
              'Total : ${fcfa(total)}\n'
              'Somme remise : ${fcfa(preview.tendered)}\n'
              'Monnaie à rendre : ${fcfa(preview.change)}\n\n'
              'Le client a-t-il bien remis cette somme ?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Corriger'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirmer'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _pay() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!await _confirmChange(ref.read(posProvider).total)) return;
    if (!mounted) return;
    final ok = await ref.read(posProvider.notifier).pay(_mode, _cash.text, {
      for (final e in _customer.entries) e.key: e.value.text.trim(),
    });
    if (!mounted) return;
    if (ok) {
      setState(() => _completed = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, true);
      });
    } else {
      setState(() {
        _submitted = true;
        _error = ref.read(posProvider).message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(posProvider);
    final preview = previewCash(state.total, _cash.text);
    final busy = state.busy || _completed;
    return PopScope(
      canPop: !state.busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Encaisser'),
          leading: IconButton(
            tooltip: 'Retour au panier',
            onPressed: busy ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: MonoColors.ink,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TOTAL À ENCAISSER',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.8,
                        color: MonoColors.gold,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      fcfa(state.total),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${state.cartQuantity} article(s) · Paiement intégral',
                      style: const TextStyle(
                        color: Color(0xFFC1CFC3),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              const SectionLabel('Mode de paiement'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final mode in PaymentMode.values)
                    ChoiceChip(
                      avatar: Icon(switch (mode) {
                        PaymentMode.cash => Icons.payments_outlined,
                        PaymentMode.mobileMoney => Icons.phone_android,
                        PaymentMode.transfer => Icons.account_balance_outlined,
                        PaymentMode.other => Icons.more_horiz,
                      }, size: 18),
                      label: Text(mode.label),
                      selected: mode == _mode,
                      onSelected: busy
                          ? null
                          : (_) => setState(() {
                              _mode = mode;
                              _error = null;
                            }),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              if (_mode == PaymentMode.cash) ...[
                TextField(
                  controller: _cash,
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  maxLength: 13,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Somme remise FCFA',
                    counterText: '',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final amount in quickTenders(state.total))
                      ActionChip(
                        label: Text(
                          amount == state.total
                              ? 'Montant exact'
                              : fcfa(amount),
                        ),
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                _cash.text = '$amount';
                                _error = null;
                              }),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: MonoColors.pale,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Expanded(child: Text('Monnaie à rendre')),
                      Flexible(
                        child: Text(
                          preview == null ? '—' : fcfa(preview.change),
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: MonoColors.green,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else
                const InlineNotice(
                  'Vérifiez que le paiement a été reçu. L’application enregistre votre déclaration sans débiter le client.',
                ),
              const SizedBox(height: 20),
              Card(
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  title: const Text(
                    'Informations client',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  initiallyExpanded: state.customerRequired.isNotEmpty,
                  subtitle: Text(
                    state.customerRequired.isEmpty
                        ? 'Facultatif'
                        : '* obligatoire',
                    style: const TextStyle(
                      fontSize: 12,
                      color: MonoColors.muted,
                    ),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  children: [
                    for (final field in _customer.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextField(
                          controller: field.value,
                          enabled: !busy,
                          maxLength: 120,
                          keyboardType: field.key == 'phone'
                              ? TextInputType.phone
                              : TextInputType.text,
                          decoration: InputDecoration(
                            counterText: '',
                            labelText:
                                '${customerFields[field.key]}'
                                '${state.customerRequired.contains(field.key) ? ' *' : ''}',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              InlineNotice(
                'Mode recette · ${ref.read(printerProvider).label}. Vérifiez le ticket après validation.',
              ),
              if (_submitted && _error != null) ...[
                const SizedBox(height: 12),
                InlineNotice(_error!, error: true),
              ],
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: FilledButton.icon(
              onPressed: busy ? null : _pay,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(busy ? 'Validation…' : 'Valider la vente'),
            ),
          ),
        ),
      ),
    );
  }
}
