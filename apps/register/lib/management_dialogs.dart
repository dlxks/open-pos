// Flutter's current SDK still ships Material widgets from this library.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:open_pos/data/pos_repository.dart';
import 'package:open_pos/data/sale_sync_client.dart';
import 'package:pos_domain/pos_domain.dart';
import 'package:uuid/uuid.dart';

const _leaf = Color(0xFF0D7468);
const _muted = Color(0xFF73827D);
const _line = Color(0xFFE3E8E3);

typedef ProductSave =
    Future<List<Product>> Function(Product? existing, Product updated);

Future<void> showCatalogManagement({
  required BuildContext context,
  required List<Product> products,
  required ProductSave onSave,
  required PosRepository repository,
}) => showDialog<void>(
  context: context,
  builder: (context) => CatalogManagementDialog(
    products: products,
    onSave: onSave,
    repository: repository,
  ),
);

class CatalogManagementDialog extends StatefulWidget {
  const CatalogManagementDialog({
    super.key,
    required this.products,
    required this.onSave,
    required this.repository,
  });

  final List<Product> products;
  final ProductSave onSave;
  final PosRepository repository;

  @override
  State<CatalogManagementDialog> createState() =>
      _CatalogManagementDialogState();
}

class _CatalogManagementDialogState extends State<CatalogManagementDialog> {
  late List<Product> _products;
  List<CatalogCategory> _categories = const [];
  bool _saving = false;
  String? _error;
  List<CatalogOperationSnapshot> _operations = const [];

  @override
  void initState() {
    super.initState();
    _products = widget.products.toList();
    _loadOperations();
    _loadCategories();
  }

