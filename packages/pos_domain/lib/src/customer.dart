class Customer {
  const Customer({
    required this.id,
    required this.name,
    required this.loyaltyPoints,
    this.phone,
    this.email,
  });

  final String id;
  final String name;
  final String? phone;
  final String? email;
  final int loyaltyPoints;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'email': email,
    'loyaltyPoints': loyaltyPoints,
  };

  factory Customer.fromJson(Map<String, Object?> json) => Customer(
    id: json['id'] as String,
    name: json['name'] as String,
    phone: json['phone'] as String?,
    email: json['email'] as String?,
    loyaltyPoints: json['loyaltyPoints'] as int? ?? 0,
  );
}

class LoyaltyConfig {
  const LoyaltyConfig({
    this.earnPointsPer100Cents = 1,
    this.redeemCentsPerPoint = 1,
    this.version = 1,
  });

  final int earnPointsPer100Cents;
  final int redeemCentsPerPoint;
  final int version;

  Map<String, Object?> toJson() => {
    'earnPointsPer100Cents': earnPointsPer100Cents,
    'redeemCentsPerPoint': redeemCentsPerPoint,
    'version': version,
  };

  factory LoyaltyConfig.fromJson(Map<String, Object?> json) {
    final value = LoyaltyConfig(
      earnPointsPer100Cents: json['earnPointsPer100Cents'] as int? ?? 1,
      redeemCentsPerPoint: json['redeemCentsPerPoint'] as int? ?? 1,
      version: json['version'] as int? ?? 1,
    );
    if (value.earnPointsPer100Cents < 0 ||
        value.earnPointsPer100Cents > 1000 ||
        value.redeemCentsPerPoint < 1 ||
        value.redeemCentsPerPoint > 100000 ||
        value.version < 1) {
      throw const FormatException('Loyalty configuration is invalid.');
    }
    return value;
  }
}
