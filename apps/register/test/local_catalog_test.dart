import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_pos/data/local_database.dart';
import 'package:pos_domain/pos_domain.dart';

void main() {
  late PosDatabase database;

  setUp(() {
    database = PosDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => database.close());

  test('stores catalog products and version for offline startup', () async {
    const product = Product(
      id: 'tea-1',
      name: 'House tea',
      category: 'Drinks',
      unitPriceCents: 4_250,
      sku: 'TEA-01',
      barcode: '4800000000012',
    );
    await database.replaceCachedProducts(8, const [product]);

    final cached = await database.readCachedCatalog();
    expect(cached?.version, 8);
    expect(cached?.products.single.toJson(), product.toJson());

    await database.replaceCachedProducts(9, const []);
    final updated = await database.readCachedCatalog();
    expect(updated?.version, 9);
    expect(updated?.products, isEmpty);
  });

  test(
    'keeps managed categories available in the offline catalog cache',
    () async {
      const category = CatalogCategory(id: 'category-1', name: 'Drinks');
      await database.replaceCachedProducts(
        10,
        const [],
        categories: const [category],
      );

      final cached = await database.readCachedCatalog();
      expect(cached?.categories.single.toJson(), category.toJson());

      await database.saveCachedCategories([
        const CatalogCategory(
          id: 'category-1',
          name: 'Drinks',
          isActive: false,
          version: 2,
        ),
      ]);
      expect((await database.readCachedCategories())?.single.isActive, isFalse);
    },
  );

  test(
    'stores and clears a cash shift snapshot for offline register startup',
    () async {
      final shift = CashShift(
        id: 'shift-1',
        openedAt: DateTime.utc(2026, 11, 23, 9),
        openingFloatCents: 10_000,
        expectedCashCents: 12_500,
        isOpen: true,
      );
      await database.saveCachedShift(shift);

      expect((await database.readCachedShift())?.toJson(), shift.toJson());

      await database.saveCachedShift(null);
      expect(await database.readCachedShift(), isNull);
    },
  );

  test(
    'caches register identity and inventory for offline operations',
    () async {
      await database.saveRegisterIdentity(id: 'register-1', name: 'Front till');
      expect(await database.readOperationalValue('register_id'), 'register-1');
      expect(
        await database.readOperationalValue('register_name'),
        'Front till',
      );
      await database.cacheInventory(const [
        InventoryItem(
          productId: 'coffee',
          name: 'Coffee',
          onHand: 4,
          lowStockThreshold: 2,
          locations: [StockLocationBalance(location: 'Main', quantity: 4)],
        ),
      ]);
      expect((await database.readCachedInventory())?.single.onHand, 4);
    },
  );

  test(
    'adds the operations cache without losing version-two register data',
    () async {
      await database.close();
      database = PosDatabase.forTesting(
        NativeDatabase.memory(
          setup: (sqlite) {
            sqlite.execute('''
              CREATE TABLE local_sales (
                id TEXT NOT NULL PRIMARY KEY,
                payload TEXT NOT NULL,
                total_cents INTEGER NOT NULL,
                created_at INTEGER NOT NULL,
                synced_at INTEGER
              )
            ''');
            sqlite.execute('''
              CREATE TABLE local_products (
                id TEXT NOT NULL PRIMARY KEY,
                payload TEXT NOT NULL
              )
            ''');
            sqlite.execute('''
              CREATE TABLE local_catalog_versions (
                id INTEGER NOT NULL PRIMARY KEY,
                version INTEGER NOT NULL
              )
            ''');
            sqlite.execute(
              'INSERT INTO local_sales (id, payload, total_cents, created_at) VALUES (?, ?, ?, ?)',
              ['legacy-sale', '{}', 100, 1799999999],
            );
            sqlite.execute(
              'INSERT INTO local_catalog_versions (id, version) VALUES (1, 7)',
            );
            sqlite.execute('PRAGMA user_version = 2');
          },
        ),
      );
      expect(
        (await database.select(database.localSales).get()).single.id,
        'legacy-sale',
      );
      expect(await database.readCachedShift(), isNull);
      expect(
        await database.select(database.localStockOperations).get(),
        isEmpty,
      );
      expect(
        (await database.select(database.localCatalogVersions).get())
            .single
            .version,
        7,
      );
    },
  );
}
