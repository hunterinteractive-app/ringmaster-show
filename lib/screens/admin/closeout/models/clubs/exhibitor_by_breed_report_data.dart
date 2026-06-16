class ExhibitorByBreedReportData {
  final String showId;
  final String showName;
  final String showDate;
  final String showLocation;
  final String hostClubName;
  final String scope;
  final String showLetter;

  final String secretaryName;
  final String secretaryAddress;
  final String secretaryEmail;
  final String secretaryPhone;

  final List<ExhibitorByBreedSection> sections;

  const ExhibitorByBreedReportData({
    required this.showId,
    required this.showName,
    required this.showDate,
    required this.showLocation,
    required this.hostClubName,
    required this.scope,
    required this.showLetter,
    required this.secretaryName,
    required this.secretaryAddress,
    required this.secretaryEmail,
    required this.secretaryPhone,
    required this.sections,
  });
}

class ExhibitorByBreedSection {
  final String breedName;
  final List<ExhibitorByBreedRow> rows;

  const ExhibitorByBreedSection({
    required this.breedName,
    required this.rows,
  });
}

class ExhibitorByBreedRow {
  final String exhibitorName;
  final String exhibitorAddress;
  final int animalsShown;
  final double classPoints;
  final double varietyPoints;
  final double groupPoints;
  final double bobBosPoints;
  final double bisRisPoints;
  final double furWoolPoints;
  final double totalPoints;

  const ExhibitorByBreedRow({
    required this.exhibitorName,
    required this.exhibitorAddress,
    required this.animalsShown,
    required this.classPoints,
    required this.varietyPoints,
    required this.groupPoints,
    required this.bobBosPoints,
    required this.bisRisPoints,
    required this.furWoolPoints,
    required this.totalPoints,
  });
}
