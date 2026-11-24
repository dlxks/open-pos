import 'package:pos_domain/pos_domain.dart';
import 'package:test/test.dart';

void main() {
  test('inventory item marks stock at threshold as low', () {
    final item = InventoryItem.fromJson({
      'productId': 'coffee',
      'name': 'Coffee',
      'onHand': 3,
      'lowStockThreshold': 3,
      'locations': [
        {'location': 'Main', 'quantity': 1},
        {'location': 'Front shelf', 'quantity': 2},
      ],
    });

    expect(item.isLowStock, isTrue);
    expect(item.locations.map((location) => location.quantity), [1, 2]);
    expect(
      InventoryItem.fromJson({
        'productId': 'tea',
        'name': 'Tea',
        'onHand': 4,
        'lowStockThreshold': 3,
      }).isLowStock,
      isFalse,
    );
  });

  test('cash shift JSON preserves open and reconciled shift fields', () {
    final shift = CashShift(
      id: 'shift-123',
      openedAt: DateTime.utc(2026, 11, 23, 9),
      openingFloatCents: 10_000,
      expectedCashCents: 12_000,
      isOpen: false,
      closedAt: DateTime.utc(2026, 11, 23, 17),
      countedCashCents: 11_900,
      varianceCents: -100,
    );

    expect(CashShift.fromJson(shift.toJson()).toJson(), shift.toJson());
  });
}
