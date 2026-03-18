class ExhibitorReportData {
  final String exhibitorName;
  final String exhibitorAddress;
  final String exhibitorCityStateZip;

  final String showName;
  final String showDate;
  final String showLocation;

  final String secretaryName;
  final String secretaryEmail;

  final List<ExhibitorEntryRow> entries;

  ExhibitorReportData({
    required this.exhibitorName,
    required this.exhibitorAddress,
    required this.exhibitorCityStateZip,
    required this.showName,
    required this.showDate,
    required this.showLocation,
    required this.secretaryName,
    required this.secretaryEmail,
    required this.entries,
  });
}

class ExhibitorEntryRow {
  final String showSection;
  final int showSectionSort;

  final String tattoo;
  final String breed;
  final String variety;
  final String className;
  final String sex;

  final String placing;
  final int? classCount;
  final int? exhibitorCount;

  final String awardsText;
  final String judgeName;
  final bool earnedLeg;

  final int displayPoints;
  final int specialtyPoints;
  final int totalPoints;

  ExhibitorEntryRow({
    required this.showSection,
    required this.showSectionSort,
    required this.tattoo,
    required this.breed,
    required this.variety,
    required this.className,
    required this.sex,
    required this.placing,
    required this.classCount,
    required this.exhibitorCount,
    required this.awardsText,
    required this.judgeName,
    required this.earnedLeg,
    required this.displayPoints,
    required this.specialtyPoints,
    required this.totalPoints,
  });
}