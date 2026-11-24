import 'modifier.dart';

class SaleLine {
  const SaleLine({
    required this.productId,
    required this.name,
    required this.unitPriceCents,
    required this.quantity,
    this.productVersion = 1,
    this.modifiers = const [],
  }) : assert(unitPriceCents >= 0 && quantity > 0);

  final String productId;
  final String name;
  final int unitPriceCents;
  final int quantity;
  final int productVersion;
  final List<SelectedModifier> modifiers;

  int get modifierDeltaCents =>
      modifiers.fold(0, (sum, modifier) => sum + modifier.priceDeltaCents);

  int get unitTotalCents => unitPriceCents + modifierDeltaCents;

  int get totalCents => unitTotalCents * quantity;

  Map<String, Object> toJson() => {
    'productId': productId,
    'name': name,
    'unitPriceCents': unitPriceCents,
    'quantity': quantity,
    'productVersion': productVersion,
    'modifiers': modifiers.map((modifier) => modifier.toJson()).toList(),
    'totalCents': totalCents,
  };

  factory SaleLine.fromJson(Map<String, Object?> json) {
    final line = SaleLine(
      productId: json['productId'] as String,
      name: json['name'] as String,
      unitPriceCents: json['unitPriceCents'] as int,
      quantity: json['quantity'] as int,
      productVersion: json['productVersion'] as int? ?? 1,
      modifiers: (json['modifiers'] as List<Object?>? ?? const [])
          .map((row) => SelectedModifier.fromJson(row! as Map<String, Object?>))
          .toList(growable: false),
    );
    if (line.unitTotalCents < 0 ||
        line.productVersion < 1 ||
        line.totalCents != json['totalCents']) {
      throw const FormatException('Sale line total does not match its price.');
    }
    return line;
  }
}

class Sale {
  Sale._({
    required this.id,
    required this.createdAt,
    required this.lines,
    required this.totalCents,
    required this.tenderedCents,
    required this.changeCents,
    this.shiftId,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.taxRateBasisPoints,
    required this.taxIncludedInPrice,
    required this.taxName,
    required this.taxConfigVersion,
    this.discountReason,
    this.customerId,
    required this.pointsRedeemed,
    required this.loyaltyDiscountCents,
    required this.loyaltyConfigVersion,
    this.registerId,
  });

  final String id;
  final DateTime createdAt;
  final List<SaleLine> lines;
  final int totalCents;
  final int tenderedCents;
  final int changeCents;
  final String? shiftId;
  final int subtotalCents;
  final int discountCents;
  final int taxCents;
  final int taxRateBasisPoints;
  final bool taxIncludedInPrice;
  final String taxName;
  final int taxConfigVersion;
  final String? discountReason;
  final String? customerId;
  final int pointsRedeemed;
  final int loyaltyDiscountCents;
  final int loyaltyConfigVersion;
  final String? registerId;

