import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/pos_repository.dart';
import '../data/settings_repository.dart';
import '../domain/models.dart';
import '../media/photo_service.dart';
import '../printing/printer_service.dart';
import '../sync/sync_service.dart';
import 'session_controller.dart';

final repositoryProvider = Provider<PosRepository>(
  (ref) => throw StateError('Base non initialisée'),
);
final printerProvider = Provider<PrinterService>((ref) => SimulatedPrinter());
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.read(repositoryProvider)),
);
final photoProvider = Provider<PhotoService>(
  (ref) => const AndroidPhotoService(),
);
final posProvider = NotifierProvider<PosController, PosState>(
  PosController.new,
);

class PosState {
  const PosState({
    this.items = const [],
    this.cart = const {},
    this.sales = const [],
    this.pending = 0,
    this.lastSync,
    this.busy = false,
    this.message,
    this.receipt,
    this.terminalId = '',
    this.receiptSettings = const ReceiptSettings(),
  });
  final List<CatalogItem> items;
  final Map<String, int> cart;
  final List<Map<String, dynamic>> sales;
  final int pending;
  final String? lastSync, message;
  final Receipt? receipt;
  final String terminalId;
  final ReceiptSettings receiptSettings;
  final bool busy;
  int get cartQuantity => cart.values.fold(0, (sum, value) => sum + value);
  int get total => cart.entries.fold(
    0,
    (sum, e) => sum + items.firstWhere((i) => i.id == e.key).price * e.value,
  );
  PosState copy({
    List<CatalogItem>? items,
    Map<String, int>? cart,
    List<Map<String, dynamic>>? sales,
    int? pending,
    String? lastSync,
    bool? busy,
    String? message,
    Receipt? receipt,
    String? terminalId,
    ReceiptSettings? receiptSettings,
  }) => PosState(
    items: items ?? this.items,
    cart: cart ?? this.cart,
    sales: sales ?? this.sales,
    pending: pending ?? this.pending,
    lastSync: lastSync ?? this.lastSync,
    busy: busy ?? this.busy,
    message: message,
    receipt: receipt ?? this.receipt,
    terminalId: terminalId ?? this.terminalId,
    receiptSettings: receiptSettings ?? this.receiptSettings,
  );
}

class PosController extends Notifier<PosState> {
  /// Logged-in operator; every business operation is attributed to them.
  Actor get actor =>
      ref.read(currentActorProvider) ??
      (throw const BusinessException(
        'Session verrouillée : saisissez votre code PIN.',
      ));
  SaleRequest? _submitted;
  HttpSyncTransport? _transport;
  SyncService? _sync;
  @override
  PosState build() {
    ref.onDispose(() => _transport?.close());
    return const PosState();
  }

  PosRepository get repo => ref.read(repositoryProvider);
  Future<void> refresh() async {
    final items = await repo.catalog();
    final sales = await repo.history();
    final terminal = await repo.terminal();
    final settings = await ref
        .read(settingsRepositoryProvider)
        .receiptSettings();
    state = state.copy(
      receiptSettings: settings,
      items: items,
      sales: sales,
      pending: await repo.pendingCount(),
      lastSync: terminal.lastSyncAt,
      terminalId: terminal.terminalId,
    );
  }

  void quantity(String id, int delta) {
    if (state.busy) return;
    if (_submitted != null) {
      state = state.copy(
        message: 'Validation non confirmée : réessayez le paiement sans modifier le panier.',
      );
      return;
    }
    final item = state.items.firstWhere((i) => i.id == id);
    final count = (state.cart[id] ?? 0) + delta;
    if (count > item.stock) {
      state = state.copy(message: 'Stock disponible : ${item.stock}.');
      return;
    }
    final cart = Map<String, int>.from(state.cart);
    if (count <= 0) {
      cart.remove(id);
    } else {
      cart[id] = count;
    }
    _submitted = null;
    state = state.copy(cart: cart);
  }

  Future<bool> createItem({
    required String category,
    required String name,
    required String sku,
    required String label,
    required String price,
    required String stock,
    List<String> photoPaths = const [],
  }) => _create(() async {
    final qty = int.tryParse(stock);
    if (qty == null) {
      throw const BusinessException('Saisissez un stock entier.');
    }
    await repo.createItem(
      actor: actor,
      category: category,
      name: name,
      sku: sku,
      label: label,
      price: moneyInput(price),
      stock: qty,
      photoPaths: photoPaths,
    );
  });

  /// Article whose variants are the colour × size combinations really in
  /// stock: only cells with a typed quantity are created (0 = sold out).
  Future<bool> createMatrixItem({
    required String category,
    required String name,
    required SizeGrid grid,
    required String reference,
    required List<String> colors,
    required String price,
    required Map<(String, String), String> stock,
    List<String> photoPaths = const [],
  }) => _create(() async {
    await repo.createProduct(
      actor: actor,
      category: category,
      name: name,
      variants: _matrix(grid, reference, colors, price, stock),
      photoPaths: photoPaths,
    );
  });

