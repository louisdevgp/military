import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mono_pos/data/database.dart';
import 'package:mono_pos/data/pos_repository.dart';
import 'package:mono_pos/domain/models.dart';
import 'package:mono_pos/sync/sync_service.dart';

class FakeServer extends SyncTransport {
  bool loseResponse = true;
  bool invalidAck = false;
  int calls = 0;
  final Map<String, Map<String, dynamic>> committed = {};
  @override
  Future<Map<String, dynamic>> send(Map<String, dynamic> e) async {
    calls++;
    committed.putIfAbsent(e['id'] as String, () => e);
    if (loseResponse) {
      loseResponse = false;
      throw const SyncFailure('RESPONSE_LOST');
    }
    return {
      'id': invalidAck ? 'wrong' : e['id'],
      'terminal_id': e['terminal_id'],
      'sequence': e['sequence'],
      'status': 'committed',
      'received_at': '2026-10-06T12:00:00Z',
    };
  }
}

void main() {
  late PosDatabase db;
  late PosRepository repo;
  late FakeServer server;
  const actor = Actor('test-admin', 'Test', Role.admin);
  setUp(() async {
    db = PosDatabase(NativeDatabase.memory());
    repo = PosRepository(db);
    await repo.initialize();
    for (final sku in ['A', 'B']) {
      await repo.createItem(
        actor: actor,
        category: 'Test',
        name: 'Test',
        sku: sku,
        label: 'Test',
        price: 10,
        stock: 1,
      );
    }
    server = FakeServer();
  });
  tearDown(() => db.close());

  test('réponse perdue : blocage ordre, délai persistant, rejeu sûr', () async {
    final sync = SyncService(
      db,
      server,
      now: () => DateTime.utc(2026, 10, 6, 12),
    );
    await expectLater(sync.synchronize(), throwsA(isA<BusinessException>()));
    expect(server.committed.length, 1);
    expect(server.calls, 1);
    expect(await repo.pendingCount(), 2);
    expect(await sync.synchronize(), 0);
    expect(server.calls, 1);
    final entries = await db.select(db.outboxEntries).get();
    expect(entries.first.attempts, 1);
    expect(entries.first.errorCode, 'RESPONSE_LOST');
    expect(await sync.synchronize(manual: true), 2);
    expect(server.committed.length, 2);
    expect(await repo.pendingCount(), 0);
    expect((await repo.terminal()).lastSyncAt, isNotNull);
    expect((await repo.catalog()).every((v) => v.stock == 1), isTrue);
  });

  test('mauvais accusé ne marque jamais une opération synchronisée', () async {
    server
      ..loseResponse = false
      ..invalidAck = true;
    await expectLater(
      SyncService(db, server).synchronize(),
      throwsA(isA<BusinessException>()),
    );
    expect(await repo.pendingCount(), 2);
    expect((await repo.terminal()).lastSyncAt, isNull);
  });
}
