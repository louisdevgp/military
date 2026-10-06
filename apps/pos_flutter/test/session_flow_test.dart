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
import 'package:mono_pos/main.dart';

void main() {
  testWidgets('activation, caisse, verrouillage puis déverrouillage par PIN', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1600);
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
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          userRepositoryProvider.overrideWithValue(users),
        ],
        child: const MonoApp(),
      ),
    );
    await settle();
    expect(find.text('Activation du terminal'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Nom de l’administrateur'),
      'Awa',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Code PIN (6 chiffres)'),
      '481516',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirmer le code PIN'),
      '481516',
    );
    await tester.tap(find.text('Activer le terminal'));
    await settle();
    expect(find.byTooltip('Administration'), findsOneWidget);
    await tester.tap(find.byTooltip('Verrouiller (Awa)'));
    await settle();
    expect(find.text('Terminal verrouillé'), findsOneWidget);
    await tester.tap(find.text('Awa'));
    await tester.pumpAndSettle();
    for (final digit in '000000'.split('')) {
      await tester.tap(find.text(digit).last);
    }
    await settle();
    expect(find.textContaining('Code PIN incorrect'), findsOneWidget);
    for (final digit in '481516'.split('')) {
      await tester.tap(find.text(digit).last);
    }
    await settle();
    expect(find.byTooltip('Verrouiller (Awa)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await db.close();
  });
}
