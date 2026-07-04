// lib/screens/admin/print_packs/check_in_generator_sheet.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/services/app_session.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'print_pack_pdf_helpers.dart';

final supabase = Supabase.instance.client;

class CheckInGeneratorSheet extends StatefulWidget {
  final String showId;
  final String showName;
  final List<Map<String, dynamic>> sections;
  final String? sectionId;
  final String sectionLabel;
  final bool includeScratched;
  final bool combineSections;
  final bool pairOpenYouthByLetter;
  final bool youthFirst;

  const CheckInGeneratorSheet({
    super.key,
    required this.showId,
    required this.showName,
    required this.sections,
    required this.sectionId,
    required this.sectionLabel,
    required this.includeScratched,
    required this.combineSections,
    required this.pairOpenYouthByLetter,
    required this.youthFirst,
  });

  @override
  State<CheckInGeneratorSheet> createState() => _CheckInGeneratorSheetState();
}

class _CheckInGeneratorSheetState extends State<CheckInGeneratorSheet> {
  bool _building = false;
  bool _sortExhibitorsByLastName = false;
  String? _msg;
  Map<String, dynamic>? _showRow;

  Future<void> _loadShowContact() async {
    final row = await supabase
        .from('shows')
        .select('id, secretary_name, secretary_phone, secretary_email')
        .eq('id', widget.showId)
        .maybeSingle();

    _showRow = row ?? <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> _fetchEntries() async {
    const pageSize = 1000;
    final list = <Map<String, dynamic>>[];

    for (var from = 0; ; from += pageSize) {
      final to = from + pageSize - 1;
      final rows = await supabase
          .rpc(
            'report_checkin_entries',
            params: {
              'p_show_id': widget.showId,
              'p_section_id': widget.combineSections ? null : widget.sectionId,
              'p_include_scratched': widget.includeScratched,
            },
          )
          .range(from, to);

      final page = (rows as List).cast<Map<String, dynamic>>();
      list.addAll(page);

      if (page.length < pageSize) break;
    }

    final exhibitorIds = list
        .map((e) => (e['exhibitor_id'] ?? '').toString().trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (exhibitorIds.isNotEmpty) {
      final exhibitorById = <String, Map<String, dynamic>>{};
      const exhibitorPageSize = 500;

      for (var i = 0; i < exhibitorIds.length; i += exhibitorPageSize) {
        final chunk = exhibitorIds.skip(i).take(exhibitorPageSize).toList();
        final exhibitorRows = await supabase
            .from('exhibitors')
            .select(
              'id, exhibitor_number, first_name, last_name, display_name, showing_name',
            )
            .inFilter('id', chunk);

        for (final row
            in (exhibitorRows as List).cast<Map<String, dynamic>>()) {
          final id = (row['id'] ?? '').toString().trim();
          if (id.isNotEmpty) {
            exhibitorById[id] = row;
          }
        }
      }

      for (final entry in list) {
        final exhibitorId = (entry['exhibitor_id'] ?? '').toString().trim();
        final exhibitor = exhibitorById[exhibitorId];
        if (exhibitor == null) continue;

        final exhibitorNumber = (exhibitor['exhibitor_number'] ?? '')
            .toString()
            .trim();
        if (exhibitorNumber.isNotEmpty) {
          entry['exhibitor_number'] = exhibitorNumber;
        }

        entry['exhibitor_first_name'] = (exhibitor['first_name'] ?? '')
            .toString()
            .trim();
        entry['exhibitor_last_name'] = (exhibitor['last_name'] ?? '')
            .toString()
            .trim();

        final displayName = (exhibitor['display_name'] ?? '').toString().trim();
        final showingName = (exhibitor['showing_name'] ?? '').toString().trim();
        if (displayName.isNotEmpty) {
          entry['exhibitor_display_name'] = displayName;
        }
        if (showingName.isNotEmpty) {
          entry['exhibitor_showing_name'] = showingName;
        }
      }
    }

    // report_checkin_entries does not currently expose every canonical entry
    // field needed by the check-in PDF, so enrich each report row from entries
    // before looking up animal-level coop assignments and fur/wool markers.
    final entryIds = list
        .map((entry) {
          final entryId = (entry['entry_id'] ?? '').toString().trim();
          if (entryId.isNotEmpty) return entryId;
          return (entry['id'] ?? '').toString().trim();
        })
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final animalIdByEntryId = <String, String>{};
    final furByEntryId = <String, bool>{};
    const entryPageSize = 500;

    for (var i = 0; i < entryIds.length; i += entryPageSize) {
      final chunk = entryIds.skip(i).take(entryPageSize).toList();
      if (chunk.isEmpty) continue;

      final entryRows = await supabase
          .from('entries')
          .select('id, animal_id, is_fur, class_name')
          .inFilter('id', chunk);

      for (final raw in (entryRows as List).cast<Map<String, dynamic>>()) {
        final entryId = (raw['id'] ?? '').toString().trim();
        final animalId = (raw['animal_id'] ?? '').toString().trim();
        if (entryId.isEmpty) continue;

        if (animalId.isNotEmpty) {
          animalIdByEntryId[entryId] = animalId;
        }

        final className = (raw['class_name'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        furByEntryId[entryId] =
            _truthy(raw['is_fur']) || className.contains('fur');
      }
    }

    for (final entry in list) {
      final entryId = (entry['entry_id'] ?? '').toString().trim().isNotEmpty
          ? (entry['entry_id'] ?? '').toString().trim()
          : (entry['id'] ?? '').toString().trim();
      entry['animal_id'] = animalIdByEntryId[entryId] ?? '';

      if (entryId.isNotEmpty) {
        entry['is_fur'] =
            _truthy(entry['is_fur']) || (furByEntryId[entryId] ?? false);
      }
    }

    final showModeRow = await supabase
        .from('shows')
        .select('coop_numbering_mode')
        .eq('id', widget.showId)
        .maybeSingle();

    final coopNumberingMode =
        ((showModeRow?['coop_numbering_mode']) ?? 'separate')
            .toString()
            .trim()
            .toLowerCase();

    final animalIds = list
        .map((entry) => (entry['animal_id'] ?? '').toString().trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final coopNumberByAnimalAndScope = <String, String>{};
    const coopPageSize = 500;

    for (var i = 0; i < animalIds.length; i += coopPageSize) {
      final chunk = animalIds.skip(i).take(coopPageSize).toList();
      if (chunk.isEmpty) continue;

      final coopRows = await supabase
          .from('show_animal_coop_numbers')
          .select('animal_id, scope, coop_number')
          .eq('show_id', widget.showId)
          .inFilter('animal_id', chunk);

      for (final raw in (coopRows as List).cast<Map<String, dynamic>>()) {
        final animalId = (raw['animal_id'] ?? '').toString().trim();
        final scope = (raw['scope'] ?? '').toString().trim().toLowerCase();
        final coopNumber = (raw['coop_number'] ?? '').toString().trim();
        if (animalId.isEmpty || scope.isEmpty) continue;
        coopNumberByAnimalAndScope['$animalId|$scope'] = coopNumber;
      }
    }

    for (final entry in list) {
      final animalId = (entry['animal_id'] ?? '').toString().trim();
      final sectionKind = (entry['section_kind'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final scope = coopNumberingMode == 'combined' ? 'all' : sectionKind;

      entry['coop_number'] = animalId.isEmpty || scope.isEmpty
          ? ''
          : (coopNumberByAnimalAndScope['$animalId|$scope'] ?? '');
    }

    int toInt(dynamic value, [int fallback = 9999]) {
      if (value == null) return fallback;
      if (value is int) return value;
      return int.tryParse(value.toString()) ?? fallback;
    }

    int kindRank(String k) {
      switch (k.toLowerCase()) {
        case 'open':
          return widget.youthFirst ? 1 : 0;
        case 'youth':
          return widget.youthFirst ? 0 : 1;
        default:
          return 99;
      }
    }

    list.sort((a, b) {
      final showCmp = _safe(a, 'show_id').compareTo(_safe(b, 'show_id'));
      if (showCmp != 0) return showCmp;

      final sectionKindCmp = kindRank(
        _safe(a, 'section_kind'),
      ).compareTo(kindRank(_safe(b, 'section_kind')));
      final sectionSortCmp = toInt(
        a['section_sort_order'],
      ).compareTo(toInt(b['section_sort_order']));
      final sectionLetterCmp = _safe(
        a,
        'section_letter',
      ).toUpperCase().compareTo(_safe(b, 'section_letter').toUpperCase());

      if (widget.pairOpenYouthByLetter) {
        if (sectionSortCmp != 0) return sectionSortCmp;
        if (sectionLetterCmp != 0) return sectionLetterCmp;
        if (sectionKindCmp != 0) return sectionKindCmp;
      } else {
        if (sectionKindCmp != 0) return sectionKindCmp;
        if (sectionSortCmp != 0) return sectionSortCmp;
        if (sectionLetterCmp != 0) return sectionLetterCmp;
      }

      final exhibitorCmp = _compareExhibitors(a, b);
      if (exhibitorCmp != 0) return exhibitorCmp;

      final breedCmp = _safe(
        a,
        'breed',
      ).toLowerCase().compareTo(_safe(b, 'breed').toLowerCase());
      if (breedCmp != 0) return breedCmp;

      final varietyCmp = _groupVarietyLabel(
        a,
      ).toLowerCase().compareTo(_groupVarietyLabel(b).toLowerCase());
      if (varietyCmp != 0) return varietyCmp;

      final classSortCmp = toInt(
        a['class_sort_order'],
      ).compareTo(toInt(b['class_sort_order']));
      if (classSortCmp != 0) return classSortCmp;

      final sexCmp = _safe(
        a,
        'sex',
      ).toLowerCase().compareTo(_safe(b, 'sex').toLowerCase());
      if (sexCmp != 0) return sexCmp;

      return _safe(
        a,
        'tattoo',
      ).toLowerCase().compareTo(_safe(b, 'tattoo').toLowerCase());
    });

    return list;
  }

  bool _emailing = false;

  String _money(dynamic value) {
    final n = value is num ? value : num.tryParse(value?.toString() ?? '');
    if (n == null) return r'$—';
    return '\$${n.toStringAsFixed(2)}';
  }

  String _moneyFromCents(dynamic value) {
    final n = value is num ? value : num.tryParse(value?.toString() ?? '');
    if (n == null) return r'$—';
    return '\$${(n / 100).toStringAsFixed(2)}';
  }

  bool _hasValue(dynamic value) {
    return value != null && value.toString().trim().isNotEmpty;
  }

  bool _truthy(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;

    final s = value.toString().trim().toLowerCase();
    return s == 'true' ||
        s == 't' ||
        s == 'yes' ||
        s == 'y' ||
        s == '1' ||
        s == 'x';
  }

  String _checkInBalanceDue(List<Map<String, dynamic>> entries) {
    if (entries.isEmpty) return r'$—';

    // Prefer the full exhibitor balance across the show/show package. The
    // check-in sheet should show what the exhibitor owes in total, not just the
    // amount attached to the selected show letter/section currently being
    // printed.
    const allShowCentsKeys = [
      'balance_due_all_shows_cents',
      'all_shows_balance_due_cents',
      'total_balance_due_cents',
      'exhibitor_balance_due_cents',
    ];

    for (final key in allShowCentsKeys) {
      for (final e in entries) {
        final value = e[key];
        if (_hasValue(value)) {
          return _moneyFromCents(value);
        }
      }
    }

    // Backward-compatible all-show/full-show dollar fields from older RPCs.
    const allShowDollarKeys = [
      'balance_due_all_shows',
      'all_shows_balance_due',
      'total_balance_due',
      'exhibitor_balance_due',
    ];

    for (final key in allShowDollarKeys) {
      for (final e in entries) {
        final value = e[key];
        if (_hasValue(value)) {
          return _money(value);
        }
      }
    }

    // Fallback only: these are usually the current show/section amount.
    const selectedShowCentsKeys = [
      'balance_due_cents',
      'balance_due_this_show_cents',
      'this_show_balance_due_cents',
    ];

    for (final key in selectedShowCentsKeys) {
      for (final e in entries) {
        final value = e[key];
        if (_hasValue(value)) {
          return _moneyFromCents(value);
        }
      }
    }

    // Last fallback for older check-in RPC fields. These values were already
    // dollar amounts and usually represent only the selected show.
    const selectedShowDollarKeys = [
      'balance_due_this_show',
      'this_show_balance_due',
    ];

    for (final key in selectedShowDollarKeys) {
      for (final e in entries) {
        final value = e[key];
        if (_hasValue(value)) {
          return _money(value);
        }
      }
    }

    return r'$—';
  }

  String _emailForExhibitor(List<Map<String, dynamic>> entries) {
    for (final e in entries) {
      final exhibitorEmail = _safe(e, 'exhibitor_email');
      if (exhibitorEmail.isNotEmpty && exhibitorEmail.contains('@')) {
        return exhibitorEmail;
      }

      final email = _safe(e, 'email');
      if (email.isNotEmpty && email.contains('@')) return email;
    }
    return '';
  }

  String _safeFileName(String value) {
    return value
        .replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  String _formatFunctionResponse(dynamic data) {
    if (data == null) return '';
    if (data is String) return data;
    try {
      return const JsonEncoder.withIndent('  ').convert(data);
    } catch (_) {
      return data.toString();
    }
  }

  bool _functionReportedFailure(dynamic data) {
    if (data is! Map) return false;

    final ok = data['ok'];
    if (ok is bool && !ok) return true;

    final success = data['success'];
    if (success is bool && !success) return true;

    final failed = data['failed'];
    if (failed is List && failed.isNotEmpty) return true;

    final failures = data['failures'];
    if (failures is List && failures.isNotEmpty) return true;

    final failedCount = data['failed_count'] ?? data['failedCount'];
    if (failedCount is num && failedCount > 0) return true;
    if (failedCount != null && int.tryParse(failedCount.toString()) != null) {
      return int.parse(failedCount.toString()) > 0;
    }

    return false;
  }

  // Loads show secretary/contact details before building each check-in sheet PDF.
  Future<Uint8List> _buildPdfBytesForEntries(
    List<Map<String, dynamic>> entries,
  ) async {
    await _loadShowContact();

    final theme = await buildPrintPackPdfTheme();
    final doc = _buildPdf(entries: entries, theme: theme);

    return Uint8List.fromList(await doc.save());
  }

  Future<void> _emailCheckInSheets() async {
    if (AppSession.isSupportMode) {
      setState(() {
        _msg = 'Email sending is disabled while viewing in support mode.';
      });
      return;
    }
    if (_emailing || _building) return;

    setState(() {
      _emailing = true;
      _msg = null;
    });

    try {
      final entries = await _fetchEntries();

      if (entries.isEmpty) {
        if (!mounted) return;
        setState(() {
          _emailing = false;
          _msg = 'No entries found for this selection.';
        });
        return;
      }

      await _loadShowContact();

      final grouped = _groupByExhibitor(entries);
      var sent = 0;
      var skipped = 0;
      final failed = <String>[];

      for (final entryList in grouped.values) {
        if (entryList.isEmpty) continue;

        final email = _emailForExhibitor(entryList);
        if (email.isEmpty) {
          skipped++;
          continue;
        }

        final exhibitorName = _exhibitorNameFromEntry(entryList.first);
        final pdfBytes = await _buildPdfBytesForEntries(entryList);

        final filename =
            'check_in_${_safeFileName(widget.showName)}_${_safeFileName(exhibitorName)}.pdf';

        final response = await supabase.functions.invoke(
          'send-checkin-sheet-email',
          body: {
            'show_id': widget.showId,
            'show_name': widget.showName,
            'section_label': widget.sectionLabel,
            'exhibitor_id': (entryList.first['exhibitor_id'] ?? '').toString(),
            'exhibitor_name': exhibitorName,
            'to_email': email,
            'filename': filename,
            'pdf_base64': base64Encode(pdfBytes),
          },
        );

        final responseDetails = _formatFunctionResponse(response.data);
        final functionReportedFailure = _functionReportedFailure(response.data);

        if (response.status < 200 ||
            response.status >= 300 ||
            functionReportedFailure) {
          final detailText = responseDetails.trim().isEmpty
              ? 'Status ${response.status}'
              : 'Status ${response.status}: $responseDetails';
          failed.add('$exhibitorName <$email> — $detailText');
          continue;
        }

        sent++;
      }

      if (!mounted) return;
      setState(() {
        _emailing = false;
        final failedSummary = failed.isEmpty
            ? ''
            : ' Failed: ${failed.length}. ${failed.take(10).join(' | ')}${failed.length > 10 ? ' | Plus ${failed.length - 10} more.' : ''}';
        _msg =
            'Email complete. Sent: $sent. Skipped with no email: $skipped.$failedSummary';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _emailing = false;
        _msg = 'Email failed: ${_formatFunctionResponse(e)}';
      });
    }
  }

  String _safe(Map<String, dynamic> e, String k) =>
      (e[k] ?? '').toString().trim();

  String _normalizeSortText(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  bool _hasMultiNameSeparator(String label) {
    return RegExp(r'[/&+,]|\band\b', caseSensitive: false).hasMatch(label);
  }

  String _displayNameSortKey(String label, {required bool byLastName}) {
    final normalizedLabel = _normalizeSortText(label);
    if (!byLastName) return normalizedLabel;

    final trimmedLabel = label.replaceAll(RegExp(r'\s+'), ' ').trim();
    final commaParts = trimmedLabel
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    final firstCommaTokens = commaParts.isEmpty
        ? const <String>[]
        : commaParts.first
              .split(RegExp(r'\s+'))
              .where((part) => part.isNotEmpty)
              .toList();

    if (commaParts.length == 2 && firstCommaTokens.length == 1) {
      return _normalizeSortText('${commaParts.first} ${commaParts.last}');
    }

    final separatorPattern = RegExp(
      r'\s*(?:/|&|\+|\band\b)\s*',
      caseSensitive: false,
    );
    final names = (commaParts.length > 1 ? commaParts : <String>[trimmedLabel])
        .expand((part) => part.split(separatorPattern))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();

    if (names.isEmpty) return normalizedLabel;

    String? sharedLastNameFor(int index) {
      for (var i = index + 1; i < names.length; i++) {
        final tokens = names[i]
            .split(RegExp(r'\s+'))
            .where((part) => part.isNotEmpty)
            .toList();
        if (tokens.length >= 2) return tokens.last;
      }
      for (var i = index - 1; i >= 0; i--) {
        final tokens = names[i]
            .split(RegExp(r'\s+'))
            .where((part) => part.isNotEmpty)
            .toList();
        if (tokens.length >= 2) return tokens.last;
      }
      return null;
    }

    final nameKeys = names.asMap().entries.map((entry) {
      final name = entry.value;
      final normalizedName = name.replaceAll(RegExp(r'\s+'), ' ').trim();
      final tokens = normalizedName
          .split(RegExp(r'\s+'))
          .where((part) => part.isNotEmpty)
          .toList();
      if (tokens.length < 2) {
        final sharedLastName = sharedLastNameFor(entry.key);
        return _normalizeSortText(
          sharedLastName == null
              ? normalizedName
              : '$sharedLastName $normalizedName',
        );
      }

      final lastName = tokens.last;
      final firstNames = tokens.take(tokens.length - 1).join(' ');
      return _normalizeSortText('$lastName $firstNames');
    });

    return nameKeys.join(' ');
  }

  String _displayAgeClassOnly(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    final lower = s.toLowerCase();
    if (lower.contains('senior')) return 'Senior';
    if (lower.contains('intermediate')) return 'Intermediate';
    if (lower.contains('junior')) return 'Junior';
    return s;
  }

  String _exhibitorNameFromEntry(Map<String, dynamic> entry) {
    final dn = _safe(entry, 'exhibitor_label');
    return dn.isEmpty ? '(Unknown Exhibitor)' : dn;
  }

  String _exhibitorFirstNameFromEntry(Map<String, dynamic> entry) {
    final firstName = _safe(entry, 'exhibitor_first_name');
    if (firstName.isNotEmpty) return firstName;
    return _safe(entry, 'first_name');
  }

  String _exhibitorLastNameFromEntry(Map<String, dynamic> entry) {
    final lastName = _safe(entry, 'exhibitor_last_name');
    if (lastName.isNotEmpty) return lastName;
    return _safe(entry, 'last_name');
  }

  String _exhibitorSortKey(Map<String, dynamic> entry) {
    final label = _exhibitorNameFromEntry(entry);
    final firstName = _exhibitorFirstNameFromEntry(entry);
    final lastName = _exhibitorLastNameFromEntry(entry);

    if (_sortExhibitorsByLastName && _hasMultiNameSeparator(label)) {
      return _displayNameSortKey(label, byLastName: true);
    }

    if (_sortExhibitorsByLastName && lastName.isNotEmpty) {
      return _normalizeSortText(
        [lastName, firstName, label].where((part) => part.isNotEmpty).join(' '),
      );
    }

    if (!_sortExhibitorsByLastName &&
        (firstName.isNotEmpty || lastName.isNotEmpty)) {
      return _normalizeSortText(
        [firstName, lastName, label].where((part) => part.isNotEmpty).join(' '),
      );
    }

    return _displayNameSortKey(label, byLastName: _sortExhibitorsByLastName);
  }

  int _compareExhibitors(Map<String, dynamic> a, Map<String, dynamic> b) {
    final keyCmp = _exhibitorSortKey(a).compareTo(_exhibitorSortKey(b));
    if (keyCmp != 0) return keyCmp;

    final labelCmp = _normalizeSortText(
      _exhibitorNameFromEntry(a),
    ).compareTo(_normalizeSortText(_exhibitorNameFromEntry(b)));
    if (labelCmp != 0) return labelCmp;

    return _exhibitorNumberFromEntry(a).compareTo(_exhibitorNumberFromEntry(b));
  }

  String _exhibitorNumberFromEntry(Map<String, dynamic> entry) {
    const keys = [
      'exhibitor_number',
      'show_exhibitor_number',
      'show_exhibitor_no',
      'exhibitor_no',
      'entry_exhibitor_number',
    ];

    for (final key in keys) {
      final value = _safe(entry, key);
      if (value.isNotEmpty) return value;
    }

    return '';
  }

  String _groupVarietyLabel(Map<String, dynamic> row) {
    final groupName = _safe(row, 'group_name');
    final variety = _safe(row, 'variety');

    if (groupName.isNotEmpty && variety.isNotEmpty) {
      return '$groupName / $variety';
    }
    if (groupName.isNotEmpty) return groupName;
    return variety;
  }

  Map<String, List<Map<String, dynamic>>> _groupByExhibitor(
    List<Map<String, dynamic>> entries,
  ) {
    final map = <String, List<Map<String, dynamic>>>{};

    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final exId = (e['exhibitor_id'] ?? '').toString().trim();
      final exhibitorLabel = _safe(e, 'exhibitor_label').toLowerCase();
      final exhibitorEmail = _safe(e, 'exhibitor_email').toLowerCase();
      final exhibitorPhone = _safe(e, 'exhibitor_phone').toLowerCase();

      // Prefer the database exhibitor_id. If it is ever missing, fall back to
      // a stable exhibitor-specific key instead of grouping all unknowns together.
      final key = exId.isNotEmpty
          ? exId
          : [
              exhibitorLabel.isEmpty ? 'unknown_exhibitor' : exhibitorLabel,
              exhibitorEmail,
              exhibitorPhone,
              i.toString(),
            ].join('|');

      map.putIfAbsent(key, () => <Map<String, dynamic>>[]);
      map[key]!.add(e);
    }

    for (final k in map.keys) {
      map[k]!.sort((a, b) {
        int toInt(dynamic value, [int fallback = 9999]) {
          if (value == null) return fallback;
          if (value is int) return value;
          return int.tryParse(value.toString()) ?? fallback;
        }

        int kindRank(String k) {
          switch (k.toLowerCase()) {
            case 'open':
              return widget.youthFirst ? 1 : 0;
            case 'youth':
              return widget.youthFirst ? 0 : 1;
            default:
              return 99;
          }
        }

        final sectionKindCmp = kindRank(
          _safe(a, 'section_kind'),
        ).compareTo(kindRank(_safe(b, 'section_kind')));
        if (sectionKindCmp != 0) return sectionKindCmp;

        final sectionSortCmp = toInt(
          a['section_sort_order'],
        ).compareTo(toInt(b['section_sort_order']));
        if (sectionSortCmp != 0) return sectionSortCmp;

        final sectionLetterCmp = _safe(
          a,
          'section_letter',
        ).toUpperCase().compareTo(_safe(b, 'section_letter').toUpperCase());
        if (sectionLetterCmp != 0) return sectionLetterCmp;

        final breedSortCmp = toInt(
          a['breed_sort_order'],
        ).compareTo(toInt(b['breed_sort_order']));
        if (breedSortCmp != 0) return breedSortCmp;

        final breedCmp = _safe(
          a,
          'breed',
        ).toLowerCase().compareTo(_safe(b, 'breed').toLowerCase());
        if (breedCmp != 0) return breedCmp;

        final groupSortCmp = toInt(
          a['group_sort_order'],
        ).compareTo(toInt(b['group_sort_order']));
        if (groupSortCmp != 0) return groupSortCmp;

        final varietySortCmp = toInt(
          a['variety_sort_order'],
        ).compareTo(toInt(b['variety_sort_order']));
        if (varietySortCmp != 0) return varietySortCmp;

        final varietyCmp = _groupVarietyLabel(
          a,
        ).toLowerCase().compareTo(_groupVarietyLabel(b).toLowerCase());
        if (varietyCmp != 0) return varietyCmp;

        final classSortCmp = toInt(
          a['class_sort_order'],
        ).compareTo(toInt(b['class_sort_order']));
        if (classSortCmp != 0) return classSortCmp;

        final sexCmp = _safe(
          a,
          'sex',
        ).toLowerCase().compareTo(_safe(b, 'sex').toLowerCase());
        if (sexCmp != 0) return sexCmp;

        return _safe(
          a,
          'tattoo',
        ).toLowerCase().compareTo(_safe(b, 'tattoo').toLowerCase());
      });
    }

    return map;
  }

  bool _isMultiSection(List<Map<String, dynamic>> exEntries) {
    final set = <String>{};
    for (final e in exEntries) {
      set.add((e['section_id'] ?? '').toString());
    }
    return set.length > 1;
  }

  Map<String, List<Map<String, dynamic>>> _groupEntriesBySection(
    List<Map<String, dynamic>> exEntries,
  ) {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final e in exEntries) {
      final sid = (e['section_id'] ?? '').toString();
      map.putIfAbsent(sid, () => <Map<String, dynamic>>[]);
      map[sid]!.add(e);
    }
    return map;
  }

  List<Map<String, dynamic>> _sortedSectionsForExhibitor(
    List<Map<String, dynamic>> exEntries,
  ) {
    final map = <String, Map<String, dynamic>>{};
    for (final e in exEntries) {
      final sid = (e['section_id'] ?? '').toString();
      map[sid] = {
        'id': sid,
        'display_name': _safe(e, 'section_display_name'),
        'kind': (e['section_kind'] ?? '').toString(),
        'letter': (e['section_letter'] ?? '').toString(),
        'sort_order': e['section_sort_order'],
      };
    }

    final list = map.values.toList();

    list.sort((a, b) {
      int kindRank(String k) {
        switch (k) {
          case 'open':
            return widget.youthFirst ? 1 : 0;
          case 'youth':
            return widget.youthFirst ? 0 : 1;
          default:
            return 99;
        }
      }

      final ak = (a['kind'] ?? '').toString().toLowerCase();
      final bk = (b['kind'] ?? '').toString().toLowerCase();

      final kr = kindRank(ak).compareTo(kindRank(bk));
      if (kr != 0) return kr;

      final aso = a['sort_order'];
      final bso = b['sort_order'];
      final asoI = (aso is int)
          ? aso
          : int.tryParse(aso?.toString() ?? '') ?? 9999;
      final bsoI = (bso is int)
          ? bso
          : int.tryParse(bso?.toString() ?? '') ?? 9999;
      final soCmp = asoI.compareTo(bsoI);
      if (soCmp != 0) return soCmp;

      final al = (a['letter'] ?? '').toString().toUpperCase();
      final bl = (b['letter'] ?? '').toString().toUpperCase();
      return al.compareTo(bl);
    });

    return list;
  }

  String _sectionHeader(Map<String, dynamic> s) {
    final dn = (s['display_name'] ?? '').toString().trim();
    if (dn.isNotEmpty) return dn;

    final kind = (s['kind'] ?? '').toString().toLowerCase();
    final letter = (s['letter'] ?? '').toString().toUpperCase();

    String kindLabel;
    switch (kind) {
      case 'open':
        kindLabel = 'Open';
        break;
      case 'youth':
        kindLabel = 'Youth';
        break;
      default:
        kindLabel = kind.isEmpty
            ? 'Section'
            : kind[0].toUpperCase() + kind.substring(1);
    }

    return letter.isEmpty ? kindLabel : '$kindLabel $letter';
  }

  pw.Document _buildPdf({
    required List<Map<String, dynamic>> entries,
    required pw.ThemeData theme,
  }) {
    final doc = pw.Document(theme: theme);

    final grouped = _groupByExhibitor(entries);
    final exhibitorKeys = grouped.keys.toList()
      ..sort((a, b) {
        final aList = grouped[a]!;
        final bList = grouped[b]!;
        if (aList.isEmpty && bList.isEmpty) return 0;
        if (aList.isEmpty) return -1;
        if (bList.isEmpty) return 1;
        return _compareExhibitors(aList.first, bList.first);
      });

    final totalPages = exhibitorKeys.length;

    pw.Widget grayBar({
      required String left,
      required String right,
      String? trailing,
    }) {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey300,
          borderRadius: pw.BorderRadius.circular(4),
          border: pw.Border.all(width: 0.8),
        ),
        child: pw.Row(
          children: [
            pw.Expanded(
              flex: 2,
              child: pw.Text(
                left,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Expanded(
              child: pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(right, style: pw.TextStyle(fontSize: 11)),
              ),
            ),
            if (trailing != null && trailing.trim().isNotEmpty) ...[
              pw.SizedBox(width: 18),
              pw.Text(
                trailing,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      );
    }

    // _balanceBox removed as per instructions.

    pw.Widget infoBlockLeft(Map<String, dynamic> ex) {
      final a1 = _safe(ex, 'exhibitor_address_line1');
      final a2 = _safe(ex, 'exhibitor_address_line2');
      final city = _safe(ex, 'exhibitor_city');
      final st = _safe(ex, 'exhibitor_state');
      final zip = _safe(ex, 'exhibitor_zip');
      final phone = _safe(ex, 'exhibitor_phone');
      final email = _safe(ex, 'exhibitor_email');

      final lines = <String>[
        if (a1.isNotEmpty) a1,
        if (a2.isNotEmpty) a2,
        if (city.isNotEmpty || st.isNotEmpty || zip.isNotEmpty)
          '${city.isEmpty ? '' : city}${city.isNotEmpty && st.isNotEmpty ? ', ' : ''}${st.isEmpty ? '' : st} ${zip.isEmpty ? '' : zip}'
              .trim(),
        if (phone.isNotEmpty) 'Phone: $phone',
        if (email.isNotEmpty) 'Email: $email',
      ];

      if (lines.isEmpty) {
        return pw.Text(
          '(No address/contact on file)',
          style: pw.TextStyle(fontSize: 9),
        );
      }

      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: lines
            .map((x) => pw.Text(x, style: pw.TextStyle(fontSize: 9)))
            .toList(),
      );
    }

    pw.Widget infoBlockRight() {
      String s2(Map<String, dynamic>? m, String k) =>
          (m == null) ? '' : (m[k] ?? '').toString().trim();

      final name = s2(_showRow, 'secretary_name');
      final phone = s2(_showRow, 'secretary_phone');
      final email = s2(_showRow, 'secretary_email');

      final lines = <pw.Widget>[
        pw.Text(
          'Show Secretary:',
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
      ];

      if (name.isNotEmpty) {
        lines.add(pw.Text(name, style: pw.TextStyle(fontSize: 9)));
      }
      if (phone.isNotEmpty) {
        lines.add(pw.Text('Phone: $phone', style: pw.TextStyle(fontSize: 9)));
      }
      if (email.isNotEmpty) {
        lines.add(pw.Text('Email: $email', style: pw.TextStyle(fontSize: 9)));
      }

      if (lines.length == 1) {
        lines.add(
          pw.Text('(Not set for this show)', style: pw.TextStyle(fontSize: 9)),
        );
      }

      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: lines,
      );
    }

    pw.Widget instructions() {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(top: 10),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              '»  If there are any problems with your entry as shown below please see the show secretary.',
              style: pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              '    No corrections or changes can be made at the judging table or after the show starts.',
              style: pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              '»  Fur column: X = entered in fur.',
              style: pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              '»  A ? in any column indicates the correct information is not known.',
              style: pw.TextStyle(fontSize: 9),
            ),
          ],
        ),
      );
    }

    pw.Widget entriesTable(List<Map<String, dynamic>> exEntries) {
      final h = pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold);
      final c = pw.TextStyle(fontSize: 10);

      return pw.Container(
        margin: const pw.EdgeInsets.only(top: 10),
        child: pw.Table(
          border: pw.TableBorder.all(width: 0.8),
          columnWidths: {
            0: const pw.FixedColumnWidth(60),
            1: const pw.FixedColumnWidth(60),
            2: const pw.FixedColumnWidth(110),
            3: const pw.FlexColumnWidth(1),
            4: const pw.FixedColumnWidth(70),
            5: const pw.FixedColumnWidth(50),
            6: const pw.FixedColumnWidth(40),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey300),
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text('Ear #', style: h),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text('Coop #', style: h),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text('Breed', style: h),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text('Group / Variety', style: h),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text('Class', style: h),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text('Sex', style: h),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text('Fur', style: h),
                ),
              ],
            ),
            ...exEntries.map((e) {
              final scratchedAt = _safe(e, 'scratched_at');
              final isScratched = scratchedAt.isNotEmpty;

              final style = isScratched
                  ? pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey700,
                      decoration: pw.TextDecoration.lineThrough,
                    )
                  : c;

              final ageClass = _displayAgeClassOnly(_safe(e, 'class_name'));
              final classNameLower = _safe(e, 'class_name').toLowerCase();
              final furMark =
                  _truthy(e['is_fur']) ||
                      classNameLower.contains('fur') ||
                      classNameLower.contains('wool')
                  ? 'X'
                  : '';

              return pw.TableRow(
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text(_safe(e, 'tattoo'), style: style),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text(_safe(e, 'coop_number'), style: style),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text(_safe(e, 'breed'), style: style),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text(_groupVarietyLabel(e), style: style),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text(ageClass, style: style),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text(_safe(e, 'sex'), style: style),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text(furMark, style: style),
                  ),
                ],
              );
            }),
          ],
        ),
      );
    }

    for (var i = 0; i < exhibitorKeys.length; i++) {
      final exKey = exhibitorKeys[i];
      final exEntries = grouped[exKey]!;
      if (exEntries.isEmpty) continue;

      final exMap = exEntries.first;
      final exName = _exhibitorNameFromEntry(exMap);
      final exhibitorNumber = _exhibitorNumberFromEntry(exMap);
      final exhibitorLabel = exhibitorNumber.isEmpty
          ? exName
          : '$exName    Exhibitor #: $exhibitorNumber';
      final numberEntered = exEntries.length;
      final balanceDue = _checkInBalanceDue(exEntries);
      final multi = _isMultiSection(exEntries);

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.letter,
          margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 28),
          build: (_) {
            final widgets = <pw.Widget>[];

            widgets.add(
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      children: [
                        pw.Text(
                          widget.showName,
                          style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          widget.sectionLabel,
                          style: pw.TextStyle(fontSize: 12),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Exhibitor Check-In Sheet',
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.Text(
                    'Page ${i + 1} of $totalPages',
                    style: pw.TextStyle(fontSize: 10),
                  ),
                ],
              ),
            );

            widgets.add(pw.SizedBox(height: 8));
            widgets.add(
              grayBar(
                left: exhibitorLabel,
                right: 'Number Entered  $numberEntered',
                trailing: 'Balance Due: $balanceDue',
              ),
            );

            widgets.add(pw.SizedBox(height: 6));
            widgets.add(
              pw.Row(
                children: [
                  pw.Text(
                    '${multi ? '[X]' : '[ ]'} Entered in multiple shows',
                    style: pw.TextStyle(fontSize: 10),
                  ),
                ],
              ),
            );

            widgets.add(pw.SizedBox(height: 8));
            widgets.add(
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(child: infoBlockLeft(exMap)),
                  pw.SizedBox(width: 24),
                  pw.Container(width: 190, child: infoBlockRight()),
                ],
              ),
            );

            widgets.add(instructions());

            if (widget.combineSections) {
              final bySection = _groupEntriesBySection(exEntries);
              final sList = _sortedSectionsForExhibitor(exEntries);

              for (final s in sList) {
                final sid = (s['id'] ?? '').toString();
                final blockEntries =
                    bySection[sid] ?? const <Map<String, dynamic>>[];
                if (blockEntries.isEmpty) continue;

                widgets.add(pw.SizedBox(height: 10));
                widgets.add(
                  pw.Text(
                    _sectionHeader(s),
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                );
                widgets.add(pw.SizedBox(height: 4));
                widgets.add(entriesTable(blockEntries));
              }
            } else {
              widgets.add(entriesTable(exEntries));
            }

            widgets.add(pw.SizedBox(height: 12));
            widgets.add(
              pw.Row(
                children: [
                  pw.Text(
                    'RingMaster One Show',
                    style: pw.TextStyle(fontSize: 9),
                  ),
                  pw.Spacer(),
                  pw.Text(
                    '${DateTime.now().toLocal()}',
                    style: pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            );

            return widgets;
          },
        ),
      );
    }

    return doc;
  }

  Future<void> _generatePdf() async {
    if (_building) return;

    setState(() {
      _building = true;
      _msg = null;
    });

    try {
      await _loadShowContact();

      final entries = await _fetchEntries();

      if (entries.isEmpty) {
        if (!mounted) return;
        setState(() {
          _building = false;
          _msg = 'No entries found for this selection.';
        });
        return;
      }

      final theme = await buildPrintPackPdfTheme();
      final doc = _buildPdf(entries: entries, theme: theme);
      final bytes = await doc.save();

      final name = widget.combineSections
          ? 'check_in_${widget.showName}_ALL_SECTIONS.pdf'
          : 'check_in_${widget.showName}_${widget.sectionLabel}.pdf';

      final savedPath = await savePdfToUserChosenLocation(
        bytes: Uint8List.fromList(bytes),
        suggestedName: name,
      );

      if (!mounted) return;
      setState(() {
        _building = false;
        _msg = savedPath == null
            ? 'Save canceled.'
            : 'PDF saved to: $savedPath';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _building = false;
        _msg = 'PDF build failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isEmailComplete = _msg != null && _msg!.startsWith('Email complete');
    final isFullEmailSuccess =
        isEmailComplete && _msg!.contains('Skipped with no email: 0.');

    final isSuccess =
        _msg != null &&
        (_msg == 'Save canceled.' ||
            _msg!.startsWith('PDF saved to:') ||
            isFullEmailSuccess);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: bottomInset + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Generate Check-In Sheets',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              '${widget.showName} • ${widget.sectionLabel}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            Text(
              widget.includeScratched
                  ? 'Including scratched entries'
                  : 'Excluding scratched entries',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(
              widget.combineSections
                  ? 'Mode: Combined (one sheet per exhibitor)'
                  : 'Mode: Single section',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Sort exhibitors by:',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: false,
                      label: Text('First name'),
                      icon: Icon(Icons.sort_by_alpha),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      label: Text('Last name'),
                      icon: Icon(Icons.badge_outlined),
                    ),
                  ],
                  selected: {_sortExhibitorsByLastName},
                  onSelectionChanged: (_building || _emailing)
                      ? null
                      : (values) {
                          setState(() {
                            _sortExhibitorsByLastName = values.first;
                          });
                        },
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_msg != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSuccess
                      ? Colors.green.withValues(alpha: .08)
                      : Colors.red.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSuccess
                        ? Colors.green.withValues(alpha: .25)
                        : Colors.red.withValues(alpha: .25),
                  ),
                ),
                child: Text(
                  _msg!,
                  style: TextStyle(
                    color: isSuccess ? Colors.green.shade700 : Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD4A623),
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: (_building || _emailing) ? null : _generatePdf,
              icon: const Icon(Icons.picture_as_pdf),
              label: Text(_building ? 'Building PDF…' : 'Generate PDF'),
            ),

            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF11285A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: (_building || _emailing) ? null : _emailCheckInSheets,
              icon: const Icon(Icons.email_outlined),
              label: Text(_emailing ? 'Emailing…' : 'Email Check-In Sheets'),
            ),

            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: (_building || _emailing)
                  ? null
                  : () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
