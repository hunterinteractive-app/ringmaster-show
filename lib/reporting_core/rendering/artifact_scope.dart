import 'dart:convert';

import 'package:crypto/crypto.dart';

const _sectionScopedReports = <String>{
  'arba_report',
  'sweepstakes_report',
  'breed_results_detail_report',
  'details_by_breed',
  'exh_by_breed',
  'best_display_report',
};

const _breedScopedReports = <String>{
  'sweepstakes_report',
  'breed_results_detail_report',
};

const _speciesScopedReports = <String>{
  'sweepstakes_report',
  'breed_results_detail_report',
  'details_by_breed',
  'exh_by_breed',
  'best_display_report',
};

const _exhibitorScopedReports = <String>{
  'exhibitor_report',
  'checkin_sheet',
  'legs',
};

const _runScopedReports = <String>{
  'unpaid_balances_report',
  'paid_exhibitor_report',
  'entered_exhibitors_contact_report',
  'ribbon_payout_report',
  'payback_report',
  'judge_report',
  'breed_judged_totals_report',
};

final class ArtifactScope {
  const ArtifactScope._();

  static String identity(String reportName, Map<String, dynamic> metadata) {
    return <String>[
      reportName,
      _identityText(metadata, 'section_id'),
      _identityText(metadata, 'exhibitor_id'),
      _identityText(metadata, 'breed_name').toLowerCase(),
      _identityText(metadata, 'club_name').toLowerCase(),
      _identityText(metadata, 'species').toLowerCase(),
      _identityText(metadata, 'scope').toUpperCase(),
      _identityText(metadata, 'show_letter').toUpperCase(),
      _identityText(metadata, 'sanctioning_body').toUpperCase(),
      _identityText(metadata, 'delivery_type').toLowerCase(),
      _identityText(metadata, 'judge_id'),
      _identityText(metadata, 'report_scope').toLowerCase(),
    ].join('|');
  }

  static String canonicalKey({
    required String showId,
    required String reportName,
    required Iterable<String> sectionIds,
    required Map<String, dynamic> metadata,
  }) {
    final sections = sectionIds.map((id) => id.trim()).toSet().toList()..sort();
    final identityHash = md5.convert(
      utf8.encode(identity(reportName, metadata)),
    );
    return '$showId:${sections.join(',')}:$identityHash';
  }

  static String? validationError({
    required String showId,
    required String reportName,
    required List<String> sectionIds,
    required String scopeKey,
    required Map<String, dynamic> metadata,
  }) {
    final sections = sectionIds.map((id) => id.trim()).toSet();
    if (showId.isEmpty || sections.isEmpty) return 'missing_section_ids';
    if (_strings(
          metadata['section_ids'],
        ).toSet().difference(sections).isNotEmpty ||
        sections
            .difference(_strings(metadata['section_ids']).toSet())
            .isNotEmpty) {
      return 'section_ids_mismatch';
    }
    if (_text(metadata, 'run_scope_key').isEmpty) {
      return 'missing_run_scope_key';
    }

    if (_sectionScopedReports.contains(reportName)) {
      final sectionId = _text(metadata, 'section_id');
      if (sectionId.isEmpty ||
          sections.length != 1 ||
          !sections.contains(sectionId)) {
        return 'invalid_section_id';
      }
      if (_text(metadata, 'scope').isEmpty) return 'missing_section_kind';
      if (_text(metadata, 'show_letter').isEmpty) return 'missing_show_letter';
      if (_breedScopedReports.contains(reportName) &&
          _text(metadata, 'breed_name').isEmpty) {
        return 'missing_breed_name';
      }
      if (_speciesScopedReports.contains(reportName) &&
          !const {
            'rabbit',
            'cavy',
          }.contains(_text(metadata, 'species').toLowerCase())) {
        return 'missing_species';
      }
    } else if (_exhibitorScopedReports.contains(reportName)) {
      if (_text(metadata, 'exhibitor_id').isEmpty) {
        return 'missing_exhibitor_id';
      }
    } else if (!_runScopedReports.contains(reportName)) {
      return 'unsupported_report_scope';
    }

    final canonical = canonicalKey(
      showId: showId,
      reportName: reportName,
      sectionIds: sections,
      metadata: metadata,
    );
    if (scopeKey != canonical || _text(metadata, 'scope_key') != canonical) {
      return 'noncanonical_scope_key';
    }
    return null;
  }
}

String _text(Map<String, dynamic> metadata, String key) =>
    metadata[key]?.toString().trim() ?? '';

String _identityText(Map<String, dynamic> metadata, String key) {
  final value = metadata[key];
  return value is String ? value.trim() : '';
}

List<String> _strings(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList();
}
