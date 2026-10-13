import 'dart:io';
import 'dart:math';

import 'package:sqlite3/sqlite3.dart';

import '../sync/secure_store.dart';

/// Secure store entry holding the database key (Android Keystore).
const databaseKeyName = 'db_key';

final _hexKey = RegExp(r'^[0-9a-f]{64}$');

class DatabaseKeyMissing implements Exception {
  const DatabaseKeyMissing();
}

/// 256-bit random key, hex encoded.
String newDatabaseKey([Random? random]) {
  final source = random ?? Random.secure();
  return [
    for (var i = 0; i < 32; i++)
      source.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

/// First statement on every connection (SQLite3 Multiple Ciphers).
String keyPragma(String hexKey) {
  if (!_hexKey.hasMatch(hexKey)) throw ArgumentError('invalid database key');
  return "PRAGMA hexkey = '$hexKey'";
}

/// A database still in clear: an install from before encryption, or a
/// restored backup (backups carry a clear copy, sealed by their passphrase).
bool isPlainDatabase(File file) {
  if (!file.existsSync() || file.lengthSync() < 16) return false;
  final raf = file.openSync();
  try {
    return String.fromCharCodes(raf.readSync(16)) == 'SQLite format 3\u0000';
  } finally {
    raf.closeSync();
  }
}

/// The key of this terminal's database, created on first use. Refuses to
/// invent a new key for a database that is already encrypted.
Future<String> databaseKey(SecureStore store, File database) async {
  final existing = await store.read(databaseKeyName);
  if (existing != null && _hexKey.hasMatch(existing)) return existing;
  if (database.existsSync() && !isPlainDatabase(database)) {
    throw const DatabaseKeyMissing();
  }
  final key = newDatabaseKey();
  await store.write(databaseKeyName, key);
  if (await store.read(databaseKeyName) != key) {
    throw StateError('database key not persisted');
  }
  return key;
}

/// Encrypts a clear database in place, keeping a copy until the encrypted
/// file has been reopened and checked; on failure the clear file is put back.
void encryptIfPlain(File database, String hexKey) {
  keyPragma(hexKey); // validates the key format
  if (!isPlainDatabase(database)) return;
  final copy = File('${database.path}.avant-chiffrement');
  database.copySync(copy.path);
  try {
    final db = sqlite3.open(database.path);
    try {
      // Rekeying requires a rollback journal, never WAL.
      db.execute('PRAGMA journal_mode = DELETE');
      db.execute("PRAGMA hexrekey = '$hexKey'");
    } finally {
      db.close();
    }
    _check(database.path, hexKey);
    if (isPlainDatabase(database)) throw StateError('still in clear');
    copy.deleteSync();
  } catch (_) {
    copy.copySync(database.path);
    copy.deleteSync();
    rethrow;
  }
}

/// Turns an encrypted copy (VACUUM INTO keeps the key) into a clear one,
/// so that a backup can be restored on another terminal.
void decryptCopy(String path, String hexKey) {
  if (isPlainDatabase(File(path))) return;
  final db = sqlite3.open(path);
  try {
    db.execute(keyPragma(hexKey));
    db.execute("PRAGMA rekey = ''");
  } finally {
    db.close();
  }
  if (!isPlainDatabase(File(path))) throw StateError('copy not decrypted');
}

void _check(String path, String hexKey) {
  final db = sqlite3.open(path);
  try {
    db.execute(keyPragma(hexKey));
    final result = db.select('PRAGMA integrity_check').first.values.first;
    if (result != 'ok') throw StateError('integrity check failed');
  } finally {
    db.close();
  }
}
