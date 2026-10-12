import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;

import '../data/database.dart';
import '../domain/models.dart';

class SyncFailure implements Exception {
  const SyncFailure(this.code);
  final String code;
}

abstract class SyncTransport {
  Future<Map<String, dynamic>> send(Map<String, dynamic> envelope);

  /// Called once before a batch; hosted servers may need to wake up.
  Future<void> wake() async {}

  /// Server view of this terminal: last_sequence and sale_sequence.
  Future<Map<String, dynamic>> state() =>
      throw UnsupportedError('Réconciliation non disponible.');

  /// Envelopes received by the server after [after], in sequence order.
  Future<Map<String, dynamic>> events(int after) =>
      throw UnsupportedError('Réconciliation non disponible.');

  void close() {}
}

class HttpSyncTransport extends SyncTransport {
  HttpSyncTransport(this.baseUrl, this.accessToken, {http.Client? client})
    : client = client ?? http.Client() {
    if (baseUrl.scheme != 'https' &&
        !(baseUrl.scheme == 'http' &&
            ['127.0.0.1', 'localhost'].contains(baseUrl.host))) {
      throw const BusinessException(
        'HTTPS est obligatoire, sauf sur la boucle locale de recette.',
      );
    }
    if (baseUrl.userInfo.isNotEmpty ||
        baseUrl.hasQuery ||
        baseUrl.hasFragment ||
        !['', '/'].contains(baseUrl.path)) {
      throw const BusinessException(
        'Saisissez uniquement l’origine du serveur.',
      );
    }
  }
  final Uri baseUrl;
  final String accessToken;
  final http.Client client;

  @override
  Future<Map<String, dynamic>> send(Map<String, dynamic> envelope) async {
    final request =
        http.Request('POST', baseUrl.resolve('/api/private/sync/events'))
          ..followRedirects = false
          ..headers.addAll({
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          })
          ..body = jsonEncode(envelope);
    final streamed = await client
        .send(request)
        .timeout(const Duration(seconds: 15));
    final response = await http.Response.fromStream(streamed)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw SyncFailure(_failureCode(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String>? query,
  ]) async {
    final response = await client
        .get(
          baseUrl.resolve(path).replace(queryParameters: query),
          headers: {'Authorization': 'Bearer $accessToken'},
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) throw SyncFailure(_failureCode(response));
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> state() => _get('/api/private/sync/state');

  @override
  Future<Map<String, dynamic>> events(int after) =>
      _get('/api/private/sync/events', {'after': '$after', 'limit': '100'});

  /// HTTP status plus the server's technical code (e.g. HTTP_409:
  /// SALE_NUMBER_MISMATCH). Only upper-case codes are kept: never a body
  /// fragment that could carry data.
  static String _failureCode(http.Response response) {
    var code = 'HTTP_${response.statusCode}';
    try {
      final detail = (jsonDecode(response.body) as Map)['detail'];
      if (detail is String && RegExp(r'^[A-Z_]{3,40}$').hasMatch(detail)) {
        code = '$code:$detail';
      }
    } catch (_) {
      // Non-JSON body: the status code alone is reported.
    }
    return code;
  }

  /// Free hosting sleeps when idle and needs about a minute to wake up:
  /// one patient health request before the first event avoids a false error.
  @override
  Future<void> wake() async {
    final response = await client
        .get(baseUrl.resolve('/health/ready'))
        .timeout(const Duration(seconds: 90));
    if (response.statusCode != 200) {
      throw SyncFailure('HTTP_${response.statusCode}');
    }
  }

  @override
  void close() => client.close();
}

class SyncService {
  SyncService(this.db, this.transport, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  final PosDatabase db;
  final SyncTransport transport;
  final DateTime Function() now;
  bool _running = false;

  Future<int> synchronize({bool manual = false}) async {
    if (_running) return 0;
    _running = true;
    var acknowledged = 0;
    try {
      final entries =
          await (db.select(db.outboxEntries)
                ..where((e) => e.status.equals('synced').not())
                ..orderBy([(e) => OrderingTerm.asc(e.sequence)])
                ..limit(100))
              .get();
      for (final entry in entries) {
        if (!manual &&
            entry.nextAttemptAt != null &&
            DateTime.parse(entry.nextAttemptAt!).isAfter(now().toUtc())) {
          break;
        }
        try {
          final envelope = jsonDecode(entry.envelope) as Map<String, dynamic>;
          final ack = await transport.send(envelope);
          if (ack['id'] != entry.id ||
              ack['sequence'] != entry.sequence ||
              ack['terminal_id'] != envelope['terminal_id'] ||
              ack['status'] != 'committed') {
            throw const SyncFailure('INVALID_ACK');
          }
          final received = DateTime.tryParse(
            ack['received_at'] as String? ?? '',
          );
          if (received == null || !received.isUtc) {
            throw const SyncFailure('INVALID_ACK');
          }
          await db.transaction(() async {
            await (db.update(
              db.outboxEntries,
            )..where((e) => e.id.equals(entry.id))).write(
              OutboxEntriesCompanion(
                status: const Value('synced'),
                receivedAt: Value(received.toIso8601String()),
                errorCode: const Value(null),
                nextAttemptAt: const Value(null),
              ),
            );
            await (db.update(
              db.terminalStates,
            )..where((t) => t.singleton.equals(1))).write(
              TerminalStatesCompanion(
                lastSyncAt: Value(now().toUtc().toIso8601String()),
              ),
            );
          });
          acknowledged++;
        } catch (error) {
          final attempts = entry.attempts + 1;
          final seconds = min(3600, 5 * (1 << min(attempts - 1, 10)));
          await (db.update(
            db.outboxEntries,
          )..where((e) => e.id.equals(entry.id))).write(
            OutboxEntriesCompanion(
              status: const Value('error'),
              attempts: Value(attempts),
              nextAttemptAt: Value(
                now().toUtc().add(Duration(seconds: seconds)).toIso8601String(),
              ),
              errorCode: Value(
                error is SyncFailure ? error.code : 'NETWORK_OR_RESPONSE',
              ),
            ),
          );
          // Never send a dependent operation after a failed predecessor.
          throw BusinessException(
            'Synchronisation interrompue à l’opération ${entry.sequence}. '
            'Les données restent enregistrées sur le terminal.',
          );
        }
      }
      return acknowledged;
    } finally {
      _running = false;
    }
  }
}
