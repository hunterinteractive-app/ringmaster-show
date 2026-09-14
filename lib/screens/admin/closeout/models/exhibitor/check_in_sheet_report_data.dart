class CheckInSheetReportData {
  const CheckInSheetReportData({
    required this.showName,
    required this.sectionLabel,
    required this.entries,
    required this.showContact,
    this.waveNote,
    this.waveSchedule,
    this.waveSheets = const [],
  });

  // Archived packets keep a separate sheet for every entered wave.
  final List<CheckInSheetReportData> waveSheets;
  final String showName;
  final String? waveNote;
  final String? waveSchedule;
  final String sectionLabel;
  final List<Map<String, dynamic>> entries;
  final Map<String, dynamic> showContact;
}