  Future<void> _loadOperations() async {
    final operations = await widget.repository.catalogOperations();
    if (mounted) setState(() => _operations = operations);
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await widget.repository.catalogCategories();
      if (mounted) setState(() => _categories = categories);
    } on Exception {
      if (mounted) {
        setState(() => _error = 'Could not load categories from the hub.');
      }
    }
  }

  Future<void> _manageCategories() async {
    try {
      final categories = await widget.repository.catalogCategories();
      if (mounted) setState(() => _categories = categories);
    } on Exception {
      // The local category snapshot remains usable while the hub is offline.
    }
    if (!mounted) return;
    final updated = await showDialog<List<CatalogCategory>>(
      context: context,
      builder: (context) => CatalogCategoryManagementDialog(
        repository: widget.repository,
        categories: _categories,
      ),
    );
    if (updated != null && mounted) {
      setState(() => _categories = updated);
    }
  }

  Future<void> _edit([Product? product]) async {
    try {
      _categories = await widget.repository.catalogCategories();
    } on Exception {
      // Use the last cached category list when the register is offline.
    }
    if (!mounted) return;
    final changed = await showDialog<Product>(
      context: context,
      builder: (context) =>
          ProductEditorDialog(product: product, categories: _categories),
    );
    if (changed == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final refreshed = await widget.onSave(product, changed);
      if (mounted) setState(() => _products = refreshed);
      await _loadOperations();
      await _loadCategories();
    } on HubApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception {
      if (mounted) {
        setState(
          () =>
              _error = 'Could not save this product. Check the hub connection.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _archive(Product product) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final refreshed = await widget.onSave(
        product,
        Product(
          id: product.id,
          name: product.name,
          category: product.category,
          unitPriceCents: product.unitPriceCents,
          sku: product.sku,
          barcode: product.barcode,
          isActive: false,
          version: product.version,
          modifierGroups: product.modifierGroups,
        ),
      );
      if (mounted) setState(() => _products = refreshed);
      await _loadOperations();
    } on Exception {
      if (mounted) {
        setState(
          () => _error =
              'Could not archive this product. Check the hub connection.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reviewOperations() async {
    await showDialog<void>(
      context: context,
      builder: (context) => _CatalogOperationsDialog(
        repository: widget.repository,
        operations: _operations,
        onChanged: (products, operations) {
          if (mounted) {
            setState(() {
              _products = products;
              _operations = operations;
            });
          }
        },
      ),
    );
    await _loadOperations();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Product catalog',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            'Manage products and category names.',
                            style: TextStyle(color: _muted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close catalog',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _manageCategories,
                      icon: const Icon(Icons.label_outline_rounded),
                      label: Text('Categories (${_categories.length})'),
                    ),
                    FilledButton.icon(
                      onPressed: _saving ? null : () => _edit(),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add product'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _line),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFB94035)),
                ),
              ),
            ),
          if (_saving) const LinearProgressIndicator(minHeight: 2),
          if (_operations.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F7F5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.sync_problem_rounded,
                    size: 18,
                    color: _leaf,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_operations.length} catalog change${_operations.length == 1 ? '' : 's'} need attention',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: _reviewOperations,
                    child: const Text('Review'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _products.isEmpty
                ? const Center(
                    child: Text('No active products yet. Add your first item.'),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(18),
                    itemCount: _products.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final product = _products[index];
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: _line),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          title: Text(
                            product.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${product.category} · ${product.sku ?? 'No SKU'}${product.barcode == null ? '' : ' · ${product.barcode}'}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _money(product.unitPriceCents),
                                style: const TextStyle(
                                  color: _leaf,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Edit ${product.name}',
                                onPressed: _saving
                                    ? null
                                    : () => _edit(product),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: 'Archive ${product.name}',
                                onPressed: _saving
                                    ? null
                                    : () => _archive(product),
                                icon: const Icon(Icons.archive_outlined),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              children: [
                const Icon(Icons.sync_rounded, size: 17, color: _muted),
                const SizedBox(width: 7),
                const Expanded(
                  child: Text(
                    'Changes sync to this deployment and its registers.',
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _CatalogOperationsDialog extends StatefulWidget {
  const _CatalogOperationsDialog({
    required this.repository,
    required this.operations,
    required this.onChanged,
  });

  final PosRepository repository;
  final List<CatalogOperationSnapshot> operations;
  final void Function(List<Product>, List<CatalogOperationSnapshot>) onChanged;

  @override
  State<_CatalogOperationsDialog> createState() =>
      _CatalogOperationsDialogState();
}

class _CatalogOperationsDialogState extends State<_CatalogOperationsDialog> {
  late List<CatalogOperationSnapshot> _operations;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _operations = widget.operations;
  }

  Future<void> _run(
    CatalogOperationSnapshot operation,
    Future<List<Product>> Function(String id) action,
  ) async {
    setState(() => _busyId = operation.id);
    try {
      final products = await action(operation.id);
      final operations = await widget.repository.catalogOperations();
      if (!mounted) return;
      setState(() {
        _operations = operations;
        _busyId = null;
      });
      widget.onChanged(products, operations);
    } on Exception {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Catalog sync'),
    content: SizedBox(
      width: 540,
      child: _operations.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('All catalog changes are synced.'),
            )
          : ListView.separated(
              shrinkWrap: true,
              itemCount: _operations.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, index) {
                final operation = _operations[index];
                final conflict = operation.status == 'conflict';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        operation.product.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        conflict
                            ? 'Changed on another register. Hub version: ${operation.currentProduct?.version ?? 'unavailable'} · your version: ${operation.product.version}'
                            : operation.error ??
                                  'Waiting for a hub connection.',
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                      if (_busyId == operation.id)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: LinearProgressIndicator(minHeight: 2),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          children: conflict
                              ? [
                                  FilledButton.tonal(
                                    onPressed: operation.currentProduct == null
                                        ? null
                                        : () => _run(
                                            operation,
                                            widget
                                                .repository
                                                .resolveCatalogConflictKeepLocal,
                                          ),
                                    child: const Text('Keep my version'),
                                  ),
                                  TextButton(
                                    onPressed: () => _run(
                                      operation,
                                      widget
                                          .repository
                                          .resolveCatalogConflictUseHub,
                                    ),
                                    child: const Text('Use hub version'),
                                  ),
                                ]
                              : [
                                  TextButton.icon(
                                    onPressed: () => _run(
                                      operation,
                                      widget.repository.retryCatalogOperation,
                                    ),
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: const Text('Retry now'),
                                  ),
                                ],
                        ),
                    ],
                  ),
                );
              },
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );
}

class CatalogCategoryManagementDialog extends StatefulWidget {
  const CatalogCategoryManagementDialog({
    super.key,
    required this.repository,
    required this.categories,
  });

  final PosRepository repository;
  final List<CatalogCategory> categories;

  @override
  State<CatalogCategoryManagementDialog> createState() =>
      _CatalogCategoryManagementDialogState();
}

class _CatalogCategoryManagementDialogState
    extends State<CatalogCategoryManagementDialog> {
  late List<CatalogCategory> _categories;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _categories = widget.categories.toList();
  }

  Future<void> _addCategory() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _CategoryNameDialog(),
    );
    if (name == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final categories = await widget.repository.createCatalogCategory(name);
      if (mounted) setState(() => _categories = categories);
    } on HubApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception {
      if (mounted) {
        setState(
          () => _error =
              'Could not create this category. Check the hub connection.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setActive(CatalogCategory category, bool isActive) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final categories = await widget.repository.setCatalogCategoryActive(
        category,
        isActive: isActive,
      );
      if (mounted) setState(() => _categories = categories);
    } on HubApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception {
      if (mounted) {
        setState(
          () => _error =
              'Could not update this category. Check the hub connection.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Categories'),
    content: SizedBox(
      width: 440,
      height: 420,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Category names are shared with all registers. Move active products before archiving a category.',
            style: TextStyle(color: _muted),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Color(0xFFB94035))),
          ],
          if (_saving) const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 8),
          Expanded(
            child: _categories.isEmpty
                ? const Center(
                    child: Text(
                      'No categories yet. Add one to group products.',
                    ),
                  )
                : ListView.separated(
                    itemCount: _categories.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final category = _categories[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                        title: Text(category.name),
                        subtitle: Text(
                          category.isActive ? 'Active' : 'Archived',
                        ),
                        trailing: IconButton(
                          tooltip: category.isActive
                              ? 'Archive ${category.name}'
                              : 'Restore ${category.name}',
                          onPressed: _saving
                              ? null
                              : () => _setActive(category, !category.isActive),
                          icon: Icon(
                            category.isActive
                                ? Icons.archive_outlined
                                : Icons.unarchive_outlined,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          OutlinedButton.icon(
            onPressed: _saving ? null : _addCategory,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add category'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context, _categories),
        child: const Text('Done'),
      ),
    ],
  );
}

class _CategoryNameDialog extends StatefulWidget {
  const _CategoryNameDialog();

  @override
  State<_CategoryNameDialog> createState() => _CategoryNameDialogState();
}

class _CategoryNameDialogState extends State<_CategoryNameDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add category'),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _name,
        autofocus: true,
        maxLength: 60,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Category name'),
        validator: (value) => _required(value, 'Enter a category name.'),
        onFieldSubmitted: (_) => _save(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Add category')),
    ],
  );

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(context, _name.text.trim());
  }
}

class ProductEditorDialog extends StatefulWidget {
  const ProductEditorDialog({
    super.key,
    this.product,
    this.categories = const [],
  });

  final Product? product;
  final List<CatalogCategory> categories;

  @override
  State<ProductEditorDialog> createState() => _ProductEditorDialogState();
}

class _ProductEditorDialogState extends State<ProductEditorDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _category;
  late final TextEditingController _price;
  late final TextEditingController _sku;
  late final TextEditingController _barcode;
  late List<ModifierGroup> _modifierGroups;
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _name = TextEditingController(text: product?.name ?? '');
    _category = TextEditingController(text: product?.category ?? '');
    final activeCategories = widget.categories
        .where((category) => category.isActive)
        .toList(growable: false);
    final selectedCategories = activeCategories
        .where((category) => category.name == product?.category)
        .toList(growable: false);
    _selectedCategory = selectedCategories.isEmpty
        ? null
        : selectedCategories.single.name;
    _price = TextEditingController(
      text: product == null ? '' : _formatCents(product.unitPriceCents),
    );
    _sku = TextEditingController(text: product?.sku ?? '');
    _barcode = TextEditingController(text: product?.barcode ?? '');
    _modifierGroups = product?.modifierGroups.toList() ?? [];
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _price.dispose();
    _sku.dispose();
    _barcode.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      Product(
        id: widget.product?.id ?? 'new',
        name: _name.text.trim(),
        category:
            widget.categories.where((category) => category.isActive).isEmpty
            ? _category.text.trim()
            : _selectedCategory ?? '',
        unitPriceCents: _parseCents(_price.text)!,
        sku: _blankToNull(_sku.text),
        barcode: _blankToNull(_barcode.text),
        version: widget.product?.version ?? 1,
        modifierGroups: List.unmodifiable(_modifierGroups),
      ),
    );
  }

  Future<void> _editModifiers() async {
    final groups = await showDialog<List<ModifierGroup>>(
      context: context,
      builder: (context) => _ModifierGroupsDialog(groups: _modifierGroups),
    );
    if (groups != null && mounted) {
      setState(() => _modifierGroups = groups);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.product == null ? 'Add product' : 'Edit product'),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Product name'),
                validator: (value) => _required(value, 'Enter a product name.'),
              ),
              const SizedBox(height: 12),
              if (widget.categories.any((category) => category.isActive))
                DropdownButtonFormField<String>(
                  initialValue: _selectedCategory,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: widget.categories
                      .where((category) => category.isActive)
                      .map(
                        (category) => DropdownMenuItem(
                          value: category.name,
                          child: Text(category.name),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) =>
                      setState(() => _selectedCategory = value),
                  validator: (value) =>
                      value == null ? 'Choose a category.' : null,
                )
              else
                TextFormField(
                  controller: _category,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    helperText:
                        'A category record is created when this product syncs.',
                  ),
                  validator: (value) => _required(value, 'Enter a category.'),
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Price',
                  prefixText: 'PHP ',
                ),
                validator: (value) => _parseCents(value ?? '') == null
                    ? 'Enter a valid price.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _sku,
                decoration: const InputDecoration(labelText: 'SKU (optional)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _barcode,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Barcode (optional)',
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _editModifiers,
                  icon: const Icon(Icons.tune_rounded),
                  label: Text('Modifiers (${_modifierGroups.length} groups)'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save product')),
    ],
  );
}