  factory Sale.cash({
    required String id,
    required DateTime createdAt,
    required Iterable<SaleLine> lines,
    required int tenderedCents,
    String? shiftId,
    int discountCents = 0,
    String? discountReason,
    int taxRateBasisPoints = 0,
    bool taxIncludedInPrice = false,
    String taxName = 'Tax',
    int taxConfigVersion = 1,
    String? customerId,
    int pointsRedeemed = 0,
    int loyaltyDiscountCents = 0,
    int loyaltyConfigVersion = 1,
    String? registerId,
  }) {
    final snapshot = List<SaleLine>.unmodifiable(lines);
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be empty.');
    }
    if (shiftId != null && shiftId.trim().isEmpty) {
      throw ArgumentError.value(shiftId, 'shiftId', 'Must not be empty.');
    }
    if (registerId != null && registerId.trim().isEmpty) {
      throw ArgumentError.value(registerId, 'registerId', 'Must not be empty.');
    }
    if (customerId != null && customerId.trim().isEmpty) {
      throw ArgumentError.value(customerId, 'customerId', 'Must not be empty.');
    }
    if (pointsRedeemed < 0 ||
        pointsRedeemed > 9007199254740991 ||
        loyaltyDiscountCents > 9007199254740991 ||
        (pointsRedeemed > 0 && customerId == null)) {
      throw ArgumentError(
        'Loyalty points require a customer and cannot be negative.',
      );
    }
    if (loyaltyDiscountCents < 0 ||
        loyaltyDiscountCents > discountCents ||
        (pointsRedeemed == 0 && loyaltyDiscountCents != 0) ||
        (pointsRedeemed > 0 && loyaltyDiscountCents == 0)) {
      throw ArgumentError(
        'Loyalty redemption details do not match the discount.',
      );
    }
    if (taxRateBasisPoints < 0 || taxRateBasisPoints > 10000) {
      throw ArgumentError.value(
        taxRateBasisPoints,
        'taxRateBasisPoints',
        'Must be between 0 and 10000 basis points.',
      );
    }
    if (taxName.trim().isEmpty ||
        taxName.trim().length > 40 ||
        taxConfigVersion < 1 ||
        loyaltyConfigVersion < 1) {
      throw ArgumentError(
        'Tax and loyalty snapshots must have valid versions and labels.',
      );
    }
    if (snapshot.isEmpty) {
      throw ArgumentError.value(lines, 'lines', 'A sale must contain an item.');
    }

    var subtotal = 0;
    for (final line in snapshot) {
      if (line.productId.trim().isEmpty || line.name.trim().isEmpty) {
        throw ArgumentError('Sale lines require a product and name.');
      }
      if (line.unitPriceCents < 0 ||
          line.quantity <= 0 ||
          line.productVersion < 1) {
        throw ArgumentError('Sale prices and quantities are invalid.');
      }
      final selectedOptionIds = line.modifiers
          .map((modifier) => '${modifier.groupId}\u0000${modifier.optionId}')
          .toSet();
      final uniqueGroupOptionPairs =
          line.modifiers.length == selectedOptionIds.length;
      if (!uniqueGroupOptionPairs ||
          line.unitTotalCents < 0 ||
          line.unitTotalCents > 9007199254740991) {
        throw ArgumentError(
          'Sale modifier totals exceed safe integer precision.',
        );
      }
      if (line.unitTotalCents > 0 &&
          line.quantity > 9007199254740991 ~/ line.unitTotalCents) {
        throw ArgumentError('Sale line exceeds safe integer precision.');
      }
      subtotal += line.totalCents;
      if (subtotal > 9007199254740991) {
        throw ArgumentError('Sale exceeds safe integer precision.');
      }
    }
    if (discountCents < 0 || discountCents > subtotal) {
      throw ArgumentError.value(
        discountCents,
        'discountCents',
        'Discount must be between zero and the subtotal.',
      );
    }
    final normalizedDiscountReason = discountReason?.trim();
    if (discountCents > 0 &&
        (normalizedDiscountReason == null ||
            normalizedDiscountReason.isEmpty ||
            normalizedDiscountReason.length > 240)) {
      throw ArgumentError('Discounts require a reason.');
    }
    if (discountCents == 0 && normalizedDiscountReason != null) {
      throw ArgumentError('A discount reason requires a discount.');
    }
    final discountedSubtotal = subtotal - discountCents;
    final tax = _roundedRatio(
      discountedSubtotal,
      taxRateBasisPoints,
      taxIncludedInPrice ? 10000 + taxRateBasisPoints : 10000,
    );
    final total = taxIncludedInPrice
        ? discountedSubtotal
        : discountedSubtotal + tax;
    if (total > 9007199254740991) {
      throw ArgumentError('Sale exceeds safe integer precision.');
    }
    if (tenderedCents < total || tenderedCents > 9007199254740991) {
      throw ArgumentError.value(
        tenderedCents,
        'tenderedCents',
        'Cash tendered must cover the sale total and stay within safe integer precision.',
      );
    }

