// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:open_pos/account_gate.dart';
import 'package:open_pos/data/local_database.dart';
import 'package:open_pos/data/pos_repository.dart';
import 'package:open_pos/data/sale_sync_client.dart';
import 'package:open_pos/data/session_vault.dart';
import 'package:open_pos/management_dialogs.dart';
import 'package:open_pos/operations_dialogs.dart';
import 'package:open_pos/purchasing_dialogs.dart';
import 'package:pos_domain/pos_domain.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';

const _ink = Color(0xFF173432);
const _leaf = Color(0xFF0D7468);
const _canvas = Color(0xFFF3F5F2);
const _line = Color(0xFFE3E8E3);
const _muted = Color(0xFF73827D);
const _configuredHubUrl = String.fromEnvironment('POS_HUB_URL');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SukiPosApp());
}

class SukiPosApp extends StatefulWidget {
  const SukiPosApp({
    super.key,
    this.database,
    this.syncClient,
    this.sessionVault,
  });

  final PosDatabase? database;
  final SaleSyncClient? syncClient;
  final SessionVault? sessionVault;

  @override
  State<SukiPosApp> createState() => _SukiPosAppState();
}

class _SukiPosAppState extends State<SukiPosApp> {
  late final PosDatabase _database;
  late final SaleSyncClient _syncClient;
  late final PosRepository _repository;
  late final bool _ownsDatabase;
  late final bool _ownsSyncClient;
  late final SessionVault _sessionVault;
  HubSession? _session;
  List<Product> _products = const [];
  bool _loading = true;
  bool _needsSetup = true;
  bool _hubUnavailable = false;

  @override
  void initState() {
    super.initState();
    _ownsDatabase = widget.database == null;
    _ownsSyncClient = widget.syncClient == null;
    _sessionVault = widget.sessionVault ?? SecureSessionVault();
    _database = widget.database ?? PosDatabase();
    _syncClient =
        widget.syncClient ??
        SaleSyncClient(
          baseUrl: _configuredHubUrl.isNotEmpty
              ? _configuredHubUrl
              : kIsWeb
              ? Uri.base.origin
              : 'http://127.0.0.1:8080',
        );
    _repository = PosRepository(database: _database, syncClient: _syncClient);
    _restoreSession();
  }

