// lib/screens/admin/closeout/data/loaders/unpaid_balances_report_loader.dart

import '../../models/base/report_request.dart';
import '../../models/unpaid/unpaid_balances_report_data.dart';
import '../closeout_repository.dart';

class UnpaidBalancesReportLoader {
  final CloseoutRepository repo;

  UnpaidBalancesReportLoader(this.repo);

  Future<UnpaidBalancesReportData> load(ReportRequest request) async {
    final showId = request.showId;

    final show = await repo.loadShowBasics(showId);
    final feeSettings = await repo.loadShowFeeSettings(showId);
    final sectionFeeSettings = await repo.loadShowSectionFeeSettings(showId);
    final sections = await repo.loadShowSections(showId);
    final entries = await repo.loadEntriesForBalanceReport(showId);

    final validEntries = entries.where((row) {
      final scratchedAt = row['scratched_at'];
      final isDisqualified = row['is_disqualified'] == true;
      final isTest = row['is_test'] == true;

      return scratchedAt == null && !isDisqualified && !isTest;
    }).map((e) => Map<String, dynamic>.from(e)).toList();

    final exhibitorIds = validEntries
        .map((e) => _str(e['exhibitor_id']))
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    final exhibitorRows = await repo.loadExhibitorsByIds(exhibitorIds);

    final exhibitorById = <String, Map<String, dynamic>>{
      for (final row in exhibitorRows) _str(row['id']): row,
    };

    final sectionById = <String, Map<String, dynamic>>{
      for (final row in sections) _str(row['id']): row,
    };

    final sectionFeeById = <String, Map<String, dynamic>>{
      for (final row in sectionFeeSettings) _str(row['section_id']): row,
    };

    final groupedByExhibitor = <String, List<Map<String, dynamic>>>{};

    for (final entry in validEntries) {
      final exhibitorId = _str(entry['exhibitor_id']);
      if (exhibitorId.isEmpty) continue;

      groupedByExhibitor.putIfAbsent(exhibitorId, () => []).add(entry);
    }

    final currency = _str(feeSettings?['currency']).isEmpty
        ? 'USD'
        : _str(feeSettings?['currency']);

    final feePerEntry = _asDouble(feeSettings?['fee_per_entry']);
    final feePerShow = _asDouble(feeSettings?['fee_per_show']);
    final discountEnabled =
        feeSettings?['multi_show_discount_enabled'] == true;
    final discountType =
        _str(feeSettings?['multi_show_discount_type']).toLowerCase();
    final discountValue = _asDouble(feeSettings?['multi_show_discount_value']);

    final rows = <UnpaidBalanceRow>[];

    for (final entry in groupedByExhibitor.entries) {
      final exhibitorId = entry.key;
      final exhibitorEntries = entry.value;
      final exhibitor = exhibitorById[exhibitorId] ?? const <String, dynamic>{};

      final exhibitorName = _resolveExhibitorName(exhibitor);
      final exhibitorType = _titleCase(_str(exhibitor['type']));
      final phone = _str(exhibitor['phone']);

      final sectionCounts = <String, int>{};
      for (final item in exhibitorEntries) {
        final sectionId = _str(item['section_id']);
        final section = sectionById[sectionId];
        final sectionLabel = _buildSectionLabel(section);
        sectionCounts[sectionLabel] = (sectionCounts[sectionLabel] ?? 0) + 1;
      }

      final sectionRows = sectionCounts.entries
          .map(
            (e) => SectionCountRow(
              label: e.key,
              count: e.value,
            ),
          )
          .toList()
        ..sort((a, b) => a.label.compareTo(b.label));

      final entryCount = exhibitorEntries.length;
      final subtotal = exhibitorEntries.fold<double>(0.0, (sum, item) {
        final sectionId = _str(item['section_id']);
        final sectionFees = sectionFeeById[sectionId];
        final sectionEntryFee = _asDouble(
          sectionFees?['fee_per_entry'],
          fallback: feePerEntry,
        );

        final furFee = item['is_fur'] == true
            ? _asDouble(sectionFees?['fur_fee'])
            : 0.0;

        return sum + sectionEntryFee + furFee;
      });

      final chargedSectionIds = exhibitorEntries
          .map((item) => _str(item['section_id']))
          .where((id) => id.isNotEmpty)
          .toSet();

      final showFee = chargedSectionIds.fold<double>(0.0, (sum, sectionId) {
        final sectionFees = sectionFeeById[sectionId];
        final sectionShowFee = _asDouble(
          sectionFees?['fee_per_show'],
          fallback: feePerShow,
        );
        return sum + sectionShowFee;
      });

      final discount = _calculateMultiShowDiscount(
        exhibitorEntries,
        sectionFeeById: sectionFeeById,
        fallbackFeePerEntry: feePerEntry,
        discountEnabled: discountEnabled,
        discountType: discountType,
        discountValue: discountValue,
      );

      final totalDue = (subtotal + showFee) - discount;

      final row = UnpaidBalanceRow(
        exhibitorId: exhibitorId,
        exhibitorName: exhibitorName,
        exhibitorType: exhibitorType,
        phone: phone,
        sections: sectionRows,
        entryCount: entryCount,
        subtotal: subtotal,
        showFee: showFee,
        discount: discount,
        totalDue: totalDue < 0 ? 0.0 : totalDue,
      );

      if (request.hideZeroBalances && row.totalDue <= 0) {
        continue;
      }

      rows.add(row);
    }

    rows.sort(
      (a, b) => a.exhibitorName.toLowerCase().compareTo(
            b.exhibitorName.toLowerCase(),
          ),
    );

    final totalExhibitors = rows.length;
    final totalEntries = rows.fold<int>(0, (sum, row) => sum + row.entryCount);
    final grandTotalDue =
        rows.fold<double>(0.0, (sum, row) => sum + row.totalDue);

    return UnpaidBalancesReportData(
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
      grandTotalDue: grandTotalDue,
    );
  }

