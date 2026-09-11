// lib/screens/admin/print_packs/remark_cards_generator_sheet.dart

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'print_pack_pdf_helpers.dart';
import 'remark_cards_pdf.dart';

final supabase = Supabase.instance.client;

class RemarkCardsGeneratorSheet extends StatefulWidget {
  final String showId;
  final String showName;
  final List<Map<String, dynamic>> sections;
  final bool includeScratched;

  const RemarkCardsGeneratorSheet({
    super.key,
    required this.showId,
    required this.showName,
    required this.sections,
    required this.includeScratched,
  });

  @override
  State<RemarkCardsGeneratorSheet> createState() =>
      _RemarkCardsGeneratorSheetState();
}

class _RemarkCardsGeneratorSheetState extends State<RemarkCardsGeneratorSheet> {
  bool _building = false;
  String? _msg;

  String? _selectedSectionId;
  bool _useCoopNumberInsteadOfName = false;
  bool _includeRunnerCards = true;

  @override
  void initState() {
    super.initState();
    if (widget.sections.isNotEmpty) {
      _selectedSectionId = widget.sections.first['id']?.toString();
    }
  }

  String _safe(Map<String, dynamic> e, String k) =>
      (e[k] ?? '').toString().trim();

  String _sectionLabel(Map<String, dynamic> s) {
    final dn = (s['display_name'] ?? '').toString().trim();
    if (dn.isNotEmpty) return dn;

    final kind = (s['kind'] ?? '').toString().toLowerCase();
    final letter = (s['letter'] ?? '').toString().trim().toUpperCase();

    final kindLabel = switch (kind) {
      'open' => 'Open',
      'youth' => 'Youth',
      _ => 'Section',
    };

    return letter.isEmpty ? kindLabel : '$kindLabel $letter';
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

  String _entryNumber(Map<String, dynamic> row) {
    for (final key in const [
      'entry_number',
      'entry_no',
      'catalog_number',
      'show_entry_number',
      'entry_index',
      'exhibitor_number',
    ]) {
      final value = _safe(row, key);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  Future<String> _loadShowDateLabel() async {
    final row = await supabase
        .from('shows')
        .select('start_date,end_date')
        .eq('id', widget.showId)
        .maybeSingle();

    if (row == null) return '';
    return _dateRangeLabel(row['start_date'], row['end_date']);
  }

  String _dateRangeLabel(dynamic startValue, dynamic endValue) {
    final start = DateTime.tryParse(startValue?.toString() ?? '');
    final end = DateTime.tryParse(endValue?.toString() ?? '');

    if (start == null && end == null) return '';
    if (start != null && end == null) return _formatDate(start);
    if (start == null && end != null) return _formatDate(end);

    final startDate = start!;
    final endDate = end!;
    if (startDate.year == endDate.year &&
        startDate.month == endDate.month &&
        startDate.day == endDate.day) {
      return _formatDate(startDate);
    }

    return '${_formatDate(startDate)} - ${_formatDate(endDate)}';
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$month/$day/${date.year}';
  }

  Future<List<Map<String, dynamic>>> _fetchEntries() async {
    const pageSize = 1000;
    final out = <Map<String, dynamic>>[];

    for (var from = 0; ; from += pageSize) {
      final to = from + pageSize - 1;
      final rows = await supabase
          .rpc(
            'report_checkin_entries',
            params: {
              'p_show_id': widget.showId,
              'p_section_id': _selectedSectionId,
              'p_include_scratched': widget.includeScratched,
            },
          )
          .range(from, to);

      final page = (rows as List).cast<Map<String, dynamic>>();
      out.addAll(page);

      if (page.length < pageSize) break;
    }

    await _attachExhibitorNumbers(out);
    await _attachCoopNumbers(out);

    int toInt(dynamic value, [int fallback = 9999]) {
      if (value == null) return fallback;
      if (value is int) return value;
      return int.tryParse(value.toString()) ?? fallback;
    }

    int cmpText(String ak, String bk) =>
        ak.toLowerCase().compareTo(bk.toLowerCase());

    out.sort((a, b) {
      final sectionSortCmp = toInt(
        a['section_sort_order'],
      ).compareTo(toInt(b['section_sort_order']));
      if (sectionSortCmp != 0) return sectionSortCmp;

      final sectionLetterCmp = cmpText(
        _safe(a, 'section_letter'),
        _safe(b, 'section_letter'),
      );
      if (sectionLetterCmp != 0) return sectionLetterCmp;

      final breedSortCmp = toInt(
        a['breed_sort_order'],
      ).compareTo(toInt(b['breed_sort_order']));
      if (breedSortCmp != 0) return breedSortCmp;

      final breedCmp = cmpText(_safe(a, 'breed'), _safe(b, 'breed'));
      if (breedCmp != 0) return breedCmp;

      final groupSortCmp = toInt(
        a['group_sort_order'],
      ).compareTo(toInt(b['group_sort_order']));
      if (groupSortCmp != 0) return groupSortCmp;

      final varietySortCmp = toInt(
        a['variety_sort_order'],
      ).compareTo(toInt(b['variety_sort_order']));
      if (varietySortCmp != 0) return varietySortCmp;

      final varietyCmp = cmpText(_groupVarietyLabel(a), _groupVarietyLabel(b));
      if (varietyCmp != 0) return varietyCmp;

      final classSortCmp = toInt(
        a['class_sort_order'],
      ).compareTo(toInt(b['class_sort_order']));
      if (classSortCmp != 0) return classSortCmp;

      final classCmp = cmpText(_safe(a, 'class_name'), _safe(b, 'class_name'));
      if (classCmp != 0) return classCmp;

      final sexSortCmp = toInt(
        a['sex_sort_order'],
      ).compareTo(toInt(b['sex_sort_order']));
      if (sexSortCmp != 0) return sexSortCmp;

      final sexCmp = cmpText(_safe(a, 'sex'), _safe(b, 'sex'));
      if (sexCmp != 0) return sexCmp;

      final coopCmp = cmpText(_safe(a, 'coop_number'), _safe(b, 'coop_number'));
      if (coopCmp != 0) return coopCmp;

      return cmpText(_safe(a, 'tattoo'), _safe(b, 'tattoo'));
    });

    for (var i = 0; i < out.length; i++) {
      if (_entryNumber(out[i]).isEmpty) {
        out[i]['entry_number'] = '${i + 1}';
      }
    }

    return out;
  }

  Future<void> _attachExhibitorNumbers(
    List<Map<String, dynamic>> entries,
  ) async {
    final exhibitorIds = entries
        .map((entry) => _safe(entry, 'exhibitor_id'))
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final exhibitorNumberById = <String, String>{};
    const exhibitorPageSize = 500;

    for (var i = 0; i < exhibitorIds.length; i += exhibitorPageSize) {
      final chunk = exhibitorIds.skip(i).take(exhibitorPageSize).toList();
      if (chunk.isEmpty) continue;

      final rows = await supabase
          .from('exhibitors')
          .select('id, exhibitor_number')
          .inFilter('id', chunk);

      for (final raw in (rows as List).cast<Map<String, dynamic>>()) {
        final exhibitorId = _safe(raw, 'id');
        final exhibitorNumber = _safe(raw, 'exhibitor_number');
        if (exhibitorId.isNotEmpty && exhibitorNumber.isNotEmpty) {
          exhibitorNumberById[exhibitorId] = exhibitorNumber;
        }
      }
    }

    for (final entry in entries) {
      final exhibitorId = _safe(entry, 'exhibitor_id');
      final exhibitorNumber = exhibitorNumberById[exhibitorId];
      if (exhibitorNumber != null && exhibitorNumber.isNotEmpty) {
        entry['exhibitor_number'] = exhibitorNumber;
      }
    }
  }

  Future<void> _attachCoopNumbers(List<Map<String, dynamic>> entries) async {
    final entryIds = entries
        .map((entry) {
          final entryId = _safe(entry, 'entry_id');
          if (entryId.isNotEmpty) return entryId;
          return _safe(entry, 'id');
        })
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final animalIdByEntryId = <String, String>{};
    const entryPageSize = 500;

    for (var i = 0; i < entryIds.length; i += entryPageSize) {
      final chunk = entryIds.skip(i).take(entryPageSize).toList();
      if (chunk.isEmpty) continue;

      final rows = await supabase
          .from('entries')
          .select('id, animal_id')
          .inFilter('id', chunk);

      for (final raw in (rows as List).cast<Map<String, dynamic>>()) {
        final entryId = _safe(raw, 'id');
        final animalId = _safe(raw, 'animal_id');
        if (entryId.isNotEmpty && animalId.isNotEmpty) {
          animalIdByEntryId[entryId] = animalId;
        }
      }
    }

    for (final entry in entries) {
      final entryId = _safe(entry, 'entry_id').isNotEmpty
          ? _safe(entry, 'entry_id')
          : _safe(entry, 'id');
      entry['animal_id'] =
          animalIdByEntryId[entryId] ?? _safe(entry, 'animal_id');
    }

    final showModeRow = await supabase
        .from('shows')
        .select('coop_numbering_mode')
        .eq('id', widget.showId)
        .maybeSingle();

    final coopNumberingMode =
        (showModeRow?['coop_numbering_mode'] ?? 'separate')
            .toString()
            .trim()
            .toLowerCase();

    final animalIds = entries
        .map((entry) => _safe(entry, 'animal_id'))
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final coopNumberByAnimalAndScope = <String, String>{};
    const coopPageSize = 500;

    for (var i = 0; i < animalIds.length; i += coopPageSize) {
      final chunk = animalIds.skip(i).take(coopPageSize).toList();
      if (chunk.isEmpty) continue;

      final rows = await supabase
          .from('show_animal_coop_numbers')
          .select('animal_id, scope, coop_number')
          .eq('show_id', widget.showId)
          .inFilter('animal_id', chunk);

      for (final raw in (rows as List).cast<Map<String, dynamic>>()) {
        final animalId = _safe(raw, 'animal_id');
        final scope = _safe(raw, 'scope').toLowerCase();
        final coopNumber = _safe(raw, 'coop_number');
        if (animalId.isEmpty || scope.isEmpty) continue;
        coopNumberByAnimalAndScope['$animalId|$scope'] = coopNumber;
      }
    }

    for (final entry in entries) {
      final animalId = _safe(entry, 'animal_id');
      final sectionKind = _safe(entry, 'section_kind').toLowerCase();
      final scope = coopNumberingMode == 'combined' ? 'all' : sectionKind;

      entry['coop_number'] = animalId.isEmpty || scope.isEmpty
          ? ''
          : (coopNumberByAnimalAndScope['$animalId|$scope'] ?? '');
    }
  }

  Future<void> _generatePdf() async {
    if (_building) return;

    if (_selectedSectionId == null || _selectedSectionId!.isEmpty) {
      setState(() => _msg = 'Please select a section.');
      return;
    }

    setState(() {
      _building = true;
      _msg = null;
    });

    try {
      final entries = await _fetchEntries();

      if (entries.isEmpty) {
        if (!mounted) return;
        setState(() {
          _building = false;
          _msg = 'No entries found for this section.';
        });
        return;
      }

      final showDateLabel = await _loadShowDateLabel();
      final theme = await buildPrintPackPdfTheme();
      final doc = RemarkCardsPdfBuilder(
        showName: widget.showName,
        includeRunnerCards: _includeRunnerCards,
        useCoopNumberInsteadOfName: _useCoopNumberInsteadOfName,
      ).build(entries: entries, theme: theme, showDateLabel: showDateLabel);
      final bytes = await doc.save();

      final section = widget.sections.firstWhere(
        (s) => s['id']?.toString() == _selectedSectionId,
        orElse: () => <String, dynamic>{},
      );

      final sectionName = section.isEmpty ? 'SECTION' : _sectionLabel(section);

      final name = 'remark_cards_${widget.showName}_$sectionName.pdf';

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
        _msg = 'Remark card PDF failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isSuccess =
        _msg != null &&
        (_msg == 'Save canceled.' || _msg!.startsWith('PDF saved to:'));

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
              'Generate Remark Cards',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              '${widget.showName} • 2 vertical cards per landscape sheet',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),

            AppTheme.surfaceTextScope(
              context,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue:
                    (_selectedSectionId != null &&
                        widget.sections.any(
                          (s) => s['id']?.toString() == _selectedSectionId,
                        ))
                    ? _selectedSectionId
                    : null,
                hint: const Text('Select a section'),
                decoration: const InputDecoration(
                  labelText: 'Show Letter / Section',
                  border: OutlineInputBorder(),
                ),
                items: widget.sections
                    .map(
                      (s) => DropdownMenuItem<String>(
                        value: s['id']?.toString(),
                        child: Text(_sectionLabel(s)),
                      ),
                    )
                    .toList(),
                onChanged: widget.sections.isEmpty
                    ? null
                    : (v) => setState(() => _selectedSectionId = v),
              ),
            ),

            const SizedBox(height: 8),

            SwitchListTile(
              value: _useCoopNumberInsteadOfName,
              contentPadding: EdgeInsets.zero,
              onChanged: (v) => setState(() => _useCoopNumberInsteadOfName = v),
              title: const Text('Use coop numbers instead of exhibitor names'),
              subtitle: const Text(
                'Keeps exhibitor data saved, but hides names on printed cards.',
              ),
            ),

            SwitchListTile(
              value: _includeRunnerCards,
              contentPadding: EdgeInsets.zero,
              onChanged: (v) => setState(() => _includeRunnerCards = v),
              title: const Text('Include detachable runner cards'),
              subtitle: const Text(
                'Adds a small tear-off card below the judge line.',
              ),
            ),

            const SizedBox(height: 6),

            Text(
              widget.includeScratched
                  ? 'Including scratched entries'
                  : 'Excluding scratched entries',
              style: Theme.of(context).textTheme.bodySmall,
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
                backgroundColor: AppColors.primaryButton,
                foregroundColor: AppColors.primaryButtonText,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _building ? null : _generatePdf,
              icon: const Icon(Icons.picture_as_pdf),
              label: Text(_building ? 'Building PDF…' : 'Generate PDF'),
            ),

            const SizedBox(height: 8),

            OutlinedButton(
              onPressed: _building ? null : () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