  @override
  void dispose() {
    if (_ownsDatabase) _database.close();
    if (_ownsSyncClient) _syncClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Suki POS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _canvas,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _leaf,
          surface: Colors.white,
        ),
        textTheme: const TextTheme(
          headlineSmall: TextStyle(
            color: _ink,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
          ),
          titleLarge: TextStyle(color: _ink, fontWeight: FontWeight.w700),
          titleMedium: TextStyle(color: _ink, fontWeight: FontWeight.w600),
          bodyMedium: TextStyle(color: _ink),
          bodySmall: TextStyle(color: _muted),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          hintStyle: const TextStyle(color: _muted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _leaf, width: 1.5),
          ),
        ),
      ),
      home: _loading
          ? const _StartupScreen()
          : _hubUnavailable
          ? HubUnavailablePage(onRetry: _restoreSession)
          : _session == null
          ? AccountGate(
              needsSetup: _needsSetup,
              api: _syncClient,
              onAuthenticated: _handleAuthentication,
            )
          : RegisterPage(
              repository: _repository,
              session: _session!,
              products: _products,
              api: _syncClient,
              onSaveProduct: _saveProduct,
              onSignOut: _signOut,
            ),
    );
  }

  Future<void> _restoreSession() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _hubUnavailable = false;
      });
    }
    HubSession? cachedSession;
    try {
      cachedSession = await _sessionVault.read();
    } on Object {
      cachedSession = null;
    }
    if (cachedSession != null) {
      _syncClient.token = cachedSession.token;
      try {
        final refreshed = await _syncClient.currentSession();
        cachedSession = refreshed;
        try {
          await _sessionVault.write(refreshed);
        } on Object {
          // Keep the in-memory session if the platform vault is unavailable.
        }
      } on HubApiException catch (error) {
        if (error.statusCode == 401) {
          cachedSession = null;
          _syncClient.token = null;
          try {
            await _sessionVault.clear();
          } on Object {
            // Continue to sign-in if the cached credential could not be removed.
          }
        }
      } on Exception {
        // Cached identity and sales remain available during a hub outage.
      }
      if (cachedSession != null) {
        await _useSession(cachedSession, refreshCatalog: true);
        return;
      }
    }
    try {
      final needsSetup = await _syncClient.needsInitialSetup();
      if (mounted) {
        setState(() {
          _needsSetup = needsSetup;
          _loading = false;
          _hubUnavailable = false;
        });
      }
    } on Exception {
      if (mounted) {
        setState(() {
          _loading = false;
          _hubUnavailable = true;
        });
      }
    }
  }

  Future<void> _handleAuthentication(HubSession session) async =>
      _useSession(session, refreshCatalog: true);

  Future<void> _useSession(
    HubSession session, {
    required bool refreshCatalog,
  }) async {
    _syncClient.token = session.token;
    final savedRegisterId = await _database.readOperationalValue('register_id');
    final registerId = savedRegisterId ?? const Uuid().v4();
    final savedRegisterName = await _database.readOperationalValue(
      'register_name',
    );
    final registerName =
        savedRegisterName ??
        'Register ${registerId.substring(0, 4).toUpperCase()}';
    await _database.saveRegisterIdentity(id: registerId, name: registerName);
    await _syncClient.enrollRegister(id: registerId, name: registerName);
    try {
      await _sessionVault.write(session);
    } on Object {
      // Keep an in-memory session if secure storage is unavailable.
    }
    var products = _products;
    if (refreshCatalog) {
      try {
        final snapshot = await _syncClient.fetchProducts();
        products = snapshot.products;
        await _database.replaceCachedProducts(
          snapshot.version,
          products,
          categories: snapshot.categories,
        );
      } on Exception {
        final cached = await _database.readCachedCatalog();
        if (cached != null) {
          products = cached.products;
        }
      }
    }
    if (mounted) {
      setState(() {
        _session = session;
        _products = products;
        _loading = false;
        _hubUnavailable = false;
      });
    }
  }

  Future<List<Product>> _saveProduct(Product? existing, Product product) async {
    final refreshed = await _repository.saveCatalogProduct(existing, product);
    if (mounted) setState(() => _products = refreshed);
    return refreshed;
  }

  Future<void> _signOut() async {
    await _syncClient.signOut();
    try {
      await _sessionVault.clear();
    } on Object {
      // The API client token is cleared even if secure storage is unavailable.
    }
    if (mounted) {
      setState(() {
        _session = null;
        _needsSetup = false;
      });
    }
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Opening your register…'),
        ],
      ),
    ),
  );
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({
    super.key,
    required this.repository,
    this.session,
    this.products = defaultProducts,
    this.api,
    this.onSaveProduct,
    this.onSignOut,
  });

  final PosRepository repository;
  final HubSession? session;
  final List<Product> products;
  final SaleSyncClient? api;
  final ProductSave? onSaveProduct;
  final VoidCallback? onSignOut;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _searchController = TextEditingController();
  final _cashController = TextEditingController(text: '0.00');
  final Map<String, _CartItem> _cart = {};
  late List<Product> _products;
  String _category = 'All items';
  String _query = '';
  int _pendingSales = 0;
  int _pendingPayments = 0;
  CashShift? _shift;
  TaxConfig _tax = const TaxConfig();
  LoyaltyConfig _loyalty = const LoyaltyConfig();
  List<Customer> _customers = const [];
  Customer? _customer;
  int _discountCents = 0;
  String? _discountReason;
  int _pointsRedeemed = 0;
  bool _hubAvailable = false;
  bool _cashWasEdited = false;
  bool _savingSale = false;
  bool _syncingPendingSales = false;
  bool _syncingChangeFeed = false;
  bool _syncingQueues = false;
  Timer? _syncTimer;

  int get _subtotalCents => _cart.values.fold(
    0,
    (sum, item) => sum + item.unitTotalCents * item.quantity,
  );

  int get _effectiveDiscountCents => _discountCents + _loyaltyDiscountCents;

  int get _loyaltyDiscountCents =>
      _pointsRedeemed * _loyalty.redeemCentsPerPoint;

  int get _taxCents {
    final taxable = (_subtotalCents - _effectiveDiscountCents).clamp(
      0,
      _subtotalCents,
    );
    final denominator = _tax.pricesIncludeTax
        ? 10000 + _tax.rateBasisPoints
        : 10000;
    return ((BigInt.from(taxable) * BigInt.from(_tax.rateBasisPoints) +
                BigInt.from(denominator ~/ 2)) ~/
            BigInt.from(denominator))
        .toInt();
  }

  int get _totalCents {
    final discounted = (_subtotalCents - _effectiveDiscountCents).clamp(
      0,
      _subtotalCents,
    );
    return _tax.pricesIncludeTax ? discounted : discounted + _taxCents;
  }

  int get _itemCount =>
      _cart.values.fold(0, (sum, item) => sum + item.quantity);

  int get _pendingSyncCount => _pendingSales + _pendingPayments;

  int get _cashCents => _parseCents(_cashController.text);

  List<Product> get _visibleProducts => _products
      .where((product) {
        final matchesCategory =
            _category == 'All items' || product.category == _category;
        final normalizedQuery = _query.trim().toLowerCase();
        final matchesSearch =
            normalizedQuery.isEmpty ||
            product.name.toLowerCase().contains(normalizedQuery) ||
            (product.sku?.toLowerCase().contains(normalizedQuery) ?? false) ||
            (product.barcode?.toLowerCase().contains(normalizedQuery) ?? false);
        return matchesCategory && matchesSearch;
      })
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _products = widget.products.where((product) => product.isActive).toList();
    _refreshPendingAndSync();
    _refreshShift();
    _loadCheckoutSettings();
    if (widget.api != null) {
      _syncTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _refreshPendingAndSync(),
      );
    }
  }

  @override
  void didUpdateWidget(covariant RegisterPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.products, widget.products)) {
      _products = widget.products.where((product) => product.isActive).toList();
      if (!_products.any((product) => product.category == _category)) {
        _category = 'All items';
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _cashController.dispose();
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshPendingAndSync() async {
    if (_syncingQueues) return;
    _syncingQueues = true;
    try {
      await widget.repository.syncPendingSales();
      await widget.repository.syncPendingStockMovements();
      await widget.repository.syncPendingCatalogOperations();
      await widget.repository.syncPendingPayments();
      await _syncRemoteChanges();
      final count = await widget.repository.pendingSaleCount();
      final paymentCount = await widget.repository.pendingPaymentCount();
      if (mounted) {
        setState(() {
          _pendingSales = count;
          _pendingPayments = paymentCount;
        });
      }
    } finally {
      _syncingQueues = false;
    }
  }

  Future<void> _syncRemoteChanges() async {
    if (_syncingChangeFeed || widget.api == null) return;
    _syncingChangeFeed = true;
    try {
      final changes = await widget.repository.syncChanges();
      if (changes == null || !mounted) return;
      if (changes.catalog != null) {
        setState(() {
          _products = changes.catalog!.products
              .where((product) => product.isActive)
              .toList(growable: false);
          if (!_products.any((product) => product.category == _category)) {
            _category = 'All items';
          }
        });
      }
      if (changes.settingsChanged) await _loadCheckoutSettings();
      if (changes.shiftChanged) await _refreshShift();
    } finally {
      _syncingChangeFeed = false;
    }
  }

  Future<void> _loadCheckoutSettings() async {
    final database = widget.repository.database;
    try {
      final cachedTax = await database.readOperationalValue('tax_config');
      if (cachedTax != null) {
        _tax = TaxConfig.fromJson(
          jsonDecode(cachedTax) as Map<String, Object?>,
        );
      }
      final cachedLoyalty = await database.readOperationalValue(
        'loyalty_config',
      );
      if (cachedLoyalty != null) {
        _loyalty = LoyaltyConfig.fromJson(
          jsonDecode(cachedLoyalty) as Map<String, Object?>,
        );
      }
      final cachedCustomers = await database.readOperationalValue(
        'customers_cache',
      );
      if (cachedCustomers != null) {
        _customers = (jsonDecode(cachedCustomers) as List<Object?>)
            .map((row) => Customer.fromJson(row! as Map<String, Object?>))
            .toList(growable: false);
      }
      if (mounted) setState(() {});
    } on Exception {
      // A corrupt optional cache does not block checkout.
    }
    final api = widget.api;
    if (api == null) return;
    try {
      final values = await Future.wait([
        api.fetchTaxConfig(),
        api.fetchLoyaltyConfig(),
        api.fetchCustomers(),
      ]);
      _tax = values[0] as TaxConfig;
      _loyalty = values[1] as LoyaltyConfig;
      _customers = values[2] as List<Customer>;
      await database.saveOperationalValue(
        'tax_config',
        jsonEncode(_tax.toJson()),
      );
      await database.saveOperationalValue(
        'loyalty_config',
        jsonEncode(_loyalty.toJson()),
      );
      await database.saveOperationalValue(
        'customers_cache',
        jsonEncode(
          _customers
              .map((customer) => customer.toJson())
              .toList(growable: false),
        ),
      );
      _hubAvailable = true;
      if (mounted) setState(() {});
    } on Exception {
      _hubAvailable = false;
    }
  }

  Future<void> _refreshShift() async {
    final api = widget.api;
    if (api == null) return;
    try {
      final cachedShift = await widget.repository.database.readCachedShift();
      if (cachedShift != null && mounted) {
        setState(() => _shift = cachedShift);
      }
    } on Exception {
      // The hub remains the source of truth when the local snapshot is unreadable.
    }
    try {
      final shift = await api.currentCashShift();
      await widget.repository.database.saveCachedShift(shift);
      if (mounted) setState(() => _shift = shift);
    } on Exception {
      // Keep the cached shift so offline sales retain the correct shift ID.
    }
  }

  Future<void> _manageCashDrawer() async {
    final api = widget.api;
    if (api == null) return;
    await showCashDrawer(context: context, api: api, shift: _shift);
    await _refreshShift();
  }

  Future<void> _pickCustomer() async {
    if (_customers.isEmpty) {
      await _createCustomer();
      return;
    }
    final selected = await showDialog<Customer>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose customer'),
        content: SizedBox(
          width: 420,
          height: 360,
          child: ListView(
            children: _customers
                .map(
                  (customer) => ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.person_outline),
                    ),
                    title: Text(customer.name),
                    subtitle: Text(
                      '${customer.loyaltyPoints} loyalty points${customer.phone == null ? '' : ' · ${customer.phone}'}',
                    ),
                    onTap: () => Navigator.pop(context, customer),
                  ),
                )
                .toList(growable: false),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.tonalIcon(
            onPressed: widget.api == null
                ? null
                : () async {
                    Navigator.pop(context);
                    await _createCustomer();
                  },
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('New customer'),
          ),
        ],
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        _customer = selected;
        _pointsRedeemed = 0;
      });
    }
  }

  Future<void> _createCustomer() async {
    final api = widget.api;
    if (api == null) return;
    try {
      final details = await showDialog<List<String>>(
        context: context,
        builder: (_) => const _CustomerDraftDialog(),
      );
      if (details == null || details.first.isEmpty) return;
      final customer = await api.createCustomer(
        name: details[0],
        phone: details[1].isEmpty ? null : details[1],
        email: details[2].isEmpty ? null : details[2],
      );
      _customers = [..._customers, customer]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _customer = customer;
      await widget.repository.database.saveOperationalValue(
        'customers_cache',
        jsonEncode(
          _customers.map((row) => row.toJson()).toList(growable: false),
        ),
      );
      if (mounted) setState(() {});
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is HubApiException
                  ? error.message
                  : 'Could not save customer.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _toggleLoyaltyRedemption() async {
    final customer = _customer;
    final api = widget.api;
    if (customer == null || api == null) return;
    try {
      final customers = await api.fetchCustomers();
      _customers = customers;
      final matching = customers.where((row) => row.id == customer.id);
      final fresh = matching.isEmpty ? null : matching.first;
      if (fresh == null) {
        throw const FormatException('Customer is no longer available.');
      }
      final maxPoints =
          ((_subtotalCents - _discountCents).clamp(0, _subtotalCents) ~/
                  _loyalty.redeemCentsPerPoint)
              .clamp(0, fresh.loyaltyPoints);
      setState(() {
        _customer = fresh;
        _pointsRedeemed = _pointsRedeemed > 0 ? 0 : maxPoints;
        _hubAvailable = true;
        _updateExactCashIfUntouched();
      });
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is HubApiException
                  ? error.message
                  : 'Connect to the hub to redeem points.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _editDiscount() async {
    final values = await showDialog<List<String>>(
      context: context,
      builder: (_) => _DiscountDialog(
        initialAmount: _discountCents,
        initialReason: _discountReason ?? '',
        maximumCents: _subtotalCents,
      ),
    );
    if (values == null) return;
    final cents = _parseCents(values[0]);
    final note = values[1].trim();
    if (cents > _subtotalCents || (cents > 0 && note.isEmpty)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid discount and reason.')),
        );
      }
      return;
    }
    setState(() {
      _discountCents = cents;
      _discountReason = cents == 0 ? null : note;
      _pointsRedeemed = 0;
      _updateExactCashIfUntouched();
    });
  }

  Future<void> _configureTaxAndLoyalty() async {
    final api = widget.api;
    if (api == null) return;
    try {
      final config = await showDialog<TaxConfig>(
        context: context,
        builder: (_) => _TaxSettingsDialog(initial: _tax),
      );
      if (config != null) {
        _tax = await api.saveTaxConfig(config);
        await widget.repository.database.saveOperationalValue(
          'tax_config',
          jsonEncode(_tax.toJson()),
        );
        if (mounted) {
          setState(() {
            _hubAvailable = true;
            _updateExactCashIfUntouched();
          });
        }
      }
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is HubApiException
                  ? error.message
                  : 'Could not save tax settings.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _configureLoyalty() async {
    final api = widget.api;
    if (api == null) return;
    try {
      final config = await showDialog<LoyaltyConfig>(
        context: context,
        builder: (_) => _LoyaltySettingsDialog(initial: _loyalty),
      );
      if (config != null) {
        _loyalty = await api.saveLoyaltyConfig(config);
        await widget.repository.database.saveOperationalValue(
          'loyalty_config',
          jsonEncode(_loyalty.toJson()),
        );
        if (mounted) {
          setState(() {
            _pointsRedeemed = 0;
          });
        }
      }
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is HubApiException
                  ? error.message
                  : 'Could not save loyalty settings.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _showReceipt(Sale sale, Customer? customer) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sale complete'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.session?.store.name ?? 'Suki POS',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Receipt ${sale.id}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
                if (customer != null)
                  Text(customer.name, textAlign: TextAlign.center),
                const Divider(height: 22),
                ...sale.lines.map(
                  (line) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('${line.quantity} × ${line.name}'),
                        ),
                        Text(_formatMoney(line.totalCents)),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 22),
                _MoneyRow(label: 'Subtotal', cents: sale.subtotalCents),
                if (sale.discountCents > 0)
                  _MoneyRow(label: 'Discount', cents: -sale.discountCents),
                _MoneyRow(label: sale.taxName, cents: sale.taxCents),
                _MoneyRow(
                  label: 'Total',
                  cents: sale.totalCents,
                  prominent: true,
                ),
                _MoneyRow(label: 'Cash', cents: sale.tenderedCents),
                _MoneyRow(label: 'Change', cents: sale.changeCents),
                const SizedBox(height: 12),
                const Text(
                  'Thank you for shopping with us!',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await _printReceipt(sale, customer);
            },
            icon: const Icon(Icons.print_outlined),
            label: const Text('Print receipt'),
          ),
        ],
      ),
    );
  }

  Future<void> _printReceipt(Sale sale, Customer? customer) async {
    final document = pw.Document();
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(12),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              widget.session?.store.name ?? 'Suki POS',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 5),
            pw.Text(
              'Receipt ${sale.id}',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 8),
            ),
            if (customer != null)
              pw.Text(
                customer.name,
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 9),
              ),
            pw.Divider(),
            ...sale.lines.map(
              (line) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        '${line.quantity} x ${_saleLineName(line)}',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ),
                    pw.Text(
                      _formatCents(line.totalCents),
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ],
                ),
              ),
            ),
            pw.Divider(),
            _pdfRow('Subtotal', sale.subtotalCents),
            if (sale.discountCents > 0)
              _pdfRow('Discount', -sale.discountCents),
            _pdfRow(sale.taxName, sale.taxCents),
            _pdfRow('TOTAL', sale.totalCents, bold: true),
            _pdfRow('Cash', sale.tenderedCents),
            _pdfRow('Change', sale.changeCents),
            pw.SizedBox(height: 12),
            pw.Text(
              'Thank you!',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 10),
            ),
          ],
        ),
      ),
    );
    try {
      await Printing.layoutPdf(onLayout: (_) async => document.save());
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not print receipt: $error')),
        );
      }
    }
  }

  Future<void> _syncPendingSales() async {
    if (_syncingPendingSales) return;
    setState(() => _syncingPendingSales = true);
    try {
      await widget.repository.syncPendingSales(force: true);
      final count = await widget.repository.pendingSaleCount();
      final paymentCount = await widget.repository.pendingPaymentCount();
      if (mounted) {
        setState(() {
          _pendingSales = count;
          _pendingPayments = paymentCount;
        });
      }
    } finally {
      if (mounted) setState(() => _syncingPendingSales = false);
    }
  }

  Future<void> _addProduct(Product product) async {
    final modifiers = product.modifierGroups.isEmpty
        ? const <SelectedModifier>[]
        : await showDialog<List<SelectedModifier>>(
            context: context,
            builder: (context) => _ModifierSelectionDialog(product: product),
          );
    if (modifiers == null || !mounted) return;
    final key = _cartKey(product, modifiers);
    setState(() {
      final existing = _cart[key];
      _cart[key] = _CartItem(
        product: product,
        quantity: (existing?.quantity ?? 0) + 1,
        modifiers: modifiers,
      );
      _updateExactCashIfUntouched();
    });
  }

  void _changeQuantity(_CartItem item, int delta) {
    setState(() {
      final existing = _cart[item.key];
      if (existing == null) return;
      final quantity = existing.quantity + delta;
      if (quantity < 1) {
        _cart.remove(item.key);
      } else {
        _cart[item.key] = _CartItem(
          product: item.product,
          quantity: quantity,
          modifiers: item.modifiers,
        );
      }
      if (_discountCents > _subtotalCents) {
        _discountCents = _subtotalCents;
        if (_discountCents == 0) _discountReason = null;
      }
      if (_customer != null) {
        final maximum =
            (_subtotalCents - _discountCents).clamp(0, _subtotalCents) ~/
            _loyalty.redeemCentsPerPoint;
        if (_pointsRedeemed > maximum) _pointsRedeemed = maximum;
      }
      _updateExactCashIfUntouched();
    });
  }

  void _updateExactCashIfUntouched() {
    if (!_cashWasEdited) _cashController.text = _formatCents(_totalCents);
  }

  Future<void> _completeSale() async {
    if (_cart.isEmpty || _cashCents < _totalCents || _savingSale) return;
    setState(() => _savingSale = true);
    try {
      final customerForReceipt = _customer;
      final result = await widget.repository.completeCashSale(
        lines: _cart.values.map(
          (item) => SaleLine(
            productId: item.product.id,
            name: item.product.name,
            unitPriceCents: item.product.unitPriceCents,
            quantity: item.quantity,
            productVersion: item.product.version,
            modifiers: item.modifiers,
          ),
        ),
        tenderedCents: _cashCents,
        shiftId: _shift?.id,
        discountCents: _effectiveDiscountCents,
        discountReason: _effectiveDiscountCents == 0
            ? null
            : [_discountReason, if (_pointsRedeemed > 0) 'Loyalty redemption']
                  .whereType<String>()
                  .where((value) => value.isNotEmpty)
                  .join(' · '),
        tax: _tax,
        loyalty: _loyalty,
        customer: _customer,
        pointsRedeemed: _pointsRedeemed,
        loyaltyDiscountCents: _loyaltyDiscountCents,
      );
      final count = await widget.repository.pendingSaleCount();
      final paymentCount = await widget.repository.pendingPaymentCount();
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _customer = null;
        _discountCents = 0;
        _discountReason = null;
        _pointsRedeemed = 0;
        _cashWasEdited = false;
        _pendingSales = count;
        _pendingPayments = paymentCount;
        _cashController.text = '0.00';
      });
      final message = result.synced
          ? 'Sale saved · change ${_formatMoney(result.sale.changeCents)}'
          : 'Sale saved offline · ${_formatMoney(result.sale.changeCents)} change';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
      setState(() => _savingSale = false);
      await _showReceipt(result.sale, customerForReceipt);
    } on ArgumentError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message?.toString() ?? 'Check cash amount.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingSale = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 1050;
            if (isWide) {
              return Row(
                children: [
                  Expanded(child: _buildCatalog()),
                  SizedBox(
                    width: 370,
                    child: _buildCartPanel(showClose: false),
                  ),
                ],
              );
            }
            return _buildCatalog();
          },
        ),
      ),
      bottomNavigationBar: MediaQuery.sizeOf(context).width < 1050
          ? _mobileCartBar()
          : null,
    );
  }

  Widget _buildCatalog() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _topBar(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 26, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Good morning, ${widget.session?.user.name.split(' ').first ?? 'there'}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 5),
                const Text('What are we selling today?'),
                const SizedBox(height: 22),
                _searchField(),
                const SizedBox(height: 18),
                _categoryPicker(),
                const SizedBox(height: 18),
                _productGrid(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _topBar() {
    final isCompact = MediaQuery.sizeOf(context).width < 600;
    return Container(
      height: isCompact ? 64 : 74,
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _leaf,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.storefront_rounded,
              color: Colors.white,
              size: 21,
            ),
          ),
          const SizedBox(width: 11),
          const Text(
            'suki',
            style: TextStyle(
              color: _ink,
              fontSize: 21,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          if (!isCompact) ...[
            const SizedBox(width: 20),
            Container(height: 30, width: 1, color: _line),
            const SizedBox(width: 18),
            const Icon(
              Icons.store_mall_directory_outlined,
              size: 18,
              color: _muted,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                widget.session?.store.name ?? 'Your store',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
          const Spacer(),
          _connectionStatus(compact: isCompact),
          const SizedBox(width: 6),
          _accountMenu(isCompact),
        ],
      ),
    );
  }

  Widget _accountMenu(bool compact) {
    final user = widget.session?.user;
    final canManageCatalog =
        user?.role == AccountRole.admin || user?.role == AccountRole.manager;
    return PopupMenuButton<String>(
      tooltip: 'Account and store settings',
      onSelected: (value) async {
        if (value == 'catalog' && widget.onSaveProduct != null) {
          await showCatalogManagement(
            context: context,
            products: _products,
            onSave: widget.onSaveProduct!,
            repository: widget.repository,
          );
        } else if (value == 'team' && widget.api != null) {
          await showDialog<void>(
            context: context,
            builder: (context) => TeamManagementDialog(api: widget.api!),
          );
        } else if (value == 'inventory' && widget.api != null) {
          await showInventoryManagement(
            context: context,
            api: widget.api!,
            repository: widget.repository,
          );
        } else if (value == 'purchasing' && widget.api != null) {
          await showPurchasingManagement(
            context: context,
            repository: widget.repository,
            products: _products,
          );
        } else if (value == 'tax-loyalty' && widget.api != null) {
          await _configureTaxAndLoyalty();
        } else if (value == 'loyalty' && widget.api != null) {
          await _configureLoyalty();
        } else if (value == 'sales' && widget.api != null) {
          await showDialog<void>(
            context: context,
            builder: (context) => SalesHistoryDialog(
              api: widget.api!,
              canManage: canManageCatalog,
            ),
          );
        } else if (value == 'cash-drawer') {
          await _manageCashDrawer();
        } else if (value == 'signout') {
          widget.onSignOut?.call();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          value: 'identity',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user?.name ?? 'Cashier',
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                user?.role.label ?? 'Register',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
        if (canManageCatalog && widget.onSaveProduct != null)
          const PopupMenuItem(
            value: 'catalog',
            child: ListTile(
              leading: Icon(Icons.inventory_2_outlined),
              title: Text('Product catalog'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
        if (canManageCatalog && widget.api != null)
          const PopupMenuItem(
            value: 'inventory',
            child: ListTile(
              leading: Icon(Icons.warehouse_outlined),
              title: Text('Inventory and stock'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
        if (canManageCatalog && widget.api != null)
          const PopupMenuItem(
            value: 'purchasing',
            child: ListTile(
              leading: Icon(Icons.local_shipping_outlined),
              title: Text('Suppliers and purchasing'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
        if (widget.api != null)
          const PopupMenuItem(
            value: 'sales',
            child: ListTile(
              leading: Icon(Icons.receipt_long_outlined),
              title: Text('Sales and returns'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
        if (canManageCatalog && widget.api != null)
          const PopupMenuItem(
            value: 'tax-loyalty',
            child: ListTile(
              leading: Icon(Icons.percent_rounded),
              title: Text('Tax settings'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
        if (canManageCatalog && widget.api != null)
          const PopupMenuItem(
            value: 'loyalty',
            child: ListTile(
              leading: Icon(Icons.stars_outlined),
              title: Text('Loyalty program'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
        if (widget.api != null)
          PopupMenuItem(
            value: 'cash-drawer',
            child: ListTile(
              leading: const Icon(Icons.point_of_sale_outlined),
              title: Text(
                _shift?.isOpen == true
                    ? 'Cash drawer · Open'
                    : 'Cash drawer · Closed',
              ),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
        if (user?.role == AccountRole.admin && widget.api != null)
          const PopupMenuItem(
            value: 'team',
            child: ListTile(
              leading: Icon(Icons.people_outline_rounded),
              title: Text('Team accounts'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
        if (widget.onSignOut != null)
          const PopupMenuItem(
            value: 'signout',
            child: ListTile(
              leading: Icon(Icons.logout_rounded),
              title: Text('Sign out'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
      ],
      child: compact
          ? const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.account_circle_outlined, color: _ink),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: const Color(0xFFE4EFEA),
                  child: Text(
                    (user?.name.isNotEmpty ?? false)
                        ? user!.name[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: _leaf,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.expand_more_rounded, color: _muted),
              ],
            ),
    );
  }

  Widget _connectionStatus({required bool compact}) {
    final color = _pendingSyncCount == 0 ? _leaf : const Color(0xFF9C6A13);
    final text = _pendingSyncCount == 0
        ? 'Ready to sync'
        : '$_pendingSyncCount waiting to sync';
    if (compact) {
      return IconButton(
        tooltip: text,
        onPressed: _pendingSyncCount == 0 || _syncingPendingSales
            ? null
            : _syncPendingSales,
        icon: _syncingPendingSales
            ? const SizedBox.square(
                dimension: 17,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                _pendingSyncCount == 0
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_upload_outlined,
                color: color,
              ),
      );
    }
    if (_pendingSyncCount > 0) {
      return TextButton.icon(
        onPressed: _syncingPendingSales ? null : _syncPendingSales,
        icon: _syncingPendingSales
            ? const SizedBox.square(
                dimension: 13,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(Icons.sync_rounded, size: 16, color: color),
        label: Text(text, style: TextStyle(color: color, fontSize: 12)),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 34),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 7),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField() => TextField(
    controller: _searchController,
    onChanged: (value) => setState(() => _query = value),
    decoration: const InputDecoration(
      prefixIcon: Icon(Icons.search_rounded),
      hintText: 'Search products or scan a barcode',
      contentPadding: EdgeInsets.symmetric(vertical: 15),
    ),
  );

  Widget _categoryPicker() {
    final categories =
        _products.map((product) => product.category).toSet().toList()..sort();
    categories.insert(0, 'All items');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: categories
            .map((category) {
              final selected = _category == category;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(category),
                  selected: selected,
                  onSelected: (_) => setState(() => _category = category),
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : _ink,
                    fontWeight: FontWeight.w600,
                  ),
                  selectedColor: _ink,
                  backgroundColor: Colors.white,
                  side: BorderSide(color: selected ? _ink : _line),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }

  Widget _productGrid() {
    if (_visibleProducts.isEmpty) {
      final canManageCatalog =
          widget.session?.user.role == AccountRole.admin ||
          widget.session?.user.role == AccountRole.manager;
      final message = _products.isEmpty
          ? canManageCatalog
                ? 'No products yet. Add your first item from Product catalog.'
                : 'No products are available. Ask a manager to add catalog items.'
          : 'No products match your search.';
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: Text(message, textAlign: TextAlign.center)),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 820
            ? 4
            : constraints.maxWidth >= 570
            ? 3
            : 2;
        return GridView.builder(
          itemCount: _visibleProducts.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.18,
          ),
          itemBuilder: (context, index) {
            final product = _visibleProducts[index];
            return _ProductTile(
              product: product,
              quantity: _cart[product.id]?.quantity ?? 0,
              onTap: () => _addProduct(product),
            );
          },
        );
      },
    );
  }

  Widget _mobileCartBar() => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: _line)),
    ),
    child: FilledButton(
      onPressed: _showCartSheet,
      style: FilledButton.styleFrom(
        backgroundColor: _ink,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.shopping_bag_outlined),
          const SizedBox(width: 9),
          Text('Cart · $_itemCount'),
          const Spacer(),
          Text(_formatMoney(_totalCents)),
          const SizedBox(width: 10),
          const Icon(Icons.arrow_forward_rounded, size: 18),
        ],
      ),
    ),
  );

  void _showCartSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.9,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: _buildCartPanel(showClose: true),
        ),
      ),
    );
  }

  Widget _buildCartPanel({required bool showClose}) => Container(
    color: Colors.white,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 16, 17),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current sale',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$_itemCount ${_itemCount == 1 ? 'item' : 'items'}',
                      style: const TextStyle(color: _muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Clear sale',
                onPressed: _cart.isEmpty ? null : _clearCart,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
              if (showClose)
                IconButton(
                  tooltip: 'Close cart',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
        ),
        const Divider(height: 1, color: _line),
        Expanded(
          child: _cart.isEmpty
              ? const _EmptyCart()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                  itemCount: _cart.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: _line),
                  itemBuilder: (context, index) {
                    final item = _cart.values.elementAt(index);
                    return _CartLine(
                      item: item,
                      onDecrease: () => _changeQuantity(item, -1),
                      onIncrease: () => _changeQuantity(item, 1),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickCustomer,
                    icon: Icon(
                      _customer == null ? Icons.person_add_alt_1 : Icons.person,
                    ),
                    label: Text(_customer?.name ?? 'Add customer'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(44, 44),
                    ),
                  ),
                  if (widget.session?.user.role == AccountRole.admin ||
                      widget.session?.user.role == AccountRole.manager)
                    OutlinedButton.icon(
                      onPressed: _editDiscount,
                      icon: const Icon(Icons.sell_outlined),
                      label: Text(
                        _discountCents == 0
                            ? 'Discount'
                            : 'Discount ${_formatMoney(_discountCents)}',
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(44, 44),
                      ),
                    ),
                  if (_customer != null && _customer!.loyaltyPoints > 0)
                    TextButton.icon(
                      onPressed: _hubAvailable
                          ? _toggleLoyaltyRedemption
                          : null,
                      icon: Icon(
                        _pointsRedeemed > 0
                            ? Icons.stars_rounded
                            : Icons.stars_outlined,
                      ),
                      label: Text(
                        _pointsRedeemed > 0
                            ? 'Used $_pointsRedeemed points'
                            : '${_customer!.loyaltyPoints} points',
                      ),
                    ),
                  if (_customer != null)
                    IconButton(
                      tooltip: 'Remove customer',
                      onPressed: () => setState(() {
                        _customer = null;
                        _pointsRedeemed = 0;
                      }),
                      icon: const Icon(Icons.close_rounded),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _MoneyRow(label: 'Subtotal', cents: _subtotalCents),
              if (_effectiveDiscountCents > 0) ...[
                const SizedBox(height: 6),
                _MoneyRow(label: 'Discount', cents: _effectiveDiscountCents),
              ],
              const SizedBox(height: 6),
              _MoneyRow(
                label:
                    '${_tax.name} (${(_tax.rateBasisPoints / 100).toStringAsFixed(2)}%)',
                cents: _taxCents,
              ),
              const Divider(height: 20, color: _line),
              _MoneyRow(
                label: 'Total due',
                cents: _totalCents,
                prominent: true,
              ),
              const SizedBox(height: 14),
              const Text(
                'Cash received',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              if (widget.api != null && _shift?.isOpen != true) ...[
                const SizedBox(height: 5),
                const Text(
                  'Open the cash drawer before completing a sale.',
                  style: TextStyle(color: Color(0xFFB94035), fontSize: 12),
                ),
              ],
              const SizedBox(height: 7),
              TextField(
                controller: _cashController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() => _cashWasEdited = true),
                decoration: const InputDecoration(
                  prefixText: 'PHP ',
                  hintText: '0.00',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 13,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (_cashCents >= _totalCents && _totalCents > 0)
                _MoneyRow(label: 'Change', cents: _cashCents - _totalCents)
              else if (_totalCents > 0)
                const Text(
                  'Cash received is below the amount due.',
                  style: TextStyle(color: Color(0xFFB94035), fontSize: 12),
                ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed:
                    _cart.isNotEmpty &&
                        _cashCents >= _totalCents &&
                        (widget.api == null || _shift?.isOpen == true) &&
                        !_savingSale
                    ? _completeSale
                    : null,
                icon: _savingSale
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: const Text('Complete cash sale'),
                style: FilledButton.styleFrom(
                  backgroundColor: _leaf,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  void _clearCart() {
    setState(() {
      _cart.clear();
      _customer = null;
      _discountCents = 0;
      _discountReason = null;
      _pointsRedeemed = 0;
      _cashWasEdited = false;
      _cashController.text = '0.00';
    });
  }
}

class SalesHistoryDialog extends StatefulWidget {
  const SalesHistoryDialog({
    super.key,
    required this.api,
    required this.canManage,
  });

  final SaleSyncClient api;
  final bool canManage;

  @override
  State<SalesHistoryDialog> createState() => _SalesHistoryDialogState();
}

class _SalesHistoryDialogState extends State<SalesHistoryDialog> {
  List<Map<String, Object?>> _sales = const [];
  bool _loading = true;
  String? _error;
  int _selectedView = 0;
  int _reportDays = 7;
  Map<String, Object?>? _report;
  bool _reportLoading = false;
  String? _reportError;
  String? _reportFrom;
  String? _reportTo;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_selectedView == 1 && widget.canManage) {
      await _refreshReport();
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sales = await widget.api.fetchSales();
      if (mounted) {
        setState(() {
          _sales = sales;
          _loading = false;
        });
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _error = error is HubApiException
              ? error.message
              : 'Could not load sales.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _refreshReport() async {
    final now = DateTime.now().toUtc();
    final to = DateTime.utc(now.year, now.month, now.day);
    final from = to.subtract(Duration(days: _reportDays - 1));
    setState(() {
      _reportLoading = true;
      _reportError = null;
    });
    try {
      final report = await widget.api.fetchSalesReport(from: from, to: to);
      if (mounted) {
        setState(() {
          _report = report;
          _reportFrom = report['from'] as String?;
          _reportTo = report['to'] as String?;
          _reportLoading = false;
        });
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _reportError = error is HubApiException
              ? error.message
              : 'Could not load the sales report.';
          _reportLoading = false;
        });
      }
    }
  }

  void _selectView(int value) {
    setState(() => _selectedView = value);
    if (value == 1) _refreshReport();
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final compact = viewport.width < 600;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: SizedBox(
        width: compact ? viewport.width * 0.9 : 860,
        height: viewport.height * 0.9,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(compact ? 16 : 22, 12, 8, 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Sales and returns',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _refresh,
                    tooltip: 'Refresh',
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            if (widget.canManage)
              Padding(
                padding: EdgeInsets.fromLTRB(compact ? 12 : 22, 0, 12, 10),
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Sales history')),
                    ButtonSegment(value: 1, label: Text('Reports')),
                  ],
                  selected: {_selectedView},
                  onSelectionChanged: (selection) =>
                      _selectView(selection.first),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: _selectedView == 1 && widget.canManage
                  ? _reportContent(compact)
                  : _salesContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _salesContent() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }
    if (_sales.isEmpty) {
      return const Center(child: Text('No completed sales yet.'));
    }
    return ListView.separated(
      itemCount: _sales.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => _saleTile(_sales[index]),
    );
  }

  Widget _reportContent(bool compact) {
    if (_reportLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_reportError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_reportError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _refreshReport,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    final report = _report;
    if (report == null) {
      return const Center(child: Text('Choose a range to view the report.'));
    }
    final summaryRaw = report['summary'];
    final summary = summaryRaw is Map
        ? summaryRaw.map((key, value) => MapEntry(key.toString(), value))
        : <String, Object?>{};
    final daily = _reportRows('daily');
    final topProducts = _reportRows('topProducts');
    final shifts = _reportRows('shifts');
    int count(String key) => summary[key] as int? ?? 0;
    final metrics = <(String, String, String?)>[
      ('Gross sales', _formatMoney(count('grossSalesCents')), null),
      (
        'Net sales',
        _formatMoney(count('netSalesCents')),
        'After refunds and voids',
      ),
      ('Discounts', _formatMoney(count('discountCents')), null),
      ('Tax collected', _formatMoney(count('taxCents')), null),
      (
        'Refunds',
        _formatMoney(count('refundCents')),
        '${count('refundCount')} transactions',
      ),
      (
        'Voids',
        _formatMoney(count('voidedCents')),
        '${count('voidCount')} sales',
      ),
      (
        'Cash variance',
        _formatMoney(count('cashVarianceCents')),
        'Shifts closed in range',
      ),
      (
        'Cash paid in',
        _formatMoney(count('cashPaidInCents')),
        'Cash drawer movements',
      ),
      (
        'Cash paid out',
        _formatMoney(count('cashPaidOutCents')),
        'Includes refunds and voids',
      ),
      (
        'Shifts',
        '${count('shiftsOpened')} opened',
        '${count('shiftsClosed')} closed · ${count('openShiftCount')} currently open',
      ),
    ];

    return SingleChildScrollView(
      padding: EdgeInsets.all(compact ? 14 : 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Sales report',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_reportFrom ?? report['from']} – ${_reportTo ?? report['to']} (UTC)',
            style: const TextStyle(color: _muted),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final days in const [7, 30, 90])
                ChoiceChip(
                  label: Text('$days days'),
                  selected: _reportDays == days,
                  onSelected: (selected) {
                    if (!selected) return;
                    setState(() => _reportDays = days);
                    _refreshReport();
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Sales, refunds, voids, and cash movements use their recorded UTC event dates.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: _muted),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 540 ? 2 : 3;
              final tileWidth =
                  (constraints.maxWidth - (columns - 1) * 10) / columns;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final metric in metrics)
                    SizedBox(
                      width: tileWidth,
                      child: _reportMetric(
                        metric.$1,
                        metric.$2,
                        detail: metric.$3,
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 22),
          _reportSectionTitle('Daily activity'),
          const SizedBox(height: 6),
          if (daily.every(
            (row) =>
                row['salesCount'] == 0 &&
                row['refundCount'] == 0 &&
                row['voidCount'] == 0,
          ))
            const _ReportEmptyRow(
              message: 'No sales, refunds, or voids in this date range.',
            )
          else
            ...daily.reversed.map((row) {
              final date = row['date'] as String? ?? '';
              final sales = row['salesCount'] as int? ?? 0;
              final refunds = row['refundCount'] as int? ?? 0;
              final voids = row['voidCount'] as int? ?? 0;
              final gross = row['grossSalesCents'] as int? ?? 0;
              final refundTotal = row['refundCents'] as int? ?? 0;
              final voidTotal = row['voidedCents'] as int? ?? 0;
              final net = row['netSalesCents'] as int? ?? 0;
              return ListTile(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: compact ? 4 : 8,
                ),
                title: Text(date),
                subtitle: Text(
                  '$sales sales | ${_formatMoney(gross)} gross\n'
                  '$refunds refunds (${_formatMoney(refundTotal)}) | '
                  '$voids voids (${_formatMoney(voidTotal)})',
                  maxLines: 2,
                ),
                trailing: Text(
                  _formatMoney(net),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              );
            }),
          const SizedBox(height: 20),
          _reportSectionTitle('Top items'),
          const SizedBox(height: 6),
          if (topProducts.isEmpty)
            const _ReportEmptyRow(message: 'No items sold in this date range.')
          else ...[
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                'Item totals are before refunds and voids.',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ),
            ...topProducts.map(
              (row) => ListTile(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: compact ? 4 : 8,
                ),
                title: Text(row['name'] as String? ?? 'Item'),
                subtitle: Text('${row['quantity'] ?? 0} units sold'),
                trailing: Text(
                  _formatMoney(row['grossCents'] as int? ?? 0),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          _reportSectionTitle('Cash drawer shifts'),
          const SizedBox(height: 6),
          if (shifts.isEmpty)
            const _ReportEmptyRow(
              message: 'No shifts opened or closed in this date range.',
            )
          else ...[
            if (report['shiftsTruncated'] == true)
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'Showing the latest 500 shifts in this range.',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
              ),
            ...shifts.map((row) {
              final closedAt = row['closedAt'] as String?;
              final variance = row['varianceCents'] as int?;
              final openedAt = row['openedAt'] as String? ?? '';
              final openingFloat = row['openingFloatCents'] as int? ?? 0;
              final expectedCash = row['expectedCashCents'] as int? ?? 0;
              final countedCash = row['countedCashCents'] as int?;
              final timestamp = openedAt.length >= 16
                  ? openedAt.substring(0, 16).replaceFirst('T', ' ')
                  : openedAt;
              return ListTile(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: compact ? 4 : 8,
                ),
                leading: Icon(
                  closedAt == null
                      ? Icons.lock_open_outlined
                      : Icons.point_of_sale_outlined,
                  color: closedAt == null ? _muted : _leaf,
                ),
                title: Text(
                  '${row['registerId'] ?? 'Register'} | ${row['id']}',
                ),
                subtitle: Text(
                  '$timestamp UTC | ${row['salesCount'] ?? 0} sales'
                  '${closedAt == null ? ' | Open' : ' | Closed'}\n'
                  'Float ${_formatMoney(openingFloat)} | '
                  'Expected ${_formatMoney(expectedCash)} | '
                  'Counted ${countedCash == null ? 'Not counted' : _formatMoney(countedCash)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: variance == null
                    ? const Text('Open')
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'Variance',
                            style: TextStyle(fontSize: 11, color: _muted),
                          ),
                          Text(
                            _formatMoney(variance),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: variance == 0
                                  ? _ink
                                  : Colors.deepOrange.shade700,
                            ),
                          ),
                        ],
                      ),
              );
            }),
          ],
        ],
      ),
    );
  }

  List<Map<String, Object?>> _reportRows(String field) {
    final raw = _report?[field];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => row.map((key, value) => MapEntry(key.toString(), value)))
        .toList(growable: false);
  }

  Widget _reportMetric(String label, String value, {String? detail}) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F8F5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 5),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _ink,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 3),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
            ],
          ],
        ),
      );

  Widget _reportSectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Text(
      title,
      style: const TextStyle(
        color: _ink,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _saleTile(Map<String, Object?> raw) {
    final sale = Sale.fromJson(raw);
    final isVoided = raw['voidedAt'] != null;
    final returns = raw['returns'] as List<Object?>? ?? const [];
    final returnedByProduct = raw['returnQuantities'] is Map
        ? (raw['returnQuantities'] as Map).map(
            (key, value) => MapEntry(key.toString(), value as int),
          )
        : <String, int>{};
    final returnedByLine = raw['returnQuantitiesByLine'] is Map
        ? (raw['returnQuantitiesByLine'] as Map).map(
            (key, value) => MapEntry(int.parse(key.toString()), value as int),
          )
        : <int, int>{};
    if (returnedByLine.isEmpty) {
      final remainingByProduct = Map<String, int>.from(returnedByProduct);
      for (final entry in sale.lines.indexed) {
        final quantity = (remainingByProduct[entry.$2.productId] ?? 0).clamp(
          0,
          entry.$2.quantity,
        );
        returnedByLine[entry.$1] = quantity;
        remainingByProduct[entry.$2.productId] =
            (remainingByProduct[entry.$2.productId] ?? 0) - quantity;
      }
    }
    final status = isVoided
        ? 'VOIDED'
        : returns.isEmpty
        ? ''
        : '${returns.length} RETURN${returns.length == 1 ? '' : 'S'}';
    return ExpansionTile(
      leading: CircleAvatar(
        backgroundColor: isVoided
            ? const Color(0xFFFCE7E5)
            : const Color(0xFFE4EFEA),
        child: Icon(
          isVoided ? Icons.block_rounded : Icons.receipt_long_outlined,
          color: isVoided ? Colors.red : _leaf,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              _formatMoney(sale.totalCents),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (status.isNotEmpty)
            Text(
              status,
              style: TextStyle(
                color: isVoided ? Colors.red : _muted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
      subtitle: Text(
        '${sale.createdAt.toLocal()} · ${sale.lines.length} products · ${sale.id}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      children: [
        ...sale.lines.indexed.map(
          (entry) => ListTile(
            dense: true,
            title: Text(_saleLineName(entry.$2)),
            subtitle: Text(
              '${entry.$2.quantity} x ${_formatMoney(entry.$2.unitTotalCents)}${returnedByLine[entry.$1] == null ? '' : ' | ${returnedByLine[entry.$1]} returned'}',
            ),
            trailing: Text(_formatMoney(entry.$2.totalCents)),
          ),
        ),
        if (isVoided && raw['voidReason'] is String)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Void reason: ${raw['voidReason']}',
              style: const TextStyle(color: _muted),
            ),
          ),
        if (returns.isNotEmpty)
          ...returns.map((item) {
            final row = item! as Map;
            return Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  'Refund ${_formatMoney(row['refundCents'] as int)} · ${row['reason']}',
                  style: const TextStyle(color: _muted),
                ),
              ),
            );
          }),
        if (widget.canManage && !isVoided)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _return(sale, returnedByLine),
                  icon: const Icon(Icons.keyboard_return_rounded),
                  label: const Text('Return items'),
                ),
                if (returns.isEmpty)
                  TextButton.icon(
                    onPressed: () => _void(sale.id),
                    icon: const Icon(Icons.block_rounded),
                    label: const Text('Void sale'),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _return(Sale sale, Map<int, int> returned) async {
    final draft = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => _ReturnSaleDialog(sale: sale, returned: returned),
    );
    if (draft == null) return;
    try {
      final refund = await widget.api.returnSale(
        id: const Uuid().v4(),
        saleId: sale.id,
        reason: draft['reason']! as String,
        lines: draft['lines']! as List<Map<String, Object?>>,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Return saved · refund ${_formatMoney(refund)}'),
          ),
        );
      }
      await _refresh();
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is HubApiException
                  ? error.message
                  : 'Could not save return.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _void(String saleId) async {
    try {
      final value = await showDialog<String>(
        context: context,
        builder: (_) => const _VoidSaleDialog(),
      );
      if (value == null || value.isEmpty) return;
      await widget.api.voidSale(saleId: saleId, reason: value);
      await _refresh();
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is HubApiException ? error.message : 'Could not void sale.',
            ),
          ),
        );
      }
    }
  }
}

class _ReportEmptyRow extends StatelessWidget {
  const _ReportEmptyRow({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF5F8F5),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _line),
    ),
    child: Text(message, style: const TextStyle(color: _muted)),
  );
}

class _CustomerDraftDialog extends StatefulWidget {
  const _CustomerDraftDialog();

  @override
  State<_CustomerDraftDialog> createState() => _CustomerDraftDialogState();
}

class _CustomerDraftDialogState extends State<_CustomerDraftDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New customer'),
    content: SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone (optional)'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email (optional)'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, [
          _name.text.trim(),
          _phone.text.trim(),
          _email.text.trim(),
        ]),
        child: const Text('Save customer'),
      ),
    ],
  );
}

class _DiscountDialog extends StatefulWidget {
  const _DiscountDialog({
    required this.initialAmount,
    required this.initialReason,
    required this.maximumCents,
  });

  final int initialAmount;
  final String initialReason;
  final int maximumCents;

  @override
  State<_DiscountDialog> createState() => _DiscountDialogState();
}

class _DiscountDialogState extends State<_DiscountDialog> {
  late final TextEditingController _amount = TextEditingController(
    text: _formatCents(widget.initialAmount),
  );
  late final TextEditingController _reason = TextEditingController(
    text: widget.initialReason,
  );

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Sale discount'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount',
              prefixText: 'PHP ',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(labelText: 'Reason'),
          ),
          const SizedBox(height: 8),
          Text(
            'Maximum ${_formatMoney(widget.maximumCents)}',
            style: const TextStyle(color: _muted),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, [_amount.text, _reason.text]),
        child: const Text('Apply discount'),
      ),
    ],
  );
}

