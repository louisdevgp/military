import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mono_pos/auth/pin.dart';
import 'package:mono_pos/backup/backup_platform.dart';
import 'package:mono_pos/backup/backup_service.dart';
import 'package:mono_pos/backup/reconciler.dart';
import 'package:mono_pos/data/database.dart';
import 'package:mono_pos/data/finance_repository.dart';
import 'package:mono_pos/data/pos_repository.dart';
import 'package:mono_pos/data/user_repository.dart';
import 'package:mono_pos/domain/finance.dart';
import 'package:mono_pos/domain/models.dart';
import 'package:mono_pos/sync/sync_service.dart';
import 'package:uuid/uuid.dart';

/// Stand-in for BackupBridge: reversible « encryption » bound to the
/// passphrase, so a wrong passphrase is refused like AES-GCM would.
class FakePlatform implements BackupPlatform {
  Uint8List? saved;
  @override
  Future<Uint8List> encrypt(Uint8List data, String passphrase) async =>
      Uint8List.fromList([...utf8.encode('$passphrase|'), ...data]);
  @override
  Future<Uint8List> decrypt(Uint8List data, String passphrase) async {
    final prefix = utf8.encode('$passphrase|');
    if (data.length < prefix.length ||
        utf8.decode(data.sublist(0, prefix.length), allowMalformed: true) !=
            '$passphrase|') {
      throw const BusinessException('Mot de passe incorrect.');
    }
    return Uint8List.fromList(data.sublist(prefix.length));
  }

  @override
  Future<bool?> save(String name, Uint8List data) async {
    saved = data;
    return true;
  }

  @override
  Future<Uint8List?> open() async => saved;
  @override
  Future<void> relaunch() async {}
}

/// In-memory server keeping envelopes as received.
class FakeServer extends SyncTransport {
  FakeServer(this.terminalId);
  final String terminalId;
  final log = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> send(Map<String, dynamic> e) async {
    if (!log.any((x) => x['id'] == e['id'])) log.add(e);
    return {
      'id': e['id'],
      'terminal_id': e['terminal_id'],
      'sequence': e['sequence'],
      'status': 'committed',
      'received_at': '2026-10-12T12:00:00Z',
    };
  }

  @override
  Future<Map<String, dynamic>> state() async => {
    'terminal_id': terminalId,
    'last_sequence': log.isEmpty ? 0 : log.last['sequence'],
    'sale_sequence': log.where((e) => e['kind'] == 'sale.completed').length,
  };

  @override
  Future<Map<String, dynamic>> events(int after) async => {
    'events': [
      for (final e in log)
        if ((e['sequence'] as int) > after) jsonDecode(jsonEncode(e)),
    ].take(3).toList(), // small pages: exercises paging
    'last_sequence': log.isEmpty ? 0 : log.last['sequence'],
  };
}