  double _calculateMultiShowDiscount(
    List<Map<String, dynamic>> entries, {
    required Map<String, Map<String, dynamic>> sectionFeeById,
    required double fallbackFeePerEntry,
    required bool discountEnabled,
    required String discountType,
    required double discountValue,
  }) {
    if (!discountEnabled || entries.length < 2) return 0.0;

    final entriesByAnimal = <String, List<Map<String, dynamic>>>{};
    for (final entry in entries) {
      final animalId = _str(entry['animal_id']);
      if (animalId.isEmpty) continue;
      entriesByAnimal.putIfAbsent(animalId, () => []).add(entry);
    }

    var discount = 0.0;

    for (final animalEntries in entriesByAnimal.values) {
      if (animalEntries.length <= 1) continue;

      final sorted = [...animalEntries]
        ..sort((a, b) {
          final aFee = _entryFeeForDiscount(
            a,
            sectionFeeById: sectionFeeById,
            fallbackFeePerEntry: fallbackFeePerEntry,
          );
          final bFee = _entryFeeForDiscount(
            b,
            sectionFeeById: sectionFeeById,
            fallbackFeePerEntry: fallbackFeePerEntry,
          );
          return bFee.compareTo(aFee);
        });

      for (final entry in sorted.skip(1)) {
        final entryFee = _entryFeeForDiscount(
          entry,
          sectionFeeById: sectionFeeById,
          fallbackFeePerEntry: fallbackFeePerEntry,
        );

        if (entryFee <= 0) continue;

        if (discountType == 'percent') {
          final pct =
              (discountValue <= 1.0) ? discountValue : (discountValue / 100.0);
          discount += entryFee * pct;
        } else if (discountType == 'amount') {
          discount += discountValue > entryFee ? entryFee : discountValue;
        }
      }
    }

    return discount < 0 ? 0.0 : discount;
  }

  double _entryFeeForDiscount(
    Map<String, dynamic> entry, {
    required Map<String, Map<String, dynamic>> sectionFeeById,
    required double fallbackFeePerEntry,
  }) {
    final sectionId = _str(entry['section_id']);
    final sectionFees = sectionFeeById[sectionId];
    return _asDouble(
      sectionFees?['fee_per_entry'],
      fallback: fallbackFeePerEntry,
    );
  }

  String _resolveExhibitorName(Map<String, dynamic> exhibitor) {
    final showingName = _str(exhibitor['showing_name']);
    if (showingName.isNotEmpty) return showingName;

    final displayName = _str(exhibitor['display_name']);
    if (displayName.isNotEmpty) return displayName;

    final fullName = [
      _str(exhibitor['first_name']),
      _str(exhibitor['last_name']),
    ].where((e) => e.isNotEmpty).join(' ').trim();

    if (fullName.isNotEmpty) return fullName;

    return 'Unknown Exhibitor';
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

  double _asDouble(dynamic value, {double fallback = 0.0}) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();

    final s = value.toString().trim();
    if (s.isEmpty) return fallback;

    return double.tryParse(s) ?? fallback;
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