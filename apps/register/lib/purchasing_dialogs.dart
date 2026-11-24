// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:open_pos/data/pos_repository.dart';
import 'package:pos_domain/pos_domain.dart';
import 'package:uuid/uuid.dart';

const _purchaseInk = Color(0xFF173432);
const _purchaseLeaf = Color(0xFF0D7468);
const _purchaseMuted = Color(0xFF73827D);
const _purchaseLine = Color(0xFFE3E8E3);

Future<void> showPurchasingManagement({
  required BuildContext context,
  required PosRepository repository,
  required List<Product> products,
}) => showDialog<void>(
  context: context,
  builder: (context) =>
      PurchasingManagementDialog(repository: repository, products: products),
);

class PurchasingManagementDialog extends StatefulWidget {
  const PurchasingManagementDialog({
    super.key,
    required this.repository,
    required this.products,
  });

  final PosRepository repository;
  final List<Product> products;

  @override
  State<PurchasingManagementDialog> createState() =>
      _PurchasingManagementDialogState();
}

class _PurchasingManagementDialogState extends State<PurchasingManagementDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<Supplier> _suppliers = const [];
  List<PurchaseOrder> _orders = const [];
  bool _loading = true;
  bool _offlineSnapshot = false;
  String? _error;
  final Set<String> _busyOrders = {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _refresh();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final suppliers = await widget.repository.fetchSuppliers();
      final orders = await widget.repository.fetchPurchaseOrders();
      if (!mounted) return;
      setState(() {
        _suppliers = suppliers.items;
        _orders = orders.items;
        _offlineSnapshot = suppliers.fromCache || orders.fromCache;
        _loading = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _editSupplier([Supplier? supplier]) async {
    final saved = await showDialog<Supplier>(
      context: context,
      builder: (context) => _SupplierEditorDialog(
        repository: widget.repository,
        initial: supplier,
      ),
    );
    if (saved != null) await _refresh();
  }

  Future<void> _setSupplierActive(Supplier supplier, bool isActive) async {
    try {
      await widget.repository.setSupplierActive(
        supplierId: supplier.id,
        isActive: isActive,
        expectedVersion: supplier.version,
      );
      await _refresh();
    } on Exception catch (error) {
      _showError(error);
    }
  }

  Future<void> _createOrder() async {
    final activeSuppliers = _suppliers.where((item) => item.isActive).toList();
    final activeProducts = widget.products
        .where((item) => item.isActive)
        .toList();
    if (activeSuppliers.isEmpty) {
      _showMessage('Add an active supplier before creating an order.');
      _tabs.animateTo(0);
      return;
    }
    if (activeProducts.isEmpty) {
      _showMessage('Add an active product before creating an order.');
      return;
    }
    final order = await showDialog<PurchaseOrder>(
      context: context,
      builder: (context) => _PurchaseOrderEditorDialog(
        repository: widget.repository,
        suppliers: activeSuppliers,
        products: activeProducts,
      ),
    );
    if (order != null) await _refresh();
  }

  Future<void> _place(PurchaseOrder order) =>
      _runOrderAction(order, widget.repository.placePurchaseOrder);

  Future<void> _cancel(PurchaseOrder order) =>
      _runOrderAction(order, widget.repository.cancelPurchaseOrder);

  Future<void> _runOrderAction(
    PurchaseOrder order,
    Future<PurchaseOrder> Function(String id) action,
  ) async {
    setState(() => _busyOrders.add(order.id));
    try {
      final updated = await action(order.id);
      if (!mounted) return;
      setState(() {
        _replaceOrder(updated);
        _busyOrders.remove(order.id);
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _busyOrders.remove(order.id));
      _showError(error);
    }
  }

  Future<void> _receive(PurchaseOrder order) async {
    final updated = await showDialog<PurchaseOrder>(
      context: context,
      builder: (context) => _ReceivePurchaseOrderDialog(
        repository: widget.repository,
        order: order,
      ),
    );
    if (updated != null && mounted) {
      setState(() => _replaceOrder(updated));
    }
  }

  void _replaceOrder(PurchaseOrder order) {
    _orders = [order, ..._orders.where((item) => item.id != order.id)];
  }

  void _showError(Object error) =>
      _showMessage(error.toString().replaceFirst('Exception: ', ''));

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final compact = viewport.width < 600;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: SizedBox(
        width: compact ? viewport.width * 0.9 : 920,
        height: viewport.height * 0.9,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(compact ? 16 : 22, 12, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Suppliers and purchasing',
                          style: TextStyle(
                            color: _purchaseInk,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Purchase orders and stock receiving',
                          style: TextStyle(color: _purchaseMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh purchasing',
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabs,
              labelColor: _purchaseLeaf,
              tabs: const [
                Tab(text: 'Suppliers'),
                Tab(text: 'Purchase orders'),
              ],
            ),
            if (_offlineSnapshot)
              const MaterialBanner(
                content: Text(
                  'Showing saved data. Reconnect to create, place, or receive orders.',
                ),
                leading: Icon(Icons.cloud_off_outlined),
                actions: [SizedBox.shrink()],
              ),
            if (_error != null)
              MaterialBanner(
                content: Text(_error!),
                actions: [
                  TextButton(onPressed: _refresh, child: const Text('Retry')),
                ],
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabs,
                      children: [
                        _supplierList(compact),
                        _purchaseOrderList(compact),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _supplierList(bool compact) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: EdgeInsets.fromLTRB(compact ? 14 : 20, 12, 14, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${_suppliers.where((item) => item.isActive).length} active suppliers',
                style: const TextStyle(color: _purchaseMuted),
              ),
            ),
            FilledButton.icon(
              onPressed: _offlineSnapshot ? null : _editSupplier,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add supplier'),
            ),
          ],
        ),
      ),
      Expanded(
        child: _suppliers.isEmpty
            ? const _PurchasingEmptyState(
                icon: Icons.local_shipping_outlined,
                title: 'No suppliers yet',
                detail: 'Add your first supplier to start purchasing stock.',
              )
            : ListView.separated(
                padding: EdgeInsets.fromLTRB(
                  compact ? 12 : 18,
                  4,
                  compact ? 12 : 18,
                  18,
                ),
                itemCount: _suppliers.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final supplier = _suppliers[index];
                  final contact =
                      [supplier.contactName, supplier.email, supplier.phone]
                          .whereType<String>()
                          .where((value) => value.isNotEmpty)
                          .join(' · ');
                  return Card(
                    margin: EdgeInsets.zero,
                    color: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: _purchaseLine),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: supplier.isActive
                            ? const Color(0xFFE4EFEA)
                            : const Color(0xFFF1F3F1),
                        child: Icon(
                          Icons.local_shipping_outlined,
                          color: supplier.isActive
                              ? _purchaseLeaf
                              : _purchaseMuted,
                        ),
                      ),
                      title: Text(
                        supplier.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        contact.isEmpty
                            ? (supplier.isActive
                                  ? 'Active supplier'
                                  : 'Archived supplier')
                            : '$contact${supplier.isActive ? '' : ' · Archived'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Supplier actions',
                        enabled: !_offlineSnapshot,
                        onSelected: (action) {
                          if (action == 'edit') _editSupplier(supplier);
                          if (action == 'active') {
                            _setSupplierActive(supplier, !supplier.isActive);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit supplier'),
                          ),
                          PopupMenuItem(
                            value: 'active',
                            child: Text(
                              supplier.isActive
                                  ? 'Archive supplier'
                                  : 'Restore supplier',
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    ],
  );

  Widget _purchaseOrderList(bool compact) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: EdgeInsets.fromLTRB(compact ? 14 : 20, 12, 14, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${_orders.length} purchase orders',
                style: const TextStyle(color: _purchaseMuted),
              ),
            ),
            FilledButton.icon(
              onPressed: _offlineSnapshot ? null : _createOrder,
              icon: const Icon(Icons.add_shopping_cart_rounded),
              label: const Text('New order'),
            ),
          ],
        ),
      ),
      Expanded(
        child: _orders.isEmpty
            ? const _PurchasingEmptyState(
                icon: Icons.assignment_outlined,
                title: 'No purchase orders',
                detail:
                    'Create a draft, place it with a supplier, then receive items.',
              )
            : ListView.separated(
                padding: EdgeInsets.fromLTRB(
                  compact ? 10 : 16,
                  4,
                  compact ? 10 : 16,
                  18,
                ),
                itemCount: _orders.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) =>
                    _purchaseOrderCard(_orders[index]),
              ),
      ),
    ],
  );

  Widget _purchaseOrderCard(PurchaseOrder order) {
    final isBusy = _busyOrders.contains(order.id);
    return Card(
      margin: EdgeInsets.zero,
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _purchaseLine),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        title: Row(
          children: [
            Expanded(
              child: Text(
                order.supplierName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            _PurchaseOrderStatusChip(status: order.status),
          ],
        ),
        subtitle: Text(
          '${order.id} · ${order.lines.length} items · ${_purchaseMoney(order.totalCents)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          if (order.expectedAt != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Expected ${_dateKey(order.expectedAt!)}',
                style: const TextStyle(color: _purchaseMuted, fontSize: 12),
              ),
            ),
          if (order.note != null && order.note!.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  order.note!,
                  style: const TextStyle(color: _purchaseMuted),
                ),
              ),
            ),
          const SizedBox(height: 6),
          ...order.lines.map(
            (line) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(line.productName),
              subtitle: Text(
                '${line.receivedQuantity} received of ${line.orderedQuantity} · ${_purchaseMoney(line.unitCostCents)} each',
              ),
              trailing: Text(_purchaseMoney(line.lineTotalCents)),
            ),
          ),
          if (!_offlineSnapshot)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (order.status == PurchaseOrderStatus.draft)
                  FilledButton.tonalIcon(
                    onPressed: isBusy ? null : () => _place(order),
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('Place order'),
                  ),
                if (order.canReceive)
                  FilledButton.icon(
                    onPressed: isBusy ? null : () => _receive(order),
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: const Text('Receive items'),
                  ),
                if (order.status == PurchaseOrderStatus.draft ||
                    order.status == PurchaseOrderStatus.ordered)
                  TextButton.icon(
                    onPressed: isBusy ? null : () => _cancel(order),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Cancel order'),
                  ),
                if (isBusy)
                  const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SupplierEditorDialog extends StatefulWidget {
  const _SupplierEditorDialog({required this.repository, this.initial});

  final PosRepository repository;
  final Supplier? initial;

  @override
  State<_SupplierEditorDialog> createState() => _SupplierEditorDialogState();
}

