import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/stripe_connect_service.dart';

/// Existing submissions stay registered while their outstanding fees are paid.
class SubmittedBalancePayment extends StatefulWidget {
  const SubmittedBalancePayment({
    super.key,
    required this.showId,
    this.loadBalances,
    this.startCheckout,
  });
  final String showId;
  final Future<List<Map<String, dynamic>>> Function()? loadBalances;
  final Future<String> Function(String cartId)? startCheckout;
  @override
  State<SubmittedBalancePayment> createState() =>
      _SubmittedBalancePaymentState();
}

class _SubmittedBalancePaymentState extends State<SubmittedBalancePayment> {
  List<Map<String, dynamic>> _balances = [];
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = widget.loadBalances != null
          ? await widget.loadBalances!()
          : await Supabase.instance.client.rpc(
              'list_my_submitted_balances',
              params: {'p_show_id': widget.showId},
            );
      if (!mounted) return;
      setState(() {
        _balances = List<Map<String, dynamic>>.from(rows as List);
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not check outstanding balances.');
      }
    }
  }

  Future<void> _pay(Map<String, dynamic> balance) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pay outstanding balance'),
        content: const Text(
          'Your entries will remain submitted. Stripe will show the current total, including any online payment fee, for you to review before paying. Do not enter your animals again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue to secure payment'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final url =
          await (widget.startCheckout ??
              StripeConnectService.createCheckoutSession)(
            balance['cart_id'].toString(),
          );
      if (!await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_self',
      )) {
        throw Exception('Unable to open the payment page. Please try again.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Payment could not start: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_error != null)
        Row(
          children: [
            Expanded(child: Text(_error!)),
            TextButton(
              onPressed: _busy ? null : _load,
              child: const Text('Refresh balances'),
            ),
          ],
        ),
      for (final balance in _balances)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${balance['exhibitors']} — ${(balance['currency'] ?? 'USD').toString().toUpperCase()} ${((balance['balance_due_cents'] as num) / 100).toStringAsFixed(2)} outstanding',
              ),
              FilledButton.icon(
                onPressed:
                    _busy ||
                        balance['review_required'] == true ||
                        balance['online_available'] != true
                    ? null
                    : () => _pay(balance),
                icon: const Icon(Icons.lock_outline),
                label: Text(
                  _busy ? 'Opening payment…' : 'Pay outstanding balance',
                ),
              ),
              if (balance['review_required'] == true)
                const Text(
                  'This submission has changes or prior payments. Please contact the show secretary to confirm the balance.',
                )
              else if (balance['online_available'] != true)
                const Text(
                  'Online payment is not available. Please contact the show secretary.',
                ),
            ],
          ),
        ),
    ],
  );
}
