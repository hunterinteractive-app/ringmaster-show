// lib/screens/admin/closeout/models/clubs/breed_results_detail_report_data.dart

class BreedResultsDetailReportData {
  final String showId;
  final String breedName;
  final String scope;
  final String judgeName;
  final List<BreedAward> breedAwards;
  final List<VarietySection> varieties;

  const BreedResultsDetailReportData({
    required this.showId,
    required this.breedName,
    required this.scope,
    required this.judgeName,
    required this.breedAwards,
    required this.varieties,
  });
}

class BreedAward {
  final String label;
  final String animal;
  final String className;
  final String exhibitor;

  const BreedAward({
    required this.label,
    required this.animal,
    required this.className,
    required this.exhibitor,
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
  final int exhibitorCount;
  final List<ClassEntry> entries;

  const ClassSection({
    required this.className,
    required this.entryCount,
    required this.exhibitorCount,
    required this.entries,
  });
}

class ClassEntry {
  final int place;
  final String animal;
  final String exhibitor;

  const ClassEntry({
    required this.place,
    required this.animal,
    required this.exhibitor,
  });
}