  /// New colours or sizes for an existing article.
  Future<bool> addVariants({
    required String productId,
    required SizeGrid grid,
    required String reference,
    required List<String> colors,
    required String price,
    required Map<(String, String), String> stock,
  }) => _create(() async {
    await repo.addVariants(
      actor,
      productId,
      _matrix(grid, reference, colors, price, stock),
    );
  });

  List<VariantDraft> _matrix(
    SizeGrid grid,
    String reference,
    List<String> colors,
    String price,
    Map<(String, String), String> stock,
  ) {
    if (reference.trim().isEmpty) {
      throw const BusinessException('Indiquez la référence de base.');
    }
    final quantities = <(String, String), int>{};
    for (final entry in stock.entries) {
      final text = entry.value.trim();
      if (text.isEmpty) continue;
      quantities[entry.key] =
          int.tryParse(text) ??
          (throw BusinessException(
            'Stock invalide : ${entry.key.$1} ${entry.key.$2}'.trim(),
          ));
    }
    if (quantities.isEmpty) {
      throw const BusinessException(
        'Saisissez le stock réel d’au moins une combinaison.',
      );
    }
    return matrixVariants(
      grid: grid,
      reference: reference,
      colors: colors,
      price: moneyInput(price),
      stock: quantities,
    );
  }

  Future<bool> _create(Future<void> Function() operation) async {
    if (state.busy) return false;
    state = state.copy(busy: true);
    try {
      await operation();
    } on BusinessException catch (e) {
      state = state.copy(busy: false, message: e.message);
      return false;
    } catch (_) {
      state = state.copy(
        busy: false,
        message:
            'Enregistrement impossible. Vérifiez les données et réessayez.',
      );
      return false;
    }
    // The transaction has committed. A refresh error must never make the form
    // delete photos now owned by the product or retry the creation.
    var message = 'Article et stock initial enregistrés.';
    try {
      await refresh();
    } catch (_) {
      message = '$message Actualisation impossible : rouvrez l’application.';
    }
    state = state.copy(busy: false, message: message);
    return true;
  }

  Future<bool> pay(
    PaymentMode mode,
    String cash,
    Map<String, String> customer,
  ) async {
    if (state.busy || state.cart.isEmpty) return false;
    state = state.copy(busy: true);
    Map<String, dynamic> sale;
    try {
      final candidate = SaleRequest(
        id: _submitted?.id ?? const Uuid().v4(),
        quantities: state.cart,
        paymentMode: mode,
        tendered: mode == PaymentMode.cash ? moneyInput(cash) : null,
        customer: customer,
      );
      if (_submitted != null &&
          fingerprint(_submitted!.toJson()) !=
              fingerprint(candidate.toJson())) {
        state = state.copy(
          busy: false,
          message: 'Une validation est en attente. Réessayez avec les mêmes informations.',
        );
        return false;
      }
      _submitted = candidate;
      sale = await repo.checkout(actor, candidate);
    } on BusinessException catch (e) {
      _submitted = null;
      state = state.copy(busy: false, message: e.message);
      return false;
    } catch (_) {
      state = state.copy(
        busy: false,
        message: 'Validation non confirmée. Réessayez sans modifier le panier.',
      );
      return false;
    }
    _submitted = null;
    state = state.copy(
      cart: {},
      receipt: buildReceipt(sale, settings: state.receiptSettings),
    );
    String message;
    try {
      final outcome = await ref
          .read(printerProvider)
          .printReceipt(state.receipt!);
      message = outcome == PrintOutcome.simulated
          ? 'Vente enregistrée. Ticket simulé : aucun papier imprimé.'
          : 'Vente enregistrée. Impression transmise, sortie papier à vérifier.';
    } catch (e) {
      message =
          'Vente enregistrée. Impression non confirmée${_code(e)} : utilisez le duplicata dans l’historique.';
    }
    try {
      await refresh();
    } catch (_) {
      message = '$message Actualisation impossible : rouvrez l’application.';
    }
    state = state.copy(busy: false, message: message);
    return true;
  }

  Future<void> duplicate(Map<String, dynamic> sale) async {
    if (state.busy) return;
    final receipt = buildReceipt(
      sale,
      duplicate: true,
      settings: state.receiptSettings,
    );
    state = state.copy(busy: true, receipt: receipt);
    try {
      final result = await ref.read(printerProvider).printReceipt(receipt);
      state = state.copy(
        busy: false,
        message: result == PrintOutcome.simulated
            ? 'Duplicata simulé. Aucun papier imprimé.'
            : 'Duplicata transmis, sortie papier à vérifier.',
      );
    } catch (e) {
      state = state.copy(
        busy: false,
        message:
            'Impression non confirmée${_code(e)}. La vente et le stock sont conservés.',
      );
    }
  }

