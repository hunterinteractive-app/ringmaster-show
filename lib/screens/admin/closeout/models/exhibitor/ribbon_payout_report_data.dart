// lib/screens/admin/closeout/models/exhibitor/ribbon_payout_report_data.dart

class RibbonPayoutRow {
  final String exhibitorNumber;
  final String exhibitorName;
  final int first;
  final int second;
  final int third;
  final int fourth;
  final int fifth;

  const RibbonPayoutRow({
    required this.exhibitorNumber,
    required this.exhibitorName,
    required this.first,
    required this.second,
    required this.third,
    required this.fourth,
    required this.fifth,
  });
}

class RibbonPayoutReportData {
  final String showId;
  final String showName;
  final String eventName;
  final String sponsoringClub;
  final String eventSecretary;
  final String eventSecretaryEmail;
  final String sponsoringSuperintendent;
  final String classification;
  final String showLetter;
  final String type;
  final String specialty;
  final String arbaSanction;
  final List<RibbonPayoutRow> rows;

  const RibbonPayoutReportData({
    required this.showId,
    required this.showName,
    required this.eventName,
    required this.sponsoringClub,
    required this.eventSecretary,
    required this.eventSecretaryEmail,
    required this.sponsoringSuperintendent,
    required this.classification,
    required this.showLetter,
    required this.type,
    required this.specialty,
    required this.arbaSanction,
    required this.rows,
  });
}