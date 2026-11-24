import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:pos_domain/pos_domain.dart';

part 'local_database.g.dart';

class LocalSales extends Table {
  TextColumn get id => text()();
  TextColumn get payload => text()();
  IntColumn get totalCents => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get syncedAt => dateTime().nullable()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class LocalProducts extends Table {
  TextColumn get id => text()();
  TextColumn get payload => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class LocalCatalogVersions extends Table {
  IntColumn get id => integer()();
  IntColumn get version => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class LocalOperationalState extends Table {
  TextColumn get key => text()();
  TextColumn get payload => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

class LocalStockOperations extends Table {
  TextColumn get id => text()();
  TextColumn get payload => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get error => text().nullable()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class LocalCatalogOperations extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text()();
  TextColumn get payload => text()();
  TextColumn get basePayload => text().nullable()();
  TextColumn get conflictPayload => text().nullable()();
  IntColumn get expectedVersion => integer()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get error => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class LocalPayments extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text()();
  TextColumn get payload => text()();
  DateTimeColumn get syncedAt => dateTime().nullable()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    LocalSales,
    LocalProducts,
    LocalCatalogVersions,
    LocalOperationalState,
    LocalStockOperations,
    LocalCatalogOperations,
    LocalPayments,
  ],
)
class PosDatabase extends _$PosDatabase {
  PosDatabase()
    : super(
        driftDatabase(
          name: 'open_pos_register',
          web: DriftWebOptions(
            sqlite3Wasm: Uri.parse('sqlite3.wasm'),
            driftWorker: Uri.parse('drift_worker.dart.js'),
          ),
        ),
      );

  PosDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(localProducts);
        await m.createTable(localCatalogVersions);
      }
      if (from < 3) await m.createTable(localOperationalState);
      if (from < 4) await m.createTable(localStockOperations);
      if (from < 5) {
        await m.addColumn(localSales, localSales.attempts);
        await m.addColumn(localSales, localSales.nextAttemptAt);
        await m.addColumn(localSales, localSales.lastError);
        if (from >= 4) {
          await m.addColumn(
            localStockOperations,
            localStockOperations.attempts,
          );
          await m.addColumn(
            localStockOperations,
            localStockOperations.nextAttemptAt,
          );
        }
      }
      if (from < 6) await m.createTable(localCatalogOperations);
      if (from < 7) await m.createTable(localPayments);
    },
  );

  Future<void> saveSale(Sale sale) async {
    await into(localSales).insertOnConflictUpdate(
      LocalSalesCompanion.insert(
        id: sale.id,
        payload: jsonEncode(sale.toJson()),
        totalCents: sale.totalCents,
        createdAt: sale.createdAt,
      ),
    );
  }

  Future<void> saveCheckout(Sale sale, PaymentRecord payment) async {
    await transaction(() async {
      await saveSale(sale);
      await into(localPayments).insertOnConflictUpdate(
        LocalPaymentsCompanion.insert(
          id: payment.id,
          saleId: payment.saleId,
          payload: jsonEncode(payment.toJson()),
        ),
      );
    });
  }

  Future<List<LocalSale>> pendingSales({DateTime? now, bool force = false}) =>
      (select(localSales)
            ..where(
              (sale) =>
                  sale.syncedAt.isNull() &
                  (force
                      ? const Constant(true)
                      : sale.nextAttemptAt.isNull() |
                            sale.nextAttemptAt.isSmallerOrEqualValue(
                              now ?? DateTime.now().toUtc(),
                            )),
            )
            ..orderBy([(sale) => OrderingTerm.asc(sale.createdAt)]))
          .get();

  Future<int> pendingSaleCount() async =>
      (selectOnly(localSales)
            ..addColumns([localSales.id.count()])
            ..where(localSales.syncedAt.isNull()))
          .map((row) => row.read(localSales.id.count()) ?? 0)
          .getSingle();