class _TaxSettingsDialog extends StatefulWidget {
  const _TaxSettingsDialog({required this.initial});

  final TaxConfig initial;

  @override
  State<_TaxSettingsDialog> createState() => _TaxSettingsDialogState();
}

class _TaxSettingsDialogState extends State<_TaxSettingsDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial.name,
  );
  late final TextEditingController _rate = TextEditingController(
    text: (widget.initial.rateBasisPoints / 100).toStringAsFixed(2),
  );
  late bool _included = widget.initial.pricesIncludeTax;

  @override
  void dispose() {
    _name.dispose();
    _rate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Tax settings'),
    content: SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Tax label'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _rate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Tax rate',
              suffixText: '%',
            ),
          ),
          SwitchListTile(
            value: _included,
            onChanged: (value) => setState(() => _included = value),
            title: const Text('Prices include tax'),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Save tax')),
    ],
  );

  void _submit() {
    final percent = double.tryParse(_rate.text.trim());
    final name = _name.text.trim();
    if (percent == null || percent < 0 || percent > 100 || name.isEmpty) {
      return;
    }
    Navigator.pop(
      context,
      TaxConfig(
        name: name,
        rateBasisPoints: (percent * 100).round(),
        pricesIncludeTax: _included,
      ),
    );
  }
}

