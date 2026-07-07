// lib/screens/admin/show_rules_dialog.dart

import 'package:flutter/material.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/services/show_lock_service.dart';

final supabase = Supabase.instance.client;

class ShowRulesDialog {
  static Future<void> open(
    BuildContext context, {
    required String showId,
    required String showName,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
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
  bool _isLocked = false;
  bool _isFinalized = false;

  bool get _isReadOnly => _isLocked || _isFinalized;

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
  void initState() {
    super.initState();
    _load();
  }

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
          .select('final_award_mode,is_locked,finalized_at')
          .eq('id', widget.showId)
          .single();

      _finalAwardMode = (showData['final_award_mode'] ?? 'four_six_bis')
          .toString();
      _isLocked = showData['is_locked'] == true;
      _isFinalized = (showData['finalized_at'] ?? '')
          .toString()
          .trim()
          .isNotEmpty;

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
        _maxEntriesPerAnimal.text = (rulesData['max_entries_per_animal'] ?? 1)
            .toString();

        blockOutsideWindow =
            rulesData['block_entries_outside_entry_window'] == true;
        blockUnpublished = rulesData['block_unpublished_show_entries'] == true;
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
    if (_isReadOnly) {
      setState(
        () => _msg = _isFinalized
            ? 'This show has been finalized. Rules can no longer be changed.'
            : 'This show is locked. Rules can no longer be changed.',
      );
      return false;
    }
    final maxPerAnimal = _parseIntOrNull(_maxEntriesPerAnimal.text);
    if (maxPerAnimal == null) {
      setState(() => _msg = 'Max entries per animal must be an integer ≥ 1.');
      return false;
    }

    if (_maxEntriesPerExhibitor.text.trim().isNotEmpty) {
      final maxPerEx = _parseIntOrNull(_maxEntriesPerExhibitor.text);
      if (maxPerEx == null) {
        setState(
          () => _msg =
              'Max entries per exhibitor must be blank or an integer ≥ 1.',
        );
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
      await ShowLockService.assertShowUnlocked(widget.showId);
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

      await supabase
          .from('shows')
          .update({'final_award_mode': _finalAwardMode})
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

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: .05), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).size;
    final savedMessage = _msg == 'Saved.';

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: media.width < 700 ? media.width - 16 : media.width * 0.76,
          maxHeight: media.height * 0.92,
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.navy, AppColors.navyDark],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/images/ringmaster_show_logo.png',
                      height: 38,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Rules & Validation — ${widget.showName}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(top: 4),
                  decoration: const BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                          child: Column(
                            children: [
                              if (_isReadOnly) ...[
                                Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.amber.shade300,
                                    ),
                                  ),
                                  child: Text(
                                    _isFinalized
                                        ? 'This show has been finalized. Rules and validation settings are view-only.'
                                        : 'This show is locked. Rules and validation settings are view-only.',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                              if (_msg != null)
                                Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: savedMessage
                                        ? Colors.green.withValues(alpha: .08)
                                        : Colors.red.withValues(alpha: .08),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: savedMessage
                                          ? Colors.green.withValues(alpha: .25)
                                          : Colors.red.withValues(alpha: .25),
                                    ),
                                  ),
                                  child: Text(
                                    _msg!,
                                    style: TextStyle(
                                      color: savedMessage
                                          ? Colors.green
                                          : Colors.red,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: SingleChildScrollView(
                                  child: Column(
                                    children: [
                                      _buildSectionCard(
                                        context: context,
                                        title: 'Required Fields',
                                        children: [
                                          SwitchListTile(
                                            contentPadding: EdgeInsets.zero,
                                            title: const Text(
                                              'Tattoo / ID required',
                                            ),
                                            value: requireTattoo,
                                            onChanged: (_saving || _isReadOnly)
                                                ? null
                                                : (v) => setState(
                                                    () => requireTattoo = v,
                                                  ),
                                          ),
                                          SwitchListTile(
                                            contentPadding: EdgeInsets.zero,
                                            title: const Text('Sex required'),
                                            value: requireSex,
                                            onChanged: (_saving || _isReadOnly)
                                                ? null
                                                : (v) => setState(
                                                    () => requireSex = v,
                                                  ),
                                          ),
                                          SwitchListTile(
                                            contentPadding: EdgeInsets.zero,
                                            title: const Text(
                                              'Birth date required',
                                            ),
                                            value: requireBirthDate,
                                            onChanged: (_saving || _isReadOnly)
                                                ? null
                                                : (v) => setState(
                                                    () => requireBirthDate = v,
                                                  ),
                                          ),
                                          SwitchListTile(
                                            contentPadding: EdgeInsets.zero,
                                            title: const Text('Breed required'),
                                            value: requireBreed,
                                            onChanged: (_saving || _isReadOnly)
                                                ? null
                                                : (v) => setState(
                                                    () => requireBreed = v,
                                                  ),
                                          ),
                                          SwitchListTile(
                                            contentPadding: EdgeInsets.zero,
                                            title: const Text(
                                              'Variety required',
                                            ),
                                            value: requireVariety,
                                            onChanged: (_saving || _isReadOnly)
                                                ? null
                                                : (v) => setState(
                                                    () => requireVariety = v,
                                                  ),
                                          ),
                                          SwitchListTile(
                                            contentPadding: EdgeInsets.zero,
                                            title: const Text('Name required'),
                                            subtitle: const Text(
                                              'Default is OFF so animal name stays optional.',
                                            ),
                                            value: requireName,
                                            onChanged: (_saving || _isReadOnly)
                                                ? null
                                                : (v) => setState(
                                                    () => requireName = v,
                                                  ),
                                          ),
                                        ],
                                      ),
                                      _buildSectionCard(
                                        context: context,
                                        title: 'Limits',
                                        children: [
                                          TextField(
                                            controller: _maxEntriesPerExhibitor,
                                            enabled: !_saving && !_isReadOnly,
                                            keyboardType: TextInputType.number,
                                            decoration: const InputDecoration(
                                              labelText:
                                                  'Max entries per exhibitor (optional)',
                                              hintText:
                                                  'Leave blank for unlimited',
                                              border: OutlineInputBorder(),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          TextField(
                                            controller: _maxEntriesPerAnimal,
                                            enabled: !_saving && !_isReadOnly,
                                            keyboardType: TextInputType.number,
                                            decoration: const InputDecoration(
                                              labelText:
                                                  'Max entries per animal',
                                              hintText: 'Usually 1',
                                              border: OutlineInputBorder(),
                                            ),
                                          ),
                                        ],
                                      ),
                                      _buildSectionCard(
                                        context: context,
                                        title: 'Award Rules',
                                        children: [
                                          DropdownButtonFormField<String>(
                                            initialValue: _finalAwardMode,
                                            decoration: const InputDecoration(
                                              labelText: 'Final award format',
                                              helperText:
                                                  'Choose how final show awards are selected.',
                                              border: OutlineInputBorder(),
                                            ),
                                            items: const [
                                              DropdownMenuItem(
                                                value: 'four_six_bis',
                                                child: Text(
                                                  'Best 4-Class / Best 6-Class / Best in Show',
                                                ),
                                              ),
                                              DropdownMenuItem(
                                                value: 'bis_ris',
                                                child: Text(
                                                  'Best in Show / Reserve in Show',
                                                ),
                                              ),
                                            ],
                                            onChanged: (_saving || _isReadOnly)
                                                ? null
                                                : (v) {
                                                    setState(() {
                                                      _finalAwardMode =
                                                          v ?? 'four_six_bis';
                                                    });
                                                  },
                                          ),
                                          const SizedBox(height: 8),
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              'Current mode: ${_finalAwardModeLabel(_finalAwardMode)}',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                          ),
                                        ],
                                      ),
                                      _buildSectionCard(
                                        context: context,
                                        title: 'Enforcement',
                                        children: [
                                          SwitchListTile(
                                            contentPadding: EdgeInsets.zero,
                                            title: const Text(
                                              'Block entries outside entry window',
                                            ),
                                            value: blockOutsideWindow,
                                            onChanged: (_saving || _isReadOnly)
                                                ? null
                                                : (v) => setState(
                                                    () =>
                                                        blockOutsideWindow = v,
                                                  ),
                                          ),
                                          SwitchListTile(
                                            contentPadding: EdgeInsets.zero,
                                            title: const Text(
                                              'Block entries when show is unpublished',
                                            ),
                                            value: blockUnpublished,
                                            onChanged: (_saving || _isReadOnly)
                                                ? null
                                                : (v) => setState(
                                                    () => blockUnpublished = v,
                                                  ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: _saving
                                          ? null
                                          : () => Navigator.pop(context),
                                      child: const Text('Close'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor:
                                            AppColors.primaryButton,
                                        foregroundColor:
                                            AppColors.primaryButtonText,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                      ),
                                      onPressed: (_saving || _isReadOnly)
                                          ? null
                                          : _save,
                                      child: Text(
                                        _saving
                                            ? 'Saving…'
                                            : _isReadOnly
                                            ? 'View Only'
                                            : 'Save',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
