import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_pos/data/local_database.dart';
import 'package:open_pos/data/pos_repository.dart';
import 'package:open_pos/data/sale_sync_client.dart';
import 'package:pos_domain/pos_domain.dart';

void main() {
  late PosDatabase database;
  late SaleSyncClient syncClient;

  setUp(() {
    database = PosDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    syncClient.close();
    await database.close();
  });

  test('saves offline sales and retries the same sale ID later', () async {
    final postedSaleIds = <String>[];
    var attempts = 0;
    var paymentAttempts = 0;
    var now = DateTime.utc(2026, 11, 23);
    syncClient = SaleSyncClient(
      baseUrl: 'http://hub.test',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/payments')) {
          paymentAttempts++;
          return http.Response('', 201);
        }
        final payload = jsonDecode(request.body) as Map<String, Object?>;
        postedSaleIds.add(payload['id']! as String);
        attempts += 1;
        if (attempts == 1) throw const SocketException('offline');
        return http.Response('', 201);
      }),
    );
    final repository = PosRepository(
      database: database,
      syncClient: syncClient,
      now: () => now,
      createId: () => 'sale-1',
    );

    final completed = await repository.completeCashSale(
      lines: const [
        SaleLine(
          productId: 'coffee',
          name: 'Coffee',
          unitPriceCents: 8_500,
          quantity: 1,
        ),
      ],
      tenderedCents: 10_000,
    );

    expect(completed.synced, isFalse);
    expect(await repository.pendingSaleCount(), 1);
    await repository.syncPendingSales();
    expect(postedSaleIds, ['sale-1']);
    now = now.add(const Duration(seconds: 5));
    await repository.syncPendingSales();

    expect(postedSaleIds, ['sale-1', 'sale-1']);
    expect(paymentAttempts, 1);
    expect(await repository.pendingSaleCount(), 0);
  });

  test(
    'loads and manages categories, then serves the cached list offline',
    () async {
      var online = true;
      final initial = const CatalogCategory(id: 'category-1', name: 'Drinks');
      final created = const CatalogCategory(id: 'category-2', name: 'Snacks');
      syncClient = SaleSyncClient(
        baseUrl: 'http://hub.test',
        client: MockClient((request) async {
          if (!online) throw const SocketException('offline');
          if (request.url.path == '/api/v1/categories' &&
              request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'categories': [initial.toJson()],
              }),
              200,
            );
          }
          if (request.url.path == '/api/v1/categories' &&
              request.method == 'POST') {
            return http.Response(jsonEncode(created.toJson()), 201);
          }
          if (request.url.path.endsWith('/category-2') &&
              request.method == 'PUT') {
            expect(
              (jsonDecode(request.body)
                  as Map<String, Object?>)['expectedVersion'],
              1,
            );
            return http.Response(
              jsonEncode({
                ...created.toJson(),
                'isActive': false,
                'version': 2,
              }),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );
      final repository = PosRepository(
        database: database,
        syncClient: syncClient,
      );

      expect((await repository.catalogCategories()).single.name, 'Drinks');
      expect(
        (await repository.createCatalogCategory(
          'Snacks',
        )).map((row) => row.name),
        ['Drinks', 'Snacks'],
      );
      final archived = await repository.setCatalogCategoryActive(
        created,
        isActive: false,
      );
      expect(archived.last.isActive, isFalse);

      online = false;
      expect((await repository.catalogCategories()).map((row) => row.name), [
        'Drinks',
        'Snacks',
      ]);
      expect((await repository.catalogCategories()).last.isActive, isFalse);
    },
  );

  test(
    'refreshes cached categories from the shared catalog event feed',
    () async {
      const previous = CatalogCategory(id: 'category-old', name: 'Old');
      const current = CatalogCategory(id: 'category-new', name: 'New');
      await database.replaceCachedProducts(
        4,
        const [],
        categories: const [previous],
      );
      syncClient = SaleSyncClient(
        baseUrl: 'http://hub.test',
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/sync/events') {
            return http.Response(
              jsonEncode({
                'events': [
                  {
                    'type': 'catalog.category_created',
                    'entityType': 'category',
                  },
                ],
                'nextCursor': 1,
                'hasMore': false,
              }),
              200,
            );
          }
          if (request.url.path == '/api/v1/products') {
            return http.Response(
              jsonEncode({
                'version': 5,
                'products': [],
                'categories': [current.toJson()],
              }),
              200,
            );
          }
          if (request.url.path == '/api/v1/sync/ack') {
            return http.Response('{}', 200);
          }
          return http.Response('{}', 404);
        }),
      );
      final repository = PosRepository(
        database: database,
        syncClient: syncClient,
      );

      final changes = await repository.syncChanges();

      expect(changes?.catalog?.categories.single.name, 'New');
      expect((await database.readCachedCatalog())?.version, 5);
      expect(
        (await database.readCachedCategories())?.single.id,
        'category-new',
      );
    },
  );

  test(
    'serves cached suppliers and purchase orders when the hub is offline',
    () async {
      var online = true;
      final supplier = Supplier(
        id: 'supplier-cache-1',
        name: 'Blue Coast Supply',
        isActive: true,
        version: 2,
        createdAt: DateTime.utc(2026, 11, 24),
        updatedAt: DateTime.utc(2026, 11, 24, 8),
      );
      final order = PurchaseOrder(
        id: 'po-cache-1',
        supplierId: supplier.id,
        supplierName: supplier.name,
        status: PurchaseOrderStatus.partiallyReceived,
        createdAt: DateTime.utc(2026, 11, 24, 7),
        updatedAt: DateTime.utc(2026, 11, 24, 9),
        version: 3,
        lines: const [
          PurchaseOrderLine(
            id: 'po-cache-line-1',
            productId: 'coffee',
            productName: 'Coffee',
            orderedQuantity: 5,
            receivedQuantity: 2,
            unitCostCents: 400,
          ),
        ],
      );
      syncClient = SaleSyncClient(
        baseUrl: 'http://hub.test',
        client: MockClient((request) async {
          if (!online) throw const SocketException('offline');
          if (request.url.path == '/api/v1/suppliers') {
            return http.Response(
              jsonEncode({
                'suppliers': [supplier.toJson()],
              }),
              200,
            );
          }
          if (request.url.path == '/api/v1/purchase-orders') {
            return http.Response(
              jsonEncode({
                'purchaseOrders': [order.toJson()],
              }),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );
      final repository = PosRepository(
        database: database,
        syncClient: syncClient,
      );

      expect((await repository.fetchSuppliers()).fromCache, isFalse);
      expect((await repository.fetchPurchaseOrders()).fromCache, isFalse);
      online = false;

      final suppliers = await repository.fetchSuppliers();
      final orders = await repository.fetchPurchaseOrders();
      expect(suppliers.fromCache, isTrue);
      expect(suppliers.items.single.name, supplier.name);
      expect(orders.fromCache, isTrue);
      expect(orders.items.single.lines.single.receivedQuantity, 2);
    },
  );

  test(
    'queues offline catalog edits and applies them with the same ID',
    () async {
      var online = false;
      var now = DateTime.utc(2026, 11, 23);
      final operationIds = <String>[];
      syncClient = SaleSyncClient(
        baseUrl: 'http://hub.test',
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          operationIds.add(body['operationId']! as String);
          if (!online) throw const SocketException('offline');
          final product = (body['product']! as Map).cast<String, Object?>();
          return http.Response(
            jsonEncode({
              'operationId': body['operationId'],
              'catalogVersion': 7,
              'product': {...product, 'version': 1},
            }),
            201,
          );
        }),
      );
      final repository = PosRepository(
        database: database,
        syncClient: syncClient,
        now: () => now,
        createId: () => 'catalog-operation-1',
      );

      final products = await repository.saveCatalogProduct(
        null,
        const Product(
          id: 'new',
          name: 'Iced tea',
          category: 'Drinks',
          unitPriceCents: 5_000,
        ),
      );
      expect(products.single.name, 'Iced tea');
      expect(products.single.id, isNot('new'));
      expect((await repository.catalogOperations()).single.status, 'pending');

      online = true;
      now = now.add(const Duration(seconds: 5));
      await repository.syncPendingCatalogOperations();
      expect(operationIds, ['catalog-operation-1', 'catalog-operation-1']);
      expect(await repository.catalogOperations(), isEmpty);
      expect((await database.readCachedCatalog())?.products.single.version, 1);
    },
  );

  test(
    'offers a version-aware keep-local resolution for catalog conflicts',
    () async {
      var now = DateTime.utc(2026, 11, 23);
      final hubProduct = const Product(
        id: 'coffee',
        name: 'House coffee',
        category: 'Coffee',
        unitPriceCents: 1_000,
        version: 2,
      );
      var requestCount = 0;
      syncClient = SaleSyncClient(
        baseUrl: 'http://hub.test',
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          requestCount++;
          if (requestCount == 1) {
            return http.Response(
              jsonEncode({
                'error': 'catalog_version_conflict',
                'message': 'Product changed.',
                'currentProduct': hubProduct.toJson(),
              }),
              409,
            );
          }
          expect(body['expectedVersion'], 2);
          final product = (body['product']! as Map).cast<String, Object?>();
          return http.Response(
            jsonEncode({
              'operationId': body['operationId'],
              'catalogVersion': 9,
              'product': {...product, 'version': 3},
            }),
            200,
          );
        }),
      );
      await database.replaceCachedProducts(8, [hubProduct]);
      final repository = PosRepository(
        database: database,
        syncClient: syncClient,
        now: () => now,
        createId: () => 'conflict-operation',
      );
      await repository.saveCatalogProduct(
        hubProduct,
        const Product(
          id: 'coffee',
          name: 'House coffee local',
          category: 'Coffee',
          unitPriceCents: 1_100,
          version: 2,
        ),
      );
      final conflict = (await repository.catalogOperations()).single;
      expect(conflict.status, 'conflict');
      expect(conflict.currentProduct?.version, 2);

      await repository.resolveCatalogConflictKeepLocal(conflict.id);
      expect(await repository.catalogOperations(), isEmpty);
      final local = await database.readCachedCatalog();
      expect(local?.products.single.name, 'House coffee local');
      expect(local?.products.single.version, 3);
      expect(requestCount, 2);
      now = now.add(const Duration(seconds: 1));
    },
  );

  test(
    'queues offline inventory changes, overlays them, and records conflicts',
    () async {
      var online = false;
      var now = DateTime.utc(2026, 11, 23);
      syncClient = SaleSyncClient(
        baseUrl: 'http://hub.test',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/inventory')) {
            return http.Response(
              jsonEncode({
                'items': [
                  {
                    'productId': 'coffee',
                    'name': 'Coffee',
                    'onHand': 4,
                    'lowStockThreshold': 2,
                    'locations': [
                      {'location': 'Main', 'quantity': 4},
                    ],
                  },
                ],
                'lowStockCount': 0,
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/inventory/movements')) {
            if (!online) throw const SocketException('offline');
            return http.Response(
              jsonEncode({'message': 'Not enough stock at Main.'}),
              409,
            );
          }
          return http.Response('', 404);
        }),
      );
      final repository = PosRepository(
        database: database,
        syncClient: syncClient,
        now: () => now,
      );

      final synced = await repository.recordStockMovement(
        id: 'offline-adjustment',
        productId: 'coffee',
        type: StockMovementType.adjustment,
        quantity: -3,
        destinationLocation: 'Main',
      );
      expect(synced, isFalse);
      expect((await repository.fetchInventory()).single.onHand, 1);

      online = true;
      await repository.syncPendingStockMovements();
      expect((await repository.stockOperations()).single.status, 'pending');
      now = now.add(const Duration(seconds: 5));
      await repository.syncPendingStockMovements();
      final queued = await repository.stockOperations();
      expect(queued.single.status, 'conflict');
      expect(queued.single.error, 'Not enough stock at Main.');
      expect((await repository.fetchInventory()).single.onHand, 4);

      await repository.discardStockOperation('offline-adjustment');
      expect(await repository.stockOperations(), isEmpty);
    },
  );
}
