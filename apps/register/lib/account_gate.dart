// Flutter's current SDK still ships Material widgets from this library.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:open_pos/data/sale_sync_client.dart';
import 'package:pos_domain/pos_domain.dart';

const _leaf = Color(0xFF0D7468);
const _ink = Color(0xFF173432);
const _muted = Color(0xFF73827D);

class AccountGate extends StatefulWidget {
  const AccountGate({
    super.key,
    required this.needsSetup,
    required this.api,
    required this.onAuthenticated,
    this.statusMessage,
  });

  final bool needsSetup;
  final SaleSyncClient api;
  final Future<void> Function(HubSession session) onAuthenticated;
  final String? statusMessage;

  @override
  State<AccountGate> createState() => _AccountGateState();
}

class _AccountGateState extends State<AccountGate> {
  final _formKey = GlobalKey<FormState>();
  final _storeName = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _showSetup = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _showSetup = widget.needsSetup;
  }

  @override
  void dispose() {
    _storeName.dispose();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final session = _showSetup
          ? await widget.api.setupStore(
              storeName: _storeName.text.trim(),
              name: _name.text.trim(),
              email: _email.text.trim(),
              password: _password.text,
            )
          : await widget.api.signIn(
              email: _email.text.trim(),
              password: _password.text,
            );
      await widget.onAuthenticated(session);
    } on HubApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception {
      if (mounted) {
        setState(
          () => _error =
              'Could not connect to the hub. Check the address and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 560;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(isCompact ? 20 : 36),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: Color(0xFFE3E8E3)),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Padding(
                  padding: EdgeInsets.all(isCompact ? 24 : 36),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: _leaf,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.storefront_rounded,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Open POS',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: _ink,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 30),
                        Text(
                          _showSetup ? 'Set up your store' : 'Welcome back',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _showSetup
                              ? 'Create the store and administrator account for this deployment.'
                              : 'Sign in to continue to the register.',
                          style: const TextStyle(color: _muted, height: 1.45),
                        ),
                        if (widget.statusMessage != null) ...[
                          const SizedBox(height: 18),
                          _MessageBox(widget.statusMessage!, warning: true),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          _MessageBox(_error!, warning: true),
                        ],
                        if (_showSetup) ...[
                          const SizedBox(height: 22),
                          _field(
                            controller: _storeName,
                            label: 'Store name',
                            icon: Icons.store_mall_directory_outlined,
                            validator: (value) =>
                                _required(value, 'Enter a store name.'),
                          ),
                          const SizedBox(height: 14),
                          _field(
                            controller: _name,
                            label: 'Administrator name',
                            icon: Icons.person_outline_rounded,
                            validator: (value) =>
                                _required(value, 'Enter your name.'),
                          ),
                        ] else
                          const SizedBox(height: 22),
                        _field(
                          controller: _email,
                          label: 'Email address',
                          icon: Icons.alternate_email_rounded,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [
                            AutofillHints.username,
                            AutofillHints.email,
                          ],
                          validator: (value) {
                            final text = value?.trim() ?? '';
                            return RegExp(
                                  r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                ).hasMatch(text)
                                ? null
                                : 'Enter a valid email address.';
                          },
                        ),
                        const SizedBox(height: 14),
                        _field(
                          controller: _password,
                          label: 'Password',
                          icon: Icons.lock_outline_rounded,
                          obscureText: true,
                          autofillHints: _showSetup
                              ? const [AutofillHints.newPassword]
                              : const [AutofillHints.password],
                          validator: (value) {
                            if (!_showSetup && (value?.isNotEmpty ?? false)) {
                              return null;
                            }
                            return (value?.length ?? 0) >= 12
                                ? null
                                : 'Use at least 12 characters.';
                          },
                          onSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: 22),
                        FilledButton(
                          onPressed: _submitting ? null : _submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: _leaf,
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _submitting
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(_showSetup ? 'Create store' : 'Sign in'),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _submitting
                              ? null
                              : () => setState(() {
                                  _showSetup = !_showSetup;
                                  _error = null;
                                }),
                          child: Text(
                            _showSetup
                                ? 'Already set up? Sign in'
                                : 'First time here? Set up this store',
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Each self-hosted hub manages one store deployment.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    Iterable<String>? autofillHints,
    bool obscureText = false,
    ValueChanged<String>? onSubmitted,
  }) => TextFormField(
    controller: controller,
    decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
    keyboardType: keyboardType,
    textCapitalization: textCapitalization,
    autofillHints: autofillHints,
    obscureText: obscureText,
    validator: validator,
    onFieldSubmitted: onSubmitted,
  );

  String? _required(String? value, String message) =>
      (value?.trim().isNotEmpty ?? false) ? null : message;
}

class HubUnavailablePage extends StatelessWidget {
  const HubUnavailablePage({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, color: _leaf, size: 48),
                const SizedBox(height: 18),
                Text(
                  'Hub is unavailable',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Connect to your Open POS hub to sign in or finish initial store setup.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted, height: 1.5),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _MessageBox extends StatelessWidget {
  const _MessageBox(this.message, {required this.warning});

  final String message;
  final bool warning;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: warning ? const Color(0xFFFFF4E5) : const Color(0xFFEAF5EF),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(message, style: const TextStyle(color: _ink, height: 1.35)),
  );
}
