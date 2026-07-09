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

    // ARBA reports must be scoped to one show section. If this is empty,
    // the report would fall back to full-show data and all ARBA PDFs would match.
    if (sectionId.isEmpty) {
      throw Exception(
        'ARBA report is missing section context. Regenerate from a queued ARBA artifact, not the manual ARBA report button.',
      );
    }

    final show = await repo.loadShowBasics(request.showId);
    final arbaDetails = await _loadArbaDetails(request.showId);

    final showNameBase = _str(show['name']);
    final sectionLabel = artifactContext.sectionLabel;
    final showName = [
      showNameBase,
      if (sectionLabel.isNotEmpty) sectionLabel,
      if (sectionLabel.isEmpty && showLetter.isNotEmpty) showLetter,
    ].where((e) => e.isNotEmpty).join(' - ');

    final secretaryName = _firstNonEmpty([
      _str(show['secretary_name']),
      _str(arbaDetails?['secretary_name']),
    ]);

    final secretaryEmail = _firstNonEmpty([
      _str(show['secretary_email']),
      _str(arbaDetails?['secretary_email']),
    ]);

    final secretaryPhone = _firstNonEmpty([
      _str(show['secretary_phone']),
      _str(arbaDetails?['secretary_phone']),
    ]);

    final secretaryAddress = _firstNonEmpty([
      _str(show['secretary_address']),
      _str(arbaDetails?['secretary_address']),
      await _loadSecretaryAddress(),
    ]);

    final superintendentName = await _loadSuperintendentName(request.showId);
    final superintendentArbaNumber = await _loadSuperintendentArbaNumber(
      request.showId,
    );

    final sweepstakesIssue = arbaDetails?['sweepstakes_issue'] == true;
    final sweepstakesClub = _str(arbaDetails?['sweepstakes_club']);

    final officialProtest = arbaDetails?['official_protest'] == true;
    final arbaReportFiled =
        officialProtest && arbaDetails?['arba_report_filed'] == true;

    final sanctionNumber = await _loadSanctionNumber(
      request.showId,
      sectionId: sectionId,
    );

    final clubName = _firstNonEmpty([
      _str(show['club_name']),
      await _loadClubName(request.showId, sectionId: sectionId),
    ]);

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

    final signedBy = secretaryName.isNotEmpty
        ? secretaryName
        : await _loadSignedByName();

    final filedDate = DateTime.now();

    final bisRabbit = rabbitsShown == 0
        ? const _ArbaBestAwardInfo(
            owner: 'No rabbits shown',
            cityState: '',
            breed: '',
            earNumber: '',
          )
        : await _loadBestAward(
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

    final bisCavy = caviesShown == 0
        ? const _ArbaBestAwardInfo(
            owner: 'No cavies shown',
            cityState: '',
            breed: '',
            earNumber: '',
          )
        : await _loadBestAward(
            request.showId,
            species: 'cavy',
            awardCodes: const [
              'best in show',
              'best of show',
              'bis',
              'bis cavy',
              'best in show cavy',
              'best of show cavy',
            ],
            fallbackAwardCodes: const ['BOB', 'best of breed'],
            sectionId: sectionId,
          );

    final validationIssues = _validateRequiredArbaReportData(
      sanctionNumber: sanctionNumber,
      secretaryName: secretaryName,
      secretaryEmail: secretaryEmail,
      secretaryPhone: secretaryPhone,
      secretaryAddress: secretaryAddress,
      superintendentName: superintendentName,
      superintendentArbaNumber: superintendentArbaNumber,
      judges: judges,
      rabbitsShown: rabbitsShown,
      caviesShown: caviesShown,
      bisRabbit: bisRabbit,
      bisCavy: bisCavy,
    );

    if (validationIssues.isNotEmpty) {
      throw Exception(
        'ARBA report is blocked until required closeout data is complete: '
        '${validationIssues.join('; ')}.',
      );
    }

    return ArbaReportData(
      showName: showName,
      sectionId: sectionId,
      sectionLabel: artifactContext.sectionLabel,
      scope: artifactContext.scope,
      showLetter: showLetter,
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
      troubleReceivingSanctionClubs: sweepstakesIssue
          ? _naIfEmpty(sweepstakesClub)
          : 'N/A',
      filedDate: filedDate,
      signedBy: signedBy,
      protestFiled: _yesNo(officialProtest),
      protestReportFiled: officialProtest ? _yesNo(arbaReportFiled) : 'N/A',
      bisRabbitOwner: bisRabbit.owner,
      bisRabbitCityState: bisRabbit.cityState,
      bisRabbitBreed: bisRabbit.breed,
      bisRabbitEarNumber: bisRabbit.earNumber,
      bisCavyOwner: bisCavy.owner,
      bisCavyCityState: bisCavy.cityState,
      bisCavyBreed: bisCavy.breed,
      bisCavyEarNumber: bisCavy.earNumber,
    );
  }

  List<String> _validateRequiredArbaReportData({
    required String sanctionNumber,
    required String secretaryName,
    required String secretaryEmail,
    required String secretaryPhone,
    required String secretaryAddress,
    required String superintendentName,
    required String superintendentArbaNumber,
    required List<String> judges,
    required int rabbitsShown,
    required int caviesShown,
    required _ArbaBestAwardInfo bisRabbit,
    required _ArbaBestAwardInfo bisCavy,
  }) {
    final issues = <String>[];

    void requireText(String value, String label) {
      if (value.trim().isEmpty) issues.add(label);
    }

    requireText(sanctionNumber, 'ARBA sanction number');
    requireText(secretaryName, 'show secretary name');
    requireText(secretaryAddress, 'show secretary address');
    requireText(secretaryEmail, 'show secretary email');
    requireText(secretaryPhone, 'show secretary phone');
    requireText(superintendentName, 'show superintendent name');
    requireText(superintendentArbaNumber, 'show superintendent ARBA number');

    if (judges.where((judge) => judge.trim().isNotEmpty).isEmpty) {
      issues.add('at least one assigned judge');
    }

    if (rabbitsShown > 0) {
      _requireBestAwardInfo(issues, 'Best In Show Rabbit', bisRabbit);
    }

    if (caviesShown > 0) {
      _requireBestAwardInfo(issues, 'Best In Show Cavy', bisCavy);
    }

    return issues;
  }

  void _requireBestAwardInfo(
    List<String> issues,
    String label,
    _ArbaBestAwardInfo award,
  ) {
    final missing = <String>[];

    if (award.owner.trim().isEmpty) missing.add('owner');
    if (award.cityState.trim().isEmpty) missing.add('owner city/state');
    if (award.breed.trim().isEmpty) missing.add('breed');
    if (award.earNumber.trim().isEmpty) missing.add('ear number');

    if (missing.isNotEmpty) {
      issues.add('$label ${missing.join(', ')}');
    }
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
          .select(
            'id, name, display_name, first_name, last_name, arba_judge_number',
          )
          .inFilter('id', judgeIds);

      return List<Map<String, dynamic>>.from(judgeRows)
          .map((j) {
            final name = _firstNonEmpty([
              _str(j['display_name']),
              _str(j['name']),
              [
                _str(j['first_name']),
                _str(j['last_name']),
              ].where((e) => e.isNotEmpty).join(' '),
            ]);

            final number = _str(j['arba_judge_number']);
            if (number.isEmpty) return name;

            final normalizedName = name.toLowerCase();
            final normalizedNumber = number.toLowerCase();
            if (normalizedName.contains('#$normalizedNumber') ||
                normalizedName.contains('($normalizedNumber)') ||
                normalizedName.contains(normalizedNumber)) {
              return name;
            }

            return '$name - $number';
          })
          .where((e) => e.trim().isNotEmpty)
          .toList();
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

      if (artifactId.isNotEmpty) {
        final row = await repo.supabase
            .from('show_report_artifacts')
            .select('id, metadata')
            .eq('id', artifactId)
            .maybeSingle();

        if (row != null) {
          final metadata = row['metadata'] is Map
              ? Map<String, dynamic>.from(row['metadata'] as Map)
              : <String, dynamic>{};

          final context = _ArbaArtifactContext(
            artifactId: artifactId,
            sectionId: _str(metadata['section_id']),
            showLetter: _str(metadata['show_letter']),
            sectionLabel: _str(metadata['section_label']),
            scope: _str(metadata['scope']),
          );

          if (context.sectionId.isNotEmpty) {
            return context;
          }

          final resolved = await _resolveSectionContext(
            request.showId,
            scope: context.scope,
            showLetter: context.showLetter,
            artifactId: artifactId,
          );

          if (resolved.sectionId.isNotEmpty) {
            return resolved;
          }

          return context;
        }
      }

      // If no artifact row was found, fall back to request-level scope/letter.
      // This should only happen for manual generation paths.
      final fallbackScope = _requestString(request, 'scope');
      final fallbackShowLetter = _requestString(request, 'showLetter');

      if (fallbackScope.isEmpty && fallbackShowLetter.isEmpty) {
        return const _ArbaArtifactContext.empty();
      }

      return _resolveSectionContext(
        request.showId,
        scope: fallbackScope,
        showLetter: fallbackShowLetter,
        artifactId: artifactId,
      );
    } catch (_) {
      return const _ArbaArtifactContext.empty();
    }
  }

  Future<_ArbaArtifactContext> _resolveSectionContext(
    String showId, {
    required String scope,
    required String showLetter,
    String artifactId = '',
  }) async {
    try {
      var query = repo.supabase
          .from('show_sections')
          .select('id, kind, letter, display_name')
          .eq('show_id', showId)
          .eq('is_enabled', true);

      if (scope.trim().isNotEmpty) {
        query = query.ilike('kind', scope.trim());
      }

      if (showLetter.trim().isNotEmpty) {
        query = query.ilike('letter', showLetter.trim());
      }

      final row = await query.limit(1).maybeSingle();
      if (row == null) return const _ArbaArtifactContext.empty();

      final kind = _str(row['kind']).toUpperCase();
      final letter = _str(row['letter']).toUpperCase();
      final displayName = _str(row['display_name']);
      final sectionLabel = displayName.isNotEmpty
          ? displayName
          : [kind, letter].where((e) => e.isNotEmpty).join(' ');

      return _ArbaArtifactContext(
        artifactId: artifactId,
        sectionId: _str(row['id']),
        showLetter: letter,
        sectionLabel: sectionLabel,
        scope: kind,
      );
    } catch (_) {
      return const _ArbaArtifactContext.empty();
    }
  }

  String _requestString(ReportRequest request, String fieldName) {
    try {
      final dynamic value = (request as dynamic).toJson?[fieldName];
      return _str(value);
    } catch (_) {
      try {
        final dynamic value = (request as dynamic).metadata?[fieldName];
        return _str(value);
      } catch (_) {
        try {
          final dynamic value = fieldName == 'scope'
              ? (request as dynamic).scope
              : (request as dynamic).showLetter;
          return _str(value);
        } catch (_) {
          return '';
        }
      }
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

  Future<String> _loadSanctionNumber(String showId, {String? sectionId}) async {
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

  Future<String> _loadClubName(String showId, {String? sectionId}) async {
    try {
      final showRow = await repo.supabase
          .from('shows')
          .select('club_name')
          .eq('id', showId)
          .maybeSingle();

      if (showRow != null) {
        final showMap = Map<String, dynamic>.from(showRow as Map);
        final clubName = _str(showMap['club_name']);
        if (clubName.isNotEmpty) return clubName;
      }
    } catch (_) {
      // Fall through to sanction-table fallback below.
    }

    try {
      final row = (sectionId != null && sectionId.trim().isNotEmpty)
          ? await repo.supabase
                .from('show_sanctions')
                .select('club_name')
                .eq('show_id', showId)
                .neq('club_name', 'ARBA')
                .eq('section_id', sectionId.trim())
                .limit(1)
                .maybeSingle()
          : await repo.supabase
                .from('show_sanctions')
                .select('club_name')
                .eq('show_id', showId)
                .neq('club_name', 'ARBA')
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
      if (_str(row['showing_name']).isNotEmpty) {
        return _str(row['showing_name']);
      }
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
      final normalizedSpecies = species.toLowerCase().trim();
      final targetSectionId = sectionId?.trim() ?? '';

      var query = repo.supabase
          .from('entries')
          .select('''
            id,
            exhibitor_id,
            species,
            section_id,
            breed,
            variety,
            fur_variety,
            tattoo,
            animal_name,
            class_name,
            sex,
            is_shown,
            scratched_at,
            is_disqualified,
            is_fur,
            exhibitors!entries_exhibitor_id_fkey(
              first_name,
              last_name,
              display_name,
              showing_name,
              address_line1,
              address_line2,
              city,
              state,
              zip
            )
          ''')
          .eq('show_id', showId)
          .eq('species', normalizedSpecies);

      if (targetSectionId.isNotEmpty) {
        query = query.eq('section_id', targetSectionId);
      }

      final rows = await query;

      final entries = (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where(_arbaAwardEntryCounts)
          .map(_normalizeArbaAwardEntry)
          .toList();

      final entryIds = entries
          .map((e) => _str(e['entry_id']))
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();

      if (entryIds.isEmpty) return const _ArbaBestAwardInfo.empty();

      final awardRows = <Map<String, dynamic>>[];
      for (var i = 0; i < entryIds.length; i += 100) {
        final chunk = entryIds.skip(i).take(100).toList();
        final chunkRows = await repo.supabase
            .from('entry_awards')
            .select('entry_id, award_code')
            .inFilter('entry_id', chunk);

        awardRows.addAll(List<Map<String, dynamic>>.from(chunkRows as List));
      }

      final normalizedAwardCodes = awardCodes.map(_normalizeAwardCode).toSet();
      final normalizedFallbackAwardCodes = fallbackAwardCodes
          .map(_normalizeAwardCode)
          .toSet();

      String? awardEntryId = _findAwardEntryId(awardRows, normalizedAwardCodes);

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

      final cityState = await _loadEntryCityState(entry, entryId: awardEntryId);

      return _ArbaBestAwardInfo(
        owner: owner,
        cityState: cityState,
        breed: _firstNonEmpty([
          _str(entry['breed_name']),
          _str(entry['breed']),
        ]),
        earNumber: _str(entry['tattoo']),
      );
    } catch (e) {
      // ignore: avoid_print
      print('Failed loading ARBA best award for section $sectionId: $e');
      return const _ArbaBestAwardInfo.empty();
    }
  }

  bool _arbaAwardEntryCounts(Map<String, dynamic> row) {
    if (row['is_shown'] == false) return false;
    if (_str(row['scratched_at']).isNotEmpty) return false;
    if (row['is_disqualified'] == true) return false;
    if (row['is_fur'] == true) return false;
    return true;
  }

  Map<String, dynamic> _normalizeArbaAwardEntry(Map<String, dynamic> row) {
    final exhibitorRaw = row['exhibitors'];
    final exhibitor = exhibitorRaw is Map
        ? Map<String, dynamic>.from(exhibitorRaw)
        : <String, dynamic>{};
    final displayName = _firstNonEmpty([
      _str(exhibitor['display_name']),
      _str(exhibitor['showing_name']),
      [
        _str(exhibitor['first_name']),
        _str(exhibitor['last_name']),
      ].where((e) => e.isNotEmpty).join(' '),
    ]);

    return {
      ...row,
      'entry_id': _str(row['id']),
      'breed_name': _str(row['breed']),
      'breed': _str(row['breed']),
      'variety_name': _str(row['variety']),
      'exhibitor_label': displayName,
      'exhibitor_showing_name': displayName,
      'exhibitor_first_name': _str(exhibitor['first_name']),
      'exhibitor_last_name': _str(exhibitor['last_name']),
      'exhibitor_address_line1': _str(exhibitor['address_line1']),
      'exhibitor_address_line2': _str(exhibitor['address_line2']),
      'exhibitor_city': _str(exhibitor['city']),
      'exhibitor_state': _str(exhibitor['state']),
      'exhibitor_zip': _str(exhibitor['zip']),
    };
  }

  Future<String> _loadEntryCityState(
    Map<String, dynamic> entry, {
    String? entryId,
  }) async {
    final fromReportRow = _formatAddressParts([
      _firstNonEmpty([
        _str(entry['exhibitor_address_line1']),
        _str(entry['address_line1']),
      ]),
      _firstNonEmpty([
        _str(entry['exhibitor_address_line2']),
        _str(entry['address_line2']),
      ]),
      _formatCityStateZip(
        city: _firstNonEmpty([
          _str(entry['exhibitor_city']),
          _str(entry['city']),
        ]),
        state: _firstNonEmpty([
          _str(entry['exhibitor_state']),
          _str(entry['state']),
        ]),
        zip: _firstNonEmpty([
          _str(entry['exhibitor_zip']),
          _str(entry['exhibitor_postal_code']),
          _str(entry['zip']),
          _str(entry['postal_code']),
        ]),
      ),
    ]);

    if (fromReportRow.isNotEmpty) return fromReportRow;

    final fromEntryJoin = await _loadEntryAddressByEntryId(entryId);
    if (fromEntryJoin.isNotEmpty) return fromEntryJoin;

    final exhibitorId = _str(entry['exhibitor_id']);
    if (exhibitorId.isEmpty) return '';

    try {
      final row = await repo.supabase
          .from('exhibitors')
          .select('address_line1,address_line2,city,state,zip')
          .eq('id', exhibitorId)
          .maybeSingle();

      if (row == null) return '';

      return _formatAddressParts([
        _str(row['address_line1']),
        _str(row['address_line2']),
        _formatCityStateZip(
          city: _str(row['city']),
          state: _str(row['state']),
          zip: _str(row['zip']),
        ),
      ]);
    } catch (e) {
      // ignore: avoid_print
      print('Failed loading ARBA exhibitor address for $exhibitorId: $e');
      return '';
    }
  }

  Future<String> _loadEntryAddressByEntryId(String? entryId) async {
    final id = _str(entryId);
    if (id.isEmpty) return '';

    try {
      final row = await repo.supabase
          .from('entries')
          .select('''
            id,
            exhibitor:exhibitors!entries_exhibitor_id_fkey(
              address_line1,
              address_line2,
              city,
              state,
              zip
            )
          ''')
          .eq('id', id)
          .maybeSingle();

      if (row == null) return '';

      final exhibitorRaw = row['exhibitor'];
      if (exhibitorRaw is! Map) return '';

      final exhibitor = Map<String, dynamic>.from(exhibitorRaw);
      return _formatAddressParts([
        _str(exhibitor['address_line1']),
        _str(exhibitor['address_line2']),
        _formatCityStateZip(
          city: _str(exhibitor['city']),
          state: _str(exhibitor['state']),
          zip: _str(exhibitor['zip']),
        ),
      ]);
    } catch (e) {
      // ignore: avoid_print
      print('Failed loading ARBA exhibitor address by entry $id: $e');
      return '';
    }
  }

  String _formatAddressParts(List<String> parts) {
    return parts.where((e) => e.trim().isNotEmpty).join(', ');
  }

  String _formatCityStateZip({
    required String city,
    required String state,
    required String zip,
  }) {
    final cityState = [
      city,
      state,
    ].where((e) => e.trim().isNotEmpty).join(', ');

    if (cityState.isEmpty) return zip;
    if (zip.isEmpty) return cityState;
    return '$cityState $zip';
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