class _ModifierGroupsDialog extends StatefulWidget {
  const _ModifierGroupsDialog({required this.groups});

  final List<ModifierGroup> groups;

  @override
  State<_ModifierGroupsDialog> createState() => _ModifierGroupsDialogState();
}

class _ModifierGroupsDialogState extends State<_ModifierGroupsDialog> {
  late List<ModifierGroup> _groups;

  @override
  void initState() {
    super.initState();
    _groups = widget.groups.toList();
  }

  Future<void> _edit([ModifierGroup? group]) async {
    final edited = await showDialog<ModifierGroup>(
      context: context,
      builder: (context) => _ModifierGroupEditor(group: group),
    );
    if (edited == null) return;
    setState(() {
      final index = _groups.indexWhere((row) => row.id == edited.id);
      if (index < 0) {
        _groups.add(edited);
      } else {
        _groups[index] = edited;
      }
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Product modifiers'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Options can add to the base price.'),
          ),
          const SizedBox(height: 12),
          if (_groups.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text('No modifier groups yet.'),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _groups.length,
                itemBuilder: (context, index) {
                  final group = _groups[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(group.name),
                    subtitle: Text(
                      '${group.minimumSelections} to ${group.maximumSelections} choices · ${group.options.length} options',
                    ),
                    onTap: () => _edit(group),
                    trailing: IconButton(
                      tooltip: 'Remove ${group.name}',
                      onPressed: () => setState(() => _groups.removeAt(index)),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  );
                },
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _groups.length >= 20 ? null : () => _edit(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add modifier group'),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(
          context,
          rootNavigator: true,
        ).pop<List<ModifierGroup>>(List.unmodifiable(_groups)),
        child: const Text('Done'),
      ),
    ],
  );
}

