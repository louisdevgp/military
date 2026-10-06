import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/pos_controller.dart';
import '../domain/models.dart';
import 'mono_theme.dart';

/// Administrator: add, remove or reorder an article's photos (cover first).
class EditPhotosScreen extends ConsumerStatefulWidget {
  const EditPhotosScreen(this.item, {super.key});
  final CatalogItem item;
  @override
  ConsumerState<EditPhotosScreen> createState() => _EditPhotosScreenState();
}

class _EditPhotosScreenState extends ConsumerState<EditPhotosScreen> {
  late final List<String> _photos = List.of(widget.item.photoPaths);

  /// Images picked during this visit; deleted if the change is abandoned.
  final _drafts = <String>{};
  bool _working = false;
  bool _allowPop = false;
  String? _error;

  void _close() {
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _discard(Iterable<String> paths) async {
    for (final path in List.of(paths)) {
      try {
        await ref.read(photoProvider).discardDraft(path);
      } catch (_) {
        // Orphan private file only; never block the operator.
      }
    }
  }

  Future<void> _cancel() async {
    if (_working) return;
    await _discard(_drafts);
    if (mounted) _close();
  }

  Future<void> _add() async {
    if (_photos.length >= 3) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final path = await ref.read(photoProvider).choosePhoto();
      if (path != null) {
        _drafts.add(path);
        _photos.add(path);
      }
    } on PlatformException catch (e) {
      _error = e.message ?? 'Cette photo ne peut pas être ajoutée.';
    } catch (_) {
      _error = 'La sélection de photo est indisponible. Réessayez.';
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _remove(String path) async {
    setState(() => _photos.remove(path));
    // A fresh, unsaved image can go now; saved ones are removed on save.
    if (_drafts.remove(path)) await _discard([path]);
  }

  Future<void> _save() async {
    setState(() {
      _working = true;
      _error = null;
    });
    final ok = await ref
        .read(posProvider.notifier)
        .updatePhotos(widget.item.productId, List.of(_photos));
    if (!mounted) return;
    if (ok) {
      _drafts.clear();
      _close();
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
          tooltip: 'Annuler',
          onPressed: _working ? null : _cancel,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text('Photos · ${widget.item.name}'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            const SectionLabel(
              'Photos de l’article',
              subtitle: 'La première est la couverture du catalogue. Touchez une photo pour la mettre en couverture.',
            ),
            for (var i = 0; i < _photos.length; i++)
              Card(
                child: ListTile(
                  leading: SizedBox(
                    width: 56,
                    height: 56,
                    child: ProductPhoto(path: _photos[i], radius: 10),
                  ),
                  title: Text(i == 0 ? 'Couverture' : 'Photo ${i + 1}'),
                  subtitle: i == 0
                      ? null
                      : const Text('Toucher pour mettre en couverture'),
                  onTap: _working || i == 0
                      ? null
                      : () => setState(() {
                          _photos.insert(0, _photos.removeAt(i));
                        }),
                  trailing: IconButton(
                    tooltip: 'Retirer la photo ${i + 1}',
                    onPressed: _working ? null : () => _remove(_photos[i]),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              ),
            if (_photos.length < 3)
              OutlinedButton.icon(
                onPressed: _working ? null : _add,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text('Ajouter une photo (${_photos.length}/3)'),
              ),
            const SizedBox(height: 12),
            const InlineNotice(
              'Les photos restent sur ce TPE. Elles ne figurent pas sur le ticket et ne sont pas encore sauvegardées hors du terminal.',
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
            label: Text(_working ? 'Enregistrement…' : 'Enregistrer'),
          ),
        ),
      ),
    ),
  );
}
