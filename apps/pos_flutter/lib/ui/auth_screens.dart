import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/session_controller.dart';
import '../domain/models.dart';
import 'backup_screen.dart';
import 'mono_theme.dart';

class _Brand extends StatelessWidget {
  const _Brand(this.subtitle);
  final String subtitle;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Image.asset(
        'assets/branding/logo.png',
        width: 96,
        semanticLabel: 'Logo Univers du Mono',
      ),
      const SizedBox(height: 12),
      const Text(
        'UNIVERS DU MONO',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      Text(subtitle, style: const TextStyle(color: MonoColors.muted)),
    ],
  );
}

/// Continues the Android launch screen while local accounts load.
class BrandSplash extends StatelessWidget {
  const BrandSplash({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Colors.white,
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Brand('Bien se vêtir pour mieux servir'),
          SizedBox(height: 24),
          SizedBox(width: 120, child: LinearProgressIndicator(minHeight: 2)),
        ],
      ),
    ),
  );
}

/// Activation: creates the first administrator. No predefined account.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});
  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _name = TextEditingController();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    for (final c in [_name, _pin, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const _Brand('Activation du terminal'),
            const SizedBox(height: 24),
            const InlineNotice(
              'Créez le compte administrateur. Il pourra ensuite ajouter les vendeurs. '
              'Le code PIN reste sur ce terminal : notez-le en lieu sûr.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              enabled: !session.busy,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nom de l’administrateur',
              ),
            ),
            const SizedBox(height: 12),
            PinField(
              _pin,
              label: 'Code PIN (6 chiffres)',
              enabled: !session.busy,
            ),
            const SizedBox(height: 12),
            PinField(
              _confirm,
              label: 'Confirmer le code PIN',
              enabled: !session.busy,
            ),
            if (session.error != null) ...[
              const SizedBox(height: 12),
              InlineNotice(session.error!, error: true),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: session.busy
                  ? null
                  : () => ref
                        .read(sessionProvider.notifier)
                        .setup(_name.text, _pin.text, _confirm.text),
              child: Text(session.busy ? 'Activation…' : 'Activer le terminal'),
            ),
            const SizedBox(height: 32),
            const Text(
              'Terminal de remplacement ? Restaurez plutôt la dernière sauvegarde : '
              'comptes, articles, stock et ventes seront récupérés.',
              style: TextStyle(fontSize: 12, color: MonoColors.muted),
            ),
            const RestoreBackupForm(),
          ],
        ),
      ),
    );
  }
}

class PinField extends StatelessWidget {
  const PinField(
    this.controller, {
    super.key,
    required this.label,
    this.enabled = true,
  });
  final TextEditingController controller;
  final String label;
  final bool enabled;
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    enabled: enabled,
    obscureText: true,
    keyboardType: TextInputType.number,
    maxLength: 6,
    decoration: InputDecoration(labelText: label, counterText: ''),
  );
}

