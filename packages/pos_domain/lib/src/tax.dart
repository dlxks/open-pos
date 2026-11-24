class TaxConfig {
  const TaxConfig({
    this.name = 'Tax',
    this.rateBasisPoints = 0,
    this.pricesIncludeTax = false,
    this.version = 1,
  });

  final String name;
  final int rateBasisPoints;
  final bool pricesIncludeTax;
  final int version;

  double get percentage => rateBasisPoints / 100;

  Map<String, Object?> toJson() => {
    'name': name,
    'rateBasisPoints': rateBasisPoints,
    'pricesIncludeTax': pricesIncludeTax,
    'version': version,
  };

  factory TaxConfig.fromJson(Map<String, Object?> json) {
    final value = TaxConfig(
      name: json['name'] as String? ?? 'Tax',
      rateBasisPoints: json['rateBasisPoints'] as int? ?? 0,
      pricesIncludeTax: json['pricesIncludeTax'] as bool? ?? false,
      version: json['version'] as int? ?? 1,
    );
    if (value.name.trim().isEmpty ||
        value.name.length > 40 ||
        value.rateBasisPoints < 0 ||
        value.rateBasisPoints > 10000 ||
        value.version < 1) {
      throw const FormatException('Tax configuration is invalid.');
    }
    return value;
  }
}
