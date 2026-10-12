import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/pos_controller.dart';
import '../domain/models.dart' show abidjanDate;
import 'mono_theme.dart';

/// Administrator: encrypted backup saved off the terminal, and restore.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});
  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  final _pass = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(posProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Sauvegarde')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          InlineNotice(
            state.lastBackupAt == null
                ? 'Aucune sauvegarde enregistrée sur ce terminal.'
                : 'Dernière sauvegarde : ${abidjanDate(state.lastBackupAt!)}.',
            error: state.lastBackupAt == null,
          ),
          const SizedBox(height: 12),
          const SectionLabel(
            'Créer une sauvegarde',
            subtitle: 'Base, photos et logo, chiffrés avec votre mot de passe. Enregistrez le fichier hors du terminal (Drive, clé USB…).',
          ),
          TextField(
            controller: _pass,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Mot de passe de sauvegarde (10 caractères min.)',
            ),
          ),
          TextField(
            controller: _confirm,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Confirmer le mot de passe',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Sans ce mot de passe, la sauvegarde est illisible : notez-le en lieu sûr, séparément du fichier.',
            style: TextStyle(fontSize: 12, color: MonoColors.muted),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: state.busy
                ? null
                : () async {
                    final ok = await ref
                        .read(posProvider.notifier)
                        .exportBackup(_pass.text, _confirm.text);
                    if (ok) {
                      _pass.clear();
                      _confirm.clear();
                    }
                  },
            icon: const Icon(Icons.backup_outlined),
            label: const Text('Créer et enregistrer la sauvegarde'),
          ),
          const SizedBox(height: 24),
          const RestoreBackupForm(),
        ],
      ),
    );
  }
}

/// Shared by the backup screen and the activation screen of a new device.
class RestoreBackupForm extends ConsumerStatefulWidget {
  const RestoreBackupForm({super.key});
  @override
  ConsumerState<RestoreBackupForm> createState() => _RestoreBackupFormState();
}

class _RestoreBackupFormState extends ConsumerState<RestoreBackupForm> {
  final _pass = TextEditingController();

  @override
  void dispose() {
    _pass.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restaurer une sauvegarde ?'),
        content: const Text(
          'Les données actuelles du terminal seront remplacées (une copie de sécurité est gardée sur le terminal). '
          'L’application redémarrera, puis les nouvelles opérations resteront bloquées jusqu’à la réconciliation avec le serveur.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Choisir le fichier'),
          ),
        ],
      ),
    );
    if (sure == true) {
      await ref.read(posProvider.notifier).restoreBackup(_pass.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(posProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel(
          'Restaurer une sauvegarde',
          subtitle: 'Fichier .monobak créé par cette application.',
        ),
        TextField(
          controller: _pass,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Mot de passe de la sauvegarde',
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: state.busy ? null : _restore,
          icon: const Icon(Icons.restore),
          label: const Text('Restaurer…'),
        ),
        if (state.message != null && state.busy)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(state.message!),
          ),
      ],
    );
  }
}

/// Shown in administrator screens while a restored terminal waits for
/// reconciliation.
class ReconcileCard extends ConsumerWidget {
  const ReconcileCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(posProvider);
    if (!state.reconcileRequired) return const SizedBox.shrink();
    return Card(
      color: const Color(0xFFFFF4E5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Restauration à terminer',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'Les nouvelles opérations sont bloquées tant que le terminal n’a pas récupéré '
              'auprès du serveur les opérations faites après la sauvegarde.',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: state.busy
                      ? null
                      : ref.read(posProvider.notifier).reconcile,
                  child: const Text('Réconcilier maintenant'),
                ),
                TextButton(
                  onPressed: state.busy
                      ? null
                      : () async {
                          final sure = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Aucun serveur utilisé ?'),
                              content: const Text(
                                'À choisir seulement si ce terminal n’a jamais été synchronisé. '
                                'Sinon, des numéros et des opérations seraient en double et la synchronisation refusée.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Annuler'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Lever le blocage'),
                                ),
                              ],
                            ),
                          );
                          if (sure == true) {
                            await ref
                                .read(posProvider.notifier)
                                .skipReconcile();
                          }
                        },
                  child: const Text('Aucun serveur utilisé'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
