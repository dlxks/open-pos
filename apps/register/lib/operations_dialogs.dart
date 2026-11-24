// ignore_for_file: deprecated_member_use
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:open_pos/data/local_database.dart';
import 'package:open_pos/data/pos_repository.dart';
import 'package:open_pos/data/sale_sync_client.dart';
import 'package:pos_domain/pos_domain.dart';
import 'package:uuid/uuid.dart';

const _opsInk = Color(0xFF173432);
const _opsLeaf = Color(0xFF0D7468);
const _opsMuted = Color(0xFF73827D);
const _opsLine = Color(0xFFE3E8E3);

Future<void> showInventoryManagement({
  required BuildContext context,
  required SaleSyncClient api,
  required PosRepository repository,
}) => showDialog<void>(
  context: context,
  builder: (context) =>
      InventoryManagementDialog(api: api, repository: repository),
);

Future<bool?> showCashDrawer({
  required BuildContext context,
  required SaleSyncClient api,
  required CashShift? shift,
}) => showDialog<bool>(
  context: context,
  builder: (context) => CashDrawerDialog(api: api, initialShift: shift),
);

class InventoryManagementDialog extends StatefulWidget {
  const InventoryManagementDialog({
    super.key,
    required this.api,
    required this.repository,
  });

  final SaleSyncClient api;
  final PosRepository repository;

  @override
  State<InventoryManagementDialog> createState() =>
      _InventoryManagementDialogState();
}

