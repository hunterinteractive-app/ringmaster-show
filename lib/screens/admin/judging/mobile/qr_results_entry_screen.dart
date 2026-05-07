// lib/screens/admin/judging/mobile/qr_results_entry_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ringmaster_show/screens/admin/results/admin_results_entry_screen.dart';

final supabase = Supabase.instance.client;

class QrResultsEntryScreen extends StatefulWidget {
  final String showId;
  final String sectionId;
  final String breedId;
  final String token;
  final String? varietyKey;
  final String? groupKey;
  final String? classSexLabel;

  const QrResultsEntryScreen({
    super.key,
    required this.showId,
    required this.sectionId,
    required this.breedId,
    required this.token,
    this.varietyKey,
    this.groupKey,
    this.classSexLabel,
  });

  @override
  State<QrResultsEntryScreen> createState() => _QrResultsEntryScreenState();
}

class _QrResultsEntryScreenState extends State<QrResultsEntryScreen> {
  bool _loading = true;
  String? _msg;

  String _showName = 'Show';
  String _sectionLabel = 'Section';

  List<Map<String, dynamic>> _entries = [];
  List<Map<String, dynamic>> _judges = [];
  final Map<String, String> _breedClassSystems = {};

  String _finalAwardMode = kDefaultFinalAwardMode;

  bool _showsByGroup = false;
  bool _showsByVariety = false;

