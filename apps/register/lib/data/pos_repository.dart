import 'dart:convert';

import 'package:open_pos/data/local_database.dart';
import 'package:open_pos/data/payment_provider.dart';
import 'package:open_pos/data/sale_sync_client.dart';
import 'package:pos_domain/pos_domain.dart';
import 'package:uuid/uuid.dart';

class CompletedSale {
  const CompletedSale({
    required this.sale,
    required this.payment,
    required this.synced,
    required this.paymentSynced,
  });

  final Sale sale;
  final PaymentRecord payment;
  final bool synced;
  final bool paymentSynced;
}

class SyncChangesResult {
  const SyncChangesResult({
    this.catalog,
    this.settingsChanged = false,
    this.shiftChanged = false,
    this.inventoryChanged = false,
  });

  final CatalogSnapshot? catalog;
  final bool settingsChanged;
  final bool shiftChanged;
  final bool inventoryChanged;
}

class CatalogOperationSnapshot {
  const CatalogOperationSnapshot({
    required this.id,
    required this.productId,
    required this.product,
    required this.expectedVersion,
    required this.status,
    this.currentProduct,
    this.error,
  });

  final String id;
  final String productId;
  final Product product;
  final int expectedVersion;
  final String status;
  final Product? currentProduct;
  final String? error;
}

Product _withProductVersion(
  Product product, {
  required String id,
  required int version,
}) => Product(
  id: id,
  name: product.name,
  category: product.category,
  unitPriceCents: product.unitPriceCents,
  sku: product.sku,
  barcode: product.barcode,
  isActive: product.isActive,
  version: version,
  modifierGroups: product.modifierGroups,
);

class PosRepository {
  factory PosRepository({
    required PosDatabase database,
    required SaleSyncClient syncClient,
    PaymentProvider? paymentProvider,
    DateTime Function()? now,
    String Function()? createId,
  }) => PosRepository._(
    database,
    syncClient,
    paymentProvider ?? const CashPaymentProvider(),
    now ?? DateTime.now,
    createId ?? const Uuid().v4,
  );

  PosRepository._(
    this._database,
    this._syncClient,
    this._paymentProvider,
    this._now,
    this._createId,
  );

  final PosDatabase _database;
  final SaleSyncClient _syncClient;
  final PaymentProvider _paymentProvider;
  final DateTime Function() _now;
  final String Function() _createId;

  PosDatabase get database => _database;

  Future<CompletedSale> completeCashSale({
    required Iterable<SaleLine> lines,
    required int tenderedCents,
    String? shiftId,
    int discountCents = 0,
    String? discountReason,
    TaxConfig tax = const TaxConfig(),
    LoyaltyConfig loyalty = const LoyaltyConfig(),
    Customer? customer,
    int pointsRedeemed = 0,
    int loyaltyDiscountCents = 0,
  }) async {
    final sale = Sale.cash(
      id: _createId(),
      createdAt: _now(),
      lines: lines,
      tenderedCents: tenderedCents,
      shiftId: shiftId,
      discountCents: discountCents,
      discountReason: discountReason,
      taxRateBasisPoints: tax.rateBasisPoints,
      taxIncludedInPrice: tax.pricesIncludeTax,
      taxName: tax.name,
      taxConfigVersion: tax.version,
      customerId: customer?.id,
      pointsRedeemed: pointsRedeemed,
      loyaltyDiscountCents: loyaltyDiscountCents,
      loyaltyConfigVersion: customer == null ? 1 : loyalty.version,
      registerId: _syncClient.registerId,
    );
    final payment = await _paymentProvider.collect(
      sale: sale,
      paymentId: _createId(),
    );
    await _database.saveCheckout(sale, payment);
    final synced = await _syncClient.send(sale);
    var paymentSynced = false;
    if (synced) {
      await _database.markSaleSynced(sale.id);
      paymentSynced = await _syncClient.sendPayment(payment);
      if (paymentSynced) {
        await _database.markPaymentSynced(payment.id);
      } else {
        await _database.deferPayment(
          payment.id,
          _now().toUtc(),
          'Payment record not yet accepted. The register will retry automatically.',
        );
      }
    } else {
      await _database.deferSale(
        sale.id,
        _now().toUtc(),
        'Hub unavailable. The register will retry automatically.',
      );
    }
    return CompletedSale(
      sale: sale,
      payment: payment,
      synced: synced,
      paymentSynced: paymentSynced,
    );
  }

