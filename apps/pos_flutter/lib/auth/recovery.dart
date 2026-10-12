import 'dart:math';

import '../domain/models.dart';

/// Settings keys of the administrator recovery code. Only its PBKDF2 hash is
/// stored, as "iterations:salt:hash"; the code itself is shown once.
const recoveryHashKey = 'admin_recovery';
const recoveryCreatedKey = 'admin_recovery_created_at';
const recoveryFailuresKey = 'admin_recovery_failures';
const recoveryLockedKey = 'admin_recovery_locked_until';

/// No 0/O, 1/I/L: the code is copied by hand on paper.
const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/// 16 characters from 31 symbols: about 79 bits, shown as XXXX-XXXX-XXXX-XXXX.
String generateRecoveryCode([Random? random]) {
  final source = random ?? Random.secure();
  final chars = [
    for (var i = 0; i < 16; i++) _alphabet[source.nextInt(_alphabet.length)],
  ];
  return [for (var i = 0; i < 16; i += 4) chars.sublist(i, i + 4).join()]
      .join('-');
}

/// Uppercase, without spaces or dashes; rejects anything else.
String normalizeRecoveryCode(String input) {
  final clean = input.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  if (clean.length != 16 ||
      clean.split('').any((c) => !_alphabet.contains(c))) {
    throw const BusinessException(
      'Code de secours invalide : 16 caractères, au format XXXX-XXXX-XXXX-XXXX.',
    );
  }
  return clean;
}
