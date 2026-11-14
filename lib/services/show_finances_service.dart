import 'package:supabase/supabase.dart';
import 'package:intl/intl.dart';

int financeCents(Object? value) => int.tryParse('$value') ?? 0;
final _financeNumberFormat = NumberFormat('#,##0.00', 'en_US');
String financeMoney(int cents, String currency) =>
    '${currency.toUpperCase()} ${_financeNumberFormat.format(cents / 100)}';
int? parseFinanceAmount(String text) {
  final value = text.trim();
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) return null;
  final parts = value.split('.');
  final whole = int.tryParse(parts.first);
  if (whole == null || whole > 21474836) return null;
  final cents =
      whole * 100 +
      (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
  return cents > 0 && cents <= 2147483647 ? cents : null;
}

class ShowFinanceRow {
  ShowFinanceRow(this.data);
  final Map<String, dynamic> data;
  String get id => data['exhibitor_id'] as String;
  String get name => data['name'] as String? ?? 'Exhibitor';
  String get currency => data['currency'] as String? ?? 'usd';
  String get lastNameSortKey =>
      (data['last_name'] as String? ?? '').trim().isNotEmpty
      ? (data['last_name'] as String).trim().toLowerCase()
      : name.trim().toLowerCase();
  static int compare(ShowFinanceRow a, ShowFinanceRow b) {
    for (final result in [
      a.lastNameSortKey.compareTo(b.lastNameSortKey),
      '${a.data['first_name'] ?? ''}'.trim().toLowerCase().compareTo(
        '${b.data['first_name'] ?? ''}'.trim().toLowerCase(),
      ),
      a.id.compareTo(b.id),
      a.currency.compareTo(b.currency),
    ]) {
      if (result != 0) return result;
    }
    return 0;
  }

  int cents(String key) => financeCents(data[key]);
  int get due => cents('due_cents');
  int get received => cents('online_cents') + cents('manual_cents');
  String get status => due == 0
      ? 'Paid'
      : received > cents('refunded_cents')
      ? 'Partial'
      : 'Unpaid';
  bool matches(String query) => [
    name,
    data['number'],
    data['email'],
    data['phone'],
  ].join(' ').toLowerCase().contains(query.toLowerCase().trim());
}

/// Keep summary totals independent of the search and payment-status filters.
/// Older backends can supply principal totals, but cannot establish payment costs.
List<Map<String, dynamic>> showFinanceSummaries(Map<String, dynamic>? data) {
  final summaries = data?['summaries'];
  if (summaries is List) {
    return summaries.map((s) => Map<String, dynamic>.from(s as Map)).toList();
  }
  final currencies = <String, Map<String, dynamic>>{};
  for (final raw in data?['exhibitors'] as List? ?? []) {
    final row = ShowFinanceRow(Map<String, dynamic>.from(raw as Map));
    final totals = currencies.putIfAbsent(
      row.currency,
      () => {
        'currency': row.currency,
        'charges_cents': 0,
        'refunded_cents': 0,
        'due_cents': 0,
      },
    );
    for (final key in ['charges_cents', 'refunded_cents', 'due_cents']) {
      totals[key] = financeCents(totals[key]) + row.cents(key);
    }
  }
  return currencies.values.toList()
    ..sort((a, b) => '${a['currency']}'.compareTo('${b['currency']}'));
}

abstract class ShowFinanceGateway {
  Future<Map<String, dynamic>> load(String showId);
  Future<Map<String, dynamic>> history(String showId, String exhibitorId);
  Future<void> record(
    String showId,
    String exhibitorId,
    Map<String, dynamic> values,
  );
}

class ShowFinancesService implements ShowFinanceGateway {
  ShowFinancesService(this.client);
  final SupabaseClient client;
  @override
  Future<Map<String, dynamic>> load(String showId) async =>
      Map<String, dynamic>.from(
        await client.rpc('get_show_finances', params: {'p_show_id': showId})
            as Map,
      );
  @override
  Future<Map<String, dynamic>> history(
    String showId,
    String exhibitorId,
  ) async => Map<String, dynamic>.from(
    await client.rpc(
          'get_show_finance_history',
          params: {'p_show_id': showId, 'p_exhibitor_id': exhibitorId},
        )
        as Map,
  );
  @override
  Future<void> record(
    String showId,
    String exhibitorId,
    Map<String, dynamic> values,
  ) async {
    final credit = values['credit'] == true;
    await client.rpc(
      credit ? 'credit_show_finance_balance' : 'record_show_finance_payment',
      params: {
        'p_show_id': showId,
        'p_exhibitor_id': exhibitorId,
        ...Map<String, dynamic>.from(values)..remove('credit'),
      },
    );
  }
}
