// lib/screens/admin/closeout/data/loaders/arba_report_loader.dart

import '../../models/arba/arba_report_data.dart';
import '../../models/base/report_request.dart';
import '../closeout_repository.dart';

class ArbaReportLoader {
  ArbaReportLoader(this.repo);

  final CloseoutRepository repo;

  Future<ArbaReportData> load(ReportRequest request) async {
    final artifactContext = await _loadArtifactContext(request);

    final sectionId = artifactContext.sectionId;
    final showLetter = artifactContext.showLetter;

    final show = await repo.loadShowBasics(request.showId);
    final arbaDetails = await _loadArbaDetails(request.showId);

    final showNameBase = _str(show['name']);
    final showName = [
      showNameBase,
      if (showLetter.isNotEmpty) showLetter,
    ].where((e) => e.isNotEmpty).join(' - ');

    final secretaryName = _firstNonEmpty([
      _str(arbaDetails?['secretary_name']),
      _str(show['secretary_name']),
    ]);

    final secretaryEmail = _firstNonEmpty([
      _str(arbaDetails?['secretary_email']),
      _str(show['secretary_email']),
    ]);

    final secretaryPhone = _firstNonEmpty([
      _str(arbaDetails?['secretary_phone']),
      _str(show['secretary_phone']),
    ]);

    final secretaryAddress = _firstNonEmpty([
      _str(arbaDetails?['secretary_address']),
      await _loadSecretaryAddress(),
    ]);

    final superintendentName = await _loadSuperintendentName(request.showId);
    final superintendentArbaNumber =
        await _loadSuperintendentArbaNumber(request.showId);

    final sweepstakesIssue = arbaDetails?['sweepstakes_issue'] == true;
    final sweepstakesClub = _str(arbaDetails?['sweepstakes_club']);

    final officialProtest = arbaDetails?['official_protest'] == true;
    final arbaReportFiled =
        officialProtest && arbaDetails?['arba_report_filed'] == true;

    final sanctionNumber = await _loadSanctionNumber(
      request.showId,
      sectionId: sectionId,
    );

    final clubName = await _loadClubName(
      request.showId,
      sectionId: sectionId,
    );

    final rabbitsShown = await _countShownSpecies(
      request.showId,
      'rabbit',
      sectionId: sectionId,
    );

    final caviesShown = await _countShownSpecies(
      request.showId,
      'cavy',
      sectionId: sectionId,
    );

    final showDate = _tryParseDate(show['start_date']);
    final reportDate = DateTime.now();

    final showLocation = [
      _str(show['location_name']),
      _str(show['location_address']),
    ].where((e) => e.isNotEmpty).join(', ');

    final ribbonsReportsMailedAt = await _loadGeneratedAt(
      request.showId,
      const ['exhibitor_report', 'legs'],
    );

    final sweepstakesReportsFiledAt = await _loadGeneratedAt(
      request.showId,
      const ['sweepstakes_report'],
    );

    final judges = await _loadJudgeNamesFromEntries(
      request.showId,
      sectionId: sectionId,
    );

    final signedBy =
        secretaryName.isNotEmpty ? secretaryName : await _loadSignedByName();

    final filedDate = DateTime.now();

    final bisRabbit = await _loadBestAward(
      request.showId,
      species: 'rabbit',
      awardCodes: const [
        'best in show',
        'best of show',
        'bis',
        'bis rabbit',
        'best in show rabbit',
        'best of show rabbit',
      ],
      fallbackAwardCodes: const ['BOB', 'best of breed'],
      sectionId: sectionId,
    );

    return ArbaReportData(
      showName: showName,
      secretaryName: secretaryName,
      secretaryEmail: secretaryEmail,
      secretaryPhone: secretaryPhone,
      sanctionNumber: sanctionNumber,
      reportDate: reportDate,
      rabbitsShown: rabbitsShown,
      caviesShown: caviesShown,
      clubName: clubName.isNotEmpty ? clubName : showNameBase,
      showDate: showDate,
      showLocation: showLocation,
      secretaryAddress: secretaryAddress,
      superintendentName: superintendentName,
      superintendentArbaNumber: superintendentArbaNumber,
      ribbonsReportsMailedAt: ribbonsReportsMailedAt,
      sweepstakesReportsFiledAt: sweepstakesReportsFiledAt,
      judges: judges,
      troubleReceivingSanctions: _yesNo(sweepstakesIssue),
      troubleReceivingSanctionClubs:
          sweepstakesIssue ? _naIfEmpty(sweepstakesClub) : 'N/A',
      filedDate: filedDate,
      signedBy: signedBy,
      protestFiled: _yesNo(officialProtest),
      protestReportFiled: officialProtest ? _yesNo(arbaReportFiled) : 'N/A',
      bisRabbitOwner: bisRabbit.owner,
      bisRabbitCityState: bisRabbit.cityState,
      bisRabbitBreed: bisRabbit.breed,
      bisRabbitEarNumber: bisRabbit.earNumber,
    );
  }

