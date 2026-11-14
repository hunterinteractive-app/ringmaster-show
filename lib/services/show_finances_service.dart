import 'package:supabase/supabase.dart';

int financeCents(Object? value) => int.tryParse('$value') ?? 0;
String financeMoney(int cents, String currency) =>
    '${currency.toUpperCase()} ${(cents / 100).toStringAsFixed(2)}';
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
