import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mono_pos/data/database.dart';
import 'package:mono_pos/data/pos_repository.dart';

void main() {
  test(
    'ouvre le schéma v1 figé sans réinitialiser identité ni compteurs',
    () async {
      final schema = File('drift_schemas/schema_v1.sql').readAsStringSync();
      final db = PosDatabase(
        NativeDatabase.memory(
          setup: (raw) {
            raw.execute(schema);
            raw.execute(
              'INSERT INTO terminal_states (singleton, terminal_id, prefix, event_sequence, sale_sequence) VALUES (?, ?, ?, ?, ?)',
              [1, 'f82996d6-4140-4240-b599-d74545ec5101', 'TF82996D6', 27, 12],
            );
            raw.execute(
              "INSERT INTO categories VALUES ('category-before', 'Test existant')",
            );
            raw.execute(
              "INSERT INTO products VALUES ('product-before', 'category-before', 'Article existant', 0)",
            );
            raw.execute(
              "INSERT INTO variants VALUES ('variant-before', 'product-before', 'BEFORE', '42', 500, 7, 1)",
            );
            raw.execute('INSERT INTO sales VALUES (?, ?, ?, ?, ?, ?)', [
              'sale-before',
              'TF82996D6-2026-000012',
              'hash-before',
              '2026-10-06T10:00:00Z',
              '{"id":"sale-before","total":500}',
              500,
            ]);
            raw.execute(
              "INSERT INTO outbox_entries (id, sequence, envelope) VALUES ('event-before', 27, '{}')",
            );
          },
        ),
      );
      final repo = PosRepository(db);
      await repo.initialize();
      final state = await repo.terminal();
      expect(state.terminalId, 'f82996d6-4140-4240-b599-d74545ec5101');
      expect(state.eventSequence, 27);
      expect(state.saleSequence, 12);
      final existing = (await repo.catalog()).single;
      expect(existing.stock, 7);
      expect(existing.price, 500);
      expect(existing.photoPaths, isEmpty);
      expect((await repo.history()).single['id'], 'sale-before');
      expect(await repo.pendingCount(), 1);
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        ),
        7,
      );
      expect(await db.select(db.users).get(), isEmpty);
      expect(await db.select(db.saleCorrections).get(), isEmpty);
      expect(
        await db.customSelect('SELECT * FROM local_product_photos').get(),
        isEmpty,
      );
      expect(
        (await db.customSelect('PRAGMA integrity_check').getSingle())
            .data
            .values
            .single,
        'ok',
      );
      await db.close();
    },
  );

  test('schéma v2 figé → v3 : utilisateurs et corrections ajoutés', () async {
    final schema = File('drift_schemas/schema_v2.sql').readAsStringSync();
    final db = PosDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute(schema);
          raw.execute(
            'INSERT INTO terminal_states (singleton, terminal_id, prefix, event_sequence, sale_sequence) VALUES (?, ?, ?, ?, ?)',
            [1, 'f82996d6-4140-4240-b599-d74545ec5101', 'TF82996D6', 3, 1],
          );
          raw.execute('INSERT INTO sales VALUES (?, ?, ?, ?, ?, ?)', [
            'sale-v2',
            'TF82996D6-2026-000001',
            'hash',
            '2026-10-06T10:00:00Z',
            '{"id":"sale-v2","total":500}',
            500,
          ]);
        },
      ),
    );
    final repo = PosRepository(db);
    await repo.initialize();
    expect((await repo.terminal()).saleSequence, 1);
    expect((await repo.history()).single['id'], 'sale-v2');
    expect(await db.select(db.users).get(), isEmpty);
    expect(
      (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
        'user_version',
      ),
      7,
    );
    expect((await db.customSelect('PRAGMA foreign_key_check').get()), isEmpty);
    await db.close();
  });
}