class _InventoryManagementDialogState extends State<InventoryManagementDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<InventoryItem> _items = const [];
  List<StockMovement> _movements = const [];
  List<LocalStockOperation> _queuedOperations = const [];
  bool _loading = true;
  bool _lowStockOnly = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
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
      await widget.repository.syncPendingStockMovements(force: true);
      final inventory = await widget.repository.fetchInventory();
      List<StockMovement> movements;
      try {
        movements = await widget.api.fetchStockMovements();
      } on Exception {
        movements = const [];
      }
      final queued = await widget.repository.stockOperations();
      if (mounted) {
        setState(() {
          _items = inventory;
          _movements = movements;
          _queuedOperations = queued;
          _loading = false;
        });
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _error = error is HubApiException
              ? error.message
              : 'Could not load inventory. Check the hub connection.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _record(InventoryItem item, StockMovementType type) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => StockMovementDialog(
        repository: widget.repository,
        item: item,
        type: type,
      ),
    );
    if (changed == true) await _refresh();
  }

  Future<void> _threshold(InventoryItem item) async {
    final value = await showDialog<int>(
      context: context,
      builder: (context) => _ThresholdDialog(value: item.lowStockThreshold),
    );
    if (value == null) return;
    try {
      await widget.api.setLowStockThreshold(
        productId: item.productId,
        threshold: value,
      );
      await _refresh();
    } on Exception catch (error) {
      if (mounted) {
        _showError(
          error is HubApiException
              ? error.message
              : 'Could not save threshold.',
        );
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: SizedBox(
      width: 800,
      height: 650,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 12, 10),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Inventory',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          color: _opsInk,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Stock levels, low-stock alerts, and movement history',
                        style: TextStyle(color: _opsMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh inventory',
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
            labelColor: _opsLeaf,
            tabs: const [
              Tab(text: 'Stock levels'),
              Tab(text: 'Movement history'),
              Tab(text: 'Offline queue'),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(18),
              child: MaterialBanner(
                content: Text(_error!),
                actions: [
                  TextButton(onPressed: _refresh, child: const Text('Retry')),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabs,
                    children: [_stockList(), _movementList(), _queuedList()],
                  ),
          ),
        ],
      ),
    ),
  );

  Widget _stockList() {
    final visible = _items
        .where((item) => !_lowStockOnly || item.isLowStock)
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 5),
          child: Row(
            children: [
              Text(
                '${_items.where((item) => item.isLowStock).length} items low',
                style: const TextStyle(color: _opsMuted),
              ),
              const Spacer(),
              const Text('Low stock only'),
              Switch(
                value: _lowStockOnly,
                onChanged: (value) => setState(() => _lowStockOnly = value),
              ),
            ],
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? const Center(child: Text('No products match this view.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = visible[index];
                    return Card(
                      margin: EdgeInsets.zero,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(color: _opsLine),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: _opsInk,
                                        ),
                                      ),
                                      if (item.sku != null)
                                        Text(
                                          item.sku!,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: _opsMuted,
                                          ),
                                        ),
                                      if (item.locations.isNotEmpty)
                                        Text(
                                          item.locations
                                              .map(
                                                (location) =>
                                                    '${location.location}: ${location.quantity}',
                                              )
                                              .join(', '),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: _opsMuted,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${item.onHand} on hand',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: 'Set low-stock threshold',
                                  onPressed: () => _threshold(item),
                                  icon: const Icon(Icons.tune_rounded),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.isLowStock
                                        ? 'Low stock · alert at ${item.lowStockThreshold}'
                                        : 'Alert at ${item.lowStockThreshold}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: item.isLowStock
                                          ? const Color(0xFFB94035)
                                          : _opsMuted,
                                    ),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () =>
                                      _record(item, StockMovementType.receive),
                                  icon: const Icon(
                                    Icons.add_box_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Receive'),
                                ),
                                PopupMenuButton<StockMovementType>(
                                  tooltip: 'More stock actions',
                                  onSelected: (type) => _record(item, type),
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: StockMovementType.adjustment,
                                      child: Text('Adjust stock'),
                                    ),
                                    PopupMenuItem(
                                      value: StockMovementType.transfer,
                                      child: Text('Transfer location'),
                                    ),
                                  ],
                                ),
                              ],
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
  }

  Widget _movementList() => _movements.isEmpty
      ? const Center(child: Text('No stock movements yet.'))
      : ListView.separated(
          padding: const EdgeInsets.all(18),
          itemCount: _movements.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final movement = _movements[index];
            final label = switch (movement.type) {
              StockMovementType.receive => 'Received',
              StockMovementType.adjustment => 'Adjustment',
              StockMovementType.transfer => 'Transfer',
              StockMovementType.sale => 'Sale',
            };
            final location = switch (movement.type) {
              StockMovementType.receive =>
                'To ${movement.destinationLocation ?? 'Main'}',
              StockMovementType.adjustment =>
                'At ${movement.destinationLocation ?? 'Main'}',
              StockMovementType.transfer =>
                '${movement.sourceLocation ?? 'Main'} to ${movement.destinationLocation ?? 'Main'}',
              StockMovementType.sale =>
                'From ${movement.sourceLocation ?? 'Main'}',
            };
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${movement.productName ?? movement.productId} · $location',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '$label · ${movement.createdAt.toLocal()}${movement.note == null ? '' : ' · ${movement.note}'}',
              ),
              trailing: Text(
                movement.quantity > 0
                    ? '+${movement.quantity}'
                    : '${movement.quantity}',
              ),
            );
          },
        );

  Widget _queuedList() => _queuedOperations.isEmpty
      ? const Center(child: Text('No offline stock changes are waiting.'))
      : ListView.separated(
          padding: const EdgeInsets.all(18),
          itemCount: _queuedOperations.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final operation = _queuedOperations[index];
            final payload =
                jsonDecode(operation.payload) as Map<String, Object?>;
            final conflict = operation.status == 'conflict';
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                conflict
                    ? Icons.warning_amber_rounded
                    : Icons.sync_problem_rounded,
                color: conflict ? Colors.deepOrange : _opsMuted,
              ),
              title: Text(
                '${payload['type']} · ${payload['quantity']} · ${payload['productId']}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                conflict
                    ? 'Conflict: ${operation.error ?? 'Hub rejected this change.'}'
                    : 'Waiting to sync',
              ),
              trailing: conflict
                  ? Wrap(
                      children: [
                        IconButton(
                          tooltip: 'Retry after checking stock',
                          onPressed: () async {
                            await widget.repository.retryStockOperation(
                              operation.id,
                            );
                            await _refresh();
                          },
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                        IconButton(
                          tooltip: 'Discard this change',
                          onPressed: () async {
                            await widget.repository.discardStockOperation(
                              operation.id,
                            );
                            await _refresh();
                          },
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      ],
                    )
                  : null,
            );
          },
        );
}

class StockMovementDialog extends StatefulWidget {
  const StockMovementDialog({
    super.key,
    required this.repository,
    required this.item,
    required this.type,
  });

