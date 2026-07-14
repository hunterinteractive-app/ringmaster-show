// lib/screens/admin/closeout/data/loaders/paid_exhibitor_report_loader.dart

import 'dart:convert';

import '../../models/base/report_request.dart';
import '../../models/paid/paid_exhibitor_report_data.dart';
import '../closeout_repository.dart';

class PaidExhibitorReportLoader {
  final CloseoutRepository repo;

  PaidExhibitorReportLoader(this.repo);

  Future<PaidExhibitorReportData> load(ReportRequest request) async {
    final showId = request.showId;

    final show = await repo.loadShowBasics(showId);
    final balanceRows = await repo.loadShowExhibitorBalancesReport(
      showId,
      sectionIds: request.sectionIds,
    );

    final rows = <PaidExhibitorRow>[];

    for (final balance in balanceRows) {
      final paidOnline = _centsToDollars(balance['paid_online_cents']);
      final paidManual = _centsToDollars(balance['paid_manual_cents']);
      final refunded = _centsToDollars(balance['refunded_cents']);

      final amountPaid = paidOnline + paidManual - refunded;

      if (amountPaid <= 0) {
        continue;
      }

      rows.add(
        PaidExhibitorRow(
          balanceId: _str(balance['balance_id']),
          exhibitorId: _str(balance['exhibitor_id']),
          exhibitorUserId: _str(balance['exhibitor_user_id']),
          exhibitorName: _resolveBalanceExhibitorName(balance),
          exhibitorType: _str(balance['exhibitor_type']),
          phone: _str(balance['phone']),
          email: _str(balance['email']),
          addressLine1: _str(balance['address_line1']),
          addressLine2: _str(balance['address_line2']),
          city: _str(balance['city']),
          state: _str(balance['state']),
          zip: _str(balance['zip']),
          arbaNumber: _str(balance['arba_number']),
          paymentStatus: _str(balance['payment_status']),
          source: _str(balance['source']),
          sections: _sectionRowsFromBreakdown(balance['section_breakdown']),
          entryCount: _asInt(balance['entry_count']),
          furCount: _asInt(balance['fur_count']),
          entriesSubtotal: _centsToDollars(balance['entries_subtotal_cents']),
          furSubtotal: _centsToDollars(balance['fur_subtotal_cents']),
          subtotal: _centsToDollars(balance['subtotal_before_discount_cents']),
          showFee: _centsToDollars(balance['show_fee_subtotal_cents']),
          discount: _centsToDollars(balance['discount_cents']),
          calculatedTotal: _centsToDollars(balance['calculated_total_cents']),
          paidOnline: paidOnline,
          paidManual: paidManual,
          refunded: refunded,
          amountPaid: amountPaid < 0 ? 0.0 : amountPaid,
          balanceDue: _centsToDollars(balance['balance_due_cents']),
        ),
      );
    }

    rows.sort(
      (a, b) => a.exhibitorName.toLowerCase().compareTo(
        b.exhibitorName.toLowerCase(),
      ),
    );

    final totalExhibitors = rows.length;
    final totalEntries = rows.fold<int>(0, (sum, row) => sum + row.entryCount);
    final totalFurEntries = rows.fold<int>(0, (sum, row) => sum + row.furCount);
    final grandSubtotal = rows.fold<double>(
      0.0,
      (sum, row) => sum + row.subtotal,
    );
    final grandShowFee = rows.fold<double>(
      0.0,
      (sum, row) => sum + row.showFee,
    );
    final grandDiscount = rows.fold<double>(
      0.0,
      (sum, row) => sum + row.discount,
    );
    final grandCalculatedTotal = rows.fold<double>(
      0.0,
      (sum, row) => sum + row.calculatedTotal,
    );
    final grandAmountPaid = rows.fold<double>(
      0.0,
      (sum, row) => sum + row.amountPaid,
    );
    final grandPaidOnline = rows.fold<double>(
      0.0,
      (sum, row) => sum + row.paidOnline,
    );
    final grandPaidManual = rows.fold<double>(
      0.0,
      (sum, row) => sum + row.paidManual,
    );
    final grandRefunded = rows.fold<double>(
      0.0,
      (sum, row) => sum + row.refunded,
    );
    final grandBalanceDue = rows.fold<double>(
      0.0,
      (sum, row) => sum + row.balanceDue,
    );

    final currency = balanceRows.isEmpty
        ? 'USD'
        : (_str(balanceRows.first['currency']).isEmpty
              ? 'USD'
              : _str(balanceRows.first['currency']).toUpperCase());

    return PaidExhibitorReportData(
      showName: _str(show['name']),
      showDate: _formatShowDateRange(show['start_date'], show['end_date']),
      showLocation: [
        _str(show['location_name']),
        _str(show['location_address']),
      ].where((e) => e.isNotEmpty).join(', '),
      currency: currency,
      rows: rows,
      totalExhibitors: totalExhibitors,
      totalEntries: totalEntries,
      totalFurEntries: totalFurEntries,
      grandSubtotal: grandSubtotal,
      grandShowFee: grandShowFee,
      grandDiscount: grandDiscount,
      grandCalculatedTotal: grandCalculatedTotal,
      grandPaidOnline: grandPaidOnline,
      grandPaidManual: grandPaidManual,
      grandRefunded: grandRefunded,
      grandAmountPaid: grandAmountPaid,
      grandBalanceDue: grandBalanceDue,
    );
  }