class _SupplierEditorDialogState extends State<_SupplierEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _contact = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  final _id = const Uuid().v4();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final supplier = widget.initial;
    if (supplier != null) {
      _name.text = supplier.name;
      _contact.text = supplier.contactName ?? '';
      _email.text = supplier.email ?? '';
      _phone.text = supplier.phone ?? '';
      _address.text = supplier.address ?? '';
      _notes.text = supplier.notes ?? '';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    _email.dispose();
    _phone.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  String? _optional(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final initial = widget.initial;
      final saved = initial == null
          ? await widget.repository.createSupplier(
              id: _id,
              name: _name.text.trim(),
              contactName: _optional(_contact),
              email: _optional(_email),
              phone: _optional(_phone),
              address: _optional(_address),
              notes: _optional(_notes),
            )
          : await widget.repository.updateSupplier(
              supplier: Supplier(
                id: initial.id,
                name: _name.text.trim(),
                contactName: _optional(_contact),
                email: _optional(_email),
                phone: _optional(_phone),
                address: _optional(_address),
                notes: _optional(_notes),
                isActive: initial.isActive,
                version: initial.version,
                createdAt: initial.createdAt,
                updatedAt: initial.updatedAt,
              ),
              expectedVersion: initial.version,
            );
      if (mounted) Navigator.pop(context, saved);
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? 'Add supplier' : 'Edit supplier'),
    content: SizedBox(
      width: (MediaQuery.sizeOf(context).width - 64)
          .clamp(240.0, 440.0)
          .toDouble(),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Supplier name'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a supplier name.'
                    : null,
              ),
              TextFormField(
                controller: _contact,
                decoration: const InputDecoration(
                  labelText: 'Contact name (optional)',
                ),
              ),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email (optional)',
                ),
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (email.isNotEmpty && !email.contains('@')) {
                    return 'Enter a valid email address.';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone (optional)',
                ),
              ),
              TextFormField(
                controller: _address,
                decoration: const InputDecoration(
                  labelText: 'Address (optional)',
                ),
              ),
              TextFormField(
                controller: _notes,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Save supplier'),
      ),
    ],
  );
}

