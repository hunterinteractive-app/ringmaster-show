// Local review fixture: all writes are in memory; no live services or messages.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/admin/show_finances_screen.dart';
import 'package:ringmaster_show/services/show_finances_service.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://finance-fixture.invalid',
    anonKey: 'test',
    authOptions: const FlutterAuthClientOptions(
      autoRefreshToken: false,
      detectSessionInUri: false,
      localStorage: EmptyLocalStorage(),
    ),
    httpClient: MockClient(
      (request) async =>
          http.Response('{"message":"Preview uses sample data only"}', 501),
    ),
  );
  runApp(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Column(
        children: [
          const Material(
            color: Colors.amber,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'LOCAL DEMO — sample balances only. No charges or emails. Reload to reset. PDF export is tested separately.',
                ),
              ),
            ),
          ),
          Expanded(
            child: ShowFinancesScreen(
              showId: 'demo',
              gateway: PreviewFinance(),
            ),
          ),
        ],
      ),
    ),
  );
}

class PreviewFinance extends ShowFinanceGateway {
  bool failLoad = false, failHistory = false, failSave = false;
  int loads = 0;
  final saved = <Map<String, dynamic>>[];
  final rows = <Map<String, dynamic>>[
    {
      'exhibitor_id': 'one',
      'name': 'Ada Miller',
      'first_name': 'Ada',
      'last_name': 'Miller',
      'currency': 'usd',
      'charges_cents': 1000,
      'manual_cents': 0,
      'online_cents': 0,
      'refunded_cents': 0,
      'due_cents': 1000,
      'entry_count': 2,
      'email': 'demo@example.test',
    },
    {
      'exhibitor_id': 'two',
      'name': 'Zoe Adams',
      'first_name': 'Zoe',
      'last_name': 'Adams',
      'currency': 'usd',
      'charges_cents': 8000,
      'manual_cents': 0,
      'online_cents': 8000,
      'due_cents': 0,
      'entry_count': 16,
    },
  ];
  @override
  Future<Map<String, dynamic>> load(String id) async {
    loads++;
    if (failLoad) throw Exception('offline');
    return {
      'show_name': 'Finance Test Show',
      'exhibitors': rows,
      'section_ids': [],
      'summaries': [
        {
          'currency': 'usd',
          'charges_cents': rows.fold<int>(
            0,
            (sum, row) => sum + financeCents(row['charges_cents']),
          ),
          'online_fee_cents': 444,
          'discount_cents': 1500,
          'refunded_cents': 0,
          'due_cents': rows.fold<int>(
            0,
            (sum, row) => sum + financeCents(row['due_cents']),
          ),
          'club_earned_cents':
              8000 +
              rows.fold<int>(
                0,
                (sum, row) => sum + financeCents(row['manual_cents']),
              ),
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> history(String show, String exhibitor) async {
    if (failHistory) throw Exception('offline');
    return {'payments': [], 'events': [], 'allocations': []};
  }

  @override
  Future<void> record(
    String show,
    String exhibitor,
    Map<String, dynamic> values,
  ) async {
    if (saved.any((v) => v['p_request_id'] == values['p_request_id'])) return;
    final row = rows.firstWhere((r) => r['exhibitor_id'] == exhibitor);
    final amount = values['p_amount_cents'] as int;
    if (amount > (row['due_cents'] as int)) {
      throw Exception('Balance changed. Refresh and try again.');
    }
    saved.add(Map.of(values));
    row['due_cents'] = (row['due_cents'] as int) - amount;
    if (values['credit'] == true) {
      row['charges_cents'] = (row['charges_cents'] as int) - amount;
      row['credit_cents'] = (row['credit_cents'] as int? ?? 0) + amount;
    } else {
      row['manual_cents'] = (row['manual_cents'] as int) + amount;
    }
  }
}
