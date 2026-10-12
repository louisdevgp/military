import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/pos_controller.dart';
import '../domain/models.dart';
import 'mono_theme.dart';

/// Administrator: server settings (kept in the Android Keystore), automatic
/// sync switch and the state of pending operations.
class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});
  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  late final _origin = TextEditingController(
    text: ref.read(posProvider).syncOrigin ?? 'https://',
  );
  final _token = TextEditingController();
  bool _editing = false;

  @override
  void dispose() {
    _origin.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(posProvider);
    final status = state.syncStatus;
    final configured = state.syncOrigin != null;
    final controller = ref.read(posProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Synchronisation')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status.pending == 0
                        ? 'Tout est synchronisé'
                        : '${status.pending} opération(s) en attente',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Dernière synchronisation : ${status.lastSyncAt == null ? 'jamais' : abidjanDate(status.lastSyncAt!)}',
                  ),
                  if (state.syncing)
                    const Text('Synchronisation automatique en cours…'),
                  if (status.errorCode != null && status.pending > 0) ...[
                    const SizedBox(height: 8),
                    InlineNotice(
                      '${syncErrorLabel(status.errorCode!)}\n'
                      'Essais : ${status.attempts}'
                      '${status.nextAttemptAt == null ? '' : ' · prochain essai automatique : ${abidjanDate(status.nextAttemptAt!)}'}\n'
                      'Les opérations restent enregistrées sur le terminal.',
                      error: true,
                    ),
                  ],
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: state.busy || !configured
                        ? null
                        : controller.synchronize,
                    icon: const Icon(Icons.sync),
                    label: const Text('Synchroniser maintenant'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Synchronisation automatique'),
            subtitle: const Text(
              'Après chaque opération et toutes les 2 minutes, sans bloquer la caisse.',
            ),
            value: state.autoSync,
            onChanged: state.busy ? null : controller.setAutoSync,
          ),
          const SizedBox(height: 8),
          const SectionLabel('Serveur'),
          if (configured && !_editing) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_outline),
              title: Text(state.syncOrigin!),
              subtitle: const Text(
                'Jeton enregistré dans le coffre sécurisé Android',
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => setState(() => _editing = true),
                  child: const Text('Changer'),
                ),
                TextButton(
                  onPressed: state.busy ? null : controller.clearSyncConfig,
                  child: const Text('Oublier ce serveur'),
                ),
              ],
            ),
          ] else ...[
            TextField(
              controller: _origin,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Origine HTTPS du serveur',
                hintText: 'https://mono-api-recette.onrender.com',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _token,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Jeton de synchronisation',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: state.busy
                  ? null
                  : () async {
                      final ok = await controller.saveSyncConfig(
                        _origin.text,
                        _token.text,
                      );
                      if (ok && mounted) {
                        _token.clear();
                        setState(() => _editing = false);
                      }
                    },
              child: const Text('Enregistrer'),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Terminal : ${state.terminalId}',
            style: const TextStyle(fontSize: 12, color: MonoColors.muted),
          ),
        ],
      ),
    );
  }
}
