import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/closeout_repository.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/unpaid_balances_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/base/report_request.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/unpaid/unpaid_balances_report_data.dart';

class FixtureRepository extends CloseoutRepository {
  FixtureRepository(super.client);
  @override
  Future<Map<String, dynamic>> loadShowBasics(String showId) async => {
    'name': 'Duneabash',
  };
  @override
  Future<List<Map<String, dynamic>>> loadCurrentShowBalances(
    String showId,
  ) async => [
    {
      'exhibitor_name': 'Secretary pay at show',
      'source': 'entries',
      'entry_count': 3,
      'balance_due_cents': 1200,
    },
    {
      'exhibitor_name': 'Submitted pay at show',
      'source': 'cart',
      'entry_count': 2,
      'balance_due_cents': 800,
    },
    {
      'exhibitor_name': 'Fully paid online',
      'source': 'entries',
      'entry_count': 4,
      'paid_online_cents': 1600,
      'balance_due_cents': 0,
    },
    {
      'exhibitor_name': 'Partially paid online',
      'source': 'entries',
      'entry_count': 13,
      'paid_online_cents': 4800,
      'balance_due_cents': 400,
    },
  ];
}

void main() {
  test(
    'Unpaid and Partial exports select the same statuses as their tabs',
    () async {
      final client = SupabaseClient('https://example.supabase.co', 'test-key');
      addTearDown(client.dispose);
      final loader = UnpaidBalancesReportLoader(FixtureRepository(client));
      final request = ReportRequest(
        showId: 'show',
        reportName: 'unpaid',
        finalizeRunId: '',
      );
      final unpaid = await loader.load(
        request,
        filter: OutstandingBalanceFilter.unpaid,
      );
      expect(unpaid.rows.map((r) => r.exhibitorName), [
        'Secretary pay at show',
        'Submitted pay at show',
      ]);
      expect(unpaid.grandTotalDue, 20);
      final partial = await loader.load(
        request,
        filter: OutstandingBalanceFilter.partial,
      );
      expect(partial.rows.single.exhibitorName, 'Partially paid online');
      expect(partial.grandTotalDue, 4);
    },
  );
  for (final hideZero in [true, false]) {
    test(
      'include committed cart balances and handle zero totals (hide zero: $hideZero)',
      () async {
        final client = SupabaseClient(
          'https://example.supabase.co',
          'test-key',
        );
        addTearDown(client.dispose);
        final report =
            await UnpaidBalancesReportLoader(FixtureRepository(client)).load(
              ReportRequest(
                showId: 'show',
                reportName: 'unpaid',
                finalizeRunId: '',
                hideZeroBalances: hideZero,
              ),
            );
        expect(
          report.rows.map((r) => r.exhibitorName),
          hideZero
              ? [
                  'Partially paid online',
                  'Secretary pay at show',
                  'Submitted pay at show',
                ]
              : [
                  'Fully paid online',
                  'Partially paid online',
                  'Secretary pay at show',
                  'Submitted pay at show',
                ],
        );
        expect(report.grandTotalDue, 24);
        expect(report.totalEntries, hideZero ? 18 : 22);
        expect(report.grandPaidOnline, hideZero ? 48 : 64);
      },
    );
  }
}
