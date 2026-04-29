// lib/screens/admin/judging/models/judging_entry_context.dart

class JudgingEntryContext {
  const JudgingEntryContext({
    required this.showId,
    required this.sectionId,
    required this.breedId,
    this.varietyKey,
    this.judgeId,
    required this.judgeName,
    this.tableNumber,
    required this.fromSuperintendentAssignment,
    required this.resultsLocked,
    required this.canEdit,
  });

  final String showId;
  final String sectionId;
  final String breedId;
  final String? varietyKey;

  final String? judgeId;
  final String judgeName;

  final String? tableNumber;
  final bool fromSuperintendentAssignment;
  final bool resultsLocked;
  final bool canEdit;
}