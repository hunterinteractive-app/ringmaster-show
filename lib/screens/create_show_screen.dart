// lib/screens/create_show_screen.dart
// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';

import '../services/app_session.dart';
import '../services/club_service.dart';
import '../widgets/rm_timezone_notice_banner.dart';

final supabase = Supabase.instance.client;

class CreateShowScreen extends StatefulWidget {
  const CreateShowScreen({super.key});

  @override
  State<CreateShowScreen> createState() => _CreateShowScreenState();
}

class _CreateShowScreenState extends State<CreateShowScreen> {
  final _name = TextEditingController();
  final _location = TextEditingController();
  final _hostingClubName = TextEditingController();

  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now();
  bool _published = false;
  bool _isNationalShow = false;
  String? _nationalShowSectionKey;
  bool _autoEmailCheckInSheets = false;

  int _openCount = 1;
  int _youthCount = 0;

  DateTime? _entryCloseAt;

  List<Map<String, dynamic>> _clubs = [];
  String? _selectedClubId;
  String? _selectedClubName;
  bool _loadingClubs = false;

  bool _hasLockedHostingClub = false;
  bool _canSwitchHostingClub = false; // from the Secretary License entitlement

  bool _saving = false;
  String? _msg;

  static const _fieldTextStyle = TextStyle(
    color: AppColors.text,
    fontWeight: FontWeight.w500,
  );

  static const _dropdownItemTextStyle = TextStyle(color: AppColors.text);

  static const _disabledTileTitleStyle = TextStyle(
    color: AppColors.muted,
    fontWeight: FontWeight.w500,
  );

  static const _disabledTileSubtitleStyle = TextStyle(color: AppColors.muted);

