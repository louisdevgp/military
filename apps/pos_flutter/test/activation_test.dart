import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mono_pos/application/pos_controller.dart';
import 'package:mono_pos/application/session_controller.dart';
import 'package:mono_pos/data/database.dart';
import 'package:mono_pos/data/pos_repository.dart';
import 'package:mono_pos/domain/models.dart';
import 'package:mono_pos/sync/secure_store.dart';
import 'package:mono_pos/sync/sync_service.dart';

const admin = Actor('a', 'Admin', Role.admin);
const seller = Actor('s', 'Vendeur', Role.seller);
final credential = 'mtc1.${'c' * 36}.${'S' * 43}';

class AckServer extends SyncTransport {
  final received = <String>[];
  @override
  Future<Map<String, dynamic>> send(Map<String, dynamic> e) async {
    received.add(e['id'] as String);
    return {
      'id': e['id'],
      'terminal_id': e['terminal_id'],
      'sequence': e['sequence'],
      'status': 'committed',
      'received_at': '2026-10-12T12:00:00Z',
    };
  }
}

void main() {
  group('activation par code', () {
    late PosDatabase db;
    late PosRepository repo;
    late MemorySecureStore store;
    late AckServer server;
    final calls = <(String, String)>[];
    Object? refusal;

    setUp(() async {
      db = PosDatabase(NativeDatabase.memory());
      repo = PosRepository(db);
      await repo.initialize();
      store = MemorySecureStore();
      server = AckServer();
      calls.clear();
      refusal = null;
    });
    tearDown(() => db.close());

    ProviderContainer container(Actor actor) {
      final c = ProviderContainer(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          currentActorProvider.overrideWithValue(actor),
          secureStoreProvider.overrideWithValue(store),
          syncTransportFactoryProvider.overrideWithValue((_, secret) {
            expect(secret, credential);
            return server;
          }),
          terminalActivatorProvider.overrideWithValue((
            origin,
            terminal,
            code,
          ) async {
            calls.add((terminal, code));
            if (refusal != null) throw refusal!;
            return credential;
          }),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test(
      'réservée à l’administrateur, code vérifié, identifiant au coffre',
      () async {
        await repo.createItem(
          actor: admin,
          category: 'TEST',
          name: 'Béret',
          sku: 'BER',
          label: '58',
          price: 5000,
          stock: 5,
        );
        expect(
          await container(seller)
              .read(posProvider.notifier)
              .activateSync('https://api.test', 'ABCD-EFGH-JKMN'),
          isFalse,
        );
        final c = container(admin);
        final pos = c.read(posProvider.notifier);
        await pos.refresh();
        expect(
          await pos.activateSync('https://api.test', 'ABCD-EFGH'),
          isFalse,
        );
        expect(
          await pos.activateSync('https://api.test', 'ABCD-EFGH-JKM0'),
          isFalse,
        );
        expect(calls, isEmpty);
        refusal = const SyncFailure('HTTP_401:ACTIVATION_INVALID');
        expect(
          await pos.activateSync('https://api.test', 'abcd efgh jkmn'),
          isFalse,
        );
        expect(
          c.read(posProvider).message,
          contains('Code d’activation refusé'),
        );
        expect(store.values, isEmpty);
        refusal = null;
        expect(
          await pos.activateSync('https://api.test/', 'abcd-efgh-jkmn'),
          isTrue,
        );
        expect(calls.last, (c.read(posProvider).terminalId, 'ABCDEFGHJKMN'));
        expect(store.values['sync_token'], credential);
        expect(store.values['sync_origin'], 'https://api.test');
        expect(c.read(posProvider).syncActivated, isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(server.received, hasLength(1));
      },
    );
  });

  group('jetons courts', () {
    final origin = Uri.parse('https://api.test');
    final envelope = {'id': 'e1', 'terminal_id': 't', 'sequence': 1};
    final ack = jsonEncode({...envelope, 'status': 'committed'});

    test('activation : l’identifiant renvoyé est vérifié', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/private/auth/activate');
        expect(jsonDecode(request.body), {
          'terminal_id': 't',
          'code': 'ABCDEFGHJKMN',
        });
        return http.Response(
          jsonEncode({
            'credential': credential,
            'access_token': 'x',
            'expires_at': '2026-10-12T12:15:00Z',
          }),
          200,
        );
      });
      expect(
        await HttpSyncTransport.activate(
          origin,
          't',
          'ABCDEFGHJKMN',
          client: client,
        ),
        credential,
      );
      final refused = MockClient(
        (_) async => http.Response('{"detail":"ACTIVATION_INVALID"}', 401),
      );
      await expectLater(
        HttpSyncTransport.activate(
          origin,
          't',
          'ABCDEFGHJKMN',
          client: refused,
        ),
        throwsA(
          isA<SyncFailure>().having(
            (f) => f.code,
            'code',
            'HTTP_401:ACTIVATION_INVALID',
          ),
        ),
      );
    });

    test(
      'jeton obtenu une fois, renouvelé quand le serveur le dit expiré',
      () async {
        final log = <String>[];
        var issued = 0;
        var expireNext = false;
        final client = MockClient((request) async {
          final auth = request.headers['Authorization']!;
          log.add('${request.url.path} $auth');
          if (request.url.path == '/api/private/auth/token') {
            expect(auth, 'Bearer $credential');
            issued++;
            return http.Response(
              jsonEncode({
                'access_token': 'mta1.jeton$issued',
                'expires_at': DateTime.now()
                    .toUtc()
                    .add(const Duration(minutes: 15))
                    .toIso8601String(),
              }),
              200,
            );
          }
          if (expireNext) {
            expireNext = false;
            return http.Response('{"detail":"TOKEN_EXPIRED"}', 401);
          }
          return http.Response(ack, 200);
        });
        final transport = HttpSyncTransport(origin, credential, client: client);
        await transport.send(envelope);
        await transport.send(envelope);
        expect(issued, 1, reason: 'jeton gardé tant qu’il est valable');
        expireNext = true;
        await transport.send(envelope);
        expect(issued, 2);
        expect(log.last, '/api/private/sync/events Bearer mta1.jeton2');
        // The device credential itself never reaches the sync endpoints.
        expect(
          log.where(
            (l) => l.startsWith('/api/private/sync') && l.contains(credential),
          ),
          isEmpty,
        );
      },
    );

    test('ancien jeton de recette envoyé tel quel', () async {
      final legacy = 'T' * 43;
      final client = MockClient((request) async {
        expect(request.url.path, '/api/private/sync/events');
        expect(request.headers['Authorization'], 'Bearer $legacy');
        return http.Response(ack, 200);
      });
      await HttpSyncTransport(origin, legacy, client: client).send(envelope);
    });
  });
}