class _ModifierGroupEditor extends StatefulWidget {
  const _ModifierGroupEditor({this.group});

  final ModifierGroup? group;

  @override
  State<_ModifierGroupEditor> createState() => _ModifierGroupEditorState();
}

class _ModifierGroupEditorState extends State<_ModifierGroupEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _minimum;
  late final TextEditingController _maximum;
  late final TextEditingController _options;

  @override
  void initState() {
    super.initState();
    final group = widget.group;
    _name = TextEditingController(text: group?.name ?? '');
    _minimum = TextEditingController(text: '${group?.minimumSelections ?? 0}');
    _maximum = TextEditingController(text: '${group?.maximumSelections ?? 1}');
    _options = TextEditingController(
      text:
          group?.options
              .map(
                (option) =>
                    '${option.name} | ${_formatCents(option.priceDeltaCents)}',
              )
              .join('\n') ??
          '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _minimum.dispose();
    _maximum.dispose();
    _options.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final lines = _options.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final previous = widget.group?.options ?? const <ModifierOption>[];
    final options = <ModifierOption>[];
    for (var index = 0; index < lines.length; index++) {
      final parts = lines[index].split('|');
      final optionName = parts.first.trim();
      final delta = parts.length == 1 ? 0 : _parseCents(parts[1].trim());
      if (optionName.isEmpty || parts.length > 2 || delta == null) return;
      options.add(
        ModifierOption(
          id: index < previous.length ? previous[index].id : _newModifierId(),
          name: optionName,
          priceDeltaCents: delta,
        ),
      );
    }
    final group = ModifierGroup(
      id: widget.group?.id ?? _newModifierId(),
      name: _name.text.trim(),
      minimumSelections: int.parse(_minimum.text),
      maximumSelections: int.parse(_maximum.text),
      options: List.unmodifiable(options),
    );
    try {
      ModifierGroup.fromJson(group.toJson());
      Navigator.pop(context, group);
    } on Object {
      setState(() {});
    }
  }

  String? _validateOptions(String? value) {
    final lines = (value ?? '')
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) return 'Add at least one option.';
    for (final line in lines) {
      final parts = line.split('|');
      if (parts.first.trim().isEmpty ||
          parts.length > 2 ||
          (parts.length == 2 && _parseCents(parts[1].trim()) == null)) {
        return 'Use “Name | 0.00” for each option.';
      }
    }
    final min = int.tryParse(_minimum.text);
    final max = int.tryParse(_maximum.text);
    if (min == null ||
        max == null ||
        min < 0 ||
        max < 1 ||
        min > max ||
        max > lines.length) {
      return 'Selection limits must fit the available options.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.group == null ? 'Add modifier group' : 'Edit modifier group',
    ),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Group name'),
                validator: (value) => _required(value, 'Enter a group name.'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _minimum,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Minimum'),
                      validator: (value) => int.tryParse(value ?? '') == null
                          ? 'Enter a number.'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _maximum,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Maximum'),
                      validator: (value) => int.tryParse(value ?? '') == null
                          ? 'Enter a number.'
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _options,
                minLines: 3,
                maxLines: 7,
                decoration: const InputDecoration(
                  labelText: 'Options: Name | price adjustment',
                  hintText: 'Regular | 0.00\nOat milk | 0.80',
                  helperText:
                      'Use one option per line. Adjustments must be non-negative.',
                ),
                validator: _validateOptions,
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save group')),
    ],
  );
}

