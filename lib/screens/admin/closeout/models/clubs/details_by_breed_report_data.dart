class DetailsByBreedReportData {
  final String showId;
  final String showName;
  final String showDate;
  final String reportDate;
  final String showLocation;
  final String hostClubName;
  final String scope;
  final String showLetter;
  final String showType;
  final String specialtyStatus;
  final String arbaSanctionNumber;
  final String stateClubName;
  final String stateClubSanctionNumber;

  final String secretaryName;
  final String secretaryAddress;
  final String secretaryEmail;
  final String secretaryPhone;
  final String superintendentName;

  final List<DetailsByBreedOverallWinner> overallWinners;
  final List<DetailsByBreedBreedSection> breeds;

  const DetailsByBreedReportData({
    required this.showId,
    required this.showName,
    required this.showDate,
    required this.reportDate,
    required this.showLocation,
    required this.hostClubName,
    required this.scope,
    required this.showLetter,
    required this.showType,
    required this.specialtyStatus,
    required this.arbaSanctionNumber,
    required this.stateClubName,
    required this.stateClubSanctionNumber,
    required this.secretaryName,
    required this.secretaryAddress,
    required this.secretaryEmail,
    required this.secretaryPhone,
    required this.superintendentName,
    required this.overallWinners,
    required this.breeds,
  });
}

class DetailsByBreedOverallWinner {
  final String award;
  final String earNumber;
  final String breedName;
  final String varietyName;
  final String className;
  final String sex;
  final String exhibitorName;
  final int showAnimals;
  final int showExhibitors;
  final List<String> additionalAwards;

  const DetailsByBreedOverallWinner({
    required this.award,
    required this.earNumber,
    required this.breedName,
    required this.varietyName,
    required this.className,
    required this.sex,
    required this.exhibitorName,
    required this.showAnimals,
    required this.showExhibitors,
    required this.additionalAwards,
  });
}

class DetailsByBreedBreedSection {
  final String breedName;
  final String judgeName;
  final int animalsShown;
  final int exhibitorCount;
  final DetailsByBreedAwardRow? bob;
  final DetailsByBreedAwardRow? bosb;
  final List<DetailsByBreedAwardRow> specialAwards;
  final List<DetailsByBreedVarietySection> varieties;

  const DetailsByBreedBreedSection({
    required this.breedName,
    required this.judgeName,
    required this.animalsShown,
    required this.exhibitorCount,
    required this.bob,
    required this.bosb,
    required this.specialAwards,
    required this.varieties,
  });
}

class DetailsByBreedVarietySection {
  final String varietyName;
  final int animalsShown;
  final int exhibitorCount;
  final DetailsByBreedAwardRow? bov;
  final DetailsByBreedAwardRow? bosv;
  final List<DetailsByBreedClassSection> classes;

  const DetailsByBreedVarietySection({
    required this.varietyName,
    required this.animalsShown,
    required this.exhibitorCount,
    required this.bov,
    required this.bosv,
    required this.classes,
  });
}

class DetailsByBreedClassSection {
  final String className;
  final String sex;
  final int animalsShown;
  final int exhibitorCount;
  final List<DetailsByBreedPlacementRow> placements;

  const DetailsByBreedClassSection({
    required this.className,
    required this.sex,
    required this.animalsShown,
    required this.exhibitorCount,
    required this.placements,
  });
}

class DetailsByBreedAwardRow {
  final String award;
  final String earNumber;
  final String varietyName;
  final String className;
  final String sex;
  final String exhibitorName;
  final int animalsShown;
  final int exhibitorCount;
  final List<String> additionalAwards;

  const DetailsByBreedAwardRow({
    required this.award,
    required this.earNumber,
    required this.varietyName,
    required this.className,
    required this.sex,
    required this.exhibitorName,
    required this.animalsShown,
    required this.exhibitorCount,
    required this.additionalAwards,
  });
}

class DetailsByBreedPlacementRow {
  final int placement;
  final String earNumber;
  final String animalName;
  final String exhibitorName;
  final List<String> awards;

  const DetailsByBreedPlacementRow({
    required this.placement,
    required this.earNumber,
    required this.animalName,
    required this.exhibitorName,
    required this.awards,
  });
}