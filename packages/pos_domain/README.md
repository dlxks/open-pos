# POS Domain

Shared Dart business rules and JSON models used by the Open POS register and hub.
The package has no Flutter dependency, so the same validation and money rules run
in the client, API, and test suites.

## Included

- Product, store, user, customer, register, inventory, stock movement, and cash
  shift models.
- Integer minor-unit sale arithmetic for subtotal, discounts, inclusive or
  exclusive tax, tender, change, loyalty, returns, and void-safe snapshots.
- Versioned tax and loyalty configuration snapshots for offline sales.
- JSON serialization with legacy sale payload compatibility.

## Use

From another Dart package in this workspace:

```yaml
dependencies:
  pos_domain:
    path: ../../packages/pos_domain
```

```dart
import 'package:pos_domain/pos_domain.dart';

final sale = Sale.cash(
  id: 'sale-001',
  lines: const [
    SaleLine(
      productId: 'coffee-001',
      name: 'Iced latte',
      unitPriceCents: 14500,
      quantity: 1,
    ),
  ],
  cashTenderedCents: 15000,
);
```

Run `dart test` from this directory. See the root README for workspace setup,
deployment, and contribution guidance.
