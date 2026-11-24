import 'package:pos_domain/pos_domain.dart';
import 'package:test/test.dart';

void main() {
  group('Sale.cash', () {
    test('calculates totals and change in whole centavos', () {
      final sale = Sale.cash(
        id: 'sale-1',
        createdAt: DateTime.utc(2026, 11, 23),
        lines: const [
          SaleLine(
            productId: 'coffee',
            name: 'Brewed coffee',
            unitPriceCents: 8_500,
            quantity: 2,
          ),
          SaleLine(
            productId: 'bread',
            name: 'Pan de sal',
            unitPriceCents: 1_500,
            quantity: 1,
          ),
        ],
        tenderedCents: 20_000,
      );

      expect(sale.totalCents, 18_500);
      expect(sale.changeCents, 1_500);
      expect(sale.createdAt.isUtc, isTrue);
    });

    test('rejects an underpaid cash sale', () {
      expect(
        () => Sale.cash(
          id: 'sale-1',
          createdAt: DateTime.now(),
          lines: const [
            SaleLine(
              productId: 'coffee',
              name: 'Brewed coffee',
              unitPriceCents: 8_500,
              quantity: 1,
            ),
          ],
          tenderedCents: 8_499,
        ),
        throwsArgumentError,
      );
    });

    test('round trips a sale and rejects tampered totals', () {
      final sale = Sale.cash(
        id: 'sale-2',
        createdAt: DateTime.utc(2026, 11, 23),
        lines: const [
          SaleLine(
            productId: 'coffee',
            name: 'Brewed coffee',
            unitPriceCents: 8_500,
            quantity: 1,
          ),
        ],
        tenderedCents: 10_000,
      );

      expect(Sale.fromJson(sale.toJson()).totalCents, 8_500);
      expect(
        () => Sale.fromJson({...sale.toJson(), 'totalCents': 1}),
        throwsFormatException,
      );
    });

    test('retains its cash shift link for offline sync', () {
      final sale = Sale.cash(
        id: 'shifted-sale',
        createdAt: DateTime.utc(2026, 11, 23),
        lines: const [
          SaleLine(
            productId: 'coffee',
            name: 'Brewed coffee',
            unitPriceCents: 8_500,
            quantity: 1,
          ),
        ],
        tenderedCents: 10_000,
        shiftId: 'shift-123',
      );

      final restored = Sale.fromJson(sale.toJson());
      expect(restored.shiftId, 'shift-123');
      expect(restored.toJson(), sale.toJson());
    });

    test('calculates inclusive tax and discounts from the sale snapshot', () {
      final sale = Sale.cash(
        id: 'taxed-sale',
        createdAt: DateTime.utc(2026, 11, 23),
        lines: const [
          SaleLine(
            productId: 'coffee',
            name: 'Coffee',
            unitPriceCents: 1000,
            quantity: 1,
          ),
        ],
        tenderedCents: 1000,
        discountCents: 100,
        discountReason: 'Promotion',
        taxRateBasisPoints: 1000,
        taxIncludedInPrice: true,
      );
      expect(sale.subtotalCents, 1000);
      expect(sale.discountCents, 100);
      expect(sale.taxCents, 82);
      expect(sale.totalCents, 900);
      expect(Sale.fromJson(sale.toJson()).toJson(), sale.toJson());
    });

    test('decodes legacy sale payloads without new snapshot fields', () {
      final sale = Sale.fromJson({
        'id': 'old-sale',
        'createdAt': '2026-11-23T00:00:00.000Z',
        'lines': [
          {
            'productId': 'coffee',
            'name': 'Coffee',
            'unitPriceCents': 100,
            'quantity': 1,
            'totalCents': 100,
          },
        ],
        'totalCents': 100,
        'tenderedCents': 200,
        'changeCents': 100,
        'tenderType': 'cash',
      });
      expect(sale.subtotalCents, 100);
      expect(sale.taxCents, 0);
      expect(sale.discountCents, 0);
    });

    test(
      'prices selected modifiers and retains the product version snapshot',
      () {
        final sale = Sale.cash(
          id: 'custom-order',
          createdAt: DateTime.utc(2026, 11, 23),
          lines: const [
            SaleLine(
              productId: 'latte',
              name: 'Iced latte',
              unitPriceCents: 14_500,
              quantity: 2,
              productVersion: 3,
              modifiers: [
                SelectedModifier(
                  groupId: 'milk',
                  groupName: 'Milk',
                  optionId: 'oat',
                  name: 'Oat milk',
                  priceDeltaCents: 800,
                ),
              ],
            ),
          ],
          tenderedCents: 31_000,
        );

        expect(sale.subtotalCents, 30_600);
        expect(sale.changeCents, 400);
        final restored = Sale.fromJson(sale.toJson());
        expect(restored.lines.single.productVersion, 3);
        expect(restored.lines.single.modifiers.single.name, 'Oat milk');
        expect(restored.toJson(), sale.toJson());
      },
    );
  });
}
