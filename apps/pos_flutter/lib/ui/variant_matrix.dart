import 'package:flutter/material.dart';

import '../domain/models.dart';
import 'mono_theme.dart';

/// Colours and real stock per colour × size, typed by the administrator.
class VariantMatrixController extends ChangeNotifier {
  VariantMatrixController(this.grid);
  SizeGrid grid;
  final colors = <String>[];
  final _cells = <(String, String), TextEditingController>{};

  TextEditingController cell(String color, String size) =>
      _cells.putIfAbsent((color, size), TextEditingController.new);

  void setGrid(SizeGrid next) {
    grid = next;
    notifyListeners();
  }

  /// Returns an error message, or null when the colour was added.
  String? addColor(String raw) {
    final color = normalizeColor(raw);
    if (color.isEmpty) return 'Saisissez une couleur.';
    if (color.length > 40) return 'Couleur trop longue (40 caractères).';
    if (colors.any((c) => c.toLowerCase() == color.toLowerCase())) {
      return 'Cette couleur est déjà dans la liste.';
    }
    if (colorCode(color).isEmpty) return 'Couleur sans lettre ni chiffre.';
    colors.add(color);
    notifyListeners();
    return null;
  }

  void removeColor(String color) {
    colors.remove(color);
    notifyListeners();
  }

  /// Typed quantities for the sections currently shown.
  Map<(String, String), String> get stock => {
    for (final color in colors.isEmpty ? [''] : colors)
      for (final size in grid.sizes) (color, size): cell(color, size).text,
  };

  @override
  void dispose() {
    for (final c in _cells.values) {
      c.dispose();
    }
    super.dispose();
  }
}

class VariantMatrixEditor extends StatefulWidget {
  const VariantMatrixEditor({
    super.key,
    required this.controller,
    this.suggestions = const [],
    this.existing = const {},
    this.enabled = true,
  });
  final VariantMatrixController controller;

  /// Colours already used in the catalogue, offered with one touch.
  final List<String> suggestions;

  /// Combinations that already exist (adding variants to an article).
  final Set<(String, String)> existing;
  final bool enabled;

  @override
  State<VariantMatrixEditor> createState() => _VariantMatrixEditorState();
}

class _VariantMatrixEditorState extends State<VariantMatrixEditor> {
  final _color = TextEditingController();
  String? _colorError;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _color.dispose();
    super.dispose();
  }

  void _add(String value) {
    final error = widget.controller.addColor(value);
    setState(() => _colorError = error);
    if (error == null) _color.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final offered = [
      for (final s in widget.suggestions)
        if (!c.colors.any((x) => x.toLowerCase() == s.toLowerCase())) s,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel(
          'Couleurs',
          subtitle: 'Facultatif. Ajoutez seulement les couleurs reçues.',
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _color,
                enabled: widget.enabled,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: _add,
                decoration: InputDecoration(
                  labelText: 'Nouvelle couleur',
                  hintText: 'Ex. Noir, Marron, Camouflage',
                  errorText: _colorError,
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: widget.enabled ? () => _add(_color.text) : null,
              child: const Text('Ajouter'),
            ),
          ],
        ),
        if (offered.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in offered)
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: Text(s),
                  onPressed: widget.enabled ? () => _add(s) : null,
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        const Text(
          'Stock réel par combinaison : case vide = n’existe pas en boutique, 0 = existe mais épuisé.',
          style: TextStyle(fontSize: 12, color: MonoColors.muted),
        ),
        const SizedBox(height: 8),
        for (final color in c.colors.isEmpty ? [''] : c.colors)
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          color.isEmpty ? 'Sans couleur' : color,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (color.isNotEmpty)
                        IconButton(
                          tooltip: 'Retirer $color',
                          onPressed: widget.enabled
                              ? () => c.removeColor(color)
                              : null,
                          icon: const Icon(Icons.close, size: 18),
                        ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final size in c.grid.sizes)
                        SizedBox(
                          width: 84,
                          child: widget.existing.contains((color, size))
                              ? InputDecorator(
                                  decoration: InputDecoration(
                                    labelText: size,
                                    isDense: true,
                                    enabled: false,
                                  ),
                                  child: const Text('existe'),
                                )
                              : TextField(
                                  controller: c.cell(color, size),
                                  enabled: widget.enabled,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: size,
                                    isDense: true,
                                  ),
                                ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
