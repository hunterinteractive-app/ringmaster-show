// lib/screens/admin/closeout/models/clubs/breed_results_detail_report_data.dart

class BreedResultsDetailReportData {
  final String showId;
  final String breedName;
  final String scope;
  final String showLetter;
  final String judgeName;
  final List<BreedAward> breedAwards;
  final List<VarietySection> varieties;
  final List<BreedResultsDetailSection> sections;

  const BreedResultsDetailReportData({
    required this.showId,
    required this.breedName,
    required this.scope,
    required this.showLetter,
    required this.judgeName,
    required this.breedAwards,
    required this.varieties,
    this.sections = const [],
  });
}

class BreedResultsDetailSection {
  final String showLetter;
  final String judgeName;
  final List<BreedAward> breedAwards;
  final List<VarietySection> varieties;

  const BreedResultsDetailSection({
    required this.showLetter,
    required this.judgeName,
    required this.breedAwards,
    required this.varieties,
  });
}

class BreedAward {
  final String award;
  final String animal;
  final String className;
  final String exhibitorName;

  const BreedAward({
    required this.award,
    required this.animal,
    required this.className,
    required this.exhibitorName,
  });
}

class VarietySection {
  final String varietyName;
  final List<BreedAward> awards;
  final List<ClassSection> classes;

  const VarietySection({
    required this.varietyName,
    required this.awards,
    required this.classes,
  });
}

class ClassSection {
  final String className;
  final int entryCount;
  final int placedCount;
  final List<ClassEntry> rows;

  const ClassSection({
    required this.className,
    required this.entryCount,
    required this.placedCount,
    required this.rows,
  });
}

class ClassEntry {
  final String place;
  final String animal;
  final String exhibitorName;

  const ClassEntry({
    required this.place,
    required this.animal,
    required this.exhibitorName,
  });
}