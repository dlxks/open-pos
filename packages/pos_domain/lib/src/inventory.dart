enum StockMovementType { receive, adjustment, transfer, sale }

class InventoryItem {
  const InventoryItem({
    required this.productId,
    required this.name,
    required this.onHand,
    required this.lowStockThreshold,
    this.sku,
    this.locations = const [],
  });

  final String productId;
  final String name;
  final String? sku;
  final int onHand;
  final int lowStockThreshold;
  final List<StockLocationBalance> locations;

  bool get isLowStock => onHand <= lowStockThreshold;

  factory InventoryItem.fromJson(Map<String, Object?> json) => InventoryItem(
    productId: json['productId'] as String,
    name: json['name'] as String,
    sku: json['sku'] as String?,
    onHand: json['onHand'] as int,
    lowStockThreshold: json['lowStockThreshold'] as int,
    locations: (json['locations'] as List<Object?>? ?? const [])
        .map(
          (location) =>
              StockLocationBalance.fromJson(location! as Map<String, Object?>),
        )
        .toList(growable: false),
  );
}

class StockLocationBalance {
  const StockLocationBalance({required this.location, required this.quantity});

  final String location;
  final int quantity;

  factory StockLocationBalance.fromJson(Map<String, Object?> json) =>
      StockLocationBalance(
        location: json['location'] as String,
        quantity: json['quantity'] as int,
      );
}

class StockMovement {
  const StockMovement({
    required this.id,
    required this.productId,
    required this.type,
    required this.quantity,
    required this.createdAt,
    this.productName,
    this.sourceLocation,
    this.destinationLocation,
    this.note,
  });

  final String id;
  final String productId;
  final StockMovementType type;
  final int quantity;
  final String? sourceLocation;
  final String? destinationLocation;
  final String? note;
  final DateTime createdAt;
  final String? productName;

  factory StockMovement.fromJson(Map<String, Object?> json) => StockMovement(
    id: json['id'] as String,
    productId: json['productId'] as String,
    type: StockMovementType.values.byName(json['type'] as String),
    quantity: json['quantity'] as int,
    productName: json['productName'] as String?,
    sourceLocation: json['sourceLocation'] as String?,
    destinationLocation: json['destinationLocation'] as String?,
    note: json['note'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}
