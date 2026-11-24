import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:pos_domain/pos_domain.dart';
import 'package:shelf/shelf.dart';
import 'package:sqlite3/sqlite3.dart';

class HubStore {
  static const currentSchemaVersion = 3;

  HubStore(this._database) {
    _createSchema();
  }

  factory HubStore.open(String path) {
    final database = sqlite3.open(path);
    try {
      return HubStore(database);
    } on Object {
      database.close();
      rethrow;
    }
  }

  factory HubStore.inMemory() {
    final database = sqlite3.openInMemory();
    try {
      return HubStore(database);
    } on Object {
      database.close();
      rethrow;
    }
  }

  final Database _database;
  static const _passwordIterations = 210000;
  static const _sessionLifetime = Duration(days: 30);
  static final _kdf = Pbkdf2.hmacSha256(
    iterations: _passwordIterations,
    bits: 256,
  );

  void _createSchema() {
    final storedVersion =
        _database.select('PRAGMA user_version').first.values.first as int;
    if (storedVersion > currentSchemaVersion) {
      throw StateError(
        'Hub database schema $storedVersion is newer than this server supports ($currentSchemaVersion).',
      );
    }
    _database.execute('PRAGMA foreign_keys = ON');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS sales (
        id TEXT PRIMARY KEY,
        created_at TEXT NOT NULL,
        total_cents INTEGER NOT NULL,
        shift_id TEXT,
        payload TEXT NOT NULL
      )
    ''');
    if (!_hasColumn('sales', 'shift_id')) {
      _database.execute('ALTER TABLE sales ADD COLUMN shift_id TEXT');
    }
    for (final column in const [
      ('voided_at', 'TEXT'),
      ('void_reason', 'TEXT'),
      ('voided_by', 'TEXT'),
      ('points_earned', 'INTEGER NOT NULL DEFAULT 0'),
    ]) {
      if (!_hasColumn('sales', column.$1)) {
        _database.execute(
          'ALTER TABLE sales ADD COLUMN ${column.$1} ${column.$2}',
        );
      }
    }
    _database.execute('''
      CREATE TABLE IF NOT EXISTS payment_records (
        id TEXT PRIMARY KEY,
        sale_id TEXT NOT NULL UNIQUE REFERENCES sales(id),
        status TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS store_meta (
        singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
        id TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE COLLATE NOCASE,
        password_salt TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        role TEXT NOT NULL CHECK (role IN ('admin', 'manager', 'cashier')),
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS sessions (
        token_hash TEXT PRIMARY KEY,
        user_id TEXT NOT NULL REFERENCES users(id),
        created_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        revoked_at TEXT
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS login_attempts (
        email TEXT PRIMARY KEY COLLATE NOCASE,
        attempts INTEGER NOT NULL,
        window_started_at TEXT NOT NULL,
        locked_until TEXT
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS products (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        sku TEXT UNIQUE COLLATE NOCASE,
        barcode TEXT UNIQUE COLLATE NOCASE,
        unit_price_cents INTEGER NOT NULL CHECK (unit_price_cents >= 0),
        is_active INTEGER NOT NULL DEFAULT 1,
        version INTEGER NOT NULL DEFAULT 1,
        modifier_groups_json TEXT NOT NULL DEFAULT '[]',
        updated_at TEXT NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS catalog_categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL COLLATE NOCASE UNIQUE,
        is_active INTEGER NOT NULL DEFAULT 1,
        version INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');
    for (final row in _database.select(
      'SELECT DISTINCT category FROM products ORDER BY category COLLATE NOCASE',
    )) {
      _database.execute(
        'INSERT OR IGNORE INTO catalog_categories (id, name, created_at) VALUES (?, ?, ?)',
        [_newId(), row['category'], DateTime.now().toUtc().toIso8601String()],
      );
    }
    if (!_hasColumn('products', 'barcode')) {
      _database.execute('ALTER TABLE products ADD COLUMN barcode TEXT');
      _database.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS products_barcode_unique ON products(barcode COLLATE NOCASE)',
      );
    }
    if (!_hasColumn('products', 'version')) {
      _database.execute(
        'ALTER TABLE products ADD COLUMN version INTEGER NOT NULL DEFAULT 1',
      );
    }
    if (!_hasColumn('products', 'modifier_groups_json')) {
      _database.execute(
        "ALTER TABLE products ADD COLUMN modifier_groups_json TEXT NOT NULL DEFAULT '[]'",
      );
    }
    _database.execute('''
      CREATE TABLE IF NOT EXISTS catalog_meta (
        singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
        version INTEGER NOT NULL DEFAULT 1
      )
    ''');
    _database.execute(
      'INSERT OR IGNORE INTO catalog_meta (singleton, version) VALUES (1, 1)',
    );
    _database.execute('''
      CREATE TABLE IF NOT EXISTS product_versions (
        product_id TEXT NOT NULL REFERENCES products(id),
        version INTEGER NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (product_id, version)
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS catalog_operations (
        id TEXT PRIMARY KEY,
        request_payload TEXT NOT NULL,
        result_payload TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    for (final row in _database.select('SELECT * FROM products')) {
      final product = Product.fromJson(_productJson(row));
      _saveProductVersion(product, DateTime.now().toUtc());
    }
    _database.execute('''
      CREATE TABLE IF NOT EXISTS audit_events (
        id TEXT PRIMARY KEY,
        actor_user_id TEXT,
        event_type TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        details TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS inventory_balances (
        product_id TEXT NOT NULL REFERENCES products(id),
        location TEXT NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (product_id, location)
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS inventory_thresholds (
        product_id TEXT PRIMARY KEY REFERENCES products(id),
        low_stock_threshold INTEGER NOT NULL DEFAULT 0 CHECK (low_stock_threshold >= 0)
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS inventory_movements (
        id TEXT PRIMARY KEY,
        product_id TEXT NOT NULL REFERENCES products(id),
        type TEXT NOT NULL CHECK (type IN ('receive', 'adjustment', 'transfer', 'sale')),
        quantity INTEGER NOT NULL,
        source_location TEXT,
        destination_location TEXT,
        note TEXT,
        actor_user_id TEXT REFERENCES users(id),
        created_at TEXT NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS suppliers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL COLLATE NOCASE UNIQUE,
        contact_name TEXT,
        email TEXT,
        phone TEXT,
        address TEXT,
        notes TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        version INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS purchase_orders (
        id TEXT PRIMARY KEY,
        supplier_id TEXT NOT NULL REFERENCES suppliers(id),
        status TEXT NOT NULL CHECK (status IN ('draft', 'ordered', 'partially_received', 'received', 'cancelled')),
        expected_at TEXT,
        note TEXT,
        create_payload TEXT NOT NULL,
        version INTEGER NOT NULL DEFAULT 1,
        created_by TEXT NOT NULL REFERENCES users(id),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        ordered_at TEXT,
        cancelled_at TEXT
      )
    ''');
    _database.execute('''
      CREATE INDEX IF NOT EXISTS purchase_orders_supplier_status
      ON purchase_orders (supplier_id, status, created_at DESC)
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS purchase_order_lines (
        id TEXT PRIMARY KEY,
        purchase_order_id TEXT NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
        product_id TEXT NOT NULL REFERENCES products(id),
        product_name TEXT NOT NULL,
        sku TEXT,
        ordered_quantity INTEGER NOT NULL CHECK (ordered_quantity > 0),
        received_quantity INTEGER NOT NULL DEFAULT 0 CHECK (received_quantity >= 0),
        unit_cost_cents INTEGER NOT NULL CHECK (unit_cost_cents >= 0)
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS purchase_order_receipts (
        id TEXT PRIMARY KEY,
        purchase_order_id TEXT NOT NULL REFERENCES purchase_orders(id),
        payload TEXT NOT NULL,
        received_by TEXT NOT NULL REFERENCES users(id),
        received_at TEXT NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS purchase_order_receipt_lines (
        receipt_id TEXT NOT NULL REFERENCES purchase_order_receipts(id) ON DELETE CASCADE,
        line_id TEXT NOT NULL REFERENCES purchase_order_lines(id),
        quantity INTEGER NOT NULL CHECK (quantity > 0),
        PRIMARY KEY (receipt_id, line_id)
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS cash_shifts (
        id TEXT PRIMARY KEY,
        opened_by TEXT NOT NULL REFERENCES users(id),
        opened_at TEXT NOT NULL,
        opening_float_cents INTEGER NOT NULL CHECK (opening_float_cents >= 0),
        closed_at TEXT,
        counted_cash_cents INTEGER,
        expected_cash_cents INTEGER NOT NULL,
        variance_cents INTEGER,
        register_id TEXT NOT NULL DEFAULT 'main'
      )
    ''');
    if (!_hasColumn('cash_shifts', 'register_id')) {
      _database.execute(
        "ALTER TABLE cash_shifts ADD COLUMN register_id TEXT NOT NULL DEFAULT 'main'",
      );
    }
    _database.execute('DROP INDEX IF EXISTS one_open_cash_shift');
    _database.execute('DROP INDEX IF EXISTS one_open_cash_shift_per_register');
    _database.execute('''
      CREATE UNIQUE INDEX one_open_cash_shift_per_register
      ON cash_shifts (register_id) WHERE closed_at IS NULL
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS cash_movements (
        id TEXT PRIMARY KEY,
        shift_id TEXT NOT NULL REFERENCES cash_shifts(id),
        type TEXT NOT NULL CHECK (type IN ('paid_in', 'paid_out')),
        amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
        note TEXT,
        actor_user_id TEXT NOT NULL REFERENCES users(id),
        created_at TEXT NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS registers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        registered_at TEXT NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS sync_events (
        cursor INTEGER PRIMARY KEY AUTOINCREMENT,
        id TEXT NOT NULL UNIQUE,
        schema_version INTEGER NOT NULL DEFAULT 1,
        event_type TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS sync_cursors (
        register_id TEXT PRIMARY KEY REFERENCES registers(id),
        cursor INTEGER NOT NULL DEFAULT 0 CHECK (cursor >= 0),
        acknowledged_at TEXT NOT NULL
      )
    ''');
    _database.execute('''
      INSERT OR IGNORE INTO sync_events
        (id, schema_version, event_type, entity_type, entity_id, payload, created_at)
      SELECT id, 1, event_type, entity_type, entity_id, details, created_at
      FROM audit_events
    ''');
    _database.execute(
      "INSERT OR IGNORE INTO registers (id, name, registered_at) VALUES ('main', 'Main register', '1970-01-01T00:00:00.000Z')",
    );
    _database.execute('''
      CREATE TABLE IF NOT EXISTS tax_settings (
        singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
        name TEXT NOT NULL,
        rate_basis_points INTEGER NOT NULL DEFAULT 0,
        prices_include_tax INTEGER NOT NULL DEFAULT 0,
        version INTEGER NOT NULL DEFAULT 1
      )
    ''');
    if (!_hasColumn('tax_settings', 'version')) {
      _database.execute(
        'ALTER TABLE tax_settings ADD COLUMN version INTEGER NOT NULL DEFAULT 1',
      );
    }
    _database.execute(
      "INSERT OR IGNORE INTO tax_settings (singleton, name, rate_basis_points, prices_include_tax) VALUES (1, 'Tax', 0, 0)",
    );
    _database.execute('''
      CREATE TABLE IF NOT EXISTS tax_config_versions (
        version INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        rate_basis_points INTEGER NOT NULL,
        prices_include_tax INTEGER NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    _database.execute(
      'INSERT OR IGNORE INTO tax_config_versions (version, name, rate_basis_points, prices_include_tax, created_at) SELECT version, name, rate_basis_points, prices_include_tax, ? FROM tax_settings WHERE singleton = 1',
      [DateTime.now().toUtc().toIso8601String()],
    );
    _database.execute('''
      CREATE TABLE IF NOT EXISTS loyalty_settings (
        singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
        earn_points_per_100_cents INTEGER NOT NULL DEFAULT 1,
        redeem_cents_per_point INTEGER NOT NULL DEFAULT 1,
        version INTEGER NOT NULL DEFAULT 1
      )
    ''');
    if (!_hasColumn('loyalty_settings', 'version')) {
      _database.execute(
        'ALTER TABLE loyalty_settings ADD COLUMN version INTEGER NOT NULL DEFAULT 1',
      );
    }
    _database.execute(
      'INSERT OR IGNORE INTO loyalty_settings (singleton, earn_points_per_100_cents, redeem_cents_per_point) VALUES (1, 1, 1)',
    );
    _database.execute('''
      CREATE TABLE IF NOT EXISTS loyalty_config_versions (
        version INTEGER PRIMARY KEY,
        earn_points_per_100_cents INTEGER NOT NULL,
        redeem_cents_per_point INTEGER NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    _database.execute(
      'INSERT OR IGNORE INTO loyalty_config_versions (version, earn_points_per_100_cents, redeem_cents_per_point, created_at) SELECT version, earn_points_per_100_cents, redeem_cents_per_point, ? FROM loyalty_settings WHERE singleton = 1',
      [DateTime.now().toUtc().toIso8601String()],
    );
    _database.execute('''
      CREATE TABLE IF NOT EXISTS customers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT UNIQUE COLLATE NOCASE,
        email TEXT UNIQUE COLLATE NOCASE,
        loyalty_points INTEGER NOT NULL DEFAULT 0 CHECK (loyalty_points >= 0),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS loyalty_events (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL REFERENCES customers(id),
        sale_id TEXT NOT NULL REFERENCES sales(id),
        points_delta INTEGER NOT NULL,
        note TEXT NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE (customer_id, sale_id, note)
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS returns (
        id TEXT PRIMARY KEY,
        sale_id TEXT NOT NULL REFERENCES sales(id),
        shift_id TEXT NOT NULL REFERENCES cash_shifts(id),
        refund_cents INTEGER NOT NULL CHECK (refund_cents >= 0),
        reason TEXT NOT NULL,
        payload TEXT NOT NULL,
        points_earned_reversed INTEGER NOT NULL DEFAULT 0,
        points_redeemed_restored INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    if (!_hasColumn('returns', 'points_earned_reversed')) {
      _database.execute(
        'ALTER TABLE returns ADD COLUMN points_earned_reversed INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!_hasColumn('returns', 'points_redeemed_restored')) {
      _database.execute(
        'ALTER TABLE returns ADD COLUMN points_redeemed_restored INTEGER NOT NULL DEFAULT 0',
      );
    }
    _database.execute('''
      CREATE TABLE IF NOT EXISTS return_lines (
        return_id TEXT NOT NULL REFERENCES returns(id),
        sale_id TEXT NOT NULL REFERENCES sales(id),
        product_id TEXT NOT NULL REFERENCES products(id),
        sale_line_index INTEGER NOT NULL DEFAULT 0,
        quantity INTEGER NOT NULL CHECK (quantity > 0),
        restock INTEGER NOT NULL DEFAULT 1,
        PRIMARY KEY (return_id, sale_line_index)
      )
    ''');
    if (!_hasColumn('return_lines', 'sale_line_index')) {
      _database.execute(
        'ALTER TABLE return_lines RENAME TO return_lines_legacy',
      );
      _database.execute('''
        CREATE TABLE return_lines (
          return_id TEXT NOT NULL REFERENCES returns(id),
          sale_id TEXT NOT NULL REFERENCES sales(id),
          product_id TEXT NOT NULL REFERENCES products(id),
          sale_line_index INTEGER NOT NULL DEFAULT 0,
          quantity INTEGER NOT NULL CHECK (quantity > 0),
          restock INTEGER NOT NULL DEFAULT 1,
          PRIMARY KEY (return_id, sale_line_index)
        )
      ''');
      _database.execute('''
        INSERT INTO return_lines
          (return_id, sale_id, product_id, sale_line_index, quantity, restock)
        SELECT return_id, sale_id, product_id, 0, quantity, restock
        FROM return_lines_legacy
      ''');
      _database.execute('DROP TABLE return_lines_legacy');
    }
    // The idempotent DDL upgrades unversioned databases in place. Keep this
    // marker so future releases can add explicit numbered migrations.
    _database.execute('PRAGMA user_version = $currentSchemaVersion');
  }

  Response setupStatus() {
    final stores = _database.select(
      'SELECT id, name FROM store_meta WHERE singleton = 1',
    );
    return _json(200, {
      'needsSetup': stores.isEmpty,
      'store': stores.isEmpty ? null : _storeJson(stores.first),
    });
  }

  Future<Response> createStoreAndAdmin(Request request) async {
    if (_storeExists) {
      return _error(
        409,
        'setup_complete',
        'This deployment is already set up.',
      );
    }
    late final Map<String, Object?> body;
    try {
      body = await _readJsonObject(request);
    } on Object {
      return _error(
        400,
        'invalid_setup',
        'Setup details are missing or malformed.',
      );
    }
    final storeName = _requiredText(body['storeName'], 2, 100);
    final userName = _requiredText(body['name'], 2, 100);
    final email = _normalizedEmail(body['email']);
    final password = body['password'];
    if (storeName == null ||
        userName == null ||
        email == null ||
        !_validPassword(password)) {
      return _error(
        400,
        'invalid_setup',
        'Enter a store name, owner name, valid email, and password with at least 12 characters.',
      );
    }

    final storeId = _newId();
    final userId = _newId();
    final salt = _randomBytes(16);
    final passwordHash = await _hashPassword(password as String, salt);
    final now = DateTime.now().toUtc();
    final token = _newToken();

    _database.execute('BEGIN IMMEDIATE');
    try {
      if (_storeExists) {
        _database.execute('ROLLBACK');
        return _error(
          409,
          'setup_complete',
          'This deployment is already set up.',
        );
      }
      _database.execute(
        'INSERT INTO store_meta (singleton, id, name, created_at) VALUES (1, ?, ?, ?)',
        [storeId, storeName, now.toIso8601String()],
      );
      _database.execute(
        'INSERT INTO users (id, name, email, password_salt, password_hash, role, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          userId,
          userName,
          email,
          _b64(salt),
          _b64(passwordHash),
          'admin',
          now.toIso8601String(),
        ],
      );
      _insertSession(token, userId, now);
      _audit(userId, 'store.setup', 'store', storeId, {'name': storeName});
      _database.execute('COMMIT');
    } on Object {
      _database.execute('ROLLBACK');
      return _error(409, 'setup_conflict', 'Could not complete initial setup.');
    }

    return _sessionResponse(201, token, userId);
  }

  Future<Response> signIn(Request request) async {
    late final Map<String, Object?> body;
    try {
      body = await _readJsonObject(request);
    } on Object {
      return _error(
        400,
        'invalid_credentials',
        'Email or password is incorrect.',
      );
    }
    final email = _normalizedEmail(body['email']);
    final password = body['password'];
    if (email == null || password is! String || password.isEmpty) {
      return _error(
        400,
        'invalid_credentials',
        'Email or password is incorrect.',
      );
    }

    final attempt = _loginAttempt(email);
    if (attempt?.lockedUntil case final DateTime lockedUntil
        when lockedUntil.isAfter(DateTime.now().toUtc())) {
      return _error(
        429,
        'login_temporarily_locked',
        'Try signing in again later.',
      );
    }

    final rows = _database.select(
      'SELECT id, password_salt, password_hash, is_active FROM users WHERE email = ?',
      [email],
    );
    final found = rows.isNotEmpty;
    final row = found ? rows.first : null;
    final salt = found
        ? _unb64(row!['password_salt'] as String)
        : List<int>.filled(16, 0);
    final actual = await _hashPassword(password, salt);
    final expected = found
        ? _unb64(row!['password_hash'] as String)
        : List<int>.filled(32, 0);
    final matches = _constantTimeEquals(actual, expected);
    if (!found || !matches || row!['is_active'] != 1) {
      final lockout = _recordFailedLogin(email);
      if (lockout) {
        return _error(
          429,
          'login_temporarily_locked',
          'Try signing in again later.',
        );
      }
      return _error(
        401,
        'invalid_credentials',
        'Email or password is incorrect.',
      );
    }

    _database.execute('DELETE FROM login_attempts WHERE email = ?', [email]);
    final userId = row['id'] as String;
    final token = _newToken();
    _insertSession(token, userId, DateTime.now().toUtc());
    _audit(userId, 'auth.sign_in', 'user', userId, const {});
    return _sessionResponse(200, token, userId);
  }

  Response currentUser(Request request) {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    return _json(200, {'user': principal.user, 'store': principal.store});
  }

  Response signOut(Request request) {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    final token = _bearerToken(request);
    _database.execute(
      'UPDATE sessions SET revoked_at = ? WHERE token_hash = ?',
      [DateTime.now().toUtc().toIso8601String(), _tokenHash(token!)],
    );
    return Response(204);
  }

  Response listProducts(Request request) {
    if (_principal(request) == null) return _unauthorized();
    final products = _database.select(
      'SELECT * FROM products WHERE is_active = 1 ORDER BY category, name COLLATE NOCASE',
    );
    final version =
        _database
                .select('SELECT version FROM catalog_meta WHERE singleton = 1')
                .first['version']
            as int;
    return _json(200, {
      'version': version,
      'products': products.map(_productJson).toList(growable: false),
      'categories': _database
          .select(
            'SELECT * FROM catalog_categories ORDER BY is_active DESC, name COLLATE NOCASE',
          )
          .map(_categoryJson)
          .toList(growable: false),
    });
  }

  Response listCategories(Request request) {
    if (_principal(request) == null) return _unauthorized();
    final categories = _database.select(
      'SELECT * FROM catalog_categories ORDER BY is_active DESC, name COLLATE NOCASE',
    );
    return _json(200, {
      'categories': categories.map(_categoryJson).toList(growable: false),
    });
  }

  Future<Response> createCategory(Request request) async {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    if (!principal.canManageCatalog) return _forbidden();
    late final Map<String, Object?> body;
    try {
      body = await _readJsonObject(request);
    } on Object {
      return _error(400, 'invalid_category', 'Category details are malformed.');
    }
    final name = _requiredText(body['name'], 1, 60);
    if (name == null) {
      return _error(
        400,
        'invalid_category',
        'Enter a category name up to 60 characters long.',
      );
    }
    if (_database.select(
      'SELECT id FROM catalog_categories WHERE name = ? COLLATE NOCASE',
      [name],
    ).isNotEmpty) {
      return _error(
        409,
        'category_name_conflict',
        'A category with this name already exists. Restore it if it is archived.',
      );
    }
    final now = DateTime.now().toUtc();
    final category = _insertCategory(name, principal.userId, now);
    return _json(201, _categoryJson(category));
  }

  Future<Response> setCategoryActive(Request request, String id) async {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    if (!principal.canManageCatalog) return _forbidden();
    late final Map<String, Object?> body;
    try {
      body = await _readJsonObject(request);
    } on Object {
      return _error(400, 'invalid_category', 'Category details are malformed.');
    }
    final isActive = body['isActive'];
    final expectedVersion = body['expectedVersion'];
    if (isActive is! bool || expectedVersion is! int || expectedVersion < 1) {
      return _error(
        400,
        'invalid_category',
        'Choose an active or archived state.',
      );
    }
    final rows = _database.select(
      'SELECT * FROM catalog_categories WHERE id = ?',
      [id],
    );
    if (rows.isEmpty) {
      return _error(404, 'category_not_found', 'No category has this ID.');
    }
    final current = rows.single;
    if (expectedVersion != current['version']) {
      return _json(409, {
        'error': 'category_version_conflict',
        'message':
            'This category changed on another register. Refresh and try again.',
        'currentCategory': _categoryJson(current),
      });
    }
    if (!isActive && current['is_active'] == 1) {
      final inUse = _database.select(
        'SELECT 1 FROM products WHERE category = ? COLLATE NOCASE AND is_active = 1 LIMIT 1',
        [current['name']],
      );
      if (inUse.isNotEmpty) {
        return _error(
          409,
          'category_in_use',
          'Move active products to another category before archiving this one.',
        );
      }
    }
    final wasActive = current['is_active'] == 1;
    if (wasActive != isActive) {
      final nextVersion = (current['version'] as int) + 1;
      _database.execute(
        'UPDATE catalog_categories SET is_active = ?, version = ? WHERE id = ?',
        [isActive ? 1 : 0, nextVersion, id],
      );
      _incrementCatalogVersion();
      _audit(
        principal.userId,
        isActive ? 'catalog.category_restored' : 'catalog.category_archived',
        'category',
        id,
        {'name': current['name'], 'version': nextVersion},
      );
    }
    final updated = _database.select(
      'SELECT * FROM catalog_categories WHERE id = ?',
      [id],
    ).single;
    return _json(200, _categoryJson(updated));
  }

  Response listSuppliers(Request request) {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    if (!principal.canManageCatalog) return _forbidden();
    final rows = _database.select(
      'SELECT * FROM suppliers ORDER BY is_active DESC, name COLLATE NOCASE LIMIT 500',
    );
    return _json(200, {
      'suppliers': rows.map(_supplierJson).toList(growable: false),
    });
  }

  Future<Response> createSupplier(Request request) async {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    if (!principal.canManageCatalog) return _forbidden();
    late final Map<String, Object?> body;
    try {
      body = await _readJsonObject(request);
    } on Object {
      return _error(400, 'invalid_supplier', 'Supplier details are malformed.');
    }
    final id = _requiredText(body['id'], 1, 128);
    final name = _requiredText(body['name'], 1, 160);
    final contactName = _optionalSupplierText(body, 'contactName', 160);
    final phone = _optionalSupplierText(body, 'phone', 64);
    final address = _optionalSupplierText(body, 'address', 500);
    final notes = _optionalSupplierText(body, 'notes', 1000);
    final emailInput = body['email'] == null
        ? ''
        : _requiredText(body['email'], 0, 254);
    final email = emailInput == null || emailInput.isEmpty
        ? null
        : _normalizedEmail(emailInput);
    if (id == null ||
        name == null ||
        (body['contactName'] != null && contactName == null) ||
        (body['phone'] != null && phone == null) ||
        (body['address'] != null && address == null) ||
        (body['notes'] != null && notes == null) ||
        emailInput == null ||
        (emailInput.isNotEmpty && email == null)) {
      return _error(
        400,
        'invalid_supplier',
        'Enter a name and valid contact details for the supplier.',
      );
    }
    final existing = _database.select('SELECT * FROM suppliers WHERE id = ?', [
      id,
    ]);
    if (existing.isNotEmpty) {
      final current = existing.single;
      final same =
          current['name'] == name &&
          current['contact_name'] == contactName &&
          current['email'] == email &&
          current['phone'] == phone &&
          current['address'] == address &&
          current['notes'] == notes;
      if (!same) {
        return _error(
          409,
          'supplier_id_conflict',
          'This supplier ID already has different details.',
        );
      }
      return _json(200, _supplierJson(current));
    }
    if (_database.select(
      'SELECT id FROM suppliers WHERE name = ? COLLATE NOCASE',
      [name],
    ).isNotEmpty) {
      return _error(
        409,
        'supplier_name_conflict',
        'A supplier with this name already exists.',
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    _database.execute(
      '''
      INSERT INTO suppliers
        (id, name, contact_name, email, phone, address, notes, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [id, name, contactName, email, phone, address, notes, now, now],
    );
    _audit(principal.userId, 'supplier.created', 'supplier', id, {
      'name': name,
    });
    return _json(
      201,
      _supplierJson(
        _database.select('SELECT * FROM suppliers WHERE id = ?', [id]).single,
      ),
    );
  }

  Future<Response> updateSupplier(Request request, String id) async {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    if (!principal.canManageCatalog) return _forbidden();
    late final Map<String, Object?> body;
    try {
      body = await _readJsonObject(request);
    } on Object {
      return _error(400, 'invalid_supplier', 'Supplier details are malformed.');
    }
    final name = _requiredText(body['name'], 1, 160);
    final contactName = _optionalSupplierText(body, 'contactName', 160);
    final phone = _optionalSupplierText(body, 'phone', 64);
    final address = _optionalSupplierText(body, 'address', 500);
    final notes = _optionalSupplierText(body, 'notes', 1000);
    final emailInput = body['email'] == null
        ? ''
        : _requiredText(body['email'], 0, 254);
    final email = emailInput == null || emailInput.isEmpty
        ? null
        : _normalizedEmail(emailInput);
    final expectedVersion = body['expectedVersion'];
    if (name == null ||
        expectedVersion is! int ||
        expectedVersion < 1 ||
        (body['contactName'] != null && contactName == null) ||
        (body['phone'] != null && phone == null) ||
        (body['address'] != null && address == null) ||
        (body['notes'] != null && notes == null) ||
        emailInput == null ||
        (emailInput.isNotEmpty && email == null)) {
      return _error(
        400,
        'invalid_supplier',
        'Enter a name and valid contact details for the supplier.',
      );
    }
    final rows = _database.select('SELECT * FROM suppliers WHERE id = ?', [id]);
    if (rows.isEmpty) {
      return _error(404, 'supplier_not_found', 'No supplier has this ID.');
    }
    final current = rows.single;
    if (current['version'] != expectedVersion) {
      return _json(409, {
        'error': 'supplier_version_conflict',
        'message': 'This supplier changed on another register.',
        'currentSupplier': _supplierJson(current),
      });
    }
    if (_database.select(
      'SELECT id FROM suppliers WHERE name = ? COLLATE NOCASE AND id != ?',
      [name, id],
    ).isNotEmpty) {
      return _error(
        409,
        'supplier_name_conflict',
        'A supplier with this name already exists.',
      );
    }
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    final version = expectedVersion + 1;
    _database.execute(
      '''
      UPDATE suppliers SET name = ?, contact_name = ?, email = ?, phone = ?,
        address = ?, notes = ?, version = ?, updated_at = ? WHERE id = ?
      ''',
      [name, contactName, email, phone, address, notes, version, updatedAt, id],
    );
    _audit(principal.userId, 'supplier.updated', 'supplier', id, {
      'name': name,
      'version': version,
    });
    return _json(
      200,
      _supplierJson(
        _database.select('SELECT * FROM suppliers WHERE id = ?', [id]).single,
      ),
    );
  }

  Future<Response> setSupplierActive(Request request, String id) async {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    if (!principal.canManageCatalog) return _forbidden();
    late final Map<String, Object?> body;
    try {
      body = await _readJsonObject(request);
    } on Object {
      return _error(400, 'invalid_supplier', 'Supplier details are malformed.');
    }
    final isActive = body['isActive'];
    final expectedVersion = body['expectedVersion'];
    if (isActive is! bool || expectedVersion is! int || expectedVersion < 1) {
      return _error(
        400,
        'invalid_supplier',
        'Choose an active or archived supplier state.',
      );
    }
    final rows = _database.select('SELECT * FROM suppliers WHERE id = ?', [id]);
    if (rows.isEmpty) {
      return _error(404, 'supplier_not_found', 'No supplier has this ID.');
    }
    final current = rows.single;
    if (current['version'] != expectedVersion) {
      return _json(409, {
        'error': 'supplier_version_conflict',
        'message': 'This supplier changed on another register.',
        'currentSupplier': _supplierJson(current),
      });
    }
    final wasActive = current['is_active'] == 1;
    if (wasActive != isActive) {
      final version = expectedVersion + 1;
      _database.execute(
        'UPDATE suppliers SET is_active = ?, version = ?, updated_at = ? WHERE id = ?',
        [
          isActive ? 1 : 0,
          version,
          DateTime.now().toUtc().toIso8601String(),
          id,
        ],
      );
      _audit(
        principal.userId,
        isActive ? 'supplier.restored' : 'supplier.archived',
        'supplier',
        id,
        {'name': current['name'], 'version': version},
      );
    }
    return _json(
      200,
      _supplierJson(
        _database.select('SELECT * FROM suppliers WHERE id = ?', [id]).single,
      ),
    );
  }

  Response listPurchaseOrders(Request request) {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    if (!principal.canManageCatalog) return _forbidden();
    final rows = _database.select(
      'SELECT id FROM purchase_orders ORDER BY created_at DESC, id DESC LIMIT 500',
    );
    return _json(200, {
      'purchaseOrders': rows
          .map((row) => _purchaseOrderJson(row['id'] as String))
          .toList(growable: false),
    });
  }

  Future<Response> createPurchaseOrder(Request request) async {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    if (!principal.canManageCatalog) return _forbidden();
    late final Map<String, Object?> body;
    try {
      body = await _readJsonObject(request);
    } on Object {
      return _error(
        400,
        'invalid_purchase_order',
        'Purchase order details are malformed.',
      );
    }
    final id = _requiredText(body['id'], 1, 128);
    final supplierId = _requiredText(body['supplierId'], 1, 128);
    final expectedAtInput = body['expectedAt'];
    final expectedAt = expectedAtInput == null || expectedAtInput == ''
        ? null
        : expectedAtInput is String
        ? _reportDate(expectedAtInput)
        : null;
    final noteInput = body['note'] == null
        ? ''
        : _requiredText(body['note'], 0, 1000);
    final note = noteInput == null || noteInput.isEmpty ? null : noteInput;
    final rawLines = body['lines'];
    if (id == null ||
        supplierId == null ||
        (expectedAtInput != null && expectedAt == null) ||
        noteInput == null ||
        rawLines is! List ||
        rawLines.isEmpty ||
        rawLines.length > 100) {
      return _error(
        400,
        'invalid_purchase_order',
        'Choose a supplier and add between 1 and 100 valid items.',
      );
    }
    final supplierRows = _database.select(
      'SELECT id FROM suppliers WHERE id = ? AND is_active = 1',
      [supplierId],
    );
    if (supplierRows.isEmpty) {
      return _error(
        409,
        'supplier_not_active',
        'Choose an active supplier before saving this order.',
      );
    }

    final cleanLines = <Map<String, Object?>>[];
    final seenIds = <String>{};
    final seenProducts = <String>{};
    var totalCents = BigInt.zero;
    for (final rawLine in rawLines) {
      if (rawLine is! Map) {
        return _error(
          400,
          'invalid_purchase_order',
          'An item line is malformed.',
        );
      }
      final lineId = _requiredText(rawLine['id'], 1, 128);
      final productId = _requiredText(rawLine['productId'], 1, 128);
      final quantity = rawLine['quantity'];
      final unitCostCents = rawLine['unitCostCents'];
      if (lineId == null ||
          productId == null ||
          quantity is! int ||
          quantity < 1 ||
          quantity > 1000000 ||
          unitCostCents is! int ||
          unitCostCents < 0 ||
          unitCostCents > 9007199254740991 ||
          !seenIds.add(lineId) ||
          !seenProducts.add(productId)) {
        return _error(
          400,
          'invalid_purchase_order',
          'Each order item needs a unique product, positive quantity, and non-negative unit cost.',
        );
      }
      final productRows = _database.select(
        'SELECT id FROM products WHERE id = ? AND is_active = 1',
        [productId],
      );
      if (productRows.isEmpty) {
        return _error(
          409,
          'product_not_active',
          'An order item is no longer active in the catalog.',
        );
      }
      totalCents += BigInt.from(quantity) * BigInt.from(unitCostCents);
      if (totalCents > BigInt.from(9007199254740991)) {
        return _error(
          400,
          'purchase_order_total_too_large',
          'The purchase order total is too large.',
        );
      }
      cleanLines.add({
        'id': lineId,
        'productId': productId,
        'quantity': quantity,
        'unitCostCents': unitCostCents,
      });
    }

    final expectedAtKey = expectedAt == null ? null : _reportDayKey(expectedAt);
    final createPayload = jsonEncode({
      'supplierId': supplierId,
      'expectedAt': expectedAtKey,
      'note': note,
      'lines': cleanLines,
    });
    final existing = _database.select(
      'SELECT create_payload FROM purchase_orders WHERE id = ?',
      [id],
    );
    if (existing.isNotEmpty) {
      if (existing.single['create_payload'] != createPayload) {
        return _error(
          409,
          'purchase_order_id_conflict',
          'This purchase order ID already has different details.',
        );
      }
      return _json(200, {
        'purchaseOrder': _purchaseOrderJson(id),
        'status': 'accepted',
      });
    }

    final now = DateTime.now().toUtc().toIso8601String();
    _database.execute('BEGIN IMMEDIATE');
    try {
      final retriedOrder = _database.select(
        'SELECT create_payload FROM purchase_orders WHERE id = ?',
        [id],
      );
      if (retriedOrder.isNotEmpty) {
        final matches = retriedOrder.single['create_payload'] == createPayload;
        _database.execute(matches ? 'COMMIT' : 'ROLLBACK');
        if (!matches) {
          return _error(
            409,
            'purchase_order_id_conflict',
            'This purchase order ID already has different details.',
          );
        }
        return _json(200, {
          'purchaseOrder': _purchaseOrderJson(id),
          'status': 'accepted',
        });
      }
      _database.execute(
        '''
        INSERT INTO purchase_orders
          (id, supplier_id, status, expected_at, note, create_payload,
           created_by, created_at, updated_at)
        VALUES (?, ?, 'draft', ?, ?, ?, ?, ?, ?)
        ''',
        [
          id,
          supplierId,
          expectedAtKey,
          note,
          createPayload,
          principal.userId,
          now,
          now,
        ],
      );
      for (final line in cleanLines) {
        final product = _database.select(
          'SELECT name, sku FROM products WHERE id = ?',
          [line['productId']],
        ).single;
        _database.execute(
          '''
          INSERT INTO purchase_order_lines
            (id, purchase_order_id, product_id, product_name, sku,
             ordered_quantity, unit_cost_cents)
          VALUES (?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            line['id'],
            id,
            line['productId'],
            product['name'],
            product['sku'],
            line['quantity'],
            line['unitCostCents'],
          ],
        );
      }
      _audit(principal.userId, 'purchase_order.created', 'purchase_order', id, {
        'supplierId': supplierId,
        'itemCount': cleanLines.length,
        'totalCents': totalCents.toInt(),
      });
      _database.execute('COMMIT');
    } on Object {
      _database.execute('ROLLBACK');
      return _error(
        500,
        'purchase_order_save_failed',
        'The purchase order could not be saved.',
      );
    }
    return _json(201, {
      'purchaseOrder': _purchaseOrderJson(id),
      'status': 'accepted',
    });
  }

  Response placePurchaseOrder(Request request, String id) {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    if (!principal.canManageCatalog) return _forbidden();
    final rows = _database.select(
      'SELECT status FROM purchase_orders WHERE id = ?',
      [id],
    );
    if (rows.isEmpty) {
      return _error(
        404,
        'purchase_order_not_found',
        'No purchase order has this ID.',
      );
    }
    final status = rows.single['status'] as String;
    if (status == 'ordered' ||
        status == 'partially_received' ||
        status == 'received') {
      return _json(200, {'purchaseOrder': _purchaseOrderJson(id)});
    }
    if (status != 'draft') {
      return _error(
        409,
        'purchase_order_not_draft',
        'Only a draft purchase order can be placed.',
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    _database.execute(
      '''
      UPDATE purchase_orders
      SET status = 'ordered', ordered_at = ?, updated_at = ?, version = version + 1
      WHERE id = ? AND status = 'draft'
      ''',
      [now, now, id],
    );
    _audit(principal.userId, 'purchase_order.placed', 'purchase_order', id, {});
    return _json(200, {'purchaseOrder': _purchaseOrderJson(id)});
  }

  Response cancelPurchaseOrder(Request request, String id) {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    if (!principal.canManageCatalog) return _forbidden();
    final rows = _database.select(
      'SELECT status FROM purchase_orders WHERE id = ?',
      [id],
    );
    if (rows.isEmpty) {
      return _error(
        404,
        'purchase_order_not_found',
        'No purchase order has this ID.',
      );
    }
    final status = rows.single['status'] as String;
    if (status == 'cancelled') {
      return _json(200, {'purchaseOrder': _purchaseOrderJson(id)});
    }
    if (status != 'draft' && status != 'ordered') {
      return _error(
        409,
        'purchase_order_cannot_cancel',
        'An order with received items cannot be cancelled.',
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    _database.execute(
      '''
      UPDATE purchase_orders
      SET status = 'cancelled', cancelled_at = ?, updated_at = ?, version = version + 1
      WHERE id = ?
      ''',
      [now, now, id],
    );
    _audit(
      principal.userId,
      'purchase_order.cancelled',
      'purchase_order',
      id,
      {},
    );
    return _json(200, {'purchaseOrder': _purchaseOrderJson(id)});
  }

  Future<Response> receivePurchaseOrder(Request request, String id) async {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    if (!principal.canManageCatalog) return _forbidden();
    late final Map<String, Object?> body;
    try {
      body = await _readJsonObject(request);
    } on Object {
      return _error(400, 'invalid_receipt', 'Receipt details are malformed.');
    }
    final receiptId = _requiredText(body['id'], 1, 128);
    final location = _requiredText(body['location'], 1, 80) ?? 'Main';
    final noteInput = body['note'] == null
        ? ''
        : _requiredText(body['note'], 0, 240);
    final note = noteInput == null || noteInput.isEmpty ? null : noteInput;
    final rawLines = body['lines'];
    if (receiptId == null ||
        location.isEmpty ||
        (body['location'] != null &&
            _requiredText(body['location'], 1, 80) == null) ||
        noteInput == null ||
        rawLines is! List ||
        rawLines.isEmpty ||
        rawLines.length > 100) {
      return _error(
        400,
        'invalid_receipt',
        'Choose a receiving location and at least one valid item quantity.',
      );
    }
    final cleanLines = <Map<String, Object?>>[];
    final seenLineIds = <String>{};
    for (final rawLine in rawLines) {
      if (rawLine is! Map) {
        return _error(400, 'invalid_receipt', 'An item quantity is malformed.');
      }
      final lineId = _requiredText(rawLine['lineId'], 1, 128);
      final quantity = rawLine['quantity'];
      if (lineId == null ||
          quantity is! int ||
          quantity < 1 ||
          quantity > 1000000 ||
          !seenLineIds.add(lineId)) {
        return _error(
          400,
          'invalid_receipt',
          'Enter a positive quantity once for each received order item.',
        );
      }
      cleanLines.add({'lineId': lineId, 'quantity': quantity});
    }
    final receiptPayload = jsonEncode({
      'location': location,
      'note': note,
      'lines': cleanLines,
    });
    final previousReceipt = _database.select(
      'SELECT purchase_order_id, payload FROM purchase_order_receipts WHERE id = ?',
      [receiptId],
    );
    if (previousReceipt.isNotEmpty) {
      final previous = previousReceipt.single;
      if (previous['purchase_order_id'] != id ||
          previous['payload'] != receiptPayload) {
        return _error(
          409,
          'receipt_id_conflict',
          'This receipt ID already has different details.',
        );
      }
      return _json(200, {
        'receiptId': receiptId,
        'purchaseOrder': _purchaseOrderJson(id),
        'status': 'accepted',
      });
    }
    final orderRows = _database.select(
      'SELECT status FROM purchase_orders WHERE id = ?',
      [id],
    );
    if (orderRows.isEmpty) {
      return _error(
        404,
        'purchase_order_not_found',
        'No purchase order has this ID.',
      );
    }
    if (!const [
      'ordered',
      'partially_received',
    ].contains(orderRows.single['status'])) {
      return _error(
        409,
        'purchase_order_not_receivable',
        'Place the order before receiving items.',
      );
    }
    for (final line in cleanLines) {
      final rows = _database.select(
        'SELECT ordered_quantity, received_quantity FROM purchase_order_lines WHERE id = ? AND purchase_order_id = ?',
        [line['lineId'], id],
      );
      if (rows.isEmpty) {
        return _error(
          400,
          'receipt_line_not_found',
          'A received item does not belong to this purchase order.',
        );
      }
      final remaining =
          (rows.single['ordered_quantity'] as int) -
          (rows.single['received_quantity'] as int);
      if ((line['quantity'] as int) > remaining) {
        return _error(
          409,
          'receipt_quantity_exceeded',
          'A received quantity is greater than the amount still due.',
        );
      }
    }

    final now = DateTime.now().toUtc().toIso8601String();
    _database.execute('BEGIN IMMEDIATE');
    try {
      final retriedReceipt = _database.select(
        'SELECT purchase_order_id, payload FROM purchase_order_receipts WHERE id = ?',
        [receiptId],
      );
      if (retriedReceipt.isNotEmpty) {
        final previous = retriedReceipt.single;
        final matches =
            previous['purchase_order_id'] == id &&
            previous['payload'] == receiptPayload;
        _database.execute(matches ? 'COMMIT' : 'ROLLBACK');
        if (!matches) {
          return _error(
            409,
            'receipt_id_conflict',
            'This receipt ID already has different details.',
          );
        }
        return _json(200, {
          'receiptId': receiptId,
          'purchaseOrder': _purchaseOrderJson(id),
          'status': 'accepted',
        });
      }
      _database.execute(
        'INSERT INTO purchase_order_receipts (id, purchase_order_id, payload, received_by, received_at) VALUES (?, ?, ?, ?, ?)',
        [receiptId, id, receiptPayload, principal.userId, now],
      );
      for (final line in cleanLines) {
        final row = _database
            .select(
              '''
          SELECT product_id, ordered_quantity, received_quantity
          FROM purchase_order_lines WHERE id = ? AND purchase_order_id = ?
          ''',
              [line['lineId'], id],
            )
            .first;
        final quantity = line['quantity'] as int;
        final remaining =
            (row['ordered_quantity'] as int) -
            (row['received_quantity'] as int);
        if (quantity > remaining) {
          _database.execute('ROLLBACK');
          return _error(
            409,
            'receipt_quantity_exceeded',
            'A received quantity is greater than the amount still due.',
          );
        }
        _database.execute(
          'INSERT INTO purchase_order_receipt_lines (receipt_id, line_id, quantity) VALUES (?, ?, ?)',
          [receiptId, line['lineId'], quantity],
        );
        _database.execute(
          'UPDATE purchase_order_lines SET received_quantity = received_quantity + ? WHERE id = ?',
          [quantity, line['lineId']],
        );
        _changeStock(row['product_id'] as String, location, quantity);
        final movementId =
            'purchase-${_b64(crypto.sha256.convert(utf8.encode('$receiptId:${line['lineId']}')).bytes)}';
        _database.execute(
          '''
          INSERT INTO inventory_movements
            (id, product_id, type, quantity, source_location, destination_location,
             note, actor_user_id, created_at)
          VALUES (?, ?, 'receive', ?, NULL, ?, ?, ?, ?)
          ''',
          [
            movementId,
            row['product_id'],
            quantity,
            location,
            'Purchase order $id${note == null ? '' : ': $note'}',
            principal.userId,
            now,
          ],
        );
      }
      final received = _database.select(
        'SELECT COALESCE(SUM(ordered_quantity), 0) AS ordered, COALESCE(SUM(received_quantity), 0) AS received FROM purchase_order_lines WHERE purchase_order_id = ?',
        [id],
      ).single;
      final isComplete = received['ordered'] == received['received'];
      final nextStatus = isComplete ? 'received' : 'partially_received';
      _database.execute(
        'UPDATE purchase_orders SET status = ?, updated_at = ?, version = version + 1 WHERE id = ?',
        [nextStatus, now, id],
      );
      _audit(
        principal.userId,
        'purchase_order.received',
        'purchase_order',
        id,
        {'receiptId': receiptId, 'location': location, 'lines': cleanLines},
      );
      _database.execute('COMMIT');
    } on Object {
      _database.execute('ROLLBACK');
      return _error(
        500,
        'receipt_failed',
        'The received stock could not be saved.',
      );
    }
    return _json(201, {
      'receiptId': receiptId,
      'purchaseOrder': _purchaseOrderJson(id),
      'status': 'accepted',
    });
  }

  Future<Response> createProduct(Request request) async {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    if (!principal.canManageCatalog) return _forbidden();
    late final Map<String, Object?> body;
    try {
      body = await _readJsonObject(request);
    } on Object {
      return _error(400, 'invalid_product', 'Product details are malformed.');
    }
    final parsedProduct = _parseProduct(body, id: _newId());
    if (parsedProduct == null) {
      return _error(
        400,
        'invalid_product',
        'Enter a product name, category, and a non-negative price in cents.',
      );
    }
    final now = DateTime.now().toUtc();
    late final Product product;
    _database.execute('BEGIN IMMEDIATE');
    try {
      final categoryName = _ensureProductCategory(
        parsedProduct.category,
        principal.userId,
        now,
      );
      if (categoryName == null) {
        _database.execute('ROLLBACK');
        return _error(
          409,
          'category_archived',
          'Restore this category before assigning it to a product.',
        );
      }
      product = _copyProduct(parsedProduct, version: 1, category: categoryName);
      _insertProduct(product, now);
      _saveProductVersion(product, now);
      _incrementCatalogVersion();
      _audit(
        principal.userId,
        'catalog.product_created',
        'product',
        product.id,
        {'name': product.name},
      );
      _database.execute('COMMIT');
    } on Object {
      _database.execute('ROLLBACK');
      return _error(
        409,
        'product_code_conflict',
        'SKU or barcode is already in use.',
      );
    }
    return _json(201, _productJsonForDomain(product));
  }

  Future<Response> applyCatalogOperation(Request request) async {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    if (!principal.canManageCatalog) return _forbidden();
    late final Map<String, Object?> body;
    try {
      body = await _readJsonObject(request);
    } on Object {
      return _error(
        400,
        'invalid_catalog_operation',
        'The catalog edit is malformed.',
      );
    }
    final operationId = _requiredText(body['operationId'], 1, 128);
    final expectedVersion = body['expectedVersion'];
    final rawProduct = body['product'];
    if (operationId == null ||
        expectedVersion is! int ||
        expectedVersion < 0 ||
        rawProduct is! Map) {
      return _error(
        400,
        'invalid_catalog_operation',
        'The catalog edit is invalid.',
      );
    }
    final productJson = rawProduct.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final productId = _requiredText(productJson['id'], 1, 128);
    if (productId == null) {
      return _error(400, 'invalid_product', 'The product ID is invalid.');
    }
    final product = _parseProduct(productJson, id: productId);
    if (product == null) {
      return _error(400, 'invalid_product', 'Product details are invalid.');
    }
    final requestPayload = jsonEncode({
      'expectedVersion': expectedVersion,
      'product': product.toJson(),
    });

    _database.execute('BEGIN IMMEDIATE');
    try {
      final prior = _database.select(
        'SELECT request_payload, result_payload FROM catalog_operations WHERE id = ?',
        [operationId],
      );
      if (prior.isNotEmpty) {
        if (prior.first['request_payload'] != requestPayload) {
          _database.execute('ROLLBACK');
          return _error(
            409,
            'catalog_operation_id_conflict',
            'This catalog operation ID was already used for different data.',
          );
        }
        final result = jsonDecode(prior.first['result_payload'] as String);
        _database.execute('ROLLBACK');
        return _json(200, result);
      }

      final currentRows = _database.select(
        'SELECT * FROM products WHERE id = ?',
        [productId],
      );
      final current = currentRows.isEmpty
          ? null
          : Product.fromJson(_productJson(currentRows.first));
      if ((expectedVersion == 0 && current != null) ||
          (expectedVersion > 0 &&
              (current == null || current.version != expectedVersion))) {
        _database.execute('ROLLBACK');
        return _catalogVersionConflict(current);
      }

      final now = DateTime.now().toUtc();
      final categoryName = _ensureProductCategory(
        product.category,
        principal.userId,
        now,
      );
      if (categoryName == null) {
        _database.execute('ROLLBACK');
        return _error(
          409,
          'category_archived',
          'Restore this category before assigning it to a product.',
        );
      }
      final savedProduct = _copyProduct(
        product,
        version: expectedVersion == 0 ? 1 : expectedVersion + 1,
        category: categoryName,
      );
      if (current == null) {
        _insertProduct(savedProduct, now);
      } else {
        _database.execute(
          'UPDATE products SET name = ?, category = ?, sku = ?, barcode = ?, unit_price_cents = ?, is_active = ?, version = ?, modifier_groups_json = ?, updated_at = ? WHERE id = ?',
          [
            savedProduct.name,
            savedProduct.category,
            savedProduct.sku,
            savedProduct.barcode,
            savedProduct.unitPriceCents,
            savedProduct.isActive ? 1 : 0,
            savedProduct.version,
            jsonEncode(
              savedProduct.modifierGroups
                  .map((group) => group.toJson())
                  .toList(),
            ),
            now.toIso8601String(),
            productId,
          ],
        );
      }
      _saveProductVersion(savedProduct, now);
      _incrementCatalogVersion();
      _audit(
        principal.userId,
        current == null ? 'catalog.product_created' : 'catalog.product_updated',
        'product',
        productId,
        {'name': savedProduct.name, 'version': savedProduct.version},
      );
      final currentCatalogVersion = catalogVersion!;
      final result = {
        'operationId': operationId,
        'catalogVersion': currentCatalogVersion,
        'product': savedProduct.toJson(),
      };
      _database.execute(
        'INSERT INTO catalog_operations (id, request_payload, result_payload, created_at) VALUES (?, ?, ?, ?)',
        [
          operationId,
          requestPayload,
          jsonEncode(result),
          now.toIso8601String(),
        ],
      );
      _database.execute('COMMIT');
      return _json(current == null ? 201 : 200, result);
    } on Object {
      _database.execute('ROLLBACK');
      return _error(
        409,
        'product_code_conflict',
        'SKU or barcode is already in use.',
      );
    }
  }

  Response _catalogVersionConflict(Product? current) => _json(409, {
    'error': 'catalog_version_conflict',
    'message': 'The product changed on another register.',
    if (current != null) 'currentProduct': current.toJson(),
  });

  Future<Response> updateProduct(Request request, String id) async {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    if (!principal.canManageCatalog) return _forbidden();
    late final Map<String, Object?> body;
    try {
      body = await _readJsonObject(request);
    } on Object {
      return _error(400, 'invalid_product', 'Product details are malformed.');
    }
    final product = _parseProduct(body, id: id);
    if (product == null) {
      return _error(400, 'invalid_product', 'Product details are invalid.');
    }
    final existing = _database.select(
      'SELECT version FROM products WHERE id = ?',
      [id],
    );
    if (existing.isEmpty) {
      return _error(404, 'product_not_found', 'No product has this ID.');
    }
    final nextVersion = (existing.first['version'] as int) + 1;
    final now = DateTime.now().toUtc();
    _database.execute('BEGIN IMMEDIATE');
    late final Product savedProduct;
    try {
      final categoryName = _ensureProductCategory(
        product.category,
        principal.userId,
        now,
      );
      if (categoryName == null) {
        _database.execute('ROLLBACK');
        return _error(
          409,
          'category_archived',
          'Restore this category before assigning it to a product.',
        );
      }
      savedProduct = _copyProduct(
        product,
        version: nextVersion,
        category: categoryName,
      );
      _database.execute(
        'UPDATE products SET name = ?, category = ?, sku = ?, barcode = ?, unit_price_cents = ?, is_active = ?, version = ?, modifier_groups_json = ?, updated_at = ? WHERE id = ?',
        [
          savedProduct.name,
          savedProduct.category,
          savedProduct.sku,
          savedProduct.barcode,
          savedProduct.unitPriceCents,
          savedProduct.isActive ? 1 : 0,
          savedProduct.version,
          jsonEncode(
            savedProduct.modifierGroups.map((group) => group.toJson()).toList(),
          ),
          now.toIso8601String(),
          id,
        ],
      );
      _saveProductVersion(savedProduct, now);
      _incrementCatalogVersion();
      _audit(principal.userId, 'catalog.product_updated', 'product', id, {
        'name': savedProduct.name,
        'isActive': savedProduct.isActive,
        'version': savedProduct.version,
      });
      _database.execute('COMMIT');
    } on Object {
      _database.execute('ROLLBACK');
      return _error(
        409,
        'product_code_conflict',
        'SKU or barcode is already in use.',
      );
    }
    return _json(200, _productJsonForDomain(savedProduct));
  }

  Response listUsers(Request request) {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    if (principal.role != AccountRole.admin) return _forbidden();
    final users = _database.select(
      'SELECT id, name, email, role FROM users WHERE is_active = 1 ORDER BY name COLLATE NOCASE',
    );
    return _json(200, {
      'users': users.map((row) => _userJson(row)).toList(growable: false),
    });
  }

  Future<Response> createUser(Request request) async {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    if (principal.role != AccountRole.admin) return _forbidden();
    late final Map<String, Object?> body;
    try {
      body = await _readJsonObject(request);
    } on Object {
      return _error(400, 'invalid_user', 'Staff details are malformed.');
    }
    final name = _requiredText(body['name'], 2, 100);
    final email = _normalizedEmail(body['email']);
    final password = body['password'];
    final roleValue = body['role'];
    final role = roleValue == 'manager' || roleValue == 'cashier'
        ? roleValue as String
        : null;
    if (name == null ||
        email == null ||
        !_validPassword(password) ||
        role == null) {
      return _error(
        400,
        'invalid_user',
        'Enter a name, valid email, manager or cashier role, and password with at least 12 characters.',
      );
    }
    final id = _newId();
    final salt = _randomBytes(16);
    final hash = await _hashPassword(password as String, salt);
    try {
      _database.execute(
        'INSERT INTO users (id, name, email, password_salt, password_hash, role, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          id,
          name,
          email,
          _b64(salt),
          _b64(hash),
          role,
          DateTime.now().toUtc().toIso8601String(),
        ],
      );
    } on Object {
      return _error(409, 'email_in_use', 'An account already uses this email.');
    }
    _audit(principal.userId, 'team.user_created', 'user', id, {'role': role});
    final row = _database.select(
      'SELECT id, name, email, role FROM users WHERE id = ?',
      [id],
    ).first;
    return _json(201, _userJson(row));
  }

  Response listAuditEvents(Request request) {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    if (principal.role != AccountRole.admin) return _forbidden();
    final rows = _database.select('''
      SELECT a.id, a.actor_user_id, u.name AS actor_name, a.event_type,
        a.entity_type, a.entity_id, a.details, a.created_at
      FROM audit_events a
      LEFT JOIN users u ON u.id = a.actor_user_id
      ORDER BY a.created_at DESC, a.id DESC
      LIMIT 100
    ''');
    return _json(200, {
      'events': rows
          .map(
            (row) => {
              'id': row['id'],
              'actorUserId': row['actor_user_id'],
              'actorName': row['actor_name'],
              'eventType': row['event_type'],
              'entityType': row['entity_type'],
              'entityId': row['entity_id'],
              'details': jsonDecode(row['details'] as String),
              'createdAt': row['created_at'],
            },
          )
          .toList(growable: false),
    });
  }

  Response operationalHealth(Request request) {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    if (principal.role != AccountRole.admin) return _forbidden();
    final integrityRows = _database.select('PRAGMA integrity_check');
    final integrity = integrityRows.isEmpty
        ? 'unavailable'
        : integrityRows.first.values.first.toString();
    final latestCursor =
        _database
                .select(
                  'SELECT COALESCE(MAX(cursor), 0) AS cursor FROM sync_events',
                )
                .first['cursor']
            as int;
    final minimumAck =
        _database.select('''
      SELECT MIN(COALESCE(sync_cursors.cursor, 0)) AS cursor
      FROM registers
      LEFT JOIN sync_cursors ON sync_cursors.register_id = registers.id
    ''').first['cursor']
            as int? ??
        latestCursor;
    final pendingEvents =
        _database.select(
              'SELECT COUNT(*) AS count FROM sync_events WHERE cursor > ?',
              [minimumAck],
            ).first['count']
            as int;
    final oldestPending = _database.select(
      'SELECT MIN(created_at) AS created_at FROM sync_events WHERE cursor > ?',
      [minimumAck],
    ).first['created_at'];
    final catalog =
        _database
                .select('SELECT version FROM catalog_meta WHERE singleton = 1')
                .first['version']
            as int;
    final registerCount =
        _database
                .select('SELECT COUNT(*) AS count FROM registers')
                .first['count']
            as int;
    return _json(200, {
      'status': integrity == 'ok' ? 'ok' : 'degraded',
      'databaseIntegrity': integrity,
      'schemaVersion': schemaVersion,
      'catalogVersion': catalog,
      'registerCount': registerCount,
      'sync': {
        'latestCursor': latestCursor,
        'minimumAcknowledgedCursor': minimumAck,
        'pendingEventCount': pendingEvents,
        'oldestPendingEventAt': oldestPending,
      },
      'checkedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Response readiness(Request request) {
    try {
      final integrityRows = _database.select('PRAGMA quick_check(1)');
      final integrity = integrityRows.isEmpty
          ? 'unavailable'
          : integrityRows.first.values.first.toString();
      final version = schemaVersion;
      final ready = integrity == 'ok' && version == currentSchemaVersion;
      return _json(ready ? 200 : 503, {
        'status': ready ? 'ready' : 'degraded',
        'databaseIntegrity': integrity,
        'schemaVersion': version,
      });
    } on Object {
      return _json(503, {'status': 'unavailable'});
    }
  }

  Future<Response> enrollRegister(Request request) async {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    late final Map<String, Object?> body;
    try {
      body = await _readJsonObject(request);
    } on Object {
      return _error(400, 'invalid_register', 'Register details are malformed.');
    }
    final id = _requiredText(body['id'], 1, 128);
    final name = _requiredText(body['name'], 1, 80);
    if (id == null || name == null) {
      return _error(400, 'invalid_register', 'Enter a register ID and name.');
    }
    final existing = _database.select(
      'SELECT id, name FROM registers WHERE id = ?',
      [id],
    );
    if (existing.isNotEmpty) {
      if (existing.first['name'] != name) {
        return _error(
          409,
          'register_id_conflict',
          'This register ID already has a different name.',
        );
      }
      return _json(200, {'id': id, 'name': name, 'status': 'enrolled'});
    }
    _database.execute(
      'INSERT INTO registers (id, name, registered_at) VALUES (?, ?, ?)',
      [id, name, DateTime.now().toUtc().toIso8601String()],
    );
    _audit(principal.userId, 'register.enrolled', 'register', id, {
      'name': name,
    });
    return _json(201, {'id': id, 'name': name, 'status': 'enrolled'});
  }

  Response getTaxSettings(Request request) {
    if (_principal(request) == null) return _unauthorized();
    return _json(200, _taxJson());
  }

  Response listSyncEvents(Request request) {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    final registerId = _requiredText(
      request.url.queryParameters['registerId'],
      1,
      128,
    );
    if (registerId == null ||
        _database.select('SELECT id FROM registers WHERE id = ?', [
          registerId,
        ]).isEmpty) {
      return _error(
        404,
        'register_not_found',
        'This register is not enrolled.',
      );
    }

    final afterText = request.url.queryParameters['after'];
    final requestedCursor = afterText == null ? null : int.tryParse(afterText);
    if (afterText != null && requestedCursor == null) {
      return _error(400, 'invalid_sync_cursor', 'The sync cursor is invalid.');
    }
    final cursorRows = _database.select(
      'SELECT cursor FROM sync_cursors WHERE register_id = ?',
      [registerId],
    );
    final after =
        requestedCursor ??
        (cursorRows.isEmpty ? 0 : cursorRows.first['cursor'] as int);
    final limit =
        (int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 100).clamp(
          1,
          500,
        );
    if (after < 0) {
      return _error(400, 'invalid_sync_cursor', 'The sync cursor is invalid.');
    }
    final rows = _database.select(
      'SELECT cursor, id, schema_version, event_type, entity_type, entity_id, payload, created_at FROM sync_events WHERE cursor > ? ORDER BY cursor LIMIT ?',
      [after, limit + 1],
    );
    final hasMore = rows.length > limit;
    final page = hasMore ? rows.take(limit).toList(growable: false) : rows;
    final nextCursor = page.isEmpty ? after : page.last['cursor'] as int;
    return _json(200, {
      'events': page
          .map(
            (row) => {
              'cursor': row['cursor'],
              'id': row['id'],
              'schemaVersion': row['schema_version'],
              'type': row['event_type'],
              'entityType': row['entity_type'],
              'entityId': row['entity_id'],
              'data': jsonDecode(row['payload'] as String),
              'createdAt': row['created_at'],
            },
          )
          .toList(growable: false),
      'nextCursor': nextCursor,
      'hasMore': hasMore,
    });
  }

  Future<Response> acknowledgeSyncCursor(Request request) async {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    late final Map<String, Object?> body;
    try {
      body = await _readJsonObject(request);
    } on Object {
      return _error(
        400,
        'invalid_sync_ack',
        'The sync acknowledgement is malformed.',
      );
    }
    final registerId = _requiredText(body['registerId'], 1, 128);
    final cursor = body['cursor'];
    if (registerId == null || cursor is! int || cursor < 0) {
      return _error(
        400,
        'invalid_sync_ack',
        'The sync acknowledgement is invalid.',
      );
    }
    final register = _database.select('SELECT id FROM registers WHERE id = ?', [
      registerId,
    ]);
    if (register.isEmpty) {
      return _error(
        404,
        'register_not_found',
        'This register is not enrolled.',
      );
    }
    final maximum =
        _database
                .select(
                  'SELECT COALESCE(MAX(cursor), 0) AS cursor FROM sync_events',
                )
                .first['cursor']
            as int;
    final previousRows = _database.select(
      'SELECT cursor FROM sync_cursors WHERE register_id = ?',
      [registerId],
    );
    final previous = previousRows.isEmpty
        ? 0
        : previousRows.first['cursor'] as int;
    if (cursor < previous || cursor > maximum) {
      return _error(
        409,
        'sync_cursor_conflict',
        'The acknowledged cursor is outside the valid range.',
      );
    }
    _database.execute(
      '''
      INSERT INTO sync_cursors (register_id, cursor, acknowledged_at)
      VALUES (?, ?, ?)
      ON CONFLICT(register_id) DO UPDATE SET
        cursor = excluded.cursor, acknowledged_at = excluded.acknowledged_at
      ''',
      [registerId, cursor, DateTime.now().toUtc().toIso8601String()],
    );
    return _json(200, {'registerId': registerId, 'cursor': cursor});
  }

  Future<Response> setTaxSettings(Request request) async {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    if (!principal.canManageCatalog) return _forbidden();
    late final Map<String, Object?> body;
    try {
      body = await _readJsonObject(request);
    } on Object {
      return _error(400, 'invalid_tax', 'Tax settings are malformed.');
    }
    late final TaxConfig tax;
    try {
      tax = TaxConfig.fromJson(body);
    } on Object {
      return _error(
        400,
        'invalid_tax',
        'Enter a tax name and rate from 0% to 100%.',
      );
    }
    final version =
        (_database
                .select('SELECT version FROM tax_settings WHERE singleton = 1')
                .first['version']
            as int) +
        1;
    final now = DateTime.now().toUtc().toIso8601String();
    _database.execute('BEGIN IMMEDIATE');
    try {
      _database.execute(
        'UPDATE tax_settings SET name = ?, rate_basis_points = ?, prices_include_tax = ?, version = ? WHERE singleton = 1',
        [
          tax.name.trim(),
          tax.rateBasisPoints,
          tax.pricesIncludeTax ? 1 : 0,
          version,
        ],
      );
      _database.execute(
        'INSERT INTO tax_config_versions (version, name, rate_basis_points, prices_include_tax, created_at) VALUES (?, ?, ?, ?, ?)',
        [
          version,
          tax.name.trim(),
          tax.rateBasisPoints,
          tax.pricesIncludeTax ? 1 : 0,
          now,
        ],
      );
      _audit(
        principal.userId,
        'tax.settings_updated',
        'tax_settings',
        '1',
        TaxConfig(
          name: tax.name.trim(),
          rateBasisPoints: tax.rateBasisPoints,
          pricesIncludeTax: tax.pricesIncludeTax,
          version: version,
        ).toJson(),
      );
      _database.execute('COMMIT');
    } on Object {
      _database.execute('ROLLBACK');
      return _error(
        500,
        'tax_update_failed',
        'Tax settings could not be saved.',
      );
    }
    return _json(200, _taxJson());
  }

  Map<String, Object?> _taxJson() {
    final row = _database
        .select(
          'SELECT name, rate_basis_points, prices_include_tax, version FROM tax_settings WHERE singleton = 1',
        )
        .first;
    return TaxConfig(
      name: row['name'] as String,
      rateBasisPoints: row['rate_basis_points'] as int,
      pricesIncludeTax: row['prices_include_tax'] == 1,
      version: row['version'] as int,
    ).toJson();
  }

  Response getLoyaltySettings(Request request) {
    if (_principal(request) == null) return _unauthorized();
    return _json(200, _loyaltyJson());
  }

  Future<Response> setLoyaltySettings(Request request) async {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    if (!principal.canManageCatalog) return _forbidden();
    late final Map<String, Object?> body;
    try {
      body = await _readJsonObject(request);
    } on Object {
      return _error(
        400,
        'invalid_loyalty_settings',
        'Loyalty settings are malformed.',
      );
    }
    late final LoyaltyConfig loyalty;
    try {
      loyalty = LoyaltyConfig.fromJson(body);
    } on Object {
      return _error(
        400,
        'invalid_loyalty_settings',
        'Enter valid earning and redemption rates.',
      );
    }
    final version =
        (_database
                .select(
                  'SELECT version FROM loyalty_settings WHERE singleton = 1',
                )
                .first['version']
            as int) +
        1;
    final now = DateTime.now().toUtc().toIso8601String();
    _database.execute('BEGIN IMMEDIATE');
    try {
      _database.execute(
        'UPDATE loyalty_settings SET earn_points_per_100_cents = ?, redeem_cents_per_point = ?, version = ? WHERE singleton = 1',
        [loyalty.earnPointsPer100Cents, loyalty.redeemCentsPerPoint, version],
      );
      _database.execute(
        'INSERT INTO loyalty_config_versions (version, earn_points_per_100_cents, redeem_cents_per_point, created_at) VALUES (?, ?, ?, ?)',
        [
          version,
          loyalty.earnPointsPer100Cents,
          loyalty.redeemCentsPerPoint,
          now,
        ],
      );
      _audit(
        principal.userId,
        'loyalty.settings_updated',
        'loyalty_settings',
        '1',
        LoyaltyConfig(
          earnPointsPer100Cents: loyalty.earnPointsPer100Cents,
          redeemCentsPerPoint: loyalty.redeemCentsPerPoint,
          version: version,
        ).toJson(),
      );
      _database.execute('COMMIT');
    } on Object {
      _database.execute('ROLLBACK');
      return _error(
        500,
        'loyalty_update_failed',
        'Loyalty settings could not be saved.',
      );
    }
    return _json(200, _loyaltyJson());
  }

  Map<String, Object?> _loyaltyJson() {
    final row = _database
        .select(
          'SELECT earn_points_per_100_cents, redeem_cents_per_point, version FROM loyalty_settings WHERE singleton = 1',
        )
        .first;
    return LoyaltyConfig(
      earnPointsPer100Cents: row['earn_points_per_100_cents'] as int,
      redeemCentsPerPoint: row['redeem_cents_per_point'] as int,
      version: row['version'] as int,
    ).toJson();
  }

  Response listCustomers(Request request) {
    if (_principal(request) == null) return _unauthorized();
    final rows = _database.select(
      'SELECT id, name, phone, email, loyalty_points FROM customers ORDER BY name COLLATE NOCASE LIMIT 500',
    );
    return _json(200, {
      'customers': rows.map(_customerJson).toList(growable: false),
    });
  }

  Future<Response> createCustomer(Request request) async {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    late final Map<String, Object?> body;
    try {
      body = await _readJsonObject(request);
    } on Object {
      return _error(400, 'invalid_customer', 'Customer details are malformed.');
    }
    final name = _requiredText(body['name'], 1, 120);
    final phone = body['phone'] == null
        ? null
        : _requiredText(body['phone'], 3, 40);
    final email = body['email'] == null
        ? null
        : _normalizedEmail(body['email']);
    if (name == null ||
        (body['phone'] != null && phone == null) ||
        (body['email'] != null && email == null)) {
      return _error(
        400,
        'invalid_customer',
        'Enter a customer name and valid contact details.',
      );
    }
    final id = _newId();
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      _database.execute(
        'INSERT INTO customers (id, name, phone, email, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        [id, name, phone, email, now, now],
      );
    } on Object {
      return _error(
        409,
        'customer_contact_in_use',
        'A customer already uses that phone or email.',
      );
    }
    _audit(principal.userId, 'customer.created', 'customer', id, {
      'name': name,
    });
    return _json(
      201,
      _customerJson(
        _database.select(
          'SELECT id, name, phone, email, loyalty_points FROM customers WHERE id = ?',
          [id],
        ).first,
      ),
    );
  }

  Future<Response> updateCustomer(Request request, String id) async {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    if (!principal.canManageCatalog) return _forbidden();
    late final Map<String, Object?> body;
    try {
      body = await _readJsonObject(request);
    } on Object {
      return _error(400, 'invalid_customer', 'Customer details are malformed.');
    }
    final name = _requiredText(body['name'], 1, 120);
    final phone = body['phone'] == null
        ? null
        : _requiredText(body['phone'], 3, 40);
    final email = body['email'] == null
        ? null
        : _normalizedEmail(body['email']);
    if (name == null ||
        (body['phone'] != null && phone == null) ||
        (body['email'] != null && email == null)) {
      return _error(
        400,
        'invalid_customer',
        'Enter a customer name and valid contact details.',
      );
    }
    try {
      if (_database.select('SELECT id FROM customers WHERE id = ?', [
        id,
      ]).isEmpty) {
        return _error(404, 'customer_not_found', 'No customer has this ID.');
      }
      _database.execute(
        'UPDATE customers SET name = ?, phone = ?, email = ?, updated_at = ? WHERE id = ?',
        [name, phone, email, DateTime.now().toUtc().toIso8601String(), id],
      );
    } on Object {
      return _error(
        409,
        'customer_contact_in_use',
        'A customer already uses that phone or email.',
      );
    }
    _audit(principal.userId, 'customer.updated', 'customer', id, {
      'name': name,
    });
    return _json(
      200,
      _customerJson(
        _database.select(
          'SELECT id, name, phone, email, loyalty_points FROM customers WHERE id = ?',
          [id],
        ).first,
      ),
    );
  }

  Map<String, Object?> _customerJson(Row row) => Customer(
    id: row['id'] as String,
    name: row['name'] as String,
    phone: row['phone'] as String?,
    email: row['email'] as String?,
    loyaltyPoints: row['loyalty_points'] as int,
  ).toJson();

  Future<Response> acceptSale(Request request) async {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    late final Sale sale;
    try {
      final body = await _readBoundedBody(request, 1024 * 1024);
      final json = jsonDecode(body) as Map<String, Object?>;
      sale = Sale.fromJson(json);
    } on RequestBodyTooLarge {
      return _error(
        413,
        'sale_too_large',
        'Sale payload exceeds one megabyte.',
      );
    } on FormatException catch (error) {
      return _error(400, 'invalid_sale', error.message);
    } on Object {
      return _error(
        400,
        'invalid_sale',
        'Sale payload is missing or malformed.',
      );
    }

    final payload = jsonEncode(sale.toJson());
    final existing = _database.select(
      'SELECT payload FROM sales WHERE id = ?',
      [sale.id],
    );
    if (existing.isNotEmpty) {
      var same = false;
      try {
        same =
            jsonEncode(
              Sale.fromJson(
                (jsonDecode(existing.first['payload'] as String) as Map).map(
                  (key, value) => MapEntry(key.toString(), value),
                ),
              ).toJson(),
            ) ==
            payload;
      } on Object {
        same = false;
      }
      if (!same) {
        return _error(
          409,
          'sale_id_conflict',
          'This sale ID has already been used for different sale data.',
        );
      }
      return _json(200, {'id': sale.id, 'status': 'accepted'});
    }
    if (sale.discountCents > 0 && !principal.canManageCatalog) {
      return _forbidden();
    }
    final registerId = sale.registerId ?? 'main';
    if (_database.select('SELECT id FROM registers WHERE id = ?', [
      registerId,
    ]).isEmpty) {
      return _error(
        409,
        'register_not_enrolled',
        'Enroll this register before syncing sales.',
      );
    }
    if (sale.shiftId != null &&
        _database.select(
          'SELECT id FROM cash_shifts WHERE id = ? AND register_id = ?',
          [sale.shiftId, registerId],
        ).isEmpty) {
      return _error(
        409,
        'shift_not_found',
        'The cash shift linked to this sale does not belong to this register.',
      );
    }
    final catalogSnapshotError = _validateSaleCatalogSnapshots(sale);
    if (catalogSnapshotError != null) {
      return _error(409, 'catalog_snapshot_invalid', catalogSnapshotError);
    }
    final taxVersion = _database.select(
      'SELECT name, rate_basis_points, prices_include_tax FROM tax_config_versions WHERE version = ?',
      [sale.taxConfigVersion],
    );
    if (taxVersion.isEmpty ||
        taxVersion.first['name'] != sale.taxName ||
        taxVersion.first['rate_basis_points'] != sale.taxRateBasisPoints ||
        (taxVersion.first['prices_include_tax'] == 1) !=
            sale.taxIncludedInPrice) {
      return _error(
        409,
        'tax_snapshot_invalid',
        'The sale tax snapshot does not match a configured tax version.',
      );
    }
    if (sale.pointsRedeemed > 0 || sale.customerId != null) {
      if (sale.customerId == null ||
          _database.select('SELECT id FROM customers WHERE id = ?', [
            sale.customerId,
          ]).isEmpty) {
        return _error(
          409,
          'customer_not_found',
          'The customer linked to this sale does not exist.',
        );
      }
    }
    final loyaltyRows = _database.select(
      'SELECT earn_points_per_100_cents, redeem_cents_per_point FROM loyalty_config_versions WHERE version = ?',
      [sale.loyaltyConfigVersion],
    );
    if (loyaltyRows.isEmpty) {
      return _error(
        409,
        'loyalty_snapshot_invalid',
        'The sale loyalty snapshot does not match a configured program version.',
      );
    }
    final loyaltyRow = loyaltyRows.first;
    final redeemValue = loyaltyRow['redeem_cents_per_point'] as int;
    final redemptionValue =
        BigInt.from(sale.pointsRedeemed) * BigInt.from(redeemValue);
    if (redemptionValue > BigInt.from(9007199254740991) ||
        redemptionValue.toInt() != sale.loyaltyDiscountCents) {
      return _error(
        409,
        'loyalty_redemption_mismatch',
        'The loyalty redemption no longer matches the current program.',
      );
    }
    if (sale.pointsRedeemed > 0) {
      final customer = _database.select(
        'SELECT loyalty_points FROM customers WHERE id = ?',
        [sale.customerId],
      ).first;
      if ((customer['loyalty_points'] as int) < sale.pointsRedeemed) {
        return _error(
          409,
          'insufficient_loyalty_points',
          'The customer no longer has enough loyalty points.',
        );
      }
    }
    final pointsEarned = sale.customerId == null
        ? 0
        : ((BigInt.from(sale.subtotalCents - sale.discountCents) *
                      BigInt.from(
                        loyaltyRow['earn_points_per_100_cents'] as int,
                      )) ~/
                  BigInt.from(100))
              .toInt();
    _database.execute('BEGIN IMMEDIATE');
    try {
      _database.execute(
        'INSERT INTO sales (id, created_at, total_cents, shift_id, payload, points_earned) VALUES (?, ?, ?, ?, ?, ?)',
        [
          sale.id,
          sale.createdAt.toIso8601String(),
          sale.totalCents,
          sale.shiftId,
          payload,
          pointsEarned,
        ],
      );
      final soldQuantities = <String, int>{};
      for (final line in sale.lines) {
        soldQuantities.update(
          line.productId,
          (quantity) => quantity + line.quantity,
          ifAbsent: () => line.quantity,
        );
      }
      for (final entry in soldQuantities.entries) {
        final product = _database.select(
          'SELECT id FROM products WHERE id = ?',
          [entry.key],
        );
        if (product.isEmpty) continue;
        final movementId = _saleStockMovementId(sale.id, entry.key);
        _changeStock(entry.key, 'Main', -entry.value);
        _database.execute(
          '''
          INSERT OR IGNORE INTO inventory_movements
            (id, product_id, type, quantity, source_location, destination_location, note, actor_user_id, created_at)
          VALUES (?, ?, 'sale', ?, 'Main', NULL, ?, ?, ?)
        ''',
          [
            movementId,
            entry.key,
            -entry.value,
            'Sale ${sale.id}',
            principal.userId,
            sale.createdAt.toIso8601String(),
          ],
        );
      }
      if (sale.customerId != null) {
        _database.execute(
          'UPDATE customers SET loyalty_points = loyalty_points - ? + ?, updated_at = ? WHERE id = ?',
          [
            sale.pointsRedeemed,
            pointsEarned,
            DateTime.now().toUtc().toIso8601String(),
            sale.customerId,
          ],
        );
        if (sale.pointsRedeemed > 0) {
          _database.execute(
            'INSERT INTO loyalty_events (id, customer_id, sale_id, points_delta, note, created_at) VALUES (?, ?, ?, ?, ?, ?)',
            [
              _newId(),
              sale.customerId,
              sale.id,
              -sale.pointsRedeemed,
              'redeemed',
              DateTime.now().toUtc().toIso8601String(),
            ],
          );
        }
        if (pointsEarned > 0) {
          _database.execute(
            'INSERT INTO loyalty_events (id, customer_id, sale_id, points_delta, note, created_at) VALUES (?, ?, ?, ?, ?, ?)',
            [
              _newId(),
              sale.customerId,
              sale.id,
              pointsEarned,
              'earned',
              DateTime.now().toUtc().toIso8601String(),
            ],
          );
        }
      }
      _audit(principal.userId, 'sale.accepted', 'sale', sale.id, {
        'totalCents': sale.totalCents,
        'lineCount': sale.lines.length,
        'shiftId': sale.shiftId,
        'registerId': registerId,
        'discountCents': sale.discountCents,
        'taxCents': sale.taxCents,
        'customerId': sale.customerId,
        'pointsEarned': pointsEarned,
      });
      if (sale.shiftId != null) _refreshShiftExpected(sale.shiftId!);
      _database.execute('COMMIT');
    } on Object {
      _database.execute('ROLLBACK');
      return _error(500, 'sale_save_failed', 'The sale could not be saved.');
    }
    return _json(201, {'id': sale.id, 'status': 'accepted'});
  }

  Future<Response> recordPayment(Request request, String saleId) async {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    late final PaymentRecord payment;
    try {
      final body = await _readBoundedBody(request, 64 * 1024);
      payment = PaymentRecord.fromJson(
        jsonDecode(body) as Map<String, Object?>,
      );
    } on RequestBodyTooLarge {
      return _error(413, 'payment_too_large', 'Payment payload is too large.');
    } on FormatException catch (error) {
      return _error(400, 'invalid_payment', error.message);
    } on Object {
      return _error(400, 'invalid_payment', 'Payment details are malformed.');
    }
    if (payment.saleId != saleId ||
        payment.provider != 'cash' ||
        payment.method != 'cash' ||
        payment.status != PaymentStatus.captured ||
        payment.currency != 'PHP') {
      return _error(
        400,
        'unsupported_payment',
        'This deployment currently accepts captured cash payments.',
      );
    }
    final saleRows = _database.select(
      'SELECT total_cents, payload, voided_at FROM sales WHERE id = ?',
      [saleId],
    );
    if (saleRows.isEmpty) {
      return _error(
        409,
        'sale_not_synced',
        'Sync the sale before syncing its payment record.',
      );
    }
    final sale = Sale.fromJson(
      (jsonDecode(saleRows.first['payload'] as String) as Map).map(
        (key, value) => MapEntry(key.toString(), value),
      ),
    );
    if (payment.amountCents != sale.totalCents ||
        payment.tenderedCents != sale.tenderedCents ||
        payment.changeCents != sale.changeCents) {
      return _error(
        409,
        'payment_amount_mismatch',
        'Payment amounts do not match the sale.',
      );
    }
    final existing = _database.select(
      'SELECT payload FROM payment_records WHERE sale_id = ?',
      [saleId],
    );
    if (existing.isNotEmpty) {
      final saved = PaymentRecord.fromJson(
        (jsonDecode(existing.first['payload'] as String) as Map).map(
          (key, value) => MapEntry(key.toString(), value),
        ),
      );
      if (saved.id != payment.id ||
          saved.provider != payment.provider ||
          saved.method != payment.method ||
          saved.amountCents != payment.amountCents ||
          saved.tenderedCents != payment.tenderedCents ||
          saved.changeCents != payment.changeCents) {
        return _error(
          409,
          'payment_id_conflict',
          'A different payment record already exists for this sale.',
        );
      }
      return _json(200, {
        'id': saved.id,
        'saleId': saleId,
        'status': saved.status.value,
      });
    }

    final refunds =
        _database.select(
              'SELECT COALESCE(SUM(refund_cents), 0) AS total FROM returns WHERE sale_id = ?',
              [saleId],
            ).first['total']
            as int;
    var savedPayment = payment.withRefundedCents(
      refunds,
      updatedAt: DateTime.now().toUtc(),
    );
    if (saleRows.first['voided_at'] != null) {
      savedPayment = savedPayment.withStatus(
        PaymentStatus.voided,
        updatedAt: DateTime.now().toUtc(),
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    _database.execute('BEGIN IMMEDIATE');
    try {
      _database.execute(
        'INSERT INTO payment_records (id, sale_id, status, payload, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        [
          savedPayment.id,
          saleId,
          savedPayment.status.value,
          jsonEncode(savedPayment.toJson()),
          savedPayment.createdAt.toIso8601String(),
          now,
        ],
      );
      _audit(principal.userId, 'payment.captured', 'payment', savedPayment.id, {
        'saleId': saleId,
        'amountCents': savedPayment.amountCents,
        'provider': savedPayment.provider,
        'status': savedPayment.status.value,
      });
      _database.execute('COMMIT');
    } on Object {
      _database.execute('ROLLBACK');
      return _error(
        409,
        'payment_save_failed',
        'The payment could not be saved.',
      );
    }
    return _json(201, {
      'id': savedPayment.id,
      'saleId': saleId,
      'status': savedPayment.status.value,
    });
  }

  Response getPayment(Request request, String saleId) {
    if (_principal(request) == null) return _unauthorized();
    final rows = _database.select(
      'SELECT payload FROM payment_records WHERE sale_id = ?',
      [saleId],
    );
    if (rows.isEmpty) {
      return _error(
        404,
        'payment_not_found',
        'No payment has synced for this sale.',
      );
    }
    return _json(
      200,
      (jsonDecode(rows.first['payload'] as String) as Map).map(
        (key, value) => MapEntry(key.toString(), value),
      ),
    );
  }

  Response getSale(Request request, String id) {
    if (_principal(request) == null) return _unauthorized();
    final rows = _database.select('SELECT payload FROM sales WHERE id = ?', [
      id,
    ]);
    if (rows.isEmpty) {
      return _error(404, 'sale_not_found', 'No sale has this ID.');
    }
    final sale = (jsonDecode(rows.first['payload'] as String) as Map).map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final status = _database.select(
      'SELECT voided_at, void_reason, points_earned FROM sales WHERE id = ?',
      [id],
    ).first;
    final returns = _database.select(
      'SELECT id, refund_cents, reason, created_at FROM returns WHERE sale_id = ? ORDER BY created_at',
      [id],
    );
    if (status['voided_at'] == null && returns.isEmpty) {
      return _json(200, sale);
    }
    return _json(200, {
      ...sale,
      'voidedAt': status['voided_at'],
      'voidReason': status['void_reason'],
      'pointsEarned': status['points_earned'],
      'returns': returns
          .map(
            (row) => {
              'id': row['id'],
              'refundCents': row['refund_cents'],
              'reason': row['reason'],
              'createdAt': row['created_at'],
            },
          )
          .toList(growable: false),
      'returnQuantities': _returnQuantities(id),
      'returnQuantitiesByLine': _returnQuantitiesByLine(id),
    });
  }

  Response listSales(Request request) {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    final rows = _database.select(
      'SELECT id, created_at, total_cents, shift_id, payload, voided_at, void_reason, points_earned FROM sales ORDER BY created_at DESC LIMIT 100',
    );
    return _json(200, {
      'sales': rows
          .map((row) {
            final sale = (jsonDecode(row['payload'] as String) as Map).map(
              (key, value) => MapEntry(key.toString(), value),
            );
            final returnRows = _database.select(
              'SELECT id, refund_cents, reason, created_at FROM returns WHERE sale_id = ? ORDER BY created_at',
              [row['id']],
            );
            return {
              ...sale,
              'voidedAt': row['voided_at'],
              'voidReason': row['void_reason'],
              'pointsEarned': row['points_earned'],
              'returns': returnRows
                  .map(
                    (r) => {
                      'id': r['id'],
                      'refundCents': r['refund_cents'],
                      'reason': r['reason'],
                      'createdAt': r['created_at'],
                    },
                  )
                  .toList(growable: false),
              'returnQuantities': _returnQuantities(row['id'] as String),
              'returnQuantitiesByLine': _returnQuantitiesByLine(
                row['id'] as String,
              ),
            };
          })
          .toList(growable: false),
    });
  }

  Response salesReport(Request request) {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    if (!principal.canManageCatalog) return _forbidden();

    final from = _reportDate(request.url.queryParameters['from']);
    final to = _reportDate(request.url.queryParameters['to']);
    if (from == null || to == null || to.isBefore(from)) {
      return _error(
        400,
        'invalid_report_range',
        'Choose valid from and to dates in YYYY-MM-DD format.',
      );
    }
    final dayCount = to.difference(from).inDays + 1;
    if (dayCount > 366) {
      return _error(
        400,
        'report_range_too_large',
        'A sales report can cover up to 366 days.',
      );
    }
    final endExclusive = to.add(const Duration(days: 1));
    final fromIso = from.toIso8601String();
    final endIso = endExclusive.toIso8601String();

    final daily = <String, Map<String, Object?>>{};
    for (
      var day = from;
      !day.isAfter(to);
      day = day.add(const Duration(days: 1))
    ) {
      final key = _reportDayKey(day);
      daily[key] = {
        'date': key,
        'salesCount': 0,
        'grossSalesCents': 0,
        'refundCount': 0,
        'refundCents': 0,
        'voidCount': 0,
        'voidedCents': 0,
        'netSalesCents': 0,
      };
    }
    void addDaily(String key, String field, int amount) {
      final row = daily[key];
      if (row == null) return;
      row[field] = (row[field] as int) + amount;
    }

    var salesCount = 0;
    var grossSalesCents = 0;
    var discountCents = 0;
    var taxCents = 0;
    final products = <String, Map<String, Object?>>{};
    final saleRows = _database.select(
      '''
      SELECT created_at, total_cents, payload
      FROM sales
      WHERE julianday(created_at) >= julianday(?)
        AND julianday(created_at) < julianday(?)
      ORDER BY created_at
      ''',
      [fromIso, endIso],
    );
    for (final row in saleRows) {
      final createdAt = _reportDateTime(row['created_at']);
      if (createdAt == null) continue;
      final day = _reportDayKey(createdAt);
      final sale = (jsonDecode(row['payload'] as String) as Map).map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final total = row['total_cents'] as int;
      salesCount++;
      grossSalesCents += total;
      discountCents += sale['discountCents'] as int? ?? 0;
      taxCents += sale['taxCents'] as int? ?? 0;
      addDaily(day, 'salesCount', 1);
      addDaily(day, 'grossSalesCents', total);

      final lines = sale['lines'];
      if (lines is! List) continue;
      for (final rawLine in lines) {
        if (rawLine is! Map) continue;
        final productId = rawLine['productId'];
        final quantity = rawLine['quantity'];
        final lineCents = rawLine['totalCents'];
        if (productId is! String || quantity is! int || lineCents is! int) {
          continue;
        }
        final product = products.putIfAbsent(
          productId,
          () => {
            'productId': productId,
            'name': rawLine['name'] is String ? rawLine['name'] : 'Item',
            'quantity': 0,
            'grossCents': 0,
          },
        );
        product['quantity'] = (product['quantity'] as int) + quantity;
        product['grossCents'] = (product['grossCents'] as int) + lineCents;
      }
    }

    var refundCount = 0;
    var refundCents = 0;
    final returnRows = _database.select(
      '''
      SELECT created_at, refund_cents FROM returns
      WHERE julianday(created_at) >= julianday(?)
        AND julianday(created_at) < julianday(?)
      ORDER BY created_at
      ''',
      [fromIso, endIso],
    );
    for (final row in returnRows) {
      final createdAt = _reportDateTime(row['created_at']);
      if (createdAt == null) continue;
      final amount = row['refund_cents'] as int;
      refundCount++;
      refundCents += amount;
      addDaily(_reportDayKey(createdAt), 'refundCount', 1);
      addDaily(_reportDayKey(createdAt), 'refundCents', amount);
    }

    var voidCount = 0;
    var voidedCents = 0;
    final voidRows = _database.select(
      '''
      SELECT voided_at, total_cents FROM sales
      WHERE voided_at IS NOT NULL
        AND julianday(voided_at) >= julianday(?)
        AND julianday(voided_at) < julianday(?)
      ORDER BY voided_at
      ''',
      [fromIso, endIso],
    );
    for (final row in voidRows) {
      final voidedAt = _reportDateTime(row['voided_at']);
      if (voidedAt == null) continue;
      final amount = row['total_cents'] as int;
      voidCount++;
      voidedCents += amount;
      addDaily(_reportDayKey(voidedAt), 'voidCount', 1);
      addDaily(_reportDayKey(voidedAt), 'voidedCents', amount);
    }

    for (final row in daily.values) {
      row['netSalesCents'] =
          (row['grossSalesCents'] as int) -
          (row['refundCents'] as int) -
          (row['voidedCents'] as int);
    }

    final shiftRows = _database.select(
      '''
      SELECT s.id, s.register_id, s.opened_at, s.closed_at,
        s.opening_float_cents, s.expected_cash_cents,
        s.counted_cash_cents, s.variance_cents,
        COALESCE((SELECT COUNT(*) FROM sales x WHERE x.shift_id = s.id), 0) AS sales_count,
        COALESCE((SELECT SUM(total_cents) FROM sales x WHERE x.shift_id = s.id), 0) AS gross_sales_cents,
        COALESCE((SELECT SUM(amount_cents) FROM cash_movements m WHERE m.shift_id = s.id AND m.type = 'paid_in'), 0) AS paid_in_cents,
        COALESCE((SELECT SUM(amount_cents) FROM cash_movements m WHERE m.shift_id = s.id AND m.type = 'paid_out'), 0) AS paid_out_cents
      FROM cash_shifts s
      WHERE (julianday(s.opened_at) >= julianday(?) AND julianday(s.opened_at) < julianday(?))
        OR (s.closed_at IS NOT NULL AND julianday(s.closed_at) >= julianday(?) AND julianday(s.closed_at) < julianday(?))
      ORDER BY COALESCE(s.closed_at, s.opened_at) DESC
      LIMIT 501
      ''',
      [fromIso, endIso, fromIso, endIso],
    );
    final shiftStats = _database
        .select(
          '''
      SELECT
        COALESCE(SUM(CASE WHEN julianday(opened_at) >= julianday(?) AND julianday(opened_at) < julianday(?) THEN 1 ELSE 0 END), 0) AS opened_count,
        COALESCE(SUM(CASE WHEN closed_at IS NOT NULL AND julianday(closed_at) >= julianday(?) AND julianday(closed_at) < julianday(?) THEN 1 ELSE 0 END), 0) AS closed_count,
        COALESCE(SUM(CASE WHEN closed_at IS NULL THEN 1 ELSE 0 END), 0) AS open_count,
        COALESCE(SUM(CASE WHEN closed_at IS NOT NULL AND julianday(closed_at) >= julianday(?) AND julianday(closed_at) < julianday(?) THEN variance_cents ELSE 0 END), 0) AS cash_variance_cents
      FROM cash_shifts
      WHERE (julianday(opened_at) >= julianday(?) AND julianday(opened_at) < julianday(?))
        OR (closed_at IS NOT NULL AND julianday(closed_at) >= julianday(?) AND julianday(closed_at) < julianday(?))
      ''',
          [
            fromIso,
            endIso,
            fromIso,
            endIso,
            fromIso,
            endIso,
            fromIso,
            endIso,
            fromIso,
            endIso,
          ],
        )
        .first;
    final movementRows = _database.select(
      '''
      SELECT type, COALESCE(SUM(amount_cents), 0) AS total_cents
      FROM cash_movements
      WHERE julianday(created_at) >= julianday(?)
        AND julianday(created_at) < julianday(?)
      GROUP BY type
      ''',
      [fromIso, endIso],
    );
    var cashPaidInCents = 0;
    var cashPaidOutCents = 0;
    for (final row in movementRows) {
      if (row['type'] == 'paid_in') {
        cashPaidInCents = row['total_cents'] as int;
      } else if (row['type'] == 'paid_out') {
        cashPaidOutCents = row['total_cents'] as int;
      }
    }

    final shifts = shiftRows
        .take(500)
        .map(
          (row) => {
            'id': row['id'],
            'registerId': row['register_id'],
            'openedAt': row['opened_at'],
            'closedAt': row['closed_at'],
            'openingFloatCents': row['opening_float_cents'],
            'expectedCashCents': row['expected_cash_cents'],
            'countedCashCents': row['counted_cash_cents'],
            'varianceCents': row['variance_cents'],
            'salesCount': row['sales_count'],
            'grossSalesCents': row['gross_sales_cents'],
            'paidInCents': row['paid_in_cents'],
            'paidOutCents': row['paid_out_cents'],
          },
        )
        .toList(growable: false);
    final topProducts = products.values.toList()
      ..sort((a, b) {
        final byGross = (b['grossCents'] as int).compareTo(
          a['grossCents'] as int,
        );
        if (byGross != 0) return byGross;
        return (b['quantity'] as int).compareTo(a['quantity'] as int);
      });

    return _json(200, {
      'from': _reportDayKey(from),
      'to': _reportDayKey(to),
      'dateBasis': 'UTC',
      'eventDateNote':
          'Sales, refunds, voids, and cash movements use their recorded UTC event dates.',
      'summary': {
        'salesCount': salesCount,
        'grossSalesCents': grossSalesCents,
        'discountCents': discountCents,
        'taxCents': taxCents,
        'refundCount': refundCount,
        'refundCents': refundCents,
        'voidCount': voidCount,
        'voidedCents': voidedCents,
        'netSalesCents': grossSalesCents - refundCents - voidedCents,
        'cashPaidInCents': cashPaidInCents,
        'cashPaidOutCents': cashPaidOutCents,
        'shiftsOpened': shiftStats['opened_count'],
        'shiftsClosed': shiftStats['closed_count'],
        'openShiftCount': shiftStats['open_count'],
        'cashVarianceCents': shiftStats['cash_variance_cents'],
      },
      'daily': daily.values.toList(growable: false),
      'topProducts': topProducts.take(10).toList(growable: false),
      'shifts': shifts,
      'shiftsTruncated': shiftRows.length > 500,
    });
  }

  Future<Response> createReturn(Request request) async {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    if (!principal.canManageCatalog) return _forbidden();
    late final Map<String, Object?> body;
    try {
      body = await _readJsonObject(request);
    } on Object {
      return _error(400, 'invalid_return', 'Return details are malformed.');
    }
    final id = _requiredText(body['id'], 1, 128);
    final saleId = _requiredText(body['saleId'], 1, 128);
    final registerId = _requiredText(body['registerId'], 1, 128) ?? 'main';
    final reason = _requiredText(body['reason'], 1, 240);
    final rawLines = body['lines'];
    if (id == null ||
        saleId == null ||
        reason == null ||
        rawLines is! List ||
        rawLines.isEmpty ||
        rawLines.length > 100) {
      return _error(
        400,
        'invalid_return',
        'Enter a sale, reason, and at least one returned item.',
      );
    }
    final cleanLines = <Map<String, Object?>>[];
    for (final raw in rawLines) {
      if (raw is! Map) {
        return _error(
          400,
          'invalid_return',
          'Return item details are invalid.',
        );
      }
      final line = raw.map((key, value) => MapEntry(key.toString(), value));
      final productId = _requiredText(line['productId'], 1, 128);
      final quantity = line['quantity'];
      final restock = line['restock'] ?? true;
      final lineIndex = line['lineIndex'];
      if (productId == null ||
          quantity is! int ||
          quantity <= 0 ||
          restock is! bool ||
          (lineIndex != null && (lineIndex is! int || lineIndex < 0))) {
        return _error(
          400,
          'invalid_return',
          'Return quantities must be positive whole numbers.',
        );
      }
      cleanLines.add({
        'productId': productId,
        'quantity': quantity,
        'restock': restock,
        if (lineIndex is int) 'lineIndex': lineIndex,
      });
    }
    final saleRows = _database.select(
      'SELECT payload, total_cents, voided_at FROM sales WHERE id = ?',
      [saleId],
    );
    if (saleRows.isEmpty) {
      return _error(404, 'sale_not_found', 'No sale has this ID.');
    }
    if (saleRows.first['voided_at'] != null) {
      return _error(409, 'sale_voided', 'A voided sale cannot be returned.');
    }
    final saleJson = (jsonDecode(saleRows.first['payload'] as String) as Map)
        .map((key, value) => MapEntry(key.toString(), value));
    final sale = Sale.fromJson(saleJson);
    final previouslyReturned = <int, int>{};
    for (final row in _database.select(
      'SELECT sale_line_index, SUM(quantity) AS quantity FROM return_lines WHERE sale_id = ? GROUP BY sale_line_index',
      [saleId],
    )) {
      previouslyReturned[row['sale_line_index'] as int] =
          row['quantity'] as int;
    }
    final cumulative = Map<int, int>.from(previouslyReturned);
    final requestedLineIndexes = <int>{};
    for (final line in cleanLines) {
      final productId = line['productId']! as String;
      final candidates = sale.lines.indexed
          .where((entry) => entry.$2.productId == productId)
          .map((entry) => entry.$1)
          .toList(growable: false);
      if (candidates.isEmpty) {
        return _error(
          400,
          'invalid_return_item',
          'The product is not part of this sale.',
        );
      }
      final requestedIndex = line['lineIndex'];
      final lineIndex = requestedIndex is int
          ? requestedIndex
          : candidates.length == 1
          ? candidates.single
          : -1;
      if (!candidates.contains(lineIndex)) {
        return _error(
          400,
          'return_line_required',
          'Choose the exact sale line when a product has different options.',
        );
      }
      if (!requestedLineIndexes.add(lineIndex)) {
        return _error(
          400,
          'invalid_return',
          'Each sale line may appear once in a return.',
        );
      }
      line['lineIndex'] = lineIndex;
    }
    final payload = jsonEncode({
      'id': id,
      'saleId': saleId,
      'registerId': registerId,
      'reason': reason,
      'lines': cleanLines,
    });
    final prior = _database.select(
      'SELECT payload, refund_cents FROM returns WHERE id = ?',
      [id],
    );
    if (prior.isNotEmpty) {
      if (prior.first['payload'] != payload) {
        return _error(
          409,
          'return_id_conflict',
          'This return ID already has different details.',
        );
      }
      return _json(200, {
        'id': id,
        'status': 'accepted',
        'refundCents': prior.first['refund_cents'],
      });
    }
    final shiftRows = _database.select(
      'SELECT id FROM cash_shifts WHERE register_id = ? AND closed_at IS NULL LIMIT 1',
      [registerId],
    );
    if (shiftRows.isEmpty) {
      return _error(
        409,
        'shift_not_open',
        'Open a cash shift on this register before refunding.',
      );
    }
    final shiftId = shiftRows.first['id'] as String;
    for (final line in cleanLines) {
      final lineIndex = line['lineIndex']! as int;
      final original = sale.lines[lineIndex];
      cumulative[lineIndex] =
          (cumulative[lineIndex] ?? 0) + (line['quantity']! as int);
      if (cumulative[lineIndex]! > original.quantity) {
        return _error(
          409,
          'return_quantity_exceeded',
          'Returned quantity exceeds the quantity sold.',
        );
      }
    }
    final returnedSubtotal = cumulative.entries.fold<int>(
      0,
      (sum, entry) =>
          sum + (sale.lines[entry.key].unitTotalCents * entry.value),
    );
    final fullyReturned = sale.lines.indexed.every(
      (entry) => (cumulative[entry.$1] ?? 0) == entry.$2.quantity,
    );
    final priorRefund =
        _database.select(
              'SELECT COALESCE(SUM(refund_cents), 0) AS total FROM returns WHERE sale_id = ?',
              [saleId],
            ).first['total']
            as int;
    final cumulativeRefund = fullyReturned
        ? sale.totalCents
        : _roundRatio(returnedSubtotal, sale.totalCents, sale.subtotalCents);
    final refund = cumulativeRefund - priorRefund;
    if (refund < 0 || priorRefund + refund > sale.totalCents) {
      return _error(
        409,
        'return_value_exceeded',
        'Return value exceeds the original sale.',
      );
    }
    if (refund > _refreshShiftExpected(shiftId)) {
      return _error(
        409,
        'insufficient_drawer_cash',
        'The register does not have enough cash to refund this return.',
      );
    }
    final earnedBefore =
        _database.select('SELECT points_earned FROM sales WHERE id = ?', [
              saleId,
            ]).first['points_earned']
            as int;
    final priorLoyalty = _database.select(
      'SELECT COALESCE(SUM(points_earned_reversed), 0) AS earned, COALESCE(SUM(points_redeemed_restored), 0) AS redeemed FROM returns WHERE sale_id = ?',
      [saleId],
    ).first;
    final cumulativeEarnedReverse = sale.totalCents == 0
        ? 0
        : (BigInt.from(earnedBefore) *
                  BigInt.from(priorRefund + refund) ~/
                  BigInt.from(sale.totalCents))
              .toInt();
    final cumulativeRedeemedRestore = sale.totalCents == 0
        ? 0
        : (BigInt.from(sale.pointsRedeemed) *
                  BigInt.from(priorRefund + refund) ~/
                  BigInt.from(sale.totalCents))
              .toInt();
    final earnedReverse =
        cumulativeEarnedReverse - (priorLoyalty['earned'] as int);
    final redeemedRestore =
        cumulativeRedeemedRestore - (priorLoyalty['redeemed'] as int);
    final now = DateTime.now().toUtc().toIso8601String();
    _database.execute('BEGIN IMMEDIATE');
    try {
      _database.execute(
        'INSERT INTO returns (id, sale_id, shift_id, refund_cents, reason, payload, points_earned_reversed, points_redeemed_restored, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          id,
          saleId,
          shiftId,
          refund,
          reason,
          payload,
          earnedReverse,
          redeemedRestore,
          now,
        ],
      );
      final restockedByProduct = <String, int>{};
      for (final line in cleanLines) {
        final productId = line['productId']! as String;
        final quantity = line['quantity']! as int;
        final restock = line['restock']! as bool;
        _database.execute(
          'INSERT INTO return_lines (return_id, sale_id, product_id, sale_line_index, quantity, restock) VALUES (?, ?, ?, ?, ?, ?)',
          [id, saleId, productId, line['lineIndex'], quantity, restock ? 1 : 0],
        );
        if (restock) {
          restockedByProduct.update(
            productId,
            (previous) => previous + quantity,
            ifAbsent: () => quantity,
          );
        }
      }
      for (final entry in restockedByProduct.entries) {
        _changeStock(entry.key, 'Main', entry.value);
        _database.execute(
          'INSERT INTO inventory_movements (id, product_id, type, quantity, source_location, destination_location, note, actor_user_id, created_at) VALUES (?, ?, \'receive\', ?, NULL, \'Main\', ?, ?, ?)',
          [
            'return-$id-${entry.key}',
            entry.key,
            entry.value,
            'Return $saleId: $reason',
            principal.userId,
            now,
          ],
        );
      }
      if (refund > 0) {
        _database.execute(
          'INSERT INTO cash_movements (id, shift_id, type, amount_cents, note, actor_user_id, created_at) VALUES (?, ?, \'paid_out\', ?, ?, ?, ?)',
          [
            'refund-$id',
            shiftId,
            refund,
            'Refund for sale $saleId: $reason',
            principal.userId,
            now,
          ],
        );
      }
      if (sale.customerId != null &&
          (earnedReverse > 0 || redeemedRestore > 0)) {
        _database.execute(
          'UPDATE customers SET loyalty_points = MAX(0, loyalty_points - ? + ?), updated_at = ? WHERE id = ?',
          [earnedReverse, redeemedRestore, now, sale.customerId],
        );
        if (earnedReverse > 0) {
          _database.execute(
            'INSERT INTO loyalty_events (id, customer_id, sale_id, points_delta, note, created_at) VALUES (?, ?, ?, ?, ?, ?)',
            [
              _newId(),
              sale.customerId,
              saleId,
              -earnedReverse,
              'return earning reversal',
              now,
            ],
          );
        }
        if (redeemedRestore > 0) {
          _database.execute(
            'INSERT INTO loyalty_events (id, customer_id, sale_id, points_delta, note, created_at) VALUES (?, ?, ?, ?, ?, ?)',
            [
              _newId(),
              sale.customerId,
              saleId,
              redeemedRestore,
              'return redemption refund',
              now,
            ],
          );
        }
      }
      _updatePaymentRefunds(saleId, DateTime.parse(now), principal.userId);
      _refreshShiftExpected(shiftId);
      _audit(principal.userId, 'sale.returned', 'sale', saleId, {
        'returnId': id,
        'refundCents': refund,
        'reason': reason,
      });
      _database.execute('COMMIT');
    } on Object {
      _database.execute('ROLLBACK');
      return _error(500, 'return_failed', 'The return could not be saved.');
    }
    return _json(201, {'id': id, 'status': 'accepted', 'refundCents': refund});
  }

  Future<Response> voidSale(Request request, String saleId) async {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    if (!principal.canManageCatalog) return _forbidden();
    late final Map<String, Object?> body;
    try {
      body = await _readJsonObject(request);
    } on Object {
      return _error(400, 'invalid_void', 'Void details are malformed.');
    }
    final reason = _requiredText(body['reason'], 1, 240);
    final registerId = _requiredText(body['registerId'], 1, 128) ?? 'main';
    if (reason == null) {
      return _error(400, 'invalid_void', 'Enter a reason for the void.');
    }
    final saleRows = _database.select(
      'SELECT payload, total_cents, voided_at, void_reason FROM sales WHERE id = ?',
      [saleId],
    );
    if (saleRows.isEmpty) {
      return _error(404, 'sale_not_found', 'No sale has this ID.');
    }
    if (saleRows.first['voided_at'] != null) {
      if (saleRows.first['void_reason'] == reason) {
        return _json(200, {'id': saleId, 'status': 'voided'});
      }
      return _error(
        409,
        'sale_already_voided',
        'This sale has already been voided.',
      );
    }
    if (_database.select('SELECT id FROM returns WHERE sale_id = ?', [
      saleId,
    ]).isNotEmpty) {
      return _error(
        409,
        'sale_has_returns',
        'A sale with returns cannot be voided.',
      );
    }
    final shift = _database.select(
      'SELECT id FROM cash_shifts WHERE register_id = ? AND closed_at IS NULL LIMIT 1',
      [registerId],
    );
    if (shift.isEmpty) {
      return _error(
        409,
        'shift_not_open',
        'Open a cash shift on this register before voiding.',
      );
    }
    final shiftId = shift.first['id'] as String;
    final saleJson = (jsonDecode(saleRows.first['payload'] as String) as Map)
        .map((key, value) => MapEntry(key.toString(), value));
    final sale = Sale.fromJson(saleJson);
    if (sale.totalCents > _refreshShiftExpected(shiftId)) {
      return _error(
        409,
        'insufficient_drawer_cash',
        'The register does not have enough cash to refund this void.',
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    _database.execute('BEGIN IMMEDIATE');
    try {
      _database.execute(
        'UPDATE sales SET voided_at = ?, void_reason = ?, voided_by = ? WHERE id = ?',
        [now, reason, principal.userId, saleId],
      );
      final voidedQuantities = <String, int>{};
      for (final line in sale.lines) {
        voidedQuantities.update(
          line.productId,
          (quantity) => quantity + line.quantity,
          ifAbsent: () => line.quantity,
        );
      }
      for (final entry in voidedQuantities.entries) {
        if (_database.select('SELECT id FROM products WHERE id = ?', [
          entry.key,
        ]).isEmpty) {
          continue;
        }
        _changeStock(entry.key, 'Main', entry.value);
        _database.execute(
          'INSERT INTO inventory_movements (id, product_id, type, quantity, source_location, destination_location, note, actor_user_id, created_at) VALUES (?, ?, \'receive\', ?, NULL, \'Main\', ?, ?, ?)',
          [
            'void-$saleId-${entry.key}',
            entry.key,
            entry.value,
            'Void $saleId: $reason',
            principal.userId,
            now,
          ],
        );
      }
      final refund = sale.totalCents;
      if (refund > 0) {
        _database.execute(
          'INSERT INTO cash_movements (id, shift_id, type, amount_cents, note, actor_user_id, created_at) VALUES (?, ?, \'paid_out\', ?, ?, ?, ?)',
          [
            'void-refund-$saleId',
            shiftId,
            refund,
            'Void refund for sale $saleId: $reason',
            principal.userId,
            now,
          ],
        );
      }
      final points =
          _database.select('SELECT points_earned FROM sales WHERE id = ?', [
                saleId,
              ]).first['points_earned']
              as int;
      if (sale.customerId != null) {
        _database.execute(
          'UPDATE customers SET loyalty_points = MAX(0, loyalty_points + ? - ?), updated_at = ? WHERE id = ?',
          [sale.pointsRedeemed, points, now, sale.customerId],
        );
        if (points > 0) {
          _database.execute(
            'INSERT INTO loyalty_events (id, customer_id, sale_id, points_delta, note, created_at) VALUES (?, ?, ?, ?, ?, ?)',
            [_newId(), sale.customerId, saleId, -points, 'void reversal', now],
          );
        }
        if (sale.pointsRedeemed > 0) {
          _database.execute(
            'INSERT INTO loyalty_events (id, customer_id, sale_id, points_delta, note, created_at) VALUES (?, ?, ?, ?, ?, ?)',
            [
              _newId(),
              sale.customerId,
              saleId,
              sale.pointsRedeemed,
              'void redemption refund',
              now,
            ],
          );
        }
      }
      _setPaymentStatus(
        saleId,
        PaymentStatus.voided,
        DateTime.parse(now),
        principal.userId,
      );
      _refreshShiftExpected(shiftId);
      _audit(principal.userId, 'sale.voided', 'sale', saleId, {
        'reason': reason,
        'refundCents': refund,
        'shiftId': shiftId,
      });
      _database.execute('COMMIT');
    } on Object {
      _database.execute('ROLLBACK');
      return _error(500, 'void_failed', 'The sale could not be voided.');
    }
    return _json(200, {'id': saleId, 'status': 'voided'});
  }

  int _roundRatio(int amount, int numerator, int denominator) =>
      denominator == 0
      ? 0
      : ((BigInt.from(amount) * BigInt.from(numerator) +
                    BigInt.from(denominator ~/ 2)) ~/
                BigInt.from(denominator))
            .toInt();

  Map<String, int> _returnQuantities(String saleId) => {
    for (final row in _database.select(
      'SELECT product_id, SUM(quantity) AS quantity FROM return_lines WHERE sale_id = ? GROUP BY product_id',
      [saleId],
    ))
      row['product_id'] as String: row['quantity'] as int,
  };

  Map<String, int> _returnQuantitiesByLine(String saleId) => {
    for (final row in _database.select(
      'SELECT sale_line_index, SUM(quantity) AS quantity FROM return_lines WHERE sale_id = ? GROUP BY sale_line_index',
      [saleId],
    ))
      '${row['sale_line_index']}': row['quantity'] as int,
  };

  void _updatePaymentRefunds(String saleId, DateTime now, String? actorId) {
    final rows = _database.select(
      'SELECT id, payload FROM payment_records WHERE sale_id = ?',
      [saleId],
    );
    if (rows.isEmpty) return;
    final refunds =
        _database.select(
              'SELECT COALESCE(SUM(refund_cents), 0) AS total FROM returns WHERE sale_id = ?',
              [saleId],
            ).first['total']
            as int;
    final payment = PaymentRecord.fromJson(
      (jsonDecode(rows.first['payload'] as String) as Map).map(
        (key, value) => MapEntry(key.toString(), value),
      ),
    );
    final updated = payment.withRefundedCents(refunds, updatedAt: now);
    _database.execute(
      'UPDATE payment_records SET status = ?, payload = ?, updated_at = ? WHERE id = ?',
      [
        updated.status.value,
        jsonEncode(updated.toJson()),
        now.toIso8601String(),
        rows.first['id'],
      ],
    );
    _audit(actorId, 'payment.refunded', 'payment', updated.id, {
      'saleId': saleId,
      'refundedCents': updated.refundedCents,
      'status': updated.status.value,
    });
  }

  void _setPaymentStatus(
    String saleId,
    PaymentStatus status,
    DateTime now,
    String? actorId,
  ) {
    final rows = _database.select(
      'SELECT id, payload FROM payment_records WHERE sale_id = ?',
      [saleId],
    );
    if (rows.isEmpty) return;
    final payment = PaymentRecord.fromJson(
      (jsonDecode(rows.first['payload'] as String) as Map).map(
        (key, value) => MapEntry(key.toString(), value),
      ),
    );
    final updated = payment.withStatus(status, updatedAt: now);
    _database.execute(
      'UPDATE payment_records SET status = ?, payload = ?, updated_at = ? WHERE id = ?',
      [
        status.value,
        jsonEncode(updated.toJson()),
        now.toIso8601String(),
        rows.first['id'],
      ],
    );
    _audit(actorId, 'payment.voided', 'payment', payment.id, {
      'saleId': saleId,
      'status': status.value,
    });
  }

  Response listInventory(Request request) {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    final rows = _database.select('''
      SELECT p.id, p.name, p.sku,
        COALESCE(SUM(b.quantity), 0) AS on_hand,
        COALESCE(t.low_stock_threshold, 0) AS low_stock_threshold
      FROM products p
      LEFT JOIN inventory_balances b ON b.product_id = p.id
      LEFT JOIN inventory_thresholds t ON t.product_id = p.id
      WHERE p.is_active = 1
      GROUP BY p.id
      ORDER BY p.name COLLATE NOCASE
    ''');
    final items = rows
        .map((row) {
          final onHand = row['on_hand'] as int;
          final threshold = row['low_stock_threshold'] as int;
          final locations = _database.select(
            'SELECT location, quantity FROM inventory_balances WHERE product_id = ? ORDER BY location COLLATE NOCASE',
            [row['id']],
          );
          return {
            'productId': row['id'],
            'name': row['name'],
            'sku': row['sku'],
            'onHand': onHand,
            'lowStockThreshold': threshold,
            'isLowStock': onHand <= threshold,
            'locations': locations
                .map(
                  (location) => {
                    'location': location['location'],
                    'quantity': location['quantity'],
                  },
                )
                .toList(growable: false),
          };
        })
        .toList(growable: false);
    return _json(200, {
      'items': items,
      'lowStockCount': items.where((item) => item['isLowStock'] == true).length,
    });
  }

  Response listStockMovements(Request request) {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    if (!principal.canManageCatalog) return _forbidden();
    final rows = _database.select('''
      SELECT m.id, m.product_id, p.name, m.type, m.quantity,
        m.source_location, m.destination_location, m.note, m.created_at,
        u.name AS actor_name
      FROM inventory_movements m
      JOIN products p ON p.id = m.product_id
      LEFT JOIN users u ON u.id = m.actor_user_id
      ORDER BY m.created_at DESC, m.id DESC
      LIMIT 200
    ''');
    return _json(200, {
      'movements': rows
          .map(
            (row) => {
              'id': row['id'],
              'productId': row['product_id'],
              'productName': row['name'],
              'type': row['type'],
              'quantity': row['quantity'],
              'sourceLocation': row['source_location'],
              'destinationLocation': row['destination_location'],
              'note': row['note'],
              'actorName': row['actor_name'],
              'createdAt': row['created_at'],
            },
          )
          .toList(growable: false),
    });
  }

  Future<Response> createStockMovement(Request request) async {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    if (!principal.canManageCatalog) return _forbidden();
    late final Map<String, Object?> body;
    try {
      body = await _readJsonObject(request);
    } on Object {
      return _error(400, 'invalid_movement', 'Movement details are malformed.');
    }
    final id = _requiredText(body['id'], 1, 128);
    final productId = _requiredText(body['productId'], 1, 128);
    final type = body['type'];
    final rawQuantity = body['quantity'];
    final quantity = rawQuantity is int ? rawQuantity : null;
    final note = body['note'] == null
        ? null
        : _requiredText(body['note'], 1, 240);
    final source = body['sourceLocation'] == null
        ? null
        : _requiredText(body['sourceLocation'], 1, 80);
    final destination = body['destinationLocation'] == null
        ? null
        : _requiredText(body['destinationLocation'], 1, 80);
    if (id == null ||
        productId == null ||
        !const ['receive', 'adjustment', 'transfer'].contains(type) ||
        quantity == null ||
        quantity == 0 ||
        quantity.abs() > 9007199254740991 ||
        (body['note'] != null && note == null) ||
        (body['sourceLocation'] != null && source == null) ||
        (body['destinationLocation'] != null && destination == null) ||
        (type == 'receive' && quantity < 0) ||
        (type == 'transfer' && quantity < 0)) {
      return _error(
        400,
        'invalid_movement',
        'Enter a valid product, type, quantity, and location.',
      );
    }
    final sourceLocation = source ?? 'Main';
    final destinationLocation = destination ?? 'Main';
    if (type == 'transfer' && sourceLocation == destinationLocation) {
      return _error(
        400,
        'invalid_movement',
        'Choose two different stock locations for a transfer.',
      );
    }
    final product = _database.select(
      'SELECT id FROM products WHERE id = ? AND is_active = 1',
      [productId],
    );
    if (product.isEmpty) {
      return _error(404, 'product_not_found', 'No active product has this ID.');
    }
    final previous = _database.select(
      'SELECT product_id, type, quantity, source_location, destination_location, note FROM inventory_movements WHERE id = ?',
      [id],
    );
    if (previous.isNotEmpty) {
      final row = previous.first;
      final same =
          row['product_id'] == productId &&
          row['type'] == type &&
          row['quantity'] == quantity &&
          row['source_location'] ==
              (type == 'transfer' ? sourceLocation : null) &&
          row['destination_location'] ==
              (type == 'receive' || type == 'adjustment'
                  ? destinationLocation
                  : (type == 'transfer' ? destinationLocation : null)) &&
          row['note'] == note;
      if (!same) {
        return _error(
          409,
          'movement_id_conflict',
          'This movement ID already has different details.',
        );
      }
      return _json(200, {'id': id, 'status': 'accepted'});
    }
    final from = type == 'transfer' ? sourceLocation : null;
    final to = type == 'transfer' || type == 'receive' || type == 'adjustment'
        ? destinationLocation
        : null;
    final signedQuantity = type == 'adjustment' ? quantity : quantity.abs();
    final now = DateTime.now().toUtc().toIso8601String();
    _database.execute('BEGIN IMMEDIATE');
    try {
      if (type == 'receive') {
        _changeStock(productId, destinationLocation, signedQuantity);
      } else if (type == 'adjustment') {
        _changeStock(productId, destinationLocation, signedQuantity);
      } else {
        final sourceRows = _database.select(
          'SELECT quantity FROM inventory_balances WHERE product_id = ? AND location = ?',
          [productId, sourceLocation],
        );
        final available = sourceRows.isEmpty
            ? 0
            : sourceRows.first['quantity'] as int;
        if (available < quantity) {
          _database.execute('ROLLBACK');
          return _error(
            409,
            'insufficient_stock',
            'The source location does not have enough stock to transfer.',
          );
        }
        _changeStock(productId, sourceLocation, -quantity);
        _changeStock(productId, destinationLocation, quantity);
      }
      _database.execute(
        '''
        INSERT INTO inventory_movements
          (id, product_id, type, quantity, source_location, destination_location, note, actor_user_id, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
        [
          id,
          productId,
          type,
          signedQuantity,
          from,
          to,
          note,
          principal.userId,
          now,
        ],
      );
      _audit(
        principal.userId,
        'inventory.movement_recorded',
        'inventory_movement',
        id,
        {
          'productId': productId,
          'type': type,
          'quantity': signedQuantity,
          'sourceLocation': from,
          'destinationLocation': to,
        },
      );
      _database.execute('COMMIT');
    } on Object {
      _database.execute('ROLLBACK');
      return _error(
        500,
        'movement_failed',
        'The stock movement could not be recorded.',
      );
    }
    return _json(201, {'id': id, 'status': 'accepted'});
  }

  Future<Response> setLowStockThreshold(
    Request request,
    String productId,
  ) async {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    if (!principal.canManageCatalog) return _forbidden();
    late final Map<String, Object?> body;
    try {
      body = await _readJsonObject(request);
    } on Object {
      return _error(
        400,
        'invalid_threshold',
        'Threshold details are malformed.',
      );
    }
    final threshold = body['lowStockThreshold'];
    if (threshold is! int || threshold < 0 || threshold > 9007199254740991) {
      return _error(
        400,
        'invalid_threshold',
        'Low-stock threshold must be a non-negative whole number.',
      );
    }
    final exists = _database.select('SELECT id FROM products WHERE id = ?', [
      productId,
    ]);
    if (exists.isEmpty) {
      return _error(404, 'product_not_found', 'No product has this ID.');
    }
    _database.execute(
      '''
      INSERT INTO inventory_thresholds (product_id, low_stock_threshold) VALUES (?, ?)
      ON CONFLICT(product_id) DO UPDATE SET low_stock_threshold = excluded.low_stock_threshold
    ''',
      [productId, threshold],
    );
    _audit(
      principal.userId,
      'inventory.threshold_updated',
      'product',
      productId,
      {'lowStockThreshold': threshold},
    );
    return _json(200, {'productId': productId, 'lowStockThreshold': threshold});
  }

  Response currentCashShift(Request request) {
    if (_principal(request) == null) return _unauthorized();
    final registerId =
        _requiredText(request.url.queryParameters['registerId'], 1, 128) ??
        'main';
    final rows = _database.select(
      'SELECT * FROM cash_shifts WHERE closed_at IS NULL AND register_id = ? LIMIT 1',
      [registerId],
    );
    return _json(200, {
      'shift': rows.isEmpty ? null : _cashShiftJson(rows.first),
    });
  }

  Response getCashShift(Request request, String id) {
    if (_principal(request) == null) return _unauthorized();
    final rows = _database.select('SELECT * FROM cash_shifts WHERE id = ?', [
      id,
    ]);
    if (rows.isEmpty) {
      return _error(404, 'shift_not_found', 'No cash shift has this ID.');
    }
    return _json(200, {'shift': _cashShiftJson(rows.first)});
  }

  Future<Response> openCashShift(Request request) async {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    late final Map<String, Object?> body;
    try {
      body = await _readJsonObject(request);
    } on Object {
      return _error(400, 'invalid_shift', 'Shift details are malformed.');
    }
    final id = _requiredText(body['id'], 1, 128);
    final registerId = _requiredText(body['registerId'], 1, 128) ?? 'main';
    final openingFloat = body['openingFloatCents'];
    if (id == null ||
        openingFloat is! int ||
        openingFloat < 0 ||
        openingFloat > 9007199254740991) {
      return _error(
        400,
        'invalid_shift',
        'Enter a shift ID and a non-negative opening float in cents.',
      );
    }
    if (_database.select('SELECT id FROM registers WHERE id = ?', [
      registerId,
    ]).isEmpty) {
      return _error(
        409,
        'register_not_enrolled',
        'Enroll this register before opening a cash shift.',
      );
    }
    final existingId = _database.select(
      'SELECT * FROM cash_shifts WHERE id = ?',
      [id],
    );
    if (existingId.isNotEmpty &&
        existingId.first['opening_float_cents'] == openingFloat &&
        existingId.first['register_id'] == registerId) {
      return _json(200, {'shift': _cashShiftJson(existingId.first)});
    }
    if (existingId.isNotEmpty) {
      return _error(409, 'shift_id_conflict', 'This shift ID already exists.');
    }
    final open = _database.select(
      'SELECT id FROM cash_shifts WHERE closed_at IS NULL AND register_id = ? LIMIT 1',
      [registerId],
    );
    if (open.isNotEmpty) {
      return _error(
        409,
        'shift_already_open',
        'Close the current cash shift before opening another.',
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    _database.execute(
      'INSERT INTO cash_shifts (id, opened_by, opened_at, opening_float_cents, expected_cash_cents, register_id) VALUES (?, ?, ?, ?, ?, ?)',
      [id, principal.userId, now, openingFloat, openingFloat, registerId],
    );
    _audit(principal.userId, 'shift.opened', 'cash_shift', id, {
      'openingFloatCents': openingFloat,
      'registerId': registerId,
    });
    final row = _database.select('SELECT * FROM cash_shifts WHERE id = ?', [
      id,
    ]).first;
    return _json(201, {'shift': _cashShiftJson(row)});
  }

  Future<Response> recordCashMovement(Request request, String shiftId) async {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    late final Map<String, Object?> body;
    try {
      body = await _readJsonObject(request);
    } on Object {
      return _error(
        400,
        'invalid_cash_movement',
        'Cash movement details are malformed.',
      );
    }
    final id = _requiredText(body['id'], 1, 128);
    final type = body['type'];
    final amount = body['amountCents'];
    final note = body['note'] == null
        ? null
        : _requiredText(body['note'], 1, 240);
    if (id == null ||
        !const ['paid_in', 'paid_out'].contains(type) ||
        amount is! int ||
        amount <= 0 ||
        amount > 9007199254740991 ||
        (body['note'] != null && note == null)) {
      return _error(
        400,
        'invalid_cash_movement',
        'Enter a movement ID, paid-in/out type, positive amount, and optional note.',
      );
    }
    final previous = _database.select(
      'SELECT shift_id, type, amount_cents, note FROM cash_movements WHERE id = ?',
      [id],
    );
    if (previous.isNotEmpty) {
      final row = previous.first;
      if (row['shift_id'] != shiftId ||
          row['type'] != type ||
          row['amount_cents'] != amount ||
          row['note'] != note) {
        return _error(
          409,
          'cash_movement_id_conflict',
          'This cash movement ID already has different details.',
        );
      }
      return _json(200, {'id': id, 'status': 'accepted'});
    }
    final shift = _database.select(
      'SELECT id FROM cash_shifts WHERE id = ? AND closed_at IS NULL',
      [shiftId],
    );
    if (shift.isEmpty) {
      return _error(
        409,
        'shift_not_open',
        'Cash movements can only be recorded on an open shift.',
      );
    }
    if (type == 'paid_out') {
      final expected = _refreshShiftExpected(shiftId);
      if (amount > expected) {
        return _error(
          409,
          'insufficient_drawer_cash',
          'Paid-out amount cannot exceed expected cash in the drawer.',
        );
      }
    }
    _database.execute(
      'INSERT INTO cash_movements (id, shift_id, type, amount_cents, note, actor_user_id, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        shiftId,
        type,
        amount,
        note,
        principal.userId,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
    _refreshShiftExpected(shiftId);
    _audit(
      principal.userId,
      'shift.cash_movement_recorded',
      'cash_shift',
      shiftId,
      {'movementId': id, 'type': type, 'amountCents': amount},
    );
    return _json(201, {'id': id, 'status': 'accepted'});
  }

  Future<Response> closeCashShift(Request request, String shiftId) async {
    final principal = _principal(request);
    if (principal == null) return _unauthorized();
    late final Map<String, Object?> body;
    try {
      body = await _readJsonObject(request);
    } on Object {
      return _error(
        400,
        'invalid_shift_close',
        'Counted cash details are malformed.',
      );
    }
    final counted = body['countedCashCents'];
    if (counted is! int || counted < 0 || counted > 9007199254740991) {
      return _error(
        400,
        'invalid_shift_close',
        'Counted cash must be a non-negative amount in cents.',
      );
    }
    final rows = _database.select('SELECT * FROM cash_shifts WHERE id = ?', [
      shiftId,
    ]);
    if (rows.isEmpty) {
      return _error(404, 'shift_not_found', 'No cash shift has this ID.');
    }
    final prior = rows.first;
    if (prior['closed_at'] != null) {
      if (prior['counted_cash_cents'] == counted) {
        return _json(200, {'shift': _cashShiftJson(prior)});
      }
      return _error(
        409,
        'shift_already_closed',
        'This shift was already closed with a different cash count.',
      );
    }
    final expected = _refreshShiftExpected(shiftId);
    final now = DateTime.now().toUtc().toIso8601String();
    _database.execute(
      'UPDATE cash_shifts SET closed_at = ?, counted_cash_cents = ?, variance_cents = ? WHERE id = ?',
      [now, counted, counted - expected, shiftId],
    );
    _audit(principal.userId, 'shift.closed', 'cash_shift', shiftId, {
      'expectedCashCents': expected,
      'countedCashCents': counted,
      'varianceCents': counted - expected,
    });
    return _json(200, {
      'shift': _cashShiftJson(
        _database.select('SELECT * FROM cash_shifts WHERE id = ?', [
          shiftId,
        ]).first,
      ),
    });
  }

  int _refreshShiftExpected(String shiftId) {
    final row = _database
        .select(
          '''
      SELECT s.opening_float_cents,
        COALESCE((SELECT SUM(total_cents) FROM sales WHERE shift_id = s.id), 0) AS sales_cents,
        COALESCE((SELECT SUM(amount_cents) FROM cash_movements WHERE shift_id = s.id AND type = 'paid_in'), 0) AS paid_in_cents,
        COALESCE((SELECT SUM(amount_cents) FROM cash_movements WHERE shift_id = s.id AND type = 'paid_out'), 0) AS paid_out_cents,
        s.counted_cash_cents, s.closed_at
      FROM cash_shifts s WHERE s.id = ?
    ''',
          [shiftId],
        )
        .first;
    final expected =
        (row['opening_float_cents'] as int) +
        (row['sales_cents'] as int) +
        (row['paid_in_cents'] as int) -
        (row['paid_out_cents'] as int);
    final variance = row['counted_cash_cents'] == null
        ? null
        : (row['counted_cash_cents'] as int) - expected;
    _database.execute(
      'UPDATE cash_shifts SET expected_cash_cents = ?, variance_cents = ? WHERE id = ?',
      [expected, variance, shiftId],
    );
    return expected;
  }

  Map<String, Object?> _cashShiftJson(Row row) {
    final expected = _refreshShiftExpected(row['id'] as String);
    final fresh = _database.select('SELECT * FROM cash_shifts WHERE id = ?', [
      row['id'],
    ]).first;
    return {
      'id': fresh['id'],
      'registerId': fresh['register_id'],
      'openedAt': fresh['opened_at'],
      'openingFloatCents': fresh['opening_float_cents'],
      'expectedCashCents': expected,
      'isOpen': fresh['closed_at'] == null,
      'closedAt': fresh['closed_at'],
      'countedCashCents': fresh['counted_cash_cents'],
      'varianceCents': fresh['variance_cents'],
    };
  }

  Map<String, Object?> _supplierJson(Row row) => {
    'id': row['id'],
    'name': row['name'],
    'contactName': row['contact_name'],
    'email': row['email'],
    'phone': row['phone'],
    'address': row['address'],
    'notes': row['notes'],
    'isActive': row['is_active'] == 1,
    'version': row['version'],
    'createdAt': row['created_at'],
    'updatedAt': row['updated_at'],
  };

  Map<String, Object?> _purchaseOrderJson(String id) {
    final order = _database
        .select(
          '''
      SELECT o.*, s.name AS supplier_name
      FROM purchase_orders o
      JOIN suppliers s ON s.id = o.supplier_id
      WHERE o.id = ?
      ''',
          [id],
        )
        .single;
    final lines = _database.select(
      'SELECT * FROM purchase_order_lines WHERE purchase_order_id = ? ORDER BY rowid',
      [id],
    );
    final lineJson = lines
        .map(
          (line) => {
            'id': line['id'],
            'productId': line['product_id'],
            'productName': line['product_name'],
            'sku': line['sku'],
            'orderedQuantity': line['ordered_quantity'],
            'receivedQuantity': line['received_quantity'],
            'unitCostCents': line['unit_cost_cents'],
          },
        )
        .toList(growable: false);
    final totalCents = lines.fold<int>(
      0,
      (total, line) =>
          total +
          (line['ordered_quantity'] as int) * (line['unit_cost_cents'] as int),
    );
    final receipts = _database.select(
      'SELECT id, payload, received_at FROM purchase_order_receipts WHERE purchase_order_id = ? ORDER BY received_at, id',
      [id],
    );
    return {
      'id': order['id'],
      'supplierId': order['supplier_id'],
      'supplierName': order['supplier_name'],
      'status': order['status'],
      'expectedAt': order['expected_at'],
      'note': order['note'],
      'orderedAt': order['ordered_at'],
      'createdAt': order['created_at'],
      'updatedAt': order['updated_at'],
      'version': order['version'],
      'totalCents': totalCents,
      'lines': lineJson,
      'receipts': receipts
          .map((receipt) {
            final payload = (jsonDecode(receipt['payload'] as String) as Map)
                .map((key, value) => MapEntry(key.toString(), value));
            return {
              'id': receipt['id'],
              'receivedAt': receipt['received_at'],
              ...payload,
            };
          })
          .toList(growable: false),
    };
  }

  void _changeStock(String productId, String location, int delta) {
    _database.execute(
      '''
      INSERT INTO inventory_balances (product_id, location, quantity) VALUES (?, ?, ?)
      ON CONFLICT(product_id, location) DO UPDATE SET quantity = quantity + excluded.quantity
    ''',
      [productId, location, delta],
    );
  }

  String _saleStockMovementId(String saleId, String productId) =>
      'sale-${_b64(crypto.sha256.convert(utf8.encode('$saleId:$productId')).bytes)}';

  void close() => _database.close();

  bool get _storeExists =>
      _database.select('SELECT 1 FROM store_meta LIMIT 1').isNotEmpty;

  bool _hasColumn(String table, String column) => _database
      .select('PRAGMA table_info($table)')
      .any((row) => row['name'] == column);

  Future<Map<String, Object?>> _readJsonObject(Request request) async {
    final decoded = jsonDecode(await _readBoundedBody(request, 64 * 1024));
    if (decoded is! Map) throw const FormatException('Expected a JSON object.');
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  String? _requiredText(Object? value, int min, int max) {
    if (value is! String) return null;
    final text = value.trim();
    return text.length >= min && text.length <= max ? text : null;
  }

  String? _optionalSupplierText(
    Map<String, Object?> body,
    String field,
    int maximumLength,
  ) {
    final raw = body[field];
    if (raw == null) return null;
    final text = _requiredText(raw, 0, maximumLength);
    if (text == null || text.isEmpty) return null;
    return text;
  }

  String? _normalizedEmail(Object? value) {
    if (value is! String) return null;
    final email = value.trim().toLowerCase();
    return email.length <= 254 &&
            RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
        ? email
        : null;
  }

  bool _validPassword(Object? value) =>
      value is String && value.length >= 12 && value.length <= 256;

  List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  Future<List<int>> _hashPassword(String password, List<int> salt) async =>
      (await _kdf.deriveKeyFromPassword(
        password: password,
        nonce: salt,
      )).extractBytes();

  String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

  List<int> _unb64(String value) =>
      base64Url.decode(base64Url.normalize(value));

  String _newId() => _b64(_randomBytes(18));

  String _newToken() => _b64(_randomBytes(32));

  String _tokenHash(String token) =>
      _b64(crypto.sha256.convert(utf8.encode(token)).bytes);

  bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }

  void _insertSession(String token, String userId, DateTime now) {
    _database.execute('DELETE FROM sessions WHERE expires_at < ?', [
      now.toIso8601String(),
    ]);
    _database.execute(
      'INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)',
      [
        _tokenHash(token),
        userId,
        now.toIso8601String(),
        now.add(_sessionLifetime).toIso8601String(),
      ],
    );
  }

  Response _sessionResponse(int statusCode, String token, String userId) {
    final user = _database.select(
      'SELECT id, name, email, role FROM users WHERE id = ?',
      [userId],
    ).first;
    final store = _database
        .select('SELECT id, name FROM store_meta WHERE singleton = 1')
        .first;
    return _json(statusCode, {
      'token': token,
      'user': _userJson(user),
      'store': _storeJson(store),
    });
  }

  Map<String, Object?> _userJson(Row row) => {
    'id': row['id'],
    'name': row['name'],
    'email': row['email'],
    'role': row['role'],
  };

  Map<String, Object?> _storeJson(Row row) => {
    'id': row['id'],
    'name': row['name'],
  };

  Map<String, Object?> _productJson(Row row) => {
    'id': row['id'],
    'name': row['name'],
    'category': row['category'],
    'sku': row['sku'],
    'barcode': row['barcode'],
    'unitPriceCents': row['unit_price_cents'],
    'isActive': row['is_active'] == 1,
    'version': row['version'],
    'modifierGroups': jsonDecode(row['modifier_groups_json'] as String),
  };

  Map<String, Object?> _categoryJson(Row row) => {
    'id': row['id'],
    'name': row['name'],
    'isActive': row['is_active'] == 1,
    'version': row['version'],
  };

  Map<String, Object?> _productJsonForDomain(Product product) =>
      product.toJson();

  String? _validateSaleCatalogSnapshots(Sale sale) {
    for (final line in sale.lines) {
      final rows = _database.select(
        'SELECT payload FROM product_versions WHERE product_id = ? AND version = ?',
        [line.productId, line.productVersion],
      );
      if (rows.isEmpty) {
        final exists = _database.select(
          'SELECT id FROM products WHERE id = ?',
          [line.productId],
        );
        if (line.modifiers.isNotEmpty || exists.isNotEmpty) {
          return 'The product version on this sale is no longer available.';
        }
        continue;
      }

      late final Product product;
      try {
        product = Product.fromJson(
          (jsonDecode(rows.first['payload'] as String) as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        );
      } on Object {
        return 'The product version on this sale could not be verified.';
      }
      if (!product.isActive ||
          product.name != line.name ||
          product.unitPriceCents != line.unitPriceCents ||
          product.version != line.productVersion) {
        return 'The product details on this sale do not match its catalog version.';
      }
      final groupsById = {
        for (final group in product.modifierGroups) group.id: group,
      };
      final selectedByGroup = <String, List<SelectedModifier>>{};
      for (final selected in line.modifiers) {
        final group = groupsById[selected.groupId];
        final matchingOptions =
            group?.options
                .where((row) => row.id == selected.optionId)
                .toList() ??
            const <ModifierOption>[];
        final option = matchingOptions.isEmpty ? null : matchingOptions.single;
        if (group == null ||
            option == null ||
            selected.groupName != group.name ||
            selected.name != option.name ||
            selected.priceDeltaCents != option.priceDeltaCents) {
          return 'The selected product options do not match the catalog.';
        }
        selectedByGroup.putIfAbsent(group.id, () => []).add(selected);
      }
      for (final group in product.modifierGroups) {
        final selected =
            selectedByGroup[group.id] ?? const <SelectedModifier>[];
        if (selected.length < group.minimumSelections ||
            selected.length > group.maximumSelections ||
            selected.map((row) => row.optionId).toSet().length !=
                selected.length) {
          return 'The selected options do not satisfy ${group.name}.';
        }
      }
    }
    return null;
  }

  Product? _parseProduct(Map<String, Object?> body, {required String id}) {
    final name = _requiredText(body['name'], 1, 120);
    final category = _requiredText(body['category'], 1, 60);
    final price = body['unitPriceCents'];
    if (name == null ||
        category == null ||
        price is! int ||
        price < 0 ||
        price > 9007199254740991) {
      return null;
    }
    final rawGroups = body['modifierGroups'];
    if (rawGroups != null && rawGroups is! List) return null;
    final List<ModifierGroup> groups;
    try {
      groups = (rawGroups as List<Object?>? ?? const [])
          .map((row) => ModifierGroup.fromJson(row! as Map<String, Object?>))
          .toList(growable: false);
    } on Object {
      return null;
    }
    final version = body['version'] as int? ?? 1;
    if (version < 1 || groups.length > 20) return null;
    final sku = body['sku'] == null ? null : _requiredText(body['sku'], 1, 64);
    final barcode = body['barcode'] == null
        ? null
        : _requiredText(body['barcode'], 1, 64);
    if ((body['sku'] != null && sku == null) ||
        (body['barcode'] != null && barcode == null) ||
        (body['isActive'] != null && body['isActive'] is! bool)) {
      return null;
    }
    final product = Product(
      id: id,
      name: name,
      category: category,
      unitPriceCents: price,
      sku: sku,
      barcode: barcode,
      isActive: body['isActive'] is bool ? body['isActive']! as bool : true,
      version: version,
      modifierGroups: List.unmodifiable(groups),
    );
    try {
      Product.fromJson(product.toJson());
      return product;
    } on Object {
      return null;
    }
  }

  void _insertProduct(Product product, DateTime now) {
    _database.execute(
      'INSERT INTO products (id, name, category, sku, barcode, unit_price_cents, is_active, version, modifier_groups_json, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        product.id,
        product.name,
        product.category,
        product.sku,
        product.barcode,
        product.unitPriceCents,
        product.isActive ? 1 : 0,
        product.version,
        jsonEncode(
          product.modifierGroups.map((group) => group.toJson()).toList(),
        ),
        now.toIso8601String(),
      ],
    );
  }

  Row _insertCategory(String name, String actorId, DateTime now) {
    final id = _newId();
    _database.execute(
      'INSERT INTO catalog_categories (id, name, created_at) VALUES (?, ?, ?)',
      [id, name, now.toIso8601String()],
    );
    _incrementCatalogVersion();
    _audit(actorId, 'catalog.category_created', 'category', id, {'name': name});
    return _database.select('SELECT * FROM catalog_categories WHERE id = ?', [
      id,
    ]).single;
  }

  String? _ensureProductCategory(String name, String actorId, DateTime now) {
    final rows = _database.select(
      'SELECT * FROM catalog_categories WHERE name = ? COLLATE NOCASE',
      [name],
    );
    if (rows.isNotEmpty) {
      return rows.single['is_active'] == 1
          ? rows.single['name'] as String
          : null;
    }
    final category = _insertCategory(name, actorId, now);
    return category['name'] as String;
  }

  Product _copyProduct(
    Product product, {
    required int version,
    String? category,
  }) => Product(
    id: product.id,
    name: product.name,
    category: category ?? product.category,
    unitPriceCents: product.unitPriceCents,
    sku: product.sku,
    barcode: product.barcode,
    isActive: product.isActive,
    version: version,
    modifierGroups: product.modifierGroups,
  );

  void _saveProductVersion(Product product, DateTime now) {
    _database.execute(
      'INSERT OR IGNORE INTO product_versions (product_id, version, payload, created_at) VALUES (?, ?, ?, ?)',
      [
        product.id,
        product.version,
        jsonEncode(product.toJson()),
        now.toIso8601String(),
      ],
    );
  }

  void _incrementCatalogVersion() => _database.execute(
    'UPDATE catalog_meta SET version = version + 1 WHERE singleton = 1',
  );

  void _audit(
    String? actorId,
    String type,
    String entityType,
    String entityId,
    Map<String, Object?> details,
  ) {
    final id = _newId();
    final createdAt = DateTime.now().toUtc().toIso8601String();
    final payload = jsonEncode(details);
    _database.execute(
      'INSERT INTO audit_events (id, actor_user_id, event_type, entity_type, entity_id, details, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [id, actorId, type, entityType, entityId, payload, createdAt],
    );
    _database.execute(
      '''
      INSERT INTO sync_events
        (id, schema_version, event_type, entity_type, entity_id, payload, created_at)
      VALUES (?, 1, ?, ?, ?, ?, ?)
      ''',
      [id, type, entityType, entityId, payload, createdAt],
    );
  }

  _Principal? _principal(Request request) {
    final token = _bearerToken(request);
    if (token == null || token.length > 256) return null;
    final rows = _database.select(
      '''
      SELECT u.id, u.name, u.email, u.role, s.id AS store_id, s.name AS store_name
      FROM sessions x
      JOIN users u ON u.id = x.user_id
      JOIN store_meta s ON s.singleton = 1
      WHERE x.token_hash = ? AND x.revoked_at IS NULL AND x.expires_at > ? AND u.is_active = 1
    ''',
      [_tokenHash(token), DateTime.now().toUtc().toIso8601String()],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final user = _userJson(row);
    return _Principal(
      userId: row['id'] as String,
      role: AccountRole.parse(row['role']),
      user: user,
      store: {'id': row['store_id'], 'name': row['store_name']},
    );
  }

  String? _bearerToken(Request request) {
    final authorization = request.headers['authorization'];
    if (authorization == null || !authorization.startsWith('Bearer ')) {
      return null;
    }
    final token = authorization.substring(7).trim();
    return token.isEmpty ? null : token;
  }

  Response _unauthorized() =>
      _error(401, 'unauthorized', 'Sign in to continue.');

  Response _forbidden() =>
      _error(403, 'forbidden', 'Your role cannot perform this action.');

  _LoginAttempt? _loginAttempt(String email) {
    final rows = _database.select(
      'SELECT attempts, window_started_at, locked_until FROM login_attempts WHERE email = ?',
      [email],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return _LoginAttempt(
      attempts: row['attempts'] as int,
      windowStartedAt: DateTime.parse(row['window_started_at'] as String),
      lockedUntil: row['locked_until'] == null
          ? null
          : DateTime.parse(row['locked_until'] as String),
    );
  }

  bool _recordFailedLogin(String email) {
    final now = DateTime.now().toUtc();
    final attempt = _loginAttempt(email);
    final freshWindow =
        attempt == null ||
        now.difference(attempt.windowStartedAt) > const Duration(minutes: 15);
    final count = freshWindow ? 1 : attempt.attempts + 1;
    final lockout = count >= 5 ? now.add(const Duration(minutes: 15)) : null;
    _database.execute(
      '''
      INSERT INTO login_attempts (email, attempts, window_started_at, locked_until)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(email) DO UPDATE SET attempts = excluded.attempts,
        window_started_at = excluded.window_started_at, locked_until = excluded.locked_until
    ''',
      [
        email,
        count,
        freshWindow
            ? now.toIso8601String()
            : attempt.windowStartedAt.toIso8601String(),
        lockout?.toIso8601String(),
      ],
    );
    return lockout != null;
  }

  int? get catalogVersion =>
      _database
              .select('SELECT version FROM catalog_meta WHERE singleton = 1')
              .first['version']
          as int?;

  int get schemaVersion =>
      _database.select('PRAGMA user_version').first.values.first as int;

  Response _error(int statusCode, String code, String message) =>
      _json(statusCode, {'error': code, 'message': message});

  Response _json(int statusCode, Object body) => Response(
    statusCode,
    body: jsonEncode(body),
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );

  Future<String> _readBoundedBody(Request request, int maximumBytes) async {
    final bytes = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in request.read()) {
      length += chunk.length;
      if (length > maximumBytes) throw const RequestBodyTooLarge();
      bytes.add(chunk);
    }
    return utf8.decode(bytes.takeBytes());
  }
}

DateTime? _reportDate(String? value) {
  if (value == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return null;
  }
  final parsed = DateTime.tryParse('${value}T00:00:00Z');
  if (parsed == null || _reportDayKey(parsed) != value) return null;
  return parsed.toUtc();
}

DateTime? _reportDateTime(Object? value) {
  if (value is! String) return null;
  final parsed = DateTime.tryParse(value);
  return parsed?.toUtc();
}

String _reportDayKey(DateTime value) {
  final utc = value.toUtc();
  final month = utc.month.toString().padLeft(2, '0');
  final day = utc.day.toString().padLeft(2, '0');
  return '${utc.year}-$month-$day';
}

class _Principal {
  const _Principal({
    required this.userId,
    required this.role,
    required this.user,
    required this.store,
  });

  final String userId;
  final AccountRole role;
  final Map<String, Object?> user;
  final Map<String, Object?> store;

  bool get canManageCatalog =>
      role == AccountRole.admin || role == AccountRole.manager;
}

class _LoginAttempt {
  const _LoginAttempt({
    required this.attempts,
    required this.windowStartedAt,
    required this.lockedUntil,
  });

  final int attempts;
  final DateTime windowStartedAt;
  final DateTime? lockedUntil;
}

class RequestBodyTooLarge implements Exception {
  const RequestBodyTooLarge();
}
