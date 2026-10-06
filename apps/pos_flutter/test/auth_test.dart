import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mono_pos/auth/pin.dart';
import 'package:mono_pos/data/database.dart';
import 'package:mono_pos/data/pos_repository.dart';
import 'package:mono_pos/data/user_repository.dart';
import 'package:mono_pos/domain/models.dart';

void main() {
  test('PBKDF2-HMAC-SHA256 : vecteurs publiés', () {
    String derive(int c) => pbkdf2Sha256(
      utf8.encode('password'),
      utf8.encode('salt'),
      c,
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    expect(
      derive(1),
      '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
    );
    expect(
      derive(4096),
      'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
    );
  });

  test('règles du code PIN', () {
    expect(
      () => validatePin('48151', '48151'),
      throwsA(isA<BusinessException>()),
    );
    expect(
      () => validatePin('48a516', '48a516'),
      throwsA(isA<BusinessException>()),
    );
    expect(
      () => validatePin('481516', '481517'),
      throwsA(isA<BusinessException>()),
    );
    for (final weak in ['000000', '123456', '654321', '345678']) {
      expect(() => validatePin(weak, weak), throwsA(isA<BusinessException>()));
    }
    validatePin('481516', '481516');
    expect(lockDuration(4), Duration.zero);
    expect(lockDuration(5), const Duration(minutes: 1));
    expect(lockDuration(7), const Duration(minutes: 4));
    expect(lockDuration(30), const Duration(minutes: 15));
  });

  group('utilisateurs locaux', () {
    late PosDatabase db;
    late UserRepository users;
    var now = DateTime.utc(2026, 10, 6, 12);

    setUp(() async {
      now = DateTime.utc(2026, 10, 6, 12);
      db = PosDatabase(NativeDatabase.memory());
      final pos = PosRepository(db, now: () => now);
      await pos.initialize();
      users = UserRepository(
        pos,
        hasher: const Pbkdf2PinHasher(iterations: 10),
      );
    });
    tearDown(() => db.close());

    test('activation : un seul premier admin, événement sans PIN', () async {
      expect(await users.hasUsers(), isFalse);
      final admin = await users.createFirstAdmin(' Awa ', '481516', '481516');
      expect(admin.name, 'Awa');
      expect(admin.role, Role.admin);
      await expectLater(
        users.createFirstAdmin('Autre', '927384', '927384'),
        throwsA(isA<BusinessException>()),
      );
      final events = await db.select(db.outboxEntries).get();
      expect(events, hasLength(1));
      final envelope = jsonDecode(events.single.envelope) as Map;
      expect(envelope['kind'], 'user.created');
      expect(envelope['actor_id'], admin.id);
      expect(envelope['payload'], {
        'user_id': admin.id,
        'name': 'Awa',
        'role': 'admin',
      });
      final row = await db.select(db.users).getSingle();
      expect(events.single.envelope, isNot(contains(row.pinHash)));
      expect(events.single.envelope, isNot(contains('481516')));
      expect(row.pinHash, isNot(contains('481516')));
    });

    test('connexion, erreurs comptées puis blocage persistant', () async {
      final admin = await users.createFirstAdmin('Awa', '481516', '481516');
      expect((await users.authenticate(admin.id, '481516')).id, admin.id);
      for (var i = 0; i < 4; i++) {
        await expectLater(
          users.authenticate(admin.id, '000001'),
          throwsA(
            isA<BusinessException>().having(
              (e) => e.message,
              'message',
              contains('essai'),
            ),
          ),
        );
      }
      await expectLater(
        users.authenticate(admin.id, '000001'),
        throwsA(
          isA<BusinessException>().having(
            (e) => e.message,
            'message',
            contains('bloqué'),
          ),
        ),
      );
      // Even the right PIN is refused while locked.
      await expectLater(
        users.authenticate(admin.id, '481516'),
        throwsA(
          isA<BusinessException>().having(
            (e) => e.message,
            'message',
            contains('Trop d’essais'),
          ),
        ),
      );
      now = now.add(const Duration(minutes: 2));
      expect((await users.authenticate(admin.id, '481516')).id, admin.id);
      expect((await db.select(db.users).getSingle()).failedAttempts, 0);
    });

    test(
      'droits : vendeur limité, dernier admin protégé, PIN réinitialisé',
      () async {
        final admin = await users.createFirstAdmin('Awa', '481516', '481516');
        await users.createUser(
          admin,
          name: 'Koffi',
          role: Role.seller,
          pin: '927384',
          confirmation: '927384',
        );
        await expectLater(
          users.createUser(
            admin,
            name: 'koffi',
            role: Role.seller,
            pin: '927384',
            confirmation: '927384',
          ),
          throwsA(isA<BusinessException>()),
        );
        final seller = (await users.users())
            .firstWhere((u) => u.role == Role.seller)
            .actor;
        await expectLater(
          users.createUser(
            seller,
            name: 'Intrus',
            role: Role.admin,
            pin: '927384',
            confirmation: '927384',
          ),
          throwsA(isA<BusinessException>()),
        );
        await expectLater(
          users.setActive(admin, admin.id, false),
          throwsA(isA<BusinessException>()),
        );
        await users.resetPin(admin, seller.id, '135792', '135792');
        await expectLater(
          users.authenticate(seller.id, '927384'),
          throwsA(isA<BusinessException>()),
        );
        expect(
          (await users.authenticate(seller.id, '135792')).role,
          Role.seller,
        );
        await users.setActive(admin, seller.id, false);
        await expectLater(
          users.authenticate(seller.id, '135792'),
          throwsA(isA<BusinessException>()),
        );
        expect((await users.users()).map((u) => u.name), ['Awa']);
        final kinds = [
          for (final e in await (db.select(
            db.outboxEntries,
          )..orderBy([(e) => OrderingTerm.asc(e.sequence)])).get())
            jsonDecode(e.envelope)['kind'],
        ];
        expect(kinds, [
          'user.created',
          'user.created',
          'user.pin_reset',
          'user.updated',
        ]);
      },
    );
  });
}
