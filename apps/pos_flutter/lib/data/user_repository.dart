import 'package:drift/drift.dart';

import '../auth/pin.dart';
import '../domain/models.dart';
import 'database.dart';
import 'pos_repository.dart';

/// Local operators, PIN checks and their audit events. PIN material stays in
/// this terminal: events carry identities and roles, never hashes.
class UserRepository {
  UserRepository(this.pos, {this.hasher = const Pbkdf2PinHasher()});
  final PosRepository pos;
  final PinHasher hasher;
  PosDatabase get db => pos.db;
  DateTime _now() => pos.now().toUtc();

  Future<bool> hasUsers() async =>
      await (db.select(db.users)..limit(1)).getSingleOrNull() != null;

  Future<List<LocalUser>> users({bool includeInactive = false}) async {
    final query = db.select(db.users)
      ..orderBy([(u) => OrderingTerm.asc(u.name)]);
    if (!includeInactive) query.where((u) => u.active.equals(true));
    return [for (final row in await query.get()) _user(row)];
  }

  LocalUser _user(User row) => LocalUser(
    id: row.id,
    name: row.name,
    role: Role.values.byName(row.role),
    active: row.active,
    lockedUntil: row.lockedUntil == null
        ? null
        : DateTime.parse(row.lockedUntil!),
  );

  /// First administrator, created at activation. No predefined account.
  Future<Actor> createFirstAdmin(
    String name,
    String pin,
    String confirmation,
  ) async {
    final clean = validateUserName(name);
    validatePin(pin, confirmation);
    final hash = await hasher.create(pin);
    final actor = Actor(PosRepository.uuid.v4(), clean, Role.admin);
    await db.transaction(() async {
      if (await hasUsers()) {
        throw const BusinessException('Le terminal est déjà activé.');
      }
      await _insert(actor, hash);
      await pos.appendEvent(
        PosRepository.uuid.v4(),
        'user.created',
        actor,
        _now().toIso8601String(),
        {'user_id': actor.id, 'name': clean, 'role': 'admin'},
      );
    });
    return actor;
  }

  Future<void> createUser(
    Actor admin, {
    required String name,
    required Role role,
    required String pin,
    required String confirmation,
  }) async {
    admin.requireAdmin();
    final clean = validateUserName(name);
    validatePin(pin, confirmation);
    final hash = await hasher.create(pin);
    await db.transaction(() async {
      await _requireActiveAdmin(admin);
      final duplicate = await (db.select(
        db.users,
      )..where((u) => u.name.lower().equals(clean.toLowerCase()))).get();
      if (duplicate.isNotEmpty) {
        throw const BusinessException('Ce nom d’utilisateur existe déjà.');
      }
      final user = Actor(PosRepository.uuid.v4(), clean, role);
      await _insert(user, hash);
      await pos.appendEvent(
        PosRepository.uuid.v4(),
        'user.created',
        admin,
        _now().toIso8601String(),
        {'user_id': user.id, 'name': clean, 'role': role.name},
      );
    });
  }

  Future<void> setActive(Actor admin, String userId, bool active) async {
    admin.requireAdmin();
    if (userId == admin.id && !active) {
      throw const BusinessException(
        'Vous ne pouvez pas désactiver votre propre accès.',
      );
    }
    await db.transaction(() async {
      await _requireActiveAdmin(admin);
      final user = await _get(userId);
      if (user.active == active) return;
      if (!active && user.role == Role.admin.name) {
        final admins =
            await (db.select(db.users)..where(
                  (u) => u.role.equals(Role.admin.name) & u.active.equals(true),
                ))
                .get();
        if (admins.length <= 1) {
          throw const BusinessException(
            'Au moins un administrateur actif est requis.',
          );
        }
      }
      await (db.update(db.users)..where((u) => u.id.equals(userId))).write(
        UsersCompanion(active: Value(active)),
      );
      await pos.appendEvent(
        PosRepository.uuid.v4(),
        'user.updated',
        admin,
        _now().toIso8601String(),
        {'user_id': userId, 'active': active},
      );
    });
  }

  Future<void> resetPin(
    Actor admin,
    String userId,
    String pin,
    String confirmation,
  ) async {
    admin.requireAdmin();
    validatePin(pin, confirmation);
    final hash = await hasher.create(pin);
    await db.transaction(() async {
      await _requireActiveAdmin(admin);
      await _get(userId);
      await (db.update(db.users)..where((u) => u.id.equals(userId))).write(
        UsersCompanion(
          pinHash: Value(hash.hash),
          pinSalt: Value(hash.salt),
          pinIterations: Value(hash.iterations),
          failedAttempts: const Value(0),
          lockedUntil: const Value(null),
        ),
      );
      // Audit only: the new PIN is never part of the event.
      await pos.appendEvent(
        PosRepository.uuid.v4(),
        'user.pin_reset',
        admin,
        _now().toIso8601String(),
        {'user_id': userId},
      );
    });
  }

  /// Checks a PIN with persistent failure counting and temporary locks.
  Future<Actor> authenticate(String userId, String pin) async {
    final row = await _get(userId);
    if (!row.active) {
      throw const BusinessException('Cet accès est désactivé.');
    }
    final now = _now();
    if (row.lockedUntil != null) {
      final until = DateTime.parse(row.lockedUntil!);
      if (until.isAfter(now)) {
        final minutes = until.difference(now).inSeconds ~/ 60 + 1;
        throw BusinessException(
          'Trop d’essais. Réessayez dans $minutes min ou demandez à un administrateur.',
        );
      }
    }
    final ok = await hasher.verify(
      pin,
      PinHash(row.pinHash, row.pinSalt, row.pinIterations),
    );
    if (ok) {
      await (db.update(db.users)..where((u) => u.id.equals(userId))).write(
        const UsersCompanion(
          failedAttempts: Value(0),
          lockedUntil: Value(null),
        ),
      );
      return Actor(row.id, row.name, Role.values.byName(row.role));
    }
    final failures = await db.transaction(() async {
      final current = await _get(userId);
      final next = current.failedAttempts + 1;
      final lock = lockDuration(next);
      await (db.update(db.users)..where((u) => u.id.equals(userId))).write(
        UsersCompanion(
          failedAttempts: Value(next),
          lockedUntil: Value(
            lock == Duration.zero ? null : now.add(lock).toIso8601String(),
          ),
        ),
      );
      return next;
    });
    final left = pinAttemptsBeforeLock - failures;
    throw BusinessException(
      left > 0
          ? 'Code PIN incorrect. $left essai(s) avant blocage temporaire.'
          : 'Code PIN incorrect. Accès bloqué ${lockDuration(failures).inMinutes} min.',
    );
  }

  Future<User> _get(String userId) async {
    final row = await (db.select(
      db.users,
    )..where((u) => u.id.equals(userId))).getSingleOrNull();
    if (row == null) throw const BusinessException('Utilisateur introuvable.');
    return row;
  }

  Future<void> _requireActiveAdmin(Actor admin) async {
    final row = await (db.select(
      db.users,
    )..where((u) => u.id.equals(admin.id))).getSingleOrNull();
    if (row == null || !row.active || row.role != Role.admin.name) {
      throw const BusinessException(
        'Cette opération est réservée à l’administrateur.',
      );
    }
  }

  Future<void> _insert(Actor actor, PinHash hash) => db
      .into(db.users)
      .insert(
        UsersCompanion.insert(
          id: actor.id,
          name: actor.name,
          role: actor.role.name,
          pinHash: hash.hash,
          pinSalt: hash.salt,
          pinIterations: hash.iterations,
          createdAt: _now().toIso8601String(),
        ),
      );
}
