import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../data/database.dart';
import '../data/encryption.dart';
import '../data/pos_repository.dart';
import '../domain/models.dart';
import 'backup_platform.dart';

/// Archive format version written in the manifest.
const backupFormat = 1;

/// Settings key set after a restore: new operations stay blocked until the
/// terminal has been reconciled with the server.
const reconcileKey = 'reconcile_required';
const lastBackupKey = 'last_backup_at';

final _photoPath = RegExp(r'[/\\]catalog_images[/\\][a-f0-9-]{36}\.jpg$');

class BackupManifest {
  BackupManifest(this.json);
  final Map<String, dynamic> json;
  int get format => json['format'] as int;
  int get schemaVersion => json['schema_version'] as int;
  String get terminalId => json['terminal_id'] as String;
  int get eventSequence => json['event_sequence'] as int;
  int get saleSequence => json['sale_sequence'] as int;
  String get createdAt => json['created_at'] as String;
}

/// Encrypted, verifiable backups of the local database and its files
/// (product photos, custom logo), and staged restores applied at startup
/// before the database is opened.
class BackupService {
  BackupService(
    this.pos,
    this.platform, {
    required this.workDir,
    this.databaseKey,
  });
  final PosRepository pos;
  final BackupPlatform platform;

  /// Private app directory for temporary snapshots.
  final Directory workDir;

  /// Key of the encrypted database: snapshots are decrypted before being
  /// sealed with the passphrase, so a backup opens on any terminal.
  final String? databaseKey;
  PosDatabase get db => pos.db;

  static String _sha(List<int> bytes) => sha256.convert(bytes).toString();

  static void _passphrase(String value) {
    if (value.length < 10) {
      throw const BusinessException(
        'Mot de passe de sauvegarde : 10 caractères minimum.',
      );
    }
  }

  /// Consistent snapshot (VACUUM INTO) plus referenced files, as JSON.
  Future<Uint8List> buildArchive() async {
    final snapshot = File(
      '${workDir.path}/snapshot-${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    try {
      await workDir.create(recursive: true);
      await db.customStatement('VACUUM INTO ?', [snapshot.path]);
      if (databaseKey != null) decryptCopy(snapshot.path, databaseKey!);
      final dbBytes = await snapshot.readAsBytes();
      final paths = <String>{
        for (final r
            in await db
                .customSelect('SELECT path FROM local_product_photos')
                .get())
          r.read<String>('path'),
        for (final r in await (db.select(
          db.shopSettings,
        )..where((s) => s.key.equals('logo_file'))).get())
          r.value,
      };
      final files = <String, String>{};
      final entries = <Map<String, Object?>>[];
      for (final path in paths) {
        final file = File(path);
        if (!_photoPath.hasMatch(path) || !await file.exists()) continue;
        final bytes = await file.readAsBytes();
        files[path] = base64Encode(bytes);
        entries.add({
          'path': path,
          'sha256': _sha(bytes),
          'size': bytes.length,
        });
      }
      final terminal = await pos.terminal();
      final manifest = {
        'format': backupFormat,
        'schema_version': db.schemaVersion,
        'terminal_id': terminal.terminalId,
        'event_sequence': terminal.eventSequence,
        'sale_sequence': terminal.saleSequence,
        'created_at': pos.now().toUtc().toIso8601String(),
        'db_sha256': _sha(dbBytes),
        'files': entries,
      };
      return utf8.encode(
        jsonEncode({
          'manifest': manifest,
          'db': base64Encode(dbBytes),
          'files': files,
        }),
      );
    } finally {
      if (await snapshot.exists()) await snapshot.delete();
    }
  }

  /// Encrypts and saves the archive where the administrator chooses.
  /// Returns false when cancelled.
  Future<bool> exportBackup(Actor actor, String passphrase) async {
    actor.requireAdmin();
    _passphrase(passphrase);
    final archive = await buildArchive();
    final sealed = await platform.encrypt(archive, passphrase);
    final now = pos.now().toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    final name =
        'mono-sauvegarde-${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}.monobak';
    final saved = await platform.save(name, sealed) ?? false;
    if (!saved) return false;
    final at = now.toIso8601String();
    await db.transaction(() async {
      await db
          .into(db.shopSettings)
          .insertOnConflictUpdate(
            ShopSettingsCompanion.insert(key: lastBackupKey, value: at),
          );
      // Audit only: the archive itself never leaves the administrator's hands.
      await pos.appendEvent(
        PosRepository.uuid.v4(),
        'backup.created',
        actor,
        at,
        {'schema_version': db.schemaVersion},
      );
    });
    return true;
  }

