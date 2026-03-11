//lib/screens/admin/results/admin_results_entry_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

/// Supported:
/// - four_six_bis
/// - bis_ris
const String kDefaultFinalAwardMode = 'four_six_bis';

class AdminResultsEntryScreen extends StatefulWidget {
  final String showId;
  final String showName;
  final String? initialEntryId;

  const AdminResultsEntryScreen({
    super.key,
    required this.showId,
    required this.showName,
    this.initialEntryId,
  });

  @override
  State<AdminResultsEntryScreen> createState() => _AdminResultsEntryScreenState();
}

class _AdminResultsEntryScreenState extends State<AdminResultsEntryScreen> {
  bool _didAutoOpenInitialEntryFromRoot = false;
  bool _loading = true;
  String? _msg;

  List<Map<String, dynamic>> _sections = [];
  String? _selectedSectionId;

  List<Map<String, dynamic>> _entries = [];
  List<Map<String, dynamic>> _judges = [];

  final Map<String, String> _breedClassSystems = {};
  String _finalAwardMode = kDefaultFinalAwardMode;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

    Future<void> _loadAll() async {
      setState(() {
        _loading = true;
        _msg = null;
      });

      try {
        await _loadSections();
        await _loadJudges();
        await _loadBreedClassSystems();
        await _loadShowSettings();
        await _loadEntries();

        if (!mounted) return;

        setState(() => _loading = false);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _openInitialEntryFromRootIfNeeded();
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _msg = 'Load failed: $e';
        });
      }
    }

  Future<void> _loadSections() async {
    final rows = await supabase
        .from('show_sections')
        .select('id,letter,display_name,kind,is_enabled,sort_order')
        .eq('show_id', widget.showId)
        .eq('is_enabled', true);

    _sections = (rows as List).cast<Map<String, dynamic>>();

    _sections.sort((a, b) {
      int kindRank(String k) {
        switch (k) {
          case 'open':
            return 0;
          case 'youth':
            return 1;
          default:
            return 99;
        }
      }

      final ak = (a['kind'] ?? '').toString().toLowerCase();
      final bk = (b['kind'] ?? '').toString().toLowerCase();

      final kr = kindRank(ak).compareTo(kindRank(bk));
      if (kr != 0) return kr;

      final aso = a['sort_order'];
      final bso = b['sort_order'];
      final asoI = (aso is int) ? aso : int.tryParse(aso?.toString() ?? '') ?? 9999;
      final bsoI = (bso is int) ? bso : int.tryParse(bso?.toString() ?? '') ?? 9999;
      final soCmp = asoI.compareTo(bsoI);
      if (soCmp != 0) return soCmp;

      final al = (a['letter'] ?? '').toString().toUpperCase();
      final bl = (b['letter'] ?? '').toString().toUpperCase();
      return al.compareTo(bl);
    });

    _selectedSectionId ??= '';
  }

  Future<void> _loadJudges() async {
    final rows = await supabase
        .from('judge_assignments')
        .select(
          'id,judge_id,assignment_label,'
          'judges(id,display_name,name,first_name,last_name,arba_judge_number,judge_type,is_active)',
        )
        .eq('show_id', widget.showId);

    final result = <Map<String, dynamic>>[];

    for (final row in (rows as List)) {
      final map = row as Map<String, dynamic>;
      final judge = map['judges'];

      if (judge is Map) {
        final displayName = (judge['display_name'] ?? '').toString().trim();
        final name = (judge['name'] ?? '').toString().trim();
        final first = (judge['first_name'] ?? '').toString().trim();
        final last = (judge['last_name'] ?? '').toString().trim();

        final label = displayName.isNotEmpty
            ? displayName
            : name.isNotEmpty
                ? name
                : [first, last].where((x) => x.isNotEmpty).join(' ');

        result.add({
          'id': (judge['id'] ?? map['judge_id']).toString(),
          'name': label.isEmpty ? (map['judge_id'] ?? '').toString() : label,
        });
      } else {
        final id = (map['judge_id'] ?? '').toString();
        if (id.isNotEmpty) {
          result.add({'id': id, 'name': id});
        }
      }
    }

    result.sort((a, b) {
      final an = (a['name'] ?? '').toString().toLowerCase();
      final bn = (b['name'] ?? '').toString().toLowerCase();
      return an.compareTo(bn);
    });

    _judges = result;
  }

    Future<void> _jumpToIssue(_ValidationIssue issue) async {
      final allEntries = await _fetchHydratedEntries(sectionId: null);

      final targetEntryId =
          (issue.entry['entry_id'] ?? issue.entry['id'] ?? '').toString().trim();

      Map<String, dynamic> targetEntry;
      try {
        targetEntry = allEntries.firstWhere((e) {
          return (e['entry_id'] ?? e['id'] ?? '').toString().trim() == targetEntryId;
        });
      } catch (_) {
        targetEntry = Map<String, dynamic>.from(issue.entry);
      }

      final breedEntries = allEntries.where((e) {
        return (e['breed'] ?? '').toString().trim().toLowerCase() ==
            issue.breed.toLowerCase();
      }).toList();

      if (breedEntries.isEmpty) return;

      final byGroup = _showsByGroup(breedEntries);
      final byVariety = _showsByVariety(breedEntries);

      List<Map<String, dynamic>> working = [...breedEntries];

      if (byGroup && (issue.groupName ?? '').trim().isNotEmpty) {
        working = working.where((e) {
          return (e['group_name'] ?? '').toString().trim().toLowerCase() ==
              issue.groupName!.toLowerCase();
        }).toList();
      }

      if (byVariety && (issue.variety ?? '').trim().isNotEmpty) {
        working = working.where((e) {
          return (e['variety'] ?? '').toString().trim().toLowerCase() ==
              issue.variety!.toLowerCase();
        }).toList();
      }

      working = working.where((e) {
        return _classSexLabelFromEntry(e).toLowerCase() ==
            issue.classSexLabel.toLowerCase();
      }).toList();

      if (working.isEmpty) {
        working = breedEntries;
      }

      final targetSectionId =
          (targetEntry['section_id'] ?? '').toString().trim();
      if (targetSectionId.isNotEmpty) {
        _selectedSectionId = targetSectionId;
      }

      final sectionName = _sectionNameForEntry(targetEntry);

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _ResultsAnimalsScreen(
            showId: widget.showId,
            showName: widget.showName,
            sectionLabel: sectionName,
            breed: issue.breed,
            variety: issue.variety ?? '',
            classSexLabel: issue.classSexLabel,
            entries: working,
            judges: _judges,
            onBulkJudgeApply: (entries, judgeId) async {
              final ids = entries
                  .map((e) => (e['entry_id'] ?? e['id'] ?? '').toString().trim())
                  .where((x) => x.isNotEmpty)
                  .toList();
              if (ids.isEmpty) return;

              await supabase
                  .from('entries')
                  .update({
                    'judged_by_show_judge_id':
                        (judgeId == null || judgeId.isEmpty) ? null : judgeId,
                    'updated_at': DateTime.now().toUtc().toIso8601String(),
                  })
                  .inFilter('id', ids);
            },
            initialJudgeId: _singleJudgeIdFromEntries(working),
            breedClassSystems: _breedClassSystems,
            finalAwardMode: _finalAwardMode,
            showsByGroup: byGroup,
            showsByVariety: byVariety,
            initialEntryIdToOpen:
                (targetEntry['entry_id'] ?? targetEntry['id'] ?? '')
                    .toString(),
          ),
        ),
      );

      await _loadEntries();
      if (mounted) setState(() {});
    }

  Future<void> _loadBreedClassSystems() async {
    final rows = await supabase
        .from('breeds')
        .select('name,class_system')
        .eq('is_active', true);

    _breedClassSystems.clear();

    for (final row in (rows as List).cast<Map<String, dynamic>>()) {
      final name = (row['name'] ?? '').toString().trim().toLowerCase();
      final classSystem = (row['class_system'] ?? 'four').toString().trim().toLowerCase();
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

    _finalAwardMode = (row['final_award_mode'] ?? kDefaultFinalAwardMode).toString();
  }

    Future<List<Map<String, dynamic>>> _fetchHydratedEntries({
      String? sectionId,
    }) async {
      final rows = await supabase.rpc(
        'report_results_entry_rows',
        params: {
          'p_show_id': widget.showId,
          'p_section_id': (sectionId == null || sectionId.isEmpty) ? null : sectionId,
        },
      );

      final entries = (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final entryIds = entries
          .map((e) => (e['entry_id'] ?? '').toString())
          .where((x) => x.isNotEmpty)
          .toList();

      final awardsByEntryId = <String, List<String>>{};

      if (entryIds.isNotEmpty) {
        final awardRows = await supabase
            .from('entry_awards')
            .select('entry_id,award_code')
            .eq('show_id', widget.showId)
            .inFilter('entry_id', entryIds);

        for (final row in (awardRows as List).cast<Map<String, dynamic>>()) {
          final entryId = (row['entry_id'] ?? '').toString();
          final award = (row['award_code'] ?? '').toString().trim();
          if (entryId.isEmpty || award.isEmpty) continue;
          awardsByEntryId.putIfAbsent(entryId, () => <String>[]);
          awardsByEntryId[entryId]!.add(award);
        }
      }

      for (final e in entries) {
        final id = (e['entry_id'] ?? '').toString();
        e['_awards'] = awardsByEntryId[id] ?? <String>[];

        // normalize old widget code expectations
        e['id'] ??= e['entry_id'];
        e['breed'] ??= e['breed_name'];
        e['variety'] ??= e['variety_name'];
      }

      return entries;
    }

    String? _singleJudgeIdFromEntries(List<Map<String, dynamic>> entries) {
      final ids = entries
          .map((e) => (e['judged_by_show_judge_id'] ?? '').toString().trim())
          .where((x) => x.isNotEmpty)
          .toSet();

      if (ids.length == 1) return ids.first;
      return null;
    }

    Future<void> _openInitialEntryFromRootIfNeeded() async {
      if (_didAutoOpenInitialEntryFromRoot) return;
      if (widget.initialEntryId == null || widget.initialEntryId!.trim().isEmpty) {
        return;
      }

      final targetId = widget.initialEntryId!.trim();

      List<Map<String, dynamic>> allEntries = _entries;
      Map<String, dynamic> target = allEntries.cast<Map<String, dynamic>>().firstWhere(
        (e) => ((e['entry_id'] ?? e['id'] ?? '').toString().trim() == targetId),
        orElse: () => <String, dynamic>{},
      );

      if (target.isEmpty) {
        allEntries = await _fetchHydratedEntries(sectionId: null);
        target = allEntries.firstWhere(
          (e) => ((e['entry_id'] ?? e['id'] ?? '').toString().trim() == targetId),
          orElse: () => <String, dynamic>{},
        );
      }

      if (target.isEmpty || !mounted) return;

      _didAutoOpenInitialEntryFromRoot = true;

      final breed = (target['breed'] ?? '').toString().trim();
      final breedEntries = allEntries.where((e) {
        return (e['breed'] ?? '').toString().trim().toLowerCase() ==
            breed.toLowerCase();
      }).toList();

      if (breedEntries.isEmpty) return;

      final byGroup = _showsByGroup(breedEntries);
      final byVariety = _showsByVariety(breedEntries);

      List<Map<String, dynamic>> working = [...breedEntries];

      final issueGroup = (target['group_name'] ?? '').toString().trim();
      final issueVariety = (target['variety'] ?? '').toString().trim();
      final classSexLabel = _classSexLabelFromEntry(target);

      if (byGroup && issueGroup.isNotEmpty) {
        working = working.where((e) {
          return (e['group_name'] ?? '').toString().trim().toLowerCase() ==
              issueGroup.toLowerCase();
        }).toList();
      }

      if (byVariety && issueVariety.isNotEmpty) {
        working = working.where((e) {
          return (e['variety'] ?? '').toString().trim().toLowerCase() ==
              issueVariety.toLowerCase();
        }).toList();
      }

      working = working.where((e) {
        return _classSexLabelFromEntry(e).toLowerCase() ==
            classSexLabel.toLowerCase();
      }).toList();

      if (working.isEmpty) {
        working = breedEntries;
      }

      final targetSectionId = (target['section_id'] ?? '').toString().trim();
      if (targetSectionId.isNotEmpty) {
        _selectedSectionId = targetSectionId;
      }

      final sectionName = _sectionNameForEntry(target);

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _ResultsAnimalsScreen(
            showId: widget.showId,
            showName: widget.showName,
            sectionLabel: sectionName,
            breed: breed,
            variety: issueVariety,
            classSexLabel: classSexLabel,
            entries: working,
            judges: _judges,
            onBulkJudgeApply: (entries, judgeId) async {
              final ids = entries
                  .map((e) => (e['entry_id'] ?? e['id'] ?? '').toString().trim())
                  .where((x) => x.isNotEmpty)
                  .toList();
              if (ids.isEmpty) return;

              await supabase
                  .from('entries')
                  .update({
                    'judged_by_show_judge_id':
                        (judgeId == null || judgeId.isEmpty) ? null : judgeId,
                    'updated_at': DateTime.now().toUtc().toIso8601String(),
                  })
                  .inFilter('id', ids);
            },
            initialJudgeId: _singleJudgeIdFromEntries(working),
            breedClassSystems: _breedClassSystems,
            finalAwardMode: _finalAwardMode,
            showsByGroup: byGroup,
            showsByVariety: byVariety,
            initialEntryIdToOpen: targetId,
          ),
        ),
      );

      await _loadEntries();
      if (mounted) setState(() {});
    }

    Future<void> _loadEntries() async {
      _entries = await _fetchHydratedEntries(
        sectionId: (_selectedSectionId == null || _selectedSectionId!.isEmpty)
            ? null
            : _selectedSectionId,
      );
    }

  String _classSexLabelFromEntry(Map<String, dynamic> e) {
    final rawClass = (e['class_name'] ?? '').toString().trim();
    final sex = (e['sex'] ?? '').toString().trim();

    String ageClassOnly(String raw) {
      final s = raw.trim();
      if (s.isEmpty) return '';
      final lower = s.toLowerCase();
      if (lower.contains('senior') || lower.startsWith('sr')) return 'Senior';
      if (lower.contains('intermediate') || lower.startsWith('int')) return 'Intermediate';
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

  String _sectionNameForEntry(Map<String, dynamic> e) {
    final sid = (e['section_id'] ?? '').toString();
    final match = _sections.where((s) => s['id']?.toString() == sid);
    if (match.isNotEmpty) return _sectionLabel(match.first);

    final label = (e['section_label'] ?? '').toString().trim();
    if (label.isNotEmpty) return label;

    return 'Section';
  }

  String _issueSubtitle(_ValidationIssue issue) {
    final parts = <String>[
      issue.breed,
      if ((issue.groupName ?? '').trim().isNotEmpty) issue.groupName!,
      if ((issue.variety ?? '').trim().isNotEmpty) issue.variety!,
      issue.classSexLabel,
      _entryLabel(issue.entry),
    ];

    if (issue.conflictsWith != null) {
      parts.add('Conflicts with: ${_entryLabel(issue.conflictsWith!)}');
    }

    return parts.where((x) => x.trim().isNotEmpty).join(' • ');
  }

  String _sectionLabel(Map<String, dynamic> s) {
    final dn = (s['display_name'] ?? '').toString().trim();
    final letter = (s['letter'] ?? '').toString().trim();
    if (dn.isNotEmpty) return dn;
    if (letter.isNotEmpty) return 'Show $letter';
    return 'Section';
  }

  Future<void> _onChangeSection(String? value) async {
    setState(() {
      _selectedSectionId = value ?? '';
      _loading = true;
      _msg = null;
    });

    try {
      await _loadEntries();
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

  Map<String, List<Map<String, dynamic>>> _groupByBreed(List<Map<String, dynamic>> items) {
    final out = <String, List<Map<String, dynamic>>>{};
    for (final e in items) {
      final breed = (e['breed_name'] ?? e['breed'] ?? '').toString().trim();
      final key = breed.isEmpty ? '(Unknown Breed)' : breed;
      out.putIfAbsent(key, () => <Map<String, dynamic>>[]);
      out[key]!.add(e);
    }
    return out;
  }

  bool _showsByGroup(List<Map<String, dynamic>> entries) {
    return entries.any((e) => e['uses_group_awards'] == true);
  }

  bool _showsByVariety(List<Map<String, dynamic>> entries) {
    return entries.any((e) => e['uses_variety_awards'] == true);
  }

  String _judgeNameById(String? judgeId) {
    if (judgeId == null || judgeId.isEmpty) return '';
    for (final j in _judges) {
      if ((j['id'] ?? '').toString() == judgeId) {
        return (j['name'] ?? '').toString();
      }
    }
    return '';
  }

  String _judgeSummary(List<Map<String, dynamic>> entries) {
    final ids = entries
        .map((e) => (e['judged_by_show_judge_id'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toSet();

    if (ids.isEmpty) return 'Judge: Not set';
    if (ids.length > 1) return 'Judge: Mixed';

    final id = ids.first;
    final name = _judgeNameById(id);
    return 'Judge: ${name.isEmpty ? id : name}';
  }

  List<_ValidationIssue> _buildValidationIssues() {
    final issues = <_ValidationIssue>[];

    _ValidationIssue makeIssue({
      required String code,
      required String title,
      required String message,
      required Map<String, dynamic> entry,
      Map<String, dynamic>? conflictsWith,
    }) {
    return _ValidationIssue(
      code: code,
      title: title,
      message: message,
      entry: entry,
      conflictsWith: conflictsWith,
      breed: (entry['breed'] ?? '').toString().trim(),
      groupName: (entry['group_name'] ?? '').toString().trim().isEmpty
          ? null
          : (entry['group_name'] ?? '').toString().trim(),
      variety: (entry['variety'] ?? '').toString().trim().isEmpty
          ? null
          : (entry['variety'] ?? '').toString().trim(),
      classSexLabel: _classSexLabelFromEntry(entry),
    );
  }

  bool isEligibleForAwards(Map<String, dynamic> e) {
    final scratched = (e['scratched_at'] ?? '').toString().trim().isNotEmpty;
    final isShown = e['is_shown'] != false;
    final isDisqualified = e['is_disqualified'] == true;
    return !scratched && isShown && !isDisqualified;
  }

  bool showsByGroup(Map<String, dynamic> e) => e['uses_group_awards'] == true;
  bool showsByVariety(Map<String, dynamic> e) => e['uses_variety_awards'] == true;

  String sex(Map<String, dynamic> e) => (e['sex'] ?? '').toString().trim().toLowerCase();
  String breed(Map<String, dynamic> e) => (e['breed'] ?? '').toString().trim();
  String variety(Map<String, dynamic> e) => (e['variety'] ?? '').toString().trim();
  String sectionId(Map<String, dynamic> e) => (e['section_id'] ?? '').toString().trim();
  String groupName(Map<String, dynamic> e) => (e['group_name'] ?? '').toString().trim();
  List<String> awards(Map<String, dynamic> e) =>
      ((e['_awards'] as List?) ?? const []).map((x) => x.toString()).toList();

  final awardBuckets = <String, List<Map<String, dynamic>>>{};

  for (final e in _entries) {
    final entryAwards = awards(e);

    if (!isEligibleForAwards(e) && entryAwards.isNotEmpty) {
      issues.add(
        makeIssue(
          code: 'ineligible_award',
          title: 'Ineligible rabbit has awards',
          message:
              '${_entryLabel(e)} has awards assigned but is scratched, disqualified, or not shown.',
          entry: e,
        ),
      );
    }

    for (final award in entryAwards) {
      switch (award) {
        case 'BOV':
        case 'BOSV':
          final key = '${sectionId(e)}|$award|${breed(e).toLowerCase()}|${variety(e).toLowerCase()}';
          awardBuckets.putIfAbsent(key, () => <Map<String, dynamic>>[]);
          awardBuckets[key]!.add(e);
          break;
        case 'BOG':
        case 'BOSG':
          final key = '${sectionId(e)}|$award|${breed(e).toLowerCase()}|${groupName(e).toLowerCase()}';
          awardBuckets.putIfAbsent(key, () => <Map<String, dynamic>>[]);
          awardBuckets[key]!.add(e);
          break;
        case 'BOB':
        case 'BOSB':
          final key = '${sectionId(e)}|$award|${breed(e).toLowerCase()}';
          awardBuckets.putIfAbsent(key, () => <Map<String, dynamic>>[]);
          awardBuckets[key]!.add(e);
          break;
        case 'Best 4-Class':
        case 'Best 6-Class':
        case 'Best In Show':
        case 'Reserve In Show':
          final key = '${sectionId(e)}|$award';
          awardBuckets.putIfAbsent(key, () => <Map<String, dynamic>>[]);
          awardBuckets[key]!.add(e);
          break;
      }
    }
  }

  for (final bucket in awardBuckets.entries) {
    if (bucket.value.length > 1) {
      final first = bucket.value.first;
      final second = bucket.value.length > 1 ? bucket.value[1] : null;
      final awardCode = bucket.key.split('|')[1];

      issues.add(
        makeIssue(
          code: 'duplicate_award',
          title: 'Duplicate award winner',
          message:
              '$awardCode is assigned to more than one rabbit: '
              '${_entryLabel(first)}'
              '${second != null ? ' and ${_entryLabel(second)}' : ''}.',
          entry: first,
          conflictsWith: second,
        ),
      );
    }
  }

  void checkOpposite({
    required String winCode,
    required String oppCode,
    required String scopeLabel,
    required String Function(Map<String, dynamic>) scopeKey,
  }) {
    final winByScope = <String, Map<String, dynamic>>{};
    final oppByScope = <String, Map<String, dynamic>>{};

    for (final e in _entries) {
      final a = awards(e);
      final scope = scopeKey(e);
      if (a.contains(winCode)) winByScope[scope] = e;
      if (a.contains(oppCode)) oppByScope[scope] = e;
    }

    for (final scope in {...winByScope.keys, ...oppByScope.keys}) {
      final w = winByScope[scope];
      final o = oppByScope[scope];
      if (w == null || o == null) continue;

      if (sex(w).isNotEmpty && sex(w) == sex(o)) {
        issues.add(
          makeIssue(
            code: 'opposite_sex',
            title: '$winCode / $oppCode sex conflict',
            message:
                '${_entryLabel(w)} and ${_entryLabel(o)} are both marked for $winCode / $oppCode in the same $scopeLabel, but are not opposite sex.',
            entry: w,
            conflictsWith: o,
          ),
        );
      }
    }
  }

  checkOpposite(
    winCode: 'BOV',
    oppCode: 'BOSV',
    scopeLabel: 'variety',
    scopeKey: (e) => '${sectionId(e)}|${breed(e).toLowerCase()}|${variety(e).toLowerCase()}',
  );

  checkOpposite(
    winCode: 'BOG',
    oppCode: 'BOSG',
    scopeLabel: 'group',
    scopeKey: (e) => '${sectionId(e)}|${breed(e).toLowerCase()}|${groupName(e).toLowerCase()}',
  );

  checkOpposite(
    winCode: 'BOB',
    oppCode: 'BOSB',
    scopeLabel: 'breed',
    scopeKey: (e) => '${sectionId(e)}|${breed(e).toLowerCase()}',
  );

  for (final e in _entries) {
    final a = awards(e);
    final breedLower = breed(e).toLowerCase();
    final byGroup = showsByGroup(e);
    final byVariety = showsByVariety(e);

    if (a.contains('BOB') || a.contains('BOSB')) {
      final eligible = byGroup
          ? (a.contains('BOG') || a.contains('BOSG'))
          : byVariety
              ? (a.contains('BOV') || a.contains('BOSV'))
              : true;

      if (!eligible) {
        issues.add(
          makeIssue(
            code: 'bob_source',
            title: 'Invalid breed award source',
            message:
                '${_entryLabel(e)} has BOB/BOSB but is not marked ${byGroup ? 'BOG/BOSG' : byVariety ? 'BOV/BOSV' : 'as eligible for direct breed awards'}.',
            entry: e,
          ),
        );
      }
    }

    final classSystem = _breedClassSystems[breedLower] ?? 'four';

    if (a.contains('Best 4-Class')) {
      if (!a.contains('BOB')) {
        issues.add(
          makeIssue(
            code: 'best4_requires_bob',
            title: 'Best 4-Class requires BOB',
            message: '${_entryLabel(e)} has Best 4-Class but is not marked BOB.',
            entry: e,
          ),
        );
      }
      if (classSystem != 'four') {
        issues.add(
          makeIssue(
            code: 'best4_wrong_breed',
            title: 'Best 4-Class on wrong breed type',
            message: '${_entryLabel(e)} has Best 4-Class but breed is not 4-class.',
            entry: e,
          ),
        );
      }
    }

    if (a.contains('Best 6-Class')) {
      if (!a.contains('BOB')) {
        issues.add(
          makeIssue(
            code: 'best6_requires_bob',
            title: 'Best 6-Class requires BOB',
            message: '${_entryLabel(e)} has Best 6-Class but is not marked BOB.',
            entry: e,
          ),
        );
      }
      if (classSystem != 'six') {
        issues.add(
          makeIssue(
            code: 'best6_wrong_breed',
            title: 'Best 6-Class on wrong breed type',
            message: '${_entryLabel(e)} has Best 6-Class but breed is not 6-class.',
            entry: e,
          ),
        );
      }
    }

    if (_finalAwardMode == 'four_six_bis' && a.contains('Best In Show')) {
      if (!(a.contains('Best 4-Class') || a.contains('Best 6-Class'))) {
        issues.add(
          makeIssue(
            code: 'bis_requires_best_class',
            title: 'Best In Show requires Best 4-Class or Best 6-Class',
            message: '${_entryLabel(e)} has Best In Show but is not Best 4-Class or Best 6-Class.',
            entry: e,
          ),
        );
      }
    }

    if (_finalAwardMode == 'bis_ris' && a.contains('Reserve In Show') && a.contains('Best In Show')) {
      issues.add(
        makeIssue(
          code: 'bis_ris_same_entry',
          title: 'Rabbit cannot be BIS and RIS',
          message: '${_entryLabel(e)} cannot be both Best In Show and Reserve In Show.',
          entry: e,
        ),
      );
    }
  }

  return issues;
}

  String _entryLabel(Map<String, dynamic> e) {
    final tattoo = (e['tattoo'] ?? '').toString().trim();
    final breed = (e['breed'] ?? '').toString().trim();
    final variety = (e['variety'] ?? '').toString().trim();
    final groupName = (e['group_name'] ?? '').toString().trim();

    return [
      tattoo.isEmpty ? '(No ear #)' : tattoo,
      breed,
      if (groupName.isNotEmpty) groupName,
      variety,
    ].where((x) => x.isNotEmpty).join(' • ');
  }

    void _openValidationSheet() {
      final issues = _buildValidationIssues();

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Results Validation',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        issues.isEmpty
                            ? 'No validation issues found.'
                            : '${issues.length} validation issue${issues.length == 1 ? '' : 's'} found.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: issues.isEmpty
                          ? const Align(
                              alignment: Alignment.topLeft,
                              child: Text('Everything looks good so far.'),
                            )
                          : ListView.separated(
                              controller: scrollController,
                              itemCount: issues.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final issue = issues[i];
                                return ListTile(
                                  leading: const Icon(Icons.warning_amber_rounded),
                                  title: Text(issue.title),
                                  subtitle: Text(
                                    '${issue.message}\n${_issueSubtitle(issue)}',
                                  ),
                                  isThreeLine: true,
                                  trailing: TextButton(
                                    onPressed: () async {
                                      Navigator.pop(context);
                                      await _jumpToIssue(issue);
                                    },
                                    child: const Text('Fix'),
                                  ),
                                  onTap: () async {
                                    Navigator.pop(context);
                                    await _jumpToIssue(issue);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByBreed(_entries);
    final breeds = grouped.keys.toList()
      ..sort((a, b) {
        int sortFor(String key) {
          final rows = grouped[key] ?? const <Map<String, dynamic>>[];
          if (rows.isEmpty) return 9999;
          final raw = rows.first['breed_sort_order'];
          if (raw is int) return raw;
          return int.tryParse(raw?.toString() ?? '') ?? 9999;
        }

        final bySort = sortFor(a).compareTo(sortFor(b));
        if (bySort != 0) return bySort;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    final issues = _buildValidationIssues();

    return Scaffold(
      appBar: AppBar(
        title: Text('Results Entry — ${widget.showName}'),
        actions: [
          IconButton(
            tooltip: 'Validation',
            onPressed: _loading ? null : _openValidationSheet,
            icon: const Icon(Icons.rule_folder_outlined),
          ),
          IconButton(
            tooltip: 'Reload',
            onPressed: _loading ? null : _loadAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  if (_msg != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _msg!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: DropdownButtonFormField<String>(
                      value: _selectedSectionId ?? '',
                      decoration: const InputDecoration(
                        labelText: 'Show Letter / Section',
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: '',
                          child: Text('All Sections'),
                        ),
                        ..._sections.map(
                          (s) => DropdownMenuItem<String>(
                            value: s['id']?.toString(),
                            child: Text(_sectionLabel(s)),
                          ),
                        ),
                      ],
                      onChanged: _onChangeSection,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _finalAwardMode == 'bis_ris'
                            ? 'Final awards: Best in Show / Reserve in Show'
                            : 'Final awards: Best 4-Class / Best 6-Class / Best in Show',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Card(
                      child: ListTile(
                        leading: Icon(
                          issues.isEmpty ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                          color: issues.isEmpty ? Colors.green : Colors.orange,
                        ),
                        title: Text(issues.isEmpty ? 'Validation looks good' : 'Validation issues found'),
                        subtitle: Text(
                          issues.isEmpty
                              ? 'No current award/result conflicts found.'
                              : '${issues.length} issue${issues.length == 1 ? '' : 's'} to review.',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _openValidationSheet,
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: breeds.isEmpty
                        ? const Center(child: Text('No entries found for this section.'))
                        : ListView.separated(
                            itemCount: breeds.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final breed = breeds[i];
                              final breedEntries = grouped[breed]!;
                              final count = breedEntries.length;
                              final byGroup = _showsByGroup(breedEntries);
                              final byVariety = _showsByVariety(breedEntries);

                              final sectionName = (_selectedSectionId == null || _selectedSectionId!.isEmpty)
                                  ? 'All Sections'
                                  : (() {
                                      final section = _sections.firstWhere(
                                        (s) => s['id']?.toString() == _selectedSectionId,
                                        orElse: () => <String, dynamic>{},
                                      );
                                      return section.isEmpty ? 'Section' : _sectionLabel(section);
                                    })();

                              String flowLabel;
                              if (byGroup && byVariety) {
                                flowLabel = 'Group → Variety';
                              } else if (byGroup) {
                                flowLabel = 'Group';
                              } else if (byVariety) {
                                flowLabel = 'Variety';
                              } else {
                                flowLabel = 'Class';
                              }

                              return ListTile(
                                title: Text(breed),
                                subtitle: Text(
                                  '$count entr${count == 1 ? 'y' : 'ies'} • $flowLabel • ${_judgeSummary(breedEntries)}',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () async {
                                  if (byGroup) {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => _ResultsGroupScreen(
                                          showId: widget.showId,
                                          showName: widget.showName,
                                          sectionLabel: sectionName,
                                          breed: breed,
                                          entries: breedEntries,
                                          judges: _judges,
                                          breedClassSystems: _breedClassSystems,
                                          finalAwardMode: _finalAwardMode,
                                          showsByVariety: byVariety,
                                        ),
                                      ),
                                    );
                                  } else if (byVariety) {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => _ResultsVarietyScreen(
                                          showId: widget.showId,
                                          showName: widget.showName,
                                          sectionLabel: sectionName,
                                          breed: breed,
                                          entries: breedEntries,
                                          judges: _judges,
                                          breedClassSystems: _breedClassSystems,
                                          finalAwardMode: _finalAwardMode,
                                          parentGroupLabel: null,
                                        ),
                                      ),
                                    );
                                  } else {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => _ResultsClassSexScreen(
                                          showId: widget.showId,
                                          showName: widget.showName,
                                          sectionLabel: sectionName,
                                          breed: breed,
                                          variety: '',
                                          contextLabel: breed,
                                          entries: breedEntries,
                                          judges: _judges,
                                          breedClassSystems: _breedClassSystems,
                                          finalAwardMode: _finalAwardMode,
                                          showsByGroup: false,
                                          showsByVariety: false,
                                        ),
                                      ),
                                    );
                                  }

                                  await _loadEntries();
                                  if (mounted) setState(() {});
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ResultsGroupScreen extends StatefulWidget {
  final String showId;
  final String showName;
  final String sectionLabel;
  final String breed;
  final List<Map<String, dynamic>> entries;
  final List<Map<String, dynamic>> judges;
  final Map<String, String> breedClassSystems;
  final String finalAwardMode;
  final bool showsByVariety;

  const _ResultsGroupScreen({
    required this.showId,
    required this.showName,
    required this.sectionLabel,
    required this.breed,
    required this.entries,
    required this.judges,
    required this.breedClassSystems,
    required this.finalAwardMode,
    required this.showsByVariety,
  });

  @override
  State<_ResultsGroupScreen> createState() => _ResultsGroupScreenState();
}

class _ResultsGroupScreenState extends State<_ResultsGroupScreen> {
  late List<Map<String, dynamic>> _entries;
  String? _msg;
  bool _savingJudge = false;

  @override
  void initState() {
    super.initState();
    _entries = [...widget.entries];
  }

  Map<String, List<Map<String, dynamic>>> _groupByGroupName() {
    final out = <String, List<Map<String, dynamic>>>{};
    for (final e in _entries) {
      final groupName = (e['group_name'] ?? '').toString().trim();
      final key = groupName.isEmpty ? '(Unknown Group)' : groupName;
      out.putIfAbsent(key, () => <Map<String, dynamic>>[]);
      out[key]!.add(e);
    }
    return out;
  }

  String _judgeNameById(String? judgeId) {
    if (judgeId == null || judgeId.isEmpty) return '';
    for (final j in widget.judges) {
      if ((j['id'] ?? '').toString() == judgeId) {
        return (j['name'] ?? '').toString();
      }
    }
    return '';
  }

  String _judgeSummary(List<Map<String, dynamic>> entries) {
    final ids = entries
        .map((e) => (e['judged_by_show_judge_id'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toSet();

    if (ids.isEmpty) return 'Judge: Not set';
    if (ids.length > 1) return 'Judge: Mixed';

    final id = ids.first;
    final name = _judgeNameById(id);
    return 'Judge: ${name.isEmpty ? id : name}';
  }

  String? _singleJudgeId(List<Map<String, dynamic>> entries) {
    final ids = entries
        .map((e) => (e['judged_by_show_judge_id'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toSet();

    if (ids.length == 1) return ids.first;
    return null;
  }

  Future<void> _applyJudgeToEntries(List<Map<String, dynamic>> entries, String? judgeId) async {
    setState(() {
      _savingJudge = true;
      _msg = null;
    });

    try {
      final ids = entries
        .map((e) => (e['entry_id'] ?? e['id'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toList();
      if (ids.isEmpty) return;

      await supabase
          .from('entries')
          .update({
            'judged_by_show_judge_id': (judgeId == null || judgeId.isEmpty) ? null : judgeId,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .inFilter('id', ids);

      for (final e in _entries) {
        final rowId = (e['entry_id'] ?? e['id'] ?? '').toString().trim();
        if (ids.contains(rowId)) {
          e['judged_by_show_judge_id'] = (judgeId == null || judgeId.isEmpty) ? null : judgeId;
        }
      }

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

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByGroupName();
    final groups = grouped.keys.toList()
      ..sort((a, b) {
        int sortFor(String key) {
          final rows = grouped[key] ?? const <Map<String, dynamic>>[];
          if (rows.isEmpty) return 9999;
          final raw = rows.first['group_sort_order'];
          if (raw is int) return raw;
          return int.tryParse(raw?.toString() ?? '') ?? 9999;
        }

        final bySort = sortFor(a).compareTo(sortFor(b));
        if (bySort != 0) return bySort;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.breed),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${widget.showName} • ${widget.sectionLabel}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: DropdownButtonFormField<String>(
              value: _singleJudgeId(_entries),
              decoration: const InputDecoration(
                labelText: 'Judge for this breed',
              ),
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
                      _applyJudgeToEntries(_entries, (v == null || v.isEmpty) ? null : v);
                    },
            ),
          ),
          if (_msg != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _msg!,
                  style: TextStyle(color: _msg == 'Judge updated.' ? Colors.green : Colors.red),
                ),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: groups.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final groupName = groups[i];
                final groupEntries = grouped[groupName]!;
                final count = groupEntries.length;

                return ListTile(
                  title: Text(groupName),
                  subtitle: Text('$count entr${count == 1 ? 'y' : 'ies'} • ${_judgeSummary(groupEntries)}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    if (widget.showsByVariety) {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _ResultsVarietyScreen(
                            showId: widget.showId,
                            showName: widget.showName,
                            sectionLabel: widget.sectionLabel,
                            breed: widget.breed,
                            entries: groupEntries,
                            judges: widget.judges,
                            breedClassSystems: widget.breedClassSystems,
                            finalAwardMode: widget.finalAwardMode,
                            parentGroupLabel: groupName,
                          ),
                        ),
                      );
                    } else {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _ResultsClassSexScreen(
                            showId: widget.showId,
                            showName: widget.showName,
                            sectionLabel: widget.sectionLabel,
                            breed: widget.breed,
                            variety: '',
                            contextLabel: groupName,
                            entries: groupEntries,
                            judges: widget.judges,
                            breedClassSystems: widget.breedClassSystems,
                            finalAwardMode: widget.finalAwardMode,
                            showsByGroup: true,
                            showsByVariety: false,
                          ),
                        ),
                      );
                    }

                    if (!mounted) return;
                    setState(() {});
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultsVarietyScreen extends StatefulWidget {
  final String showId;
  final String showName;
  final String sectionLabel;
  final String breed;
  final List<Map<String, dynamic>> entries;
  final List<Map<String, dynamic>> judges;
  final Map<String, String> breedClassSystems;
  final String finalAwardMode;
  final String? parentGroupLabel;

  const _ResultsVarietyScreen({
    required this.showId,
    required this.showName,
    required this.sectionLabel,
    required this.breed,
    required this.entries,
    required this.judges,
    required this.breedClassSystems,
    required this.finalAwardMode,
    required this.parentGroupLabel,
  });

  @override
  State<_ResultsVarietyScreen> createState() => _ResultsVarietyScreenState();
}

class _ResultsVarietyScreenState extends State<_ResultsVarietyScreen> {
  late List<Map<String, dynamic>> _entries;
  String? _msg;
  bool _savingJudge = false;

  @override
  void initState() {
    super.initState();
    _entries = [...widget.entries];
  }

  Map<String, List<Map<String, dynamic>>> _groupByVariety() {
    final out = <String, List<Map<String, dynamic>>>{};
    for (final e in _entries) {
      final variety = (e['variety'] ?? '').toString().trim();
      final key = variety.isEmpty ? '(Unknown Variety)' : variety;
      out.putIfAbsent(key, () => <Map<String, dynamic>>[]);
      out[key]!.add(e);
    }
    return out;
  }

  String _judgeNameById(String? judgeId) {
    if (judgeId == null || judgeId.isEmpty) return '';
    for (final j in widget.judges) {
      if ((j['id'] ?? '').toString() == judgeId) {
        return (j['name'] ?? '').toString();
      }
    }
    return '';
  }

  String _judgeSummary(List<Map<String, dynamic>> entries) {
    final ids = entries
        .map((e) => (e['judged_by_show_judge_id'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toSet();

    if (ids.isEmpty) return 'Judge: Not set';
    if (ids.length > 1) return 'Judge: Mixed';

    final id = ids.first;
    final name = _judgeNameById(id);
    return 'Judge: ${name.isEmpty ? id : name}';
  }

  String? _singleJudgeId(List<Map<String, dynamic>> entries) {
    final ids = entries
        .map((e) => (e['judged_by_show_judge_id'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toSet();

    if (ids.length == 1) return ids.first;
    return null;
  }

  Future<void> _applyJudgeToEntries(List<Map<String, dynamic>> entries, String? judgeId) async {
    setState(() {
      _savingJudge = true;
      _msg = null;
    });

    try {
      final ids = entries
        .map((e) => (e['entry_id'] ?? e['id'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toList();
      if (ids.isEmpty) return;

      await supabase
          .from('entries')
          .update({
            'judged_by_show_judge_id': (judgeId == null || judgeId.isEmpty) ? null : judgeId,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .inFilter('id', ids);

      for (final e in _entries) {
        final rowId = (e['entry_id'] ?? e['id'] ?? '').toString().trim();
        if (ids.contains(rowId)) {
          e['judged_by_show_judge_id'] =
              (judgeId == null || judgeId.isEmpty) ? null : judgeId;
        }
      }

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

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByVariety();
    final varieties = grouped.keys.toList()
      ..sort((a, b) {
        int sortFor(String key) {
          final rows = grouped[key] ?? const <Map<String, dynamic>>[];
          if (rows.isEmpty) return 9999;
          final raw = rows.first['variety_sort_order'];
          if (raw is int) return raw;
          return int.tryParse(raw?.toString() ?? '') ?? 9999;
        }

        final bySort = sortFor(a).compareTo(sortFor(b));
        if (bySort != 0) return bySort;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.parentGroupLabel ?? widget.breed),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.parentGroupLabel == null
                    ? '${widget.showName} • ${widget.sectionLabel} • ${widget.breed}'
                    : '${widget.showName} • ${widget.sectionLabel} • ${widget.breed} • ${widget.parentGroupLabel}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: DropdownButtonFormField<String>(
                        value: _singleJudgeId(_entries),
                        decoration: InputDecoration(
                          labelText: widget.parentGroupLabel == null
                              ? 'Judge for this breed'
                              : 'Judge for this group',
                        ),
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
                                _applyJudgeToEntries(
                                  _entries,
                                  (v == null || v.isEmpty) ? null : v,
                                );
                              },
                      ),
                    ),
                    if (_msg != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _msg!,
                            style: TextStyle(
                              color: _msg == 'Judge updated.' ? Colors.green : Colors.red,
                            ),
                          ),
                        ),
                      ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: varieties.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final variety = varieties[i];
                final varietyEntries = grouped[variety]!;
                final count = varietyEntries.length;

                return ListTile(
                  title: Text(variety),
                  subtitle: Text('$count entr${count == 1 ? 'y' : 'ies'} • ${_judgeSummary(varietyEntries)}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _ResultsClassSexScreen(
                          showId: widget.showId,
                          showName: widget.showName,
                          sectionLabel: widget.sectionLabel,
                          breed: widget.breed,
                          variety: variety,
                          contextLabel: widget.parentGroupLabel ?? variety,
                          entries: varietyEntries,
                          judges: widget.judges,
                          breedClassSystems: widget.breedClassSystems,
                          finalAwardMode: widget.finalAwardMode,
                          showsByGroup: varietyEntries.any((e) => e['uses_group_awards'] == true),
                          showsByVariety: true,
                        ),
                      ),
                    );
                    if (!mounted) return;
                    setState(() {});
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultsClassSexScreen extends StatefulWidget {
  final String showId;
  final String showName;
  final String sectionLabel;
  final String breed;
  final String variety;
  final String contextLabel;
  final List<Map<String, dynamic>> entries;
  final List<Map<String, dynamic>> judges;
  final Map<String, String> breedClassSystems;
  final String finalAwardMode;
  final bool showsByGroup;
  final bool showsByVariety;

  const _ResultsClassSexScreen({
    required this.showId,
    required this.showName,
    required this.sectionLabel,
    required this.breed,
    required this.variety,
    required this.contextLabel,
    required this.entries,
    required this.judges,
    required this.breedClassSystems,
    required this.finalAwardMode,
    required this.showsByGroup,
    required this.showsByVariety,
  });

  @override
  State<_ResultsClassSexScreen> createState() => _ResultsClassSexScreenState();
}

class _ResultsClassSexScreenState extends State<_ResultsClassSexScreen> {
  late List<Map<String, dynamic>> _entries;
  String? _msg;
  bool _savingJudge = false;

  @override
  void initState() {
    super.initState();
    _entries = [...widget.entries];
  }

  String _ageClassOnly(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    final lower = s.toLowerCase();
    if (lower.contains('senior') || lower.startsWith('sr')) return 'Senior';
    if (lower.contains('intermediate') || lower.startsWith('int')) return 'Intermediate';
    if (lower.contains('junior') || lower.startsWith('jr')) return 'Junior';
    if (lower.contains('open')) return 'Open';
    return s;
  }

  int _classRank(String v) {
    final x = v.toLowerCase();
    if (x == 'junior') return 0;
    if (x == 'intermediate') return 1;
    if (x == 'senior') return 2;
    if (x == 'open') return 3;
    return 99;
  }

  int _sexRank(String v) {
    final x = v.toLowerCase();
    if (x.contains('buck') || x.contains('boar')) return 0;
    if (x.contains('doe') || x.contains('sow')) return 1;
    return 99;
  }

  Map<String, List<Map<String, dynamic>>> _groupByClassSex() {
    final out = <String, List<Map<String, dynamic>>>{};
    for (final e in _entries) {
      final cls = _ageClassOnly((e['class_name'] ?? '').toString());
      final sex = (e['sex'] ?? '').toString().trim();
      final label = [
        if (cls.isNotEmpty) cls,
        if (sex.isNotEmpty) sex,
      ].join(' ');
      final key = label.isEmpty ? '(Unknown Class)' : label;
      out.putIfAbsent(key, () => <Map<String, dynamic>>[]);
      out[key]!.add(e);
    }
    return out;
  }

  String _judgeNameById(String? judgeId) {
    if (judgeId == null || judgeId.isEmpty) return '';
    for (final j in widget.judges) {
      if ((j['id'] ?? '').toString() == judgeId) {
        return (j['name'] ?? '').toString();
      }
    }
    return '';
  }

  String _judgeSummary(List<Map<String, dynamic>> entries) {
    final ids = entries
        .map((e) => (e['judged_by_show_judge_id'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toSet();

    if (ids.isEmpty) return 'Judge: Not set';
    if (ids.length > 1) return 'Judge: Mixed';

    final id = ids.first;
    final name = _judgeNameById(id);
    return 'Judge: ${name.isEmpty ? id : name}';
  }

  String? _singleJudgeId(List<Map<String, dynamic>> entries) {
    final ids = entries
        .map((e) => (e['judged_by_show_judge_id'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toSet();

    if (ids.length == 1) return ids.first;
    return null;
  }

  Future<void> _applyJudgeToEntries(List<Map<String, dynamic>> entries, String? judgeId) async {
    setState(() {
      _savingJudge = true;
      _msg = null;
    });

    try {
      final ids = entries
        .map((e) => (e['entry_id'] ?? e['id'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toList();
      if (ids.isEmpty) return;

      await supabase
          .from('entries')
          .update({
            'judged_by_show_judge_id': (judgeId == null || judgeId.isEmpty) ? null : judgeId,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .inFilter('id', ids);

      for (final e in _entries) {
        final rowId = (e['entry_id'] ?? e['id'] ?? '').toString().trim();
        if (ids.contains(rowId)) {
          e['judged_by_show_judge_id'] = (judgeId == null || judgeId.isEmpty) ? null : judgeId;
        }
      }

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

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByClassSex();
    final labels = grouped.keys.toList()
      ..sort((a, b) {
        final ap = a.split(' ');
        final bp = b.split(' ');
        final aClass = ap.isNotEmpty ? ap.first : '';
        final bClass = bp.isNotEmpty ? bp.first : '';
        final aSex = ap.length > 1 ? ap.sublist(1).join(' ') : '';
        final bSex = bp.length > 1 ? bp.sublist(1).join(' ') : '';

        final cr = _classRank(aClass).compareTo(_classRank(bClass));
        if (cr != 0) return cr;

        return _sexRank(aSex).compareTo(_sexRank(bSex));
      });

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.contextLabel),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                [
                  widget.showName,
                  widget.sectionLabel,
                  widget.breed,
                  if (widget.contextLabel != widget.breed && widget.contextLabel.trim().isNotEmpty) widget.contextLabel,
                ].join(' • '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          if (_msg != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _msg!,
                  style: TextStyle(color: _msg == 'Judge updated.' ? Colors.green : Colors.red),
                ),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: labels.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final label = labels[i];
                final classEntries = grouped[label]!;
                final count = classEntries.length;

                return ListTile(
                  title: Text(label),
                  subtitle: Text(
                    '$count rabbit${count == 1 ? '' : 's'} • ${_judgeSummary(classEntries)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _ResultsAnimalsScreen(
                          showId: widget.showId,
                          showName: widget.showName,
                          sectionLabel: widget.sectionLabel,
                          breed: widget.breed,
                          variety: widget.variety,
                          classSexLabel: label,
                          entries: classEntries,
                          judges: widget.judges,
                          onBulkJudgeApply: _applyJudgeToEntries,
                          initialJudgeId: _singleJudgeId(classEntries),
                          breedClassSystems: widget.breedClassSystems,
                          finalAwardMode: widget.finalAwardMode,
                          showsByGroup: widget.showsByGroup,
                          showsByVariety: widget.showsByVariety,
                        ),
                      ),
                    );
                    if (!mounted) return;
                    setState(() {});
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultsAnimalsScreen extends StatefulWidget {
  final String showId;
  final String showName;
  final String sectionLabel;
  final String breed;
  final String variety;
  final String classSexLabel;
  final String? initialEntryIdToOpen;
  final List<Map<String, dynamic>> entries;
  final List<Map<String, dynamic>> judges;
  final Future<void> Function(List<Map<String, dynamic>> entries, String? judgeId) onBulkJudgeApply;
  final String? initialJudgeId;
  final Map<String, String> breedClassSystems;
  final String finalAwardMode;
  final bool showsByGroup;
  final bool showsByVariety;

  const _ResultsAnimalsScreen({
    required this.showId,
    required this.showName,
    required this.sectionLabel,
    required this.breed,
    required this.variety,
    required this.classSexLabel,
    required this.entries,
    required this.judges,
    required this.onBulkJudgeApply,
    required this.initialJudgeId,
    required this.breedClassSystems,
    required this.finalAwardMode,
    required this.showsByGroup,
    required this.showsByVariety,
    this.initialEntryIdToOpen,
  });

  @override
  State<_ResultsAnimalsScreen> createState() => _ResultsAnimalsScreenState();
}

class _ResultsAnimalsScreenState extends State<_ResultsAnimalsScreen> {
  late List<Map<String, dynamic>> _entries;
  String? _msg;
  bool _savingJudge = false;
  String? _currentJudgeId;
  bool _didAutoOpenInitialEntry = false;

  @override
  void initState() {
    super.initState();
    _entries = [...widget.entries];
    _currentJudgeId = widget.initialJudgeId;
    _sortEntries();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openInitialEntryIfNeeded();
    });
  }

  void _sortEntries() {
    _entries.sort((a, b) {
      final at = (a['tattoo'] ?? '').toString().toLowerCase();
      final bt = (b['tattoo'] ?? '').toString().toLowerCase();
      return at.compareTo(bt);
    });
  }

  void _openInitialEntryIfNeeded() {
    if (_didAutoOpenInitialEntry) return;
    if (widget.initialEntryIdToOpen == null || widget.initialEntryIdToOpen!.trim().isEmpty) return;

    final index = _entries.indexWhere((e) {
      final id = (e['entry_id'] ?? e['id'] ?? '').toString().trim();
      return id == widget.initialEntryIdToOpen;
    });

    if (index >= 0 && mounted) {
      _didAutoOpenInitialEntry = true;
      _openResultEntryAt(index);
    }
  }

  String _exhibitorName(Map<String, dynamic> e) {
    final label = (e['exhibitor_label'] ?? '').toString().trim();
    if (label.isNotEmpty) return label;
    return '(Unknown Exhibitor)';
  }

  String _judgeNameById(String? judgeId) {
    if (judgeId == null || judgeId.isEmpty) return '';
    for (final j in widget.judges) {
      if ((j['id'] ?? '').toString() == judgeId) {
        return (j['name'] ?? '').toString();
      }
    }
    return '';
  }

  Future<void> _reloadAll() async {
    final currentIds = _entries
      .map((e) => (e['entry_id'] ?? e['id'] ?? '').toString().trim())
      .where((x) => x.isNotEmpty)
      .toSet();
    if (currentIds.isEmpty) return;

    final rows = await supabase.rpc(
      'report_results_entry_rows',
      params: {
        'p_show_id': widget.showId,
        'p_section_id': null,
      },
    );

    final allRows = (rows as List).cast<Map<String, dynamic>>();

    final refreshed = allRows.where((row) {
      final id = (row['entry_id'] ?? '').toString();
      return currentIds.contains(id);
    }).map((e) {
      final copy = Map<String, dynamic>.from(e);
      copy['id'] ??= copy['entry_id'];
      copy['breed'] ??= copy['breed_name'];
      copy['variety'] ??= copy['variety_name'];
      return copy;
    }).toList();

    final awardRows = await supabase
        .from('entry_awards')
        .select('entry_id,award_code')
        .eq('show_id', widget.showId)
        .inFilter('entry_id', refreshed.map((e) => e['entry_id'].toString()).toList());

    final awardsByEntryId = <String, List<String>>{};
    for (final row in (awardRows as List).cast<Map<String, dynamic>>()) {
      final entryId = (row['entry_id'] ?? '').toString();
      final award = (row['award_code'] ?? '').toString().trim();
      if (entryId.isEmpty || award.isEmpty) continue;
      awardsByEntryId.putIfAbsent(entryId, () => <String>[]);
      awardsByEntryId[entryId]!.add(award);
    }

    for (final e in refreshed) {
      final id = e['entry_id'].toString();
      e['_awards'] = awardsByEntryId[id] ?? <String>[];
    }

    _entries = refreshed;
    _sortEntries();

    final judgeIds = _entries
        .map((e) => (e['judged_by_show_judge_id'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toSet();

    _currentJudgeId = judgeIds.length == 1 ? judgeIds.first : null;

    if (mounted) setState(() {});

    _openInitialEntryIfNeeded();
  }

  int _shownCount() {
    return _entries.where((e) {
      final scratched = (e['scratched_at'] ?? '').toString().trim().isNotEmpty;
      final isShown = e['is_shown'] != false;
      final isDisqualified = e['is_disqualified'] == true;
      return !scratched && isShown && !isDisqualified;
    }).length;
  }

  List<String> _availablePlacements({String? excludingEntryId}) {
    final shownCount = _shownCount();
    final all = List<String>.generate(shownCount, (i) => '${i + 1}');

    final used = <String>{};
    for (final e in _entries) {
      if (excludingEntryId != null &&
          (e['entry_id'] ?? e['id'] ?? '').toString().trim() == excludingEntryId) {
        continue;
      }

      final scratched = (e['scratched_at'] ?? '').toString().trim().isNotEmpty;
      final isShown = e['is_shown'] != false;
      final isDisqualified = e['is_disqualified'] == true;
      if (scratched || !isShown || isDisqualified) continue;

      final placement = (e['placement'] ?? '').toString().trim();
      if (placement.isNotEmpty) used.add(placement);
    }

    return all.where((p) => !used.contains(p)).toList();
  }

  Future<void> _applyJudgeToClass(String? judgeId) async {
    setState(() {
      _savingJudge = true;
      _msg = null;
    });

    try {
      await widget.onBulkJudgeApply(_entries, judgeId);
      await _reloadAll();
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

  Future<void> _openResultEntryAt(int index) async {
    if (index < 0 || index >= _entries.length) return;

    final entry = _entries[index];

    final result = await showModalBottomSheet<_ResultsEntryOutcome>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ResultsEntrySheet(
        showId: widget.showId,
        entry: entry,
        classEntries: _entries,
        judges: widget.judges,
        availablePlacements: _availablePlacements(
          excludingEntryId: (entry['entry_id'] ?? entry['id'] ?? '').toString().trim(),
        ),
        shownCount: _shownCount(),
        currentIndex: index,
        totalCount: _entries.length,
        breedClassSystems: widget.breedClassSystems,
        finalAwardMode: widget.finalAwardMode,
        showsByGroup: widget.showsByGroup,
        showsByVariety: widget.showsByVariety,
      ),
    );

    if (result == null) return;

    await _reloadAll();

    if (!mounted) return;

    setState(() {
      _msg = 'Results updated.';
    });

    if (result.goNext) {
      final nextIndex = index + 1;
      if (nextIndex < _entries.length) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _openResultEntryAt(nextIndex);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rabbitCount = _entries.length;
    final exhibitorCount = _entries
        .map((e) => (e['exhibitor_id'] ?? '').toString())
        .where((x) => x.isNotEmpty)
        .toSet()
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.classSexLabel),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                [
                  widget.showName,
                  widget.sectionLabel,
                  widget.breed,
                  if (widget.variety.trim().isNotEmpty) widget.variety,
                ].join(' • '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: DropdownButtonFormField<String>(
              value: _currentJudgeId,
              decoration: const InputDecoration(
                labelText: 'Judge for this class',
              ),
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
                      _applyJudgeToClass((v == null || v.isEmpty) ? null : v);
                    },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '$rabbitCount rabbits • $exhibitorCount exhibitors • ${_shownCount()} shown/eligible',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
          if (_msg != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _msg!,
                  style: TextStyle(
                    color: _msg == 'Judge updated.' || _msg == 'Results updated.' ? Colors.green : Colors.red,
                  ),
                ),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: _entries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final e = _entries[i];
                final tattoo = (e['tattoo'] ?? '').toString();
                final exhibitor = _exhibitorName(e);
                final placement = (e['placement'] ?? '').toString().trim();
                final awards = ((e['_awards'] as List?) ?? const []).map((x) => x.toString()).toList();
                final awardsText = awards.join(', ');
                final isShown = e['is_shown'] != false;
                final isDisqualified = e['is_disqualified'] == true;
                final scratched = (e['scratched_at'] ?? '').toString().trim().isNotEmpty;
                final judgeId = (e['judged_by_show_judge_id'] ?? '').toString().trim();
                final judgeName = _judgeNameById(judgeId);

                final subtitleParts = <String>[
                  if (exhibitor.isNotEmpty) exhibitor,
                  if (placement.isNotEmpty) 'Place: $placement',
                  if (awardsText.isNotEmpty) 'Awards: $awardsText',
                  if (judgeId.isNotEmpty) 'Judge: ${judgeName.isEmpty ? judgeId : judgeName}',
                  if (!isShown) 'Not shown',
                  if (isDisqualified) 'Disqualified',
                  if (scratched) 'Scratched',
                ];

                return ListTile(
                  title: Text(tattoo.isEmpty ? '(No ear #)' : tattoo),
                  subtitle: Text(subtitleParts.join(' • ')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openResultEntryAt(i),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultsEntryOutcome {
  final bool goNext;

  const _ResultsEntryOutcome({
    required this.goNext,
  });
}

class _ResultsEntrySheet extends StatefulWidget {
  final String showId;
  final Map<String, dynamic> entry;
  final List<Map<String, dynamic>> classEntries;
  final List<Map<String, dynamic>> judges;
  final List<String> availablePlacements;
  final int shownCount;
  final int currentIndex;
  final int totalCount;
  final Map<String, String> breedClassSystems;
  final String finalAwardMode;
  final bool showsByGroup;
  final bool showsByVariety;

  const _ResultsEntrySheet({
    required this.showId,
    required this.entry,
    required this.classEntries,
    required this.judges,
    required this.availablePlacements,
    required this.shownCount,
    required this.currentIndex,
    required this.totalCount,
    required this.breedClassSystems,
    required this.finalAwardMode,
    required this.showsByGroup,
    required this.showsByVariety,
  });

  @override
  State<_ResultsEntrySheet> createState() => _ResultsEntrySheetState();
}

class _ResultsEntrySheetState extends State<_ResultsEntrySheet> {
  bool _saving = false;
  String? _msg;

  late final TextEditingController _dqReason;

  late bool _isShown;
  late bool _isDisqualified;

  String? _placement;
  String? _judgeId;
  late Set<String> _selectedAwards;

  String get _entryUuid {
    final raw = widget.entry['entry_id'] ?? widget.entry['id'] ?? '';
    return raw.toString().trim();
  }

  @override
  void initState() {
    super.initState();

    _dqReason = TextEditingController(
      text: (widget.entry['disqualified_reason'] ?? '').toString(),
    );

    _isShown = widget.entry['is_shown'] != false;
    _isDisqualified = widget.entry['is_disqualified'] == true;

    _judgeId = (widget.entry['judged_by_show_judge_id'] ?? '').toString().trim();
    if (_judgeId != null && _judgeId!.isEmpty) {
      _judgeId = null;
    }

    final currentPlacement = (widget.entry['placement'] ?? '').toString().trim();
    _placement = currentPlacement.isEmpty ? null : currentPlacement;

    _selectedAwards = (((widget.entry['_awards'] as List?) ?? const [])
            .map((x) => x.toString().trim())
            .where((x) => x.isNotEmpty))
        .toSet();

    if ((_placement == null || _placement!.isEmpty) &&
        widget.shownCount == 1 &&
        _isShown &&
        !_isDisqualified &&
        !_isScratched(widget.entry)) {
      _placement = '1';
    }
  }

  @override
  void dispose() {
    _dqReason.dispose();
    super.dispose();
  }

  bool _isScratched(Map<String, dynamic> e) {
    return (e['scratched_at'] ?? '').toString().trim().isNotEmpty;
  }

  String _sex(Map<String, dynamic> e) => (e['sex'] ?? '').toString().trim().toLowerCase();

  String _breed(Map<String, dynamic> e) => (e['breed'] ?? '').toString().trim();

  String _variety(Map<String, dynamic> e) => (e['variety'] ?? '').toString().trim();

  String _groupName(Map<String, dynamic> e) => (e['group_name'] ?? '').toString().trim();

  String _entryId(Map<String, dynamic> e) =>
    (e['entry_id'] ?? e['id'] ?? '').toString().trim();

  String _sectionId(Map<String, dynamic> e) => (e['section_id'] ?? '').toString().trim();

  List<String> _entryAwards(Map<String, dynamic> e) =>
      (((e['_awards'] as List?) ?? const []).map((x) => x.toString().trim()).where((x) => x.isNotEmpty))
          .toList();

  bool _isEligibleForAwards(Map<String, dynamic> e) {
    final scratched = _isScratched(e);
    final isShown = e['is_shown'] != false;
    final isDisqualified = e['is_disqualified'] == true;
    return !scratched && isShown && !isDisqualified;
  }

  String _classSystemForEntry(Map<String, dynamic> e) {
    final breedLower = _breed(e).toLowerCase();
    return widget.breedClassSystems[breedLower] ?? 'four';
  }

  bool _breedUsesGroups() => widget.showsByGroup;
  bool get _showsByVariety => widget.showsByVariety;

  List<String> get _visibleAwardCodes {
    final awards = <String>[];

    if (widget.showsByGroup) {
      awards.addAll(const ['BOG', 'BOSG']);
    }

    if (_showsByVariety) {
      awards.addAll(const ['BOV', 'BOSV']);
    }

    awards.addAll(const ['BOB', 'BOSB']);

    if (widget.finalAwardMode == 'bis_ris') {
      awards.addAll(const ['Best In Show', 'Reserve In Show']);
    } else {
      awards.addAll(const ['Best 4-Class', 'Best 6-Class', 'Best In Show']);
    }

    return awards;
  }

  List<String> _placementOptions() {
    final current = (_placement ?? '').trim();
    final options = [...widget.availablePlacements];
    if (current.isNotEmpty && !options.contains(current)) {
      options.add(current);
    }
    options.sort((a, b) {
      final ai = int.tryParse(a) ?? 999;
      final bi = int.tryParse(b) ?? 999;
      return ai.compareTo(bi);
    });
    return options;
  }

  bool _hasAward(String award) => _selectedAwards.contains(award);

  Map<String, dynamic>? _winnerForAwardInScope({
    required String award,
    required bool Function(Map<String, dynamic>) sameScope,
  }) {
    for (final e in widget.classEntries) {
      if (_entryId(e) == _entryId(widget.entry)) continue;
      if (!sameScope(e)) continue;
      final awards = _entryAwards(e);
      if (awards.contains(award)) return e;
    }
    return null;
  }

  bool _isOppositeSexOf(Map<String, dynamic>? other) {
    if (other == null) return true;
    final mySex = _sex(widget.entry);
    final otherSex = _sex(other);
    if (mySex.isEmpty || otherSex.isEmpty) return true;
    return mySex != otherSex;
  }

  bool _canUseAward(String award) {
    if (!_isEligibleForAwards(widget.entry)) return false;

    final currentAwards = _selectedAwards;

    switch (award) {
      case 'BOG':
      case 'BOSG':
        return _breedUsesGroups();

      case 'BOV':
      case 'BOSV':
        return _showsByVariety;

      case 'BOB':
      case 'BOSB':
        if (_breedUsesGroups()) {
          return currentAwards.contains('BOG') || currentAwards.contains('BOSG');
        }
        if (_showsByVariety) {
          return currentAwards.contains('BOV') || currentAwards.contains('BOSV');
        }
        return true;

      case 'Best 4-Class':
        return _classSystemForEntry(widget.entry) == 'four' && currentAwards.contains('BOB');

      case 'Best 6-Class':
        return _classSystemForEntry(widget.entry) == 'six' && currentAwards.contains('BOB');

      case 'Best In Show':
        if (widget.finalAwardMode == 'four_six_bis') {
          return currentAwards.contains('Best 4-Class') || currentAwards.contains('Best 6-Class');
        }
        return currentAwards.contains('BOB');

      case 'Reserve In Show':
        if (widget.finalAwardMode == 'bis_ris') {
          return currentAwards.contains('BOB');
        }
        return false;
    }

    return false;
  }

  String? _validateAwards() {
    if (!_isEligibleForAwards(widget.entry) && _selectedAwards.isNotEmpty) {
      return 'This rabbit cannot receive awards because it is scratched, disqualified, or not shown.';
    }

    bool sameVariety(Map<String, dynamic> e) =>
        _sectionId(e) == _sectionId(widget.entry) &&
        _breed(e).toLowerCase() == _breed(widget.entry).toLowerCase() &&
        _variety(e).toLowerCase() == _variety(widget.entry).toLowerCase();

    bool sameGroup(Map<String, dynamic> e) =>
        _sectionId(e) == _sectionId(widget.entry) &&
        _breed(e).toLowerCase() == _breed(widget.entry).toLowerCase() &&
        _groupName(e).toLowerCase() == _groupName(widget.entry).toLowerCase();

    bool sameBreed(Map<String, dynamic> e) =>
        _sectionId(e) == _sectionId(widget.entry) &&
        _breed(e).toLowerCase() == _breed(widget.entry).toLowerCase();

    bool sameSection(Map<String, dynamic> e) => _sectionId(e) == _sectionId(widget.entry);

    if (_hasAward('BOV')) {
      final existing = _winnerForAwardInScope(award: 'BOV', sameScope: sameVariety);
      if (existing != null) return 'BOV is already assigned for this variety.';
      final bosv = _winnerForAwardInScope(award: 'BOSV', sameScope: sameVariety);
      if (!_isOppositeSexOf(bosv)) return 'BOV and BOSV must be opposite sex.';
    }

    if (_hasAward('BOSV')) {
      final existing = _winnerForAwardInScope(award: 'BOSV', sameScope: sameVariety);
      if (existing != null) return 'BOSV is already assigned for this variety.';
      final bov = _winnerForAwardInScope(award: 'BOV', sameScope: sameVariety);
      if (!_isOppositeSexOf(bov)) return 'BOV and BOSV must be opposite sex.';
    }

    if (_hasAward('BOG')) {
      final existing = _winnerForAwardInScope(award: 'BOG', sameScope: sameGroup);
      if (existing != null) return 'BOG is already assigned for this group.';
      final bosg = _winnerForAwardInScope(award: 'BOSG', sameScope: sameGroup);
      if (!_isOppositeSexOf(bosg)) return 'BOG and BOSG must be opposite sex.';
    }

    if (_hasAward('BOSG')) {
      final existing = _winnerForAwardInScope(award: 'BOSG', sameScope: sameGroup);
      if (existing != null) return 'BOSG is already assigned for this group.';
      final bog = _winnerForAwardInScope(award: 'BOG', sameScope: sameGroup);
      if (!_isOppositeSexOf(bog)) return 'BOG and BOSG must be opposite sex.';
    }

    if (_hasAward('BOB')) {
      final existing = _winnerForAwardInScope(award: 'BOB', sameScope: sameBreed);
      if (existing != null) return 'BOB is already assigned for this breed.';
      final bosb = _winnerForAwardInScope(award: 'BOSB', sameScope: sameBreed);
      if (!_isOppositeSexOf(bosb)) return 'BOB and BOSB must be opposite sex.';

      if (_breedUsesGroups()) {
        if (!(_hasAward('BOG') || _hasAward('BOSG'))) {
          return 'BOB can only be selected from BOG/BOSG winners for group breeds.';
        }
      } else if (_showsByVariety) {
        if (!(_hasAward('BOV') || _hasAward('BOSV'))) {
          return 'BOB can only be selected from BOV/BOSV winners for breeds with variety awards.';
        }
      }
    }

    if (_hasAward('BOSB')) {
      final existing = _winnerForAwardInScope(award: 'BOSB', sameScope: sameBreed);
      if (existing != null) return 'BOSB is already assigned for this breed.';
      final bob = _winnerForAwardInScope(award: 'BOB', sameScope: sameBreed);
      if (!_isOppositeSexOf(bob)) return 'BOB and BOSB must be opposite sex.';

      if (_breedUsesGroups()) {
        if (!(_hasAward('BOG') || _hasAward('BOSG'))) {
          return 'BOSB can only be selected from BOG/BOSG winners for group breeds.';
        }
      } else if (_showsByVariety) {
        if (!(_hasAward('BOV') || _hasAward('BOSV'))) {
          return 'BOSB can only be selected from BOV/BOSV winners for breeds with variety awards.';
        }
      }
    }

    if (_hasAward('Best 4-Class')) {
      final existing = _winnerForAwardInScope(award: 'Best 4-Class', sameScope: sameSection);
      if (existing != null) return 'Best 4-Class is already assigned in this section.';
      if (!_canUseAward('Best 4-Class')) return 'Best 4-Class requires a 4-class breed and BOB.';
    }

    if (_hasAward('Best 6-Class')) {
      final existing = _winnerForAwardInScope(award: 'Best 6-Class', sameScope: sameSection);
      if (existing != null) return 'Best 6-Class is already assigned in this section.';
      if (!_canUseAward('Best 6-Class')) return 'Best 6-Class requires a 6-class breed and BOB.';
    }

    if (_hasAward('Best In Show')) {
      final existing = _winnerForAwardInScope(award: 'Best In Show', sameScope: sameSection);
      if (existing != null) return 'Best In Show is already assigned in this section.';
      if (!_canUseAward('Best In Show')) {
        return widget.finalAwardMode == 'four_six_bis'
            ? 'Best In Show must come from Best 4-Class or Best 6-Class.'
            : 'Best In Show must come from a breed winner.';
      }
    }

    if (_hasAward('Reserve In Show')) {
      final existing = _winnerForAwardInScope(award: 'Reserve In Show', sameScope: sameSection);
      if (existing != null) return 'Reserve In Show is already assigned in this section.';
      if (!_canUseAward('Reserve In Show')) return 'Reserve In Show is only available in BIS/RIS mode.';
      if (_hasAward('Best In Show')) return 'This rabbit cannot be both Best In Show and Reserve In Show.';
      final bis = _winnerForAwardInScope(award: 'Best In Show', sameScope: sameSection);
      if (bis != null && _entryId(bis) == _entryId(widget.entry)) {
        return 'This rabbit cannot be both Best In Show and Reserve In Show.';
      }
    }

    return null;
  }

  String _awardDisabledReason(String award) {
    switch (award) {
      case 'BOG':
      case 'BOSG':
        return 'Only for breeds judged by group.';
      case 'BOV':
      case 'BOSV':
        return 'Only for breeds with variety awards.';
      case 'BOB':
      case 'BOSB':
        return 'Requires BOV/BOSV or BOG/BOSG first.';
      case 'Best 4-Class':
        return 'Requires BOB from a 4-class breed.';
      case 'Best 6-Class':
        return 'Requires BOB from a 6-class breed.';
      case 'Best In Show':
        return widget.finalAwardMode == 'four_six_bis'
            ? 'Requires Best 4-Class or Best 6-Class.'
            : 'Requires breed winner.';
      case 'Reserve In Show':
        return 'Only used in BIS/RIS mode.';
      default:
        return 'Not eligible right now.';
    }
  }

  Future<void> _save({required bool goNext}) async {
    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      final entryId = _entryUuid;
      if (entryId.isEmpty) {
        throw Exception('Entry ID is missing.');
      }

      final scratched = _isScratched(widget.entry);
      final shouldClearPlacement = !_isShown || _isDisqualified || scratched;

      final awardError = _validateAwards();
      if (awardError != null) {
        setState(() {
          _saving = false;
          _msg = awardError;
        });
        return;
      }

      await supabase
          .from('entries')
          .update({
            'placement': shouldClearPlacement ? null : _placement,
            'disqualified_reason': _isDisqualified
                ? (_dqReason.text.trim().isEmpty ? null : _dqReason.text.trim())
                : null,
            'is_shown': _isShown,
            'is_disqualified': _isDisqualified,
            'judged_by_show_judge_id': _judgeId,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', entryId);

      await supabase
          .from('entry_awards')
          .delete()
          .eq('show_id', widget.showId)
          .eq('entry_id', entryId);

      if (_selectedAwards.isNotEmpty) {
        await supabase.from('entry_awards').insert(
              _selectedAwards.map((award) {
                return {
                  'show_id': widget.showId,
                  'entry_id': entryId,
                  'award_code': award,
                };
              }).toList(),
            );
      }

      if (!mounted) return;
      Navigator.pop(
        context,
        _ResultsEntryOutcome(goNext: goNext),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _msg = 'Save failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tattoo = (widget.entry['tattoo'] ?? '').toString();
    final breed = (widget.entry['breed'] ?? '').toString();
    final groupName = (widget.entry['group_name'] ?? '').toString();
    final variety = (widget.entry['variety'] ?? '').toString();
    final sex = (widget.entry['sex'] ?? '').toString();
    final className = (widget.entry['class_name'] ?? '').toString();
    final scratched = _isScratched(widget.entry);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final placementOptions = _placementOptions();
    final canPlace = !scratched && _isShown && !_isDisqualified;
    final canAward = !scratched && _isShown && !_isDisqualified;

    if (!canPlace) {
      _placement = null;
    }

    if (!canAward) {
      _selectedAwards.clear();
    }

    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 10, bottom: bottomInset + 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Record Results (${widget.currentIndex + 1} of ${widget.totalCount})',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (_msg != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(_msg!, style: const TextStyle(color: Colors.red)),
              ),
            Text(
              [
                breed,
                if (groupName.trim().isNotEmpty) groupName,
                variety,
                sex,
                className,
              ].where((x) => x.trim().isNotEmpty).join(' • '),
            ),
            const SizedBox(height: 4),
            Text('Ear #: ${tattoo.isEmpty ? '(No ear #)' : tattoo}'),
            if (scratched) ...[
              const SizedBox(height: 6),
              const Text(
                'This animal is scratched. Placement and awards will be cleared.',
                style: TextStyle(color: Colors.red),
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _judgeId,
              decoration: const InputDecoration(
                labelText: 'Judge',
              ),
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
              onChanged: _saving
                  ? null
                  : (v) {
                      setState(() {
                        _judgeId = (v == null || v.isEmpty) ? null : v;
                      });
                    },
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              value: _isShown,
              onChanged: scratched || _saving
                  ? null
                  : (v) {
                      setState(() {
                        _isShown = v;
                        if (!_isShown) {
                          _placement = null;
                          _selectedAwards.clear();
                        }
                      });
                    },
              title: const Text('Animal was shown'),
            ),
            SwitchListTile(
              value: _isDisqualified,
              onChanged: scratched || _saving
                  ? null
                  : (v) {
                      setState(() {
                        _isDisqualified = v;
                        if (_isDisqualified) {
                          _placement = null;
                          _selectedAwards.clear();
                        }
                      });
                    },
              title: const Text('Disqualified'),
            ),
            const SizedBox(height: 10),
            if (canPlace)
              DropdownButtonFormField<String>(
                value: (_placement != null && placementOptions.contains(_placement)) ? _placement : null,
                decoration: const InputDecoration(
                  labelText: 'Placement',
                ),
                items: placementOptions
                    .map(
                      (p) => DropdownMenuItem<String>(
                        value: p,
                        child: Text(p),
                      ),
                    )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (v) {
                        setState(() {
                          _placement = v;
                        });
                      },
              ),
            if (canPlace) const SizedBox(height: 14),
            Text(
              'Awards',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ..._visibleAwardCodes.map((award) {
              final allowed = _canUseAward(award);
              final checked = _selectedAwards.contains(award);

              return CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: checked,
                title: Text(award),
                subtitle: !allowed && canAward ? Text(_awardDisabledReason(award)) : null,
                onChanged: (!canAward || _saving || !allowed)
                    ? null
                    : (v) {
                        setState(() {
                          if (v == true) {
                            _selectedAwards.add(award);
                          } else {
                            _selectedAwards.remove(award);
                          }
                        });
                      },
              );
            }),
            if (_isDisqualified) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _dqReason,
                enabled: !_saving,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Disqualification Reason',
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : () => _save(goNext: false),
                    child: Text(_saving ? 'Saving…' : 'Save'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : () => _save(goNext: true),
                    child: const Text('Save & Next'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ValidationIssue {
  final String code;
  final String title;
  final String message;

  final Map<String, dynamic> entry;
  final Map<String, dynamic>? conflictsWith;

  final String breed;
  final String? groupName;
  final String? variety;
  final String classSexLabel;

  const _ValidationIssue({
    required this.code,
    required this.title,
    required this.message,
    required this.entry,
    required this.conflictsWith,
    required this.breed,
    required this.groupName,
    required this.variety,
    required this.classSexLabel,
  });
}