  String? _writerName;
  String? _writerPhone;
  bool _qrLocked = false;
  DateTime? _qrLockStartsAt;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadQrLockStatus() async {
    final rows = await supabase
        .from('show_result_entry_locks')
        .select('lock_starts_at')
        .eq('show_id', widget.showId)
        .eq('section_id', widget.sectionId)
        .eq('breed_id', widget.breedId)
        .limit(1);

    if ((rows as List).isEmpty) {
      _qrLocked = false;
      _qrLockStartsAt = null;
      return;
    }

    final row = Map<String, dynamic>.from(rows.first as Map);
    final raw = (row['lock_starts_at'] ?? '').toString().trim();

    if (raw.isEmpty) {
      _qrLocked = false;
      _qrLockStartsAt = null;
      return;
    }

    final startsAt = DateTime.tryParse(raw)?.toUtc();
    final now = DateTime.now().toUtc();

    _qrLockStartsAt = startsAt;
    _qrLocked = startsAt != null && now.isAfter(startsAt);
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      await _loadShowAndSection();
      await _loadJudges();
      await _loadBreedClassSystems();
      await _loadShowSettings();
      await _loadEntries();
      await _loadQrLockStatus();

      if (_entries.isEmpty) {
        throw Exception('No matching entries were found for this QR code.');
      }

      _showsByGroup = _computeShowsByGroup(_entries);
      _showsByVariety = _computeShowsByVariety(_entries);

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _msg = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _loadShowAndSection() async {
    final show = await supabase
        .from('shows')
        .select('name')
        .eq('id', widget.showId)
        .maybeSingle();

    if (show == null) {
      throw Exception(
        'This show could not be found or is not available for QR results entry.',
      );
    }

    _showName = (show['name'] ?? 'Show').toString();

    final section = await supabase
        .from('show_sections')
        .select('letter, display_name')
        .eq('id', widget.sectionId)
        .maybeSingle();

    if (section == null) {
      throw Exception(
        'This show section could not be found or is not available for QR results entry.',
      );
    }

    final displayName = (section['display_name'] ?? '').toString().trim();
    final letter = (section['letter'] ?? '').toString().trim();

    _sectionLabel = displayName.isNotEmpty
        ? displayName
        : letter.isNotEmpty
            ? 'Show $letter'
            : 'Section';
  }

  Future<void> _loadJudges() async {
    final rows = await supabase
        .from('judge_assignments')
        .select(
          'id,judge_id,assignment_label,'
          'judges(id,display_name,name,first_name,last_name,judge_type,is_active,arba_judge_number)',
        )
        .eq('show_id', widget.showId);

    final result = <Map<String, dynamic>>[];

    for (final raw in (rows as List)) {
      final map = Map<String, dynamic>.from(raw as Map);
      final judge = map['judges'];

      final assignmentId = (map['id'] ?? '').toString().trim();
      final masterJudgeId = (map['judge_id'] ?? '').toString().trim();

      if (masterJudgeId.isEmpty) continue;

      String label = '';

      if (judge is Map) {
        final judgeMap = Map<String, dynamic>.from(judge);
        final displayName = (judgeMap['display_name'] ?? '').toString().trim();
        final name = (judgeMap['name'] ?? '').toString().trim();
        final first = (judgeMap['first_name'] ?? '').toString().trim();
        final last = (judgeMap['last_name'] ?? '').toString().trim();
        final arbaNumber =
            (judgeMap['arba_judge_number'] ?? '').toString().trim();

        final baseName = displayName.isNotEmpty
            ? displayName
            : name.isNotEmpty
                ? name
                : [first, last].where((x) => x.isNotEmpty).join(' ').trim();

        label = baseName.isNotEmpty ? baseName : masterJudgeId;

        if (arbaNumber.isNotEmpty && !label.contains('#$arbaNumber')) {
          label = '$label (#$arbaNumber)';
        }
      } else {
        label = (map['assignment_label'] ?? '').toString().trim();
        if (label.isEmpty) label = masterJudgeId;
      }

      if (!result.any((j) => (j['id'] ?? '').toString() == masterJudgeId)) {
        result.add({
          'id': masterJudgeId,
          'judge_id': masterJudgeId,
          'assignment_id': assignmentId,
          'name': label,
        });
      }
    }

    result.sort((a, b) {
      final an = (a['name'] ?? '').toString().toLowerCase();
      final bn = (b['name'] ?? '').toString().toLowerCase();
      return an.compareTo(bn);
    });

    _judges = result;
  }

  Future<void> _loadBreedClassSystems() async {
    final rows = await supabase
        .from('breeds')
        .select('name,class_system')
        .eq('is_active', true);

    _breedClassSystems.clear();

    for (final row in (rows as List).cast<Map<String, dynamic>>()) {
      final name = (row['name'] ?? '').toString().trim().toLowerCase();
      final classSystem =
          (row['class_system'] ?? 'four').toString().trim().toLowerCase();

      if (name.isNotEmpty) {
        _breedClassSystems[name] = classSystem;
      }
    }
  }

  Future<void> _loadShowSettings() async {
    final row = await supabase
        .from('shows')
        .select('final_award_mode')
        .eq('id', widget.showId)
        .single();

    _finalAwardMode =
        (row['final_award_mode'] ?? kDefaultFinalAwardMode).toString();
  }

  Future<void> _loadEntries() async {
    final rows = await supabase.rpc(
      'report_results_entry_rows',
      params: {
        'p_show_id': widget.showId,
        'p_section_id': widget.sectionId,
      },
    );

    var entries = (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    entries = entries.where((e) {
      final breed = (e['breed'] ?? e['breed_name'] ?? '').toString().trim();
      return breed.toLowerCase() == widget.breedId.trim().toLowerCase();
    }).toList();

    final groupKey = (widget.groupKey ?? '').trim();
    if (groupKey.isNotEmpty) {
      entries = entries.where((e) {
        final groupName = (
          e['group_name'] ??
          e['group_display_name'] ??
          e['group_label'] ??
          e['group'] ??
          e['group_code'] ??
          ''
        ).toString().trim();

        return groupName.toLowerCase() == groupKey.toLowerCase();
      }).toList();
    }

    final varietyKey = (widget.varietyKey ?? '').trim();
    if (varietyKey.isNotEmpty) {
      entries = entries.where((e) {
        final variety =
            (e['variety'] ?? e['variety_name'] ?? '').toString().trim();

        return variety.toLowerCase() == varietyKey.toLowerCase();
      }).toList();
    }

    final classSexLabel = (widget.classSexLabel ?? '').trim();
    if (classSexLabel.isNotEmpty) {
      entries = entries.where((e) {
        return _classSexLabelFromEntry(e).toLowerCase() ==
            classSexLabel.toLowerCase();
      }).toList();
    }

    final entryIds = entries
        .map((e) => (e['entry_id'] ?? '').toString())
        .where((x) => x.isNotEmpty)
        .toList();

    final awardsByEntryId = <String, List<String>>{};

    if (entryIds.isNotEmpty) {
      for (var i = 0; i < entryIds.length; i += 100) {
        final chunk = entryIds.skip(i).take(100).toList();

        final awardRows = await supabase
            .from('entry_awards')
            .select('entry_id,award_code')
            .eq('show_id', widget.showId)
            .inFilter('entry_id', chunk);

        for (final row in (awardRows as List).cast<Map<String, dynamic>>()) {
          final entryId = (row['entry_id'] ?? '').toString().trim();
          final award = (row['award_code'] ?? '').toString().trim();

          if (entryId.isEmpty || award.isEmpty) continue;

          awardsByEntryId.putIfAbsent(entryId, () => <String>[]);
          awardsByEntryId[entryId]!.add(award);
        }
      }
    }

    for (final e in entries) {
      final id = (e['entry_id'] ?? '').toString();

      e['id'] ??= e['entry_id'];
      e['breed'] ??= e['breed_name'];
      e['variety'] ??= e['variety_name'];
      e['animal_name'] ??= '';
      e['_awards'] = awardsByEntryId[id] ?? <String>[];

      final normalizedGroup = (
        e['group_name'] ??
        e['group_display_name'] ??
        e['group_label'] ??
        e['group'] ??
        e['group_code']
      )?.toString().trim();

      e['group_name'] =
          (normalizedGroup == null || normalizedGroup.isEmpty)
              ? null
              : normalizedGroup;
    }

    _entries = entries;
  }

  bool _computeShowsByGroup(List<Map<String, dynamic>> entries) {
    final usesGroups = entries.any((e) => e['uses_group_awards'] == true);
    if (!usesGroups) return false;

    return entries.any((e) {
      final groupName = (
        e['group_name'] ??
        e['group_display_name'] ??
        e['group_label'] ??
        e['group'] ??
        e['group_code'] ??
        ''
      ).toString().trim();

      return groupName.isNotEmpty;
    });
  }

  bool _computeShowsByVariety(List<Map<String, dynamic>> entries) {
    return entries.any((e) => e['uses_variety_awards'] == true);
  }

  String _classSexLabelFromEntry(Map<String, dynamic> e) {
    final rawClass = (e['class_name'] ?? '').toString().trim();
    final sex = (e['sex'] ?? '').toString().trim();

    String ageClassOnly(String raw) {
      final s = raw.trim();
      if (s.isEmpty) return '';

      final lower = s.toLowerCase();

      if (lower.contains('pre-junior') ||
          lower.contains('pre junior') ||
          lower.contains('prejunior') ||
          lower.startsWith('pre jr') ||
          lower.startsWith('pre-jr')) {
        return 'Pre-Junior';
      }

      if (lower.contains('senior') || lower.startsWith('sr')) return 'Senior';
      if (lower.contains('intermediate') || lower.startsWith('int')) {
        return 'Intermediate';
      }
      if (lower.contains('junior') || lower.startsWith('jr')) return 'Junior';
      if (lower.contains('open')) return 'Open';

      return s;
    }

    final cls = ageClassOnly(rawClass);

    return [
      if (cls.isNotEmpty) cls,
      if (sex.isNotEmpty) sex,
    ].join(' ');
  }

  Future<void> _applyJudgeToEntries(
    List<Map<String, dynamic>> entries,
    String? judgeId,
  ) async {
    if (_qrLocked) {
      throw Exception(
        'This QR results link is locked because breed results have already been submitted.',
      );
    }

    final ids = entries
        .map((e) => (e['entry_id'] ?? e['id'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toSet()
        .toList();

    if (ids.isEmpty) return;

    final normalizedJudgeId =
        (judgeId == null || judgeId.trim().isEmpty) ? null : judgeId.trim();

    for (var i = 0; i < ids.length; i += 100) {
      final chunk = ids.skip(i).take(100).toList();

      await supabase
          .from('entries')
          .update({
            'judged_by_show_judge_id': normalizedJudgeId,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .inFilter('id', chunk);
    }

    for (final e in _entries) {
      final id = (e['entry_id'] ?? e['id'] ?? '').toString().trim();
      if (ids.contains(id)) {
        e['judged_by_show_judge_id'] = normalizedJudgeId;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF4F6FB),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_msg != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF4F6FB),
        appBar: AppBar(
          backgroundColor: const Color(0xFF11285A),
          foregroundColor: Colors.white,
          title: const Text('QR Results Entry'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  _msg!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_qrLocked) {
      return Scaffold(
        backgroundColor: const Color(0xFFF4F6FB),
        appBar: AppBar(
          backgroundColor: const Color(0xFF11285A),
          foregroundColor: Colors.white,
          title: const Text('QR Results Entry'),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Card(
              elevation: 0,
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'This QR results link is locked because breed results have already been submitted.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_writerName == null || _writerPhone == null) {
      return _QrWriterInfoScreen(
        showName: _showName,
        sectionLabel: _sectionLabel,
        breed: widget.breedId,
        onContinue: (name, phone) {
          setState(() {
            _writerName = name;
            _writerPhone = phone;
          });
        },
      );
    }

    return _QrBreedDrilldownScreen(
      showId: widget.showId,
      showName: _showName,
      sectionLabel: _sectionLabel,
      breed: widget.breedId,
      entries: _entries,
      judges: _judges,
      breedClassSystems: _breedClassSystems,
      finalAwardMode: _finalAwardMode,
      showsByGroup: _showsByGroup,
      showsByVariety: _showsByVariety,
      writerName: _writerName!,
      writerPhone: _writerPhone!,
      onBulkJudgeApply: _applyJudgeToEntries,
    );
  }
}

class _QrBreedDrilldownScreen extends StatefulWidget {
  final String showId;
  final String showName;
  final String sectionLabel;
  final String breed;
  final List<Map<String, dynamic>> entries;
  final List<Map<String, dynamic>> judges;
  final Map<String, String> breedClassSystems;
  final String finalAwardMode;
  final bool showsByGroup;
  final bool showsByVariety;
  final String writerName;
  final String writerPhone;
  final Future<void> Function(
    List<Map<String, dynamic>> entries,
    String? judgeId,
  ) onBulkJudgeApply;

  const _QrBreedDrilldownScreen({
    required this.showId,
    required this.showName,
    required this.sectionLabel,
    required this.breed,
    required this.entries,
    required this.judges,
    required this.breedClassSystems,
    required this.finalAwardMode,
    required this.showsByGroup,
    required this.showsByVariety,
    required this.writerName,
    required this.writerPhone,
    required this.onBulkJudgeApply,
  });

  @override
  State<_QrBreedDrilldownScreen> createState() =>
      _QrBreedDrilldownScreenState();
}

class _QrBreedDrilldownScreenState extends State<_QrBreedDrilldownScreen> {
  late List<Map<String, dynamic>> _entries;
  bool _savingJudge = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    _entries = [...widget.entries];
  }

  String _groupName(Map<String, dynamic> e) {
    return (
      e['group_name'] ??
      e['group_display_name'] ??
      e['group_label'] ??
      e['group'] ??
      e['group_code'] ??
      ''
    ).toString().trim();
  }

  String _varietyName(Map<String, dynamic> e) {
    return (e['variety'] ?? e['variety_name'] ?? '').toString().trim();
  }

  String _classSexLabelFromEntry(Map<String, dynamic> e) {
    final rawClass = (e['class_name'] ?? '').toString().trim();
    final sex = (e['sex'] ?? '').toString().trim();

    String ageClassOnly(String raw) {
      final s = raw.trim();
      if (s.isEmpty) return '';

      final lower = s.toLowerCase();

      if (lower.contains('pre-junior') ||
          lower.contains('pre junior') ||
          lower.contains('prejunior') ||
          lower.startsWith('pre jr') ||
          lower.startsWith('pre-jr')) {
        return 'Pre-Junior';
      }

      if (lower.contains('senior') || lower.startsWith('sr')) return 'Senior';
      if (lower.contains('intermediate') || lower.startsWith('int')) {
        return 'Intermediate';
      }
      if (lower.contains('junior') || lower.startsWith('jr')) return 'Junior';
      if (lower.contains('open')) return 'Open';

      return s;
    }

    final cls = ageClassOnly(rawClass);

    return [
      if (cls.isNotEmpty) cls,
      if (sex.isNotEmpty) sex,
    ].join(' ');
  }

  String? _singleJudgeIdFromEntries(List<Map<String, dynamic>> entries) {
    final ids = entries
        .map((e) => (e['judged_by_show_judge_id'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toSet();

    if (ids.length == 1) return ids.first;
    return null;
  }

  String _judgeNameById(String? judgeId) {
    if (judgeId == null || judgeId.isEmpty) return '';

    for (final j in widget.judges) {
      final savedJudgeId = (j['id'] ?? '').toString().trim();
      final masterJudgeId = (j['judge_id'] ?? '').toString().trim();
      final assignmentId = (j['assignment_id'] ?? '').toString().trim();

      if (savedJudgeId == judgeId ||
          masterJudgeId == judgeId ||
          assignmentId == judgeId) {
        return (j['name'] ?? '').toString().trim();
      }
    }

    return '';
  }

  String _judgeSummary(List<Map<String, dynamic>> entries) {
    final id = _singleJudgeIdFromEntries(entries);
    if (id == null || id.isEmpty) return 'Judge: Not set';

    final name = _judgeNameById(id);
    return name.isEmpty ? 'Judge: Not set' : 'Judge: $name';
  }

  bool _isFurOrWoolClass(List<Map<String, dynamic>> entries) {
    return entries.any((e) {
      final rawClass = (e['class_name'] ?? '').toString().toLowerCase();
      final rawGroup = (e['group_name'] ?? '').toString().toLowerCase();
      final rawVariety = (e['variety'] ?? '').toString().toLowerCase();

      return rawClass.contains('fur') ||
          rawClass.contains('wool') ||
          rawGroup.contains('fur') ||
          rawGroup.contains('wool') ||
          rawVariety.contains('fur') ||
          rawVariety.contains('wool');
    });
  }

  Map<String, List<Map<String, dynamic>>> _groupBy(
    List<Map<String, dynamic>> source,
    String Function(Map<String, dynamic>) keyBuilder,
  ) {
    final out = <String, List<Map<String, dynamic>>>{};

    for (final e in source) {
      final key = keyBuilder(e).trim();
      final safeKey = key.isEmpty ? '(Unknown)' : key;
      out.putIfAbsent(safeKey, () => <Map<String, dynamic>>[]);
      out[safeKey]!.add(e);
    }

    return out;
  }

  void _applyJudgeToLocalEntries(
    Iterable<String> ids,
    String? judgeId,
  ) {
    final idSet = ids.toSet();

    for (final e in _entries) {
      final id = (e['entry_id'] ?? e['id'] ?? '').toString().trim();
      if (idSet.contains(id)) {
        e['judged_by_show_judge_id'] = judgeId;
      }
    }
  }

  Future<void> _applyJudgeAndRefresh(
    List<Map<String, dynamic>> entries,
    String? judgeId,
  ) async {
    setState(() {
      _savingJudge = true;
      _msg = null;
    });

    try {
      final ids = entries
          .map((e) => (e['entry_id'] ?? e['id'] ?? '').toString().trim())
          .where((x) => x.isNotEmpty)
          .toSet()
          .toList();

      await widget.onBulkJudgeApply(entries, judgeId);

      final normalizedJudgeId =
          (judgeId == null || judgeId.trim().isEmpty) ? null : judgeId.trim();

      _applyJudgeToLocalEntries(ids, normalizedJudgeId);

      if (!mounted) return;
      setState(() {
        _savingJudge = false;
        _msg = 'Judge updated.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingJudge = false;
        _msg = 'Judge update failed: $e';
      });
    }
  }

  Widget _judgeDropdown({
    required String labelText,
    required List<Map<String, dynamic>> entries,
    required String keyPrefix,
  }) {
    final selectedJudgeId = _singleJudgeIdFromEntries(entries);

    return DropdownButtonFormField<String>(
      key: ValueKey('$keyPrefix-${selectedJudgeId ?? 'mixed'}-${entries.length}'),
      value: selectedJudgeId,
      decoration: InputDecoration(labelText: labelText),
      items: [
        const DropdownMenuItem<String>(
          value: '',
          child: Text('(Not set)'),
        ),
        ...widget.judges.map(
          (j) => DropdownMenuItem<String>(
            value: (j['id'] ?? '').toString(),
            child: Text((j['name'] ?? '').toString()),
          ),
        ),
      ],
      onChanged: _savingJudge
          ? null
          : (v) {
              _applyJudgeAndRefresh(
                entries,
                (v == null || v.isEmpty) ? null : v,
              );
            },
    );
  }

  Widget _buildList({
    required String title,
    required Map<String, List<Map<String, dynamic>>> grouped,
    required void Function(String label, List<Map<String, dynamic>> entries)
        onTap,
    String? judgeLabel,
  }) {
    final labels = grouped.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final allRows = grouped.values.expand((x) => x).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF11285A),
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: labels.length,
        itemBuilder: (context, i) {
        
          final label = labels[i];
          final rows = grouped[label] ?? const <Map<String, dynamic>>[];

          return Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${rows.length} entr${rows.length == 1 ? 'y' : 'ies'} • ${_judgeSummary(rows)}',
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => onTap(label, rows),
                  ),
                  const SizedBox(height: 10),
                  _judgeDropdown(
                    labelText: judgeLabel ?? 'Judge for this item',
                    entries: rows,
                    keyPrefix: 'item-judge-$title-$label',
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _openNextLevel(List<Map<String, dynamic>> entries) {
    if (widget.showsByGroup) {
      final grouped = _groupBy(entries, _groupName);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _buildList(
            title: widget.breed,
            grouped: grouped,
            judgeLabel: 'Judge for this group',
            onTap: (label, rows) {
              if (widget.showsByVariety) {
                final byVariety = _groupBy(rows, _varietyName);

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _buildList(
                      title: label,
                      grouped: byVariety,
                      judgeLabel: 'Judge for this variety',
                      onTap: (varietyLabel, varietyRows) {
                        _openClassList(varietyLabel, varietyRows);
                      },
                    ),
                  ),
                );
              } else {
                _openClassList(label, rows);
              }
            },
          ),
        ),
      );
      return;
    }

    if (widget.showsByVariety) {
      final grouped = _groupBy(entries, _varietyName);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _buildList(
            title: widget.breed,
            grouped: grouped,
            judgeLabel: 'Judge for this variety',
            onTap: (label, rows) {
              _openClassList(label, rows);
            },
          ),
        ),
      );
      return;
    }

    _openClassList(widget.breed, entries);
  }

  void _openClassList(String title, List<Map<String, dynamic>> entries) {
    final grouped = _groupBy(entries, _classSexLabelFromEntry);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _buildList(
          title: title,
          grouped: grouped,
          judgeLabel: 'Judge for this class',
          onTap: (label, rows) {
            _openClass(
              label: label,
              entries: rows,
              showsByGroup: widget.showsByGroup,
              showsByVariety: widget.showsByVariety,
            );
          },
        ),
      ),
    );
  }

  Future<void> _openClass({
    required String label,
    required List<Map<String, dynamic>> entries,
    required bool showsByGroup,
    required bool showsByVariety,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultsAnimalsScreen(
          showId: widget.showId,
          showName: widget.showName,
          sectionLabel: widget.sectionLabel,
          breed: widget.breed,
          variety: entries.isEmpty ? '' : _varietyName(entries.first),
          classSexLabel: label,
          isFurOrWoolClass: _isFurOrWoolClass(entries),
          entries: entries,
          judges: widget.judges,
          onBulkJudgeApply: _applyJudgeAndRefresh,
          initialJudgeId: _singleJudgeIdFromEntries(entries),
          breedClassSystems: widget.breedClassSystems,
          finalAwardMode: widget.finalAwardMode,
          showsByGroup: showsByGroup,
          showsByVariety: showsByVariety,
          writerName: widget.writerName,
          writerPhone: widget.writerPhone,
          isQrEntryMode: true,
        ),
      ),
    );

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final exhibitorCount = _entries
        .map((e) => (e['exhibitor_id'] ?? '').toString())
        .where((x) => x.isNotEmpty)
        .toSet()
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF11285A),
        foregroundColor: Colors.white,
        title: const Text('QR Results Entry'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.showName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${widget.sectionLabel} • ${widget.breed}',
                    style: const TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _pill('${_entries.length} entries'),
                      _pill('$exhibitorCount exhibitors'),
                      _pill(_judgeSummary(_entries)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _judgeDropdown(
                    labelText: 'Judge for this breed',
                    entries: _entries,
                    keyPrefix: 'breed-judge-${widget.breed}',
                  ),
                  if (_msg != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _msg!,
                      style: TextStyle(
                        color: _msg == 'Judge updated.'
                            ? Colors.green
                            : Colors.red,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              title: Text(
                widget.breed,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Tap to choose group, variety, or class.'),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openNextLevel(_entries),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.05),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _QrWriterInfoScreen extends StatefulWidget {
  final String showName;
  final String sectionLabel;
  final String breed;
  final void Function(String name, String phone) onContinue;

  const _QrWriterInfoScreen({
    required this.showName,
    required this.sectionLabel,
    required this.breed,
    required this.onContinue,
  });

  @override
  State<_QrWriterInfoScreen> createState() => _QrWriterInfoScreenState();
}

class _QrWriterInfoScreenState extends State<_QrWriterInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Writer name is required.';
    if (text.length < 2) return 'Enter a full name.';
    return null;
  }

  String? _validatePhone(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Phone number is required.';
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 10) return 'Enter a valid phone number.';
    return null;
  }

  void _continue() {
    if (!_formKey.currentState!.validate()) return;

    widget.onContinue(
      _nameController.text.trim(),
      _phoneController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF11285A),
        foregroundColor: Colors.white,
        title: const Text('QR Results Entry'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.showName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${widget.sectionLabel} • ${widget.breed}',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Writer Information',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Enter the name and phone number of the person recording results. This is saved with the results in case the secretary has questions.',
                      style: TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _nameController,
                      validator: _validateName,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Writer name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneController,
                      validator: _validatePhone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _continue(),
                      decoration: const InputDecoration(
                        labelText: 'Phone number',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _continue,
                      icon: const Icon(Icons.chevron_right),
                      label: const Text('Continue to Results'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