  /// Records a return or cancellation, then prints the refund ticket. The
  /// screen keeps the same operation id on retry, so a refund happens once.
  Future<bool> returnSale(ReturnRequest request) async {
    if (state.busy) return false;
    state = state.copy(busy: true);
    Map<String, dynamic> operation;
    try {
      operation = await repo.returnSale(actor, request);
    } on BusinessException catch (e) {
      state = state.copy(busy: false, message: e.message);
      return false;
    } catch (_) {
      state = state.copy(
        busy: false,
        message: 'Retour non confirmé. Réessayez sans modifier la saisie.',
      );
      return false;
    }
    final receipt = buildReturnReceipt(
      operation,
      settings: state.receiptSettings,
    );
    state = state.copy(receipt: receipt);
    var message =
        '${request.cancel ? 'Vente annulée' : 'Retour enregistré'} : ${fcfa(operation['refund_total'] as int)} à rembourser.';
    try {
      final outcome = await ref.read(printerProvider).printReceipt(receipt);
      if (outcome == PrintOutcome.simulated) {
        message = '$message Ticket simulé.';
      }
    } catch (e) {
      message = '$message Ticket non imprimé${_code(e)}.';
    }
    try {
      await refresh();
    } catch (_) {
      message = '$message Actualisation impossible.';
    }
    state = state.copy(busy: false, message: message);
    return true;
  }

  /// Reception, loss or correction typed by the administrator.
  Future<bool> moveStock(
    String variantId,
    StockKind kind,
    String quantity,
    String reason,
  ) => _run(() async {
    final qty = int.tryParse(quantity.trim());
    if (qty == null) {
      throw const BusinessException('Saisissez une quantité entière.');
    }
    await repo.moveStock(
      actor,
      variantId,
      kind: kind,
      quantity: qty,
      reason: reason,
    );
    return '${kind.label} enregistrée.';
  });

  /// Inventory counts keyed by variant id; empty fields are not counted.
  Future<bool> countInventory(Map<String, String> counts, String reason) =>
      _run(() async {
        final counted = <String, int>{};
        for (final e in counts.entries) {
          final text = e.value.trim();
          if (text.isEmpty) continue;
          counted[e.key] =
              int.tryParse(text) ??
              (throw const BusinessException('Quantité comptée invalide.'));
        }
        final changed = await repo.countInventory(
          actor,
          counted,
          reason: reason,
        );
        return changed == 0
            ? 'Inventaire conforme : aucun écart.'
            : 'Inventaire enregistré : $changed écart(s) corrigé(s).';
      });

  Future<bool> updateVariant(
    String variantId, {
    String? threshold,
    bool? active,
  }) => _run(() async {
    int? level;
    if (threshold != null) {
      level =
          int.tryParse(threshold.trim()) ??
          (throw const BusinessException('Seuil invalide.'));
    }
    await repo.updateVariant(
      actor,
      variantId,
      threshold: level,
      active: active,
    );
    return active == null
        ? 'Seuil enregistré.'
        : active
        ? 'Variante réactivée.'
        : 'Variante désactivée : elle n’est plus proposée à la vente.';
  });

  /// Runs an administrator operation, then refreshes the screens.
  Future<bool> _run(Future<String> Function() operation) async {
    if (state.busy) return false;
    state = state.copy(busy: true);
    String message;
    try {
      message = await operation();
    } on BusinessException catch (e) {
      state = state.copy(busy: false, message: e.message);
      return false;
    } catch (_) {
      state = state.copy(
        busy: false,
        message: 'Opération non confirmée. Réessayez.',
      );
      return false;
    }
    try {
      await refresh();
    } catch (_) {
      message = '$message Actualisation impossible.';
    }
    state = state.copy(busy: false, message: message);
    return true;
  }

  /// Saves an article's photos; removed images are deleted after commit.
  Future<bool> updatePhotos(String productId, List<String> paths) async {
    if (state.busy) return false;
    state = state.copy(busy: true);
    List<String> removed;
    try {
      removed = await repo.replacePhotos(actor, productId, paths);
    } on BusinessException catch (e) {
      state = state.copy(busy: false, message: e.message);
      return false;
    } catch (_) {
      state = state.copy(
        busy: false,
        message: 'Photos non enregistrées. Réessayez.',
      );
      return false;
    }
    var message = 'Photos mises à jour.';
    for (final path in removed) {
      try {
        await ref.read(photoProvider).discardDraft(path);
      } catch (_) {
        // An unreferenced private file is harmless; the change is committed.
      }
    }
    try {
      await refresh();
    } catch (_) {
      message = '$message Actualisation impossible.';
    }
    state = state.copy(busy: false, message: message);
    return true;
  }

