import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mono_pos/application/pos_controller.dart';
import 'package:mono_pos/application/session_controller.dart';
import 'package:mono_pos/auth/pin.dart';
import 'package:mono_pos/data/database.dart';
import 'package:mono_pos/data/pos_repository.dart';
import 'package:mono_pos/data/user_repository.dart';
import 'package:mono_pos/ui/auth_screens.dart';

void main() {
  testWidgets('nouveau code PIN depuis Utilisateurs, sans erreur d’écran', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1440);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = PosDatabase(NativeDatabase.memory());
    final repo = PosRepository(db);
    await repo.initialize();
    final users = UserRepository(
      repo,
      hasher: const Pbkdf2PinHasher(iterations: 10),
    );
    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
    }

    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        userRepositoryProvider.overrideWithValue(users),
      ],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      await container.read(sessionProvider.notifier).load();
      await container
          .read(sessionProvider.notifier)
          .setup('Dosso', '481516', '481516');
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: UsersScreen()),
      ),
    );
    await settle();
    await tester.tap(find.byTooltip('Actions pour Dosso'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nouveau code PIN'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Code PIN (6 chiffres)'),
      '927384',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirmer le code PIN'),
      '927384',
    );
    await tester.tap(find.text('Enregistrer'));
    await settle();
    await settle();
    expect(tester.takeException(), isNull);
    expect(find.text('Utilisateurs'), findsOneWidget);
    final dosso = (await tester.runAsync(() => users.users()))!.single;
    expect(
      (await tester.runAsync(() => users.authenticate(dosso.id, '927384')))!
          .name,
      'Dosso',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await db.close();
  });
}
