import 'package:pos_domain/pos_domain.dart';
import 'package:test/test.dart';

void main() {
  test('category JSON preserves active state and version', () {
    const category = CatalogCategory(
      id: 'category-1',
      name: 'Bakery',
      isActive: false,
      version: 3,
    );

    expect(
      CatalogCategory.fromJson(category.toJson()).toJson(),
      category.toJson(),
    );
  });

  test('rejects invalid category snapshots', () {
    expect(
      () => CatalogCategory.fromJson({
        'id': 'category-1',
        'name': 'x'.padRight(61, 'x'),
      }),
      throwsFormatException,
    );
  });
}
