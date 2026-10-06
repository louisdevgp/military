import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/pos_controller.dart';
import '../domain/models.dart';
import 'mono_theme.dart';
import 'variant_matrix.dart';

/// Administrator: new colours or sizes received for an existing article.
class AddVariantsScreen extends ConsumerStatefulWidget {
  const AddVariantsScreen(this.variants, {super.key});
  final List<CatalogItem> variants;
  @override
  ConsumerState<AddVariantsScreen> createState() => _AddVariantsScreenState();
}

class _AddVariantsScreenState extends ConsumerState<AddVariantsScreen> {
  late final CatalogItem _first = widget.variants.first;
  late final _matrix = VariantMatrixController(_guessGrid());
  late final _reference = TextEditingController(text: _guessReference());
  late final _price = TextEditingController(text: '${_first.price}');
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final color in {
      for (final v in widget.variants)
        if (v.color != null) v.color!,
    }) {
      _matrix.addColor(color);
    }
  }

  SizeGrid _guessGrid() {
    final sizes = {for (final v in widget.variants) v.size};
    return sizes.every(SizeGrid.shoes.sizes.contains)
        ? SizeGrid.shoes
        : SizeGrid.clothing;
  }

  /// RAN-NOIR-42 with colour Noir and size 42 → RAN.
  String _guessReference() {
    final v = _first;
    var sku = v.sku;
    if (v.size != null && sku.endsWith('-${v.size}')) {
      sku = sku.substring(0, sku.length - v.size!.length - 1);
    }
    final code = v.color == null ? '' : colorCode(v.color!);
    if (code.isNotEmpty && sku.endsWith('-$code')) {
      sku = sku.substring(0, sku.length - code.length - 1);
    }
    return sku;
  }

  Set<(String, String)> get _existing => {
    for (final v in widget.variants)
      if (v.size != null) (v.color ?? '', v.size!),
  };

  @override
  void dispose() {
    _matrix.dispose();
    _reference.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _working = true;
      _error = null;
    });
    final ok = await ref
        .read(posProvider.notifier)
        .addVariants(
          productId: _first.productId,
          grid: _matrix.grid,
          reference: _reference.text,
          colors: List.of(_matrix.colors),
          price: _price.text,
          stock: _matrix.stock,
        );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() {
        _working = false;
        _error = ref.read(posProvider).message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Variantes · ${_first.name}')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const InlineNotice(
            'Ajoutez seulement ce qui est réellement arrivé en boutique. Les variantes existantes ne changent pas.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              for (final grid in [SizeGrid.clothing, SizeGrid.shoes])
                ChoiceChip(
                  label: Text(grid.title),
                  selected: _matrix.grid == grid,
                  onSelected: _working
                      ? null
                      : (_) => setState(() => _matrix.setGrid(grid)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reference,
            enabled: !_working,
            decoration: const InputDecoration(labelText: 'Référence de base'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _price,
            enabled: !_working,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Prix des nouvelles variantes FCFA',
            ),
          ),
          const SizedBox(height: 16),
          VariantMatrixEditor(
            controller: _matrix,
            enabled: !_working,
            existing: _existing,
            suggestions: {
              for (final i in ref.read(posProvider).items)
                if (i.color != null) i.color!,
            }.toList()..sort(),
          ),
          if (_error != null) ...[
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
          onPressed: _working ? null : _save,
          icon: const Icon(Icons.check),
          label: Text(_working ? 'Enregistrement…' : 'Ajouter les variantes'),
        ),
      ),
    ),
  );
}
