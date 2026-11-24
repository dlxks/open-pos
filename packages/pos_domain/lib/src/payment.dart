enum PaymentStatus {
  pending('pending'),
  authorized('authorized'),
  captured('captured'),
  partiallyRefunded('partially_refunded'),
  refunded('refunded'),
  failed('failed'),
  voided('voided');

  const PaymentStatus(this.value);

  final String value;

  static PaymentStatus parse(Object? value) => PaymentStatus.values.firstWhere(
    (status) => status.value == value,
    orElse: () => throw const FormatException('Payment status is invalid.'),
  );
}

class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.saleId,
    required this.provider,
    required this.method,
    required this.status,
    required this.amountCents,
    required this.tenderedCents,
    required this.changeCents,
    required this.createdAt,
    required this.updatedAt,
    this.currency = 'PHP',
    this.providerReference,
    this.refundedCents = 0,
  });

  final String id;
  final String saleId;
  final String provider;
  final String method;
  final PaymentStatus status;
  final int amountCents;
  final int tenderedCents;
  final int changeCents;
  final int refundedCents;
  final String currency;
  final String? providerReference;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'saleId': saleId,
    'provider': provider,
    'method': method,
    'status': status.value,
    'amountCents': amountCents,
    'tenderedCents': tenderedCents,
    'changeCents': changeCents,
    'refundedCents': refundedCents,
    'currency': currency,
    'providerReference': providerReference,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory PaymentRecord.fromJson(Map<String, Object?> json) {
    final record = PaymentRecord(
      id: json['id'] as String,
      saleId: json['saleId'] as String,
      provider: json['provider'] as String,
      method: json['method'] as String,
      status: PaymentStatus.parse(json['status']),
      amountCents: json['amountCents'] as int,
      tenderedCents: json['tenderedCents'] as int,
      changeCents: json['changeCents'] as int,
      refundedCents: json['refundedCents'] as int? ?? 0,
      currency: json['currency'] as String? ?? 'PHP',
      providerReference: json['providerReference'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
    );
    if (record.id.trim().isEmpty ||
        record.saleId.trim().isEmpty ||
        record.provider.trim().isEmpty ||
        record.method.trim().isEmpty ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(record.currency) ||
        record.amountCents <= 0 ||
        record.tenderedCents < record.amountCents ||
        record.changeCents != record.tenderedCents - record.amountCents ||
        record.refundedCents < 0 ||
        record.refundedCents > record.amountCents ||
        (record.status == PaymentStatus.partiallyRefunded &&
            (record.refundedCents == 0 ||
                record.refundedCents == record.amountCents)) ||
        (record.status == PaymentStatus.refunded &&
            record.refundedCents != record.amountCents)) {
      throw const FormatException('Payment record is invalid.');
    }
    return record;
  }

  PaymentRecord withRefundedCents(int value, {DateTime? updatedAt}) {
    final status = value == 0
        ? PaymentStatus.captured
        : value == amountCents
        ? PaymentStatus.refunded
        : PaymentStatus.partiallyRefunded;
    return PaymentRecord(
      id: id,
      saleId: saleId,
      provider: provider,
      method: method,
      status: status,
      amountCents: amountCents,
      tenderedCents: tenderedCents,
      changeCents: changeCents,
      refundedCents: value,
      currency: currency,
      providerReference: providerReference,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  PaymentRecord withStatus(PaymentStatus value, {DateTime? updatedAt}) =>
      PaymentRecord(
        id: id,
        saleId: saleId,
        provider: provider,
        method: method,
        status: value,
        amountCents: amountCents,
        tenderedCents: tenderedCents,
        changeCents: changeCents,
        refundedCents: refundedCents,
        currency: currency,
        providerReference: providerReference,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now().toUtc(),
      );
}