String _newModifierId() => const Uuid().v4();

class TeamManagementDialog extends StatefulWidget {
  const TeamManagementDialog({super.key, required this.api});

  final SaleSyncClient api;

  @override
  State<TeamManagementDialog> createState() => _TeamManagementDialogState();
}

class _TeamManagementDialogState extends State<TeamManagementDialog> {
  List<PosUser> _users = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final users = await widget.api.fetchUsers();
      if (mounted) setState(() => _users = users);
    } on HubApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception {
      if (mounted) {
        setState(
          () => _error = 'Could not load staff. Check the hub connection.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final data = await showDialog<_StaffDraft>(
      context: context,
      builder: (context) => const _StaffEditorDialog(),
    );
    if (data == null) return;
    try {
      await widget.api.createUser(
        name: data.name,
        email: data.email,
        password: data.password,
        role: data.role,
      );
      await _load();
    } on HubApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception {
      if (mounted) {
        setState(
          () => _error =
              'Could not add this staff account. Check the hub connection.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        const Expanded(child: Text('Team accounts')),
        FilledButton.icon(
          onPressed: _add,
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('Add staff'),
        ),
      ],
    ),
    content: SizedBox(
      width: 520,
      height: 420,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _users.isEmpty
          ? Center(child: Text(_error!, textAlign: TextAlign.center))
          : Column(
              children: [
                if (_error != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFB94035)),
                    ),
                  ),
                Expanded(
                  child: ListView.separated(
                    itemCount: _users.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final user = _users[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFE4EFEA),
                          child: Text(
                            user.name.isEmpty
                                ? '?'
                                : user.name[0].toUpperCase(),
                            style: const TextStyle(color: _leaf),
                          ),
                        ),
                        title: Text(user.name),
                        subtitle: Text(user.email),
                        trailing: Text(
                          user.role.label,
                          style: const TextStyle(color: _muted),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );
}

class _StaffDraft {
  const _StaffDraft(this.name, this.email, this.password, this.role);
  final String name;
  final String email;
  final String password;
  final AccountRole role;
}

class _StaffEditorDialog extends StatefulWidget {
  const _StaffEditorDialog();

  @override
  State<_StaffEditorDialog> createState() => _StaffEditorDialogState();
}

class _StaffEditorDialogState extends State<_StaffEditorDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  AccountRole _role = AccountRole.cashier;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      _StaffDraft(_name.text.trim(), _email.text.trim(), _password.text, _role),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add staff account'),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: (value) => _required(value, 'Enter a name.'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email address'),
              validator: (value) =>
                  RegExp(
                    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                  ).hasMatch(value?.trim() ?? '')
                  ? null
                  : 'Enter a valid email.',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<AccountRole>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: const [AccountRole.cashier, AccountRole.manager]
                  .map(
                    (role) =>
                        DropdownMenuItem(value: role, child: Text(role.label)),
                  )
                  .toList(),
              onChanged: (role) {
                if (role != null) setState(() => _role = role);
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(
                labelText: 'Temporary password',
              ),
              validator: (value) => (value?.length ?? 0) >= 12
                  ? null
                  : 'Use at least 12 characters.',
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Create account')),
    ],
  );
}

String? _required(String? value, String message) =>
    (value?.trim().isNotEmpty ?? false) ? null : message;

String? _blankToNull(String value) =>
    value.trim().isEmpty ? null : value.trim();

int? _parseCents(String input) {
  final parts = input.trim().split('.');
  if (parts.length > 2 ||
      parts.first.isEmpty ||
      !RegExp(r'^\d+$').hasMatch(parts.first)) {
    return null;
  }
  final fraction = parts.length == 1 ? '' : parts[1];
  if (fraction.isNotEmpty && !RegExp(r'^\d{1,2}$').hasMatch(fraction)) {
    return null;
  }
  final whole = int.tryParse(parts.first);
  if (whole == null || whole > 90071992547409) return null;
  return whole * 100 + (int.tryParse(fraction.padRight(2, '0')) ?? 0);
}

String _formatCents(int cents) =>
    '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';

String _money(int cents) => 'PHP ${_formatCents(cents)}';