class _LoyaltySettingsDialog extends StatefulWidget {
  const _LoyaltySettingsDialog({required this.initial});

  final LoyaltyConfig initial;

  @override
  State<_LoyaltySettingsDialog> createState() => _LoyaltySettingsDialogState();
}

class _LoyaltySettingsDialogState extends State<_LoyaltySettingsDialog> {
  late final TextEditingController _earn = TextEditingController(
    text: '${widget.initial.earnPointsPer100Cents}',
  );
  late final TextEditingController _redeem = TextEditingController(
    text: '${widget.initial.redeemCentsPerPoint}',
  );

  @override
  void dispose() {
    _earn.dispose();
    _redeem.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Loyalty program'),
    content: SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _earn,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Points earned per PHP 1 spent',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _redeem,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Discount cents per point',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Points accrue on the discounted pre-tax subtotal.',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Save program')),
    ],
  );

  void _submit() {
    final earned = int.tryParse(_earn.text.trim());
    final value = int.tryParse(_redeem.text.trim());
    if (earned == null ||
        value == null ||
        earned < 0 ||
        earned > 1000 ||
        value < 1 ||
        value > 100000) {
      return;
    }
    Navigator.pop(
      context,
      LoyaltyConfig(earnPointsPer100Cents: earned, redeemCentsPerPoint: value),
    );
  }
}

