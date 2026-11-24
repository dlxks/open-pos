import 'package:pos_domain/pos_domain.dart';
import 'package:test/test.dart';

void main() {
  test(
    'payment record keeps capture and refund state separate from a sale',
    () {
      final captured = PaymentRecord(
        id: 'payment-1',
        saleId: 'sale-1',
        provider: 'cash',
        method: 'cash',
        status: PaymentStatus.captured,
        amountCents: 1250,
        tenderedCents: 2000,
        changeCents: 750,
        createdAt: DateTime.utc(2026, 11, 23),
        updatedAt: DateTime.utc(2026, 11, 23),
      );

      final refunded = captured.withRefundedCents(
        400,
        updatedAt: DateTime.utc(2026, 11, 24),
      );
      expect(refunded.status, PaymentStatus.partiallyRefunded);
      expect(refunded.refundedCents, 400);
      expect(
        PaymentRecord.fromJson(refunded.toJson()).toJson(),
        refunded.toJson(),
      );
      expect(
        () => PaymentRecord.fromJson({...captured.toJson(), 'changeCents': 0}),
        throwsFormatException,
      );
    },
  );
}
