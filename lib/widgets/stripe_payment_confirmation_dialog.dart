import 'package:flutter/material.dart';
import '../services/stripe_connect_service.dart';

Future<bool> showStripePaymentConfirmation(
  BuildContext context, {
  String? checkoutSessionId,
  String? cartId,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StripePaymentConfirmationDialog(
        loadStatus: () => StripeConnectService.registrationStatus(
          checkoutSessionId: checkoutSessionId,
          cartId: cartId,
        ),
      ),
    ) ??
    false;

class StripePaymentConfirmationDialog extends StatefulWidget {
  const StripePaymentConfirmationDialog({
    super.key,
    required this.loadStatus,
    this.pollInterval = const Duration(seconds: 1),
    this.maxAttempts = 20,
  });
  final Future<Map<String, dynamic>> Function() loadStatus;
  final Duration pollInterval;
  final int maxAttempts;
  @override
  State<StripePaymentConfirmationDialog> createState() =>
      _StripePaymentConfirmationDialogState();
}

class _StripePaymentConfirmationDialogState
    extends State<StripePaymentConfirmationDialog> {
  bool _checking = true;
  bool _completed = false;
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      for (var attempt = 0; attempt < widget.maxAttempts; attempt++) {
        final status = await widget.loadStatus();
        if (!mounted) return;
        if (status['completed'] == true) {
          setState(() {
            _completed = true;
            _checking = false;
          });
          return;
        }
        if (attempt + 1 < widget.maxAttempts) {
          await Future<void>.delayed(widget.pollInterval);
          if (!mounted) return;
        }
      }
    } catch (_) {
      // An unavailable status response is not proof that a payment failed.
    }
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      _completed
          ? 'Payment confirmed'
          : _checking
          ? 'Confirming registration'
          : 'Confirmation pending',
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_checking)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: CircularProgressIndicator(),
          ),
        Text(
          _completed
              ? 'Your payment is confirmed and your entries have been submitted.'
              : 'We are checking your payment and entries. Please confirm their status before starting another checkout.',
        ),
      ],
    ),
    actions: [
      if (!_checking && !_completed)
        TextButton(onPressed: _check, child: const Text('Check again')),
      TextButton(
        onPressed: () => Navigator.pop(context, _completed),
        child: Text(_completed ? 'View entries' : 'Close'),
      ),
    ],
  );
}
