class ResultsReadinessDto {
  final bool ready;
  final int missingPlacementCount;
  final int missingJudgeCount;
  final int duplicatePlacementGroupCount;
  final int missingFinalAwardCount;
  final int duplicateFinalAwardCount;
  final List<MissingFinalAward> missingFinalAwards;

  ResultsReadinessDto({
    required this.ready,
    required this.missingPlacementCount,
    required this.missingJudgeCount,
    required this.duplicatePlacementGroupCount,
    required this.missingFinalAwardCount,
    required this.duplicateFinalAwardCount,
    this.missingFinalAwards = const [],
  });

  factory ResultsReadinessDto.fromJson(Map<String, dynamic> json) {
    return ResultsReadinessDto(
      ready: (json['ready'] ?? false) == true,
      missingPlacementCount: ((json['missing_placement_count'] ?? 0) as num)
          .toInt(),
      missingJudgeCount: ((json['missing_judge_count'] ?? 0) as num).toInt(),
      duplicatePlacementGroupCount:
          ((json['duplicate_placement_group_count'] ?? 0) as num).toInt(),
      missingFinalAwardCount:
          (json['missing_final_award_count'] as num?)?.toInt() ?? 0,
      duplicateFinalAwardCount:
          (json['duplicate_final_award_count'] as num?)?.toInt() ?? 0,
      missingFinalAwards: (json['missing_final_awards'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                MissingFinalAward.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }
}

class MissingFinalAward {
  final String sectionId;
  final String sectionLabel;
  final String awardCode;
  final String awardLabel;

  const MissingFinalAward({
    required this.sectionId,
    required this.sectionLabel,
    required this.awardCode,
    required this.awardLabel,
  });

  factory MissingFinalAward.fromJson(Map<String, dynamic> json) {
    final awardCode = (json['award_code'] ?? '').toString();
    return MissingFinalAward(
      sectionId: (json['section_id'] ?? '').toString(),
      sectionLabel: (json['section_label'] ?? 'Section').toString(),
      awardCode: awardCode,
      awardLabel: (json['award_label'] ?? awardCode).toString(),
    );
  }
}
