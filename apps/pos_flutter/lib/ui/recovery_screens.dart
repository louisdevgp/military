import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/session_controller.dart';
import '../domain/models.dart';
import 'auth_screens.dart';
import 'mono_theme.dart';

/// The administrator recovery code, shown once. Closing requires confirming
/// that it was written down.
class RecoveryCodeView extends StatefulWidget {
  const RecoveryCodeView(this.code, {super.key, required this.onNoted});
  final String code;
  final VoidCallback onNoted;
  @override
  State<RecoveryCodeView> createState() => _RecoveryCodeViewState();
}

class _RecoveryCodeViewState extends State<RecoveryCodeView> {
  bool _noted = false;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const InlineNotice(
        'Code de secours administrateur. Il permet de choisir un nouveau code PIN '
        'si tous les PIN administrateur sont oubliés. Écrivez-le sur papier et '
        'gardez-le hors de la boutique. Il ne sera plus jamais affiché.',
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        decoration: BoxDecoration(
          color: MonoColors.pale,
          borderRadius: BorderRadius.circular(16),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SelectableText(
            widget.code,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: _noted,
        onChanged: (v) => setState(() => _noted = v ?? false),
        title: const Text('J’ai noté ce code en lieu sûr'),
      ),
      FilledButton(
        onPressed: _noted ? widget.onNoted : null,
        child: const Text('Continuer'),
      ),
    ],
  );
}

class RecoveryCodeScreen extends ConsumerWidget {
  const RecoveryCodeScreen(this.code, {super.key});
  final String code;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      title: const Text('Code de secours'),
      automaticallyImplyLeading: false,
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          RecoveryCodeView(
            code,
            onNoted: () =>
                ref.read(sessionProvider.notifier).recoveryCodeNoted(),
          ),
        ],
      ),
    ),
  );
}

Future<void> showRecoveryCode(BuildContext context, String code) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Nouveau code de secours'),
        content: SingleChildScrollView(
          child: RecoveryCodeView(code, onNoted: () => Navigator.pop(context)),
        ),
      ),
    );

/// Forgotten administrator PIN: recovery code, administrator, new PIN.
class RecoveryScreen extends ConsumerStatefulWidget {
  const RecoveryScreen({super.key});
  @override
  ConsumerState<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends ConsumerState<RecoveryScreen> {
  final _code = TextEditingController();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  String? _userId;

  @override
  void dispose() {
    for (final c in [_code, _pin, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final userId = _userId;
    if (userId == null) return;
    final ok = await ref
        .read(sessionProvider.notifier)
        .recover(_code.text, userId, _pin.text, _confirm.text);
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final admins = [
      for (final u in session.users)
        if (u.role == Role.admin) u,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('PIN administrateur oublié')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const InlineNotice(
              'Saisissez le code de secours noté à l’activation. Il ne sert '
              'qu’une fois : un nouveau code vous sera donné.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _code,
              enabled: !session.busy,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              maxLength: 19,
              decoration: const InputDecoration(
                labelText: 'Code de secours',
                hintText: 'XXXX-XXXX-XXXX-XXXX',
                counterText: '',
              ),
            ),
            const SizedBox(height: 16),
            const SectionLabel('Administrateur'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final admin in admins)
                  ChoiceChip(
                    label: Text(admin.name),
                    selected: _userId == admin.id,
                    onSelected: session.busy
                        ? null
                        : (_) => setState(() => _userId = admin.id),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            PinField(
              _pin,
              label: 'Nouveau code PIN (6 chiffres)',
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
              onPressed: session.busy || _userId == null ? null : _submit,
              child: Text(
                session.busy ? 'Vérification…' : 'Choisir ce nouveau PIN',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
