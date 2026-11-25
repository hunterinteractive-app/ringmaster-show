import 'package:flutter/material.dart';
import '../services/ringmaster_backend.dart';
import '../theme/app_theme.dart';

Future<Map<String, dynamic>?> showAddFurWoolDialog(
  BuildContext context,
  Map<String, dynamic> entry,
) => showDialog<Map<String, dynamic>>(
  context: context,
  barrierDismissible: false,
  builder: (context) => Theme(
    data: AppTheme.surfaceDialogTheme(Theme.of(context)),
    child: AddFurWoolDialog(
      currentSectionId: entry['section_id'].toString(),
      load: () async => Map<String, dynamic>.from(
        await ringMasterClient.rpc(
              'exhibitor_fur_additions',
              params: {'p_entry_id': entry['id']},
            )
            as Map,
      ),
      save: (sections, variety) async => Map<String, dynamic>.from(
        await ringMasterClient.rpc(
              'exhibitor_fur_additions',
              params: {
                'p_entry_id': entry['id'],
                'p_section_ids': sections,
                'p_fur_variety': variety,
              },
            )
            as Map,
      ),
    ),
  ),
);

class AddFurWoolDialog extends StatefulWidget {
  const AddFurWoolDialog({
    super.key,
    required this.currentSectionId,
    required this.load,
    required this.save,
  });
  final String currentSectionId;
  final Future<Map<String, dynamic>> Function() load;
  final Future<Map<String, dynamic>> Function(List<String>, String) save;

  @override
  State<AddFurWoolDialog> createState() => _AddFurWoolDialogState();
}

class _AddFurWoolDialogState extends State<AddFurWoolDialog> {
  Map<String, dynamic>? data;
  final selected = <String>{};
  String? variety, error;
  bool loading = true, saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String message(Object e) => e is PostgrestException
      ? e.message
      : 'Unable to update Fur/Wool entries. Please try again.';

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.load();
      if (!mounted) return;
      setState(() {
        data = result;
        selected.clear();
        if (sections.any(
          (s) =>
              s['id'] == widget.currentSectionId &&
              s['unavailable_reason'] == null,
        )) {
          selected.add(widget.currentSectionId);
        }
      });
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<Map<String, dynamic>> get sections => (data?['sections'] as List? ?? [])
      .map((s) => Map<String, dynamic>.from(s as Map))
      .toList();

  String price(int cents) =>
      '${data?['currency'] ?? 'USD'} ${(cents / 100).toStringAsFixed(2)}';

  Future<void> _save() async {
    if (saving || selected.isEmpty || variety == null) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final result = await widget.save(selected.toList(), variety!);
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = message(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = sections
        .where((s) => s['unavailable_reason'] == null)
        .toList();
    final total = sections
        .where((s) => selected.contains(s['id']))
        .fold<int>(0, (n, s) => n + (s['fee_cents'] as num).toInt());
    return PopScope(
      canPop: !saving,
      child: AlertDialog(
        title: const Text('Add Fur/Wool'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (loading)
                  const Center(child: CircularProgressIndicator())
                else if (data != null) ...[
                  Text(
                    '${data!['tattoo'] ?? 'Rabbit'} • ${data!['show_name'] ?? 'Show'}',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Select the sections where this rabbit is already entered. Only sections offering Fur/Wool are listed.',
                  ),
                  if (sections.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'No eligible Fur/Wool sections are available for this rabbit.',
                      ),
                    ),
                  if (available.length > 1)
                    TextButton(
                      onPressed: saving
                          ? null
                          : () => setState(() {
                              if (selected.length == available.length) {
                                selected.clear();
                              } else {
                                selected.addAll(
                                  available.map((s) => s['id'] as String),
                                );
                              }
                            }),
                      child: Text(
                        selected.length == available.length
                            ? 'Clear selection'
                            : 'Select all available sections',
                      ),
                    ),
                  for (final section in sections)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        section['label'] as String,
                        style: const TextStyle(color: AppColors.text),
                      ),
                      subtitle: Text(
                        section['unavailable_reason'] as String? ??
                            price((section['fee_cents'] as num).toInt()),
                        style: const TextStyle(color: AppColors.muted),
                      ),
                      value: selected.contains(section['id']),
                      onChanged: saving || section['unavailable_reason'] != null
                          ? null
                          : (value) => setState(() {
                              if (value == true) {
                                selected.add(section['id'] as String);
                              } else {
                                selected.remove(section['id']);
                              }
                            }),
                    ),
                  if (available.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: variety,
                      decoration: const InputDecoration(
                        labelText: 'Fur/Wool class',
                        helperText: 'Required for the selected sections',
                      ),
                      items: const [
                        DropdownMenuItem(value: 'White', child: Text('White')),
                        DropdownMenuItem(
                          value: 'Colored',
                          child: Text('Colored'),
                        ),
                      ],
                      onChanged: saving
                          ? null
                          : (value) => setState(() => variety = value),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Fur/Wool fees: ${price(total)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Continue to checkout to confirm these additions. Online-payment shows require payment. Other items already in your cart will also be shown.',
                    ),
                  ],
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ),
                if (!loading && data == null)
                  TextButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (data?['cart_id'] != null &&
              sections.any((s) => s['unavailable_reason'] == 'Already in cart'))
            TextButton(
              onPressed: saving
                  ? null
                  : () => Navigator.pop(context, {
                      'cart_id': data!['cart_id'],
                      'show_id': data!['show_id'],
                      'show_name': data!['show_name'],
                    }),
              child: const Text('View existing cart'),
            ),
          if (available.isNotEmpty)
            FilledButton(
              onPressed:
                  loading || saving || selected.isEmpty || variety == null
                  ? null
                  : _save,
              child: Text(saving ? 'Adding…' : 'Continue to checkout'),
            ),
        ],
      ),
    );
  }
}