  /// New prices typed by the administrator, keyed by variant id.
  Future<bool> changePrices(Map<String, String> inputs) async {
    if (state.busy) return false;
    state = state.copy(busy: true);
    int changed;
    try {
      changed = await repo.changePrices(actor, {
        for (final e in inputs.entries) e.key: moneyInput(e.value),
      });
    } on BusinessException catch (e) {
      state = state.copy(busy: false, message: e.message);
      return false;
    } catch (_) {
      state = state.copy(
        busy: false,
        message: 'Prix non enregistrés. Réessayez.',
      );
      return false;
    }
    var message = changed == 0
        ? 'Aucun prix modifié.'
        : '$changed prix modifié(s). Les ventes passées gardent leur prix.';
    try {
      await refresh();
    } catch (_) {
      message = '$message Actualisation impossible.';
    }
    state = state.copy(busy: false, message: message);
    return true;
  }

  /// Saves the receipt identity (administrator only).
  Future<bool> saveReceiptSettings(ReceiptSettings next) async {
    if (state.busy) return false;
    state = state.copy(busy: true);
    try {
      await ref
          .read(settingsRepositoryProvider)
          .saveReceiptSettings(actor, next);
    } on BusinessException catch (e) {
      state = state.copy(busy: false, message: e.message);
      return false;
    } catch (_) {
      state = state.copy(
        busy: false,
        message: 'Réglages non enregistrés. Réessayez.',
      );
      return false;
    }
    var message = 'Ticket mis à jour.';
    try {
      await refresh();
    } catch (_) {
      message = '$message Actualisation impossible : rouvrez l’application.';
    }
    state = state.copy(busy: false, message: message);
    return true;
  }

  /// Administrator correction of a recorded sale's payment.
  Future<bool> correctPayment(
    String saleId,
    PaymentMode mode,
    String tendered,
    String reason,
  ) async {
    if (state.busy) return false;
    state = state.copy(busy: true);
    try {
      await repo.correctPayment(
        actor,
        saleId,
        mode: mode,
        tendered: mode == PaymentMode.cash ? moneyInput(tendered) : null,
        reason: reason,
      );
    } on BusinessException catch (e) {
      state = state.copy(busy: false, message: e.message);
      return false;
    } catch (_) {
      state = state.copy(
        busy: false,
        message: 'Correction non confirmée. Réessayez.',
      );
      return false;
    }
    var message = 'Correction enregistrée. La vente d’origine est conservée.';
    try {
      await refresh();
    } catch (_) {
      message = '$message Actualisation impossible.';
    }
    state = state.copy(busy: false, message: message);
    return true;
  }

  /// Printer error code for the operator; never a stack trace or receipt data.
  static String _code(Object error) =>
      error is PlatformException ? ' (${error.code})' : '';

  /// Prints the calibration ticket; no sale, stock or outbox change.
  Future<void> printTest() async {
    if (state.busy) return;
    final receipt = buildTestReceipt(settings: state.receiptSettings);
    state = state.copy(busy: true, receipt: receipt);
    String message;
    try {
      final result = await ref.read(printerProvider).printReceipt(receipt);
      message = result == PrintOutcome.simulated
          ? 'Ticket test simulé. Aucun papier imprimé.'
          : 'Ticket test transmis : vérifiez le papier.';
    } catch (e) {
      message = 'Ticket test non confirmé${_code(e)}.';
    }
    state = state.copy(busy: false, message: message);
  }

  void configureSync(String url, String token) {
    actor.requireAdmin();
    if (state.busy) {
      throw const BusinessException('Une opération est en cours.');
    }
    if (token.trim().isEmpty) {
      throw const BusinessException('Jeton de recette requis.');
    }
    final next = HttpSyncTransport(Uri.parse(url.trim()), token.trim());
    _transport?.close();
    _transport = next;
    _sync = SyncService(repo.db, next);
    state = state.copy(
      message: 'Connexion configurée pour cette session uniquement.',
    );
  }

  Future<void> synchronize() async {
    if (state.busy) return;
    if (_sync == null) {
      state = state.copy(
        message: 'Configurez le serveur de recette avec l’icône Réglages.',
      );
      return;
    }
    state = state.copy(
      busy: true,
      message: 'Connexion au serveur… (jusqu’à 1 min s’il est en veille)',
    );
    String message;
    try {
      await _transport?.wake();
      final n = await _sync!.synchronize(manual: true);
      message = '$n opération(s) confirmée(s) par le serveur.';
    } on BusinessException catch (e) {
      message = e.message;
    } catch (_) {
      message = 'Synchronisation indisponible. Données conservées localement.';
    }
    try {
      await refresh();
    } catch (_) {
      message = '$message Actualisation impossible.';
    }
    state = state.copy(busy: false, message: message);
  }
}
