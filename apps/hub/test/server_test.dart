import 'dart:convert';

import 'package:hub/hub_app.dart';
import 'package:hub/hub_store.dart';
import 'package:pos_domain/pos_domain.dart';
import 'package:shelf/shelf.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late HubStore store;
  late Handler app;
  late String adminToken;

  setUp(() async {
    store = HubStore.inMemory();
    app = createApp(store);
    final session = await _postJson(app, '/api/v1/setup', {
      'storeName': 'Corner Store',
      'name': 'Admin User',
      'email': 'admin@example.test',
      'password': 'correct-horse-battery',
    });
    expect(session.statusCode, 201);
    adminToken =
        (jsonDecode(await session.readAsString()) as Map)['token'] as String;
  });

  tearDown(() => store.close());

  test('records schema upgrades and rejects databases from newer servers', () {
    final legacyDatabase = sqlite3.openInMemory();
    legacyDatabase.execute('''
      CREATE TABLE sales (
        id TEXT PRIMARY KEY,
        created_at TEXT NOT NULL,
        total_cents INTEGER NOT NULL,
        payload TEXT NOT NULL
      )
    ''');
    legacyDatabase.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        sku TEXT UNIQUE COLLATE NOCASE,
        barcode TEXT UNIQUE COLLATE NOCASE,
        unit_price_cents INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        version INTEGER NOT NULL DEFAULT 1,
        modifier_groups_json TEXT NOT NULL DEFAULT '[]',
        updated_at TEXT NOT NULL DEFAULT '2026-01-01T00:00:00.000Z'
      )
    ''');
    legacyDatabase.execute(
      'INSERT INTO products (id, name, category, unit_price_cents, updated_at) VALUES (?, ?, ?, ?, ?)',
      [
        'legacy-product',
        'Legacy tea',
        'Drinks',
        350,
        '2026-01-01T00:00:00.000Z',
      ],
    );
    legacyDatabase.execute(
      'INSERT INTO sales (id, created_at, total_cents, payload) VALUES (?, ?, ?, ?)',
      ['legacy-sale', '2026-11-23T00:00:00.000Z', 500, '{}'],
    );
    legacyDatabase.execute('PRAGMA user_version = 0');
    final upgraded = HubStore(legacyDatabase);
    try {
      expect(upgraded.schemaVersion, HubStore.currentSchemaVersion);
      expect(
        legacyDatabase
            .select('PRAGMA table_info(sales)')
            .map((row) => row['name']),
        containsAll(['shift_id', 'voided_at']),
      );
      expect(
        legacyDatabase.select('SELECT id FROM sales').single['id'],
        'legacy-sale',
      );
      expect(
        legacyDatabase
            .select('SELECT name FROM catalog_categories')
            .single['name'],
        'Drinks',
      );
      expect(
        legacyDatabase
            .select("SELECT name FROM sqlite_master WHERE type = 'table'")
            .map((row) => row['name']),
        containsAll([
          'suppliers',
          'purchase_orders',
          'purchase_order_lines',
          'purchase_order_receipts',
          'purchase_order_receipt_lines',
        ]),
      );
    } finally {
      upgraded.close();
    }

    final futureDatabase = sqlite3.openInMemory();
    futureDatabase.execute('PRAGMA user_version = 999');
    expect(() => HubStore(futureDatabase), throwsStateError);
    futureDatabase.close();
  });

  test(
    'exposes liveness and database readiness with secure response headers',
    () async {
      final live = await _get(app, '/health');
      expect(live.statusCode, 200);
      expect(jsonDecode(await live.readAsString())['status'], 'ok');

      final ready = await _get(app, '/health/ready');
      expect(ready.statusCode, 200);
      expect(jsonDecode(await ready.readAsString()), {
        'status': 'ready',
        'databaseIntegrity': 'ok',
        'schemaVersion': HubStore.currentSchemaVersion,
      });
      expect(ready.headers['cache-control'], 'no-store');
      expect(
        ready.headers['content-security-policy'],
        contains("default-src 'none'"),
      );
      expect(ready.headers['referrer-policy'], 'no-referrer');
      expect(ready.headers['x-content-type-options'], 'nosniff');
      expect(ready.headers['x-frame-options'], 'DENY');
    },
  );

  test(
    'first-run setup is one-time and creates an administrator session',
    () async {
      final status = await _get(app, '/api/v1/setup/status');
      expect(jsonDecode(await status.readAsString()), {
        'needsSetup': false,
        'store': {'id': isA<String>(), 'name': 'Corner Store'},
      });

      final duplicate = await _postJson(app, '/api/v1/setup', {
        'storeName': 'Another Store',
        'name': 'Owner',
        'email': 'owner@example.test',
        'password': 'correct-horse-battery',
      });
      expect(duplicate.statusCode, 409);

      final me = await _get(app, '/api/v1/auth/me', token: adminToken);
      final body = jsonDecode(await me.readAsString()) as Map;
      expect(me.statusCode, 200);
      expect(body['user']['role'], 'admin');
      expect(body['store']['name'], 'Corner Store');
      expect(body.toString(), isNot(contains('password_hash')));
    },
  );

  test('requires authentication before accessing the sales API', () async {
    final sale = _sampleSale();
    final response = await _postJson(app, '/api/v1/sales', sale.toJson());
    expect(response.statusCode, 401);

    final products = await _get(app, '/api/v1/products');
    expect(products.statusCode, 401);
  });

  test(
    'sales report is manager-only and summarizes UTC sales and shifts',
    () async {
      expect(
        (await _get(
          app,
          '/api/v1/reports/sales?from=2026-11-23&to=2026-11-23',
        )).statusCode,
        401,
      );
      final cashierCreated = await _postJson(app, '/api/v1/users', {
        'name': 'Report Cashier',
        'email': 'report-cashier@example.test',
        'password': 'report-cashier-password',
        'role': 'cashier',
      }, token: adminToken);
      expect(cashierCreated.statusCode, 201);
      final cashierLogin = await _postJson(app, '/api/v1/auth/login', {
        'email': 'report-cashier@example.test',
        'password': 'report-cashier-password',
      });
      final cashierToken =
          (jsonDecode(await cashierLogin.readAsString()) as Map)['token']
              as String;
      final managerCreated = await _postJson(app, '/api/v1/users', {
        'name': 'Report Manager',
        'email': 'report-manager@example.test',
        'password': 'report-manager-password',
        'role': 'manager',
      }, token: adminToken);
      expect(managerCreated.statusCode, 201);
      final managerLogin = await _postJson(app, '/api/v1/auth/login', {
        'email': 'report-manager@example.test',
        'password': 'report-manager-password',
      });
      final managerToken =
          (jsonDecode(await managerLogin.readAsString()) as Map)['token']
              as String;
      expect(
        (await _get(
          app,
          '/api/v1/reports/sales?from=2026-11-23&to=2026-11-23',
          token: cashierToken,
        )).statusCode,
        403,
      );

      final invalidDate = await _get(
        app,
        '/api/v1/reports/sales?from=2026-02-31&to=2026-03-01',
        token: adminToken,
      );
      expect(invalidDate.statusCode, 400);
      final oversizedRange = await _get(
        app,
        '/api/v1/reports/sales?from=2025-01-01&to=2026-01-02',
        token: adminToken,
      );
      expect(oversizedRange.statusCode, 400);

      final now = DateTime.now().toUtc();
      final today = DateTime.utc(now.year, now.month, now.day);
      final rangeFrom = today.subtract(const Duration(days: 1));
      final rangeTo = today.add(const Duration(days: 1));
      final shift = await _postJson(app, '/api/v1/shifts', {
        'id': 'report-shift',
        'registerId': 'main',
        'openingFloatCents': 10_000,
      }, token: adminToken);
      expect(shift.statusCode, 201);
      final sale = Sale.cash(
        id: 'report-sale',
        createdAt: now,
        lines: const [
          SaleLine(
            productId: 'coffee',
            name: 'Brewed coffee',
            unitPriceCents: 8_500,
            quantity: 1,
          ),
        ],
        tenderedCents: 10_000,
        shiftId: 'report-shift',
        registerId: 'main',
      );
      expect((await _postSale(app, sale, adminToken)).statusCode, 201);
      final close = await _postJson(app, '/api/v1/shifts/report-shift/close', {
        'countedCashCents': 18_000,
      }, token: adminToken);
      expect(close.statusCode, 200);

      String dateKey(DateTime value) =>
          value.toIso8601String().substring(0, 10);
      final reportResponse = await _get(
        app,
        '/api/v1/reports/sales?from=${dateKey(rangeFrom)}&to=${dateKey(rangeTo)}',
        token: managerToken,
      );
      expect(reportResponse.statusCode, 200);
      final report = jsonDecode(await reportResponse.readAsString()) as Map;
      expect(report['dateBasis'], 'UTC');
      final summary = report['summary'] as Map;
      expect(summary['salesCount'], 1);
      expect(summary['grossSalesCents'], 8_500);
      expect(summary['netSalesCents'], 8_500);
      expect(summary['shiftsOpened'], 1);
      expect(summary['shiftsClosed'], 1);
      expect(summary['cashVarianceCents'], -500);
      final topProduct = (report['topProducts'] as List).single as Map;
      expect(topProduct['productId'], 'coffee');
      expect(topProduct['quantity'], 1);
      expect(topProduct['grossCents'], 8_500);
      final daily = (report['daily'] as List).cast<Map>();
      expect(
        daily.singleWhere((row) => row['salesCount'] == 1)['grossSalesCents'],
        8_500,
      );
      final reportedShift = (report['shifts'] as List).single as Map;
      expect(reportedShift['expectedCashCents'], 18_500);
      expect(reportedShift['varianceCents'], -500);
    },
  );

  test(
    'purchase orders receive stock partially and retries do not double receive',
    () async {
      final productCreated = await _postJson(app, '/api/v1/products', {
        'name': 'Purchase coffee',
        'category': 'Coffee',
        'sku': 'PO-COFFEE-01',
        'unitPriceCents': 800,
      }, token: adminToken);
      expect(productCreated.statusCode, 201);
      final productId =
          (jsonDecode(await productCreated.readAsString()) as Map)['id']
              as String;

      final cashierCreated = await _postJson(app, '/api/v1/users', {
        'name': 'Purchase Cashier',
        'email': 'purchase-cashier@example.test',
        'password': 'purchase-cashier-password',
        'role': 'cashier',
      }, token: adminToken);
      expect(cashierCreated.statusCode, 201);
      final cashierLogin = await _postJson(app, '/api/v1/auth/login', {
        'email': 'purchase-cashier@example.test',
        'password': 'purchase-cashier-password',
      });
      final cashierToken =
          (jsonDecode(await cashierLogin.readAsString()) as Map)['token']
              as String;
      expect(
        (await _get(app, '/api/v1/suppliers', token: cashierToken)).statusCode,
        403,
      );
      expect(
        (await _get(
          app,
          '/api/v1/purchase-orders',
          token: cashierToken,
        )).statusCode,
        403,
      );
      expect(
        (await _postJson(
          app,
          '/api/v1/purchase-orders',
          const {},
          token: cashierToken,
        )).statusCode,
        403,
      );

      final supplierBody = {
        'id': 'supplier-coast',
        'name': 'Blue Coast Supply',
        'contactName': 'Alex Reyes',
        'email': 'orders@bluecoast.example',
      };
      final supplierCreated = await _postJson(
        app,
        '/api/v1/suppliers',
        supplierBody,
        token: adminToken,
      );
      expect(supplierCreated.statusCode, 201);
      expect(
        (jsonDecode(await supplierCreated.readAsString()) as Map)['version'],
        1,
      );
      final supplierRetry = await _postJson(
        app,
        '/api/v1/suppliers',
        supplierBody,
        token: adminToken,
      );
      expect(supplierRetry.statusCode, 200);
      expect(
        (jsonDecode(await supplierRetry.readAsString()) as Map)['id'],
        'supplier-coast',
      );

      final orderBody = {
        'id': 'po-coast-001',
        'supplierId': 'supplier-coast',
        'expectedAt': '2026-12-01',
        'note': 'Weekly coffee stock',
        'lines': [
          {
            'id': 'po-coast-line-coffee',
            'productId': productId,
            'quantity': 5,
            'unitCostCents': 400,
          },
        ],
      };
      final orderCreated = await _postJson(
        app,
        '/api/v1/purchase-orders',
        orderBody,
        token: adminToken,
      );
      expect(orderCreated.statusCode, 201);
      final orderJson =
          (jsonDecode(await orderCreated.readAsString())
                  as Map)['purchaseOrder']
              as Map;
      expect(orderJson['status'], 'draft');
      expect(orderJson['totalCents'], 2_000);
      final orderRetry = await _postJson(
        app,
        '/api/v1/purchase-orders',
        orderBody,
        token: adminToken,
      );
      expect(orderRetry.statusCode, 200);
      expect(
        (((jsonDecode(await orderRetry.readAsString()) as Map)['purchaseOrder'])
            as Map)['id'],
        'po-coast-001',
      );
      final conflictingOrderRetry = await _postJson(
        app,
        '/api/v1/purchase-orders',
        {...orderBody, 'note': 'Different order details'},
        token: adminToken,
      );
      expect(conflictingOrderRetry.statusCode, 409);

      final placed = await _postJson(
        app,
        '/api/v1/purchase-orders/po-coast-001/place',
        const {},
        token: adminToken,
      );
      expect(placed.statusCode, 200);
      expect(
        ((jsonDecode(await placed.readAsString()) as Map)['purchaseOrder']
            as Map)['status'],
        'ordered',
      );

      final receipt = {
        'id': 'po-coast-receipt-1',
        'location': 'Back room',
        'lines': [
          {'lineId': 'po-coast-line-coffee', 'quantity': 2},
        ],
      };
      final partial = await _postJson(
        app,
        '/api/v1/purchase-orders/po-coast-001/receipts',
        receipt,
        token: adminToken,
      );
      expect(partial.statusCode, 201);
      final partialOrder =
          (jsonDecode(await partial.readAsString()) as Map)['purchaseOrder']
              as Map;
      expect(partialOrder['status'], 'partially_received');
      expect(
        ((partialOrder['lines'] as List).single as Map)['receivedQuantity'],
        2,
      );
      final inventoryAfterPartial = await _get(
        app,
        '/api/v1/inventory',
        token: adminToken,
      );
      int coffeeOnHand(String responseBody) {
        final items = (jsonDecode(responseBody) as Map)['items'] as List;
        return (items.singleWhere((item) => item['productId'] == productId)
                as Map)['onHand']
            as int;
      }

      expect(coffeeOnHand(await inventoryAfterPartial.readAsString()), 2);
      final receiptRetry = await _postJson(
        app,
        '/api/v1/purchase-orders/po-coast-001/receipts',
        receipt,
        token: adminToken,
      );
      expect(receiptRetry.statusCode, 200);
      expect(
        coffeeOnHand(
          await (await _get(
            app,
            '/api/v1/inventory',
            token: adminToken,
          )).readAsString(),
        ),
        2,
      );
      final conflictingReceiptRetry = await _postJson(
        app,
        '/api/v1/purchase-orders/po-coast-001/receipts',
        {...receipt, 'note': 'Different receipt details'},
        token: adminToken,
      );
      expect(conflictingReceiptRetry.statusCode, 409);
      expect(
        coffeeOnHand(
          await (await _get(
            app,
            '/api/v1/inventory',
            token: adminToken,
          )).readAsString(),
        ),
        2,
      );

      final excessiveReceipt = await _postJson(
        app,
        '/api/v1/purchase-orders/po-coast-001/receipts',
        {
          'id': 'po-coast-receipt-too-many',
          'location': 'Back room',
          'lines': [
            {'lineId': 'po-coast-line-coffee', 'quantity': 4},
          ],
        },
        token: adminToken,
      );
      expect(excessiveReceipt.statusCode, 409);

      final finalReceipt = await _postJson(
        app,
        '/api/v1/purchase-orders/po-coast-001/receipts',
        {
          'id': 'po-coast-receipt-2',
          'location': 'Back room',
          'lines': [
            {'lineId': 'po-coast-line-coffee', 'quantity': 3},
          ],
        },
        token: adminToken,
      );
      expect(finalReceipt.statusCode, 201);
      final completeOrder =
          (jsonDecode(await finalReceipt.readAsString())
                  as Map)['purchaseOrder']
              as Map;
      expect(completeOrder['status'], 'received');
      expect(
        coffeeOnHand(
          await (await _get(
            app,
            '/api/v1/inventory',
            token: adminToken,
          )).readAsString(),
        ),
        5,
      );
      final cancelReceived = await _postJson(
        app,
        '/api/v1/purchase-orders/po-coast-001/cancel',
        const {},
        token: adminToken,
      );
      expect(cancelReceived.statusCode, 409);

      final updatedSupplier =
          await _putJson(app, '/api/v1/suppliers/supplier-coast', {
            'name': 'Blue Coast Supply Ltd',
            'contactName': 'Alex Reyes',
            'email': 'orders@bluecoast.example',
            'expectedVersion': 1,
          }, token: adminToken);
      expect(updatedSupplier.statusCode, 200);
      expect(
        (jsonDecode(await updatedSupplier.readAsString()) as Map)['version'],
        2,
      );
      final staleSupplierUpdate = await _putJson(
        app,
        '/api/v1/suppliers/supplier-coast',
        {'name': 'Stale Blue Coast Supply', 'expectedVersion': 1},
        token: adminToken,
      );
      expect(staleSupplierUpdate.statusCode, 409);
      final archiveSupplier = await _putJson(
        app,
        '/api/v1/suppliers/supplier-coast/active',
        {'isActive': false, 'expectedVersion': 2},
        token: adminToken,
      );
      expect(archiveSupplier.statusCode, 200);
      expect(
        (jsonDecode(await archiveSupplier.readAsString()) as Map)['isActive'],
        isFalse,
      );
    },
  );

  test(
    'sync feed pages events and acknowledges per-register cursors',
    () async {
      final enrolled = await _postJson(app, '/api/v1/registers', {
        'id': 'sync-register-a',
        'name': 'Front till',
      }, token: adminToken);
      expect(enrolled.statusCode, 201);

      final firstPage = await _get(
        app,
        '/api/v1/sync/events?registerId=sync-register-a&after=0&limit=1',
        token: adminToken,
      );
      expect(firstPage.statusCode, 200);
      final first = jsonDecode(await firstPage.readAsString()) as Map;
      expect((first['events'] as List), hasLength(1));
      expect(first['hasMore'], isTrue);
      final firstCursor = first['nextCursor'] as int;

      final acknowledgement = await _postJson(app, '/api/v1/sync/ack', {
        'registerId': 'sync-register-a',
        'cursor': firstCursor,
      }, token: adminToken);
      expect(acknowledgement.statusCode, 200);

      final resumed = await _get(
        app,
        '/api/v1/sync/events?registerId=sync-register-a&limit=10',
        token: adminToken,
      );
      final resumedBody = jsonDecode(await resumed.readAsString()) as Map;
      expect(resumed.statusCode, 200);
      expect((resumedBody['events'] as List), isNotEmpty);
      expect(resumedBody['nextCursor'], greaterThan(firstCursor));

      final invalidAcknowledgement = await _postJson(app, '/api/v1/sync/ack', {
        'registerId': 'sync-register-a',
        'cursor': (resumedBody['nextCursor'] as int) + 100,
      }, token: adminToken);
      expect(invalidAcknowledgement.statusCode, 409);
    },
  );

  test(
    'exposes authenticated operational health to store administrators',
    () async {
      expect((await _get(app, '/api/v1/operations/health')).statusCode, 401);
      final response = await _get(
        app,
        '/api/v1/operations/health',
        token: adminToken,
      );
      expect(response.statusCode, 200);
      final health = jsonDecode(await response.readAsString()) as Map;
      expect(health['status'], 'ok');
      expect(health['databaseIntegrity'], 'ok');
      expect(health['schemaVersion'], HubStore.currentSchemaVersion);
      expect(health['registerCount'], greaterThan(0));
      expect(health['sync']['latestCursor'], greaterThan(0));
    },
  );

  test('accepts and returns a cash sale', () async {
    final sale = _sampleSale();
    final response = await _postSale(app, sale, adminToken);

    expect(response.statusCode, 201);
    expect(jsonDecode(await response.readAsString()), {
      'id': sale.id,
      'status': 'accepted',
    });

    final saved = await _get(
      app,
      '/api/v1/sales/${sale.id}',
      token: adminToken,
    );
    expect(saved.statusCode, 200);
    expect(jsonDecode(await saved.readAsString()), sale.toJson());
  });

  test('accepts identical retries without duplicating the sale', () async {
    final sale = _sampleSale();
    expect((await _postSale(app, sale, adminToken)).statusCode, 201);
    expect((await _postSale(app, sale, adminToken)).statusCode, 200);
    final saved = await _get(
      app,
      '/api/v1/sales/${sale.id}',
      token: adminToken,
    );
    expect(jsonDecode(await saved.readAsString()), sale.toJson());
  });

  test(
    'stores payment state separately and accepts identical payment retries',
    () async {
      final sale = _sampleSale();
      expect((await _postSale(app, sale, adminToken)).statusCode, 201);
      final now = sale.createdAt;
      final payment = PaymentRecord(
        id: 'payment-1',
        saleId: sale.id,
        provider: 'cash',
        method: 'cash',
        status: PaymentStatus.captured,
        amountCents: sale.totalCents,
        tenderedCents: sale.tenderedCents,
        changeCents: sale.changeCents,
        createdAt: now,
        updatedAt: now,
      );
      final recorded = await _postJson(
        app,
        '/api/v1/sales/${sale.id}/payments',
        payment.toJson(),
        token: adminToken,
      );
      expect(recorded.statusCode, 201);
      expect(jsonDecode(await recorded.readAsString())['status'], 'captured');

      final repeated = await _postJson(
        app,
        '/api/v1/sales/${sale.id}/payments',
        payment.toJson(),
        token: adminToken,
      );
      expect(repeated.statusCode, 200);
      final saved = await _get(
        app,
        '/api/v1/sales/${sale.id}/payment',
        token: adminToken,
      );
      expect(saved.statusCode, 200);
      expect(
        PaymentRecord.fromJson(
          (jsonDecode(await saved.readAsString()) as Map)
              .cast<String, Object?>(),
        ).status,
        PaymentStatus.captured,
      );

      final mismatch = PaymentRecord(
        id: 'payment-other',
        saleId: sale.id,
        provider: 'cash',
        method: 'cash',
        status: PaymentStatus.captured,
        amountCents: sale.totalCents - 1,
        tenderedCents: sale.tenderedCents,
        changeCents: sale.changeCents + 1,
        createdAt: now,
        updatedAt: now,
      );
      final rejected = await _postJson(
        app,
        '/api/v1/sales/${sale.id}/payments',
        mismatch.toJson(),
        token: adminToken,
      );
      expect(rejected.statusCode, 409);
      expect(
        jsonDecode(await rejected.readAsString())['error'],
        'payment_amount_mismatch',
      );
    },
  );

  test(
    'configures tax and loyalty customers and applies points exactly once',
    () async {
      final defaults = await _get(app, '/api/v1/tax', token: adminToken);
      expect(jsonDecode(await defaults.readAsString()), {
        'name': 'Tax',
        'rateBasisPoints': 0,
        'pricesIncludeTax': false,
        'version': 1,
      });
      final configured = await _putJson(app, '/api/v1/tax', {
        'name': 'VAT',
        'rateBasisPoints': 875,
        'pricesIncludeTax': true,
      }, token: adminToken);
      expect(configured.statusCode, 200);
      final taxVersion =
          (jsonDecode(await configured.readAsString()) as Map)['version']
              as int;
      final offlineSnapshot = Sale.cash(
        id: 'offline-tax-v1-sale',
        createdAt: DateTime.utc(2026, 11, 23),
        lines: const [
          SaleLine(
            productId: 'taxed-item',
            name: 'Item',
            unitPriceCents: 10000,
            quantity: 1,
          ),
        ],
        tenderedCents: 10000,
      );
      expect(
        (await _postSale(app, offlineSnapshot, adminToken)).statusCode,
        201,
      );
      final alteredTax = Sale.cash(
        id: 'altered-tax-sale',
        createdAt: DateTime.utc(2026, 11, 23),
        lines: const [
          SaleLine(
            productId: 'taxed-item',
            name: 'Item',
            unitPriceCents: 10000,
            quantity: 1,
          ),
        ],
        tenderedCents: 10000,
        taxName: 'VAT',
        taxRateBasisPoints: 0,
        taxConfigVersion: taxVersion,
      );
      expect((await _postSale(app, alteredTax, adminToken)).statusCode, 409);

      final created = await _postJson(app, '/api/v1/customers', {
        'name': 'Ana Santos',
        'phone': '+639171234567',
      }, token: adminToken);
      expect(created.statusCode, 201);
      final customer = jsonDecode(await created.readAsString()) as Map;
      final customerId = customer['id'] as String;
      final sale = Sale.cash(
        id: 'loyalty-sale-1',
        createdAt: DateTime.utc(2026, 11, 23),
        lines: const [
          SaleLine(
            productId: 'loyalty-item',
            name: 'Item',
            unitPriceCents: 10000,
            quantity: 1,
          ),
        ],
        tenderedCents: 10000,
        customerId: customerId,
        taxName: 'VAT',
        taxRateBasisPoints: 875,
        taxIncludedInPrice: true,
        taxConfigVersion: taxVersion,
      );
      expect((await _postSale(app, sale, adminToken)).statusCode, 201);
      expect((await _postSale(app, sale, adminToken)).statusCode, 200);
      final loyaltyProgram = await _putJson(app, '/api/v1/loyalty/settings', {
        'earnPointsPer100Cents': 2,
        'redeemCentsPerPoint': 2,
        'version': 1,
      }, token: adminToken);
      expect(
        (jsonDecode(await loyaltyProgram.readAsString()) as Map)['version'],
        2,
      );

      final redeemed = Sale.cash(
        id: 'loyalty-sale-2',
        createdAt: DateTime.utc(2026, 11, 23),
        lines: const [
          SaleLine(
            productId: 'loyalty-item',
            name: 'Item',
            unitPriceCents: 10000,
            quantity: 1,
          ),
        ],
        tenderedCents: 9990,
        discountCents: 10,
        discountReason: 'Loyalty redemption',
        customerId: customerId,
        pointsRedeemed: 10,
        loyaltyDiscountCents: 10,
        loyaltyConfigVersion: 1,
        taxRateBasisPoints: 875,
        taxIncludedInPrice: true,
        taxName: 'VAT',
        taxConfigVersion: taxVersion,
      );
      expect((await _postSale(app, redeemed, adminToken)).statusCode, 201);
      final customers = await _get(app, '/api/v1/customers', token: adminToken);
      final rows =
          (jsonDecode(await customers.readAsString()) as Map)['customers']
              as List;
      expect((rows.single as Map)['loyaltyPoints'], 189);
    },
  );

  test(
    'allows separate register shifts and isolates current drawers',
    () async {
      for (final entry in const [
        ('reg-a', 'Front till'),
        ('reg-b', 'Back till'),
      ]) {
        final enrolled = await _postJson(app, '/api/v1/registers', {
          'id': entry.$1,
          'name': entry.$2,
        }, token: adminToken);
        expect(enrolled.statusCode, 201);
        final shift = await _postJson(app, '/api/v1/shifts', {
          'id': 'shift-${entry.$1}',
          'registerId': entry.$1,
          'openingFloatCents': 1000,
        }, token: adminToken);
        expect(shift.statusCode, 201);
      }
      expect(
        (await _postJson(app, '/api/v1/shifts', {
          'id': 'reg-a-second',
          'registerId': 'reg-a',
          'openingFloatCents': 0,
        }, token: adminToken)).statusCode,
        409,
      );
      final currentA = await _get(
        app,
        '/api/v1/shifts/current?registerId=reg-a',
        token: adminToken,
      );
      final currentB = await _get(
        app,
        '/api/v1/shifts/current?registerId=reg-b',
        token: adminToken,
      );
      expect(
        ((jsonDecode(await currentA.readAsString()) as Map)['shift']
            as Map)['id'],
        'shift-reg-a',
      );
      expect(
        ((jsonDecode(await currentB.readAsString()) as Map)['shift']
            as Map)['id'],
        'shift-reg-b',
      );
    },
  );

  test(
    'returns items partially, restores stock and voids only untouched sales',
    () async {
      final productResponse = await _postJson(app, '/api/v1/products', {
        'name': 'Return coffee',
        'category': 'Coffee',
        'sku': 'RET-001',
        'unitPriceCents': 500,
      }, token: adminToken);
      final productId =
          (jsonDecode(await productResponse.readAsString()) as Map)['id']
              as String;
      await _postJson(app, '/api/v1/inventory/movements', {
        'id': 'return-stock-receive',
        'productId': productId,
        'type': 'receive',
        'quantity': 5,
      }, token: adminToken);
      await _postJson(app, '/api/v1/shifts', {
        'id': 'return-shift',
        'openingFloatCents': 1000,
      }, token: adminToken);
      final sale = Sale.cash(
        id: 'returnable-sale',
        createdAt: DateTime.utc(2026, 11, 23),
        lines: [
          SaleLine(
            productId: productId,
            name: 'Return coffee',
            unitPriceCents: 500,
            quantity: 2,
          ),
        ],
        tenderedCents: 1000,
        shiftId: 'return-shift',
      );
      expect((await _postSale(app, sale, adminToken)).statusCode, 201);
      final payment = PaymentRecord(
        id: 'return-payment',
        saleId: sale.id,
        provider: 'cash',
        method: 'cash',
        status: PaymentStatus.captured,
        amountCents: sale.totalCents,
        tenderedCents: sale.tenderedCents,
        changeCents: sale.changeCents,
        createdAt: sale.createdAt,
        updatedAt: sale.createdAt,
      );
      expect(
        (await _postJson(
          app,
          '/api/v1/sales/${sale.id}/payments',
          payment.toJson(),
          token: adminToken,
        )).statusCode,
        201,
      );
      final returned = {
        'id': 'return-1',
        'saleId': sale.id,
        'reason': 'Customer changed mind',
        'lines': [
          {'productId': productId, 'quantity': 1, 'restock': true},
        ],
      };
      final firstReturn = await _postJson(
        app,
        '/api/v1/returns',
        returned,
        token: adminToken,
      );
      expect(firstReturn.statusCode, 201);
      expect(
        (jsonDecode(await firstReturn.readAsString()) as Map)['refundCents'],
        500,
      );
      final paymentAfterReturn = await _get(
        app,
        '/api/v1/sales/${sale.id}/payment',
        token: adminToken,
      );
      final returnedPayment = PaymentRecord.fromJson(
        (jsonDecode(await paymentAfterReturn.readAsString()) as Map)
            .cast<String, Object?>(),
      );
      expect(returnedPayment.status, PaymentStatus.partiallyRefunded);
      expect(returnedPayment.refundedCents, 500);
      expect(
        (await _postJson(
          app,
          '/api/v1/returns',
          returned,
          token: adminToken,
        )).statusCode,
        200,
      );
      expect(
        (await _postJson(app, '/api/v1/returns', {
          ...returned,
          'id': 'return-too-many',
          'lines': [
            {'productId': productId, 'quantity': 2, 'restock': true},
          ],
        }, token: adminToken)).statusCode,
        409,
      );
      expect(
        (await _postJson(app, '/api/v1/sales/${sale.id}/void', {
          'reason': 'Mistake',
        }, token: adminToken)).statusCode,
        409,
      );

      final untouched = Sale.cash(
        id: 'voidable-sale',
        createdAt: DateTime.utc(2026, 11, 23),
        lines: [
          SaleLine(
            productId: productId,
            name: 'Return coffee',
            unitPriceCents: 500,
            quantity: 1,
          ),
        ],
        tenderedCents: 500,
        shiftId: 'return-shift',
      );
      expect((await _postSale(app, untouched, adminToken)).statusCode, 201);
      final untouchedPayment = PaymentRecord(
        id: 'void-payment',
        saleId: untouched.id,
        provider: 'cash',
        method: 'cash',
        status: PaymentStatus.captured,
        amountCents: untouched.totalCents,
        tenderedCents: untouched.tenderedCents,
        changeCents: untouched.changeCents,
        createdAt: untouched.createdAt,
        updatedAt: untouched.createdAt,
      );
      expect(
        (await _postJson(
          app,
          '/api/v1/sales/${untouched.id}/payments',
          untouchedPayment.toJson(),
          token: adminToken,
        )).statusCode,
        201,
      );
      expect(
        (await _postJson(app, '/api/v1/sales/${untouched.id}/void', {
          'reason': 'Wrong item',
        }, token: adminToken)).statusCode,
        200,
      );
      final voidedPayment = await _get(
        app,
        '/api/v1/sales/${untouched.id}/payment',
        token: adminToken,
      );
      expect(
        PaymentRecord.fromJson(
          (jsonDecode(await voidedPayment.readAsString()) as Map)
              .cast<String, Object?>(),
        ).status,
        PaymentStatus.voided,
      );
      expect(
        (await _postJson(app, '/api/v1/sales/${untouched.id}/void', {
          'reason': 'Wrong item',
        }, token: adminToken)).statusCode,
        200,
      );
      final inventoryResponse = await _get(
        app,
        '/api/v1/inventory',
        token: adminToken,
      );
      final inventory =
          (jsonDecode(await inventoryResponse.readAsString()) as Map)['items']
              as List;
      expect((inventory.single as Map)['onHand'], 4);
    },
  );

  test(
    'returns the selected modifier line and accepts a retry after shift close',
    () async {
      final createdResponse = await _postJson(app, '/api/v1/products', {
        'name': 'Return tea',
        'category': 'Drinks',
        'unitPriceCents': 500,
      }, token: adminToken);
      final created =
          jsonDecode(await createdResponse.readAsString())
              as Map<String, Object?>;
      final productId = created['id']! as String;
      final group = ModifierGroup(
        id: 'size',
        name: 'Size',
        minimumSelections: 1,
        maximumSelections: 1,
        options: const [
          ModifierOption(id: 'regular', name: 'Regular'),
          ModifierOption(id: 'large', name: 'Large', priceDeltaCents: 500),
        ],
      );
      final editedProduct = {
        ...created,
        'modifierGroups': [group.toJson()],
      };
      final catalogUpdate = await _postJson(app, '/api/v1/catalog/operations', {
        'operationId': 'return-modifier-product-edit',
        'expectedVersion': 1,
        'product': editedProduct,
      }, token: adminToken);
      expect(catalogUpdate.statusCode, 200);
      await _postJson(app, '/api/v1/inventory/movements', {
        'id': 'return-modifier-stock',
        'productId': productId,
        'type': 'receive',
        'quantity': 2,
      }, token: adminToken);
      expect(
        (await _postJson(app, '/api/v1/shifts', {
          'id': 'return-modifier-shift',
          'openingFloatCents': 1000,
        }, token: adminToken)).statusCode,
        201,
      );
      final sale = Sale.cash(
        id: 'return-modifier-sale',
        createdAt: DateTime.utc(2026, 11, 23),
        lines: [
          SaleLine(
            productId: productId,
            name: 'Return tea',
            unitPriceCents: 500,
            quantity: 1,
            productVersion: 2,
            modifiers: const [
              SelectedModifier(
                groupId: 'size',
                groupName: 'Size',
                optionId: 'regular',
                name: 'Regular',
                priceDeltaCents: 0,
              ),
            ],
          ),
          SaleLine(
            productId: productId,
            name: 'Return tea',
            unitPriceCents: 500,
            quantity: 1,
            productVersion: 2,
            modifiers: const [
              SelectedModifier(
                groupId: 'size',
                groupName: 'Size',
                optionId: 'large',
                name: 'Large',
                priceDeltaCents: 500,
              ),
            ],
          ),
        ],
        tenderedCents: 1500,
        shiftId: 'return-modifier-shift',
      );
      expect((await _postSale(app, sale, adminToken)).statusCode, 201);
      final payment = PaymentRecord(
        id: 'return-modifier-payment',
        saleId: sale.id,
        provider: 'cash',
        method: 'cash',
        status: PaymentStatus.captured,
        amountCents: sale.totalCents,
        tenderedCents: sale.tenderedCents,
        changeCents: sale.changeCents,
        createdAt: sale.createdAt,
        updatedAt: sale.createdAt,
      );
      expect(
        (await _postJson(
          app,
          '/api/v1/sales/${sale.id}/payments',
          payment.toJson(),
          token: adminToken,
        )).statusCode,
        201,
      );
      final returnRequest = {
        'id': 'return-large-option',
        'saleId': sale.id,
        'reason': 'Large size returned',
        'lines': [
          {
            'productId': productId,
            'lineIndex': 1,
            'quantity': 1,
            'restock': true,
          },
        ],
      };
      final returned = await _postJson(
        app,
        '/api/v1/returns',
        returnRequest,
        token: adminToken,
      );
      expect(returned.statusCode, 201);
      expect(
        (jsonDecode(await returned.readAsString()) as Map)['refundCents'],
        1000,
      );
      final closedShift = await _postJson(
        app,
        '/api/v1/shifts/return-modifier-shift/close',
        {'countedCashCents': 1500},
        token: adminToken,
      );
      expect(closedShift.statusCode, 200);
      expect(
        (await _postJson(
          app,
          '/api/v1/returns',
          returnRequest,
          token: adminToken,
        )).statusCode,
        200,
      );
      final savedPayment = await _get(
        app,
        '/api/v1/sales/${sale.id}/payment',
        token: adminToken,
      );
      final paymentRecord = PaymentRecord.fromJson(
        (jsonDecode(await savedPayment.readAsString()) as Map)
            .cast<String, Object?>(),
      );
      expect(paymentRecord.status, PaymentStatus.partiallyRefunded);
      expect(paymentRecord.refundedCents, 1000);
      final inventoryResponse = await _get(
        app,
        '/api/v1/inventory',
        token: adminToken,
      );
      final items =
          (jsonDecode(await inventoryResponse.readAsString()) as Map)['items']
              as List;
      expect((items.single as Map)['onHand'], 1);
    },
  );

  test(
    'records inventory movements idempotently and flags low stock',
    () async {
      final productResponse = await _postJson(app, '/api/v1/products', {
        'name': 'Inventory coffee',
        'category': 'Coffee',
        'sku': 'INV-COF-01',
        'unitPriceCents': 2500,
      }, token: adminToken);
      final product = jsonDecode(await productResponse.readAsString()) as Map;
      final productId = product['id'] as String;

      final received = {
        'id': 'movement-receive-1',
        'productId': productId,
        'type': 'receive',
        'quantity': 8,
        'destinationLocation': 'Main',
        'note': 'Opening delivery',
      };
      expect(
        (await _postJson(
          app,
          '/api/v1/inventory/movements',
          received,
          token: adminToken,
        )).statusCode,
        201,
      );
      expect(
        (await _postJson(
          app,
          '/api/v1/inventory/movements',
          received,
          token: adminToken,
        )).statusCode,
        200,
      );
      expect(
        (await _postJson(app, '/api/v1/inventory/movements', {
          ...received,
          'quantity': 9,
        }, token: adminToken)).statusCode,
        409,
      );

      final threshold = await _putJson(
        app,
        '/api/v1/inventory/items/$productId/threshold',
        {'lowStockThreshold': 5},
        token: adminToken,
      );
      expect(threshold.statusCode, 200);
      expect(
        (await _postJson(app, '/api/v1/inventory/movements', {
          'id': 'movement-transfer-too-large',
          'productId': productId,
          'type': 'transfer',
          'quantity': 9,
          'sourceLocation': 'Main',
          'destinationLocation': 'Front shelf',
        }, token: adminToken)).statusCode,
        409,
      );
      expect(
        (await _postJson(app, '/api/v1/inventory/movements', {
          'id': 'movement-transfer-1',
          'productId': productId,
          'type': 'transfer',
          'quantity': 3,
          'sourceLocation': 'Main',
          'destinationLocation': 'Front shelf',
        }, token: adminToken)).statusCode,
        201,
      );
      expect(
        (await _postJson(app, '/api/v1/inventory/movements', {
          'id': 'movement-adjustment-1',
          'productId': productId,
          'type': 'adjustment',
          'quantity': -1,
          'destinationLocation': 'Front shelf',
        }, token: adminToken)).statusCode,
        201,
      );

      final sale = Sale.cash(
        id: 'inventory-sale-1',
        createdAt: DateTime.utc(2026, 11, 23),
        lines: [
          SaleLine(
            productId: productId,
            name: 'Inventory coffee',
            unitPriceCents: 2500,
            quantity: 2,
          ),
        ],
        tenderedCents: 5000,
      );
      expect((await _postSale(app, sale, adminToken)).statusCode, 201);
      expect((await _postSale(app, sale, adminToken)).statusCode, 200);

      final inventoryResponse = await _get(
        app,
        '/api/v1/inventory',
        token: adminToken,
      );
      final inventory =
          jsonDecode(await inventoryResponse.readAsString()) as Map;
      final items = inventory['items'] as List;
      final item =
          items.singleWhere((entry) => entry['productId'] == productId) as Map;
      expect(item['onHand'], 5);
      expect(item['lowStockThreshold'], 5);
      expect(item['isLowStock'], isTrue);
      final locations = item['locations'] as List;
      expect(
        locations.map(
          (location) => [location['location'], location['quantity']],
        ),
        containsAll([
          ['Main', 3],
          ['Front shelf', 2],
        ]),
      );
      expect(inventory['lowStockCount'], 1);
    },
  );

  test(
    'opens, reconciles and refreshes drawer cash after offline sync',
    () async {
      final shiftId = 'drawer-shift-1';
      final opened = await _postJson(app, '/api/v1/shifts', {
        'id': shiftId,
        'openingFloatCents': 10000,
      }, token: adminToken);
      expect(opened.statusCode, 201);
      expect(
        (await _postJson(app, '/api/v1/shifts', {
          'id': shiftId,
          'openingFloatCents': 10000,
        }, token: adminToken)).statusCode,
        200,
      );
      expect(
        (await _postJson(app, '/api/v1/shifts', {
          'id': 'second-shift',
          'openingFloatCents': 0,
        }, token: adminToken)).statusCode,
        409,
      );

      final paidIn = await _postJson(
        app,
        '/api/v1/shifts/$shiftId/cash-movements',
        {'id': 'paid-in-1', 'type': 'paid_in', 'amountCents': 2000},
        token: adminToken,
      );
      expect(paidIn.statusCode, 201);
      expect(
        (await _postJson(app, '/api/v1/shifts/$shiftId/cash-movements', {
          'id': 'paid-in-1',
          'type': 'paid_in',
          'amountCents': 2000,
        }, token: adminToken)).statusCode,
        200,
      );
      expect(
        (await _postJson(app, '/api/v1/shifts/$shiftId/cash-movements', {
          'id': 'paid-in-1',
          'type': 'paid_in',
          'amountCents': 2500,
        }, token: adminToken)).statusCode,
        409,
      );
      expect(
        (await _postJson(app, '/api/v1/shifts/$shiftId/cash-movements', {
          'id': 'paid-out-1',
          'type': 'paid_out',
          'amountCents': 500,
        }, token: adminToken)).statusCode,
        201,
      );

      final productResponse = await _postJson(app, '/api/v1/products', {
        'name': 'Shift item',
        'category': 'General',
        'unitPriceCents': 2500,
      }, token: adminToken);
      final product = jsonDecode(await productResponse.readAsString()) as Map;
      final sale = Sale.cash(
        id: 'shift-sale-1',
        createdAt: DateTime.utc(2026, 11, 23),
        lines: [
          SaleLine(
            productId: product['id'] as String,
            name: 'Shift item',
            unitPriceCents: 2500,
            quantity: 1,
          ),
        ],
        tenderedCents: 3000,
        shiftId: shiftId,
      );
      expect((await _postSale(app, sale, adminToken)).statusCode, 201);

      final close = await _postJson(app, '/api/v1/shifts/$shiftId/close', {
        'countedCashCents': 13750,
      }, token: adminToken);
      expect(close.statusCode, 200);
      final closedShift =
          (jsonDecode(await close.readAsString()) as Map)['shift'] as Map;
      expect(closedShift['expectedCashCents'], 14000);
      expect(closedShift['varianceCents'], -250);
      expect(closedShift['isOpen'], isFalse);
      expect(
        (await _postJson(app, '/api/v1/shifts/$shiftId/close', {
          'countedCashCents': 13750,
        }, token: adminToken)).statusCode,
        200,
      );
      expect(
        (await _postJson(app, '/api/v1/shifts/$shiftId/close', {
          'countedCashCents': 13700,
        }, token: adminToken)).statusCode,
        409,
      );

      final repricedProduct = await _putJson(
        app,
        '/api/v1/products/${product['id']}',
        {...product, 'unitPriceCents': 1000},
        token: adminToken,
      );
      expect(repricedProduct.statusCode, 200);
      final repriced = jsonDecode(await repricedProduct.readAsString()) as Map;
      final lateSale = Sale.cash(
        id: 'shift-sale-late',
        createdAt: DateTime.utc(2026, 11, 23),
        lines: [
          SaleLine(
            productId: product['id'] as String,
            name: 'Shift item',
            unitPriceCents: 1000,
            quantity: 1,
            productVersion: repriced['version'] as int,
          ),
        ],
        tenderedCents: 1000,
        shiftId: shiftId,
      );
      expect((await _postSale(app, lateSale, adminToken)).statusCode, 201);
      final refreshed = await _get(
        app,
        '/api/v1/shifts/$shiftId',
        token: adminToken,
      );
      final reconciled =
          (jsonDecode(await refreshed.readAsString()) as Map)['shift'] as Map;
      expect(reconciled['expectedCashCents'], 15000);
      expect(reconciled['varianceCents'], -1250);
    },
  );

  test('adds shift linkage without dropping existing hub sales', () {
    final oldDatabase = sqlite3.openInMemory();
    oldDatabase.execute('''
      CREATE TABLE sales (
        id TEXT PRIMARY KEY,
        created_at TEXT NOT NULL,
        total_cents INTEGER NOT NULL,
        payload TEXT NOT NULL
      )
    ''');
    oldDatabase.execute(
      'INSERT INTO sales (id, created_at, total_cents, payload) VALUES (?, ?, ?, ?)',
      ['existing-sale', '2026-01-01T00:00:00.000Z', 100, '{}'],
    );

    final migratedStore = HubStore(oldDatabase);
    final columns = oldDatabase.select('PRAGMA table_info(sales)');
    expect(columns.any((row) => row['name'] == 'shift_id'), isTrue);
    expect(
      oldDatabase.select('SELECT id FROM sales').single['id'],
      'existing-sale',
    );
    migratedStore.close();
  });

  test('rejects reuse of a sale ID with different contents', () async {
    final first = _sampleSale();
    final second = Sale.cash(
      id: first.id,
      createdAt: first.createdAt,
      lines: const [
        SaleLine(
          productId: 'bread',
          name: 'Pan de sal',
          unitPriceCents: 1_500,
          quantity: 1,
        ),
      ],
      tenderedCents: 2_000,
    );

    expect((await _postSale(app, first, adminToken)).statusCode, 201);
    expect((await _postSale(app, second, adminToken)).statusCode, 409);
  });

  test(
    'rejects malformed sale data after authenticating the request',
    () async {
      final response = await app(
        Request(
          'POST',
          Uri.parse('http://localhost/api/v1/sales'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $adminToken',
          },
          body: '{"id":"broken"}',
        ),
      );
      expect(response.statusCode, 400);
    },
  );

  test(
    'supports sign-in, staff creation, and server-enforced role permissions',
    () async {
      final createCashier = await _postJson(app, '/api/v1/users', {
        'name': 'Taylor Cashier',
        'email': 'cashier@example.test',
        'password': 'cashier-password-123',
        'role': 'cashier',
      }, token: adminToken);
      expect(createCashier.statusCode, 201);

      final login = await _postJson(app, '/api/v1/auth/login', {
        'email': 'cashier@example.test',
        'password': 'cashier-password-123',
      });
      expect(login.statusCode, 200);
      final cashierToken =
          (jsonDecode(await login.readAsString()) as Map)['token'] as String;

      final product = await _postJson(app, '/api/v1/products', {
        'name': 'Bottled tea',
        'category': 'Drinks',
        'unitPriceCents': 5000,
      }, token: cashierToken);
      expect(product.statusCode, 403);

      final staff = await _get(app, '/api/v1/users', token: cashierToken);
      expect(staff.statusCode, 403);

      final inventoryView = await _get(
        app,
        '/api/v1/inventory',
        token: cashierToken,
      );
      expect(inventoryView.statusCode, 200);
      final inventoryEdit = await _postJson(
        app,
        '/api/v1/inventory/movements',
        {},
        token: cashierToken,
      );
      expect(inventoryEdit.statusCode, 403);

      final sale = await _postSale(app, _sampleSale(), cashierToken);
      expect(sale.statusCode, 201);
      final discounted = Sale.cash(
        id: 'cashier-discount-sale',
        createdAt: DateTime.utc(2026, 11, 23),
        lines: const [
          SaleLine(
            productId: 'coffee',
            name: 'Coffee',
            unitPriceCents: 1000,
            quantity: 1,
          ),
        ],
        tenderedCents: 900,
        discountCents: 100,
        discountReason: 'Courtesy',
      );
      expect((await _postSale(app, discounted, cashierToken)).statusCode, 403);

      final logout = await app(
        Request(
          'POST',
          Uri.parse('http://localhost/api/v1/auth/logout'),
          headers: {'authorization': 'Bearer $cashierToken'},
        ),
      );
      expect(logout.statusCode, 204);
      expect(
        (await _get(app, '/api/v1/auth/me', token: cashierToken)).statusCode,
        401,
      );
    },
  );

  test(
    'managers can maintain catalog; catalog carries barcode and version',
    () async {
      final createManager = await _postJson(app, '/api/v1/users', {
        'name': 'Store Manager',
        'email': 'manager@example.test',
        'password': 'manager-password-123',
        'role': 'manager',
      }, token: adminToken);
      expect(createManager.statusCode, 201);
      final login = await _postJson(app, '/api/v1/auth/login', {
        'email': 'manager@example.test',
        'password': 'manager-password-123',
      });
      final managerToken =
          (jsonDecode(await login.readAsString()) as Map)['token'] as String;

      final beforeResponse = await _get(
        app,
        '/api/v1/products',
        token: managerToken,
      );
      final before = jsonDecode(await beforeResponse.readAsString()) as Map;
      final createProduct = await _postJson(app, '/api/v1/products', {
        'name': 'House tea',
        'category': 'Drinks',
        'sku': 'TEA-01',
        'barcode': '4800000000012',
        'unitPriceCents': 4250,
      }, token: managerToken);
      expect(createProduct.statusCode, 201);
      final created =
          jsonDecode(await createProduct.readAsString())
              as Map<String, Object?>;
      expect(created['barcode'], '4800000000012');

      final afterResponse = await _get(
        app,
        '/api/v1/products',
        token: managerToken,
      );
      final after = jsonDecode(await afterResponse.readAsString()) as Map;
      expect(after['version'], greaterThan(before['version'] as int));
      expect(
        (after['products'] as List).any(
          (product) => product['id'] == created['id'],
        ),
        isTrue,
      );

      final archived = await _putJson(
        app,
        '/api/v1/products/${created['id']}',
        {...created, 'isActive': false},
        token: managerToken,
      );
      expect(archived.statusCode, 200);
      final currentResponse = await _get(
        app,
        '/api/v1/products',
        token: managerToken,
      );
      final current = jsonDecode(await currentResponse.readAsString()) as Map;
      expect(
        (current['products'] as List).any(
          (product) => product['id'] == created['id'],
        ),
        isFalse,
      );
    },
  );

  test(
    'manages shared categories and blocks unsafe archive operations',
    () async {
      final createdCategory = await _postJson(app, '/api/v1/categories', {
        'name': 'Pastries',
      }, token: adminToken);
      expect(createdCategory.statusCode, 201);
      final category =
          jsonDecode(await createdCategory.readAsString())
              as Map<String, Object?>;
      expect(category['name'], 'Pastries');
      expect(category['isActive'], isTrue);

      final duplicate = await _postJson(app, '/api/v1/categories', {
        'name': ' pastries ',
      }, token: adminToken);
      expect(duplicate.statusCode, 409);

      final productResponse = await _postJson(app, '/api/v1/products', {
        'name': 'Butter croissant',
        'category': 'pastries',
        'unitPriceCents': 8500,
      }, token: adminToken);
      expect(productResponse.statusCode, 201);
      final product =
          jsonDecode(await productResponse.readAsString())
              as Map<String, Object?>;
      expect(product['category'], 'Pastries');

      final archiveWhileInUse = await _putJson(
        app,
        '/api/v1/categories/${category['id']}',
        {'isActive': false, 'expectedVersion': 1},
        token: adminToken,
      );
      expect(archiveWhileInUse.statusCode, 409);
      expect(
        (jsonDecode(await archiveWhileInUse.readAsString()) as Map)['error'],
        'category_in_use',
      );

      expect(
        (await _putJson(app, '/api/v1/products/${product['id']}', {
          ...product,
          'isActive': false,
        }, token: adminToken)).statusCode,
        200,
      );
      final archived = await _putJson(
        app,
        '/api/v1/categories/${category['id']}',
        {'isActive': false, 'expectedVersion': 1},
        token: adminToken,
      );
      expect(archived.statusCode, 200);
      expect(
        (jsonDecode(await archived.readAsString()) as Map)['isActive'],
        isFalse,
      );

      final staleRestore = await _putJson(
        app,
        '/api/v1/categories/${category['id']}',
        {'isActive': true, 'expectedVersion': 1},
        token: adminToken,
      );
      expect(staleRestore.statusCode, 409);
      expect(
        (jsonDecode(await staleRestore.readAsString()) as Map)['error'],
        'category_version_conflict',
      );

      final archivedAssignment = await _postJson(app, '/api/v1/products', {
        'name': 'Fruit tart',
        'category': 'Pastries',
        'unitPriceCents': 5000,
      }, token: adminToken);
      expect(archivedAssignment.statusCode, 409);

      final restored = await _putJson(
        app,
        '/api/v1/categories/${category['id']}',
        {'isActive': true, 'expectedVersion': 2},
        token: adminToken,
      );
      expect(restored.statusCode, 200);
      final categoriesResponse = await _get(
        app,
        '/api/v1/categories',
        token: adminToken,
      );
      final categories =
          (jsonDecode(await categoriesResponse.readAsString())
                  as Map)['categories']
              as List;
      expect(categories.single['isActive'], isTrue);
    },
  );

  test('records and restricts access to sensitive audit events', () async {
    final product = await _postJson(app, '/api/v1/products', {
      'name': 'Audit tea',
      'category': 'Drinks',
      'unitPriceCents': 4000,
    }, token: adminToken);
    expect(product.statusCode, 201);

    final adminLogin = await _postJson(app, '/api/v1/auth/login', {
      'email': 'admin@example.test',
      'password': 'correct-horse-battery',
    });
    expect(adminLogin.statusCode, 200);

    final auditResponse = await _get(app, '/api/v1/audit', token: adminToken);
    final audit = jsonDecode(await auditResponse.readAsString()) as Map;
    final events = audit['events'] as List;
    expect(events.any((event) => event['eventType'] == 'store.setup'), isTrue);
    expect(
      events.any((event) => event['eventType'] == 'catalog.product_created'),
      isTrue,
    );
    expect(events.any((event) => event['eventType'] == 'auth.sign_in'), isTrue);

    final cashierResponse = await _postJson(app, '/api/v1/users', {
      'name': 'Audit Cashier',
      'email': 'audit-cashier@example.test',
      'password': 'cashier-password-123',
      'role': 'cashier',
    }, token: adminToken);
    final cashierLogin = await _postJson(app, '/api/v1/auth/login', {
      'email': 'audit-cashier@example.test',
      'password': 'cashier-password-123',
    });
    expect(cashierResponse.statusCode, 201);
    final cashierToken =
        (jsonDecode(await cashierLogin.readAsString()) as Map)['token']
            as String;
    expect(
      (await _get(app, '/api/v1/audit', token: cashierToken)).statusCode,
      403,
    );
  });

  test(
    'applies catalog edits once and validates historical modifier snapshots on sales',
    () async {
      final createdResponse = await _postJson(app, '/api/v1/products', {
        'name': 'House tea',
        'category': 'Drinks',
        'unitPriceCents': 4250,
      }, token: adminToken);
      expect(createdResponse.statusCode, 201);
      final created =
          jsonDecode(await createdResponse.readAsString())
              as Map<String, Object?>;
      final group = ModifierGroup(
        id: 'size',
        name: 'Size',
        minimumSelections: 1,
        maximumSelections: 1,
        options: const [
          ModifierOption(id: 'regular', name: 'Regular'),
          ModifierOption(id: 'large', name: 'Large', priceDeltaCents: 750),
        ],
      );
      final editedProduct = {
        ...created,
        'modifierGroups': [group.toJson()],
      };
      final operation = {
        'operationId': 'modifier-edit-1',
        'expectedVersion': 1,
        'product': editedProduct,
      };
      final applied = await _postJson(
        app,
        '/api/v1/catalog/operations',
        operation,
        token: adminToken,
      );
      expect(applied.statusCode, 200);
      final appliedBody = jsonDecode(await applied.readAsString()) as Map;
      expect(appliedBody['product']['version'], 2);
      expect(appliedBody['product']['modifierGroups'], [group.toJson()]);

      final repeated = await _postJson(
        app,
        '/api/v1/catalog/operations',
        operation,
        token: adminToken,
      );
      expect(repeated.statusCode, 200);
      expect(jsonDecode(await repeated.readAsString()), appliedBody);

      final stale = await _postJson(app, '/api/v1/catalog/operations', {
        'operationId': 'modifier-edit-stale',
        'expectedVersion': 1,
        'product': {...editedProduct, 'name': 'Stale tea'},
      }, token: adminToken);
      expect(stale.statusCode, 409);
      expect(
        jsonDecode(await stale.readAsString())['error'],
        'catalog_version_conflict',
      );

      final sale = Sale.cash(
        id: 'modifier-sale',
        createdAt: DateTime.utc(2026, 11, 23),
        lines: [
          SaleLine(
            productId: created['id']! as String,
            name: 'House tea',
            unitPriceCents: 4250,
            quantity: 1,
            productVersion: 2,
            modifiers: const [
              SelectedModifier(
                groupId: 'size',
                groupName: 'Size',
                optionId: 'large',
                name: 'Large',
                priceDeltaCents: 750,
              ),
            ],
          ),
        ],
        tenderedCents: 5000,
      );
      expect((await _postSale(app, sale, adminToken)).statusCode, 201);

      final tampered = Sale.cash(
        id: 'modifier-sale-tampered',
        createdAt: DateTime.utc(2026, 11, 23),
        lines: [
          SaleLine(
            productId: created['id']! as String,
            name: 'House tea',
            unitPriceCents: 4250,
            quantity: 1,
            productVersion: 2,
            modifiers: const [
              SelectedModifier(
                groupId: 'size',
                groupName: 'Size',
                optionId: 'large',
                name: 'Large',
                priceDeltaCents: 1,
              ),
            ],
          ),
        ],
        tenderedCents: 5000,
      );
      final rejected = await _postSale(app, tampered, adminToken);
      expect(rejected.statusCode, 409);
      expect(
        jsonDecode(await rejected.readAsString())['error'],
        'catalog_snapshot_invalid',
      );
    },
  );

  test(
    'locks repeated incorrect sign-ins and returns a generic error',
    () async {
      Response? last;
      for (var index = 0; index < 5; index++) {
        last = await _postJson(app, '/api/v1/auth/login', {
          'email': 'admin@example.test',
          'password': 'incorrect-password',
        });
      }
      expect(last!.statusCode, 429);
      expect(await last.readAsString(), contains('Try signing in again later'));
    },
  );

  test(
    'allows browser sync with authorization from a configured origin',
    () async {
      final response = await app(
        Request(
          'OPTIONS',
          Uri.parse('http://localhost/api/v1/sales'),
          headers: const {
            'origin': 'http://127.0.0.1:7357',
            'access-control-request-method': 'POST',
            'access-control-request-headers': 'content-type, authorization',
          },
        ),
      );
      expect(response.statusCode, 204);
      expect(
        response.headers['access-control-allow-origin'],
        'http://127.0.0.1:7357',
      );
      expect(
        response.headers['access-control-allow-headers'],
        'content-type, authorization',
      );
    },
  );

  test('rejects browser requests from unconfigured origins', () async {
    final response = await app(
      Request(
        'POST',
        Uri.parse('http://localhost/api/v1/sales'),
        headers: const {
          'origin': 'https://untrusted.example',
          'content-type': 'application/json',
        },
        body: '{}',
      ),
    );
    expect(response.statusCode, 403);
  });
}

Future<Response> _get(Handler app, String path, {String? token}) async =>
    await app(
      Request(
        'GET',
        Uri.parse('http://localhost$path'),
        headers: {if (token != null) 'authorization': 'Bearer $token'},
      ),
    );

Future<Response> _postJson(
  Handler app,
  String path,
  Object body, {
  String? token,
}) async => await app(
  Request(
    'POST',
    Uri.parse('http://localhost$path'),
    headers: {
      'content-type': 'application/json',
      if (token != null) 'authorization': 'Bearer $token',
    },
    body: jsonEncode(body),
  ),
);

Future<Response> _putJson(
  Handler app,
  String path,
  Object body, {
  required String token,
}) async => await app(
  Request(
    'PUT',
    Uri.parse('http://localhost$path'),
    headers: {
      'content-type': 'application/json',
      'authorization': 'Bearer $token',
    },
    body: jsonEncode(body),
  ),
);

Future<Response> _postSale(Handler app, Sale sale, String token) =>
    _postJson(app, '/api/v1/sales', sale.toJson(), token: token);

Sale _sampleSale() => Sale.cash(
  id: 'sale-${DateTime.now().microsecondsSinceEpoch}',
  createdAt: DateTime.utc(2026, 11, 23),
  lines: const [
    SaleLine(
      productId: 'coffee',
      name: 'Brewed coffee',
      unitPriceCents: 8_500,
      quantity: 1,
    ),
  ],
  tenderedCents: 10_000,
);