  final PosRepository repository;
  final InventoryItem item;
  final StockMovementType type;

  @override
  State<StockMovementDialog> createState() => _StockMovementDialogState();
}

class _StockMovementDialogState extends State<StockMovementDialog> {
  final _quantity = TextEditingController();
  final _source = TextEditingController(text: 'Main');
  final _destination = TextEditingController(text: 'Main');
  final _note = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _quantity.dispose();
    _source.dispose();
    _destination.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final transfer = widget.type == StockMovementType.transfer;
    final receive = widget.type == StockMovementType.receive;
    final title = receive
        ? 'Receive stock'
        : transfer
        ? 'Transfer stock'
        : 'Adjust stock';
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 390,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.item.name, style: const TextStyle(color: _opsMuted)),
            const SizedBox(height: 14),
            TextField(
              controller: _quantity,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: transfer
                    ? 'Quantity'
                    : receive
                    ? 'Quantity received'
                    : 'Change in stock',
                helperText: widget.type == StockMovementType.adjustment
                    ? 'Use a negative number to remove stock.'
                    : null,
              ),
            ),
            if (transfer) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _source,
                decoration: const InputDecoration(labelText: 'From location'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _destination,
                decoration: const InputDecoration(labelText: 'To location'),
              ),
            ] else if (receive) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _destination,
                decoration: const InputDecoration(labelText: 'Stock location'),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save movement'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final quantity = int.tryParse(_quantity.text.trim());
    if (quantity == null ||
        quantity == 0 ||
        (widget.type != StockMovementType.adjustment && quantity < 0)) {
      setState(
        () => _error =
            'Enter a non-zero whole number${widget.type == StockMovementType.adjustment ? '' : ' above zero'}.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final synced = await widget.repository.recordStockMovement(
        id: const Uuid().v4(),
        productId: widget.item.productId,
        type: widget.type,
        quantity: quantity,
        sourceLocation: widget.type == StockMovementType.transfer
            ? _source.text.trim()
            : null,
        destinationLocation:
            widget.type == StockMovementType.transfer ||
                widget.type == StockMovementType.receive
            ? _destination.text.trim()
            : null,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      if (!synced && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Stock change saved on this device and queued for sync.',
            ),
          ),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is HubApiException
              ? error.message
              : 'Could not save stock movement.';
        });
      }
    }
  }
}

class _ThresholdDialog extends StatefulWidget {
  const _ThresholdDialog({required this.value});
  final int value;

  @override
  State<_ThresholdDialog> createState() => _ThresholdDialogState();
}

class _ThresholdDialogState extends State<_ThresholdDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.value}',
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Low-stock alert'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: 'Alert when stock is at or below',
        errorText: _error,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final value = int.tryParse(_controller.text.trim());
          if (value == null || value < 0) {
            setState(() => _error = 'Enter zero or a positive whole number.');
            return;
          }
          Navigator.pop(context, value);
        },
        child: const Text('Save'),
      ),
    ],
  );
}

class CashDrawerDialog extends StatefulWidget {
  const CashDrawerDialog({
    super.key,
    required this.api,
    required this.initialShift,
  });
  final SaleSyncClient api;
  final CashShift? initialShift;

  @override
  State<CashDrawerDialog> createState() => _CashDrawerDialogState();
}