  Future<int> pendingPaymentCount() async =>
      (selectOnly(localPayments)
            ..addColumns([localPayments.id.count()])
            ..where(localPayments.syncedAt.isNull()))
          .map((row) => row.read(localPayments.id.count()) ?? 0)
          .getSingle();

  Future<bool> isSaleSynced(String saleId) async {
    final rows = await (select(
      localSales,
    )..where((row) => row.id.equals(saleId))).get();
    return rows.isNotEmpty && rows.single.syncedAt != null;
  }

  Future<void> markPaymentSynced(String paymentId) async =>
      (update(localPayments)..where((row) => row.id.equals(paymentId))).write(
        LocalPaymentsCompanion(
          syncedAt: Value(DateTime.now().toUtc()),
          nextAttemptAt: const Value(null),
          lastError: const Value(null),
        ),
      );

  Future<List<LocalPayment>> pendingPayments({
    DateTime? now,
    bool force = false,
  }) =>
      (select(localPayments)..where(
            (row) =>
                row.syncedAt.isNull() &
                (force
                    ? const Constant(true)
                    : row.nextAttemptAt.isNull() |
                          row.nextAttemptAt.isSmallerOrEqualValue(
                            now ?? DateTime.now().toUtc(),
                          )),
          ))
          .get();

  Future<void> deferPayment(String id, DateTime now, String error) async {
    final rows = await (select(
      localPayments,
    )..where((row) => row.id.equals(id))).get();
    if (rows.isEmpty) return;
    final attempts = rows.single.attempts + 1;
    final seconds = (5 * (1 << (attempts - 1).clamp(0, 10))).clamp(5, 3600);
    await (update(localPayments)..where((row) => row.id.equals(id))).write(
      LocalPaymentsCompanion(
        attempts: Value(attempts),
        nextAttemptAt: Value(now.add(Duration(seconds: seconds))),
        lastError: Value(error),
      ),
    );
  }

  Future<void> markSaleSynced(String saleId) async {
    await (update(localSales)..where((sale) => sale.id.equals(saleId))).write(
      LocalSalesCompanion(
        syncedAt: Value(DateTime.now().toUtc()),
        nextAttemptAt: const Value(null),
        lastError: const Value(null),
      ),
    );
  }

  Future<void> deferSale(String id, DateTime now, String error) async {
    final rows = await (select(
      localSales,
    )..where((row) => row.id.equals(id))).get();
    if (rows.isEmpty) return;
    final attempts = rows.single.attempts + 1;
    final seconds = (5 * (1 << (attempts - 1).clamp(0, 10))).clamp(5, 3600);
    await (update(localSales)..where((row) => row.id.equals(id))).write(
      LocalSalesCompanion(
        attempts: Value(attempts),
        nextAttemptAt: Value(now.add(Duration(seconds: seconds))),
        lastError: Value(error),
      ),
    );
  }

  Future<void> replaceCachedProducts(
    int version,
    Iterable<Product> products, {
    Iterable<CatalogCategory>? categories,
  }) async {
    await transaction(() async {
      await delete(localProducts).go();
      await batch((batch) {
        batch.insertAll(
          localProducts,
          products.map(
            (product) => LocalProductsCompanion.insert(
              id: product.id,
              payload: jsonEncode(product.toJson()),
            ),
          ),
        );
      });
      final pending = await (select(
        localCatalogOperations,
      )..where((row) => row.status.equals('pending'))).get();
      for (final operation in pending) {
        await into(localProducts).insertOnConflictUpdate(
          LocalProductsCompanion.insert(
            id: operation.productId,
            payload: operation.payload,
          ),
        );
      }
      await into(localCatalogVersions).insertOnConflictUpdate(
        LocalCatalogVersionsCompanion(
          id: const Value(1),
          version: Value(version),
        ),
      );
    });
    if (categories != null) await saveCachedCategories(categories);
  }

  Future<void> saveCachedCategories(Iterable<CatalogCategory> categories) =>
      saveOperationalValue(
        'catalog_categories',
        jsonEncode(categories.map((row) => row.toJson()).toList()),
      );

