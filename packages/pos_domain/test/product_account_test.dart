import 'package:pos_domain/pos_domain.dart';
import 'package:test/test.dart';

void main() {
  test('product JSON preserves barcode, price, and archive state', () {
    const product = Product(
      id: 'tea-1',
      name: 'House tea',
      category: 'Drinks',
      unitPriceCents: 4_250,
      sku: 'TEA-01',
      barcode: '4800000000012',
      isActive: false,
    );

    expect(Product.fromJson(product.toJson()).toJson(), product.toJson());
  });

  test('account roles parse only the supported API values', () {
    expect(AccountRole.parse('admin'), AccountRole.admin);
    expect(AccountRole.parse('manager').label, 'Manager');
    expect(() => AccountRole.parse('superuser'), throwsFormatException);
  });

  test(
    'session JSON contains identity and store without exposing passwords',
    () {
      const session = HubSession(
        token: 'opaque-token',
        user: PosUser(
          id: 'user-1',
          name: 'A. Cashier',
          email: 'cashier@example.test',
          role: AccountRole.cashier,
        ),
        store: PosStore(id: 'store-1', name: 'Corner Store'),
      );

      expect(HubSession.fromJson(session.toJson()).toJson(), session.toJson());
      expect(session.toJson().toString(), isNot(contains('password')));
    },
  );
}