class _CashDrawerDialogState extends State<CashDrawerDialog> {
  final _openingAmount = TextEditingController(text: '0.00');
  final _movementAmount = TextEditingController(text: '0.00');
  final _countedCash = TextEditingController(text: '0.00');
  final _note = TextEditingController();
  CashShift? _shift;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _shift = widget.initialShift;
    if (_shift?.isOpen == true) _refreshOpenShift();
  }

  Future<void> _refreshOpenShift() async {
    try {
      final shift = await widget.api.currentCashShift();
      if (mounted && shift != null) setState(() => _shift = shift);
    } on Exception {
      // Keep the cached shift visible when the hub is offline.
    }
  }

  @override
  void dispose() {
    _openingAmount.dispose();
    _movementAmount.dispose();
    _countedCash.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shift = _shift;
    return AlertDialog(
      title: const Text('Cash drawer'),
      content: SizedBox(
        width: 410,
        child: shift == null ? _openForm() : _shiftForm(shift),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(shift != null && !shift.isOpen ? 'Done' : 'Close'),
        ),
        if (shift != null && !shift.isOpen)
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Done'),
          ),
      ],
    );
  }

  Widget _openForm() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Open a drawer shift before taking cash sales.'),
      const SizedBox(height: 14),
      TextField(
        controller: _openingAmount,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: 'Opening float',
          prefixText: 'PHP ',
        ),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_error!, style: const TextStyle(color: Colors.red)),
        ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _saving ? null : _open,
        icon: const Icon(Icons.lock_open_rounded),
        label: Text(_saving ? 'Opening…' : 'Open cash drawer'),
      ),
    ],
  );

  Widget _shiftForm(CashShift shift) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        shift.isOpen ? 'Shift is open' : 'Shift closed',
        style: const TextStyle(fontWeight: FontWeight.w700, color: _opsInk),
      ),
      const SizedBox(height: 8),
      _cashRow('Opening float', shift.openingFloatCents),
      _cashRow('Expected cash', shift.expectedCashCents),
      if (!shift.isOpen) ...[
        _cashRow('Counted cash', shift.countedCashCents ?? 0),
        _cashRow(
          'Variance',
          shift.varianceCents ?? 0,
          highlight: shift.varianceCents != 0,
        ),
      ] else ...[
        const SizedBox(height: 12),
        TextField(
          controller: _movementAmount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Amount',
            prefixText: 'PHP ',
          ),
        ),
        const SizedBox(height: 9),
        TextField(
          controller: _note,
          decoration: const InputDecoration(
            labelText: 'Reason or note (optional)',
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _saving ? null : () => _cashMove('paid_in'),
                icon: const Icon(Icons.south_west_rounded),
                label: const Text('Paid in'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _saving ? null : () => _cashMove('paid_out'),
                icon: const Icon(Icons.north_east_rounded),
                label: const Text('Paid out'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Divider(),
        const SizedBox(height: 8),
        TextField(
          controller: _countedCash,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Count cash to close',
            prefixText: 'PHP ',
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _saving ? null : _closeShift,
          icon: const Icon(Icons.lock_outline_rounded),
          label: Text(_saving ? 'Saving…' : 'Close and reconcile shift'),
        ),
      ],
    ],
  );

  Widget _cashRow(String label, int cents, {bool highlight = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Text(label, style: const TextStyle(color: _opsMuted)),
        const Spacer(),
        Text(
          _money(cents),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: highlight ? const Color(0xFFB94035) : _opsInk,
          ),
        ),
      ],
    ),
  );

  Future<void> _open() async {
    final cents = _parseMoney(_openingAmount.text);
    if (cents == null) {
      setState(() => _error = 'Enter a valid opening float.');
      return;
    }
    await _run(() async {
      _shift = await widget.api.openCashShift(
        id: const Uuid().v4(),
        openingFloatCents: cents,
      );
    });
  }

  Future<void> _cashMove(String type) async {
    final shift = _shift;
    final cents = _parseMoney(_movementAmount.text);
    if (shift == null || cents == null || cents <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }
    await _run(() async {
      await widget.api.recordCashMovement(
        shiftId: shift.id,
        id: const Uuid().v4(),
        type: type,
        amountCents: cents,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      _shift = await widget.api.currentCashShift();
      _movementAmount.text = '0.00';
      _note.clear();
    });
  }

  Future<void> _closeShift() async {
    final shift = _shift;
    final cents = _parseMoney(_countedCash.text);
    if (shift == null || cents == null) {
      setState(() => _error = 'Enter a valid counted cash amount.');
      return;
    }
    await _run(() async {
      _shift = await widget.api.closeCashShift(
        shiftId: shift.id,
        countedCashCents: cents,
      );
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) setState(() {});
    } on Exception catch (error) {
      if (mounted) {
        setState(
          () => _error = error is HubApiException
              ? error.message
              : 'The cash drawer request failed.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

int? _parseMoney(String value) {
  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(value.trim());
  if (match == null) return null;
  final whole = int.tryParse(match.group(1)!);
  if (whole == null || whole > 90071992547409) return null;
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  final cents = whole * 100 + (int.tryParse(fraction) ?? 0);
  return cents <= 9007199254740991 ? cents : null;
}

String _money(int cents) => 'PHP ${(cents / 100).toStringAsFixed(2)}';
