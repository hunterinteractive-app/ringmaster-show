// lib/screens/admin/closeout/data/loaders/ribbon_payout_report_loader.dart

import 'package:supabase_flutter/supabase_flutter.dart';

import '../closeout_repository.dart';
import '../../models/base/report_request.dart';
import '../../models/exhibitor/ribbon_payout_report_data.dart';

final supabase = Supabase.instance.client;

class RibbonPayoutReportLoader {
  final CloseoutRepository repository;

  RibbonPayoutReportLoader(this.repository);

  Future<RibbonPayoutReportData> load(ReportRequest req) async {
    final rows = await supabase.rpc(
      'report_results_entry_rows',
      params: {
        'p_show_id': req.showId,
        'p_section_id': null,
        'p_show_letter': null,
      },
    );

    await repository.loadShowBasics(req.showId);

    final sanctions = await supabase
        .from('show_sanctions')
        .select('''
          club_name,
          sanction_number,
          sanctioning_body,
          show_sections (
            letter,
            kind
          )
        ''')
        .eq('show_id', req.showId);

    String sponsoringClub = '';
    String arbaSanction = '';
    String showLetter = '';
    String classification = '';
    String type = 'Non-national';
    String specialty = 'No';

    for (final raw in (sanctions as List)) {
      final row = Map<String, dynamic>.from(raw as Map);

      final body =
          (row['sanctioning_body'] ?? '').toString().trim().toUpperCase();

      if (body == 'ARBA') {
        sponsoringClub = (row['club_name'] ?? '').toString().trim();
        arbaSanction = (row['sanction_number'] ?? '').toString().trim();

        final section = row['show_sections'];
        if (section is Map) {
          final sectionMap = Map<String, dynamic>.from(section);
          showLetter = (sectionMap['letter'] ?? '').toString().trim();

          final kind =
              (sectionMap['kind'] ?? '').toString().trim().toLowerCase();

          if (kind == 'open') {
            classification = 'Open';
          } else if (kind == 'youth') {
            classification = 'Youth';
          }
        }

        break;
      }
    }

    final arbaDetails = await supabase
        .from('show_arba_report_details')
        .select('''
          secretary_name,
          secretary_email,
          superintendent_name
        ''')
        .eq('show_id', req.showId)
        .maybeSingle();

    final secretaryName =
        (arbaDetails?['secretary_name'] ?? '').toString().trim();
    final secretaryEmail =
        (arbaDetails?['secretary_email'] ?? '').toString().trim();
    final superintendentName =
        (arbaDetails?['superintendent_name'] ?? '').toString().trim();

    final Map<String, RibbonPayoutRow> map = {};

    for (final raw in (rows as List)) {
      final row = Map<String, dynamic>.from(raw as Map);

      final scratchedAt = (row['scratched_at'] ?? '').toString().trim();
      final isShown = row['is_shown'] != false;
      final isDisqualified = row['is_disqualified'] == true;

      if (scratchedAt.isNotEmpty || !isShown || isDisqualified) {
        continue;
      }

      final placementRaw = row['placement'];
      final placement = placementRaw is int
          ? placementRaw
          : int.tryParse(placementRaw?.toString() ?? '');

      if (placement == null || placement < 1 || placement > 5) {
        continue;
      }

      final exhibitorId = (row['exhibitor_id'] ?? '').toString().trim();
      final exhibitorLabel = (row['exhibitor_label'] ?? '').toString().trim();

      if (exhibitorId.isEmpty && exhibitorLabel.isEmpty) {
        continue;
      }

      final exhibitorNumber = exhibitorId;
      final exhibitorName =
          exhibitorLabel.isNotEmpty ? exhibitorLabel : '(Unknown Exhibitor)';

      final key = exhibitorId.isNotEmpty ? exhibitorId : exhibitorName;

      final existing = map[key];

      if (existing == null) {
        map[key] = RibbonPayoutRow(
          exhibitorNumber: exhibitorNumber,
          exhibitorName: exhibitorName,
          first: placement == 1 ? 1 : 0,
          second: placement == 2 ? 1 : 0,
          third: placement == 3 ? 1 : 0,
          fourth: placement == 4 ? 1 : 0,
          fifth: placement == 5 ? 1 : 0,
        );
      } else {
        map[key] = RibbonPayoutRow(
          exhibitorNumber: existing.exhibitorNumber,
          exhibitorName: existing.exhibitorName,
          first: existing.first + (placement == 1 ? 1 : 0),
          second: existing.second + (placement == 2 ? 1 : 0),
          third: existing.third + (placement == 3 ? 1 : 0),
          fourth: existing.fourth + (placement == 4 ? 1 : 0),
          fifth: existing.fifth + (placement == 5 ? 1 : 0),
        );
      }
    }

    final results = map.values.toList()
      ..sort((a, b) {
        final numberCmp = a.exhibitorNumber.compareTo(b.exhibitorNumber);
        if (numberCmp != 0) return numberCmp;
        return a.exhibitorName.toLowerCase().compareTo(
              b.exhibitorName.toLowerCase(),
            );
      });

    return RibbonPayoutReportData(
      showId: req.showId,
      showName: req.showName ?? '',
      eventName: req.showName ?? '',
      sponsoringClub: sponsoringClub,
      eventSecretary: secretaryName,
      eventSecretaryEmail: secretaryEmail,
      sponsoringSuperintendent: superintendentName,
      classification: classification,
      showLetter: showLetter,
      type: type,
      specialty: specialty,
      arbaSanction: arbaSanction,
      rows: results,
    );
  }
}