  Future<List<CatalogCategory>?> readCachedCategories() async {
    final payload = await readOperationalValue('catalog_categories');
    if (payload == null) return null;
    final rows = jsonDecode(payload) as List<Object?>;
    return rows
        .map((row) => CatalogCategory.fromJson(row! as Map<String, Object?>))
        .toList(growable: false);
  }

  Future<void> saveCachedSuppliers(Iterable<Supplier> suppliers) =>
      saveOperationalValue(
        'suppliers_snapshot',
        jsonEncode(suppliers.map((supplier) => supplier.toJson()).toList()),
      );

  Future<List<Supplier>?> readCachedSuppliers() async {
    final payload = await readOperationalValue('suppliers_snapshot');
    if (payload == null) return null;
    final rows = jsonDecode(payload) as List<Object?>;
    return rows
        .map((row) => Supplier.fromJson(row! as Map<String, Object?>))
        .toList(growable: false);
  }

  Future<void> saveCachedPurchaseOrders(
    Iterable<PurchaseOrder> purchaseOrders,
  ) => saveOperationalValue(
    'purchase_orders_snapshot',
    jsonEncode(purchaseOrders.map((order) => order.toJson()).toList()),
  );

  Future<List<PurchaseOrder>?> readCachedPurchaseOrders() async {
    final payload = await readOperationalValue('purchase_orders_snapshot');
    if (payload == null) return null;
    final rows = jsonDecode(payload) as List<Object?>;
    return rows
        .map((row) => PurchaseOrder.fromJson(row! as Map<String, Object?>))
        .toList(growable: false);
  }

  Future<void> saveCachedProduct(Product product) async {
    await into(localProducts).insertOnConflictUpdate(
      LocalProductsCompanion.insert(
        id: product.id,
        payload: jsonEncode(product.toJson()),
      ),
    );
  }

  Future<void> deleteCachedProduct(String productId) async =>
      (delete(localProducts)..where((row) => row.id.equals(productId))).go();

  Future<void> saveCatalogVersion(int version) async {
    await into(localCatalogVersions).insertOnConflictUpdate(
      LocalCatalogVersionsCompanion(
        id: const Value(1),
        version: Value(version),
      ),
    );
  }

  Future<CachedCatalog?> readCachedCatalog() async {
    final versionRows = await select(localCatalogVersions).get();
    if (versionRows.isEmpty) return null;
    final products = await select(localProducts).get();
    return CachedCatalog(
      version: versionRows.single.version,
      products: products
          .map(
            (row) => Product.fromJson(
              jsonDecode(row.payload) as Map<String, Object?>,
            ),
          )
          .toList(growable: false),
      categories: await readCachedCategories() ?? const [],
    );
  }

  Future<void> saveCachedShift(CashShift? shift) async {
    const key = 'active_cash_shift';
    if (shift == null) {
      await (delete(
        localOperationalState,
      )..where((row) => row.key.equals(key))).go();
      return;
    }
    await into(localOperationalState).insertOnConflictUpdate(
      LocalOperationalStateCompanion.insert(
        key: key,
        payload: jsonEncode(shift.toJson()),
      ),
    );
  }

  Future<CashShift?> readCachedShift() async {
    const key = 'active_cash_shift';
    final rows = await (select(
      localOperationalState,
    )..where((row) => row.key.equals(key))).get();
    if (rows.isEmpty) return null;
    return CashShift.fromJson(
      jsonDecode(rows.single.payload) as Map<String, Object?>,
    );
  }

  Future<void> saveRegisterIdentity({
    required String id,
    required String name,
  }) async {
    await saveOperationalValue('register_id', id);
    await saveOperationalValue('register_name', name);
  }

  Future<String?> readOperationalValue(String key) async {
    final rows = await (select(
      localOperationalState,
    )..where((row) => row.key.equals(key))).get();
    if (rows.isEmpty) return null;
    return jsonDecode(rows.single.payload) as String;
  }

