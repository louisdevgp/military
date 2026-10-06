import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../domain/models.dart';

/// PBKDF2 work factor for new PINs. Stored per user so it can be raised
/// later; to calibrate on the H10 (pure Dart, run off the UI isolate).
const defaultPinIterations = 20000;

/// Consecutive failures allowed before a temporary lock.
const pinAttemptsBeforeLock = 5;

/// Session locked after this period without touching the screen.
const inactivityLock = Duration(minutes: 5);

final _pinPattern = RegExp(r'^\d{6}$');

void validatePin(String pin, String confirmation) {
  if (!_pinPattern.hasMatch(pin)) {
    throw const BusinessException('Le code PIN doit contenir 6 chiffres.');
  }
  if (pin != confirmation) {
    throw const BusinessException('Les deux codes PIN sont différents.');
  }
  if (RegExp(r'^(\d)\1{5}$').hasMatch(pin) ||
      '0123456789'.contains(pin) ||
      '9876543210'.contains(pin)) {
    throw const BusinessException(
      'Code trop simple : évitez 000000, 123456 ou 654321.',
    );
  }
}

String validateUserName(String name) {
  final trimmed = name.trim();
  if (trimmed.length < 2 || trimmed.length > 60) {
    throw const BusinessException('Le nom doit contenir 2 à 60 caractères.');
  }
  return trimmed;
}

/// PBKDF2-HMAC-SHA256 with a single 32-byte block (RFC 8018).
List<int> pbkdf2Sha256(List<int> password, List<int> salt, int iterations) {
  final hmac = Hmac(sha256, password);
  var block = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final result = List<int>.of(block);
  for (var i = 1; i < iterations; i++) {
    block = hmac.convert(block).bytes;
    for (var j = 0; j < result.length; j++) {
      result[j] ^= block[j];
    }
  }
  return result;
}

class PinHash {
  const PinHash(this.hash, this.salt, this.iterations);
  final String hash, salt;
  final int iterations;
}

/// Hashing strategy; tests inject a fast one, the app runs it in an isolate.
abstract interface class PinHasher {
  Future<PinHash> create(String pin);
  Future<bool> verify(String pin, PinHash stored);
}

class Pbkdf2PinHasher implements PinHasher {
  const Pbkdf2PinHasher({this.iterations = defaultPinIterations});
  final int iterations;

  @override
  Future<PinHash> create(String pin) async {
    final random = Random.secure();
    final salt = base64Encode(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
    final hash = await compute(_derive, (pin, salt, iterations));
    return PinHash(hash, salt, iterations);
  }

  @override
  Future<bool> verify(String pin, PinHash stored) async {
    final candidate = await compute(_derive, (
      pin,
      stored.salt,
      stored.iterations,
    ));
    return _sameBytes(base64Decode(candidate), base64Decode(stored.hash));
  }
}

String _derive((String, String, int) input) => base64Encode(
  pbkdf2Sha256(utf8.encode(input.$1), base64Decode(input.$2), input.$3),
);

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// Lock after repeated failures: 1, 2, 4… minutes, capped at 15.
Duration lockDuration(int failures) {
  if (failures < pinAttemptsBeforeLock) return Duration.zero;
  return Duration(minutes: min(15, 1 << (failures - pinAttemptsBeforeLock)));
}