class _VoidSaleDialog extends StatefulWidget {
  const _VoidSaleDialog();

  @override
  State<_VoidSaleDialog> createState() => _VoidSaleDialogState();
}

class _VoidSaleDialogState extends State<_VoidSaleDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Void sale'),
    content: TextField(
      controller: _reason,
      autofocus: true,
      maxLength: 240,
      decoration: const InputDecoration(labelText: 'Reason for void'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _reason.text.trim()),
        child: const Text('Void sale'),
      ),
    ],
  );
}

class _ReturnSaleDialog extends StatefulWidget {
  const _ReturnSaleDialog({required this.sale, required this.returned});
  final Sale sale;
  final Map<int, int> returned;

  @override
  State<_ReturnSaleDialog> createState() => _ReturnSaleDialogState();
}

class _ReturnSaleDialogState extends State<_ReturnSaleDialog> {
  late final TextEditingController _reason = TextEditingController();
  late final Map<int, TextEditingController> _quantities = {
    for (final entry in widget.sale.lines.indexed)
      entry.$1: TextEditingController(text: '0'),
  };
  final Set<int> _restock = {};

  @override
  void initState() {
    super.initState();
    _restock.addAll(widget.sale.lines.indexed.map((entry) => entry.$1));
  }

  @override
  void dispose() {
    _reason.dispose();
    for (final controller in _quantities.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Return items'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ...widget.sale.lines.indexed.map((entry) {
              final line = entry.$2;
              final lineIndex = entry.$1;
              final remaining =
                  line.quantity - (widget.returned[lineIndex] ?? 0);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _saleLineName(line),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '$remaining remaining of ${line.quantity} | ${_formatMoney(line.unitTotalCents)} each',
                            style: const TextStyle(color: _muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 82,
                      child: TextField(
                        controller: _quantities[lineIndex],
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Qty',
                          helperText: remaining == 0
                              ? 'Returned'
                              : 'max $remaining',
                        ),
                      ),
                    ),
                    Checkbox(
                      value: _restock.contains(lineIndex),
                      onChanged: remaining == 0
                          ? null
                          : (value) => setState(() {
                              if (value == true) {
                                _restock.add(lineIndex);
                              } else {
                                _restock.remove(lineIndex);
                              }
                            }),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 10),
            TextField(
              controller: _reason,
              maxLength: 240,
              decoration: const InputDecoration(labelText: 'Return reason'),
            ),
            const Text(
              'Checked items will be returned to Main stock.',
              style: TextStyle(color: _muted, fontSize: 12),
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
      FilledButton(onPressed: _submit, child: const Text('Save return')),
    ],
  );

