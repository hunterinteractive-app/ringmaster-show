import '../../models/base/report_request.dart';
import '../../models/clubs/details_by_breed_report_data.dart';
import '../closeout_repository.dart';

class DetailsByBreedReportLoader {
  DetailsByBreedReportLoader(this.repo);

  final CloseoutRepository repo;

  Future<DetailsByBreedReportData> load(ReportRequest request) async {
    final scope = (request.scope ?? '').trim().toUpperCase();
    final showLetter = (request.showLetter ?? '').trim().toUpperCase();

    if (scope.isEmpty) {
      throw Exception('Details by Breed requires scope.');
    }
    if (showLetter.isEmpty) {
      throw Exception('Details by Breed requires showLetter.');
    }

    final header = await _loadHeader(request.showId);

    final response = await repo.supabase.rpc(
      'report_results_entry_rows',
      params: {
        'p_show_id': request.showId,
        'p_section_id': null,
        'p_show_letter': showLetter,
      },
    );

    final rows = (response as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((row) {
          final rowScope = _text(row, ['scope', 'section_kind', 'kind'])
              .trim()
              .toUpperCase();
          return (rowScope.isEmpty || rowScope == scope) && _isActuallyShown(row);
        })
        .toList();

    final grouped = <String, _BreedAccumulator>{};

    for (final row in rows) {
      final breed = _text(row, ['breed_name', 'breed']).trim();
      if (breed.isEmpty) continue;

      final accumulator = grouped.putIfAbsent(
        _key(breed),
        () => _BreedAccumulator(breed),
      );

      accumulator.animalsShown++;

      final exhibitor = _exhibitorName(row);
      final awards = _awardCodes(row);

      if (awards.contains('BOB')) {
        accumulator.bobExhibitor = exhibitor;
      }
      if (awards.contains('BOS') || awards.contains('BOSB')) {
        accumulator.bosExhibitor = exhibitor;
      }
    }

    final resultRows = grouped.values
        .map(
          (e) => DetailsByBreedRow(
            breedName: e.breedName,
            animalsShown: e.animalsShown,
            bobExhibitor: e.bobExhibitor,
            bosExhibitor: e.bosExhibitor,
          ),
        )
        .toList()
      ..sort((a, b) => a.breedName.toLowerCase().compareTo(
            b.breedName.toLowerCase(),
          ));

    return DetailsByBreedReportData(
      showId: request.showId,
      showName: (request.showName ?? header.showName).trim(),
      showDate: (request.showDate ?? header.showDate).trim(),
      showLocation: header.showLocation,
      hostClubName: header.hostClubName,
      scope: scope,
      showLetter: showLetter,
      secretaryName: header.secretaryName,
      secretaryAddress: header.secretaryAddress,
      secretaryEmail: header.secretaryEmail,
      secretaryPhone: header.secretaryPhone,
      rows: resultRows,
    );
  }

  Future<_Header> _loadHeader(String showId) async {
    final showResponse = await repo.supabase
        .from('shows')
        .select()
        .eq('id', showId)
        .maybeSingle();

    final show = showResponse == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(showResponse);

    String hostClubName = '';
    final clubId = (show['club_id'] ?? '').toString().trim();
    if (clubId.isNotEmpty) {
      final clubResponse = await repo.supabase
          .from('clubs')
          .select('name')
          .eq('id', clubId)
          .maybeSingle();
      if (clubResponse != null) {
        hostClubName =
            (Map<String, dynamic>.from(clubResponse)['name'] ?? '').toString();
      }
    }

    final detailsResponse = await repo.supabase
        .from('show_arba_report_details')
        .select()
        .eq('show_id', showId)
        .maybeSingle();

    final details = detailsResponse == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(detailsResponse);

    String first(List<String> keys) {
      final fromDetails = _text(details, keys);
      if (fromDetails.isNotEmpty) return fromDetails;
      return _text(show, keys);
    }

    final addressParts = <String>[
      first(['secretary_address', 'secretary_address_line1']),
      first(['secretary_address_line2']),
      first(['secretary_city']),
      first(['secretary_state']),
      first(['secretary_zip', 'secretary_postal_code']),
    ].where((e) => e.isNotEmpty).toList();

    return _Header(
      showName: _text(show, ['name', 'show_name']),
      showDate: _text(show, ['start_date', 'show_date']),
      showLocation: _text(show, ['location_name', 'location']),
      hostClubName: hostClubName,
      secretaryName: first(['secretary_name']),
      secretaryAddress: addressParts.join(', '),
      secretaryEmail: first(['secretary_email']),
      secretaryPhone: first(['secretary_phone']),
    );
  }

  static Set<String> _awardCodes(Map<String, dynamic> row) {
    final raw = row['special_awards'] ?? row['awards'] ?? row['award_codes'];
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim().toUpperCase())
          .where((e) => e.isNotEmpty)
          .toSet();
    }

    return (raw ?? '')
        .toString()
        .toUpperCase()
        .split(RegExp(r'[,;|\s]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
  }


  static String _text(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = (row[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static bool _bool(dynamic value, {bool fallback = false}) {
    if (value is bool) return value;
    final text = (value ?? '').toString().trim().toLowerCase();
    if (text == 'true' || text == 't' || text == '1' || text == 'yes') {
      return true;
    }
    if (text == 'false' || text == 'f' || text == '0' || text == 'no') {
      return false;
    }
    return fallback;
  }

  static String _key(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static bool _isActuallyShown(Map<String, dynamic> row) {
    if (_bool(row['is_test'])) return false;
    if ((row['scratched_at'] ?? '').toString().trim().isNotEmpty) return false;
    if (_bool(row['is_disqualified'])) return false;
    if (!_bool(row['is_shown'], fallback: true)) return false;

    final status = _text(row, ['result_status', 'status']).toLowerCase();
    if (status.contains('no show') ||
        status.contains('scratch') ||
        status.contains('disqual') ||
        status.contains('wrong sex') ||
        status.contains('wrong variety') ||
        status.contains('wrong class') ||
        status.contains('unworthy')) {
      return false;
    }

    // Fur/wool is reported separately and must not inflate the regular animal count.
    if (_bool(row['is_fur']) || _bool(row['is_wool'])) return false;

    return true;
  }

  static String _exhibitorName(Map<String, dynamic> row) => _text(row, [
        'exhibitor_name',
        'exhibitor_label',
        'showing_name',
        'owner_name',
      ]);

  static String _exhibitorAddress(Map<String, dynamic> row) {
    final direct = _text(row, ['exhibitor_address', 'address']);
    if (direct.isNotEmpty) return direct;

    final parts = <String>[
      _text(row, ['address_line1', 'address1']),
      _text(row, ['address_line2', 'address2']),
      _text(row, ['city']),
      _text(row, ['state', 'state_code']),
      _text(row, ['postal_code', 'zip', 'zip_code']),
    ].where((e) => e.isNotEmpty).toList();

    return parts.join(', ');
  }

}

class _BreedAccumulator {
  final String breedName;
  int animalsShown = 0;
  String bobExhibitor = '';
  String bosExhibitor = '';

  _BreedAccumulator(this.breedName);
}

class _Header {
  final String showName;
  final String showDate;
  final String showLocation;
  final String hostClubName;
  final String secretaryName;
  final String secretaryAddress;
  final String secretaryEmail;
  final String secretaryPhone;

  const _Header({
    this.showName = '',
    this.showDate = '',
    this.showLocation = '',
    this.hostClubName = '',
    this.secretaryName = '',
    this.secretaryAddress = '',
    this.secretaryEmail = '',
    this.secretaryPhone = '',
  });
}
