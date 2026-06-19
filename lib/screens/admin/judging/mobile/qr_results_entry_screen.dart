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
  String _sectionKind = 'open';
  String _coopNumberingMode = 'separate';

  List<Map<String, dynamic>> _entries = [];
  List<Map<String, dynamic>> _judges = [];
  final Map<String, String> _breedClassSystems = {};

  String _finalAwardMode = kDefaultFinalAwardMode;

  bool _showsByGroup = false;
  bool _showsByVariety = false;

  static String? _rememberedWriterName;
  static String? _rememberedWriterPhone;

  String? _writerName;
  String? _writerPhone;
  bool _qrLocked = false;
  DateTime? _qrLockStartsAt;

  @override
  void initState() {
    super.initState();
    _writerName = _rememberedWriterName;
    _writerPhone = _rememberedWriterPhone;
    _loadAll();
  }

  @override
  void didUpdateWidget(covariant QrResultsEntryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final qrTargetChanged = oldWidget.showId != widget.showId ||
        oldWidget.sectionId != widget.sectionId ||
        oldWidget.breedId != widget.breedId ||
        oldWidget.token != widget.token ||
        oldWidget.varietyKey != widget.varietyKey ||
        oldWidget.groupKey != widget.groupKey ||
        oldWidget.classSexLabel != widget.classSexLabel;

    if (!qrTargetChanged) return;

    _writerName = _rememberedWriterName;
    _writerPhone = _rememberedWriterPhone;
    _qrLocked = false;
    _qrLockStartsAt = null;
    _entries = [];
    _judges = [];
    _breedClassSystems.clear();
    _showsByGroup = false;
    _showsByVariety = false;
    _showName = 'Show';
    _sectionLabel = 'Section';
    _sectionKind = 'open';
    _coopNumberingMode = 'separate';
    _finalAwardMode = kDefaultFinalAwardMode;

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
        .select('letter, display_name, kind')
        .eq('id', widget.sectionId)
        .maybeSingle();

    if (section == null) {
      throw Exception(
        'This show section could not be found or is not available for QR results entry.',
      );
    }

    final displayName = (section['display_name'] ?? '').toString().trim();
    final letter = (section['letter'] ?? '').toString().trim();
    _sectionKind =
        (section['kind'] ?? 'open').toString().trim().toLowerCase();

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
        .select('final_award_mode, coop_numbering_mode')
        .eq('id', widget.showId)
        .single();

    _finalAwardMode =
        (row['final_award_mode'] ?? kDefaultFinalAwardMode).toString();
    _coopNumberingMode =
        (row['coop_numbering_mode'] ?? 'separate')
            .toString()
            .trim()
            .toLowerCase();
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
        .map((e) => (e['entry_id'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toSet()
        .toList();

    final animalIdByEntryId = <String, String>{};
    for (var i = 0; i < entryIds.length; i += 100) {
      final chunk = entryIds.skip(i).take(100).toList();
      if (chunk.isEmpty) continue;

      final sourceRows = await supabase
          .from('entries')
          .select('id, animal_id')
          .inFilter('id', chunk);

      for (final raw in sourceRows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final entryId = (row['id'] ?? '').toString().trim();
        final animalId = (row['animal_id'] ?? '').toString().trim();
        if (entryId.isNotEmpty && animalId.isNotEmpty) {
          animalIdByEntryId[entryId] = animalId;
        }
      }
    }

    final animalIds = animalIdByEntryId.values.toSet().toList();
    final coopNumberByAnimalAndScope = <String, String>{};

    for (var i = 0; i < animalIds.length; i += 100) {
      final chunk = animalIds.skip(i).take(100).toList();
      if (chunk.isEmpty) continue;

      final coopRows = await supabase
          .from('show_animal_coop_numbers')
          .select('animal_id, scope, coop_number')
          .eq('show_id', widget.showId)
          .inFilter('animal_id', chunk);

      for (final raw in coopRows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final animalId = (row['animal_id'] ?? '').toString().trim();
        final scope = (row['scope'] ?? '').toString().trim().toLowerCase();
        final coopNumber = (row['coop_number'] ?? '').toString().trim();
        if (animalId.isEmpty || scope.isEmpty) continue;
        coopNumberByAnimalAndScope['$animalId|$scope'] = coopNumber;
      }
    }

    final coopScope =
        _coopNumberingMode == 'combined' ? 'all' : _sectionKind;

    for (final entry in entries) {
      final entryId = (entry['entry_id'] ?? '').toString().trim();
      final animalId = animalIdByEntryId[entryId] ?? '';
      entry['animal_id'] = animalId;
      entry['coop_number'] = animalId.isEmpty
          ? ''
          : (coopNumberByAnimalAndScope['$animalId|$coopScope'] ?? '');
    }

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

  Future<List<Map<String, dynamic>>> _reloadEntriesForDrilldown() async {
    await _loadEntries();

    _showsByGroup = _computeShowsByGroup(_entries);
    _showsByVariety = _computeShowsByVariety(_entries);

    if (mounted) {
      setState(() {});
    }

    return _entries
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
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
        initialName: _rememberedWriterName,
        initialPhone: _rememberedWriterPhone,
        onContinue: (name, phone) {
          _rememberedWriterName = name;
          _rememberedWriterPhone = phone;

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
      onReloadEntries: _reloadEntriesForDrilldown,
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
  final Future<List<Map<String, dynamic>>> Function() onReloadEntries;

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
    required this.onReloadEntries,
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

  // --- Status/completion highlighting helpers ---
  bool _isCompletedResultStatus(String rawStatus) {
    final normalized = rawStatus.trim().toLowerCase().replaceAll(' ', '_');

    if (normalized.isEmpty) return false;

    final compact = rawStatus.trim().toLowerCase();
    if (compact.startsWith('disqualified')) return true;

    // These statuses can exist while a row is still waiting for an actual
    // result and should not make the QR rollup look complete.
    const incompleteStatuses = {
      'pending',
      'not_started',
      'not-started',
      'in_progress',
      'in-progress',
      'started',
      'open',
    };

    if (incompleteStatuses.contains(normalized)) return false;

    // Match the main results-entry screen's basic completion behavior. Do not
    // count generic/default statuses like `Shown`, `Placed`, `Complete`, or
    // `Completed` by themselves because the RPC can return those before a real
    // row outcome has been entered. A row is complete when it has placement,
    // result_entered_at, DQ data, or one of these explicit non-placement outcomes.
    return normalized == 'no_show' ||
        normalized == 'no-show' ||
        normalized == 'noshow' ||
        normalized == 'disqualified' ||
        normalized == 'dq' ||
        normalized == 'unworthy_of_award' ||
        normalized == 'unworthy-of-award' ||
        normalized == 'unworthy';
  }

  bool _hasResult(Map<String, dynamic> entry) {
    final resultStatus = (entry['result_status'] ?? '').toString().trim();
    final placement = (entry['placement'] ?? '').toString().trim();
    final enteredAt = (entry['result_entered_at'] ?? '').toString().trim();
    final isDisqualified = entry['is_disqualified'];
    final dqReason = (entry['disqualified_reason'] ?? '').toString().trim();

    // Do not count `is_shown == false` by itself. In the results RPC that can
    // be the default value for rows that have not been touched yet, which made
    // the QR breed rollup show 13/13 complete even when only a few rows were
    // actually entered.
    return placement.isNotEmpty ||
        enteredAt.isNotEmpty ||
        isDisqualified == true ||
        dqReason.isNotEmpty ||
        _isCompletedResultStatus(resultStatus);
  }

  int _completedCount(List<Map<String, dynamic>> entries) {
    return entries.where(_hasResult).length;
  }

  bool _isComplete(List<Map<String, dynamic>> entries) {
    return entries.isNotEmpty && _completedCount(entries) >= entries.length;
  }

  bool _isInProgress(List<Map<String, dynamic>> entries) {
    final completed = _completedCount(entries);
    return completed > 0 && completed < entries.length;
  }

  String _statusLabel(List<Map<String, dynamic>> entries) {
    if (_isComplete(entries)) return 'Complete';
    if (_isInProgress(entries)) return 'In Progress';
    return 'Not Started';
  }

  IconData _statusIcon(List<Map<String, dynamic>> entries) {
    if (_isComplete(entries)) return Icons.check_circle;
    if (_isInProgress(entries)) return Icons.pending;
    return Icons.radio_button_unchecked;
  }

  Color _statusColor(BuildContext context, List<Map<String, dynamic>> entries) {
    final colorScheme = Theme.of(context).colorScheme;
    if (_isComplete(entries)) return Colors.green;
    if (_isInProgress(entries)) return colorScheme.primary;
    return colorScheme.onSurfaceVariant;
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

  Future<void> _applyEntryCorrection({
    required String entryId,
    required String fieldName,
    required String newValue,
    required String reason,
    required String pinCode,
  }) async {
    final cleanEntryId = entryId.trim();
    final cleanFieldName = fieldName.trim();
    final cleanNewValue = newValue.trim();
    final cleanReason = reason.trim();
    final cleanPinCode = pinCode.trim();

    if (cleanEntryId.isEmpty) {
      throw Exception('Missing entry id.');
    }

    await supabase.rpc(
      'apply_entry_correction',
      params: {
        'p_show_id': widget.showId,
        'p_entry_id': cleanEntryId,
        'p_field_name': cleanFieldName,
        'p_new_value': cleanNewValue,
        'p_reason': cleanReason,
        'p_writer_name': widget.writerName,
        'p_writer_phone': widget.writerPhone,
        'p_pin_code': cleanPinCode,
      },
    );

    for (final e in _entries) {
      final id = (e['entry_id'] ?? e['id'] ?? '').toString().trim();
      if (id != cleanEntryId) continue;

      e[cleanFieldName] = cleanNewValue;

      if (cleanFieldName == 'tattoo') {
        e['ear_number'] = cleanNewValue;
      }

      if (cleanFieldName == 'variety') {
        e['variety_name'] = cleanNewValue;
      }
    }

    if (mounted) setState(() {});
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
          final completed = _completedCount(rows);
          final statusColor = _statusColor(context, rows);

          return Card(
            elevation: 0,
            color: statusColor.withOpacity(0.06),
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
                    leading: CircleAvatar(
                      backgroundColor: statusColor.withOpacity(0.12),
                      child: Icon(
                        _statusIcon(rows),
                        color: statusColor,
                      ),
                    ),
                    title: Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '$completed/${rows.length} entered • ${_statusLabel(rows)}\n${_judgeSummary(rows)}',
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
          onQrCorrectionApply: _applyEntryCorrection,
        ),
      ),
    );

    try {
      final refreshedEntries = await widget.onReloadEntries();

      if (!mounted) return;
      setState(() {
        _entries = refreshedEntries;
        _msg = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msg = 'Results were saved, but the status could not be refreshed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final exhibitorCount = _entries
        .map((e) => (e['exhibitor_id'] ?? '').toString())
        .where((x) => x.isNotEmpty)
        .toSet()
        .length;
    final completedCount = _completedCount(_entries);
    final breedStatusColor = _statusColor(context, _entries);

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
                      _pill('$completedCount/${_entries.length} entered'),
                      _pill(_statusLabel(_entries)),
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
            color: breedStatusColor.withOpacity(0.06),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              leading: CircleAvatar(
                backgroundColor: breedStatusColor.withOpacity(0.12),
                child: Icon(
                  _statusIcon(_entries),
                  color: breedStatusColor,
                ),
              ),
              title: Text(
                widget.breed,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '$completedCount/${_entries.length} entered • ${_statusLabel(_entries)}\nTap to choose group, variety, or class.',
                ),
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
  final String? initialName;
  final String? initialPhone;
  final void Function(String name, String phone) onContinue;

  const _QrWriterInfoScreen({
    required this.showName,
    required this.sectionLabel,
    required this.breed,
    this.initialName,
    this.initialPhone,
    required this.onContinue,
  });

  @override
  State<_QrWriterInfoScreen> createState() => _QrWriterInfoScreenState();
}

class _QrWriterInfoScreenState extends State<_QrWriterInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _phoneController = TextEditingController(text: widget.initialPhone ?? '');
  }

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
