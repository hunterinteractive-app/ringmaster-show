import 'package:flutter/material.dart';

import '../services/square_checkout_service.dart';
import '../widgets/ringmaster_page_shell.dart';
import 'cart_screen.dart';
import 'my_entries_screen.dart';

class SquarePaymentReturnScreen extends StatefulWidget {
  const SquarePaymentReturnScreen({super.key, required this.uri});

  final Uri uri;

  @override
  State<SquarePaymentReturnScreen> createState() =>
      _SquarePaymentReturnScreenState();
}

class _SquarePaymentReturnScreenState extends State<SquarePaymentReturnScreen> {
  bool _loading = true;
  bool _navigating = false;
  String? _error;
  SquarePaymentAttemptStatus? _status;

  String get _cartId => (widget.uri.queryParameters['cart_id'] ?? '').trim();
  String get _paymentSessionId =>
      (widget.uri.queryParameters['payment_session_id'] ?? '').trim();

  @override
  void initState() {
    super.initState();
    _poll();
  }

  Future<void> _poll() async {
    if (_cartId.isEmpty || _paymentSessionId.isEmpty) {
      setState(() {
        _loading = false;
        _error =
            'This Square return link is missing its RingMaster payment reference.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      SquarePaymentAttemptStatus? latest;
      for (var attempt = 0; attempt < 8; attempt++) {
        latest = await SquareCheckoutService.loadAttemptStatus(
          cartId: _cartId,
          paymentSessionId: _paymentSessionId,
          reconcileIfPending: attempt >= 3,
        );
        if (!latest.pending) break;
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!mounted) return;
      }
      if (!mounted) return;
      setState(() {
        _status = latest;
        _loading = false;
      });
      if (latest?.finalized == true) {
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
        setState(() => _navigating = true);
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MyEntriesScreen()),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to confirm the Square payment: $error';
      });
    }
  }

  void _returnToCart() {
    final status = _status;
    if (status == null) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CartScreen(
          cartId: _cartId,
          showId: status.showId,
          showName: status.showName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final finalized = status?.finalized == true;
    final terminal = status?.terminal == true;
    return RingMasterPageShell(
      title: 'Square Payment',
      subtitle: finalized
          ? 'Payment confirmed'
          : 'Confirming your Square payment…',
      showBackButton: false,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_loading || _navigating) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 18),
                    Text(
                      _navigating
                          ? 'Payment confirmed. Opening your submitted entries…'
                          : 'Confirming your Square payment…',
                      textAlign: TextAlign.center,
                    ),
                  ] else if (finalized) ...[
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 52,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Payment confirmed. Your entries were submitted successfully.',
                      textAlign: TextAlign.center,
                    ),
                  ] else if (terminal) ...[
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 52,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      status?.failureMessage ??
                          'This Square payment was not completed. Your cart remains available.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _returnToCart,
                      child: const Text('Return to Cart'),
                    ),
                  ] else if (_error != null) ...[
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 52,
                    ),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: _poll,
                      child: const Text('Refresh Status'),
                    ),
                  ] else ...[
                    const Icon(Icons.schedule, color: Colors.orange, size: 52),
                    const SizedBox(height: 12),
                    const Text(
                      'Square is still processing this payment. Do not start another checkout.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _poll,
                      child: const Text('Refresh Status'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
