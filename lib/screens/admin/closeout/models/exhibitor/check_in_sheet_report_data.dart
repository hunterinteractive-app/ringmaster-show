class CheckInSheetReportData {
  const CheckInSheetReportData({
    required this.showName,
    required this.sectionLabel,
    required this.entries,
    required this.showContact,
  });

  final String showName;
  final String sectionLabel;
  final List<Map<String, dynamic>> entries;
  final Map<String, dynamic> showContact;
}
