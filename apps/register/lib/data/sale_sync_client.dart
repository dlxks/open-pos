import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pos_domain/pos_domain.dart';

class SaleSyncClient {
  SaleSyncClient({required this.baseUrl, http.Client? client, String? token})
    : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  String? token;
  String registerId = 'main';
  String registerName = 'Main register';

  String get _root => baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  Map<String, String> get _headers => {
    'content-type': 'application/json',
    if (token != null) 'authorization': 'Bearer $token',
  };

  Future<bool> needsInitialSetup() async {
    final response = await _client
        .get(Uri.parse('$_root/api/v1/setup/status'))
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 200) throw _hubError(response.statusCode, body);
    return body['needsSetup'] as bool;
  }

  Future<HubSession> setupStore({
    required String storeName,
    required String name,
    required String email,
    required String password,
  }) => _postSession('/api/v1/setup', {
    'storeName': storeName,
    'name': name,
    'email': email,
    'password': password,
  });

  Future<HubSession> signIn({
    required String email,
    required String password,
  }) => _postSession('/api/v1/auth/login', {
    'email': email,
    'password': password,
  });

  Future<HubSession> currentSession() async {
    final response = await _client
        .get(Uri.parse('$_root/api/v1/auth/me'), headers: _headers)
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 200) throw _hubError(response.statusCode, body);
    return HubSession(
      token: token ?? '',
      user: PosUser.fromJson(body['user'] as Map<String, Object?>),
      store: PosStore.fromJson(body['store'] as Map<String, Object?>),
    );
  }

  Future<void> signOut() async {
    try {
      await _client
          .post(Uri.parse('$_root/api/v1/auth/logout'), headers: _headers)
          .timeout(const Duration(seconds: 3));
    } on Exception {
      // The local vault is still cleared so this device signs out offline too.
    } finally {
      token = null;
    }
  }

  Future<bool> enrollRegister({
    required String id,
    required String name,
  }) async {
    registerId = id;
    registerName = name;
    try {
      final response = await _client
          .post(
            Uri.parse('$_root/api/v1/registers'),
            headers: _headers,
            body: jsonEncode({'id': id, 'name': name}),
          )
          .timeout(const Duration(seconds: 5));
      final body = _decodeResponse(response);
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw _hubError(response.statusCode, body);
      }
      return true;
    } on Exception {
      return false;
    }
  }

  Future<SyncEventPage> fetchSyncEvents({
    required int after,
    int limit = 100,
  }) async {
    final uri = Uri.parse('$_root/api/v1/sync/events').replace(
      queryParameters: {
        'registerId': registerId,
        'after': '$after',
        'limit': '$limit',
      },
    );
    final response = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 200) throw _hubError(response.statusCode, body);
    return SyncEventPage(
      events: (body['events'] as List<Object?>)
          .map(
            (event) => (event! as Map).map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          )
          .toList(growable: false),
      nextCursor: body['nextCursor'] as int,
      hasMore: body['hasMore'] as bool? ?? false,
    );
  }

  Future<void> acknowledgeSyncCursor(int cursor) async {
    final response = await _client
        .post(
          Uri.parse('$_root/api/v1/sync/ack'),
          headers: _headers,
          body: jsonEncode({'registerId': registerId, 'cursor': cursor}),
        )
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 200) throw _hubError(response.statusCode, body);
  }

  Future<TaxConfig> fetchTaxConfig() async {
    final response = await _client
        .get(Uri.parse('$_root/api/v1/tax'), headers: _headers)
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 200) throw _hubError(response.statusCode, body);
    return TaxConfig.fromJson(body);
  }

  Future<TaxConfig> saveTaxConfig(TaxConfig tax) async {
    final response = await _client
        .put(
          Uri.parse('$_root/api/v1/tax'),
          headers: _headers,
          body: jsonEncode(tax.toJson()),
        )
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 200) throw _hubError(response.statusCode, body);
    return TaxConfig.fromJson(body);
  }

  Future<LoyaltyConfig> fetchLoyaltyConfig() async {
    final response = await _client
        .get(Uri.parse('$_root/api/v1/loyalty/settings'), headers: _headers)
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 200) throw _hubError(response.statusCode, body);
    return LoyaltyConfig.fromJson(body);
  }

  Future<LoyaltyConfig> saveLoyaltyConfig(LoyaltyConfig loyalty) async {
    final response = await _client
        .put(
          Uri.parse('$_root/api/v1/loyalty/settings'),
          headers: _headers,
          body: jsonEncode(loyalty.toJson()),
        )
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 200) throw _hubError(response.statusCode, body);
    return LoyaltyConfig.fromJson(body);
  }

  Future<List<Customer>> fetchCustomers() async {
    final response = await _client
        .get(Uri.parse('$_root/api/v1/customers'), headers: _headers)
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 200) throw _hubError(response.statusCode, body);
    return (body['customers'] as List<Object?>)
        .map((row) => Customer.fromJson(row! as Map<String, Object?>))
        .toList(growable: false);
  }

  Future<Customer> createCustomer({
    required String name,
    String? phone,
    String? email,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_root/api/v1/customers'),
          headers: _headers,
          body: jsonEncode({'name': name, 'phone': ?phone, 'email': ?email}),
        )
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 201) throw _hubError(response.statusCode, body);
    return Customer.fromJson(body);
  }

  Future<List<Supplier>> fetchSuppliers() async {
    final response = await _client
        .get(Uri.parse('$_root/api/v1/suppliers'), headers: _headers)
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 200) throw _hubError(response.statusCode, body);
    return (body['suppliers'] as List<Object?>)
        .map((row) => Supplier.fromJson(_jsonObject(row)))
        .toList(growable: false);
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
    final response = await _client
        .post(
          Uri.parse('$_root/api/v1/suppliers'),
          headers: _headers,
          body: jsonEncode({
            'id': id,
            'name': name,
            'contactName': ?contactName,
            'email': ?email,
            'phone': ?phone,
            'address': ?address,
            'notes': ?notes,
          }),
        )
        .timeout(const Duration(seconds: 10));
    final body = _decodeResponse(response);
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw _hubError(response.statusCode, body);
    }
    return Supplier.fromJson(body);
  }

  Future<Supplier> updateSupplier({
    required Supplier supplier,
    required int expectedVersion,
  }) async {
    final response = await _client
        .put(
          Uri.parse(
            '$_root/api/v1/suppliers/${Uri.encodeComponent(supplier.id)}',
          ),
          headers: _headers,
          body: jsonEncode({
            'name': supplier.name,
            if (supplier.contactName != null)
              'contactName': supplier.contactName,
            if (supplier.email != null) 'email': supplier.email,
            if (supplier.phone != null) 'phone': supplier.phone,
            if (supplier.address != null) 'address': supplier.address,
            if (supplier.notes != null) 'notes': supplier.notes,
            'expectedVersion': expectedVersion,
          }),
        )
        .timeout(const Duration(seconds: 10));
    final body = _decodeResponse(response);
    if (response.statusCode != 200) throw _hubError(response.statusCode, body);
    return Supplier.fromJson(body);
  }

  Future<Supplier> setSupplierActive({
    required String supplierId,
    required bool isActive,
    required int expectedVersion,
  }) async {
    final response = await _client
        .put(
          Uri.parse(
            '$_root/api/v1/suppliers/${Uri.encodeComponent(supplierId)}/active',
          ),
          headers: _headers,
          body: jsonEncode({
            'isActive': isActive,
            'expectedVersion': expectedVersion,
          }),
        )
        .timeout(const Duration(seconds: 10));
    final body = _decodeResponse(response);
    if (response.statusCode != 200) throw _hubError(response.statusCode, body);
    return Supplier.fromJson(body);
  }

  Future<List<PurchaseOrder>> fetchPurchaseOrders() async {
    final response = await _client
        .get(Uri.parse('$_root/api/v1/purchase-orders'), headers: _headers)
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 200) throw _hubError(response.statusCode, body);
    return (body['purchaseOrders'] as List<Object?>)
        .map((row) => PurchaseOrder.fromJson(_jsonObject(row)))
        .toList(growable: false);
  }

  Future<PurchaseOrder> createPurchaseOrder({
    required String id,
    required String supplierId,
    required List<Map<String, Object?>> lines,
    String? expectedAt,
    String? note,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_root/api/v1/purchase-orders'),
          headers: _headers,
          body: jsonEncode({
            'id': id,
            'supplierId': supplierId,
            'expectedAt': ?expectedAt,
            'note': ?note,
            'lines': lines,
          }),
        )
        .timeout(const Duration(seconds: 10));
    final body = _decodeResponse(response);
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw _hubError(response.statusCode, body);
    }
    return PurchaseOrder.fromJson(_jsonObject(body['purchaseOrder']));
  }

  Future<PurchaseOrder> placePurchaseOrder(String id) =>
      _purchaseOrderAction(id, 'place');

  Future<PurchaseOrder> cancelPurchaseOrder(String id) =>
      _purchaseOrderAction(id, 'cancel');

  Future<PurchaseOrder> _purchaseOrderAction(String id, String action) async {
    final response = await _client
        .post(
          Uri.parse(
            '$_root/api/v1/purchase-orders/${Uri.encodeComponent(id)}/$action',
          ),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 10));
    final body = _decodeResponse(response);
    if (response.statusCode != 200) throw _hubError(response.statusCode, body);
    return PurchaseOrder.fromJson(_jsonObject(body['purchaseOrder']));
  }

  Future<PurchaseOrder> receivePurchaseOrder({
    required String purchaseOrderId,
    required String receiptId,
    required String location,
    required List<Map<String, Object?>> lines,
    String? note,
  }) async {
    final response = await _client
        .post(
          Uri.parse(
            '$_root/api/v1/purchase-orders/${Uri.encodeComponent(purchaseOrderId)}/receipts',
          ),
          headers: _headers,
          body: jsonEncode({
            'id': receiptId,
            'location': location,
            'note': ?note,
            'lines': lines,
          }),
        )
        .timeout(const Duration(seconds: 10));
    final body = _decodeResponse(response);
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw _hubError(response.statusCode, body);
    }
    return PurchaseOrder.fromJson(_jsonObject(body['purchaseOrder']));
  }

  Future<List<Map<String, Object?>>> fetchSales() async {
    final response = await _client
        .get(Uri.parse('$_root/api/v1/sales'), headers: _headers)
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 200) throw _hubError(response.statusCode, body);
    return (body['sales'] as List<Object?>)
        .map(
          (row) => (row! as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        )
        .toList(growable: false);
  }

  Future<Map<String, Object?>> fetchSalesReport({
    required DateTime from,
    required DateTime to,
  }) async {
    String dateKey(DateTime value) {
      final utc = value.toUtc();
      final month = utc.month.toString().padLeft(2, '0');
      final day = utc.day.toString().padLeft(2, '0');
      return '${utc.year}-$month-$day';
    }

    final uri = Uri.parse(
      '$_root/api/v1/reports/sales',
    ).replace(queryParameters: {'from': dateKey(from), 'to': dateKey(to)});
    final response = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 10));
    final body = _decodeResponse(response);
    if (response.statusCode != 200) throw _hubError(response.statusCode, body);
    return body;
  }

  Future<void> voidSale({
    required String saleId,
    required String reason,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_root/api/v1/sales/${Uri.encodeComponent(saleId)}/void'),
          headers: _headers,
          body: jsonEncode({'reason': reason, 'registerId': registerId}),
        )
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 200) throw _hubError(response.statusCode, body);
  }

  Future<int> returnSale({
    required String id,
    required String saleId,
    required String reason,
    required List<Map<String, Object?>> lines,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_root/api/v1/returns'),
          headers: _headers,
          body: jsonEncode({
            'id': id,
            'saleId': saleId,
            'registerId': registerId,
            'reason': reason,
            'lines': lines,
          }),
        )
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw _hubError(response.statusCode, body);
    }
    return body['refundCents'] as int;
  }

  Future<CatalogSnapshot> fetchProducts() async {
    final response = await _client
        .get(Uri.parse('$_root/api/v1/products'), headers: _headers)
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 200) throw _hubError(response.statusCode, body);
    final rawProducts = body['products'] as List<Object?>;
    return CatalogSnapshot(
      version: body['version'] as int,
      products: rawProducts
          .map((product) => Product.fromJson(product! as Map<String, Object?>))
          .toList(growable: false),
      categories: (body['categories'] as List<Object?>? ?? const [])
          .map((row) => CatalogCategory.fromJson(row! as Map<String, Object?>))
          .toList(growable: false),
    );
  }

  Future<List<CatalogCategory>> fetchCategories() async {
    final response = await _client
        .get(Uri.parse('$_root/api/v1/categories'), headers: _headers)
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 200) throw _hubError(response.statusCode, body);
    return (body['categories'] as List<Object?>)
        .map((row) => CatalogCategory.fromJson(row! as Map<String, Object?>))
        .toList(growable: false);
  }

  Future<CatalogCategory> createCategory(String name) async {
    final response = await _client
        .post(
          Uri.parse('$_root/api/v1/categories'),
          headers: _headers,
          body: jsonEncode({'name': name}),
        )
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 201) throw _hubError(response.statusCode, body);
    return CatalogCategory.fromJson(body);
  }

  Future<CatalogCategory> setCategoryActive(
    String id, {
    required bool isActive,
    required int expectedVersion,
  }) async {
    final response = await _client
        .put(
          Uri.parse('$_root/api/v1/categories/${Uri.encodeComponent(id)}'),
          headers: _headers,
          body: jsonEncode({
            'isActive': isActive,
            'expectedVersion': expectedVersion,
          }),
        )
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 200) throw _hubError(response.statusCode, body);
    return CatalogCategory.fromJson(body);
  }

  Future<Product> createProduct(Product product) async {
    final response = await _client
        .post(
          Uri.parse('$_root/api/v1/products'),
          headers: _headers,
          body: jsonEncode(product.toJson()),
        )
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 201) throw _hubError(response.statusCode, body);
    return Product.fromJson(body);
  }

  Future<Product> updateProduct(Product product) async {
    final response = await _client
        .put(
          Uri.parse(
            '$_root/api/v1/products/${Uri.encodeComponent(product.id)}',
          ),
          headers: _headers,
          body: jsonEncode(product.toJson()),
        )
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 200) throw _hubError(response.statusCode, body);
    return Product.fromJson(body);
  }

  Future<CatalogOperationResult> applyCatalogOperation({
    required String operationId,
    required int expectedVersion,
    required Product product,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_root/api/v1/catalog/operations'),
          headers: _headers,
          body: jsonEncode({
            'operationId': operationId,
            'expectedVersion': expectedVersion,
            'product': product.toJson(),
          }),
        )
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if ((response.statusCode == 200 || response.statusCode == 201) &&
        body['product'] is Map) {
      return CatalogOperationResult(
        product: Product.fromJson(
          (body['product']! as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        ),
        catalogVersion: body['catalogVersion'] as int?,
      );
    }
    if (response.statusCode == 409 &&
        body['error'] == 'catalog_version_conflict') {
      final rawCurrent = body['currentProduct'];
      return CatalogOperationResult(
        conflict: true,
        currentProduct: rawCurrent is Map
            ? Product.fromJson(
                rawCurrent.map((key, value) => MapEntry(key.toString(), value)),
              )
            : null,
      );
    }
    throw _hubError(response.statusCode, body);
  }

  Future<List<InventoryItem>> fetchInventory() async {
    final response = await _client
        .get(Uri.parse('$_root/api/v1/inventory'), headers: _headers)
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 200) throw _hubError(response.statusCode, body);
    return (body['items'] as List<Object?>)
        .map((item) => InventoryItem.fromJson(item! as Map<String, Object?>))
        .toList(growable: false);
  }

  Future<List<StockMovement>> fetchStockMovements() async {
    final response = await _client
        .get(Uri.parse('$_root/api/v1/inventory/movements'), headers: _headers)
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 200) throw _hubError(response.statusCode, body);
    return (body['movements'] as List<Object?>)
        .map((item) => StockMovement.fromJson(item! as Map<String, Object?>))
        .toList(growable: false);
  }

  Future<void> createStockMovement({
    required String id,
    required String productId,
    required StockMovementType type,
    required int quantity,
    String? sourceLocation,
    String? destinationLocation,
    String? note,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_root/api/v1/inventory/movements'),
          headers: _headers,
          body: jsonEncode({
            'id': id,
            'productId': productId,
            'type': type.name,
            'quantity': quantity,
            'sourceLocation': ?sourceLocation,
            'destinationLocation': ?destinationLocation,
            'note': ?note,
          }),
        )
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw _hubError(response.statusCode, body);
    }
  }

  Future<void> setLowStockThreshold({
    required String productId,
    required int threshold,
  }) async {
    final response = await _client
        .put(
          Uri.parse(
            '$_root/api/v1/inventory/items/${Uri.encodeComponent(productId)}/threshold',
          ),
          headers: _headers,
          body: jsonEncode({'lowStockThreshold': threshold}),
        )
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 200) throw _hubError(response.statusCode, body);
  }

  Future<CashShift?> currentCashShift() async {
    final response = await _client
        .get(
          Uri.parse(
            '$_root/api/v1/shifts/current?registerId=${Uri.encodeQueryComponent(registerId)}',
          ),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 200) throw _hubError(response.statusCode, body);
    final shift = body['shift'];
    return shift == null
        ? null
        : CashShift.fromJson(shift as Map<String, Object?>);
  }

  Future<CashShift> fetchCashShift(String shiftId) async {
    final response = await _client
        .get(
          Uri.parse('$_root/api/v1/shifts/${Uri.encodeComponent(shiftId)}'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 200) throw _hubError(response.statusCode, body);
    return CashShift.fromJson(body['shift'] as Map<String, Object?>);
  }

  Future<CashShift> openCashShift({
    required String id,
    required int openingFloatCents,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_root/api/v1/shifts'),
          headers: _headers,
          body: jsonEncode({
            'id': id,
            'openingFloatCents': openingFloatCents,
            'registerId': registerId,
          }),
        )
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw _hubError(response.statusCode, body);
    }
    return CashShift.fromJson(body['shift'] as Map<String, Object?>);
  }

  Future<void> recordCashMovement({
    required String shiftId,
    required String id,
    required String type,
    required int amountCents,
    String? note,
  }) async {
    final response = await _client
        .post(
          Uri.parse(
            '$_root/api/v1/shifts/${Uri.encodeComponent(shiftId)}/cash-movements',
          ),
          headers: _headers,
          body: jsonEncode({
            'id': id,
            'type': type,
            'amountCents': amountCents,
            'note': ?note,
          }),
        )
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw _hubError(response.statusCode, body);
    }
  }

  Future<CashShift> closeCashShift({
    required String shiftId,
    required int countedCashCents,
  }) async {
    final response = await _client
        .post(
          Uri.parse(
            '$_root/api/v1/shifts/${Uri.encodeComponent(shiftId)}/close',
          ),
          headers: _headers,
          body: jsonEncode({'countedCashCents': countedCashCents}),
        )
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 200) throw _hubError(response.statusCode, body);
    return CashShift.fromJson(body['shift'] as Map<String, Object?>);
  }

  Future<List<PosUser>> fetchUsers() async {
    final response = await _client
        .get(Uri.parse('$_root/api/v1/users'), headers: _headers)
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 200) throw _hubError(response.statusCode, body);
    return (body['users'] as List<Object?>)
        .map((user) => PosUser.fromJson(user! as Map<String, Object?>))
        .toList(growable: false);
  }

  Future<PosUser> createUser({
    required String name,
    required String email,
    required String password,
    required AccountRole role,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_root/api/v1/users'),
          headers: _headers,
          body: jsonEncode({
            'name': name,
            'email': email,
            'password': password,
            'role': role.wireValue,
          }),
        )
        .timeout(const Duration(seconds: 5));
    final body = _decodeResponse(response);
    if (response.statusCode != 201) throw _hubError(response.statusCode, body);
    return PosUser.fromJson(body);
  }

  Future<bool> send(Sale sale) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$_root/api/v1/sales'),
            headers: _headers,
            body: jsonEncode(sale.toJson()),
          )
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200 || response.statusCode == 201;
    } on Exception {
      return false;
    }
  }

  Future<bool> sendPayment(PaymentRecord payment) async {
    try {
      final response = await _client
          .post(
            Uri.parse(
              '$_root/api/v1/sales/${Uri.encodeComponent(payment.saleId)}/payments',
            ),
            headers: _headers,
            body: jsonEncode(payment.toJson()),
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200 || response.statusCode == 201;
    } on Exception {
      return false;
    }
  }

  Future<HubSession> _postSession(
    String path,
    Map<String, Object?> payload,
  ) async {
    final response = await _client
        .post(
          Uri.parse('$_root$path'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 10));
    final body = _decodeResponse(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _hubError(response.statusCode, body);
    }
    final session = HubSession.fromJson(body);
    token = session.token;
    return session;
  }

  Map<String, Object?> _jsonObject(Object? value) {
    if (value is! Map) {
      throw const FormatException('Hub response is malformed.');
    }
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  Map<String, Object?> _decodeResponse(http.Response response) {
    if (response.body.isEmpty) return <String, Object?>{};
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('Hub response is malformed.');
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  HubApiException _hubError(int statusCode, Map<String, Object?> body) =>
      HubApiException(
        statusCode,
        body['message'] is String
            ? body['message']! as String
            : 'The hub request failed.',
      );

  void close() => _client.close();
}

class CatalogSnapshot {
  const CatalogSnapshot({
    required this.version,
    required this.products,
    this.categories = const [],
  });

  final int version;
  final List<Product> products;
  final List<CatalogCategory> categories;
}

class SyncEventPage {
  const SyncEventPage({
    required this.events,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<Map<String, Object?>> events;
  final int nextCursor;
  final bool hasMore;
}

class CatalogOperationResult {
  const CatalogOperationResult({
    this.product,
    this.catalogVersion,
    this.conflict = false,
    this.currentProduct,
  });

  final Product? product;
  final int? catalogVersion;
  final bool conflict;
  final Product? currentProduct;
}

class HubApiException implements Exception {
  const HubApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}