  Future<void> syncPendingSales({bool force = false}) async {
    for (final row in await _database.pendingSales(
      now: _now().toUtc(),
      force: force,
    )) {
      final sale = decodeLocalSale(row.payload);
      if (!await _syncClient.send(sale)) {
        await _database.deferSale(
          sale.id,
          _now().toUtc(),
          'Hub unavailable. The register will retry automatically.',
        );
        return;
      }
      await _database.markSaleSynced(sale.id);
    }
    await syncPendingPayments(force: force);
  }

  Future<void> syncPendingPayments({bool force = false}) async {
    for (final row in await _database.pendingPayments(
      now: _now().toUtc(),
      force: force,
    )) {
      final payment = PaymentRecord.fromJson(
        jsonDecode(row.payload) as Map<String, Object?>,
      );
      if (!await _database.isSaleSynced(payment.saleId)) continue;
      if (!await _syncClient.sendPayment(payment)) {
        await _database.deferPayment(
          payment.id,
          _now().toUtc(),
          'Payment record not yet accepted. The register will retry automatically.',
        );
        return;
      }
      await _database.markPaymentSynced(payment.id);
    }
  }

  Future<int> pendingPaymentCount() => _database.pendingPaymentCount();

  Future<SyncChangesResult?> syncChanges() async {
    final stored = await _database.readOperationalValue('sync_cursor');
    var cursor = int.tryParse(stored ?? '') ?? 0;
    var catalogChanged = false;
    var settingsChanged = false;
    var shiftChanged = false;
    var inventoryChanged = false;
    var maximumCursor = cursor;
    try {
      var keepReading = true;
      while (keepReading) {
        final page = await _syncClient.fetchSyncEvents(after: cursor);
        if (page.events.isEmpty) break;
        for (final event in page.events) {
          final type = event['type']! as String;
          final entity = event['entityType']! as String;
          if (entity == 'product' || type.startsWith('catalog.')) {
            catalogChanged = true;
          }
          if (entity == 'customer' ||
              type.startsWith('loyalty.') ||
              type.startsWith('tax.')) {
            settingsChanged = true;
          }
          if (entity == 'tax_settings' || entity == 'loyalty_settings') {
            settingsChanged = true;
          }
          if (entity == 'inventory' || type.startsWith('inventory.')) {
            inventoryChanged = true;
          }
          if (entity == 'sale') {
            inventoryChanged = true;
            shiftChanged = true;
            settingsChanged = true;
          }
          if (entity == 'cash_shift' || entity == 'cash_movement') {
            shiftChanged = true;
          }
        }
        maximumCursor = page.nextCursor;
        keepReading = page.hasMore;
        if (keepReading && page.nextCursor <= cursor) {
          throw const FormatException(
            'The hub returned a stalled sync cursor.',
          );
        }
        cursor = page.nextCursor;
      }

      CatalogSnapshot? catalog;
      if (catalogChanged) {
        catalog = await _syncClient.fetchProducts();
        await _database.replaceCachedProducts(
          catalog.version,
          catalog.products,
          categories: catalog.categories,
        );
      }
      if (inventoryChanged) await fetchInventory();
      if (settingsChanged) {
        final tax = await _syncClient.fetchTaxConfig();
        final loyalty = await _syncClient.fetchLoyaltyConfig();
        final customers = await _syncClient.fetchCustomers();
        await _database.saveOperationalValue(
          'tax_config',
          jsonEncode(tax.toJson()),
        );
        await _database.saveOperationalValue(
          'loyalty_config',
          jsonEncode(loyalty.toJson()),
        );
        await _database.saveOperationalValue(
          'customers_cache',
          jsonEncode(customers.map((row) => row.toJson()).toList()),
        );
      }
      if (shiftChanged) {
        final shift = await _syncClient.currentCashShift();
        await _database.saveCachedShift(shift);
      }

      await _database.saveOperationalValue('sync_cursor', '$maximumCursor');
      await _syncClient.acknowledgeSyncCursor(maximumCursor);
      return SyncChangesResult(
        catalog: catalog,
        settingsChanged: settingsChanged,
        shiftChanged: shiftChanged,
        inventoryChanged: inventoryChanged,
      );
    } on Exception {
      return null;
    }
  }

