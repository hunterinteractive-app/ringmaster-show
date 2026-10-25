// Local visual QA only. Never deploy this entry point. All settings use the
// loopback fixture server; purchases and location checks are disabled in preview.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/super_admin/convention_sale_admin_screen.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'http://127.0.0.1:58620',
    anonKey: 'local-preview-only',
  );
  runApp(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Column(
          children: [
            const Material(
              color: AppColors.gold,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.all(10),
                  child: Text(
                    'LOCAL PREVIEW • Settings are examples • Purchases disabled',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            const Expanded(child: ConventionSaleAdminScreen()),
          ],
        ),
      ),
    ),
  );
}
