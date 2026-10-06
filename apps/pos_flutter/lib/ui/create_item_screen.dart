import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/pos_controller.dart';
import '../domain/models.dart';
import 'mono_theme.dart';
import 'variant_matrix.dart';

class CreateItemScreen extends ConsumerStatefulWidget {
  const CreateItemScreen({super.key});
  @override
  ConsumerState<CreateItemScreen> createState() => _CreateItemScreenState();
}

class _CreateItemScreenState extends ConsumerState<CreateItemScreen> {
  final _form = GlobalKey<FormState>();
  final _fields = {
    for (final key in [
      'category',
      'name',
      'sku',
      'label',
      'price',
      'stock',
      'reference',
    ])
      key: TextEditingController(),
  };
  SizeGrid _grid = SizeGrid.single;
  final _matrix = VariantMatrixController(SizeGrid.clothing);
  final _photos = <String>[];
  bool _working = false;
  bool _allowPop = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    _matrix.dispose();
    super.dispose();
  }

  void _pop(bool saved) {
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, saved);
    });
  }

  Future<void> _cancel() async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      for (final path in List<String>.from(_photos)) {
        await ref.read(photoProvider).discardDraft(path);
        _photos.remove(path);
      }
      if (mounted) _pop(false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _working = false;
          _error = 'Une photo provisoire n’a pas pu être supprimée. Réessayez de fermer la fiche.';
        });
      }
    }
  }

  Future<void> _choosePhoto() async {
    if (_working || _photos.length >= 3) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final path = await ref.read(photoProvider).choosePhoto();
      if (mounted && path != null) _photos.add(path);
    } on PlatformException catch (e) {
      if (mounted) {
        _error = e.message ?? 'Cette photo ne peut pas être ajoutée.';
      }
    } catch (_) {
      if (mounted) {
        _error = 'La sélection de photo est indisponible. Réessayez.';
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _removePhoto(String path) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await ref.read(photoProvider).discardDraft(path);
      if (mounted) _photos.remove(path);
    } catch (_) {
      if (mounted) _error = 'La photo n’a pas pu être retirée. Réessayez.';
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _save() async {
    if (_working || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _working = true;
      _error = null;
    });
    final controller = ref.read(posProvider.notifier);
    final ok = _grid == SizeGrid.single
        ? await controller.createItem(
            category: _fields['category']!.text,
            name: _fields['name']!.text,
            sku: _fields['sku']!.text,
            label: _fields['label']!.text,
            price: _fields['price']!.text,
            stock: _fields['stock']!.text,
            photoPaths: List.of(_photos),
          )
        : await controller.createMatrixItem(
            category: _fields['category']!.text,
            name: _fields['name']!.text,
            grid: _grid,
            reference: _fields['reference']!.text,
            colors: List.of(_matrix.colors),
            price: _fields['price']!.text,
            stock: _matrix.stock,
            photoPaths: List.of(_photos),
          );
    if (!mounted) return;
    if (ok) {
      _pop(true);
    } else {
      setState(() {
        _working = false;
        _error = ref.read(posProvider).message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _cancel();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Annuler la création',
          onPressed: _working ? null : _cancel,
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Nouvel article'),
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              const SectionLabel(
                'Présentez votre article',
                subtitle:
                    'Des photos claires pour le reconnaître en un instant.',
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        children: [
                          AspectRatio(
                            aspectRatio: 0.92,
                            child: i < _photos.length
                                ? Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      ProductPhoto(path: _photos[i]),
                                      Positioned(
                                        right: 3,
                                        top: 3,
                                        child: IconButton.filled(
                                          tooltip: 'Retirer la photo ${i + 1}',
                                          onPressed: _working
                                              ? null
                                              : () => _removePhoto(_photos[i]),
                                          style: IconButton.styleFrom(
                                            backgroundColor: MonoColors.ink
                                                .withValues(alpha: 0.8),
                                            minimumSize: const Size(36, 36),
                                          ),
                                          icon: const Icon(
                                            Icons.close,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : Material(
                                    color: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      side: const BorderSide(
                                        color: MonoColors.line,
                                      ),
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: _working ? null : _choosePhoto,
                                      child: const Center(
                                        child: Icon(
                                          Icons.add_photo_alternate_outlined,
                                          color: MonoColors.green,
                                          size: 30,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            i == 0 ? 'Couverture' : 'Photo ${i + 1}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Jusqu’à 3 photos · JPEG, PNG ou WebP · 12 Mo maximum par fichier',
                style: TextStyle(fontSize: 12, color: MonoColors.muted),
              ),
              const SizedBox(height: 28),
              const SectionLabel('L’essentiel'),
              _field('name', 'Nom de l’article', hint: 'Ex. Rangers noirs'),
              _field('category', 'Catégorie', hint: 'Ex. Chaussures'),
              const SizedBox(height: 4),
              const SectionLabel('Tailles'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final grid in SizeGrid.values)
                    ChoiceChip(
                      label: Text(grid.title),
                      selected: grid == _grid,
                      onSelected: _working
                          ? null
                          : (_) => setState(() {
                              _grid = grid;
                              if (grid != SizeGrid.single) {
                                _matrix.setGrid(grid);
                              }
                            }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (_grid == SizeGrid.single) ...[
                _field('sku', 'Référence unique', hint: 'Ex. RAN-NOIR-42'),
                _field(
                  'label',
                  'Variante · taille, couleur, pointure',
                  hint: 'Ex. Noir · Pointure 42',
                ),
                const SizedBox(height: 12),
                const SectionLabel('Prix et disponibilité'),
                _field('price', 'Prix de vente FCFA', number: true),
                _field('stock', 'Stock initial', number: true),
              ] else ...[
                _field(
                  'reference',
                  'Référence de base',
                  hint: 'Ex. RAN, puis RAN-NOIR-42',
                ),
                _field('price', 'Prix de vente FCFA', number: true),
                const Text(
                  'Prix commun à la création ; ajustable ensuite par variante avec « Modifier le prix ».',
                  style: TextStyle(fontSize: 12, color: MonoColors.muted),
                ),
                const SizedBox(height: 16),
                VariantMatrixEditor(
                  controller: _matrix,
                  enabled: !_working,
                  suggestions: {
                    for (final i in ref.read(posProvider).items)
                      if (i.color != null) i.color!,
                  }.toList()..sort(),
                ),
                const SizedBox(height: 12),
              ],
              const InlineNotice(
                'Les photos sont conservées sur ce TPE. Leur sauvegarde et leur publication sur le site ne sont pas encore disponibles.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                InlineNotice(_error!, error: true),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: FilledButton.icon(
            onPressed: _working ? null : _save,
            icon: _working
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(_working ? 'Enregistrement…' : 'Enregistrer l’article'),
          ),
        ),
      ),
    ),
  );

  Widget _field(
    String key,
    String label, {
    String? hint,
    bool number = false,
    bool optional = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: _fields[key],
      enabled: !_working,
      maxLength: number ? 13 : 120,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      textCapitalization: number
          ? TextCapitalization.none
          : TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
      ),
      validator: (value) => !optional && (value == null || value.trim().isEmpty)
          ? 'Ce champ est requis.'
          : null,
    ),
  );
}
