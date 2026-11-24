import 'dart:convert';
import 'dart:io' show Platform;

import 'package:hub/hub_store.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

Handler createApp(HubStore store, {Set<String>? allowedOrigins}) {
  final router = Router()
    ..get('/health', (_) => _jsonResponse(200, {'status': 'ok'}))
    ..get('/health/ready', store.readiness)
    ..get('/api/v1/setup/status', (_) => store.setupStatus())
    ..post('/api/v1/setup', store.createStoreAndAdmin)
    ..post('/api/v1/auth/login', store.signIn)
    ..post('/api/v1/auth/logout', store.signOut)
    ..get('/api/v1/auth/me', store.currentUser)
    ..post('/api/v1/registers', store.enrollRegister)
    ..get('/api/v1/sync/events', store.listSyncEvents)
    ..post('/api/v1/sync/ack', store.acknowledgeSyncCursor)
    ..get('/api/v1/tax', store.getTaxSettings)
    ..put('/api/v1/tax', store.setTaxSettings)
    ..get('/api/v1/loyalty/settings', store.getLoyaltySettings)
    ..put('/api/v1/loyalty/settings', store.setLoyaltySettings)
    ..get('/api/v1/categories', store.listCategories)
    ..post('/api/v1/categories', store.createCategory)
    ..put(
      '/api/v1/categories/<id>',
      (request, id) => store.setCategoryActive(request, id),
    )
    ..get('/api/v1/suppliers', store.listSuppliers)
    ..post('/api/v1/suppliers', store.createSupplier)
    ..put(
      '/api/v1/suppliers/<id>',
      (request, id) => store.updateSupplier(request, id),
    )
    ..put(
      '/api/v1/suppliers/<id>/active',
      (request, id) => store.setSupplierActive(request, id),
    )
    ..get('/api/v1/purchase-orders', store.listPurchaseOrders)
    ..post('/api/v1/purchase-orders', store.createPurchaseOrder)
    ..post(
      '/api/v1/purchase-orders/<id>/place',
      (request, id) => store.placePurchaseOrder(request, id),
    )
    ..post(
      '/api/v1/purchase-orders/<id>/cancel',
      (request, id) => store.cancelPurchaseOrder(request, id),
    )
    ..post(
      '/api/v1/purchase-orders/<id>/receipts',
      (request, id) => store.receivePurchaseOrder(request, id),
    )
    ..get('/api/v1/customers', store.listCustomers)
    ..post('/api/v1/customers', store.createCustomer)
    ..put(
      '/api/v1/customers/<id>',
      (request, id) => store.updateCustomer(request, id),
    )
    ..get('/api/v1/products', store.listProducts)
    ..post('/api/v1/products', store.createProduct)
    ..post('/api/v1/catalog/operations', store.applyCatalogOperation)
    ..put(
      '/api/v1/products/<id>',
      (Request request, String id) => store.updateProduct(request, id),
    )
    ..get('/api/v1/users', store.listUsers)
    ..post('/api/v1/users', store.createUser)
    ..get('/api/v1/audit', store.listAuditEvents)
    ..get('/api/v1/operations/health', store.operationalHealth)
    ..post('/api/v1/sales', store.acceptSale)
    ..get('/api/v1/sales', store.listSales)
    ..get('/api/v1/reports/sales', store.salesReport)
    ..post(
      '/api/v1/sales/<id>/void',
      (request, id) => store.voidSale(request, id),
    )
    ..post(
      '/api/v1/sales/<id>/payments',
      (request, id) => store.recordPayment(request, id),
    )
    ..get(
      '/api/v1/sales/<id>/payment',
      (request, id) => store.getPayment(request, id),
    )
    ..post('/api/v1/returns', store.createReturn)
    ..get(
      '/api/v1/sales/<id>',
      (Request request, String id) => store.getSale(request, id),
    )
    ..get('/api/v1/inventory', store.listInventory)
    ..get('/api/v1/inventory/movements', store.listStockMovements)
    ..post('/api/v1/inventory/movements', store.createStockMovement)
    ..put(
      '/api/v1/inventory/items/<id>/threshold',
      (Request request, String id) => store.setLowStockThreshold(request, id),
    )
    ..get('/api/v1/shifts/current', store.currentCashShift)
    ..post('/api/v1/shifts', store.openCashShift)
    ..get(
      '/api/v1/shifts/<id>',
      (Request request, String id) => store.getCashShift(request, id),
    )
    ..post(
      '/api/v1/shifts/<id>/cash-movements',
      (Request request, String id) => store.recordCashMovement(request, id),
    )
    ..post(
      '/api/v1/shifts/<id>/close',
      (Request request, String id) => store.closeCashShift(request, id),
    );
  return Pipeline()
      .addMiddleware(_securityHeadersMiddleware)
      .addMiddleware(_corsMiddleware(allowedOrigins ?? _configuredOrigins()))
      .addHandler(router.call);
}

Handler _securityHeadersMiddleware(Handler innerHandler) => (request) async {
  final response = await innerHandler(request);
  return response.change(
    headers: const {
      'cache-control': 'no-store',
      'content-security-policy':
          "default-src 'none'; frame-ancestors 'none'; base-uri 'none'",
      'referrer-policy': 'no-referrer',
      'x-content-type-options': 'nosniff',
      'x-frame-options': 'DENY',
    },
  );
};

Set<String> _configuredOrigins() {
  const defaults = {
    'http://localhost:5000',
    'http://127.0.0.1:5000',
    'http://localhost:7357',
    'http://127.0.0.1:7357',
  };
  final configured = Platform.environment['POS_ALLOWED_ORIGINS'] ?? '';
  return configured.isEmpty
      ? defaults
      : configured.split(',').map((origin) => origin.trim()).toSet();
}

Middleware _corsMiddleware(Set<String> allowedOrigins) => (innerHandler) {
  return (request) async {
    final origin = request.headers['origin'];
    if (origin != null && !allowedOrigins.contains(origin)) {
      return Response.forbidden('Origin is not allowed.');
    }
    if (request.method == 'OPTIONS') {
      if (origin == null) return Response.forbidden('Origin is required.');
      return Response(
        204,
        headers: {
          'access-control-allow-origin': origin,
          'access-control-allow-methods': 'GET, POST, PUT, OPTIONS',
          'access-control-allow-headers': 'content-type, authorization',
          'access-control-max-age': '600',
          'vary': 'origin',
        },
      );
    }

    final response = await innerHandler(request);
    if (origin == null) return response;
    if (!allowedOrigins.contains(origin)) {
      return Response.forbidden('Origin is not allowed.');
    }
    return response.change(
      headers: {'access-control-allow-origin': origin, 'vary': 'origin'},
    );
  };
};

Response _jsonResponse(int statusCode, Object body) => Response(
  statusCode,
  body: jsonEncode(body),
  headers: const {'content-type': 'application/json; charset=utf-8'},
);