class _PurchaseDraftLine {
  _PurchaseDraftLine({required this.id, required this.productId});

  final String id;
  String productId;
  final quantity = TextEditingController(text: '1');
  final cost = TextEditingController(text: '0.00');

  void dispose() {
    quantity.dispose();
    cost.dispose();
  }
}

class _PurchaseOrderEditorDialog extends StatefulWidget {
  const _PurchaseOrderEditorDialog({
    required this.repository,
    required this.suppliers,
    required this.products,
  });

  final PosRepository repository;
  final List<Supplier> suppliers;
  final List<Product> products;

  @override
  State<_PurchaseOrderEditorDialog> createState() =>
      _PurchaseOrderEditorDialogState();
}

class _PurchaseOrderEditorDialogState
    extends State<_PurchaseOrderEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _expectedAt = TextEditingController();
  final _note = TextEditingController();
  final _orderId = const Uuid().v4();
  final List<_PurchaseDraftLine> _lines = [];
  String? _supplierId;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _supplierId = widget.suppliers.first.id;
    _addLine();
  }

  @override
  void dispose() {
    _expectedAt.dispose();
    _note.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  void _addLine() => setState(() {
    _lines.add(
      _PurchaseDraftLine(
        id: const Uuid().v4(),
        productId: widget.products.first.id,
      ),
    );
  });

  void _removeLine(_PurchaseDraftLine line) {
    setState(() {
      _lines.remove(line);
      line.dispose();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final lines = <Map<String, Object?>>[];
    for (final line in _lines) {
      final quantity = int.tryParse(line.quantity.text.trim());
      final unitCostCents = _parsePurchaseMoney(line.cost.text);
      if (quantity == null || quantity < 1 || unitCostCents == null) {
        setState(
          () => _error = 'Enter a quantity and valid unit cost for every item.',
        );
        return;
      }
      lines.add({
        'id': line.id,
        'productId': line.productId,
        'quantity': quantity,
        'unitCostCents': unitCostCents,
      });
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final order = await widget.repository.createPurchaseOrder(
        id: _orderId,
        supplierId: _supplierId!,
        lines: lines,
        expectedAt: _expectedAt.text.trim().isEmpty
            ? null
            : _expectedAt.text.trim(),
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      if (mounted) Navigator.pop(context, order);
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New purchase order'),
    content: SizedBox(
      width: (MediaQuery.sizeOf(context).width - 64)
          .clamp(240.0, 580.0)
          .toDouble(),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _supplierId,
                decoration: const InputDecoration(labelText: 'Supplier'),
                items: widget.suppliers
                    .map(
                      (item) => DropdownMenuItem(
                        value: item.id,
                        child: Text(item.name),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) => setState(() => _supplierId = value),
              ),
              const SizedBox(height: 10),
              for (final line in _lines) _orderLineEditor(line),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _saving ? null : _addLine,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add item'),
                ),
              ),
              TextFormField(
                controller: _expectedAt,
                decoration: const InputDecoration(
                  labelText: 'Expected delivery (optional)',
                  hintText: 'YYYY-MM-DD',
                ),
                validator: (value) {
                  final input = value?.trim() ?? '';
                  if (input.isEmpty) return null;
                  final date = DateTime.tryParse('${input}T00:00:00Z');
                  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(input) ||
                      date == null ||
                      date.toIso8601String().substring(0, 10) != input) {
                    return 'Use a valid YYYY-MM-DD date.';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _note,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Order note (optional)',
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Save draft'),
      ),
    ],
  );

  Widget _orderLineEditor(_PurchaseDraftLine line) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: _purchaseLine),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(line.id),
                    initialValue: line.productId,
                    decoration: const InputDecoration(labelText: 'Product'),
                    items: widget.products
                        .map(
                          (product) => DropdownMenuItem(
                            value: product.id,
                            child: Text(
                              product.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value != null) setState(() => line.productId = value);
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Remove item',
                  onPressed: _lines.length == 1 || _saving
                      ? null
                      : () => _removeLine(line),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: line.quantity,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Quantity'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: line.cost,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Unit cost (PHP)',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _ReceivePurchaseOrderDialog extends StatefulWidget {
  const _ReceivePurchaseOrderDialog({
    required this.repository,
    required this.order,
  });

  final PosRepository repository;
  final PurchaseOrder order;

  @override
  State<_ReceivePurchaseOrderDialog> createState() =>
      _ReceivePurchaseOrderDialogState();
}

class _ReceivePurchaseOrderDialogState
    extends State<_ReceivePurchaseOrderDialog> {
  final _location = TextEditingController(text: 'Main');
  final _note = TextEditingController();
  final _receiptId = const Uuid().v4();
  final Map<String, TextEditingController> _quantities = {};
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final line in widget.order.lines.where(
      (line) => line.remainingQuantity > 0,
    )) {
      _quantities[line.id] = TextEditingController(text: '0');
    }
  }

  @override
  void dispose() {
    _location.dispose();
    _note.dispose();
    for (final controller in _quantities.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final lines = <Map<String, Object?>>[];
    for (final line in widget.order.lines) {
      if (line.remainingQuantity == 0) continue;
      final quantity = int.tryParse(_quantities[line.id]!.text.trim());
      if (quantity == null ||
          quantity < 0 ||
          quantity > line.remainingQuantity) {
        setState(
          () => _error =
              'Enter no more than the remaining quantity for each item.',
        );
        return;
      }
      if (quantity > 0) lines.add({'lineId': line.id, 'quantity': quantity});
    }
    if (lines.isEmpty) {
      setState(() => _error = 'Enter at least one received quantity.');
      return;
    }
    if (_location.text.trim().isEmpty) {
      setState(() => _error = 'Enter the stock location.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final order = await widget.repository.receivePurchaseOrder(
        purchaseOrderId: widget.order.id,
        receiptId: _receiptId,
        location: _location.text.trim(),
        lines: lines,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      if (mounted) Navigator.pop(context, order);
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Receive purchase order'),
    content: SizedBox(
      width: (MediaQuery.sizeOf(context).width - 64)
          .clamp(240.0, 520.0)
          .toDouble(),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final line in widget.order.lines.where(
              (line) => line.remainingQuantity > 0,
            ))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            line.productName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${line.remainingQuantity} remaining',
                            style: const TextStyle(
                              color: _purchaseMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: _quantities[line.id],
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Received',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            TextField(
              controller: _location,
              decoration: const InputDecoration(labelText: 'Stock location'),
            ),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'Receipt note (optional)',
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Receiving…' : 'Receive items'),
      ),
    ],
  );
}

class _PurchasingEmptyState extends StatelessWidget {
  const _PurchasingEmptyState({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _purchaseMuted, size: 38),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _purchaseMuted),
          ),
        ],
      ),
    ),
  );
}

