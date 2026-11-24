import 'modifier.dart';

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.unitPriceCents,
    this.sku,
    this.barcode,
    this.isActive = true,
    this.version = 1,
    this.modifierGroups = const [],
  }) : assert(unitPriceCents >= 0);

  final String id;
  final String name;
  final String category;
  final int unitPriceCents;
  final String? sku;
  final String? barcode;
  final bool isActive;
  final int version;
  final List<ModifierGroup> modifierGroups;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'unitPriceCents': unitPriceCents,
    'sku': sku,
    'barcode': barcode,
    'isActive': isActive,
    'version': version,
    'modifierGroups': modifierGroups
        .map((group) => group.toJson())
        .toList(growable: false),
  };

  factory Product.fromJson(Map<String, Object?> json) {
    final groups = (json['modifierGroups'] as List<Object?>? ?? const [])
        .map((row) => ModifierGroup.fromJson(row! as Map<String, Object?>))
        .toList(growable: false);
    final product = Product(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      unitPriceCents: json['unitPriceCents'] as int,
      sku: json['sku'] as String?,
      barcode: json['barcode'] as String?,
      isActive: json['isActive'] as bool? ?? true,
      version: json['version'] as int? ?? 1,
      modifierGroups: List.unmodifiable(groups),
    );
    if (product.id.trim().isEmpty ||
        product.name.trim().isEmpty ||
        product.category.trim().isEmpty ||
        product.unitPriceCents < 0 ||
        product.version < 1 ||
        groups.length > 20 ||
        groups.map((group) => group.id).toSet().length != groups.length) {
      throw const FormatException('Product data is invalid.');
    }
    return product;
  }
}

const defaultProducts = <Product>[
  Product(
    id: 'latte',
    name: 'Iced latte',
    category: 'Coffee',
    unitPriceCents: 14500,
    sku: 'COF-001',
  ),
  Product(
    id: 'americano',
    name: 'Americano',
    category: 'Coffee',
    unitPriceCents: 11000,
    sku: 'COF-002',
  ),
  Product(
    id: 'cappuccino',
    name: 'Cappuccino',
    category: 'Coffee',
    unitPriceCents: 13500,
    sku: 'COF-003',
  ),
  Product(
    id: 'matcha',
    name: 'Matcha latte',
    category: 'Drinks',
    unitPriceCents: 15500,
    sku: 'DRK-001',
  ),
  Product(
    id: 'pandesal',
    name: 'Pan de sal',
    category: 'Bakery',
    unitPriceCents: 1500,
    sku: 'BAK-001',
  ),
  Product(
    id: 'ensaymada',
    name: 'Ensaymada',
    category: 'Bakery',
    unitPriceCents: 6500,
    sku: 'BAK-002',
  ),
  Product(
    id: 'croissant',
    name: 'Butter croissant',
    category: 'Bakery',
    unitPriceCents: 8500,
    sku: 'BAK-003',
  ),
  Product(
    id: 'silog',
    name: 'Longsilog',
    category: 'Meals',
    unitPriceCents: 17500,
    sku: 'MEA-001',
  ),
  Product(
    id: 'tapsilog',
    name: 'Tapsilog',
    category: 'Meals',
    unitPriceCents: 19500,
    sku: 'MEA-002',
  ),
  Product(
    id: 'lemonade',
    name: 'Calamansi juice',
    category: 'Drinks',
    unitPriceCents: 7500,
    sku: 'DRK-002',
  ),
  Product(
    id: 'water',
    name: 'Bottled water',
    category: 'Drinks',
    unitPriceCents: 3500,
    sku: 'DRK-003',
  ),
  Product(
    id: 'cookies',
    name: 'Chocolate cookies',
    category: 'Bakery',
    unitPriceCents: 5500,
    sku: 'BAK-004',
  ),
];
