// lib/screens/admin/closeout/models/clubs/breed_results_detail_report_data.dart

class BreedResultsDetailReportData {
  final String showId;
  final String breedName;
  final String scope;
  final String showLetter;
  final String judgeName;

  final String arbaSanction;
  final String nationalClubSanction;
  final String breedSanctionNumber;
  final String hostClubName;
  final String showLocation;
  final String secretaryName;
  final String secretaryEmail;
  final String secretaryPhone;

  final List<BreedAward> breedAwards;
  final List<VarietySection> varieties;
  final List<BreedResultsDetailSection> sections;
  final bool noResultsFound;

  const BreedResultsDetailReportData({
    required this.showId,
    required this.breedName,
    required this.scope,
    required this.showLetter,
    required this.judgeName,
    this.arbaSanction = '',
    this.nationalClubSanction = '',
    this.breedSanctionNumber = '',
    this.hostClubName = '',
    this.showLocation = '',
    this.secretaryName = '',
    this.secretaryEmail = '',
    this.secretaryPhone = '',
    required this.breedAwards,
    required this.varieties,
    this.sections = const [],
    this.noResultsFound = false,
  });
}

class BreedResultsDetailSection {
  final String showLetter;
  final String judgeName;
  final List<BreedAward> breedAwards;
  final List<VarietySection> varieties;
  final bool noResultsFound;

  const BreedResultsDetailSection({
    required this.showLetter,
    required this.judgeName,
    required this.breedAwards,
    required this.varieties,
    this.noResultsFound = false,
  });
}

class BreedAward {
  final String award;
  final String animal;
  final String className;
  final String exhibitorName;
  final String sex;
  final String variety;
  final int animalsJudged;
  final int exhibitorsJudged;

  const BreedAward({
    required this.award,
    required this.animal,
    required this.className,
    required this.exhibitorName,
    this.sex = '',
    this.variety = '',
    this.animalsJudged = 0,
    this.exhibitorsJudged = 0,
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
  final int animalsJudged;
  final int exhibitorsJudged;
  final List<ClassEntry> rows;

  const ClassSection({
    required this.className,
    required this.entryCount,
    required this.placedCount,
    required this.animalsJudged,
    required this.exhibitorsJudged,
    required this.rows,
  });
}

class ClassEntry {
  final String place;
  final String animal;
  final String exhibitorName;
  final String sex;
  final String variety;
  final String status;

  const ClassEntry({
    required this.place,
    required this.animal,
    required this.exhibitorName,
    this.sex = '',
    this.variety = '',
    this.status = '',
  });
}