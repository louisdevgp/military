import 'package:flutter/services.dart';

/// Native side of backups (BackupBridge.kt): encryption with the backup
/// passphrase, document picker read/write and app restart.
abstract interface class BackupPlatform {
  Future<Uint8List> encrypt(Uint8List data, String passphrase);
  Future<Uint8List> decrypt(Uint8List data, String passphrase);

  /// False or null when the operator cancels.
  Future<bool?> save(String name, Uint8List data);

  /// Null when the operator cancels.
  Future<Uint8List?> open();
  Future<void> relaunch();
}

class AndroidBackupPlatform implements BackupPlatform {
  const AndroidBackupPlatform();
  static const channel = MethodChannel('ci.universdumono/backup');

  @override
  Future<Uint8List> encrypt(Uint8List data, String passphrase) async =>
      (await channel.invokeMethod<Uint8List>('encrypt', {
        'data': data,
        'passphrase': passphrase,
      }))!;

  @override
  Future<Uint8List> decrypt(Uint8List data, String passphrase) async =>
      (await channel.invokeMethod<Uint8List>('decrypt', {
        'data': data,
        'passphrase': passphrase,
      }))!;

  @override
  Future<bool?> save(String name, Uint8List data) =>
      channel.invokeMethod<bool>('save', {'name': name, 'data': data});

  @override
  Future<Uint8List?> open() => channel.invokeMethod<Uint8List>('open');

  @override
  Future<void> relaunch() => channel.invokeMethod<void>('relaunch');
}
