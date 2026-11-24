class CatalogCategory {
  const CatalogCategory({
    required this.id,
    required this.name,
    this.isActive = true,
    this.version = 1,
  });

  final String id;
  final String name;
  final bool isActive;
  final int version;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'isActive': isActive,
    'version': version,
  };

  factory CatalogCategory.fromJson(Map<String, Object?> json) {
    final category = CatalogCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      isActive: json['isActive'] as bool? ?? true,
      version: json['version'] as int? ?? 1,
    );
    if (category.id.trim().isEmpty ||
        category.name.trim().isEmpty ||
        category.name.trim().length > 60 ||
        category.version < 1) {
      throw const FormatException('Catalog category data is invalid.');
    }
    return category;
  }
}