  String _resolveBalanceExhibitorName(Map<String, dynamic> balance) {
    final exhibitorName = _str(balance['exhibitor_name']);
    if (exhibitorName.isNotEmpty) return exhibitorName;

    final showingName = _str(balance['showing_name']);
    if (showingName.isNotEmpty) return showingName;

    final displayName = _str(balance['display_name']);
    if (displayName.isNotEmpty) return displayName;

    final fullName = [
      _str(balance['first_name']),
      _str(balance['last_name']),
    ].where((e) => e.isNotEmpty).join(' ').trim();

    if (fullName.isNotEmpty) return fullName;

    return 'Unknown Exhibitor';
  }

  List<PaidSectionCountRow> _sectionRowsFromBreakdown(dynamic value) {
    final items = _jsonList(value);
    if (items.isEmpty) return const <PaidSectionCountRow>[];

    final parsedRows = items
        .whereType<Map>()
        .map((item) {
          final map = Map<String, dynamic>.from(item);
          final label = _str(map['label']).isEmpty
              ? _buildSectionLabel(map)
              : _str(map['label']);

          return _ParsedSectionCountRow(
            label: label,
            sectionId: _str(map['section_id']),
            count: _asInt(map['entry_count']),
            kind: _str(map['kind']),
            letter: _str(map['letter']),
            furCount: _asInt(map['fur_count']),
            entriesSubtotal: _centsToDollars(map['entries_subtotal_cents']),
            furSubtotal: _centsToDollars(map['fur_subtotal_cents']),
            showFee: _centsToDollars(map['show_fee_cents']),
          );
        })
        .where((row) => row.label.isNotEmpty && row.count > 0)
        .toList();

    parsedRows.sort((a, b) {
      final kindCompare = _sectionKindRank(
        a.kind,
      ).compareTo(_sectionKindRank(b.kind));
      if (kindCompare != 0) return kindCompare;

      final letterCompare = a.letter.toUpperCase().compareTo(
        b.letter.toUpperCase(),
      );
      if (letterCompare != 0) return letterCompare;

      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });

    return parsedRows
        .map(
          (row) => PaidSectionCountRow(
            label: row.label,
            sectionId: row.sectionId,
            kind: row.kind,
            letter: row.letter,
            count: row.count,
            furCount: row.furCount,
            entriesSubtotal: row.entriesSubtotal,
            furSubtotal: row.furSubtotal,
            showFee: row.showFee,
          ),
        )
        .toList();
  }

  List<dynamic> _jsonList(dynamic value) {
    if (value is List) return value;

    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return const <dynamic>[];

      try {
        final decoded = jsonDecode(trimmed);
        return decoded is List ? decoded : const <dynamic>[];
      } catch (_) {
        return const <dynamic>[];
      }
    }

    return const <dynamic>[];
  }

  int _sectionKindRank(String kind) {
    switch (kind.trim().toLowerCase()) {
      case 'open':
        return 0;
      case 'youth':
        return 1;
      default:
        return 9;
    }
  }

  double _centsToDollars(dynamic value) {
    return _asInt(value) / 100.0;
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.round();

    final s = value.toString().trim();
    if (s.isEmpty) return fallback;

    return int.tryParse(s) ?? double.tryParse(s)?.round() ?? fallback;
  }

  String _buildSectionLabel(Map<String, dynamic>? section) {
    if (section == null) return 'Unknown Section';

    final kind = _titleCase(_str(section['kind']));
    final letter = _str(section['letter']).toUpperCase();

    if (kind.isEmpty && letter.isEmpty) return 'Unknown Section';
    if (kind.isEmpty) return letter;
    if (letter.isEmpty) return kind;

    return '$kind $letter';
  }

  String _formatShowDateRange(dynamic startDate, dynamic endDate) {
    final start = _tryParseDate(startDate);
    final end = _tryParseDate(endDate);

    if (start == null && end == null) return '';
    if (start != null && end != null) {
      return '${_fmtDate(start)} - ${_fmtDate(end)}';
    }
    return _fmtDate(start ?? end!);
  }

  String _fmtDate(DateTime value) {
    return '${value.month}/${value.day}/${value.year}';
  }

  String _titleCase(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';

    return trimmed
        .split(RegExp(r'\s+'))
        .map((word) {
          if (word.isEmpty) return word;
          final lower = word.toLowerCase();
          return lower[0].toUpperCase() + lower.substring(1);
        })
        .join(' ');
  }

  String _str(dynamic value) {
    if (value == null) return '';
    return value.toString().trim();
  }

  DateTime? _tryParseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }
}

class _ParsedSectionCountRow {
  final String label;
  final String sectionId;
  final int count;
  final String kind;
  final String letter;
  final int furCount;
  final double entriesSubtotal;
  final double furSubtotal;
  final double showFee;

  const _ParsedSectionCountRow({
    required this.label,
    required this.sectionId,
    required this.count,
    required this.kind,
    required this.letter,
    required this.furCount,
    required this.entriesSubtotal,
    required this.furSubtotal,
    required this.showFee,
  });
}
