import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mono_pos/application/pos_controller.dart';
import 'package:mono_pos/application/session_controller.dart';
import 'package:mono_pos/data/database.dart';
import 'package:mono_pos/data/pos_repository.dart';
import 'package:mono_pos/domain/models.dart';
import 'package:mono_pos/main.dart';

const testAdmin = Actor('test-admin', 'Admin test', Role.admin);

void main() {
  testWidgets(
    'parcours écran catalogue, panier, validation, aperçu et duplicata',
    (tester) async {
      tester.view.physicalSize = const Size(720, 1440);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = PosDatabase(NativeDatabase.memory());
      final repo = PosRepository(db);
      await repo.initialize();
      await repo.createItem(
        actor: testAdmin,
        category: 'TEST',
        name: 'Article TEST',
        sku: 'TEST-42',
        label: '42',
        price: 12500,
        stock: 3,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            currentActorProvider.overrideWithValue(testAdmin),
          ],
          child: const MonoApp(),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Article TEST'), findsOneWidget);
      await tester.ensureVisible(
        find.byTooltip('Ajouter Article TEST au panier'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Ajouter Article TEST au panier'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Panier'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Passer au paiement'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Somme remise FCFA'),
        '15000',
      );
      await tester.tap(find.text('Valider la vente'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Aperçu du ticket'), findsOneWidget);
      expect(find.text('Imprimante simulée'), findsOneWidget);
      expect(find.text('RENDU'), findsOneWidget);
      expect(find.text('2 500 F CFA'), findsOneWidget);
      expect(
        find.text('N° FACTURE : FACT-${DateTime.now().toUtc().year}-00001'),
        findsOneWidget,
      );
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Aperçu du duplicata'));
      await tester.pumpAndSettle();
      expect(find.textContaining('DUPLICATA'), findsOneWidget);
      expect((await repo.history()).length, 1);
      expect((await repo.catalog()).single.stock, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await db.close();
    },
  );

  testWidgets('article à tailles : une carte, choix de la taille, panier', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1440);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = PosDatabase(NativeDatabase.memory());
    final repo = PosRepository(db);
    await repo.initialize();
    await repo.createProduct(
      actor: testAdmin,
      category: 'Treillis',
      name: 'Treillis MO',
      variants: [
        for (final size in ['M', 'L'])
          VariantDraft(
            sku: SizeGrid.clothing.sku('TRE-MO', size),
            label: SizeGrid.clothing.label(size, ''),
            price: size == 'M' ? 20000 : 22000,
            stock: size == 'M' ? 0 : 4,
          ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        currentActorProvider.overrideWithValue(testAdmin),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MonoApp()),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Treillis MO'), findsOneWidget);
    expect(find.text('2 tailles'), findsOneWidget);
    expect(find.text('Dès 20 000 FCFA'), findsOneWidget);
    await tester.ensureVisible(
      find.byTooltip('Choisir la taille de Treillis MO'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Choisir la taille de Treillis MO'));
    await tester.pumpAndSettle();
    expect(find.text('Modifier le prix'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Taille M'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Taille M'));
    await tester.pumpAndSettle();
    expect(container.read(posProvider).cart, isEmpty, reason: 'épuisé');
    await tester.scrollUntilVisible(
      find.text('Taille L'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Taille L'));
    await tester.pumpAndSettle();
    final lId = (await repo.catalog())
        .firstWhere((i) => i.sku == 'TRE-MO-L')
        .id;
    expect(container.read(posProvider).cart, {lId: 1});
    await tester.pumpWidget(const SizedBox.shrink());
    await db.close();
  });

  testWidgets('article en couleurs : choix de la couleur puis de la taille', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1440);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = PosDatabase(NativeDatabase.memory());
    final repo = PosRepository(db);
    await repo.initialize();
    await repo.createProduct(
      actor: testAdmin,
      category: 'Chaussures',
      name: 'Rangers',
      variants: matrixVariants(
        grid: SizeGrid.shoes,
        reference: 'RAN',
        colors: ['Noir', 'Marron'],
        price: 15000,
        stock: {('Noir', '42'): 2, ('Noir', '43'): 1, ('Marron', '40'): 1},
      ),
    );
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        currentActorProvider.overrideWithValue(testAdmin),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MonoApp()),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 couleurs · 3 variantes'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Choisir la taille de Rangers'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Choisir la taille de Rangers'));
    await tester.pumpAndSettle();
    final sheet = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(
      find.text('Marron'),
      120,
      scrollable: sheet,
    );
    expect(find.text('Couleurs / tailles'), findsOneWidget);
    // Black is selected first: brown sizes are hidden.
    expect(find.text('Marron · Pointure 40'), findsNothing);
    await tester.tap(find.text('Marron'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Marron · Pointure 40'),
      120,
      scrollable: sheet,
    );
    expect(find.text('Noir · Pointure 42'), findsNothing);
    await tester.tap(find.text('Marron · Pointure 40'));
    await tester.pumpAndSettle();
    final brownId = (await repo.catalog())
        .firstWhere((i) => i.color == 'Marron')
        .id;
    expect(container.read(posProvider).cart, {brownId: 1});
    await tester.pumpWidget(const SizedBox.shrink());
    await db.close();
  });

  testWidgets('stock : réception depuis l’écran Stock', (tester) async {
    tester.view.physicalSize = const Size(720, 1440);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = PosDatabase(NativeDatabase.memory());
    final repo = PosRepository(db);
    await repo.initialize();
    await repo.createItem(
      actor: testAdmin,
      category: 'TEST',
      name: 'Béret',
      sku: 'BER-58',
      label: 'Taille 58',
      price: 5000,
      stock: 2,
    );
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        currentActorProvider.overrideWithValue(testAdmin),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MonoApp()),
    );
    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
    }

    await settle();
    await tester.tap(find.byTooltip('Administration'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stock'));
    await settle();
    expect(find.text('Béret · Taille 58'), findsOneWidget);
    await tester.tap(find.text('Béret · Taille 58'));
    await settle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Réception'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Quantité'), '3');
    await tester.tap(find.text('Enregistrer'));
    await settle();
    expect((await repo.catalog()).single.stock, 5);
    expect(find.text('5'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await db.close();
  });
}
