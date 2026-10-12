import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/pos_controller.dart';
import 'application/session_controller.dart';
import 'data/database.dart';
import 'data/pos_repository.dart';
import 'printing/printer_service.dart';
import 'sync/secure_store.dart';
import 'ui/auth_screens.dart';
import 'ui/pos_screen.dart';
import 'ui/mono_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('RECETTE_MODE')) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Version de recette non activée. '
                'L’activation sécurisée de production sera disponible dans un prochain lot.',
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }
  final db = PosDatabase();
  final repo = PosRepository(db);
  try {
    await repo.initialize();
    final printer = await _detectPrinter();
    runApp(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          printerProvider.overrideWithValue(printer),
          if (Platform.isAndroid)
            secureStoreProvider.overrideWithValue(const AndroidSecureStore()),
        ],
        child: const MonoApp(),
      ),
    );
  } catch (_) {
    await db.close();
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Impossible d’ouvrir la base locale. Ne désinstallez pas l’application.',
            ),
          ),
        ),
      ),
    );
  }
}

/// Uses the H10 built-in printer only when its service answers; otherwise the
/// explicitly labelled simulator.
Future<PrinterService> _detectPrinter() async {
  if (!Platform.isAndroid) return SimulatedPrinter();
  try {
    return PlatformPrinter(version: await PlatformPrinter.probe());
  } catch (_) {
    return SimulatedPrinter();
  }
}

class MonoApp extends ConsumerWidget {
  const MonoApp({super.key});
  static final navigator = GlobalKey<NavigatorState>();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(currentActorProvider, (previous, next) {
      // Locking must not leave a payment or catalogue screen on top.
      if (previous != null && next == null) {
        navigator.currentState?.popUntil((route) => route.isFirst);
      }
    });
    final actor = ref.watch(currentActorProvider);
    final session = actor == null ? ref.watch(sessionProvider) : null;
    return Listener(
      // Any touch postpones the inactivity lock.
      onPointerDown: (_) => ref.read(sessionProvider.notifier).touch(),
      child: MaterialApp(
        navigatorKey: navigator,
        title: 'Univers du Mono · Recette',
        debugShowCheckedModeBanner: false,
        theme: monoTheme(),
        home: switch (session) {
          null => const PosScreen(),
          SessionState(loading: true) => const BrandSplash(),
          SessionState(activated: false) => const SetupScreen(),
          _ => const LockScreen(),
        },
      ),
    );
  }
}