  Future<String?> lastBackupAt() async => (await (db.select(
    db.shopSettings,
  )..where((s) => s.key.equals(lastBackupKey))).getSingleOrNull())?.value;

  /// Decrypts and verifies a backup, keeps a safety copy of the current
  /// database, then stages the files for the next start. [actor] must be an
  /// administrator, except on a terminal not activated yet (new device).
  Future<BackupManifest> stageRestore(
    Uint8List sealed,
    String passphrase, {
    required Actor? actor,
    required Directory docsDir,
  }) async {
    final hasUsers =
        await (db.select(db.users)..limit(1)).getSingleOrNull() != null;
    if (hasUsers) {
      if (actor == null) {
        throw const BusinessException('Connectez-vous en administrateur.');
      }
      actor.requireAdmin();
    }
    final archive = jsonDecode(
      utf8.decode(await platform.decrypt(sealed, passphrase)),
    ) as Map<String, dynamic>;
    final manifest = BackupManifest(
      archive['manifest'] as Map<String, dynamic>,
    );
    if (manifest.format != backupFormat) {
      throw const BusinessException('Format de sauvegarde non pris en charge.');
    }
    if (manifest.schemaVersion > db.schemaVersion) {
      throw const BusinessException(
        'Sauvegarde créée par une version plus récente : mettez l’application à jour.',
      );
    }
    final dbBytes = base64Decode(archive['db'] as String);
    if (_sha(dbBytes) != manifest.json['db_sha256'] ||
        !utf8
            .decode(dbBytes.sublist(0, 15), allowMalformed: true)
            .startsWith('SQLite format 3')) {
      throw const BusinessException('Sauvegarde endommagée : base invalide.');
    }
    final files = (archive['files'] as Map).cast<String, String>();
    for (final entry in (manifest.json['files'] as List).cast<Map>()) {
      final bytes = base64Decode(files[entry['path']] ?? '');
      if (!_photoPath.hasMatch(entry['path'] as String) ||
          _sha(bytes) != entry['sha256']) {
        throw const BusinessException(
          'Sauvegarde endommagée : fichier invalide.',
        );
      }
    }
    // Safety copy of the current state before anything is replaced.
    final safety = Directory('${docsDir.path}/safety')
      ..createSync(recursive: true);
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    await db.customStatement('VACUUM INTO ?', [
      '${safety.path}/avant-restauration-$stamp.sqlite',
    ]);
    final staging = Directory('${docsDir.path}/restore_pending');
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    staging.createSync(recursive: true);
    await File('${staging.path}/database.sqlite')
        .writeAsBytes(dbBytes, flush: true);
    final staged = <String, String>{};
    var index = 0;
    for (final entry in files.entries) {
      final name = 'file-${index++}';
      await File('${staging.path}/$name')
          .writeAsBytes(base64Decode(entry.value));
      staged[name] = entry.key;
    }
    // Written last: its presence means the staging is complete.
    await File('${staging.path}/manifest.json').writeAsString(
      jsonEncode({...manifest.json, 'staged_files': staged}),
      flush: true,
    );
    return manifest;
  }

  /// Called by main() before the database is opened. Returns the applied
  /// manifest, or null when nothing is pending.
  static Future<BackupManifest?> applyPendingRestore({
    required Directory docsDir,
    required String dbFileName,
  }) async {
    final staging = Directory('${docsDir.path}/restore_pending');
    final marker = File('${staging.path}/manifest.json');
    if (!marker.existsSync()) {
      if (staging.existsSync()) staging.deleteSync(recursive: true);
      return null;
    }
    final json =
        jsonDecode(await marker.readAsString()) as Map<String, dynamic>;
    final target = File('${docsDir.path}/$dbFileName');
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final extra = File('${target.path}$suffix');
      if (extra.existsSync()) extra.deleteSync();
    }
    await File('${staging.path}/database.sqlite').copy(target.path);
    for (final entry
        in (json['staged_files'] as Map).cast<String, String>().entries) {
      if (!_photoPath.hasMatch(entry.value)) continue;
      final destination = File(entry.value);
      destination.parent.createSync(recursive: true);
      await File('${staging.path}/${entry.key}').copy(destination.path);
    }
    staging.deleteSync(recursive: true);
    return BackupManifest(json);
  }

  /// After a restore: block new operations until reconciled.
  Future<void> markReconcileRequired() => db
      .into(db.shopSettings)
      .insertOnConflictUpdate(
        ShopSettingsCompanion.insert(key: reconcileKey, value: '1'),
      );
}