    return Sale._(
      id: id,
      createdAt: createdAt.toUtc(),
      lines: snapshot,
      totalCents: total,
      tenderedCents: tenderedCents,
      changeCents: tenderedCents - total,
      shiftId: shiftId,
      subtotalCents: subtotal,
      discountCents: discountCents,
      taxCents: tax,
      taxRateBasisPoints: taxRateBasisPoints,
      taxIncludedInPrice: taxIncludedInPrice,
      taxName: taxName.trim(),
      taxConfigVersion: taxConfigVersion,
      discountReason: normalizedDiscountReason,
      customerId: customerId,
      pointsRedeemed: pointsRedeemed,
      loyaltyDiscountCents: loyaltyDiscountCents,
      loyaltyConfigVersion: loyaltyConfigVersion,
      registerId: registerId,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'lines': lines.map((line) => line.toJson()).toList(growable: false),
    'totalCents': totalCents,
    'tenderedCents': tenderedCents,
    'changeCents': changeCents,
    'tenderType': 'cash',
    if (shiftId != null) 'shiftId': shiftId,
    'subtotalCents': subtotalCents,
    'discountCents': discountCents,
    'taxCents': taxCents,
    'taxRateBasisPoints': taxRateBasisPoints,
    'taxIncludedInPrice': taxIncludedInPrice,
    'taxName': taxName,
    'taxConfigVersion': taxConfigVersion,
    if (discountReason != null) 'discountReason': discountReason,
    if (customerId != null) 'customerId': customerId,
    'pointsRedeemed': pointsRedeemed,
    'loyaltyDiscountCents': loyaltyDiscountCents,
    'loyaltyConfigVersion': loyaltyConfigVersion,
    if (registerId != null) 'registerId': registerId,
  };

  factory Sale.fromJson(Map<String, Object?> json) {
    if (json['tenderType'] != 'cash') {
      throw const FormatException(
        'Only cash tender is supported in this release.',
      );
    }
    final rawLines = json['lines'] as List<Object?>;
    final sale = Sale.cash(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lines: rawLines
          .map((line) => SaleLine.fromJson(line! as Map<String, Object?>))
          .toList(growable: false),
      tenderedCents: json['tenderedCents'] as int,
      shiftId: json['shiftId'] as String?,
      discountCents: json['discountCents'] as int? ?? 0,
      discountReason: json['discountReason'] as String?,
      taxRateBasisPoints: json['taxRateBasisPoints'] as int? ?? 0,
      taxIncludedInPrice: json['taxIncludedInPrice'] as bool? ?? false,
      taxName: json['taxName'] as String? ?? 'Tax',
      taxConfigVersion: json['taxConfigVersion'] as int? ?? 1,
      customerId: json['customerId'] as String?,
      pointsRedeemed: json['pointsRedeemed'] as int? ?? 0,
      loyaltyDiscountCents: json['loyaltyDiscountCents'] as int? ?? 0,
      loyaltyConfigVersion: json['loyaltyConfigVersion'] as int? ?? 1,
      registerId: json['registerId'] as String?,
    );
    if (sale.totalCents != json['totalCents'] ||
        sale.changeCents != json['changeCents'] ||
        (json['subtotalCents'] is int &&
            sale.subtotalCents != json['subtotalCents']) ||
        (json['taxCents'] is int && sale.taxCents != json['taxCents'])) {
      throw const FormatException(
        'Sale totals do not match its items, tax, or discount.',
      );
    }
    return sale;
  }
}

int _roundedRatio(int amount, int numerator, int denominator) {
  if (amount == 0 || numerator == 0) return 0;
  final value =
      (BigInt.from(amount) * BigInt.from(numerator) +
          BigInt.from(denominator ~/ 2)) ~/
      BigInt.from(denominator);
  if (value > BigInt.from(9007199254740991)) {
    throw ArgumentError('Calculated tax exceeds safe integer precision.');
  }
  return value.toInt();
}
