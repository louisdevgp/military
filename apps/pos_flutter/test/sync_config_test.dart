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
import 'package:uuid/uuid.dart';

const admin = Actor('a', 'Admin', Role.admin);
const seller = Actor('s', 'Vendeur', Role.seller);
final token = 'T' * 43;

/// Acknowledges every event, or refuses them with [refuse].
class FakeServer extends SyncTransport {
  String? refuse;
  final received = <String>[];
  int wakes = 0;
  @override
  Future<void> wake() async => wakes++;
  @override
  Future<Map<String, dynamic>> send(Map<String, dynamic> e) async {
    if (refuse != null) throw SyncFailure(refuse!);
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
  late PosDatabase db;
  late PosRepository repo;
  late MemorySecureStore store;
  late FakeServer server;

  setUp(() async {
    db = PosDatabase(NativeDatabase.memory());
    repo = PosRepository(db);
    await repo.initialize();
    store = MemorySecureStore();
    server = FakeServer();
  });
  tearDown(() => db.close());

  ProviderContainer container(Actor actor) {
    final c = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        currentActorProvider.overrideWithValue(actor),
        secureStoreProvider.overrideWithValue(store),
        syncTransportFactoryProvider.overrideWithValue((_, _) => server),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<void> sell(String id) => repo.checkout(
    seller,
    SaleRequest(
      id: const Uuid().v4(),
      quantities: {id: 1},
      paymentMode: PaymentMode.mobileMoney,
    ),
  );

  test(
    'serveur enregistré de façon sécurisée et retrouvé au redémarrage',
    () async {
      final id = await repo.createItem(
        actor: admin,
        category: 'TEST',
        name: 'Béret',
        sku: 'BER',
        label: '58',
        price: 5000,
        stock: 5,
      );
      final asSeller = container(seller).read(posProvider.notifier);
      expect(await asSeller.saveSyncConfig('https://api.test', token), isFalse);
      final c = container(admin);
      final pos = c.read(posProvider.notifier);
      await pos.refresh();
      expect(await pos.saveSyncConfig('http://api.test', token), isFalse);
      expect(await pos.saveSyncConfig('https://api.test', 'court'), isFalse);
      expect(store.values, isEmpty);
      expect(await pos.saveSyncConfig('https://api.test/', token), isTrue);
      expect(store.values['sync_origin'], 'https://api.test');
      expect(store.values['sync_token'], token);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(server.received, hasLength(1), reason: 'catalogue envoyé');
      expect(c.read(posProvider).syncStatus.pending, 0);

      // Restart: a new controller finds the server and sends in background.
      await sell(id);
      final restarted = container(admin);
      final again = restarted.read(posProvider.notifier);
      await again.refresh();
      expect(restarted.read(posProvider).syncOrigin, 'https://api.test');
      expect(restarted.read(posProvider).syncStatus.pending, 1);
      await again.runAutoSync();
      expect(server.received, hasLength(2));
      expect(restarted.read(posProvider).syncStatus.pending, 0);
      expect(restarted.read(posProvider).lastSync, isNotNull);
    },
  );

  test('erreur serveur conservée avec son code, puis arrêt et oubli', () async {
    final id = await repo.createItem(
      actor: admin,
      category: 'TEST',
      name: 'Béret',
      sku: 'BER',
      label: '58',
      price: 5000,
      stock: 5,
    );
    store.values
      ..['sync_origin'] = 'https://api.test'
      ..['sync_token'] = token;
    final c = container(admin);
    final pos = c.read(posProvider.notifier);
    server.refuse = 'HTTP_409:SALE_NUMBER_MISMATCH';
    await pos.refresh();
    await pos.runAutoSync();
    final status = c.read(posProvider).syncStatus;
    expect(status.pending, 1);
    expect(status.errorCode, 'HTTP_409:SALE_NUMBER_MISMATCH');
    expect(status.attempts, 1);
    expect(status.nextAttemptAt, isNotNull);
    expect(syncErrorLabel(status.errorCode!), contains('SALE_NUMBER_MISMATCH'));
    // Background runs respect the retry delay: nothing is resent yet.
    server.refuse = null;
    await pos.runAutoSync();
    expect(server.received, isEmpty);
    // A manual sync retries immediately.
    await pos.synchronize();
    expect(server.received, hasLength(1));
    await sell(id);
    await pos.setAutoSync(false);
    expect(store.values['sync_auto'], 'false');
    await pos.runAutoSync();
    await pos.refresh();
    expect(server.received, hasLength(1));
    expect(
      c.read(posProvider).syncStatus.pending,
      1,
      reason: 'automatique coupé',
    );
    await pos.clearSyncConfig();
    expect(store.values.containsKey('sync_token'), isFalse);
    expect(c.read(posProvider).syncOrigin, isNull);
  });

  test('code technique du serveur conservé, jamais le contenu', () async {
    var body = jsonEncode({'detail': 'TOKEN_EXPIRED'});
    final client = MockClient((_) async => http.Response(body, 401));
    final transport = HttpSyncTransport(
      Uri.parse('https://api.test'),
      token,
      client: client,
    );
    await expectLater(
      transport.send({'id': 'x'}),
      throwsA(
        isA<SyncFailure>().having(
          (f) => f.code,
          'code',
          'HTTP_401:TOKEN_EXPIRED',
        ),
      ),
    );
    body = jsonEncode({'detail': 'contains client data: Kone'});
    await expectLater(
      transport.send({'id': 'x'}),
      throwsA(isA<SyncFailure>().having((f) => f.code, 'code', 'HTTP_401')),
    );
  });
}