/// Lock screen: choose an operator, then type the PIN on the keypad.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});
  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  LocalUser? _user;
  String _pin = '';

  Future<void> _digit(String d) async {
    if (_user == null || _pin.length >= 6) return;
    setState(() => _pin += d);
    if (_pin.length == 6) {
      final pin = _pin;
      final ok = await ref.read(sessionProvider.notifier).login(_user!.id, pin);
      if (!ok && mounted) setState(() => _pin = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const _Brand('Terminal verrouillé'),
            const SizedBox(height: 20),
            const SectionLabel('Qui êtes-vous ?'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final user in session.users)
                  ChoiceChip(
                    avatar: Icon(
                      user.role == Role.admin
                          ? Icons.admin_panel_settings_outlined
                          : Icons.person_outline,
                      size: 18,
                    ),
                    label: Text(user.name),
                    selected: _user?.id == user.id,
                    onSelected: session.busy
                        ? null
                        : (_) => setState(() {
                            _user = user;
                            _pin = '';
                          }),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (_user != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 6; i++)
                    Container(
                      margin: const EdgeInsets.all(6),
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _pin.length
                            ? MonoColors.ink
                            : MonoColors.line,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _Keypad(
                enabled: !session.busy,
                onDigit: _digit,
                onErase: () => setState(
                  () => _pin = _pin.isEmpty
                      ? ''
                      : _pin.substring(0, _pin.length - 1),
                ),
              ),
            ],
            if (session.busy) const LinearProgressIndicator(minHeight: 2),
            if (session.error != null) ...[
              const SizedBox(height: 12),
              InlineNotice(session.error!, error: true),
            ],
          ],
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.enabled,
    required this.onDigit,
    required this.onErase,
  });
  final bool enabled;
  final void Function(String) onDigit;
  final VoidCallback onErase;

  @override
  Widget build(BuildContext context) {
    Widget key(String label, VoidCallback action, {String? tooltip}) => Padding(
      padding: const EdgeInsets.all(6),
      child: SizedBox(
        width: 72,
        height: 56,
        child: OutlinedButton(
          onPressed: enabled ? action : null,
          child: Text(
            label,
            semanticsLabel: tooltip,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
    return Column(
      children: [
        for (final row in [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (final d in row) key(d, () => onDigit(d))],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 84),
            key('0', () => onDigit('0')),
            key('⌫', onErase, tooltip: 'Effacer'),
          ],
        ),
      ],
    );
  }
}

/// Administrator screen: add operators, deactivate them, reset PINs.
class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});
  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  List<LocalUser> _all = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_reload);
  }

  Future<void> _reload() async {
    final all = await ref.read(sessionProvider.notifier).allUsers();
    if (mounted) setState(() => _all = all);
  }

  Future<void> _form({LocalUser? reset}) async {
    final name = TextEditingController(), pin = TextEditingController();
    final confirm = TextEditingController();
    var role = Role.seller;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, _) => StatefulBuilder(
          builder: (context, setDialog) {
            final session = ref.watch(sessionProvider);
            return AlertDialog(
              title: Text(
                reset == null
                    ? 'Nouvel utilisateur'
                    : 'Nouveau PIN · ${reset.name}',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (reset == null) ...[
                      TextField(
                        controller: name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Nom'),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<Role>(
                        segments: const [
                          ButtonSegment(
                            value: Role.seller,
                            label: Text('Vendeur'),
                          ),
                          ButtonSegment(
                            value: Role.admin,
                            label: Text('Admin'),
                          ),
                        ],
                        selected: {role},
                        onSelectionChanged: (s) =>
                            setDialog(() => role = s.single),
                      ),
                      const SizedBox(height: 8),
                    ],
                    PinField(pin, label: 'Code PIN (6 chiffres)'),
                    PinField(confirm, label: 'Confirmer le code PIN'),
                    if (session.error != null)
                      InlineNotice(session.error!, error: true),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: session.busy
                      ? null
                      : () async {
                          final notifier = ref.read(sessionProvider.notifier);
                          final ok = reset == null
                              ? await notifier.createUser(
                                  name.text,
                                  role,
                                  pin.text,
                                  confirm.text,
                                )
                              : await notifier.resetPin(
                                  reset.id,
                                  pin.text,
                                  confirm.text,
                                );
                          if (ok && context.mounted) {
                            Navigator.pop(context, true);
                          }
                        },
                  child: const Text('Enregistrer'),
                ),
              ],
            );
          },
        ),
      ),
    );
    if (saved == true) await _reload();
    // Let the dialog finish closing before releasing its fields (a disposed
    // controller still in use crashed the H10 screen on a PIN change).
    await Future<void>.delayed(const Duration(milliseconds: 350));
    for (final c in [name, pin, confirm]) {
      c.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentActorProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Utilisateurs')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _form(),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Ajouter'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          for (final user in _all)
            Card(
              child: ListTile(
                leading: Icon(
                  user.role == Role.admin
                      ? Icons.admin_panel_settings_outlined
                      : Icons.person_outline,
                ),
                title: Text(user.name),
                subtitle: Text(
                  '${user.role == Role.admin ? 'Administrateur' : 'Vendeur'}'
                  '${user.active ? '' : ' · désactivé'}',
                ),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Actions pour ${user.name}',
                  onSelected: (action) async {
                    if (action == 'pin') return _form(reset: user);
                    final ok = await ref
                        .read(sessionProvider.notifier)
                        .setActive(user.id, !user.active);
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(ref.read(sessionProvider).error ?? ''),
                        ),
                      );
                    }
                    await _reload();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'pin',
                      child: Text('Nouveau code PIN'),
                    ),
                    if (user.id != me?.id)
                      PopupMenuItem(
                        value: 'active',
                        child: Text(user.active ? 'Désactiver' : 'Réactiver'),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
