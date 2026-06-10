// lib/screens/admin/closeout/data/loaders/ribbon_payout_report_loader.dart

import 'package:supabase_flutter/supabase_flutter.dart';

import '../closeout_repository.dart';
import '../../models/base/report_request.dart';
import '../../models/exhibitor/ribbon_payout_report_data.dart';

final supabase = Supabase.instance.client;

class RibbonPayoutReportLoader {
  final CloseoutRepository repository;

  RibbonPayoutReportLoader(this.repository);

  Future<List<Map<String, dynamic>>> _loadRowsPaged({
    required String showId,
    String? showLetter,
  }) async {
    const pageSize = 1000;
    final allRows = <Map<String, dynamic>>[];

    for (var from = 0;; from += pageSize) {
      final to = from + pageSize - 1;
      final page = await supabase
          .rpc(
            'report_results_entry_rows',
            params: {
              'p_show_id': showId,
              'p_section_id': null,
              'p_show_letter': showLetter,
            },
          )
          .range(from, to);

      final pageRows = (page as List)
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();

      allRows.addAll(pageRows);

      if (pageRows.length < pageSize) {
        break;
      }
    }

    return allRows;
  }

  List<RibbonPayoutRow> _buildRows(List<Map<String, dynamic>> rowList) {
    final Map<String, RibbonPayoutRow> map = {};

    for (final row in rowList) {
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
      final exhibitorNumber = (
        row['exhibitor_number'] ??
        row['exhibitor_no'] ??
        row['exhibitor_num'] ??
        row['entry_exhibitor_number'] ??
        row['show_exhibitor_number'] ??
        row['exhibitor_code'] ??
        ''
      ).toString().trim();

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
          exhibitorNumber: existing.exhibitorNumber.isNotEmpty
              ? existing.exhibitorNumber
              : exhibitorNumber,
          exhibitorName: existing.exhibitorName,
          first: existing.first + (placement == 1 ? 1 : 0),
          second: existing.second + (placement == 2 ? 1 : 0),
          third: existing.third + (placement == 3 ? 1 : 0),
          fourth: existing.fourth + (placement == 4 ? 1 : 0),
          fifth: existing.fifth + (placement == 5 ? 1 : 0),
        );
      }
    }

    int exhibitorNumberSortValue(String value) {
      final numeric = int.tryParse(value.trim());
      return numeric ?? 999999;
    }

    return map.values.toList()
      ..sort((a, b) {
        final numberCmp = exhibitorNumberSortValue(a.exhibitorNumber).compareTo(
          exhibitorNumberSortValue(b.exhibitorNumber),
        );
        if (numberCmp != 0) return numberCmp;
        return a.exhibitorName.toLowerCase().compareTo(
              b.exhibitorName.toLowerCase(),
            );
      });
  }

  Future<RibbonPayoutReportData> load(ReportRequest req) async {
    await repository.loadShowBasics(req.showId);

    final sectionsRaw = await supabase
        .from('show_sections')
        .select('id, letter, kind, sort_order, is_enabled')
        .eq('show_id', req.showId)
        .eq('is_enabled', true)
        .order('sort_order')
        .order('letter');

    final sections = (sectionsRaw as List)
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();

    final sanctionsRaw = await supabase
        .from('show_sanctions')
        .select('''
          club_name,
          sanction_number,
          sanctioning_body,
          section_id,
          show_sections (
            letter,
            kind
          )
        ''')
        .eq('show_id', req.showId);

    final sanctions = (sanctionsRaw as List)
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();

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

    String sectionClassification(Map<String, dynamic> section) {
      final kind = (section['kind'] ?? '').toString().trim().toLowerCase();
      if (kind == 'open') return 'Open';
      if (kind == 'youth') return 'Youth';
      return kind.isEmpty ? '' : kind[0].toUpperCase() + kind.substring(1);
    }

    int sectionKindRank(Map<String, dynamic> section) {
      final kind = (section['kind'] ?? '').toString().trim().toLowerCase();
      if (kind == 'open') return 0;
      if (kind == 'youth') return 1;
      return 9;
    }

    Map<String, dynamic>? sanctionForSection(Map<String, dynamic> section) {
      final sectionId = (section['id'] ?? '').toString();
      final sectionLetter = (section['letter'] ?? '').toString().trim();
      final sectionKind = (section['kind'] ?? '').toString().trim().toLowerCase();

      for (final sanction in sanctions) {
        final body = (sanction['sanctioning_body'] ?? '')
            .toString()
            .trim()
            .toUpperCase();
        if (body != 'ARBA') continue;

        final sanctionSectionId =
            (sanction['section_id'] ?? '').toString().trim();
        if (sanctionSectionId.isNotEmpty && sanctionSectionId == sectionId) {
          return sanction;
        }
      }

      for (final sanction in sanctions) {
        final body = (sanction['sanctioning_body'] ?? '')
            .toString()
            .trim()
            .toUpperCase();
        if (body != 'ARBA') continue;

        final joinedSection = sanction['show_sections'];
        if (joinedSection is! Map) continue;

        final joined = Map<String, dynamic>.from(joinedSection);
        final joinedLetter =
            (joined['letter'] ?? '').toString().trim().toUpperCase();
        final joinedKind =
            (joined['kind'] ?? '').toString().trim().toLowerCase();

        if (joinedLetter == sectionLetter.toUpperCase() &&
            joinedKind == sectionKind) {
          return sanction;
        }
      }

      return null;
    }

    final sortedSections = [...sections]
      ..sort((a, b) {
        final kindCmp = sectionKindRank(a).compareTo(sectionKindRank(b));
        if (kindCmp != 0) return kindCmp;

        final sortA = a['sort_order'] is int
            ? a['sort_order'] as int
            : int.tryParse(a['sort_order']?.toString() ?? '') ?? 9999;
        final sortB = b['sort_order'] is int
            ? b['sort_order'] as int
            : int.tryParse(b['sort_order']?.toString() ?? '') ?? 9999;
        final sortCmp = sortA.compareTo(sortB);
        if (sortCmp != 0) return sortCmp;

        return (a['letter'] ?? '')
            .toString()
            .compareTo((b['letter'] ?? '').toString());
      });

    final sectionReports = <RibbonPayoutSectionData>[];

    for (final section in sortedSections) {
      final letter = (section['letter'] ?? '').toString().trim();
      if (letter.isEmpty) continue;

      final rowList = await _loadRowsPaged(
        showId: req.showId,
        showLetter: letter,
      );
      final resultRows = _buildRows(rowList);
      if (resultRows.isEmpty) continue;

      final sanction = sanctionForSection(section);

      sectionReports.add(
        RibbonPayoutSectionData(
          sponsoringClub:
              (sanction?['club_name'] ?? '').toString().trim(),
          classification: sectionClassification(section),
          showLetter: letter,
          type: 'Non-national',
          specialty: 'No',
          arbaSanction:
              (sanction?['sanction_number'] ?? '').toString().trim(),
          rows: resultRows,
        ),
      );
    }

    final firstSection = sectionReports.isNotEmpty ? sectionReports.first : null;

    return RibbonPayoutReportData(
      showId: req.showId,
      showName: req.showName ?? '',
      eventName: req.showName ?? '',
      sponsoringClub: firstSection?.sponsoringClub ?? '',
      eventSecretary: secretaryName,
      eventSecretaryEmail: secretaryEmail,
      sponsoringSuperintendent: superintendentName,
      classification: firstSection?.classification ?? '',
      showLetter: firstSection?.showLetter ?? '',
      type: firstSection?.type ?? 'Non-national',
      specialty: firstSection?.specialty ?? 'No',
      arbaSanction: firstSection?.arbaSanction ?? '',
      rows: firstSection?.rows ?? const [],
      sections: sectionReports,
    );
  }
}