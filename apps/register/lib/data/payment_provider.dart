import 'package:pos_domain/pos_domain.dart';

abstract interface class PaymentProvider {
  String get id;

  Future<PaymentRecord> collect({
    required Sale sale,
    required String paymentId,
  });
}

class CashPaymentProvider implements PaymentProvider {
  const CashPaymentProvider();

  @override
  String get id => 'cash';

  @override
  Future<PaymentRecord> collect({
    required Sale sale,
    required String paymentId,
  }) async {
    final now = sale.createdAt.toUtc();
    return PaymentRecord.fromJson({
      'id': paymentId,
      'saleId': sale.id,
      'provider': id,
      'method': 'cash',
      'status': PaymentStatus.captured.value,
      'amountCents': sale.totalCents,
      'tenderedCents': sale.tenderedCents,
      'changeCents': sale.changeCents,
      'refundedCents': 0,
      'currency': 'PHP',
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    });
  }
}
