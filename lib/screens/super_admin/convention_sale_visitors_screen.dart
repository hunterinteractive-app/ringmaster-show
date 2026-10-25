import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/app_session.dart';
import '../../services/convention_sale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ringmaster_page_shell.dart';
import '../../widgets/rm_widgets.dart';

class ConventionSaleVisitorsScreen extends StatefulWidget {
  const ConventionSaleVisitorsScreen({super.key});

  @override
  State<ConventionSaleVisitorsScreen> createState() =>
      _ConventionSaleVisitorsScreenState();
}

class _ConventionSaleVisitorsScreenState
    extends State<ConventionSaleVisitorsScreen> {
  final _rows = <Map<String, dynamic>>[];
  bool _loading = false, _more = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(refresh: true);
  }

  Future<void> _load({bool refresh = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (AppSession.isSupportMode) {
        throw StateError('Exit View As User to review visitor records.');
      }
      final rows = await ConventionSaleService.visitors(
        before: refresh || _rows.isEmpty ? null : _rows.last,
      );
      if (!mounted) return;
      setState(() {
        if (refresh) _rows.clear();
        _rows.addAll(rows);
        _more = rows.length == 50;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = AppSession.isSupportMode
              ? 'Exit View As User to review visitor records.'
              : 'Visitor records could not load. Super Admin access is required.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _record(Map<String, dynamic> row) {
    final city = row['city'] as String?;
    final state = row['state'] as String?;
    final location = city != null
        ? '$city, $state'
        : state != null
        ? 'City unavailable, $state'
        : 'City and state unavailable';
    final checked = DateTime.parse(row['checked_at'] as String).toLocal();
    final result = row['eligible'] == true
        ? row['purchased'] == true
              ? 'Within sale area · Purchase completed'
              : 'Within sale area · Purchase not completed'
        : 'Outside sale area or accuracy boundary';
    final plan = switch (row['plan']) {
      'single_show' => '1 token package',
      'four_shows' => '4 token package',
      _ => 'Unlimited package',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RMCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(location, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            SelectableText('${row['email']}'),
            const SizedBox(height: 6),
            Text('${DateFormat.yMMMd().add_jm().format(checked)} · $plan'),
            Text('${row['venue']}'),
            const SizedBox(height: 8),
            Text(result, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (row['locality_status'] == 'pending')
              const Text('City/state lookup has not completed.'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    title: 'Convention visitor locations',
    subtitle: 'Super Admin',
    showHelpButton: false,
    body: SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'City and state at the purchase location check',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Only visitors who use the updated purchase location check appear here. These are check locations, not home addresses. No precise visitor coordinates are saved. U.S. city/state lookups may be unavailable. Times use this device’s time zone. Refresh to update payment results.',
                style: TextStyle(color: Colors.white, height: 1.5),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _loading ? null : () => _load(refresh: true),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh visitor log'),
                ),
              ),
              const SizedBox(height: 18),
              if (_error != null)
                RMCard(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ),
              if (!_loading && _error == null && _rows.isEmpty)
                const RMCard(
                  child: Text('No purchase location checks recorded yet.'),
                ),
              for (final row in _rows) _record(row),
              if (_loading) const Center(child: CircularProgressIndicator()),
              if (!_loading && _rows.isNotEmpty && _more)
                FilledButton(
                  onPressed: _load,
                  child: const Text('Load older checks'),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    ),
  );
}
