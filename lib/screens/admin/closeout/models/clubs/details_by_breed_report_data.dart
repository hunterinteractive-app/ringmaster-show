class DetailsByBreedReportData {
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

  final List<DetailsByBreedRow> rows;

  const DetailsByBreedReportData({
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
    required this.rows,
  });
}

class DetailsByBreedRow {
  final String breedName;
  final int animalsShown;
  final String bobExhibitor;
  final String bosExhibitor;

  const DetailsByBreedRow({
    required this.breedName,
    required this.animalsShown,
    required this.bobExhibitor,
    required this.bosExhibitor,
  });
}
