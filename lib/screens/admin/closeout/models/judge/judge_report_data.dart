// lib/screens/admin/closeout/models/exhibitor/judge_report_data.dart

class JudgeReportShowInfo {
  JudgeReportShowInfo({
    required this.showId,
    required this.showName,
    this.startDate,
    this.endDate,
    this.locationName = '',
    this.secretaryName,
    this.secretaryEmail,
    this.secretaryPhone,
  });

  final String showId;
  final String showName;
  final DateTime? startDate;
  final DateTime? endDate;
  final String locationName;
  final String? secretaryName;
  final String? secretaryEmail;
  final String? secretaryPhone;
}

class JudgeReportData {
  JudgeReportData({
    required this.show,
    required this.generatedAt,
    required this.judges,
  });

  final JudgeReportShowInfo show;
  final DateTime generatedAt;
  final List<JudgeReportJudge> judges;

  int get totalBreedEntries => judges.fold<int>(
        0,
        (sum, judge) => sum + judge.breedEntryCount,
      );

  int get totalFurEntries => judges.fold<int>(
        0,
        (sum, judge) => sum + judge.furEntryCount,
      );

  int get totalEntriesJudged => totalBreedEntries + totalFurEntries;
}

class JudgeReportJudge {
  JudgeReportJudge({
    required this.judgeId,
    required this.displayName,
    this.arbaNumber,
    this.email,
    this.phone,
    required this.rows,
  });

  final String judgeId;
  final String displayName;
  final String? arbaNumber;
  final String? email;
  final String? phone;
  final List<JudgeReportRow> rows;

  String get displayLabel {
    final number = arbaNumber?.trim();
    if (number == null || number.isEmpty) return displayName;
    return '$displayName [$number]';
  }

  int get breedEntryCount => rows.where((row) => !row.isFur).length;
  int get furEntryCount => rows.where((row) => row.isFur).length;
  int get totalEntryCount => rows.length;
}

class JudgeReportRow {
  JudgeReportRow({
    required this.entryId,
    required this.sectionLabel,
    required this.species,
    required this.breed,
    required this.variety,
    required this.className,
    required this.sex,
    required this.tattoo,
    required this.exhibitorName,
    this.animalName,
    this.placement,
    this.resultStatus,
    this.disqualifiedReason,
    this.awards = const <String>[],
    this.isFur = false,
    this.furVariety,
    this.notes,
  });

  final String entryId;
  final String sectionLabel;
  final String species;
  final String breed;
  final String variety;
  final String className;
  final String sex;
  final String tattoo;
  final String exhibitorName;
  final String? animalName;
  final int? placement;
  final String? resultStatus;
  final String? disqualifiedReason;
  final List<String> awards;
  final bool isFur;
  final String? furVariety;
  final String? notes;

  String get judgedAsLabel {
    if (!isFur) return 'Breed';
    final fur = furVariety?.trim();
    if (fur == null || fur.isEmpty) return 'Fur';
    return 'Fur - $fur';
  }

  String get varietyLabel {
    if (!isFur) return variety;
    final fur = furVariety?.trim();
    if (fur == null || fur.isEmpty) return variety;
    return fur;
  }

  String get placementLabel {
    if (placement != null && placement! > 0) return placement.toString();

    final status = resultStatus?.trim();
    if (status == null || status.isEmpty) return 'No Place';

    final lower = status.toLowerCase();
    if (lower.contains('disqual')) {
      final reason = disqualifiedReason?.trim();
      if (reason == null || reason.isEmpty) return 'DQ';
      return 'DQ - $reason';
    }

    if (lower == 'no_place' || lower == 'no place') return 'No Place';
    if (lower == 'unworthy' || lower.contains('unworthy')) {
      return 'Unworthy';
    }

    return status;
  }

  String get awardsLabel =>
      awards.where((award) => award.trim().isNotEmpty).join(', ');
}