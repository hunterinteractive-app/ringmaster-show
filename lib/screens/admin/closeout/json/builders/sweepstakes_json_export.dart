import 'dart:convert';

import '../../models/base/report_file_result.dart';
import '../../models/base/report_request.dart';
import '../../models/clubs/breed_results_detail_report_data.dart';
import '../../models/clubs/sweepstakes_report_data.dart';

/// Versioned machine-readable export for breed clubs that opt in to it.
class SweepstakesJsonExport {
  const SweepstakesJsonExport();

  ReportFileResult buildFile({
    required BreedResultsDetailReportData results,
    required SweepstakesReportData sweepstakes,
    required ReportRequest request,
  }) {
    final payload = <String, dynamic>{
      'format': 'ringmaster.sweepstakes_results',
      'version': 1,
      'event': {
        'name': request.showName ?? '',
        'date': request.showDate ?? '',
        'host_club': results.hostClubName,
        'location': results.showLocation,
        'secretary': {
          'name': results.secretaryName,
          'email': results.secretaryEmail,
          'phone': results.secretaryPhone,
        },
      },
      'breed': results.breedName,
      'club': results.breedClubName,
      'show': {
        'scope': results.scope,
        'letter': results.showLetter,
        'judge': results.judgeName,
        'arba_sanction_number': results.arbaSanction,
        'club_sanction_number': results.breedSanctionNumber,
        'awards': results.breedAwards.map(_award).toList(),
        'varieties': results.varieties.map(_variety).toList(),
      },
      'sweepstakes': {
        'rule_source': sweepstakes.ruleSource,
        'verification_status': sweepstakes.verificationStatus,
        'exhibitors': sweepstakes.rows.map(_points).toList(),
      },
    };
    final fileStem = _safeFileName(
      '${request.showName}_${results.breedName}_${results.scope}_${results.showLetter}',
    );
    return ReportFileResult(
      fileName: '${fileStem}_Sweepstakes.json',
      mimeType: 'application/json',
      bytes: utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)),
    );
  }

  Map<String, dynamic> _award(BreedAward value) => {
    'award': value.award,
    'animal': value.animal,
    'exhibitor': value.exhibitorName,
    'variety': value.variety,
    'class': value.className,
    'sex': value.sex,
    'animals_judged': value.animalsJudged,
    'exhibitors_judged': value.exhibitorsJudged,
    'points': value.pointsEarned,
  };

  Map<String, dynamic> _variety(VarietySection value) => {
    'name': value.varietyName,
    'awards': value.awards.map(_award).toList(),
    'classes': [
      for (final sex in value.sexSections)
        for (final section in sex.classes)
          {
            'name': section.className,
            'sex': sex.sexLabel,
            'shown': section.entryCount,
            'placements': section.rows.map(_entry).toList(),
          },
    ],
  };

  Map<String, dynamic> _entry(ClassEntry value) => {
    'placement': value.place,
    'animal': value.animal,
    'exhibitor': value.exhibitorName,
    'sex': value.sex,
    'variety': value.variety,
    'points': value.pointsEarned,
  };

  Map<String, dynamic> _points(SweepstakesReportRow value) => {
    'rank': value.rank,
    'exhibitor': value.exhibitorName,
    'address': value.exhibitorAddress,
    'class_points': value.classPoints,
    'variety_points': value.varietyPoints,
    'group_points': value.groupPoints,
    'breed_points': value.bobPoints,
    'best_in_show_points': value.bisPoints,
    'fur_points': value.furPoints,
    'total_points': value.totalPoints,
  };

  String _safeFileName(String value) => value
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}