  @override
  void initState() {
    super.initState();
    _loadClubs();
  }

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    _hostingClubName.dispose();
    super.dispose();
  }

  Future<void> _loadClubs() async {
    setState(() => _loadingClubs = true);

    try {
      final clubs = await ClubService.loadMyClubs();
      final canSwitch = await ClubService.canSwitchHostingClub();

      if (!mounted) return;
      setState(() {
        _clubs = clubs;
        _canSwitchHostingClub = canSwitch;

        if (_clubs.isNotEmpty) {
          _hasLockedHostingClub = true;

          if (_selectedClubId == null || _selectedClubId!.isEmpty) {
            _selectedClubId = _clubs.first['id']?.toString();
            _selectedClubName = _clubs.first['name']?.toString();
          }

          _hostingClubName.text = _selectedClubName ?? '';
        } else {
          _hasLockedHostingClub = false;
          _selectedClubId = null;
          _selectedClubName = null;
          _hostingClubName.text = '';
        }

        _loadingClubs = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingClubs = false;
        _msg = 'Failed to load clubs: $e';
      });
    }
  }

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _start : _end,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;

    setState(() {
      if (isStart) {
        _start = picked;
        if (_end.isBefore(_start)) {
          _end = picked;
        }
      } else {
        _end = picked;
      }
    });
  }

  Future<DateTime?> _pickDateTime(DateTime? current) async {
    final base = current?.toLocal() ?? DateTime.now();

    final d = await showDatePicker(
      context: context,
      initialDate: DateTime(base.year, base.month, base.day),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (d == null) return null;

    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
    );
    if (t == null) return null;

    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  Future<void> _pickEntryCloseAt() async {
    final picked = await _pickDateTime(_entryCloseAt);
    if (picked == null) return;
    setState(() => _entryCloseAt = picked);
  }

  String _fmtDateTime(DateTime? d) {
    if (d == null) return '(not set)';
    final x = d.toLocal();
    final hh = x.hour.toString().padLeft(2, '0');
    final mm = x.minute.toString().padLeft(2, '0');
    final yyyy = x.year.toString().padLeft(4, '0');
    final mo = x.month.toString().padLeft(2, '0');
    final dd = x.day.toString().padLeft(2, '0');
    return '$yyyy-$mo-$dd $hh:$mm';
  }

  bool _validate() {
    if (AppSession.isSupportMode) {
      setState(
        () =>
            _msg = 'Creating shows is disabled while viewing in support mode.',
      );
      return false;
    }

    final userId = AppSession.effectiveUserId;
    if (userId == null) {
      setState(() => _msg = 'Not signed in.');
      return false;
    }

    if (_name.text.trim().isEmpty) {
      setState(() => _msg = 'Show name is required.');
      return false;
    }

    if (_location.text.trim().isEmpty) {
      setState(() => _msg = 'Location is required.');
      return false;
    }

    if (_hasLockedHostingClub) {
      if (_selectedClubId == null || _selectedClubId!.isEmpty) {
        setState(() => _msg = 'Hosting club is required.');
        return false;
      }
    } else {
      if (_hostingClubName.text.trim().isEmpty) {
        setState(() => _msg = 'Hosting club name is required.');
        return false;
      }
    }

    if (_end.isBefore(_start)) {
      setState(() => _msg = 'End date cannot be before start date.');
      return false;
    }

    if (_openCount == 0 && _youthCount == 0) {
      setState(
        () => _msg = 'Select at least one show type (Open and/or Youth).',
      );
      return false;
    }

    if (_isNationalShow && _nationalShowSectionKey == null) {
      setState(() => _msg = 'Select which show is the national show.');
      return false;
    }

    if (_entryCloseAt != null) {
      final showEndLocal = DateTime(_end.year, _end.month, _end.day, 23, 59);
      if (_entryCloseAt!.isAfter(showEndLocal)) {
        setState(() => _msg = 'Entry close can’t be after the show end date.');
        return false;
      }
    }

    return true;
  }

  List<Map<String, dynamic>> _buildSectionRows(String showId) {
    final rows = <Map<String, dynamic>>[];

    void addSections({
      required String kind,
      required int count,
      required int baseSort,
      required String label,
    }) {
      for (var i = 0; i < count; i++) {
        final letter = String.fromCharCode(65 + i);
        rows.add({
          'show_id': showId,
          'kind': kind,
          'letter': letter,
          'display_name': '$label $letter',
          'is_enabled': true,
          'sort_order': baseSort + (i * 10),
          'breed_scope': 'all',
          'allowed_breed_ids': null,
        });
      }
    }

    addSections(kind: 'open', count: _openCount, baseSort: 10, label: 'Open');
    addSections(
      kind: 'youth',
      count: _youthCount,
      baseSort: 100,
      label: 'Youth',
    );

    return rows;
  }

  List<DropdownMenuItem<String>> _nationalShowSectionItems() {
    final items = <DropdownMenuItem<String>>[];
    void addItems(String kind, String label, int count) {
      for (var index = 0; index < count; index++) {
        final letter = String.fromCharCode(65 + index);
        items.add(
          DropdownMenuItem(
            value: '$kind:$letter',
            child: Text('$label $letter'),
          ),
        );
      }
    }

    addItems('open', 'Open', _openCount);
    addItems('youth', 'Youth', _youthCount);
    return items;
  }

  bool _nationalShowSectionKeyIsAvailable(String? key) {
    if (key == null) return false;
    return _nationalShowSectionItems().any((item) => item.value == key);
  }

  Future<Map<String, dynamic>> _createFirstClubForUser({
    required String userId,
    required String clubName,
  }) async {
    final created = await supabase
        .from('clubs')
        .insert({
          'name': clubName.trim(),
          'created_by': userId,
          'is_active': true,
        })
        .select()
        .single();

    final clubId = created['id'].toString();

    await supabase.from('club_members').insert({
      'club_id': clubId,
      'user_id': userId,
      'role': 'owner',
      'is_active': true,
    });

    return Map<String, dynamic>.from(created);
  }

  Future<void> _create() async {
    if (!_validate()) return;

    final userId = AppSession.effectiveUserId!;

    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      String? clubId = _selectedClubId;
      String? clubName = _selectedClubName;

      if (!_hasLockedHostingClub) {
        final createdClub = await _createFirstClubForUser(
          userId: userId,
          clubName: _hostingClubName.text.trim(),
        );

        clubId = createdClub['id']?.toString();
        clubName = createdClub['name']?.toString();

        if (mounted) {
          setState(() {
            _selectedClubId = clubId;
            _selectedClubName = clubName;
            _hasLockedHostingClub = true;
          });
        }

        await _loadClubs();
      }

      final dynamic rpcResult = await supabase.rpc(
        'create_show_with_license',
        params: {
          'p_name': _name.text.trim(),
          'p_start_date': _start.toIso8601String().substring(0, 10),
          'p_end_date': _end.toIso8601String().substring(0, 10),
          'p_location_name': _location.text.trim(),
        },
      );

      final showId = rpcResult.toString();

      await supabase
          .from('shows')
          .update({
            'timezone': 'America/Indiana/Indianapolis',
            'is_published': _published,
            'is_national_show': _isNationalShow,
            'entry_close_at': _entryCloseAt?.toUtc().toIso8601String(),
            'auto_email_checkin_sheets': _autoEmailCheckInSheets,
            'club_id': clubId,
            'club_name': clubName,
          })
          .eq('id', showId);

      final sectionRows = _buildSectionRows(showId);
      if (sectionRows.isNotEmpty) {
        final insertedSections = await supabase
            .from('show_sections')
            .insert(sectionRows)
            .select('id,kind,letter');
        if (_isNationalShow && _nationalShowSectionKey != null) {
          final selected = (insertedSections as List).cast<Map>().firstWhere(
            (section) =>
                '${section['kind']}:${section['letter']}' ==
                _nationalShowSectionKey,
          );
          await supabase
              .from('shows')
              .update({'national_show_section_id': selected['id']})
              .eq('id', showId);
        }
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Create failed: $e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedClubExists = _clubs.any(
      (club) => club['id']?.toString() == _selectedClubId,
    );

    return RingMasterPageShell(
      title: 'RingMaster Show',
      subtitle: 'Create Show',
      showBackButton: true,
      useScrollView: false,
      bodyPadding: EdgeInsets.zero,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const RMTimezoneNoticeBanner(),
            if (AppSession.isSupportMode) ...[
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warningBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.warningBorder),
                ),
                child: const Text(
                  'Creating shows is disabled while viewing as another user. '
                  'Exit impersonation to create a show from your account.',
                  style: TextStyle(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            Expanded(
              child: SingleChildScrollView(
                child: AppTheme.surfaceTextScope(
                  context,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .05),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            TextField(
                              controller: _name,
                              enabled: !_saving,
                              style: _fieldTextStyle,
                              decoration: const InputDecoration(
                                labelText: 'Show name (required)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _location,
                              enabled: !_saving,
                              style: _fieldTextStyle,
                              decoration: const InputDecoration(
                                labelText: 'Location (required)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_loadingClubs) const LinearProgressIndicator(),
                            if (!_hasLockedHostingClub) ...[
                              TextField(
                                controller: _hostingClubName,
                                enabled: !_saving,
                                style: _fieldTextStyle,
                                decoration: const InputDecoration(
                                  labelText: 'Hosting Club Name (required)',
                                  border: OutlineInputBorder(),
                                  helperText:
                                      'This will be saved as your default hosting club.',
                                ),
                              ),
                            ] else ...[
                              DropdownButtonFormField<String>(
                                initialValue: selectedClubExists
                                    ? _selectedClubId
                                    : null,
                                style: _dropdownItemTextStyle,
                                dropdownColor: AppColors.surface,
                                iconEnabledColor: AppColors.muted,
                                iconDisabledColor: AppColors.muted,
                                decoration: InputDecoration(
                                  labelText: 'Hosting Club',
                                  border: const OutlineInputBorder(),
                                  helperText: _canSwitchHostingClub
                                      ? 'You can switch hosting clubs.'
                                      : 'Locked to your account. A Secretary License is required to change this.',
                                ),
                                items: _clubs.map((club) {
                                  return DropdownMenuItem<String>(
                                    value: club['id'].toString(),
                                    child: Text(
                                      (club['name'] ?? 'Club').toString(),
                                      style: _dropdownItemTextStyle,
                                    ),
                                  );
                                }).toList(),
                                onChanged:
                                    (_saving ||
                                        _loadingClubs ||
                                        !_canSwitchHostingClub)
                                    ? null
                                    : (value) {
                                        setState(() {
                                          _selectedClubId = value;

                                          final selected = _clubs.firstWhere(
                                            (c) => c['id'].toString() == value,
                                            orElse: () => <String, dynamic>{},
                                          );

                                          _selectedClubName =
                                              (selected['name'] ?? '')
                                                  .toString();
                                        });
                                      },
                              ),
                            ],
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Show Start: ${_start.toIso8601String().substring(0, 10)}',
                                    style: _fieldTextStyle,
                                  ),
                                ),
                                TextButton(
                                  onPressed: _saving
                                      ? null
                                      : () => _pickDate(true),
                                  child: const Text('Pick'),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Show End: ${_end.toIso8601String().substring(0, 10)}',
                                    style: _fieldTextStyle,
                                  ),
                                ),
                                TextButton(
                                  onPressed: _saving
                                      ? null
                                      : () => _pickDate(false),
                                  child: const Text('Pick'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Published'),
                              value: _published,
                              onChanged: _saving
                                  ? null
                                  : (v) => setState(() => _published = v),
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('National Show'),
                              subtitle: const Text(
                                'Enables national show reporting rules, including Top 10 Breed reporting.',
                              ),
                              value: _isNationalShow,
                              onChanged: _saving
                                  ? null
                                  : (v) => setState(() {
                                      _isNationalShow = v;
                                      if (!v) _nationalShowSectionKey = null;
                                    }),
                            ),
                            if (_isNationalShow) ...[
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                initialValue: _nationalShowSectionKey,
                                decoration: const InputDecoration(
                                  labelText: 'Which show is the national show?',
                                  border: OutlineInputBorder(),
                                ),
                                items: _nationalShowSectionItems(),
                                onChanged: _saving
                                    ? null
                                    : (value) => setState(
                                        () => _nationalShowSectionKey = value,
                                      ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .05),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Entry Deadline',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Entry close: ${_fmtDateTime(_entryCloseAt)}',
                                    style: _fieldTextStyle,
                                  ),
                                ),
                                TextButton(
                                  onPressed: _saving ? null : _pickEntryCloseAt,
                                  child: const Text('Pick'),
                                ),
                                TextButton(
                                  onPressed: _saving
                                      ? null
                                      : () => setState(() {
                                          _entryCloseAt = null;
                                          _autoEmailCheckInSheets = false;
                                        }),
                                  child: const Text('Clear'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                'Automatically email check-in sheets when entries close?',
                                style: _entryCloseAt == null
                                    ? _disabledTileTitleStyle
                                    : null,
                              ),
                              subtitle: Text(
                                'You can update this later from Print Packs → Check-In Sheets.',
                                style: _entryCloseAt == null
                                    ? _disabledTileSubtitleStyle
                                    : null,
                              ),
                              value: _autoEmailCheckInSheets,
                              onChanged: (_saving || _entryCloseAt == null)
                                  ? null
                                  : (v) => setState(
                                      () => _autoEmailCheckInSheets = v,
                                    ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .05),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Show Types / Sections',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<int>(
                              initialValue: _openCount,
                              style: _dropdownItemTextStyle,
                              dropdownColor: AppColors.surface,
                              iconEnabledColor: AppColors.muted,
                              iconDisabledColor: AppColors.muted,
                              decoration: const InputDecoration(
                                labelText: 'Open shows',
                                border: OutlineInputBorder(),
                              ),
                              items: List.generate(6, (i) {
                                if (i == 0) {
                                  return const DropdownMenuItem<int>(
                                    value: 0,
                                    child: Text(
                                      '0 (No Open shows)',
                                      style: _dropdownItemTextStyle,
                                    ),
                                  );
                                }
                                final letters = List.generate(
                                  i,
                                  (x) => String.fromCharCode(65 + x),
                                ).join(', ');
                                return DropdownMenuItem<int>(
                                  value: i,
                                  child: Text(
                                    '$i (Open $letters)',
                                    style: _dropdownItemTextStyle,
                                  ),
                                );
                              }),
                              onChanged: _saving
                                  ? null
                                  : (v) => setState(() {
                                      _openCount = v ?? 0;
                                      if (!_nationalShowSectionKeyIsAvailable(
                                        _nationalShowSectionKey,
                                      )) {
                                        _nationalShowSectionKey = null;
                                      }
                                    }),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<int>(
                              initialValue: _youthCount,
                              style: _dropdownItemTextStyle,
                              dropdownColor: AppColors.surface,
                              iconEnabledColor: AppColors.muted,
                              iconDisabledColor: AppColors.muted,
                              decoration: const InputDecoration(
                                labelText: 'Youth shows',
                                border: OutlineInputBorder(),
                              ),
                              items: List.generate(6, (i) {
                                if (i == 0) {
                                  return const DropdownMenuItem<int>(
                                    value: 0,
                                    child: Text(
                                      '0 (No Youth shows)',
                                      style: _dropdownItemTextStyle,
                                    ),
                                  );
                                }
                                final letters = List.generate(
                                  i,
                                  (x) => String.fromCharCode(65 + x),
                                ).join(', ');
                                return DropdownMenuItem<int>(
                                  value: i,
                                  child: Text(
                                    '$i (Youth $letters)',
                                    style: _dropdownItemTextStyle,
                                  ),
                                );
                              }),
                              onChanged: _saving
                                  ? null
                                  : (v) => setState(() {
                                      _youthCount = v ?? 0;
                                      if (!_nationalShowSectionKeyIsAvailable(
                                        _nationalShowSectionKey,
                                      )) {
                                        _nationalShowSectionKey = null;
                                      }
                                    }),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'This will create sections like Open A / Open B / Youth A / Youth B.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .05),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'This creates Open A/B/C and Youth A/B/C sections. '
                              'Breed restrictions are managed per section in Show Settings → Modify Number of Shows.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      if (_msg != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: .08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.red.withValues(alpha: .25),
                            ),
                          ),
                          child: Text(
                            _msg!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: Tooltip(
                message: AppSession.isSupportMode
                    ? 'Exit impersonation to create a show.'
                    : 'Create show',
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryButton,
                    foregroundColor: AppColors.primaryButtonText,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: (_saving || AppSession.isSupportMode)
                      ? null
                      : _create,
                  child: Text(_saving ? 'Creating…' : 'Create'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