  Future<List<String>> _loadJudgeNamesFromEntries(
    String showId, {
    String? sectionId,
  }) async {
    try {
      var query = repo.supabase
          .from('entries')
          .select('judged_by_show_judge_id')
          .eq('show_id', showId)
          .not('judged_by_show_judge_id', 'is', null);

      if (sectionId != null && sectionId.trim().isNotEmpty) {
        query = query.eq('section_id', sectionId.trim());
      }

      final rows = await query;

      final judgeIds = List<Map<String, dynamic>>.from(rows)
          .map((e) => _str(e['judged_by_show_judge_id']))
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();

      if (judgeIds.isEmpty) return const [];

      final judgeRows = await repo.supabase
          .from('judges')
          .select('id, name, display_name, first_name, last_name, arba_judge_number')
          .inFilter('id', judgeIds);

      return List<Map<String, dynamic>>.from(judgeRows).map((j) {
        final name = _firstNonEmpty([
          _str(j['display_name']),
          _str(j['name']),
          [
            _str(j['first_name']),
            _str(j['last_name']),
          ].where((e) => e.isNotEmpty).join(' '),
        ]);

        final number = _str(j['arba_judge_number']);
        return number.isEmpty ? name : '$name - $number';
      }).where((e) => e.trim().isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, dynamic>?> _loadArbaDetails(String showId) async {
    try {
      final row = await repo.supabase
          .from('show_arba_report_details')
          .select('''
            secretary_name,
            secretary_address,
            secretary_email,
            secretary_phone,
            superintendent_name,
            superintendent_arba_number,
            sweepstakes_issue,
            sweepstakes_club,
            official_protest,
            arba_report_filed
          ''')
          .eq('show_id', showId)
          .maybeSingle();

      return row == null ? null : Map<String, dynamic>.from(row);
    } catch (_) {
      return null;
    }
  }

  Future<_ArbaArtifactContext> _loadArtifactContext(
    ReportRequest request,
  ) async {
    try {
      final artifactId = _reportArtifactIdFromRequest(request);
      if (artifactId.isEmpty) {
        return const _ArbaArtifactContext.empty();
      }

      final row = await repo.supabase
          .from('show_report_artifacts')
          .select('id, metadata')
          .eq('id', artifactId)
          .maybeSingle();

      if (row == null) {
        return const _ArbaArtifactContext.empty();
      }

      final metadata = row['metadata'] is Map
          ? Map<String, dynamic>.from(row['metadata'] as Map)
          : <String, dynamic>{};

      return _ArbaArtifactContext(
        artifactId: artifactId,
        sectionId: _str(metadata['section_id']),
        showLetter: _str(metadata['show_letter']),
        sectionLabel: _str(metadata['section_label']),
        scope: _str(metadata['scope']),
      );
    } catch (_) {
      return const _ArbaArtifactContext.empty();
    }
  }

  String _reportArtifactIdFromRequest(ReportRequest request) {
    try {
      final dynamic raw = (request as dynamic).artifactId;
      return _str(raw);
    } catch (_) {
      return '';
    }
  }

  Future<String> _loadSanctionNumber(
    String showId, {
    String? sectionId,
  }) async {
    try {
      final row = (sectionId != null && sectionId.trim().isNotEmpty)
          ? await repo.supabase
              .from('show_sanctions')
              .select('sanction_number')
              .eq('show_id', showId)
              .eq('sanctioning_body', 'ARBA')
              .eq('section_id', sectionId.trim())
              .limit(1)
              .maybeSingle()
          : await repo.supabase
              .from('show_sanctions')
              .select('sanction_number')
              .eq('show_id', showId)
              .eq('sanctioning_body', 'ARBA')
              .limit(1)
              .maybeSingle();

      if (row == null) return '';
      return _str(row['sanction_number']);
    } catch (_) {
      return '';
    }
  }

  Future<String> _loadClubName(
    String showId, {
    String? sectionId,
  }) async {
    try {
      final row = (sectionId != null && sectionId.trim().isNotEmpty)
          ? await repo.supabase
              .from('show_sanctions')
              .select('club_name')
              .eq('show_id', showId)
              .eq('sanctioning_body', 'ARBA')
              .eq('section_id', sectionId.trim())
              .limit(1)
              .maybeSingle()
          : await repo.supabase
              .from('show_sanctions')
              .select('club_name')
              .eq('show_id', showId)
              .eq('sanctioning_body', 'ARBA')
              .limit(1)
              .maybeSingle();

      if (row == null) return '';
      return _str(row['club_name']);
    } catch (_) {
      return '';
    }
  }

  Future<int> _countShownSpecies(
    String showId,
    String species, {
    String? sectionId,
  }) async {
    try {
      final rows = (sectionId != null && sectionId.trim().isNotEmpty)
          ? await repo.supabase
              .from('entries')
              .select('id')
              .eq('show_id', showId)
              .eq('is_shown', true)
              .eq('species', species)
              .eq('section_id', sectionId.trim())
          : await repo.supabase
              .from('entries')
              .select('id')
              .eq('show_id', showId)
              .eq('is_shown', true)
              .eq('species', species);

      return (rows as List).length;
    } catch (_) {
      return 0;
    }
  }

  Future<String> _loadSecretaryAddress() async {
    try {
      final user = repo.supabase.auth.currentUser;
      if (user == null) return '';

      final row = await repo.supabase
          .from('user_profiles')
          .select('address1,address2,city,state,postal_code')
          .eq('user_id', user.id)
          .maybeSingle();

      if (row == null) return '';

      return [
        _str(row['address1']),
        _str(row['address2']),
        _str(row['city']),
        _str(row['state']),
        _str(row['postal_code']),
      ].where((e) => e.isNotEmpty).join(', ');
    } catch (_) {
      return '';
    }
  }

  Future<String> _loadSuperintendentName(String showId) async {
    try {
      final row = await repo.supabase
          .from('show_arba_report_details')
          .select('superintendent_name')
          .eq('show_id', showId)
          .maybeSingle();

      if (row == null) return '';
      return _str(row['superintendent_name']);
    } catch (_) {
      return '';
    }
  }

  Future<String> _loadSuperintendentArbaNumber(String showId) async {
    try {
      final row = await repo.supabase
          .from('show_arba_report_details')
          .select('superintendent_arba_number')
          .eq('show_id', showId)
          .maybeSingle();

      if (row == null) return '';
      return _str(row['superintendent_arba_number']);
    } catch (_) {
      return '';
    }
  }

  Future<DateTime?> _loadGeneratedAt(
    String showId,
    List<String> reportNames,
  ) async {
    try {
      final rows = await repo.supabase
          .from('show_report_artifacts')
          .select('report_name,generated_at,is_current,artifact_status')
          .eq('show_id', showId)
          .eq('is_current', true)
          .eq('artifact_status', 'generated');

      final list = List<Map<String, dynamic>>.from(rows);

      for (final reportName in reportNames) {
        for (final row in list) {
          if (_str(row['report_name']) == reportName) {
            final parsed = _tryParseDate(row['generated_at']);
            if (parsed != null) return parsed;
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> _loadJudgeNames(
    String showId, {
    String? sectionId,
  }) async {
    try {
      Future<List<Map<String, dynamic>>> loadAssignments({bool filterSection = false}) async {
        var query = repo.supabase
            .from('judge_assignments')
            .select('judge_id, assignment_label, created_at, section_id')
            .eq('show_id', showId);

        if (filterSection && sectionId != null && sectionId.trim().isNotEmpty) {
          query = query.eq('section_id', sectionId.trim());
        }

        final rows = await query.order('created_at');
        return List<Map<String, dynamic>>.from(rows);
      }

      var assignments = await loadAssignments(
        filterSection: sectionId != null && sectionId.trim().isNotEmpty,
      );

      // Fallback: if nothing matched the section, use all judges for the show
      if (assignments.isEmpty) {
        assignments = await loadAssignments(filterSection: false);
      }

      if (assignments.isEmpty) return const [];

      final judgeIds = assignments
          .map((e) => _str(e['judge_id']))
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();

      if (judgeIds.isEmpty) return const [];

      final judgeRows = await repo.supabase
          .from('judges')
          .select('id, name, first_name, last_name, arba_judge_number')
          .inFilter('id', judgeIds);

      final judges = List<Map<String, dynamic>>.from(judgeRows);

      final byId = <String, Map<String, dynamic>>{};
      for (final row in judges) {
        byId[_str(row['id'])] = row;
      }

      final seen = <String>{};
      final output = <String>[];

      for (final assignment in assignments) {
        final judgeId = _str(assignment['judge_id']);
        if (judgeId.isEmpty || seen.contains(judgeId)) continue;

        final judge = byId[judgeId];
        if (judge == null) continue;

        final name = _str(judge['name']).isNotEmpty
            ? _str(judge['name'])
            : [
                _str(judge['first_name']),
                _str(judge['last_name']),
              ].where((e) => e.isNotEmpty).join(' ');

        final arbaNumber = _str(judge['arba_judge_number']);

        if (name.isEmpty && arbaNumber.isEmpty) continue;

        output.add(arbaNumber.isEmpty ? name : '$name - $arbaNumber');
        seen.add(judgeId);
      }

      return output;
    } catch (_) {
      return const [];
    }
  }

  Future<String> _loadSignedByName() async {
    try {
      final user = repo.supabase.auth.currentUser;
      if (user == null) return '';

      final row = await repo.supabase
          .from('user_profiles')
          .select('first_name,last_name,showing_name,email')
          .eq('user_id', user.id)
          .maybeSingle();

      if (row == null) return '';

      final fullName = [
        _str(row['first_name']),
        _str(row['last_name']),
      ].where((e) => e.isNotEmpty).join(' ');

      if (fullName.isNotEmpty) return fullName;
      if (_str(row['showing_name']).isNotEmpty) return _str(row['showing_name']);
      return _str(row['email']);
    } catch (_) {
      return '';
    }
  }

  Future<_ArbaBestAwardInfo> _loadBestAward(
    String showId, {
    required String species,
    required List<String> awardCodes,
    List<String> fallbackAwardCodes = const [],
    String? sectionId,
  }) async {
    try {
      final rows = await repo.supabase.rpc(
        'report_results_entry_rows',
        params: {'p_show_id': showId},
      );

      final normalizedSpecies = species.toLowerCase().trim();
      final targetSectionId = sectionId?.trim() ?? '';

      final entries = (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) {
            final rowSpecies = _str(e['species']).toLowerCase().trim();
            if (rowSpecies.isEmpty) return normalizedSpecies == 'rabbit';
            return rowSpecies == normalizedSpecies;
          })
          .where((e) {
            if (targetSectionId.isEmpty) return true;
            return _str(e['section_id']) == targetSectionId;
          })
          .toList();

      final entryIds = entries
          .map((e) => _str(e['entry_id']))
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();

      if (entryIds.isEmpty) return const _ArbaBestAwardInfo.empty();

      final awardRows = await repo.supabase
          .from('entry_awards')
          .select('entry_id, award_code')
          .eq('show_id', showId)
          .inFilter('entry_id', entryIds);

      final normalizedAwardCodes = awardCodes.map(_normalizeAwardCode).toSet();
      final normalizedFallbackAwardCodes =
          fallbackAwardCodes.map(_normalizeAwardCode).toSet();

      String? awardEntryId = _findAwardEntryId(
        awardRows as List,
        normalizedAwardCodes,
      );

      if (awardEntryId == null || awardEntryId.isEmpty) {
        awardEntryId = _findAwardEntryId(
          awardRows,
          normalizedFallbackAwardCodes,
        );
      }

      if (awardEntryId == null || awardEntryId.isEmpty) {
        return const _ArbaBestAwardInfo.empty();
      }

      final entry = entries.firstWhere(
        (e) => _str(e['entry_id']) == awardEntryId,
        orElse: () => <String, dynamic>{},
      );

      if (entry.isEmpty) return const _ArbaBestAwardInfo.empty();

      final owner = _firstNonEmpty([
        _str(entry['exhibitor_showing_name']),
        _str(entry['exhibitor_label']),
        [
          _str(entry['exhibitor_first_name']),
          _str(entry['exhibitor_last_name']),
        ].where((e) => e.isNotEmpty).join(' '),
      ]);

      final cityState = [
        _str(entry['exhibitor_city']),
        _str(entry['exhibitor_state']),
      ].where((e) => e.isNotEmpty).join(', ');

      return _ArbaBestAwardInfo(
        owner: owner,
        cityState: cityState,
        breed: _firstNonEmpty([
          _str(entry['breed_name']),
          _str(entry['breed']),
        ]),
        earNumber: _str(entry['tattoo']),
      );
    } catch (_) {
      return const _ArbaBestAwardInfo.empty();
    }
  }

  String? _findAwardEntryId(
    List<dynamic> awardRows,
    Set<String> normalizedAwardCodes,
  ) {
    if (normalizedAwardCodes.isEmpty) return null;

    for (final raw in awardRows) {
      final row = Map<String, dynamic>.from(raw as Map);
      final award = _normalizeAwardCode(_str(row['award_code']));

      if (normalizedAwardCodes.contains(award)) {
        return _str(row['entry_id']);
      }

      for (final target in normalizedAwardCodes) {
        if (award.contains(target) || target.contains(award)) {
          return _str(row['entry_id']);
        }
      }
    }

    return null;
  }

  String _normalizeAwardCode(String value) {
    return value
        .toLowerCase()
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _yesNo(bool value) => value ? 'Yes' : 'No';

  String _naIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'N/A' : trimmed;
  }

  String _firstNonEmpty(List<String> values) {
    for (final value in values) {
      if (value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  String _str(dynamic value) {
    if (value == null) return '';
    return value.toString().trim();
  }

  DateTime? _tryParseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }
}

class _ArbaArtifactContext {
  final String artifactId;
  final String sectionId;
  final String showLetter;
  final String sectionLabel;
  final String scope;

  const _ArbaArtifactContext({
    required this.artifactId,
    required this.sectionId,
    required this.showLetter,
    required this.sectionLabel,
    required this.scope,
  });

  const _ArbaArtifactContext.empty()
      : artifactId = '',
        sectionId = '',
        showLetter = '',
        sectionLabel = '',
        scope = '';
}

class _ArbaBestAwardInfo {
  final String owner;
  final String cityState;
  final String breed;
  final String earNumber;

  const _ArbaBestAwardInfo({
    required this.owner,
    required this.cityState,
    required this.breed,
    required this.earNumber,
  });

  const _ArbaBestAwardInfo.empty()
      : owner = '',
        cityState = '',
        breed = '',
        earNumber = '';
}