  void _submit() {
    final reason = _reason.text.trim();
    if (reason.isEmpty) return;
    final lines = <Map<String, Object?>>[];
    for (final entry in widget.sale.lines.indexed) {
      final line = entry.$2;
      final lineIndex = entry.$1;
      final quantity = int.tryParse(_quantities[lineIndex]!.text.trim()) ?? 0;
      final remaining = line.quantity - (widget.returned[lineIndex] ?? 0);
      if (quantity < 0 || quantity > remaining) return;
      if (quantity > 0) {
        lines.add({
          'productId': line.productId,
          'lineIndex': lineIndex,
          'quantity': quantity,
          'restock': _restock.contains(lineIndex),
        });
      }
    }
    if (lines.isNotEmpty) {
      Navigator.pop(context, {'reason': reason, 'lines': lines});
    }
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.product,
    required this.quantity,
    required this.onTap,
  });

  final Product product;
  final int quantity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = _productTint(product.category);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            border: Border.all(color: quantity > 0 ? _leaf : _line),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.11),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      _productIcon(product.category),
                      color: tint,
                      size: 20,
                    ),
                  ),
                  const Spacer(),
                  if (quantity > 0)
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: _leaf,
                      child: Text(
                        '$quantity',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatMoney(product.unitPriceCents),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _leaf,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartItem {
  const _CartItem({
    required this.product,
    required this.quantity,
    this.modifiers = const [],
  });

  final Product product;
  final int quantity;
  final List<SelectedModifier> modifiers;

  int get unitTotalCents =>
      product.unitPriceCents +
      modifiers.fold(0, (sum, modifier) => sum + modifier.priceDeltaCents);

  String get key => _cartKey(product, modifiers);
}

class _CartLine extends StatelessWidget {
  const _CartLine({
    required this.item,
    required this.onDecrease,
    required this.onIncrease,
  });

  final _CartItem item;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    final lineTotal = item.unitTotalCents * item.quantity;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (item.modifiers.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    item.modifiers.map((modifier) => modifier.name).join(', '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  _formatMoney(lineTotal),
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove one ${item.product.name}',
            onPressed: onDecrease,
            icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
          ),
          Text(
            '${item.quantity}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          IconButton(
            tooltip: 'Add one ${item.product.name}',
            onPressed: onIncrease,
            icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

String _cartKey(Product product, List<SelectedModifier> modifiers) {
  if (modifiers.isEmpty) return product.id;
  final selections =
      modifiers
          .map((modifier) => '${modifier.groupId}:${modifier.optionId}')
          .toList()
        ..sort();
  return '${product.id}|${selections.join('|')}';
}

class _ModifierSelectionDialog extends StatefulWidget {
  const _ModifierSelectionDialog({required this.product});

  final Product product;

  @override
  State<_ModifierSelectionDialog> createState() =>
      _ModifierSelectionDialogState();
}

class _ModifierSelectionDialogState extends State<_ModifierSelectionDialog> {
  final Map<String, Set<String>> _selected = {};

  bool get _valid => widget.product.modifierGroups.every((group) {
    final count = _selected[group.id]?.length ?? 0;
    return count >= group.minimumSelections && count <= group.maximumSelections;
  });

  void _toggle(ModifierGroup group, ModifierOption option, bool checked) {
    setState(() {
      final values = Set<String>.of(_selected[group.id] ?? const {});
      if (group.maximumSelections == 1) {
        values
          ..clear()
          ..addAll(checked ? [option.id] : const []);
      } else if (checked) {
        values.add(option.id);
      } else {
        values.remove(option.id);
      }
      _selected[group.id] = values;
    });
  }

  List<SelectedModifier> _result() => [
    for (final group in widget.product.modifierGroups)
      for (final option in group.options)
        if (_selected[group.id]?.contains(option.id) ?? false)
          SelectedModifier(
            groupId: group.id,
            groupName: group.name,
            optionId: option.id,
            name: option.name,
            priceDeltaCents: option.priceDeltaCents,
          ),
  ];

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Choose ${widget.product.name} options'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final group in widget.product.modifierGroups) ...[
              const SizedBox(height: 8),
              Text(
                '${group.name} · choose ${group.minimumSelections}–${group.maximumSelections}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final option in group.options)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _selected[group.id]?.contains(option.id) ?? false,
                  title: Text(option.name),
                  secondary: option.priceDeltaCents == 0
                      ? null
                      : Text(_formatMoney(option.priceDeltaCents)),
                  onChanged:
                      (_selected[group.id]?.length ?? 0) >=
                              group.maximumSelections &&
                          !(_selected[group.id]?.contains(option.id) ?? false)
                      ? null
                      : (value) => _toggle(group, option, value ?? false),
                ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _valid ? () => Navigator.pop(context, _result()) : null,
        child: const Text('Add to sale'),
      ),
    ],
  );
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.label,
    required this.cents,
    this.prominent = false,
  });

  final String label;
  final int cents;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: prominent ? _ink : _muted,
      fontSize: prominent ? 18 : 13,
      fontWeight: prominent ? FontWeight.w700 : FontWeight.w500,
    );
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            _formatMoney(cents),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: style,
          ),
        ),
      ],
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.shopping_bag_outlined, color: Color(0xFF9AA8A2), size: 34),
        SizedBox(height: 10),
        Text('Add products to start a sale', style: TextStyle(color: _muted)),
      ],
    ),
  );
}

