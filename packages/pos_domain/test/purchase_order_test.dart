import 'package:pos_domain/pos_domain.dart';
import 'package:test/test.dart';

void main() {
  test('supplier JSON round trip preserves optional details and version', () {
    final supplier = Supplier(
      id: 'supplier-1',
      name: 'Blue Coast Supply',
      contactName: 'Alex Reyes',
      email: 'orders@example.test',
      phone: '555-0100',
      address: '12 Market Road',
      notes: 'Delivers on Tuesdays',
      isActive: false,
      version: 3,
      createdAt: DateTime.utc(2026, 11, 24, 8),
      updatedAt: DateTime.utc(2026, 11, 24, 9),
    );

    expect(Supplier.fromJson(supplier.toJson()).toJson(), supplier.toJson());
  });

  test('purchase order JSON round trip preserves partial receipt state', () {
    final purchaseOrder = PurchaseOrder(
      id: 'po-1',
      supplierId: 'supplier-1',
      supplierName: 'Blue Coast Supply',
      status: PurchaseOrderStatus.partiallyReceived,
      expectedAt: DateTime.utc(2026, 12, 1),
      note: 'Weekly coffee stock',
      orderedAt: DateTime.utc(2026, 11, 24, 7),
      createdAt: DateTime.utc(2026, 11, 24, 6),
      updatedAt: DateTime.utc(2026, 11, 24, 8),
      version: 3,
      lines: const [
        PurchaseOrderLine(
          id: 'line-1',
          productId: 'coffee',
          productName: 'Coffee',
          sku: 'COF-001',
          orderedQuantity: 5,
          receivedQuantity: 2,
          unitCostCents: 400,
        ),
      ],
    );

    final restored = PurchaseOrder.fromJson(purchaseOrder.toJson());
    expect(restored.toJson(), purchaseOrder.toJson());
    expect(restored.totalCents, 2_000);
    expect(restored.lines.single.remainingQuantity, 3);
    expect(restored.canReceive, isTrue);
  });

  test('purchase order status parser rejects unknown server values', () {
    final purchaseOrder = PurchaseOrder(
      id: 'po-1',
      supplierId: 'supplier-1',
      supplierName: 'Blue Coast Supply',
      status: PurchaseOrderStatus.draft,
      createdAt: DateTime.utc(2026, 11, 24),
      updatedAt: DateTime.utc(2026, 11, 24),
      version: 1,
      lines: const [],
    );

    expect(
      () => PurchaseOrder.fromJson({
        ...purchaseOrder.toJson(),
        'status': 'unexpected',
      }),
      throwsFormatException,
    );
  });
}
