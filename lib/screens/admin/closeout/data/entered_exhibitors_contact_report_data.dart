// lib/screens/admin/closeout/data/entered_exhibitors_contact_report_data.dart

class EnteredExhibitorsContactRow {
  final String exhibitorName;
  final String address;
  final String email;
  final String phone;

  EnteredExhibitorsContactRow({
    required this.exhibitorName,
    required this.address,
    required this.email,
    required this.phone,
  });
}

class EnteredExhibitorsContactReportData {
  final String showName;
  final List<EnteredExhibitorsContactRow> rows;

  EnteredExhibitorsContactReportData({
    required this.showName,
    required this.rows,
  });
}