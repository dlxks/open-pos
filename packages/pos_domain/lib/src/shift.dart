class CashShift {
  const CashShift({
    required this.id,
    required this.openedAt,
    required this.openingFloatCents,
    required this.expectedCashCents,
    required this.isOpen,
    this.registerId = 'main',
    this.closedAt,
    this.countedCashCents,
    this.varianceCents,
  });

  final String id;
  final DateTime openedAt;
  final int openingFloatCents;
  final int expectedCashCents;
  final bool isOpen;
  final String registerId;
  final DateTime? closedAt;
  final int? countedCashCents;
  final int? varianceCents;

  Map<String, Object?> toJson() => {
    'id': id,
    'openedAt': openedAt.toUtc().toIso8601String(),
    'openingFloatCents': openingFloatCents,
    'expectedCashCents': expectedCashCents,
    'isOpen': isOpen,
    'registerId': registerId,
    'closedAt': closedAt?.toUtc().toIso8601String(),
    'countedCashCents': countedCashCents,
    'varianceCents': varianceCents,
  };

  factory CashShift.fromJson(Map<String, Object?> json) => CashShift(
    id: json['id'] as String,
    openedAt: DateTime.parse(json['openedAt'] as String),
    openingFloatCents: json['openingFloatCents'] as int,
    expectedCashCents: json['expectedCashCents'] as int,
    isOpen: json['isOpen'] as bool,
    registerId: json['registerId'] as String? ?? 'main',
    closedAt: json['closedAt'] == null
        ? null
        : DateTime.parse(json['closedAt'] as String),
    countedCashCents: json['countedCashCents'] as int?,
    varianceCents: json['varianceCents'] as int?,
  );
}
