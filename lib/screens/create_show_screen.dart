import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/club_service.dart';

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

  int _openCount = 1;
  int _youthCount = 0;

  DateTime? _entryCloseAt;

  bool _isSingleBreedShow = false;
  String? _singleBreedId;
  bool _loadingBreeds = false;
  List<Map<String, dynamic>> _breedOptions = [];

  List<Map<String, dynamic>> _clubs = [];
  String? _selectedClubId;
  String? _selectedClubName;
  bool _loadingClubs = false;

  bool _hasLockedHostingClub = false;
  bool _canSwitchHostingClub = false; // future paid add-on

  bool _saving = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    _loadBreeds();
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
          }

          final selected = _clubs.cast<Map<String, dynamic>?>().firstWhere(
                (club) => club?['id']?.toString() == _selectedClubId,
                orElse: () => _clubs.first,
              );

          _selectedClubId = selected?['id']?.toString();
          _selectedClubName = selected?['name']?.toString() ?? '';
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

  Future<void> _loadBreeds() async {
    setState(() => _loadingBreeds = true);

    try {
      final List data = await supabase
          .from('breeds')
          .select('id,name,species,is_active')
          .eq('is_active', true)
          .order('species')
          .order('name');

      if (!mounted) return;
      setState(() {
        _breedOptions = data.cast<Map<String, dynamic>>();
        _loadingBreeds = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingBreeds = false;
        _msg = 'Failed to load breeds: $e';
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
    final user = supabase.auth.currentUser;
    if (user == null) {
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
      setState(() => _msg = 'Select at least one show type (Open and/or Youth).');
      return false;
    }

    if (_isSingleBreedShow &&
        (_singleBreedId == null || _singleBreedId!.isEmpty)) {
      setState(() => _msg = 'Select the breed for this single-breed show.');
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
        });
      }
    }

    addSections(kind: 'open', count: _openCount, baseSort: 10, label: 'Open');
    addSections(kind: 'youth', count: _youthCount, baseSort: 100, label: 'Youth');

    return rows;
  }

  Future<void> _ensureShowAdmin({
    required String showId,
    required String userId,
  }) async {
    final existing = await supabase
        .from('show_admins')
        .select('show_id')
        .eq('show_id', showId)
        .eq('user_id', userId)
        .maybeSingle();

    if (existing == null) {
      await supabase.from('show_admins').insert({
        'show_id': showId,
        'user_id': userId,
      });
    }
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

    final user = supabase.auth.currentUser!;

    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      String? clubId = _selectedClubId;
      String? clubName = _selectedClubName;

      if (!_hasLockedHostingClub) {
        final createdClub = await _createFirstClubForUser(
          userId: user.id,
          clubName: _hostingClubName.text.trim(),
        );

        clubId = createdClub['id']?.toString();
        clubName = createdClub['name']?.toString();

        _selectedClubId = clubId;
        _selectedClubName = clubName;
        _hasLockedHostingClub = true;

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

      await supabase.from('shows').update({
        'timezone': 'America/Indiana/Indianapolis',
        'is_published': _published,
        'entry_close_at': _entryCloseAt?.toUtc().toIso8601String(),
        'is_single_breed_show': _isSingleBreedShow,
        'single_breed_id': _isSingleBreedShow ? _singleBreedId : null,
        'club_id': clubId,
        'club_name': clubName,
      }).eq('id', showId);

      final sectionRows = _buildSectionRows(showId);
      if (sectionRows.isNotEmpty) {
        await supabase.from('show_sections').insert(sectionRows);
      }

      await _ensureShowAdmin(showId: showId, userId: user.id);

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

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 70,
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: 12),
            Image.asset(
              'assets/images/ringmaster_show_logo.png',
              height: 42,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Create Show',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF11285A),
              Color(0xFF0B1C43),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF4F6FB),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(.05),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                TextField(
                                  controller: _name,
                                  enabled: !_saving,
                                  decoration: const InputDecoration(
                                    labelText: 'Show name (required)',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _location,
                                  enabled: !_saving,
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
                                    decoration: const InputDecoration(
                                      labelText: 'Hosting Club Name (required)',
                                      border: OutlineInputBorder(),
                                      helperText:
                                          'This will be saved as your default hosting club.',
                                    ),
                                  ),
                                ] else ...[
                                  DropdownButtonFormField<String>(
                                    value: selectedClubExists ? _selectedClubId : null,
                                    decoration: InputDecoration(
                                      labelText: 'Hosting Club',
                                      border: const OutlineInputBorder(),
                                      helperText: _canSwitchHostingClub
                                          ? 'You can switch hosting clubs.'
                                          : 'Locked to your account. Upgrade to Multi-Club Hosting to change this.',
                                    ),
                                    items: _clubs.map((club) {
                                      return DropdownMenuItem<String>(
                                        value: club['id'].toString(),
                                        child: Text(
                                          (club['name'] ?? 'Club').toString(),
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

                                                  final selected =
                                                      _clubs.firstWhere(
                                                    (c) =>
                                                        c['id'].toString() ==
                                                        value,
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
                                        'Start: ${_start.toIso8601String().substring(0, 10)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed:
                                          _saving ? null : () => _pickDate(true),
                                      child: const Text('Pick'),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'End: ${_end.toIso8601String().substring(0, 10)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed:
                                          _saving ? null : () => _pickDate(false),
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
                                  color: Colors.black.withOpacity(.05),
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
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed:
                                          _saving ? null : _pickEntryCloseAt,
                                      child: const Text('Pick'),
                                    ),
                                    TextButton(
                                      onPressed: _saving
                                          ? null
                                          : () => setState(() => _entryCloseAt = null),
                                      child: const Text('Clear'),
                                    ),
                                  ],
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
                                  color: Colors.black.withOpacity(.05),
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
                                  value: _openCount,
                                  decoration: const InputDecoration(
                                    labelText: 'Open shows',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: List.generate(6, (i) {
                                    if (i == 0) {
                                      return const DropdownMenuItem<int>(
                                        value: 0,
                                        child: Text('0 (No Open shows)'),
                                      );
                                    }
                                    final letters = List.generate(
                                      i,
                                      (x) => String.fromCharCode(65 + x),
                                    ).join(', ');
                                    return DropdownMenuItem<int>(
                                      value: i,
                                      child: Text('$i (Open $letters)'),
                                    );
                                  }),
                                  onChanged: _saving
                                      ? null
                                      : (v) => setState(() => _openCount = v ?? 0),
                                ),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<int>(
                                  value: _youthCount,
                                  decoration: const InputDecoration(
                                    labelText: 'Youth shows',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: List.generate(6, (i) {
                                    if (i == 0) {
                                      return const DropdownMenuItem<int>(
                                        value: 0,
                                        child: Text('0 (No Youth shows)'),
                                      );
                                    }
                                    final letters = List.generate(
                                      i,
                                      (x) => String.fromCharCode(65 + x),
                                    ).join(', ');
                                    return DropdownMenuItem<int>(
                                      value: i,
                                      child: Text('$i (Youth $letters)'),
                                    );
                                  }),
                                  onChanged: _saving
                                      ? null
                                      : (v) => setState(() => _youthCount = v ?? 0),
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
                                  color: Colors.black.withOpacity(.05),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('Single breed show'),
                                  subtitle: const Text(
                                    'Only one breed can be entered for this show.',
                                  ),
                                  value: _isSingleBreedShow,
                                  onChanged: _saving
                                      ? null
                                      : (v) {
                                          setState(() {
                                            _isSingleBreedShow = v;
                                            if (!v) _singleBreedId = null;
                                          });
                                        },
                                ),
                                if (_isSingleBreedShow) ...[
                                  if (_loadingBreeds) const LinearProgressIndicator(),
                                  const SizedBox(height: 12),
                                  DropdownButtonFormField<String>(
                                    value: _singleBreedId,
                                    items: _breedOptions.map((b) {
                                      final label =
                                          '${(b['species'] ?? '').toString().toUpperCase()} — ${(b['name'] ?? '').toString()}';
                                      return DropdownMenuItem<String>(
                                        value: b['id'].toString(),
                                        child: Text(label),
                                      );
                                    }).toList(),
                                    onChanged: _saving
                                        ? null
                                        : (v) => setState(() => _singleBreedId = v),
                                    decoration: const InputDecoration(
                                      labelText: 'Allowed breed (required)',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Tip: Breed Settings can auto-lock to this breed.',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (_msg != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.red.withOpacity(.25),
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
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFD4A623),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: _saving ? null : _create,
                      child: Text(_saving ? 'Creating…' : 'Create'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}