const productCategories = ['All items', 'Coffee', 'Bakery', 'Meals', 'Drinks'];

const demoProducts = <Product>[
  Product(
    id: 'latte',
    name: 'Iced latte',
    category: 'Coffee',
    unitPriceCents: 14500,
    sku: 'COF-001',
  ),
  Product(
    id: 'americano',
    name: 'Americano',
    category: 'Coffee',
    unitPriceCents: 11000,
    sku: 'COF-002',
  ),
  Product(
    id: 'cappuccino',
    name: 'Cappuccino',
    category: 'Coffee',
    unitPriceCents: 13500,
    sku: 'COF-003',
  ),
  Product(
    id: 'matcha',
    name: 'Matcha latte',
    category: 'Drinks',
    unitPriceCents: 15500,
    sku: 'DRK-001',
  ),
  Product(
    id: 'pandesal',
    name: 'Pan de sal',
    category: 'Bakery',
    unitPriceCents: 1500,
    sku: 'BAK-001',
  ),
  Product(
    id: 'ensaymada',
    name: 'Ensaymada',
    category: 'Bakery',
    unitPriceCents: 6500,
    sku: 'BAK-002',
  ),
  Product(
    id: 'croissant',
    name: 'Butter croissant',
    category: 'Bakery',
    unitPriceCents: 8500,
    sku: 'BAK-003',
  ),
  Product(
    id: 'silog',
    name: 'Longsilog',
    category: 'Meals',
    unitPriceCents: 17500,
    sku: 'MEA-001',
  ),
  Product(
    id: 'tapsilog',
    name: 'Tapsilog',
    category: 'Meals',
    unitPriceCents: 19500,
    sku: 'MEA-002',
  ),
  Product(
    id: 'lemonade',
    name: 'Calamansi juice',
    category: 'Drinks',
    unitPriceCents: 7500,
    sku: 'DRK-002',
  ),
  Product(
    id: 'water',
    name: 'Bottled water',
    category: 'Drinks',
    unitPriceCents: 3500,
    sku: 'DRK-003',
  ),
  Product(
    id: 'cookies',
    name: 'Chocolate cookies',
    category: 'Bakery',
    unitPriceCents: 5500,
    sku: 'BAK-004',
  ),
];

