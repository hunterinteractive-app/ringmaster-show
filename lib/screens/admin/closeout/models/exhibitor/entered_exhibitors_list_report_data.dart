class EnteredExhibitorsListRow {
  final String exhibitorNumber;
  final String lastName;
  final String firstName;
  final String displayName;

  const EnteredExhibitorsListRow({
    required this.exhibitorNumber,
    required this.lastName,
    required this.firstName,
    required this.displayName,
  });
}

class EnteredExhibitorsListReportData {
  final String showId;
  final String showName;
  final List<EnteredExhibitorsListRow> rows;

  const EnteredExhibitorsListReportData({
    required this.showId,
    required this.showName,
    required this.rows,
  });
}
