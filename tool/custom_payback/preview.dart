// Local review harness. Uses the actual editor; saves stay in memory.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/admin/payback_settings_dialog.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final schedules = <String?, List<dynamic>>{
    'open': [
      for (final (n, p, c) in [
        (2, 1, 200),
        (3, 1, 400),
        (3, 2, 200),
        (4, 1, 400),
        (4, 2, 200),
      ])
        {
          'applies_to_species': 'rabbit',
          'min_shown': n,
          'max_shown': n,
          'placement': p,
          'amount_cents': c,
        },
    ],
  };
  final specials = <String?, List<dynamic>>{};
  await Supabase.initialize(
    url: 'http://local-preview.invalid',
    anonKey: 'preview-only',
    authOptions: const FlutterAuthClientOptions(
      autoRefreshToken: false,
      detectSessionInUri: false,
      localStorage: EmptyLocalStorage(),
    ),
    httpClient: MockClient((request) async {
      final rpc = request.url.path.split('/').last;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      Object? result;
      switch (rpc) {
        case 'can_configure_best_opposite_final_award':
          result = true;
        case 'get_show_payback_setup':
          result = {
            'sections': [
              {'id': 'open', 'kind': 'open', 'letter': 'A', 'label': 'Open A'},
              {
                'id': 'youth',
                'kind': 'youth',
                'letter': 'A',
                'label': 'Youth A',
              },
            ],
            'schedules': [
              for (final e in schedules.entries)
                {'section_id': e.key, 'rows': e.value},
            ],
            'special_money_rules': specials.values.expand((r) => r).toList(),
          };
        case 'save_show_custom_payback_schedule':
          schedules[body['p_section_id']] = body['p_rows'];
          result = 'preview-schedule';
        case 'save_show_special_money_rules':
          specials[body['p_section_id']] = [
            for (final r in body['p_rules'])
              {...r, 'section_id': body['p_section_id']},
          ];
        case 'copy_show_payback_settings':
          schedules[body['p_to_section_id']] = jsonDecode(
            jsonEncode(schedules[body['p_from_section_id']] ?? []),
          );
          specials[body['p_to_section_id']] = [
            for (final r in specials[body['p_from_section_id']] ?? [])
              {...r, 'section_id': body['p_to_section_id']},
          ];
        default:
          throw StateError('Unsupported preview request: $rpc');
      }
      return http.Response(
        jsonEncode(result),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  runApp(MaterialApp(theme: AppTheme.lightTheme, home: const _Preview()));
}

class _Preview extends StatelessWidget {
  const _Preview();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('LOCAL PREVIEW — Houston premiums')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Starts with Kyle’s five saved Open Rabbit payout rows. Save only changes this preview. Refresh resets it. Production is not connected.',
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const PaybackSettingsDialog(showId: 'preview'),
              ),
              child: const Text('Review Payback Settings'),
            ),
          ],
        ),
      ),
    ),
  );
}