void main() {
  late Directory dir;
  setUp(
    () async => dir = await Directory.systemTemp.createTemp('mono_backup_'),
  );
  tearDown(() => dir.delete(recursive: true));

  test(
    'sauvegarde chiffrée, restauration, blocage puis réconciliation',
    () async {
      var clock = DateTime.utc(2026, 10, 12, 8);
      final dbA = PosDatabase(NativeDatabase.memory());
      addTearDown(dbA.close);
      final a = PosRepository(dbA, now: () => clock);
      await a.initialize();
      final usersA = UserRepository(
        a,
        hasher: const Pbkdf2PinHasher(iterations: 10),
      );
      final admin = await usersA.createFirstAdmin('Dosso', '481516', '481516');
      final item = await a.createItem(
        actor: admin,
        category: 'Chaussures',
        name: 'Rangers',
        sku: 'RAN-42',
        label: '42',
        price: 15000,
        stock: 10,
      );
      Future<Map<String, dynamic>> sell(int qty) => a.checkout(
        admin,
        SaleRequest(
          id: const Uuid().v4(),
          quantities: {item: qty},
          paymentMode: PaymentMode.cash,
          tendered: qty * 15000,
        ),
      );
      await sell(1);
      final terminalId = (await a.terminal()).terminalId;
      final server = FakeServer(terminalId);
      final sync = SyncService(dbA, server);
      await sync.synchronize(manual: true);

      // Backup now (event 4 not yet sent), then work continues on A.
      final platform = FakePlatform();
      final backups = BackupService(
        a,
        platform,
        workDir: Directory('${dir.path}/work'),
      );
      await expectLater(
        backups.exportBackup(admin, 'court'),
        throwsA(isA<BusinessException>()),
      );
      final unsent = await sell(1); // sequence 4, inside the backup, unsent
      expect(await backups.exportBackup(admin, 'phrase-secrete-42'), isTrue);
      expect(await backups.lastBackupAt(), isNotNull);
      clock = clock.add(const Duration(hours: 1));
      await usersA.createUser(
        admin,
        name: 'Koffi',
        role: Role.seller,
        pin: '927384',
        confirmation: '927384',
      );
      final later = await sell(2);
      await a.returnSale(
        admin,
        ReturnRequest(
          id: const Uuid().v4(),
          saleId: later['id'] as String,
          lines: {item: (quantity: 1, resaleable: true)},
          refundMode: PaymentMode.cash,
          reason: 'Taille',
        ),
      );
      await a.moveStock(
        admin,
        item,
        kind: StockKind.reception,
        quantity: 5,
        reason: 'Livraison',
      );
      final financeA = FinanceRepository(a);
      await financeA.recordExpense(
        admin,
        kind: ExpenseKind.charge,
        category: 'Transport',
        amount: 2000,
        mode: PaymentMode.cash,
        reason: 'Livraison',
      );
      await financeA.closeCash(
        admin,
        counted: 1000,
        keptFloat: 0,
        comment: 'Test écart',
        openingFloat: 0,
      );
      await sync.synchronize(manual: true);
      expect(await a.pendingCount(), 0);

      // New terminal B: restore the backup.
      final docs = Directory('${dir.path}/docs')..createSync();
      final dbFresh = PosDatabase(NativeDatabase.memory());
      final fresh = PosRepository(dbFresh);
      await fresh.initialize();
      final restorer = BackupService(
        fresh,
        platform,
        workDir: Directory('${dir.path}/work'),
      );
      await expectLater(
        restorer.stageRestore(
          platform.saved!,
          'mauvais-mot-de-passe',
          actor: null,
          docsDir: docs,
        ),
        throwsA(isA<BusinessException>()),
      );
      final manifest = await restorer.stageRestore(
        platform.saved!,
        'phrase-secrete-42',
        actor: null, // not activated yet: allowed on a new device
        docsDir: docs,
      );
      await dbFresh.close();
      expect(manifest.terminalId, terminalId);
      final applied = await BackupService.applyPendingRestore(
        docsDir: docs,
        dbFileName: 'mono.sqlite',
      );
      expect(applied, isNotNull);
      expect(Directory('${docs.path}/restore_pending').existsSync(), isFalse);
      expect(Directory('${docs.path}/safety').listSync(), hasLength(1));
      final dbB = PosDatabase(NativeDatabase(File('${docs.path}/mono.sqlite')));
      addTearDown(dbB.close);
      final b = PosRepository(
        dbB,
        now: () => clock.add(const Duration(hours: 1)),
      );
      await b.initialize();
      await BackupService(b, platform, workDir: docs).markReconcileRequired();
      expect((await b.terminal()).terminalId, terminalId);
      expect(
        (await b.catalog()).single.stock,
        8,
        reason: 'état de la sauvegarde',
      );

      // Blocked until reconciled.
      await expectLater(
        b.checkout(
          admin,
          SaleRequest(
            id: const Uuid().v4(),
            quantities: {item: 1},
            paymentMode: PaymentMode.mobileMoney,
          ),
        ),
        throwsA(isA<BusinessException>()),
      );
      final result = await Reconciler(b, server).run();
      expect(result.confirmed, 1, reason: 'opération 4 de la sauvegarde');
      // backup.created (written right after the snapshot), new user, sale,
      // return, reception, expense, closing.
      expect(result.applied, 7);
      expect(result.usersWithoutPin, ['Koffi']);
      expect(result.pending, 0);
      expect(unsent['number'], 'FACT-2026-00002');

      // B now equals A.
      expect(
        (await b.catalog()).single.stock,
        (await a.catalog()).single.stock,
      );
      final stateA = await a.terminal(), stateB = await b.terminal();
      expect(
        (stateB.eventSequence, stateB.saleSequence),
        (stateA.eventSequence, stateA.saleSequence),
      );
      final day = ReportPeriod.day(clock);
      final reportA = await financeA.report(day);
      final reportB = await FinanceRepository(b).report(day);
      expect(
        (reportB.gross, reportB.refunds, reportB.closings),
        (reportA.gross, reportA.refunds, reportA.closings),
      );
      expect(reportB.expensesByKind, reportA.expensesByKind);
      expect(
        (await b.movements(item)).length,
        (await a.movements(item)).length,
      );

      // And continues after the server, without reusing a number.
      final next = await b.checkout(
        admin,
        SaleRequest(
          id: const Uuid().v4(),
          quantities: {item: 1},
          paymentMode: PaymentMode.mobileMoney,
        ),
      );
      expect(next['number'], 'FACT-2026-00004');
      final syncB = SyncService(dbB, server);
      expect(await syncB.synchronize(manual: true), 1);
      // Koffi cannot log in before an administrator gives a new PIN.
      final koffi = (await UserRepository(
        b,
      ).users()).firstWhere((u) => u.name == 'Koffi');
      await expectLater(
        UserRepository(
          b,
          hasher: const Pbkdf2PinHasher(iterations: 10),
        ).authenticate(koffi.id, '927384'),
        throwsA(isA<BusinessException>()),
      );
    },
  );

  test(
    'restauration refusée : version future, fichier modifié, vendeur',
    () async {
      final db = PosDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final pos = PosRepository(db);
      await pos.initialize();
      final users = UserRepository(
        pos,
        hasher: const Pbkdf2PinHasher(iterations: 10),
      );
      final admin = await users.createFirstAdmin('Dosso', '481516', '481516');
      final platform = FakePlatform();
      final service = BackupService(
        pos,
        platform,
        workDir: Directory('${dir.path}/w'),
      );
      final archive = jsonDecode(
        utf8.decode(await service.buildArchive()),
      ) as Map<String, dynamic>;
      Future<Uint8List> seal(Map<String, dynamic> a) => platform.encrypt(
        Uint8List.fromList(utf8.encode(jsonEncode(a))),
        'phrase-secrete-42',
      );
      final docs = Directory('${dir.path}/d')..createSync();
      final future = jsonDecode(jsonEncode(archive)) as Map<String, dynamic>;
      future['manifest']['schema_version'] = 99;
      await expectLater(
        service.stageRestore(
          await seal(future),
          'phrase-secrete-42',
          actor: admin,
          docsDir: docs,
        ),
        throwsA(
          isA<BusinessException>().having(
            (e) => e.message,
            'm',
            contains('plus récente'),
          ),
        ),
      );
      final tampered = jsonDecode(jsonEncode(archive)) as Map<String, dynamic>;
      final bytes = base64Decode(tampered['db'] as String)..[200] ^= 0xFF;
      tampered['db'] = base64Encode(bytes);
      await expectLater(
        service.stageRestore(
          await seal(tampered),
          'phrase-secrete-42',
          actor: admin,
          docsDir: docs,
        ),
        throwsA(
          isA<BusinessException>().having(
            (e) => e.message,
            'm',
            contains('endommagée'),
          ),
        ),
      );
      await expectLater(
        service.stageRestore(
          await seal(archive),
          'phrase-secrete-42',
          actor: const Actor('s', 'Vendeur', Role.seller),
          docsDir: docs,
        ),
        throwsA(isA<BusinessException>()),
      );
      expect(Directory('${docs.path}/restore_pending').existsSync(), isFalse);
    },
  );
}
