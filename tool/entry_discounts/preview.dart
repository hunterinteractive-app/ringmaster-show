// Local-only review harness. Uses real discount widgets and cart/database APIs.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/cart_screen.dart';
import 'package:ringmaster_show/widgets/discounts/show_discount_codes.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  if (!{'127.0.0.1', 'localhost'}.contains(Uri.parse(url).host)) {
    throw StateError('The discount preview requires a local database.');
  }
  await Supabase.initialize(
    url: url,
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );
  await Supabase.instance.client.auth.signInWithPassword(
    email: const String.fromEnvironment('DISCOUNT_PREVIEW_EMAIL'),
    password: const String.fromEnvironment('DISCOUNT_PREVIEW_PASSWORD'),
  );
  runApp(MaterialApp(theme: AppTheme.lightTheme, home: const _Preview()));
}

class _Preview extends StatelessWidget {
  const _Preview();
  @override
  Widget build(BuildContext context) {
    const show = String.fromEnvironment('DISCOUNT_PREVIEW_SHOW');
    final carts =
        (jsonDecode(const String.fromEnvironment('DISCOUNT_PREVIEW_CARTS'))
                as List)
            .cast<Map<String, dynamic>>();
    return Scaffold(
      appBar: AppBar(title: const Text('LOCAL TEST — Entry discounts')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Synthetic exhibitors only. No real payments or emails. Nothing deployed.',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  r'MEMBER20 gives $20 off entry fees across the show. PERENTRY gives $3 off each entry. Codes apply per exhibitor. Try both: only the best total savings wins.',
                ),
                const SizedBox(height: 16),
                for (final cart in carts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: OutlinedButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CartScreen(
                            cartId: cart['id'],
                            showId: show,
                            showName: 'Local Discount Test Show',
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(cart['label']),
                      ),
                    ),
                  ),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: ShowDiscountCodes(showId: show),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
