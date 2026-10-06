import 'dart:convert';
import 'dart:io';

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
import 'package:mono_pos/media/photo_service.dart';

// A one-pixel fixture tests storage and decoding, never a store catalogue asset.
const pixel =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

class FakePhotos implements PhotoService {
  FakePhotos(this.path);
  final String path;
  @override
  Future<String?> choosePhoto() async => path;
  @override
  Future<void> discardDraft(String path) async {
    await File(path).delete();
  }
}

class RefreshFailureRepository extends PosRepository {
  RefreshFailureRepository(super.db);
  @override
  Future<List<CatalogItem>> catalog() async =>
      throw StateError('Read failed after commit');
}

const testAdmin = Actor('test-admin', 'Admin test', Role.admin);

void main() {
  late Directory directory;
  late File photo;
  late PosDatabase db;
  late PosRepository repo;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mono_photos_');
    final images = await Directory('${directory.path}/catalog_images').create();
    photo = File('${images.path}/f82996d6-4140-4240-b599-d74545ec5101.jpg');
    await photo.writeAsBytes(base64Decode(pixel));
    db = PosDatabase(NativeDatabase.memory());
    repo = PosRepository(db);
    await repo.initialize();
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  Future<String> create({String sku = 'PHOTO', List<String>? photos}) =>
      repo.createItem(
        actor: testAdmin,
        category: 'Test',
        name: 'Article photo',
        sku: sku,
        label: '42',
        price: 12500,
        stock: 3,
        photoPaths: photos ?? [photo.path],
      );

  test(
    'photo liée à l’article, chemin local exclu de la synchronisation',
    () async {
      await create();
      expect((await repo.catalog()).single.photoPaths, [photo.path]);
      expect(await repo.pendingCount(), 1);
      final event = (await db.select(db.outboxEntries).get()).single;
      expect(event.envelope, isNot(contains(photo.path)));
      expect(await photo.exists(), isTrue);
    },
  );

  test(
    'photo manquante ou répétée : aucun article, mouvement ni événement',
    () async {
      await expectLater(
        create(photos: [photo.path, photo.path]),
        throwsA(isA<BusinessException>()),
      );
      await photo.delete();
      await expectLater(create(), throwsA(isA<BusinessException>()));
      expect(await repo.catalog(), isEmpty);
      expect(await repo.pendingCount(), 0);
      expect(await db.select(db.stockMovements).get(), isEmpty);
    },
  );

  test('échec outbox annule aussi le rattachement des photos', () async {
    await db.customStatement(
      "CREATE TRIGGER reject_event BEFORE INSERT ON outbox_entries BEGIN SELECT RAISE(ABORT, 'test failure'); END",
    );
    await expectLater(create(), throwsA(isA<Exception>()));
    expect(
      await db.customSelect('SELECT * FROM local_product_photos').get(),
      isEmpty,
    );
    expect(await repo.catalog(), isEmpty);
    expect(await photo.exists(), isTrue); // Still owned by the unsaved form.
  });

  test(
    'échec de lecture après commit : création réussie, photos conservées',
    () async {
      final container = ProviderContainer(
        overrides: [
          repositoryProvider.overrideWithValue(RefreshFailureRepository(db)),
          currentActorProvider.overrideWithValue(testAdmin),
        ],
      );
      addTearDown(container.dispose);
      final ok = await container
          .read(posProvider.notifier)
          .createItem(
            category: 'Test',
            name: 'Photo',
            sku: 'PHOTO',
            label: '42',
            price: '100',
            stock: '1',
            photoPaths: [photo.path],
          );
      expect(ok, isTrue);
      expect((await repo.catalog()).single.photoPaths, [photo.path]);
      expect(
        container.read(posProvider).message,
        contains('Actualisation impossible'),
      );
    },
  );

  test('aperçu monnaie : total exact, trop peu et montant invalide', () {
    expect(previewCash(12500, '15000')?.change, 2500);
    expect(previewCash(12500, '12500')?.change, 0);
    expect(previewCash(12500, '10000'), isNull);
    expect(previewCash(12500, '12.5'), isNull);
  });

  test(
    'réouverture SQLite conserve les photos et l’identité terminal',
    () async {
      await db.close();
      final databaseFile = File('${directory.path}/photos.sqlite');
      db = PosDatabase(NativeDatabase(databaseFile));
      repo = PosRepository(db);
      await repo.initialize();
      final identity = (await repo.terminal()).terminalId;
      await create();
      await db.close();
      db = PosDatabase(NativeDatabase(databaseFile));
      repo = PosRepository(db);
      await repo.initialize();
      expect((await repo.catalog()).single.photoPaths, [photo.path]);
      expect((await repo.terminal()).terminalId, identity);
      expect(await repo.pendingCount(), 1);
    },
  );

  for (final save in [false, true]) {
    testWidgets(
      save
          ? 'fiche photo enregistrée depuis le formulaire'
          : 'annulation fiche : brouillon photo supprimé',
      (tester) async {
        tester.view.physicalSize = const Size(720, 1440);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              repositoryProvider.overrideWithValue(repo),
              currentActorProvider.overrideWithValue(testAdmin),
              photoProvider.overrideWithValue(FakePhotos(photo.path)),
            ],
            child: const MonoApp(),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Créer un article'));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined).first);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        expect(find.byTooltip('Retirer la photo 1'), findsOneWidget);
        final preview = tester.widget<Image>(find.byType(Image).last);
        final stream = preview.image.resolve(ImageConfiguration.empty);
        var decoded = false;
        Object? decodeError;
        final listener = ImageStreamListener(
          (_, _) => decoded = true,
          onError: (error, _) => decodeError = error,
        );
        stream.addListener(listener);
        for (
          var attempts = 0;
          attempts < 40 && !decoded && decodeError == null;
          attempts++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump();
        }
        stream.removeListener(listener);
        expect(decodeError, isNull);
        expect(
          decoded,
          isTrue,
          reason:
              'La photo choisie doit être décodée avant de fermer la fiche.',
        );
        if (save) {
          final fields = {
            'Nom de l’article': 'Photo test',
            'Catégorie': 'Test',
            'Référence unique': 'PHOTO',
            'Variante · taille, couleur, pointure': 'Noir · 42',
            'Prix de vente FCFA': '12500',
            'Stock initial': '3',
          };
          for (final entry in fields.entries) {
            final field = find.widgetWithText(TextFormField, entry.key);
            await tester.ensureVisible(field);
            await tester.pumpAndSettle();
            await tester.enterText(field, entry.value);
          }
          await tester.runAsync(() async {
            await tester.tap(find.text('Enregistrer l’article'));
            await Future<void>.delayed(const Duration(milliseconds: 200));
          });
        } else {
          await tester.runAsync(() async {
            await tester.tap(find.byTooltip('Annuler la création'));
            await Future<void>.delayed(const Duration(milliseconds: 100));
          });
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Nouvel article'), findsNothing);
        expect(photo.existsSync(), save);
        expect((await repo.catalog()).length, save ? 1 : 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      },
    );
  }

  test(
    'modification des photos : ajout, couverture, retrait, sans événement',
    () async {
      final second = File(
        '${photo.parent.path}/0b9f6c1e-2d3a-4e5f-8a7b-1c2d3e4f5a6b.jpg',
      )..writeAsBytesSync(base64Decode(pixel));
      final id = await create(photos: [photo.path]);
      final productId = (await repo.catalog()).single.productId;
      final events = (await db.select(db.outboxEntries).get()).length;
      const seller = Actor('s', 'Vendeur', Role.seller);
      await expectLater(
        repo.replacePhotos(seller, productId, [second.path]),
        throwsA(isA<BusinessException>()),
      );
      await expectLater(
        repo.replacePhotos(testAdmin, productId, [second.path, second.path]),
        throwsA(isA<BusinessException>()),
      );
      await expectLater(
        repo.replacePhotos(testAdmin, productId, ['/tmp/ailleurs.jpg']),
        throwsA(isA<BusinessException>()),
      );
      // New cover first, old photo kept second.
      var removed = await repo.replacePhotos(testAdmin, productId, [
        second.path,
        photo.path,
      ]);
      expect(removed, isEmpty);
      expect((await repo.catalog()).single.photoPaths, [
        second.path,
        photo.path,
      ]);
      removed = await repo.replacePhotos(testAdmin, productId, [second.path]);
      expect(removed, [photo.path]);
      expect((await repo.catalog()).single.photoPaths, [second.path]);
      expect((await repo.catalog()).single.id, id);
      expect((await db.select(db.outboxEntries).get()).length, events);
    },
  );
}
