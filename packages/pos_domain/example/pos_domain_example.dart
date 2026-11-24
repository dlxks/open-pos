import 'package:pos_domain/pos_domain.dart';

void main() {
  final sale = Sale.cash(
    id: 'sale-example',
    createdAt: DateTime.now(),
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

  print('Sale total: ${sale.totalCents} cents');
  print('Cash change: ${sale.changeCents} cents');
}