  Future<void> saveOperationalValue(String key, String value) async {
    await into(localOperationalState).insertOnConflictUpdate(
      LocalOperationalStateCompanion.insert(
        key: key,
        payload: jsonEncode(value),
      ),
    );
  }

  Future<void> cacheInventory(Iterable<InventoryItem> items) async {
    await saveOperationalValue(
      'inventory_snapshot',
      jsonEncode(
        items
            .map(
              (item) => {
                'productId': item.productId,
                'name': item.name,
                'sku': item.sku,
                'onHand': item.onHand,
                'lowStockThreshold': item.lowStockThreshold,
                'locations': item.locations
                    .map(
                      (location) => {
                        'location': location.location,
                        'quantity': location.quantity,
                      },
                    )
                    .toList(growable: false),
              },
            )
            .toList(growable: false),
      ),
    );
  }

  Future<List<InventoryItem>?> readCachedInventory() async {
    final rows = await (select(
      localOperationalState,
    )..where((row) => row.key.equals('inventory_snapshot'))).get();
    if (rows.isEmpty) return null;
    final raw = jsonDecode(rows.single.payload) as String;
    final list = jsonDecode(raw) as List<Object?>;
    return list
        .map((row) => InventoryItem.fromJson(row! as Map<String, Object?>))
        .toList(growable: false);
  }

  Future<void> saveStockOperation(
    String id,
    Map<String, Object?> payload,
  ) async {
    await into(localStockOperations).insertOnConflictUpdate(
      LocalStockOperationsCompanion.insert(
        id: id,
        payload: jsonEncode(payload),
        createdAt: DateTime.now().toUtc(),
        status: const Value('pending'),
      ),
    );
  }

