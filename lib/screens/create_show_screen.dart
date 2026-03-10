import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class CreateShowScreen extends StatefulWidget {
  const CreateShowScreen({super.key});

  @override
  State<CreateShowScreen> createState() => _CreateShowScreenState();
}

class _CreateShowScreenState extends State<CreateShowScreen> {
  final _name = TextEditingController();
  final _location = TextEditingController();
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now();
  bool _published = false;

  // NEW: sections (Open A/B/C..., Youth A/B/C...)
  int _openCount = 1;
  int _youthCount = 0;

  // NEW: entry deadline/window
  DateTime? _entryCloseAt; // optional

  // Single breed show
  bool _isSingleBreedShow = false;
  String? _singleBreedId;
  bool _loadingBreeds = false;
  List<Map<String, dynamic>> _breedOptions = [];

  bool _saving = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    _loadBreeds();
  }

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    super.dispose();
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
      if (isStart) _start = picked;
      if (!isStart) _end = picked;
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
    if (_end.isBefore(_start)) {
      setState(() => _msg = 'End date cannot be before start date.');
      return false;
    }

    // Require at least one section
    if (_openCount == 0 && _youthCount == 0) {
      setState(() => _msg = 'Select at least one show type (Open and/or Youth).');
      return false;
    }

    if (_isSingleBreedShow && (_singleBreedId == null || _singleBreedId!.isEmpty)) {
      setState(() => _msg = 'Select the breed for this single-breed show.');
      return false;
    }

    // Entry close should not be after show end (optional safety)
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
        final letter = String.fromCharCode(65 + i); // A, B, C, D...
        rows.add({
          'show_id': showId,
          'kind': kind, // open | youth
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

  Future<void> _create() async {
    if (!_validate()) return;

    final user = supabase.auth.currentUser!;

    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      final inserted = await supabase
          .from('shows')
          .insert({
            'created_by': user.id,
            'name': _name.text.trim(),
            'start_date': _start.toIso8601String().substring(0, 10),
            'end_date': _end.toIso8601String().substring(0, 10),
            'location_name': _location.text.trim(),
            'timezone': 'America/Indiana/Indianapolis',
            'is_published': _published,

            // entry deadline/window (store as timestamptz ISO UTC)
            'entry_close_at': _entryCloseAt?.toUtc().toIso8601String(),

            // single-breed fields
            'is_single_breed_show': _isSingleBreedShow,
            'single_breed_id': _isSingleBreedShow ? _singleBreedId : null,
          })
          .select('id')
          .single();

      final showId = inserted['id'].toString();

      final sectionRows = _buildSectionRows(showId);
      if (sectionRows.isNotEmpty) {
        await supabase.from('show_sanctions').insert(sectionRows);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Create failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Show')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _name,
              enabled: !_saving,
              decoration: const InputDecoration(labelText: 'Show name (required)'),
            ),
            TextField(
              controller: _location,
              enabled: !_saving,
              decoration: const InputDecoration(labelText: 'Location (required)'),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(child: Text('Start: ${_start.toIso8601String().substring(0, 10)}')),
                TextButton(onPressed: _saving ? null : () => _pickDate(true), child: const Text('Pick')),
              ],
            ),
            Row(
              children: [
                Expanded(child: Text('End: ${_end.toIso8601String().substring(0, 10)}')),
                TextButton(onPressed: _saving ? null : () => _pickDate(false), child: const Text('Pick')),
              ],
            ),

            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Published'),
              value: _published,
              onChanged: _saving ? null : (v) => setState(() => _published = v),
            ),

            const Divider(height: 24),

            // Entry deadline picker (added back)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Entry deadline',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('Entry close: ${_fmtDateTime(_entryCloseAt)}')),
                TextButton(
                  onPressed: _saving ? null : _pickEntryCloseAt,
                  child: const Text('Pick'),
                ),
                TextButton(
                  onPressed: _saving ? null : () => setState(() => _entryCloseAt = null),
                  child: const Text('Clear'),
                ),
              ],
            ),

            const Divider(height: 24),

            // Show sections selector
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Show Types / Sections',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),

            DropdownButtonFormField<int>(
              value: _openCount,
              decoration: const InputDecoration(labelText: 'Open shows'),
              items: List.generate(6, (i) {
                if (i == 0) {
                  return const DropdownMenuItem(
                    value: 0,
                    child: Text('0 (No Open shows)'),
                  );
                }
                final letters = List.generate(i, (x) => String.fromCharCode(65 + x)).join(', ');
                return DropdownMenuItem(
                  value: i,
                  child: Text('$i (Open $letters)'),
                );
              }),
              onChanged: _saving ? null : (v) => setState(() => _openCount = v ?? 0),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: _youthCount,
              decoration: const InputDecoration(labelText: 'Youth shows'),
              items: List.generate(6, (i) {
                if (i == 0) {
                  return const DropdownMenuItem(
                    value: 0,
                    child: Text('0 (No Youth shows)'),
                  );
                }
                final letters = List.generate(i, (x) => String.fromCharCode(65 + x)).join(', ');
                return DropdownMenuItem(
                  value: i,
                  child: Text('$i (Youth $letters)'),
                );
              }),
              onChanged: _saving ? null : (v) => setState(() => _youthCount = v ?? 0),
            ),

            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'This will create sections like Open A / Open B / Youth A / Youth B.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),

            const Divider(height: 24),

            // Single-breed show config
            SwitchListTile(
              title: const Text('Single breed show'),
              subtitle: const Text('Only one breed can be entered for this show.'),
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
              const SizedBox(height: 8),
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
                onChanged: _saving ? null : (v) => setState(() => _singleBreedId = v),
                decoration: const InputDecoration(
                  labelText: 'Allowed breed (required)',
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Tip: Breed Settings can auto-lock to this breed.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],

            if (_msg != null) ...[
              const SizedBox(height: 8),
              Text(_msg!, style: const TextStyle(color: Colors.red)),
            ],

            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _create,
                child: Text(_saving ? 'Creating…' : 'Create'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}