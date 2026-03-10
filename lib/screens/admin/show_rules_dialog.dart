import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class ShowRulesDialog {
  static Future<void> open(
    BuildContext context, {
    required String showId,
    required String showName,
  }) async {
    await showDialog(
      context: context,
      builder: (_) => _ShowRulesDialog(showId: showId, showName: showName),
    );
  }
}

class _ShowRulesDialog extends StatefulWidget {
  final String showId;
  final String showName;

  const _ShowRulesDialog({required this.showId, required this.showName});

  @override
  State<_ShowRulesDialog> createState() => _ShowRulesDialogState();
}

class _ShowRulesDialogState extends State<_ShowRulesDialog> {
  bool _loading = true;
  bool _saving = false;
  String? _msg;

  bool requireTattoo = true;
  bool requireSex = true;
  bool requireBirthDate = true;
  bool requireBreed = true;
  bool requireVariety = true;
  bool requireName = false;

  final _maxEntriesPerExhibitor = TextEditingController();
  final _maxEntriesPerAnimal = TextEditingController(text: '1');

  bool blockOutsideWindow = true;
  bool blockUnpublished = true;

  String _finalAwardMode = 'four_six_bis';

  @override
  void dispose() {
    _maxEntriesPerExhibitor.dispose();
    _maxEntriesPerAnimal.dispose();
    super.dispose();
  }

