import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/pos_controller.dart';
import '../data/settings_repository.dart';
import '../domain/models.dart' show customerFields;
import '../printing/receipt.dart';
import 'mono_theme.dart';
import 'receipt_preview.dart';

/// Administrator page: shop name, contacts, footer and logo printed on
/// receipts, with a live preview.
class ReceiptSettingsScreen extends ConsumerStatefulWidget {
  const ReceiptSettingsScreen({super.key});
  @override
  ConsumerState<ReceiptSettingsScreen> createState() =>
      _ReceiptSettingsScreenState();
}

class _ReceiptSettingsScreenState extends ConsumerState<ReceiptSettingsScreen> {
  late final ReceiptSettings _initial = ref.read(posProvider).receiptSettings;
  late final _name = TextEditingController(text: _initial.shopName);
  late final _contacts = TextEditingController(text: _initial.contacts);
  late final _footer = TextEditingController(text: _initial.footer);
  late LogoChoice _logo = _initial.logo;
  late String? _file = _initial.logoFile;

  /// Image picked during this visit and not saved yet.
  String? _draft;
  bool _working = false;
  bool _allowPop = false;
  String? _error;

  ReceiptSettings get _current => ReceiptSettings(
    shopName: _name.text,
    contacts: _contacts.text,
    footer: _footer.text,
    logo: _logo,
    logoFile: _file,
  );

  @override
  void dispose() {
    for (final c in [_name, _contacts, _footer]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _discard(String? path) async {
    if (path == null) return;
    try {
      await ref.read(photoProvider).discardDraft(path);
    } catch (_) {
      // An orphan private image is harmless; never block the operator.
    }
  }

  Future<void> _choose() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final path = await ref.read(photoProvider).choosePhoto();
      if (path != null) {
        await _discard(_draft);
        _draft = path;
        _file = path;
        _logo = LogoChoice.custom;
      }
    } on PlatformException catch (e) {
      _error = e.message ?? 'Cette image ne peut pas être utilisée.';
    } catch (_) {
      _error = 'La sélection d’image est indisponible. Réessayez.';
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _close() {
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _cancel() async {
    if (_working) return;
    await _discard(_draft);
    if (mounted) _close();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _working = true;
      _error = null;
    });
    final next = _current;
    final ok = await ref.read(posProvider.notifier).saveReceiptSettings(next);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _working = false;
        _error = ref.read(posProvider).message;
      });
      return;
    }
    // The previous custom image is no longer referenced.
    final previous = _initial.logoFile;
    if (previous != null && previous != next.logoFile) await _discard(previous);
    _draft = null;
    _close();
  }

  Widget _field(TextEditingController c, String label, int max) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: c,
      enabled: !_working,
      maxLength: max,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(labelText: label),
    ),
  );

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
        title: const Text('Ticket et boutique'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const SectionLabel(
              'Logo du ticket',
              subtitle: 'Image nette sur fond blanc, de préférence carrée.',
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Logo d’origine'),
                  selected: _logo == LogoChoice.original,
                  onSelected: _working
                      ? null
                      : (_) => setState(() => _logo = LogoChoice.original),
                ),
                if (_file != null)
                  ChoiceChip(
                    avatar: CircleAvatar(
                      backgroundImage: FileImage(File(_file!)),
                    ),
                    label: const Text('Image choisie'),
                    selected: _logo == LogoChoice.custom,
                    onSelected: _working
                        ? null
                        : (_) => setState(() => _logo = LogoChoice.custom),
                  ),
                ChoiceChip(
                  label: const Text('Sans logo'),
                  selected: _logo == LogoChoice.none,
                  onSelected: _working
                      ? null
                      : (_) => setState(() => _logo = LogoChoice.none),
                ),
                ActionChip(
                  avatar: const Icon(Icons.image_outlined, size: 18),
                  label: const Text('Choisir une image'),
                  onPressed: _working ? null : _choose,
                ),
              ],
            ),
            const SizedBox(height: 20),
            const SectionLabel('Textes du ticket'),
            _field(_name, 'Nom de la boutique', SettingsRepository.maxShopName),
            _field(
              _contacts,
              'Contacts (téléphones)',
              SettingsRepository.maxContacts,
            ),
            _field(_footer, 'Pied de ticket', SettingsRepository.maxFooter),
            if (_error != null) ...[
              InlineNotice(_error!, error: true),
              const SizedBox(height: 12),
            ],
            const SectionLabel(
              'Informations client obligatoires',
              subtitle: 'Exigées à chaque vente. Enregistré immédiatement.',
            ),
            for (final field in customerFields.entries)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(field.value),
                value: ref
                    .watch(posProvider)
                    .customerRequired
                    .contains(field.key),
                onChanged: _working
                    ? null
                    : (on) {
                        final next = {
                          ...ref.read(posProvider).customerRequired,
                        };
                        on ? next.add(field.key) : next.remove(field.key);
                        ref
                            .read(posProvider.notifier)
                            .saveCustomerRequired(next);
                      },
              ),
            const SectionLabel('Aperçu'),
            Center(child: ReceiptPreview(buildTestReceipt(settings: _current))),
            const SizedBox(height: 8),
            const Text(
              'Après enregistrement, utilisez « Ticket test » dans le bandeau de recette pour vérifier le papier.',
              style: TextStyle(fontSize: 12, color: MonoColors.muted),
            ),
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
