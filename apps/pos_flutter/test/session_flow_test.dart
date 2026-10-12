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
    // Hashing runs in isolates, one after the other: wait for each.
    Future<void> settle() async {
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await tester.pumpAndSettle();
      }
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
    // The recovery code is shown once, and only closes once noted.
    expect(find.text('Code de secours'), findsOneWidget);
    final code = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .data!;
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
    expect(find.text('Code de secours'), findsOneWidget);
    await tester.tap(find.text('J’ai noté ce code en lieu sûr'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuer'));
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

    // Forgotten PIN: the recovery code sets a new one and is replaced.
    await tester.tap(find.byTooltip('Verrouiller (Awa)'));
    await settle();
    await tester.tap(find.text('PIN administrateur oublié ?'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Code de secours'),
      code.toLowerCase(),
    );
    await tester.tap(find.text('Awa'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Nouveau code PIN (6 chiffres)'),
      '730194',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirmer le code PIN'),
      '730194',
    );
    await tester.tap(find.text('Choisir ce nouveau PIN'));
    await settle();
    final next = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .data!;
    expect(next, isNot(code));
    await tester.tap(find.text('J’ai noté ce code en lieu sûr'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuer'));
    await settle();
    expect(find.byTooltip('Verrouiller (Awa)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await db.close();
  });
}