class _PurchaseOrderStatusChip extends StatelessWidget {
  const _PurchaseOrderStatusChip({required this.status});

  final PurchaseOrderStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color, background) = switch (status) {
      PurchaseOrderStatus.draft => (
        'Draft',
        _purchaseMuted,
        const Color(0xFFF1F3F1),
      ),
      PurchaseOrderStatus.ordered => (
        'Ordered',
        const Color(0xFF2E6A93),
        const Color(0xFFEAF3F8),
      ),
      PurchaseOrderStatus.partiallyReceived => (
        'Partial',
        const Color(0xFF946513),
        const Color(0xFFFFF5DA),
      ),
      PurchaseOrderStatus.received => (
        'Received',
        _purchaseLeaf,
        const Color(0xFFE4EFEA),
      ),
      PurchaseOrderStatus.cancelled => (
        'Cancelled',
        const Color(0xFF9D4036),
        const Color(0xFFFCE7E5),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

int? _parsePurchaseMoney(String value) {
  final normalized = value.trim();
  if (!RegExp(r'^\d{1,12}(?:\.\d{1,2})?$').hasMatch(normalized)) return null;
  final parts = normalized.split('.');
  final whole = int.tryParse(parts.first);
  if (whole == null) return null;
  final fraction = parts.length == 1
      ? 0
      : int.tryParse(parts.last.padRight(2, '0'));
  if (fraction == null) return null;
  return whole * 100 + fraction;
}

String _purchaseMoney(int cents) =>
    'PHP ${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';

String _dateKey(DateTime date) =>
    date.toUtc().toIso8601String().substring(0, 10);
