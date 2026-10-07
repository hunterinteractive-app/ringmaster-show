import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/ringmaster_page_shell.dart';

class AssistantUsageScreen extends StatefulWidget {
  const AssistantUsageScreen({super.key});
  @override
  State<AssistantUsageScreen> createState() => _AssistantUsageScreenState();
}

class _AssistantUsageScreenState extends State<AssistantUsageScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false;
  final _budget = TextEditingController();
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _budget.dispose();
    super.dispose();
  }

  String _money(dynamic n) =>
      '\$${((n as num? ?? 0) / 1000000).toStringAsFixed(4)}';
  Future<void> _load({bool? enabled, int? budget}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await Supabase.instance.client.rpc(
        'assistant_admin',
        params: {'p_enabled': enabled, 'p_budget': budget},
      );
      if (mounted) {
        setState(() {
          _data = Map<String, dynamic>.from(result as Map);
          _budget.text =
              ((_data!['settings']['monthly_budget_microusd'] as num) / 1000000)
                  .toStringAsFixed(2);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Unable to load assistant usage. Superadmin access and the assistant database update are required.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _data?['settings'];
    final usage = _data?['usage'];
    return RingMasterPageShell(
      title: 'AI assistant usage',
      showHelpButton: false,
      body: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: ListView(
          children: [
            const Text(
              'Monthly usage • UTC',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
              ),
            if (_busy) const LinearProgressIndicator(),
            if (_data != null) ...[
              SwitchListTile(
                title: const Text('Enable AI answers'),
                subtitle: const Text(
                  'FAQ and contact support remain available when paused.',
                ),
                value: settings['enabled'] == true,
                onChanged: _busy ? null : (v) => _load(enabled: v),
              ),
              Text(
                'Reserved / estimated spend: ${_money(usage['charged_microusd'])} of ${_money(settings['monthly_budget_microusd'])}',
              ),
              Text(
                '${usage['questions']} questions • ${usage['conversations']} conversations',
              ),
              Text(
                '${usage['unconfirmed']} unconfirmed or failed requests retain their maximum reservation.',
              ),
              Text(
                'Limits: ${settings['daily_questions']} questions per user/day, ${settings['minute_questions']} per minute; one active question at a time.',
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _budget,
                  enabled: !_busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Monthly AI budget (USD)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: _busy
                      ? null
                      : () {
                          final v = double.tryParse(_budget.text);
                          if (v == null || !v.isFinite || v < 0 || v > 1000) {
                            setState(
                              () =>
                                  _error = r'Enter a budget from $0 to $1,000.',
                            );
                            return;
                          }
                          _load(budget: (v * 1000000).round());
                        },
                  child: const Text('Save budget'),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Recent conversations',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const Text(
                'Usage totals are shown here. Open Chester Conversations in Super Admin to review saved chats.',
              ),
              for (final c in _data!['recent_conversations'] as List)
                ListTile(
                  title: Text(
                    '${c['questions']} questions • ${_money(c['charged_microusd'])}',
                  ),
                  subtitle: Text('${c['last_used']}\n${c['conversation_id']}'),
                ),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _busy ? null : () => _load(),
                child: const Text('Refresh'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