  Future<int> pendingSaleCount() => _database.pendingSaleCount();

  Future<List<CatalogCategory>> catalogCategories() async {
    try {
      final categories = await _syncClient.fetchCategories();
      await _database.saveCachedCategories(categories);
      return categories;
    } on Exception {
      final cached = await _database.readCachedCategories();
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<List<CatalogCategory>> createCatalogCategory(String name) async {
    final category = await _syncClient.createCategory(name);
    final current = await _database.readCachedCategories() ?? const [];
    final updated = [...current.where((row) => row.id != category.id), category]
      ..sort(_compareCategories);
    await _database.saveCachedCategories(updated);
    return updated;
  }

  Future<List<CatalogCategory>> setCatalogCategoryActive(
    CatalogCategory category, {
    required bool isActive,
  }) async {
    final updatedCategory = await _syncClient.setCategoryActive(
      category.id,
      isActive: isActive,
      expectedVersion: category.version,
    );
    final current = await _database.readCachedCategories() ?? const [];
    final updated = [
      for (final row in current)
        if (row.id == category.id) updatedCategory else row,
    ]..sort(_compareCategories);
    await _database.saveCachedCategories(updated);
    return updated;
  }

  int _compareCategories(CatalogCategory first, CatalogCategory second) {
    if (first.isActive != second.isActive) return first.isActive ? -1 : 1;
    return first.name.toLowerCase().compareTo(second.name.toLowerCase());
  }

  Future<List<Product>> saveCatalogProduct(
    Product? existing,
    Product updated,
  ) async {
    final productId = existing?.id ?? _createId();
    final previous = await _database.pendingCatalogOperationFor(productId);
    final expectedVersion = previous?.expectedVersion ?? existing?.version ?? 0;
    final id = previous?.id ?? _createId();
    final basePayload =
        previous?.basePayload ??
        (existing == null ? null : jsonEncode(existing.toJson()));
    final product = _withProductVersion(
      updated,
      id: productId,
      version: expectedVersion + 1,
    );
    await _database.enqueueCatalogOperation(
      id: id,
      productId: productId,
      payload: jsonEncode(product.toJson()),
      expectedVersion: expectedVersion,
      basePayload: basePayload,
      createdAt: _now().toUtc(),
    );
    await _database.saveCachedProduct(product);
    final cached = await _database.readCachedCatalog();
    if (cached == null) await _database.saveCatalogVersion(1);
    await syncPendingCatalogOperations(force: true);
    return _readActiveCachedProducts();
  }

  Future<void> syncPendingCatalogOperations({bool force = false}) async {
    for (final operation in await _database.pendingCatalogOperations(
      now: _now().toUtc(),
      force: force,
    )) {
      final product = Product.fromJson(
        jsonDecode(operation.payload) as Map<String, Object?>,
      );
      try {
        final result = await _syncClient.applyCatalogOperation(
          operationId: operation.id,
          expectedVersion: operation.expectedVersion,
          product: product,
        );
        if (result.conflict) {
          final currentPayload = result.currentProduct == null
              ? null
              : jsonEncode(result.currentProduct!.toJson());
          await _database.markCatalogOperationConflict(
            operation.id,
            'This product changed on another register.',
            currentPayload,
          );
          if (result.currentProduct != null) {
            await _database.saveCachedProduct(result.currentProduct!);
          }
          continue;
        }
        final savedProduct = result.product;
        if (savedProduct == null) {
          await _database.deferCatalogOperation(
            operation.id,
            _now().toUtc(),
            'The hub returned an empty catalog result.',
          );
          continue;
        }
        await _database.removeCatalogOperation(operation.id);
        await _database.saveCachedProduct(savedProduct);
        if (result.catalogVersion != null) {
          await _database.saveCatalogVersion(result.catalogVersion!);
        }
      } on HubApiException catch (error) {
        await _database.deferCatalogOperation(
          operation.id,
          _now().toUtc(),
          error.message,
        );
        if (error.statusCode >= 500) break;
      } on Exception {
        await _database.deferCatalogOperation(
          operation.id,
          _now().toUtc(),
          'Hub unavailable. The register will retry automatically.',
        );
        break;
      }
    }
  }

  Future<List<CatalogOperationSnapshot>> catalogOperations() async {
    final operations = await _database.visibleCatalogOperations();
    return operations
        .map(
          (operation) => CatalogOperationSnapshot(
            id: operation.id,
            productId: operation.productId,
            product: Product.fromJson(
              jsonDecode(operation.payload) as Map<String, Object?>,
            ),
            expectedVersion: operation.expectedVersion,
            status: operation.status,
            currentProduct: operation.conflictPayload == null
                ? null
                : Product.fromJson(
                    jsonDecode(operation.conflictPayload!)
                        as Map<String, Object?>,
                  ),
            error: operation.error,
          ),
        )
        .toList(growable: false);
  }

  Future<List<Product>> retryCatalogOperation(String id) async {
    await _database.retryCatalogOperation(id);
    await syncPendingCatalogOperations(force: true);
    return _readActiveCachedProducts();
  }

  Future<List<Product>> resolveCatalogConflictKeepLocal(String id) async {
    final rows = (await _database.visibleCatalogOperations())
        .where((row) => row.id == id)
        .toList();
    if (rows.isEmpty || rows.single.status != 'conflict') {
      return _readActiveCachedProducts();
    }
    final operation = rows.single;
    if (operation.conflictPayload == null) {
      throw const FormatException(
        'The hub version is unavailable for this conflict.',
      );
    }
    final current = Product.fromJson(
      jsonDecode(operation.conflictPayload!) as Map<String, Object?>,
    );
    final local = Product.fromJson(
      jsonDecode(operation.payload) as Map<String, Object?>,
    );
    final rebased = _withProductVersion(
      local,
      id: current.id,
      version: current.version + 1,
    );
    await _database.replaceCatalogConflictWithPending(
      oldId: id,
      newId: _createId(),
      productId: rebased.id,
      payload: jsonEncode(rebased.toJson()),
      expectedVersion: current.version,
      basePayload: jsonEncode(current.toJson()),
      createdAt: _now().toUtc(),
    );
    await _database.saveCachedProduct(rebased);
    await syncPendingCatalogOperations(force: true);
    return _readActiveCachedProducts();
  }

  Future<List<Product>> resolveCatalogConflictUseHub(String id) async {
    final rows = (await _database.visibleCatalogOperations())
        .where((row) => row.id == id)
        .toList();
    if (rows.isEmpty) return _readActiveCachedProducts();
    final operation = rows.single;
    await _database.removeCatalogOperation(id);
    final payload = operation.conflictPayload ?? operation.basePayload;
    if (payload == null) {
      await _database.deleteCachedProduct(operation.productId);
    } else {
      await _database.saveCachedProduct(
        Product.fromJson(jsonDecode(payload) as Map<String, Object?>),
      );
    }
    return _readActiveCachedProducts();
  }

  Future<List<Product>> _readActiveCachedProducts() async {
    final catalog = await _database.readCachedCatalog();
    return catalog?.products.where((product) => product.isActive).toList() ??
        const [];
  }

  Future<({List<Supplier> items, bool fromCache})> fetchSuppliers() async {
    try {
      final suppliers = await _syncClient.fetchSuppliers();
      await _database.saveCachedSuppliers(suppliers);
      return (items: suppliers, fromCache: false);
    } on Exception {
      final cached = await _database.readCachedSuppliers();
      if (cached == null) rethrow;
      return (items: cached, fromCache: true);
    }
  }

  Future<Supplier> createSupplier({
    required String id,
    required String name,
    String? contactName,
    String? email,
    String? phone,
    String? address,
    String? notes,
  }) async {
    final supplier = await _syncClient.createSupplier(
      id: id,
      name: name,
      contactName: contactName,
      email: email,
      phone: phone,
      address: address,
      notes: notes,
    );
    await _cacheSupplier(supplier);
    return supplier;
  }

  Future<Supplier> updateSupplier({
    required Supplier supplier,
    required int expectedVersion,
  }) async {
    final updated = await _syncClient.updateSupplier(
      supplier: supplier,
      expectedVersion: expectedVersion,
    );
    await _cacheSupplier(updated);
    return updated;
  }

  Future<Supplier> setSupplierActive({
    required String supplierId,
    required bool isActive,
    required int expectedVersion,
  }) async {
    final updated = await _syncClient.setSupplierActive(
      supplierId: supplierId,
      isActive: isActive,
      expectedVersion: expectedVersion,
    );
    await _cacheSupplier(updated);
    return updated;
  }

  Future<void> _cacheSupplier(Supplier supplier) async {
    final cached = await _database.readCachedSuppliers() ?? const <Supplier>[];
    await _database.saveCachedSuppliers([
      ...cached.where((item) => item.id != supplier.id),
      supplier,
    ]);
  }

  Future<({List<PurchaseOrder> items, bool fromCache})>
  fetchPurchaseOrders() async {
    try {
      final orders = await _syncClient.fetchPurchaseOrders();
      await _database.saveCachedPurchaseOrders(orders);
      return (items: orders, fromCache: false);
    } on Exception {
      final cached = await _database.readCachedPurchaseOrders();
      if (cached == null) rethrow;
      return (items: cached, fromCache: true);
    }
  }

  Future<PurchaseOrder> createPurchaseOrder({
    required String id,
    required String supplierId,
    required List<Map<String, Object?>> lines,
    String? expectedAt,
    String? note,
  }) async {
    final order = await _syncClient.createPurchaseOrder(
      id: id,
      supplierId: supplierId,
      lines: lines,
      expectedAt: expectedAt,
      note: note,
    );
    await _cachePurchaseOrder(order);
    return order;
  }

  Future<PurchaseOrder> placePurchaseOrder(String id) async {
    final order = await _syncClient.placePurchaseOrder(id);
    await _cachePurchaseOrder(order);
    return order;
  }

  Future<PurchaseOrder> cancelPurchaseOrder(String id) async {
    final order = await _syncClient.cancelPurchaseOrder(id);
    await _cachePurchaseOrder(order);
    return order;
  }

  Future<PurchaseOrder> receivePurchaseOrder({
    required String purchaseOrderId,
    required String receiptId,
    required String location,
    required List<Map<String, Object?>> lines,
    String? note,
  }) async {
    final order = await _syncClient.receivePurchaseOrder(
      purchaseOrderId: purchaseOrderId,
      receiptId: receiptId,
      location: location,
      lines: lines,
      note: note,
    );
    await _cachePurchaseOrder(order);
    return order;
  }

  Future<void> _cachePurchaseOrder(PurchaseOrder order) async {
    final cached =
        await _database.readCachedPurchaseOrders() ?? const <PurchaseOrder>[];
    await _database.saveCachedPurchaseOrders([
      order,
      ...cached.where((item) => item.id != order.id),
    ]);
  }

  Future<List<InventoryItem>> fetchInventory() async {
    List<InventoryItem> base;
    try {
      base = await _syncClient.fetchInventory();
      await _database.cacheInventory(base);
    } on Exception {
      base = await _database.readCachedInventory() ?? const [];
    }
    final balances = <String, Map<String, int>>{};
    final itemById = <String, InventoryItem>{};
    for (final item in base) {
      itemById[item.productId] = item;
      balances[item.productId] = {
        for (final location in item.locations)
          location.location: location.quantity,
      };
      if (item.locations.isEmpty) {
        balances[item.productId]!['Main'] = item.onHand;
      }
    }
    void change(String productId, String location, int delta) {
      if (!balances.containsKey(productId)) return;
      final locations = balances[productId]!;
      locations[location] = (locations[location] ?? 0) + delta;
    }

    for (final row in await _database.pendingStockOperations(force: true)) {
      final payload = jsonDecode(row.payload) as Map<String, Object?>;
      final productId = payload['productId'] as String;
      final quantity = payload['quantity'] as int;
      final type = payload['type'] as String;
      final source = payload['sourceLocation'] as String? ?? 'Main';
      final destination = payload['destinationLocation'] as String? ?? 'Main';
      if (type == StockMovementType.transfer.name) {
        change(productId, source, -quantity);
        change(productId, destination, quantity);
      } else if (type == StockMovementType.adjustment.name) {
        change(productId, destination, quantity);
      } else {
        change(productId, destination, quantity.abs());
      }
    }
    for (final row in await _database.pendingSales(force: true)) {
      final sale = decodeLocalSale(row.payload);
      for (final line in sale.lines) {
        change(line.productId, 'Main', -line.quantity);
      }
    }
    return base
        .map((item) {
          final locations = balances[item.productId]!.entries
              .map(
                (entry) => StockLocationBalance(
                  location: entry.key,
                  quantity: entry.value,
                ),
              )
              .toList(growable: false);
          final onHand = locations.fold<int>(
            0,
            (sum, location) => sum + location.quantity,
          );
          return InventoryItem(
            productId: item.productId,
            name: item.name,
            sku: item.sku,
            onHand: onHand,
            lowStockThreshold: item.lowStockThreshold,
            locations: locations,
          );
        })
        .toList(growable: false);
  }

  Future<bool> recordStockMovement({
    required String id,
    required String productId,
    required StockMovementType type,
    required int quantity,
    String? sourceLocation,
    String? destinationLocation,
    String? note,
  }) async {
    final payload = <String, Object?>{
      'id': id,
      'productId': productId,
      'type': type.name,
      'quantity': quantity,
      'sourceLocation': sourceLocation,
      'destinationLocation': destinationLocation,
      'note': note,
    };
    await _database.saveStockOperation(id, payload);
    await syncPendingStockMovements();
    final rows = await _database.visibleStockOperations();
    return !rows.any((row) => row.id == id && row.status != 'synced');
  }

  Future<void> syncPendingStockMovements({bool force = false}) async {
    for (final row in await _database.pendingStockOperations(
      now: _now().toUtc(),
      force: force,
    )) {
      final payload = jsonDecode(row.payload) as Map<String, Object?>;
      try {
        await _syncClient.createStockMovement(
          id: payload['id']! as String,
          productId: payload['productId']! as String,
          type: StockMovementType.values.byName(payload['type']! as String),
          quantity: payload['quantity']! as int,
          sourceLocation: payload['sourceLocation'] as String?,
          destinationLocation: payload['destinationLocation'] as String?,
          note: payload['note'] as String?,
        );
        await _database.markStockOperationSynced(row.id);
      } on HubApiException catch (error) {
        if (error.statusCode == 409 || error.statusCode == 400) {
          await _database.markStockOperationConflict(row.id, error.message);
          continue;
        }
        await _database.deferStockOperation(row.id, _now().toUtc());
        return;
      } on Exception {
        await _database.deferStockOperation(row.id, _now().toUtc());
        return;
      }
    }
  }

  Future<List<LocalStockOperation>> stockOperations() =>
      _database.visibleStockOperations();

  Future<void> retryStockOperation(String id) async {
    await _database.retryStockOperation(id);
    await syncPendingStockMovements(force: true);
  }

  Future<void> discardStockOperation(String id) =>
      _database.discardStockOperation(id);
}
