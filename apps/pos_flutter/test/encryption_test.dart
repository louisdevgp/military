import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mono_pos/backup/backup_service.dart';
import 'package:mono_pos/data/database.dart';
import 'package:mono_pos/data/encryption.dart';
import 'package:mono_pos/data/pos_repository.dart';
import 'package:mono_pos/domain/models.dart';
import 'package:mono_pos/sync/secure_store.dart';

import 'backup_test.dart' show FakePlatform;

const admin = Actor('a', 'Admin', Role.admin);

void main() {
  late Directory dir;
  late File file;
  final key = newDatabaseKey();

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mono-chiffrement');
    file = File('${dir.path}/mono.sqlite');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  PosDatabase open({String? withKey}) => PosDatabase(
    NativeDatabase(
      file,
      setup: withKey == null ? null : (raw) => raw.execute(keyPragma(withKey)),
    ),
  );

  Future<void> seed() async {
    final db = open();
    final repo = PosRepository(db);
    await repo.initialize();
    await repo.createItem(
      actor: admin,
      category: 'TEST',
      name: 'Rangers TEST',
      sku: 'RAN-42',
      label: '42',
      price: 30000,
      stock: 3,
    );
    await db.close();
  }

  test('clé de 256 bits, format contrôlé', () {
    expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(newDatabaseKey(), isNot(key));
    expect(() => keyPragma("ab' ; DROP"), throwsArgumentError);
  });

  test('base existante chiffrée sur place, illisible sans la clé', () async {
    await seed();
    expect(isPlainDatabase(file), isTrue);
    encryptIfPlain(file, key);
    expect(isPlainDatabase(file), isFalse);
    expect(File('${file.path}.avant-chiffrement').existsSync(), isFalse);
    // Clear text no longer appears in the file.
    expect(
      latin1.decode(file.readAsBytesSync()),
      isNot(contains('Rangers TEST')),
    );
    final db = open(withKey: key);
    expect((await db.select(db.variants).get()).single.stock, 3);
    await db.close();
    final wrong = open(withKey: newDatabaseKey());
    await expectLater(wrong.select(wrong.variants).get(), throwsA(anything));
    await wrong.close();
    // Idempotent: an encrypted database is left untouched.
    final before = file.readAsBytesSync();
    encryptIfPlain(file, key);
    expect(file.readAsBytesSync(), before);
  });

  test(
    'clé créée une fois, jamais réinventée pour une base chiffrée',
    () async {
      final store = MemorySecureStore();
      final first = await databaseKey(store, file);
      expect(await databaseKey(store, file), first);
      await seed();
      encryptIfPlain(file, first);
      await expectLater(
        databaseKey(MemorySecureStore(), file),
        throwsA(isA<DatabaseKeyMissing>()),
      );
    },
  );

  test('la sauvegarde contient une copie en clair, scellée ensuite', () async {
    await seed();
    encryptIfPlain(file, key);
    final db = open(withKey: key);
    final repo = PosRepository(db);
    final archive = await BackupService(
      repo,
      FakePlatform(),
      workDir: Directory('${dir.path}/work'),
      databaseKey: key,
    ).buildArchive();
    await db.close();
    final json = jsonDecode(utf8.decode(archive)) as Map<String, dynamic>;
    final bytes = base64Decode(json['db'] as String);
    expect(latin1.decode(bytes.sublist(0, 15)), 'SQLite format 3');
    // Restored on another terminal: opens without this terminal's key.
    final other = File('${dir.path}/autre.sqlite')..writeAsBytesSync(bytes);
    final restored = PosDatabase(NativeDatabase(other));
    expect((await restored.select(restored.variants).get()).single.stock, 3);
    await restored.close();
  });
}
