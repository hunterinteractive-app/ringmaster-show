class ArbaReportData {
  const ArbaReportData({
    required this.showName,
    required this.secretaryName,
    required this.secretaryEmail,
    required this.secretaryPhone,
    required this.sanctionNumber,
    required this.reportDate,
    required this.rabbitsShown,
    required this.caviesShown,
    required this.clubName,
    required this.showDate,
    required this.showLocation,
    required this.secretaryAddress,
    required this.superintendentName,
    required this.ribbonsReportsMailedAt,
    required this.sweepstakesReportsFiledAt,
    required this.judges,
    required this.troubleReceivingSanctions,
    required this.troubleReceivingSanctionClubs,
    required this.filedDate,
    required this.signedBy,
    required this.protestFiled,
    required this.protestReportFiled,
    required this.bisRabbitOwner,
    required this.bisRabbitCityState,
    required this.bisRabbitBreed,
    required this.bisRabbitEarNumber,
    required this.superintendentArbaNumber,
  });

  final String showName;
  final String secretaryName;
  final String secretaryEmail;
  final String secretaryPhone;

  final String superintendentArbaNumber;

  final String sanctionNumber;
  final DateTime? reportDate;

  final int rabbitsShown;
  final int caviesShown;

  final String clubName;
  final DateTime? showDate;
  final String showLocation;

  final String secretaryAddress;
  final String superintendentName;

  final DateTime? ribbonsReportsMailedAt;
  final DateTime? sweepstakesReportsFiledAt;

  final List<String> judges;

  final String troubleReceivingSanctions;
  final String troubleReceivingSanctionClubs;

  final DateTime? filedDate;
  final String signedBy;

  final String protestFiled;
  final String protestReportFiled;

  final String bisRabbitOwner;
  final String bisRabbitCityState;
  final String bisRabbitBreed;
  final String bisRabbitEarNumber;
}