import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/pin.dart';
import '../data/user_repository.dart';
import '../domain/models.dart';
import 'pos_controller.dart';

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => UserRepository(ref.read(repositoryProvider)),
);

final sessionProvider = NotifierProvider<SessionController, SessionState>(
  SessionController.new,
);

/// Operator of every business operation. Null while the terminal is locked.
final currentActorProvider = Provider<Actor?>(
  (ref) => ref.watch(sessionProvider).actor,
);

class SessionState {
  const SessionState({
    this.loading = true,
    this.activated = false,
    this.users = const [],
    this.actor,
    this.busy = false,
    this.error,
  });
  final bool loading, activated, busy;
  final List<LocalUser> users;
  final Actor? actor;
  final String? error;

  SessionState copy({
    bool? loading,
    bool? activated,
    List<LocalUser>? users,
    Actor? Function()? actor,
    bool? busy,
    String? error,
  }) => SessionState(
    loading: loading ?? this.loading,
    activated: activated ?? this.activated,
    users: users ?? this.users,
    actor: actor == null ? this.actor : actor(),
    busy: busy ?? this.busy,
    error: error,
  );
}

class SessionController extends Notifier<SessionState> {
  Timer? _idle;

  UserRepository get _users => ref.read(userRepositoryProvider);

  @override
  SessionState build() {
    ref.onDispose(() => _idle?.cancel());
    Future.microtask(load);
    return const SessionState();
  }

  Future<void> load() async {
    try {
      final activated = await _users.hasUsers();
      state = state.copy(
        loading: false,
        activated: activated,
        users: await _users.users(),
      );
    } catch (_) {
      state = state.copy(
        loading: false,
        error: 'Lecture des utilisateurs impossible. Rouvrez l’application.',
      );
    }
  }

  Future<bool> setup(String name, String pin, String confirmation) =>
      _guard(() async {
        final actor = await _users.createFirstAdmin(name, pin, confirmation);
        state = state.copy(
          activated: true,
          users: await _users.users(),
          actor: () => actor,
        );
        touch();
      });

  Future<bool> login(String userId, String pin) => _guard(() async {
    final actor = await _users.authenticate(userId, pin);
    state = state.copy(actor: () => actor);
    touch();
  });

  void lock() {
    _idle?.cancel();
    state = state.copy(actor: () => null);
    unawaited(refreshUsers());
  }

  /// Restarts the inactivity countdown on every screen interaction.
  void touch() {
    if (state.actor == null) return;
    _idle?.cancel();
    _idle = Timer(inactivityLock, _idleLock);
  }

  /// Never interrupts a sale validation or print in progress.
  void _idleLock() {
    if (ref.read(posProvider).busy) {
      touch();
    } else {
      lock();
    }
  }

  Actor get _admin =>
      state.actor ?? (throw const BusinessException('Session verrouillée.'));

  Future<bool> createUser(
    String name,
    Role role,
    String pin,
    String confirmation,
  ) => _guard(() async {
    await _users.createUser(
      _admin,
      name: name,
      role: role,
      pin: pin,
      confirmation: confirmation,
    );
    await refreshUsers();
  });

  Future<bool> setActive(String userId, bool active) => _guard(() async {
    await _users.setActive(_admin, userId, active);
    await refreshUsers();
  });

  Future<bool> resetPin(String userId, String pin, String confirmation) =>
      _guard(() => _users.resetPin(_admin, userId, pin, confirmation));

  Future<List<LocalUser>> allUsers() => _users.users(includeInactive: true);

  Future<void> refreshUsers() async {
    try {
      state = state.copy(users: await _users.users());
    } catch (_) {
      state = state.copy(error: 'Liste des utilisateurs indisponible.');
    }
  }

  Future<bool> _guard(Future<void> Function() body) async {
    if (state.busy) return false;
    state = state.copy(busy: true);
    try {
      await body();
      state = state.copy(busy: false);
      return true;
    } on BusinessException catch (e) {
      state = state.copy(busy: false, error: e.message);
    } catch (_) {
      state = state.copy(
        busy: false,
        error: 'Opération non confirmée. Réessayez.',
      );
    }
    return false;
  }
}
