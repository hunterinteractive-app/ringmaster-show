// lib/screens/admin/closeout/models/paid/paid_exhibitor_report_data.dart

class PaidExhibitorReportData {
  final String showName;
  final String showDate;
  final String showLocation;
  final String currency;

  final List<PaidExhibitorRow> rows;

  final int totalExhibitors;
  final int totalEntries;
  final int totalFurEntries;

  final double grandSubtotal;
  final double grandShowFee;
  final double grandDiscount;
  final double grandCalculatedTotal;

  final double grandPaidOnline;
  final double grandPaidManual;
  final double grandRefunded;
  final double grandAmountPaid;
  final double grandBalanceDue;

  PaidExhibitorReportData({
    required this.showName,
    required this.showDate,
    required this.showLocation,
    required this.currency,
    required this.rows,
    required this.totalExhibitors,
    required this.totalEntries,
    this.totalFurEntries = 0,
    this.grandSubtotal = 0,
    this.grandShowFee = 0,
    this.grandDiscount = 0,
    this.grandCalculatedTotal = 0,
    this.grandPaidOnline = 0,
    this.grandPaidManual = 0,
    this.grandRefunded = 0,
    required this.grandAmountPaid,
    this.grandBalanceDue = 0,
  });
}

class PaidExhibitorRow {
  final String balanceId;
  final String exhibitorId;
  final String exhibitorUserId;
  final String exhibitorName;
  final String exhibitorType;
  final String phone;
  final String email;
  final String addressLine1;
  final String addressLine2;
  final String city;
  final String state;
  final String zip;
  final String arbaNumber;
  final String paymentStatus;
  final String source;

  final List<PaidSectionCountRow> sections;

  final int entryCount;
  final int furCount;

  final double entriesSubtotal;
  final double furSubtotal;
  final double subtotal;
  final double showFee;
  final double discount;
  final double calculatedTotal;

  final double paidOnline;
  final double paidManual;
  final double refunded;
  final double amountPaid;
  final double balanceDue;

  PaidExhibitorRow({
    this.balanceId = '',
    required this.exhibitorId,
    this.exhibitorUserId = '',
    required this.exhibitorName,
    required this.exhibitorType,
    required this.phone,
    this.email = '',
    this.addressLine1 = '',
    this.addressLine2 = '',
    this.city = '',
    this.state = '',
    this.zip = '',
    this.arbaNumber = '',
    this.paymentStatus = 'paid',
    this.source = '',
    required this.sections,
    required this.entryCount,
    this.furCount = 0,
    this.entriesSubtotal = 0,
    this.furSubtotal = 0,
    required this.subtotal,
    required this.showFee,
    required this.discount,
    this.calculatedTotal = 0,
    this.paidOnline = 0,
    this.paidManual = 0,
    this.refunded = 0,
    required this.amountPaid,
    this.balanceDue = 0,
  });
}

class PaidSectionCountRow {
  final String label;
  final String sectionId;
  final String kind;
  final String letter;
  final int count;
  final int furCount;
  final double entriesSubtotal;
  final double furSubtotal; 
  final double showFee;

  PaidSectionCountRow({
    required this.label,
    this.sectionId = '',
    this.kind = '',
    this.letter = '',
    required this.count,
    this.furCount = 0,
    this.entriesSubtotal = 0,
    this.furSubtotal = 0,
    this.showFee = 0,
  });
}