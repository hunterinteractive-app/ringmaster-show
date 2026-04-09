// lib/screens/admin/closeout/models/unpaid/unpaid_balances_report_data.dart

class UnpaidBalancesReportData {
  final String showName;
  final String showDate;
  final String showLocation;
  final String currency;

  final List<UnpaidBalanceRow> rows;

  final int totalExhibitors;
  final int totalEntries;
  final double grandTotalDue;

  UnpaidBalancesReportData({
    required this.showName,
    required this.showDate,
    required this.showLocation,
    required this.currency,
    required this.rows,
    required this.totalExhibitors,
    required this.totalEntries,
    required this.grandTotalDue,
  });
}

class UnpaidBalanceRow {
  final String exhibitorId;
  final String exhibitorName;
  final String exhibitorType;
  final String phone;

  final List<SectionCountRow> sections;

  final int entryCount;
  final double subtotal;
  final double showFee;
  final double discount;
  final double totalDue;

  UnpaidBalanceRow({
    required this.exhibitorId,
    required this.exhibitorName,
    required this.exhibitorType,
    required this.phone,
    required this.sections,
    required this.entryCount,
    required this.subtotal,
    required this.showFee,
    required this.discount,
    required this.totalDue,
  });
}

class SectionCountRow {
  final String label;
  final int count;

  SectionCountRow({
    required this.label,
    required this.count,
  });
}