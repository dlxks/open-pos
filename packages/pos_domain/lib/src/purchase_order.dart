enum PurchaseOrderStatus {
  draft,
  ordered,
  partiallyReceived,
  received,
  cancelled,
}

class PurchaseOrderLine {
  const PurchaseOrderLine({
    required this.id,
    required this.productId,
    required this.productName,
    required this.orderedQuantity,
    required this.receivedQuantity,
    required this.unitCostCents,
    this.sku,
  });

  final String id;
  final String productId;
  final String productName;
  final String? sku;
  final int orderedQuantity;
  final int receivedQuantity;
  final int unitCostCents;

  int get remainingQuantity => orderedQuantity - receivedQuantity;
  int get lineTotalCents => orderedQuantity * unitCostCents;

  Map<String, Object?> toJson() => {
    'id': id,
    'productId': productId,
    'productName': productName,
    'sku': sku,
    'orderedQuantity': orderedQuantity,
    'receivedQuantity': receivedQuantity,
    'unitCostCents': unitCostCents,
    'lineTotalCents': lineTotalCents,
  };

  factory PurchaseOrderLine.fromJson(Map<String, Object?> json) =>
      PurchaseOrderLine(
        id: json['id'] as String,
        productId: json['productId'] as String,
        productName: json['productName'] as String,
        sku: json['sku'] as String?,
        orderedQuantity: json['orderedQuantity'] as int,
        receivedQuantity: json['receivedQuantity'] as int,
        unitCostCents: json['unitCostCents'] as int,
      );
}

class PurchaseOrder {
  const PurchaseOrder({
    required this.id,
    required this.supplierId,
    required this.supplierName,
    required this.status,
    required this.lines,
    required this.createdAt,
    required this.updatedAt,
    required this.version,
    this.expectedAt,
    this.note,
    this.orderedAt,
  });

  final String id;
  final String supplierId;
  final String supplierName;
  final PurchaseOrderStatus status;
  final DateTime? expectedAt;
  final String? note;
  final DateTime? orderedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;
  final List<PurchaseOrderLine> lines;

  int get totalCents =>
      lines.fold(0, (total, line) => total + line.lineTotalCents);
  bool get canReceive =>
      status == PurchaseOrderStatus.ordered ||
      status == PurchaseOrderStatus.partiallyReceived;

  Map<String, Object?> toJson() => {
    'id': id,
    'supplierId': supplierId,
    'supplierName': supplierName,
    'status': _statusName(status),
    'expectedAt': expectedAt == null
        ? null
        : _purchaseOrderDateKey(expectedAt!),
    'note': note,
    'orderedAt': orderedAt?.toUtc().toIso8601String(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'version': version,
    'totalCents': totalCents,
    'lines': lines.map((line) => line.toJson()).toList(growable: false),
  };

  factory PurchaseOrder.fromJson(Map<String, Object?> json) => PurchaseOrder(
    id: json['id'] as String,
    supplierId: json['supplierId'] as String,
    supplierName: json['supplierName'] as String,
    status: _parsePurchaseOrderStatus(json['status'] as String),
    expectedAt: json['expectedAt'] is String
        ? DateTime.parse('${json['expectedAt']}T00:00:00Z')
        : null,
    note: json['note'] as String?,
    orderedAt: json['orderedAt'] is String
        ? DateTime.parse(json['orderedAt']! as String).toUtc()
        : null,
    createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
    updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
    version: json['version'] as int? ?? 1,
    lines: (json['lines'] as List<Object?>)
        .map(
          (line) => PurchaseOrderLine.fromJson(
            (line! as Map).map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList(growable: false),
  );
}

String _statusName(PurchaseOrderStatus status) => switch (status) {
  PurchaseOrderStatus.draft => 'draft',
  PurchaseOrderStatus.ordered => 'ordered',
  PurchaseOrderStatus.partiallyReceived => 'partially_received',
  PurchaseOrderStatus.received => 'received',
  PurchaseOrderStatus.cancelled => 'cancelled',
};

String _purchaseOrderDateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

PurchaseOrderStatus _parsePurchaseOrderStatus(String value) => switch (value) {
  'draft' => PurchaseOrderStatus.draft,
  'ordered' => PurchaseOrderStatus.ordered,
  'partially_received' => PurchaseOrderStatus.partiallyReceived,
  'received' => PurchaseOrderStatus.received,
  'cancelled' => PurchaseOrderStatus.cancelled,
  _ => throw FormatException('Unknown purchase order status: $value'),
};
