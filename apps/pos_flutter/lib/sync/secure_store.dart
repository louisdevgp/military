import 'package:flutter/services.dart';

/// Sync settings kept across restarts. Values are encrypted by the Android
/// Keystore (SecureStoreBridge.kt); nothing is written in clear.
abstract interface class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class AndroidSecureStore implements SecureStore {
  const AndroidSecureStore();
  static const channel = MethodChannel('ci.universdumono/secure');

  @override
  Future<String?> read(String key) =>
      channel.invokeMethod<String>('read', {'key': key});

  @override
  Future<void> write(String key, String value) =>
      channel.invokeMethod<void>('write', {'key': key, 'value': value});

  @override
  Future<void> delete(String key) =>
      channel.invokeMethod<void>('delete', {'key': key});
}

/// Tests and non-Android runs: kept in memory only.
class MemorySecureStore implements SecureStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}
