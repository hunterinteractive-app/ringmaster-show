// lib/screens/admin/closeout/models/exhibitor/entered_exhibitors_contact_report_data.dart

class EnteredExhibitorsContactRow {
  final String exhibitorName;
  final String address;
  final String email;
  final String phone;

  const EnteredExhibitorsContactRow({
    required this.exhibitorName,
    required this.address,
    required this.email,
    required this.phone,
  });
}

class EnteredExhibitorsContactReportData {
  final String showId;
  final String showName;
  final List<EnteredExhibitorsContactRow> rows;

  const EnteredExhibitorsContactReportData({
    required this.showId,
    required this.showName,
    required this.rows,
  });
}