Color _productTint(String category) => switch (category) {
  'Coffee' => const Color(0xFF845B36),
  'Bakery' => const Color(0xFFC17C33),
  'Meals' => const Color(0xFFB44D3E),
  _ => const Color(0xFF3B7C86),
};

IconData _productIcon(String category) => switch (category) {
  'Coffee' => Icons.coffee_rounded,
  'Bakery' => Icons.bakery_dining_rounded,
  'Meals' => Icons.ramen_dining_rounded,
  _ => Icons.local_drink_rounded,
};

pw.Widget _pdfRow(String label, int cents, {bool bold = false}) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 2),
  child: pw.Row(
    children: [
      pw.Expanded(
        child: pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ),
      pw.Text(
        '${cents < 0 ? '-' : ''}${_formatCents(cents.abs())}',
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    ],
  ),
);

int _parseCents(String input) {
  final parts = input.trim().split('.');
  if (parts.length > 2 || parts.isEmpty || parts.first.isEmpty) return 0;
  if (!RegExp(r'^\d+$').hasMatch(parts.first)) return 0;
  final fraction = parts.length == 1 ? '' : parts[1];
  if (fraction.isNotEmpty && !RegExp(r'^\d{1,2}$').hasMatch(fraction)) return 0;
  final whole = int.tryParse(parts.first);
  final centavos = int.tryParse(fraction.padRight(2, '0')) ?? 0;
  if (whole == null || whole > 90071992547409) return 0;
  return whole * 100 + centavos;
}

String _formatCents(int cents) {
  final sign = cents < 0 ? '-' : '';
  final absolute = cents.abs();
  return '$sign${absolute ~/ 100}.${(absolute % 100).toString().padLeft(2, '0')}';
}

String _formatMoney(int cents) => 'PHP ${_formatCents(cents)}';

String _saleLineName(SaleLine line) => line.modifiers.isEmpty
    ? line.name
    : '${line.name} (${line.modifiers.map((modifier) => modifier.name).join(', ')})';
