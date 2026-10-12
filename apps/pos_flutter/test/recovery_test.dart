import 'dart:convert';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mono_pos/auth/pin.dart';
import 'package:mono_pos/auth/recovery.dart';
import 'package:mono_pos/data/database.dart';
import 'package:mono_pos/data/pos_repository.dart';
import 'package:mono_pos/data/user_repository.dart';
import 'package:mono_pos/domain/models.dart';

void main() {
  test('format du code de secours', () {
    final code = generateRecoveryCode(Random(1));
    expect(code, matches(RegExp(r'^[A-Z2-9]{4}(-[A-Z2-9]{4}){3}$')));
    expect(code, isNot(matches(RegExp('[01OIL]'))));
    expect(
      normalizeRecoveryCode(' ${code.toLowerCase()} '),
      code.replaceAll('-', ''),
    );
    for (final bad in ['', 'ABCD-EFGH-JKMN', 'ABCD-EFGH-JKMN-PQR0']) {
      expect(
        () => normalizeRecoveryCode(bad),
        throwsA(isA<BusinessException>()),
      );
    }
  });

  group('récupération de l’accès administrateur', () {
    late PosDatabase db;
    late PosRepository repo;
    late UserRepository users;
    var now = DateTime.utc(2026, 10, 12, 9);

    setUp(() async {
      now = DateTime.utc(2026, 10, 12, 9);
      db = PosDatabase(NativeDatabase.memory());
      repo = PosRepository(db, now: () => now);
      await repo.initialize();
      users = UserRepository(
        repo,
        hasher: const Pbkdf2PinHasher(iterations: 10),
      );
    });
    tearDown(() => db.close());

    Future<List<Map<String, dynamic>>> events() async => [
      for (final e in await db.select(db.outboxEntries).get())
        jsonDecode(e.envelope) as Map<String, dynamic>,
    ];

    test(
      'le code remplace le PIN oublié, une seule fois, et se renouvelle',
      () async {
        final admin = await users.createFirstAdmin(
          'Admin TEST',
          '481516',
          '481516',
        );
        expect(await users.recoveryCreatedAt(), isNull);
        final code = await users.createRecoveryCode(admin);
        expect(await users.recoveryCreatedAt(), isNotNull);
        // Hash only: the code is never stored in clear.
        final stored = await db.select(db.shopSettings).get();
        expect(
          stored.map((s) => s.value).join(),
          isNot(contains(code.replaceAll('-', ''))),
        );

        final (actor, next) = await users.recoverAdmin(
          code,
          admin.id,
          '730194',
          '730194',
        );
        expect(actor.id, admin.id);
        expect(next, isNot(code));
        expect((await users.authenticate(admin.id, '730194')).id, admin.id);
        await expectLater(
          users.authenticate(admin.id, '481516'),
          throwsA(isA<BusinessException>()),
        );
        // Single use: the old code no longer works, the new one does.
        await expectLater(
          users.recoverAdmin(code, admin.id, '285713', '285713'),
          throwsA(isA<BusinessException>()),
        );
        await users.recoverAdmin(next, admin.id, '285713', '285713');

        final log = await events();
        final recovered = log.where((e) => e['kind'] == 'user.admin_recovered');
        expect(recovered.map((e) => e['actor_id']), [admin.id, admin.id]);
        expect(recovered.first['payload'], {'user_id': admin.id});
        expect(
          log.where((e) => e['kind'] == 'security.recovery_code_created'),
          hasLength(3),
        );
        // Neither PIN nor code in the outbox.
        final text = jsonEncode(log);
        for (final secret in [
          '730194',
          '285713',
          code,
          next,
          code.replaceAll('-', ''),
        ]) {
          expect(text, isNot(contains(secret)));
        }
      },
    );

    test('vendeur refusé, essais limités, pas de code', () async {
      final admin = await users.createFirstAdmin(
        'Admin TEST',
        '481516',
        '481516',
      );
      await expectLater(
        users.recoverAdmin('ABCD-EFGH-JKMN-PQRS', admin.id, '730194', '730194'),
        throwsA(
          isA<BusinessException>().having(
            (e) => e.message,
            'message',
            contains('Aucun code'),
          ),
        ),
      );
      final code = await users.createRecoveryCode(admin);
      await users.createUser(
        admin,
        name: 'Vendeur TEST',
        role: Role.seller,
        pin: '927384',
        confirmation: '927384',
      );
      final seller = (await users.users()).firstWhere(
        (u) => u.role == Role.seller,
      );
      await expectLater(
        users.recoverAdmin(code, seller.id, '730194', '730194'),
        throwsA(isA<BusinessException>()),
      );
      for (var i = 0; i < pinAttemptsBeforeLock; i++) {
        await expectLater(
          users.recoverAdmin(
            'ABCD-EFGH-JKMN-PQRS',
            admin.id,
            '730194',
            '730194',
          ),
          throwsA(isA<BusinessException>()),
        );
      }
      // Locked even with the right code, until the delay has passed.
      await expectLater(
        users.recoverAdmin(code, admin.id, '730194', '730194'),
        throwsA(
          isA<BusinessException>().having(
            (e) => e.message,
            'message',
            contains('Trop d’essais'),
          ),
        ),
      );
      now = now.add(const Duration(minutes: 2));
      await users.recoverAdmin(code, admin.id, '730194', '730194');
      await expectLater(
        users.createRecoveryCode(seller.actor),
        throwsA(isA<BusinessException>()),
      );
    });
  });
}
