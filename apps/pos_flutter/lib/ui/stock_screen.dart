import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/pos_controller.dart';
import '../domain/models.dart';
import 'mono_theme.dart';

/// Administrator stock management: receptions, losses, corrections,
/// thresholds, deactivation, history and inventory.
class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key});
  @override
  ConsumerState<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends ConsumerState<StockScreen> {
  List<CatalogItem> _items = const [];
  String _search = '';
  bool _lowOnly = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_reload);
  }

  Future<void> _reload() async {
    final items = await ref.read(repositoryProvider).inventory();
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  String _status(CatalogItem v) => !v.active
      ? 'désactivée'
      : v.stock == 0
      ? 'épuisée'
      : v.lowStock
      ? 'stock faible'
      : '';

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(posProvider).busy;
    final query = _search.trim().toLowerCase();
    final shown = [
      for (final v in _items)
        if ((!_lowOnly || v.lowStock || (v.active && v.stock == 0)) &&
            '${v.name} ${v.label} ${v.sku}'.toLowerCase().contains(query))
          v,
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock'),
        actions: [
          TextButton.icon(
            onPressed: busy
                ? null
                : () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const InventoryScreen(),
                      ),
                    );
                    await _reload();
                  },
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Inventaire'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                TextField(
                  onChanged: (v) => setState(() => _search = v),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Article, variante ou référence',
                  ),
                ),
                const SizedBox(height: 8),
                FilterChip(
                  label: Text(
                    'Stock faible ou épuisé (${_items.where((v) => v.lowStock || (v.active && v.stock == 0)).length})',
                  ),
                  selected: _lowOnly,
                  onSelected: (on) => setState(() => _lowOnly = on),
                ),
                const SizedBox(height: 8),
                if (shown.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Aucune variante.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                for (final v in shown)
                  Card(
                    child: ListTile(
                      title: Text('${v.name} · ${v.label}'),
                      subtitle: Text(
                        [
                          v.sku,
                          if (v.threshold > 0) 'seuil ${v.threshold}',
                          if (_status(v).isNotEmpty) _status(v),
                        ].join(' · '),
                        style: TextStyle(
                          color: !v.active || v.stock == 0 || v.lowStock
                              ? Colors.red.shade800
                              : null,
                        ),
                      ),
                      trailing: Text(
                        '${v.stock}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      onTap: busy ? null : () => _actions(v),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _actions(CatalogItem v) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: FutureBuilder<List<StockMovementView>>(
            future: ref.read(repositoryProvider).movements(v.id),
            builder: (context, snapshot) => ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Text(
                  '${v.name} · ${v.label}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text('${v.sku} · stock ${v.stock}'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final kind in StockKind.values)
                      OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _move(v, kind);
                        },
                        child: Text(kind.label),
                      ),
                    OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _threshold(v);
                      },
                      child: const Text('Seuil d’alerte'),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        await ref
                            .read(posProvider.notifier)
                            .updateVariant(v.id, active: !v.active);
                        await _reload();
                      },
                      child: Text(v.active ? 'Désactiver' : 'Réactiver'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const SectionLabel('Historique'),
                if (!snapshot.hasData)
                  const LinearProgressIndicator(minHeight: 2)
                else if (snapshot.data!.isEmpty)
                  const Text('Aucun mouvement.')
                else
                  for (final m in snapshot.data!)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${_kindLabel(m.kind)} ${m.quantity > 0 ? '+' : ''}${m.quantity}'
                        '${m.counted == null ? '' : ' (compté ${m.counted})'}',
                      ),
                      subtitle: Text(
                        '${abidjanDate(m.occurredAt)} · ${m.actor} · ${m.reason}',
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _kindLabel(String code) => switch (code) {
    'INITIAL' => 'Stock initial',
    'RECEPTION' => 'Réception',
    'SALE' => 'Vente',
    'RETURN' => 'Retour',
    'LOSS' => 'Perte',
    'ADJUSTMENT' => 'Correction',
    'REVERSAL' => 'Annulation',
    _ => code,
  };

  Future<void> _move(CatalogItem v, StockKind kind) async {
    final qty = TextEditingController();
    final reason = TextEditingController(
      text: kind == StockKind.reception ? 'Réception fournisseur' : '',
    );
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${kind.label} · ${v.label}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Stock actuel : ${v.stock}'),
            TextField(
              controller: qty,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              decoration: InputDecoration(
                labelText: kind == StockKind.adjustment
                    ? 'Quantité (+ ou −, ex. -2)'
                    : 'Quantité',
              ),
            ),
            TextField(
              controller: reason,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Motif (obligatoire)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () async {
              final ok = await ref
                  .read(posProvider.notifier)
                  .moveStock(v.id, kind, qty.text, reason.text);
              if (ok && context.mounted) Navigator.pop(context);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    // Let the dialog finish closing before releasing its fields.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    qty.dispose();
    reason.dispose();
    await _reload();
  }

  Future<void> _threshold(CatalogItem v) async {
    final level = TextEditingController(text: '${v.threshold}');
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Seuil d’alerte · ${v.label}'),
        content: TextField(
          controller: level,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Alerte quand le stock atteint (0 = aucune)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () async {
              final ok = await ref
                  .read(posProvider.notifier)
                  .updateVariant(v.id, threshold: level.text);
              if (ok && context.mounted) Navigator.pop(context);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    // Let the dialog finish closing before releasing its fields.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    level.dispose();
    await _reload();
  }
}

/// Counted quantities for active variants; only filled fields are counted.
class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});
  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  List<CatalogItem> _items = const [];
  final _counts = <String, TextEditingController>{};
  final _reason = TextEditingController(text: 'Inventaire');

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final items = await ref.read(repositoryProvider).inventory();
      if (mounted) {
        setState(
          () => _items = [
            for (final i in items)
              if (i.active) i,
          ],
        );
      }
    });
  }

  @override
  void dispose() {
    for (final c in [..._counts.values, _reason]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(posProvider).busy;
    return Scaffold(
      appBar: AppBar(title: const Text('Inventaire')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const InlineNotice(
            'Saisissez la quantité réellement comptée. Champ vide = non compté. Chaque écart crée une correction tracée avec la quantité comptée.',
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(labelText: 'Motif'),
          ),
          const SizedBox(height: 8),
          for (final v in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${v.name} · ${v.label}\nAttendu : ${v.stock}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  SizedBox(
                    width: 88,
                    child: TextField(
                      controller: _counts.putIfAbsent(
                        v.id,
                        TextEditingController.new,
                      ),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Compté',
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: FilledButton.icon(
            onPressed: busy
                ? null
                : () async {
                    final ok = await ref
                        .read(posProvider.notifier)
                        .countInventory({
                          for (final e in _counts.entries) e.key: e.value.text,
                        }, _reason.text);
                    if (ok && context.mounted) Navigator.pop(context);
                  },
            icon: const Icon(Icons.check),
            label: const Text('Enregistrer l’inventaire'),
          ),
        ),
      ),
    );
  }
}
