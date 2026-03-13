import '../../models/arba/arba_report_data.dart';
import '../../models/base/report_request.dart';
import '../closeout_repository.dart';

class ArbaReportLoader {
  ArbaReportLoader(this.repo);

  final CloseoutRepository repo;

  Future<ArbaReportData> load(ReportRequest request) async {
    final show = await repo.loadShowBasics(request.showId);
    final arbaDetails = await _loadArbaDetails(request.showId);

    final showName = _str(show['name']);

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

    final sanctionNumber = await _loadSanctionNumber(request.showId);
    final clubName = await _loadClubName(request.showId);

    final rabbitsShown = await _countShownSpecies(request.showId, 'rabbit');
    final caviesShown = await _countShownSpecies(request.showId, 'cavy');

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
      const ['newsletter_show_report', 'exh_total_points', 'exh_by_breed'],
    );

    final judges = await _loadJudgeNames(request.showId);

    final signedBy =
        secretaryName.isNotEmpty ? secretaryName : await _loadSignedByName();

    final filedDate = DateTime.now();

    final bisRabbit = await _loadBisRabbit(request.showId);

    return ArbaReportData(
      showName: showName,
      secretaryName: secretaryName,
      secretaryEmail: secretaryEmail,
      secretaryPhone: secretaryPhone,
      sanctionNumber: sanctionNumber,
      reportDate: reportDate,
      rabbitsShown: rabbitsShown,
      caviesShown: caviesShown,
      clubName: clubName.isNotEmpty ? clubName : showName,
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

  Future<String> _loadSanctionNumber(String showId) async {
    try {
      final row = await repo.supabase
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

  Future<String> _loadClubName(String showId) async {
    try {
      final row = await repo.supabase
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

  Future<int> _countShownSpecies(String showId, String species) async {
    try {
      final rows = await repo.supabase
          .from('entries')
          .select('id')
          .eq('show_id', showId)
          .eq('is_shown', true)
          .eq('species', species);

      return rows.length;
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

  Future<List<String>> _loadJudgeNames(String showId) async {
    try {
      final assignmentRows = await repo.supabase
          .from('judge_assignments')
          .select('judge_id, assignment_label, created_at')
          .eq('show_id', showId)
          .order('created_at');

      final assignments = List<Map<String, dynamic>>.from(assignmentRows);
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

  Future<_BisRabbitInfo> _loadBisRabbit(String showId) async {
    try {
      final rows = await repo.supabase
          .from('entry_awards')
          .select('''
            award_code,
            entry_id,
            entries!entry_awards_entry_id_fkey (
              id,
              species,
              tattoo,
              breed,
              exhibitor_id
            )
          ''')
          .eq('show_id', showId);

      final awards = List<Map<String, dynamic>>.from(rows);

      Map<String, dynamic>? bisAward;

      for (final row in awards) {
        final awardCode = _str(row['award_code']).toLowerCase();
        final entry = row['entries'];

        if (entry is! Map<String, dynamic>) continue;

        final species = _str(entry['species']).toLowerCase();

        final isBisRabbit = species == 'rabbit' &&
            (awardCode == 'bis' ||
                awardCode == 'best_in_show' ||
                awardCode == 'best in show' ||
                awardCode == 'bis_rabbit');

        if (isBisRabbit) {
          bisAward = row;
          break;
        }
      }

      if (bisAward == null) {
        return const _BisRabbitInfo.empty();
      }

      final entry = Map<String, dynamic>.from(bisAward['entries'] as Map);
      final exhibitorId = _str(entry['exhibitor_id']);

      String owner = '';
      String cityState = '';

      if (exhibitorId.isNotEmpty) {
        final exhibitor = await repo.supabase
            .from('exhibitors')
            .select('display_name, first_name, last_name, city, state')
            .eq('id', exhibitorId)
            .maybeSingle();

        if (exhibitor != null) {
          owner = _str(exhibitor['display_name']).isNotEmpty
              ? _str(exhibitor['display_name'])
              : [
                  _str(exhibitor['first_name']),
                  _str(exhibitor['last_name']),
                ].where((e) => e.isNotEmpty).join(' ');

          cityState = [
            _str(exhibitor['city']),
            _str(exhibitor['state']),
          ].where((e) => e.isNotEmpty).join(', ');
        }
      }

      return _BisRabbitInfo(
        owner: owner,
        cityState: cityState,
        breed: _str(entry['breed']),
        earNumber: _str(entry['tattoo']),
      );
    } catch (_) {
      return const _BisRabbitInfo.empty();
    }
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

class _BisRabbitInfo {
  final String owner;
  final String cityState;
  final String breed;
  final String earNumber;

  const _BisRabbitInfo({
    required this.owner,
    required this.cityState,
    required this.breed,
    required this.earNumber,
  });

  const _BisRabbitInfo.empty()
      : owner = '',
        cityState = '',
        breed = '',
        earNumber = '';
}