  String _finalAwardModeLabel(String mode) {
    switch (mode) {
      case 'bis_ris':
        return 'Best in Show / Reserve in Show';
      case 'four_six_bis':
      default:
        return 'Best 4-Class / Best 6-Class / Best in Show';
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      final rulesData = await supabase
          .from('show_rule_settings')
          .select(
            'require_tattoo,require_sex,require_birth_date,require_breed,require_variety,require_name,'
            'max_entries_per_exhibitor,max_entries_per_animal,'
            'block_entries_outside_entry_window,block_unpublished_show_entries',
          )
          .eq('show_id', widget.showId)
          .maybeSingle();

      final showData = await supabase
          .from('shows')
          .select('final_award_mode')
          .eq('id', widget.showId)
          .single();

      _finalAwardMode = (showData['final_award_mode'] ?? 'four_six_bis').toString();

      if (rulesData == null) {
        _maxEntriesPerExhibitor.text = '';
        _maxEntriesPerAnimal.text = '1';
      } else {
        requireTattoo = rulesData['require_tattoo'] == true;
        requireSex = rulesData['require_sex'] == true;
        requireBirthDate = rulesData['require_birth_date'] == true;
        requireBreed = rulesData['require_breed'] == true;
        requireVariety = rulesData['require_variety'] == true;
        requireName = rulesData['require_name'] == true;

        _maxEntriesPerExhibitor.text =
            (rulesData['max_entries_per_exhibitor'] ?? '').toString();
        _maxEntriesPerAnimal.text =
            (rulesData['max_entries_per_animal'] ?? 1).toString();

        blockOutsideWindow =
            rulesData['block_entries_outside_entry_window'] == true;
        blockUnpublished =
            rulesData['block_unpublished_show_entries'] == true;
      }

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _msg = 'Load failed: $e';
      });
    }
  }

  int? _parseIntOrNull(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    final v = int.tryParse(t);
    if (v == null) return null;
    if (v < 1) return null;
    return v;
  }

  bool _validate() {
    final maxPerAnimal = _parseIntOrNull(_maxEntriesPerAnimal.text);
    if (maxPerAnimal == null) {
      setState(() => _msg = 'Max entries per animal must be an integer ≥ 1.');
      return false;
    }

    if (_maxEntriesPerExhibitor.text.trim().isNotEmpty) {
      final maxPerEx = _parseIntOrNull(_maxEntriesPerExhibitor.text);
      if (maxPerEx == null) {
        setState(() => _msg = 'Max entries per exhibitor must be blank or an integer ≥ 1.');
        return false;
      }
    }

    if (_finalAwardMode != 'four_six_bis' && _finalAwardMode != 'bis_ris') {
      setState(() => _msg = 'Final award format is invalid.');
      return false;
    }

    return true;
  }

    Future<void> _save() async {
      if (!_validate()) return;

      setState(() {
        _saving = true;
        _msg = null;
      });

      final maxPerExhibitor = _parseIntOrNull(_maxEntriesPerExhibitor.text);
      final maxPerAnimal = int.parse(_maxEntriesPerAnimal.text.trim());

      try {
        // 1) Save rule settings
        await supabase.from('show_rule_settings').upsert({
          'show_id': widget.showId,
          'require_tattoo': requireTattoo,
          'require_sex': requireSex,
          'require_birth_date': requireBirthDate,
          'require_breed': requireBreed,
          'require_variety': requireVariety,
          'require_name': requireName,
          'max_entries_per_exhibitor': maxPerExhibitor,
          'max_entries_per_animal': maxPerAnimal,
          'block_entries_outside_entry_window': blockOutsideWindow,
          'block_unpublished_show_entries': blockUnpublished,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });

        // 2) Save final award mode on shows
        await supabase
            .from('shows')
            .update({
              'final_award_mode': _finalAwardMode,
            })
            .eq('id', widget.showId);

        if (!mounted) return;
        setState(() {
          _saving = false;
          _msg = 'Saved.';
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _msg = 'Save failed: $e';
        });
      }
    }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Rules & Validation — ${widget.showName}'),
      content: _loading
          ? const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_msg != null) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _msg!,
                        style: TextStyle(
                          color: _msg == 'Saved.' ? Colors.green : Colors.red,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Required fields',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tattoo / ID required'),
                    value: requireTattoo,
                    onChanged: _saving ? null : (v) => setState(() => requireTattoo = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sex required'),
                    value: requireSex,
                    onChanged: _saving ? null : (v) => setState(() => requireSex = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Birth date required'),
                    value: requireBirthDate,
                    onChanged: _saving ? null : (v) => setState(() => requireBirthDate = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Breed required'),
                    value: requireBreed,
                    onChanged: _saving ? null : (v) => setState(() => requireBreed = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Variety required'),
                    value: requireVariety,
                    onChanged: _saving ? null : (v) => setState(() => requireVariety = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Name required'),
                    subtitle: const Text('Default is OFF (you wanted name optional)'),
                    value: requireName,
                    onChanged: _saving ? null : (v) => setState(() => requireName = v),
                  ),

                  const Divider(height: 24),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Limits',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  TextField(
                    controller: _maxEntriesPerExhibitor,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Max entries per exhibitor (optional)',
                      hintText: 'Leave blank for unlimited',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _maxEntriesPerAnimal,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Max entries per animal',
                      hintText: 'Usually 1',
                    ),
                  ),

                  const Divider(height: 24),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Award rules',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _finalAwardMode,
                    decoration: const InputDecoration(
                      labelText: 'Final award format',
                      helperText: 'Choose how final show awards are selected.',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'four_six_bis',
                        child: Text('Best 4-Class / Best 6-Class / Best in Show'),
                      ),
                      DropdownMenuItem(
                        value: 'bis_ris',
                        child: Text('Best in Show / Reserve in Show'),
                      ),
                    ],
                    onChanged: _saving
                        ? null
                        : (v) {
                            setState(() {
                              _finalAwardMode = v ?? 'four_six_bis';
                            });
                          },
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Current mode: ${_finalAwardModeLabel(_finalAwardMode)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),

                  const Divider(height: 24),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Enforcement',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Block entries outside entry window'),
                    value: blockOutsideWindow,
                    onChanged: _saving ? null : (v) => setState(() => blockOutsideWindow = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Block entries when show is unpublished'),
                    value: blockUnpublished,
                    onChanged: _saving ? null : (v) => setState(() => blockUnpublished = v),
                  ),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}