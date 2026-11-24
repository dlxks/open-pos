class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    required this.isActive,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.contactName,
    this.email,
    this.phone,
    this.address,
    this.notes,
  });

  final String id;
  final String name;
  final String? contactName;
  final String? email;
  final String? phone;
  final String? address;
  final String? notes;
  final bool isActive;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'contactName': contactName,
    'email': email,
    'phone': phone,
    'address': address,
    'notes': notes,
    'isActive': isActive,
    'version': version,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory Supplier.fromJson(Map<String, Object?> json) => Supplier(
    id: json['id'] as String,
    name: json['name'] as String,
    contactName: json['contactName'] as String?,
    email: json['email'] as String?,
    phone: json['phone'] as String?,
    address: json['address'] as String?,
    notes: json['notes'] as String?,
    isActive: json['isActive'] as bool? ?? true,
    version: json['version'] as int? ?? 1,
    createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
    updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
  );
}