  Future<List<LocalStockOperation>> pendingStockOperations({
    DateTime? now,
    bool force = false,
  }) =>
      (select(localStockOperations)
            ..where(
              (row) =>
                  row.status.equals('pending') &
                  (force
                      ? const Constant(true)
                      : row.nextAttemptAt.isNull() |
                            row.nextAttemptAt.isSmallerOrEqualValue(
                              now ?? DateTime.now().toUtc(),
                            )),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
          .get();

  Future<void> deferStockOperation(String id, DateTime now) async {
    final rows = await (select(
      localStockOperations,
    )..where((row) => row.id.equals(id))).get();
    if (rows.isEmpty) return;
    final attempts = rows.single.attempts + 1;
    final seconds = (5 * (1 << (attempts - 1).clamp(0, 10))).clamp(5, 3600);
    await (update(
      localStockOperations,
    )..where((row) => row.id.equals(id))).write(
      LocalStockOperationsCompanion(
        attempts: Value(attempts),
        nextAttemptAt: Value(now.add(Duration(seconds: seconds))),
      ),
    );
  }

  Future<List<LocalStockOperation>> visibleStockOperations() =>
      (select(localStockOperations)
            ..where((row) => row.status.isNotValue('synced'))
            ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
          .get();

  Future<void> markStockOperationSynced(String id) async =>
      (update(localStockOperations)..where((row) => row.id.equals(id))).write(
        const LocalStockOperationsCompanion(
          status: Value('synced'),
          error: Value(null),
          nextAttemptAt: Value(null),
        ),
      );

  Future<void> markStockOperationConflict(String id, String error) async =>
      (update(localStockOperations)..where((row) => row.id.equals(id))).write(
        LocalStockOperationsCompanion(
          status: const Value('conflict'),
          error: Value(error),
          nextAttemptAt: const Value(null),
        ),
      );

  Future<void> retryStockOperation(String id) async =>
      (update(localStockOperations)..where((row) => row.id.equals(id))).write(
        const LocalStockOperationsCompanion(
          status: Value('pending'),
          error: Value(null),
          nextAttemptAt: Value(null),
        ),
      );

  Future<void> discardStockOperation(String id) async =>
      (delete(localStockOperations)..where((row) => row.id.equals(id))).go();

  Future<LocalCatalogOperation?> pendingCatalogOperationFor(
    String productId,
  ) async {
    final rows =
        await (select(localCatalogOperations)
              ..where(
                (row) =>
                    row.productId.equals(productId) &
                    row.status.equals('pending'),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.createdAt)])
              ..limit(1))
            .get();
    return rows.isEmpty ? null : rows.single;
  }

  Future<List<LocalCatalogOperation>> pendingCatalogOperations({
    DateTime? now,
    bool force = false,
  }) =>
      (select(localCatalogOperations)
            ..where(
              (row) =>
                  row.status.equals('pending') &
                  (force
                      ? const Constant(true)
                      : row.nextAttemptAt.isNull() |
                            row.nextAttemptAt.isSmallerOrEqualValue(
                              now ?? DateTime.now().toUtc(),
                            )),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
          .get();

  Future<List<LocalCatalogOperation>> visibleCatalogOperations() =>
      (select(localCatalogOperations)
            ..where((row) => row.status.isNotValue('synced'))
            ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
          .get();

  Future<void> enqueueCatalogOperation({
    required String id,
    required String productId,
    required String payload,
    required int expectedVersion,
    required String? basePayload,
    required DateTime createdAt,
  }) async {
    await into(localCatalogOperations).insertOnConflictUpdate(
      LocalCatalogOperationsCompanion.insert(
        id: id,
        productId: productId,
        payload: payload,
        expectedVersion: expectedVersion,
        basePayload: Value(basePayload),
        createdAt: createdAt,
        status: const Value('pending'),
      ),
    );
  }

  Future<void> deferCatalogOperation(
    String id,
    DateTime now,
    String error,
  ) async {
    final rows = await (select(
      localCatalogOperations,
    )..where((row) => row.id.equals(id))).get();
    if (rows.isEmpty) return;
    final attempts = rows.single.attempts + 1;
    final seconds = (5 * (1 << (attempts - 1).clamp(0, 10))).clamp(5, 3600);
    await (update(
      localCatalogOperations,
    )..where((row) => row.id.equals(id))).write(
      LocalCatalogOperationsCompanion(
        attempts: Value(attempts),
        nextAttemptAt: Value(now.add(Duration(seconds: seconds))),
        error: Value(error),
      ),
    );
  }

  Future<void> markCatalogOperationConflict(
    String id,
    String error,
    String? currentProductPayload,
  ) async =>
      (update(localCatalogOperations)..where((row) => row.id.equals(id))).write(
        LocalCatalogOperationsCompanion(
          status: const Value('conflict'),
          error: Value(error),
          conflictPayload: Value(currentProductPayload),
          nextAttemptAt: const Value(null),
        ),
      );

  Future<void> retryCatalogOperation(String id) async =>
      (update(localCatalogOperations)..where((row) => row.id.equals(id))).write(
        const LocalCatalogOperationsCompanion(
          status: Value('pending'),
          error: Value(null),
          nextAttemptAt: Value(null),
        ),
      );

  Future<void> removeCatalogOperation(String id) async =>
      (delete(localCatalogOperations)..where((row) => row.id.equals(id))).go();

  Future<void> replaceCatalogConflictWithPending({
    required String oldId,
    required String newId,
    required String productId,
    required String payload,
    required int expectedVersion,
    required String basePayload,
    required DateTime createdAt,
  }) async {
    await transaction(() async {
      await (delete(
        localCatalogOperations,
      )..where((row) => row.id.equals(oldId))).go();
      await enqueueCatalogOperation(
        id: newId,
        productId: productId,
        payload: payload,
        expectedVersion: expectedVersion,
        basePayload: basePayload,
        createdAt: createdAt,
      );
    });
  }
}

class CachedCatalog {
  const CachedCatalog({
    required this.version,
    required this.products,
    this.categories = const [],
  });

  final int version;
  final List<Product> products;
  final List<CatalogCategory> categories;
}

Sale decodeLocalSale(String payload) =>
    Sale.fromJson(jsonDecode(payload) as Map<String, Object?>);
