import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'encryption.dart';

part 'database.g.dart';

class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().unique()();
  @override
  Set<Column> get primaryKey => {id};
}

class Products extends Table {
  TextColumn get id => text()();
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get name => text()();
  BoolColumn get published => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {id};
}

class Variants extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get sku => text().unique()();
  TextColumn get label => text()();
  IntColumn get price =>
      integer().check(const CustomExpression<bool>('price >= 0'))();
  IntColumn get stock =>
      integer().check(const CustomExpression<bool>('stock >= 0'))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  // Structured attributes (schema v5); null on older or free variants.
  TextColumn get color => text().nullable()();
  TextColumn get size => text().nullable()();
  // Low-stock alert level (schema v6); 0 = no alert.
  IntColumn get threshold => integer().withDefault(const Constant(0))();
  @override
  Set<Column> get primaryKey => {id};
}

class Sales extends Table {
  TextColumn get id => text()();
  TextColumn get number => text().unique()();
  TextColumn get requestHash => text()();
  TextColumn get occurredAt => text()();
  TextColumn get snapshot => text()();
  IntColumn get total =>
      integer().check(const CustomExpression<bool>('total >= 0'))();
  @override
  Set<Column> get primaryKey => {id};
}

class StockMovements extends Table {
  TextColumn get id => text()();
  TextColumn get variantId => text().references(Variants, #id)();
  TextColumn get kind => text()();
  IntColumn get quantity => integer()();
  TextColumn get actorId => text()();
  TextColumn get reason => text()();
  TextColumn get originId => text()();
  TextColumn get occurredAt => text()();
  // Quantity counted during an inventory (schema v6); null otherwise.
  IntColumn get counted => integer().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class OutboxEntries extends Table {
  TextColumn get id => text()();
  IntColumn get sequence => integer().unique()();
  TextColumn get envelope => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get nextAttemptAt => text().nullable()();
  TextColumn get errorCode => text().nullable()();
  TextColumn get receivedAt => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

/// Local operators. Only a salted PBKDF2 hash of the PIN is stored; the PIN
/// never leaves the terminal and is never synchronized.
class Users extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().unique()();
  TextColumn get role => text().check(
    const CustomExpression<bool>("role IN ('admin', 'seller')"),
  )();
  TextColumn get pinHash => text()();
  TextColumn get pinSalt => text()();
  IntColumn get pinIterations => integer()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  IntColumn get failedAttempts => integer().withDefault(const Constant(0))();
  TextColumn get lockedUntil => text().nullable()();
  TextColumn get createdAt => text()();
  @override
  Set<Column> get primaryKey => {id};
}

/// Administrator corrections of a sale's declared payment. The sale snapshot
/// is never modified; the latest correction gives the effective payment.
class SaleCorrections extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text().references(Sales, #id)();
  TextColumn get paymentMode => text()();
  IntColumn get tendered => integer().nullable()();
  IntColumn get changeGiven =>
      integer().check(const CustomExpression<bool>('change_given >= 0'))();
  TextColumn get reason => text()();
  TextColumn get actorId => text()();
  TextColumn get actorName => text()();
  TextColumn get occurredAt => text()();
  @override
  Set<Column> get primaryKey => {id};
}

/// Return or cancellation linked to a sale (schema v7). The sale itself is
/// never modified; cumulative returns are bounded by the quantities sold.
class SaleReturns extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text().references(Sales, #id)();
  TextColumn get kind => text().check(
    const CustomExpression<bool>("kind IN ('RETURN', 'CANCEL')"),
  )();
  IntColumn get refundTotal =>
      integer().check(const CustomExpression<bool>('refund_total >= 0'))();
  TextColumn get refundMode => text()();
  TextColumn get reason => text()();
  TextColumn get requestHash => text()();
  TextColumn get actorId => text()();
  TextColumn get actorName => text()();
  TextColumn get occurredAt => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class SaleReturnLines extends Table {
  TextColumn get returnId => text().references(SaleReturns, #id)();
  TextColumn get variantId => text()();
  IntColumn get quantity =>
      integer().check(const CustomExpression<bool>('quantity > 0'))();
  IntColumn get unitPrice => integer()();
  IntColumn get lineTotal => integer()();

  /// Resaleable items go back to stock; damaged ones do not.
  BoolColumn get resaleable => boolean()();
  @override
  Set<Column> get primaryKey => {returnId, variantId};
}

/// Shop expense (schema v8). Never edited; an error is cancelled with a
/// traced reason. Kinds keep stock purchases, operating charges and cash
/// transfers apart so that reports never deduct the same money twice.
class Expenses extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text().check(
    const CustomExpression<bool>("kind IN ('CHARGE', 'STOCK', 'TREASURY')"),
  )();
  TextColumn get category => text()();
  IntColumn get amount =>
      integer().check(const CustomExpression<bool>('amount > 0'))();
  TextColumn get paymentMode => text()();
  TextColumn get reason => text()();
  TextColumn get occurredAt => text()();
  TextColumn get actorId => text()();
  TextColumn get actorName => text()();
  TextColumn get recordedAt => text()();
  TextColumn get cancelledAt => text().nullable()();
  TextColumn get cancelReason => text().nullable()();
  TextColumn get cancelledBy => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

/// Cash drawer closing (schema v8): expected cash computed from the float
/// and cash movements since the previous closing, counted cash and gap.
class CashClosings extends Table {
  TextColumn get id => text()();
  TextColumn get periodStart => text()();
  TextColumn get closedAt => text()();
  IntColumn get openingFloat => integer()();
  IntColumn get cashSales => integer()();
  IntColumn get cashRefunds => integer()();
  IntColumn get cashExpenses => integer()();
  IntColumn get expected => integer()();
  IntColumn get counted =>
      integer().check(const CustomExpression<bool>('counted >= 0'))();
  IntColumn get difference => integer()();
  IntColumn get keptFloat =>
      integer().check(const CustomExpression<bool>('kept_float >= 0'))();
  TextColumn get comment => text()();
  TextColumn get actorId => text()();
  TextColumn get actorName => text()();
  @override
  Set<Column> get primaryKey => {id};
}

/// Shop settings edited by the administrator (receipt identity, logo).
class ShopSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}

class TerminalStates extends Table {
  IntColumn get singleton => integer().withDefault(const Constant(1))();
  TextColumn get terminalId => text()();
  TextColumn get prefix => text().unique()();
  IntColumn get eventSequence => integer().withDefault(const Constant(0))();
  IntColumn get saleSequence => integer().withDefault(const Constant(0))();
  TextColumn get lastSyncAt => text().nullable()();
  @override
  Set<Column> get primaryKey => {singleton};
}

@DriftDatabase(
  tables: [
    Categories,
    Products,
    Variants,
    Sales,
    StockMovements,
    OutboxEntries,
    TerminalStates,
    Users,
    SaleCorrections,
    ShopSettings,
    SaleReturns,
    SaleReturnLines,
    Expenses,
    CashClosings,
  ],
)
class PosDatabase extends _$PosDatabase {
  PosDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: databaseName));

  /// The terminal's database, encrypted with [hexKey] (SQLite3 Multiple
  /// Ciphers): the key is the first statement of every connection.
  PosDatabase.encrypted(String hexKey)
    : super(
        driftDatabase(
          name: databaseName,
          native: DriftNativeOptions(
            setup: (raw) => raw.execute(keyPragma(hexKey)),
          ),
        ),
      );

  static const databaseName = 'mono_recette_v1';

  @override
  int get schemaVersion => 8;

  Future<void> _createLocalPhotoTable() => customStatement('''
    CREATE TABLE local_product_photos (
      product_id TEXT NOT NULL REFERENCES products(id),
      position INTEGER NOT NULL CHECK(position BETWEEN 0 AND 2),
      path TEXT NOT NULL UNIQUE,
      PRIMARY KEY(product_id, position)
    )
  ''');

  Future<void> _createFinanceIndexes() async {
    await customStatement(
      'CREATE INDEX expenses_date_idx ON expenses(occurred_at)',
    );
    await customStatement(
      'CREATE INDEX cash_closings_date_idx ON cash_closings(closed_at)',
    );
  }

  Future<void> _createReturnIndex() => customStatement(
    'CREATE INDEX sale_returns_sale_idx ON sale_returns(sale_id, occurred_at)',
  );

  Future<void> _createCorrectionIndex() => customStatement(
    'CREATE INDEX sale_corrections_sale_idx ON sale_corrections(sale_id, occurred_at)',
  );

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createLocalPhotoTable();
      await customStatement(
        'CREATE INDEX movement_variant_idx ON stock_movements(variant_id)',
      );
      await customStatement(
        'CREATE INDEX outbox_status_sequence_idx ON outbox_entries(status, sequence)',
      );
      await customStatement(
        'CREATE INDEX sales_date_idx ON sales(occurred_at)',
      );
      await _createCorrectionIndex();
      await _createReturnIndex();
      await _createFinanceIndexes();
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
    onUpgrade: (m, from, to) async {
      if (from < 1 || to != 8) {
        throw StateError('Migration non prise en charge : $from → $to.');
      }
      // Additive steps only: existing sales, stock and outbox stay untouched.
      if (from < 2) await _createLocalPhotoTable();
      if (from < 3) {
        await m.createTable(users);
        await m.createTable(saleCorrections);
        await _createCorrectionIndex();
      }
      if (from < 4) await m.createTable(shopSettings);
      if (from < 5) {
        await m.addColumn(variants, variants.color);
        await m.addColumn(variants, variants.size);
      }
      if (from < 6) {
        await m.addColumn(variants, variants.threshold);
        await m.addColumn(stockMovements, stockMovements.counted);
      }
      if (from < 7) {
        await m.createTable(saleReturns);
        await m.createTable(saleReturnLines);
        await _createReturnIndex();
      }
      if (from < 8) {
        await m.createTable(expenses);
        await m.createTable(cashClosings);
        await _createFinanceIndexes();
      }
    },
  );
}
