// lib/screens/admin/admin_print_packs_screen.dart

import 'dart:typed_data';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<pw.ThemeData> _buildPdfTheme() async {
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
  );
  final italic = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSans-Italic.ttf'),
  );
  final boldItalic = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSans-BoldItalic.ttf'),
  );

  return pw.ThemeData.withFont(
    base: regular,
    bold: bold,
    italic: italic,
    boldItalic: boldItalic,
  );
}

final supabase = Supabase.instance.client;

const String kQrResultsEntryBaseUrl =
    'https://show.ringmasterone.com/#/qr-results-entry';

Future<String?> _savePdfToUserChosenLocation({
  required Uint8List bytes,
  required String suggestedName,
}) async {
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'PDF',
        extensions: ['pdf'],
      ),
    ],
  );

  if (location == null) return null;

  final file = XFile.fromData(
    bytes,
    mimeType: 'application/pdf',
    name: suggestedName,
  );

  await file.saveTo(location.path);
  return location.path;
}

class AdminPrintPacksScreen extends StatefulWidget {
  final String showId;
  final String showName;

  const AdminPrintPacksScreen({
    super.key,
    required this.showId,
    required this.showName,
  });

  @override
  State<AdminPrintPacksScreen> createState() => _AdminPrintPacksScreenState();
}

class _AdminPrintPacksScreenState extends State<AdminPrintPacksScreen> {
  bool _loading = true;
  String? _msg;

  List<Map<String, dynamic>> _sections = [];
  String? _selectedSectionId;

  bool _includeScratched = false;
  bool _combineSections = true;

  @override
  void initState() {
    super.initState();
    _loadSections();
  }

  Future<void> _loadSections() async {
    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      final rows = await supabase
          .from('show_sections')
          .select('id,letter,display_name,kind,is_enabled,sort_order')
          .eq('show_id', widget.showId)
          .eq('is_enabled', true);

      _sections = (rows as List).cast<Map<String, dynamic>>();

      _sections.sort((a, b) {
        int kindRank(String k) {
          switch (k) {
            case 'open':
              return 0;
            case 'youth':
              return 1;
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
        final asoI =
            (aso is int) ? aso : int.tryParse(aso?.toString() ?? '') ?? 9999;
        final bsoI =
            (bso is int) ? bso : int.tryParse(bso?.toString() ?? '') ?? 9999;
        final soCmp = asoI.compareTo(bsoI);
        if (soCmp != 0) return soCmp;

        final al = (a['letter'] ?? '').toString().toUpperCase();
        final bl = (b['letter'] ?? '').toString().toUpperCase();
        return al.compareTo(bl);
      });

      if (_sections.isNotEmpty) {
        final currentStillExists = _sections.any(
          (s) => s['id']?.toString() == _selectedSectionId,
        );

        if (!currentStillExists) {
          _selectedSectionId = _sections.first['id']?.toString();
        }
      } else {
        _selectedSectionId = null;
      }

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _msg = 'Failed to load sections: $e';
      });
    }
  }

  String _sectionLabel(Map<String, dynamic> s) {
    final dn = (s['display_name'] ?? '').toString().trim();
    if (dn.isNotEmpty) return dn;

    final kind = (s['kind'] ?? '').toString().toLowerCase();
    final letter = (s['letter'] ?? '').toString().trim().toUpperCase();

    String kindLabel;
    switch (kind) {
      case 'open':
        kindLabel = 'Open';
        break;
      case 'youth':
        kindLabel = 'Youth';
        break;
      default:
        kindLabel = 'Section';
    }

    if (letter.isNotEmpty) return '$kindLabel $letter';
    return kindLabel;
  }

  Map<String, dynamic>? _selectedSection() {
    if (_selectedSectionId == null || _selectedSectionId!.isEmpty) return null;
    for (final s in _sections) {
      if (s['id']?.toString() == _selectedSectionId) return s;
    }
    return null;
  }

  void _openRemarkCardsGenerator() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _themedBottomSheetShell(
        context,
        child: _RemarkCardsGeneratorSheet(
          showId: widget.showId,
          showName: widget.showName,
          sections: _sections,
          includeScratched: _includeScratched,
        ),
      ),
    );
  }

  void _openCheckInGenerator() {
    if (!_combineSections &&
        (_selectedSectionId == null || _selectedSectionId!.isEmpty)) {
      setState(() {
        _msg = 'Please select a section for check-in sheets.';
      });
      return;
    }

    final section = _selectedSection();
    final sectionName = _combineSections
        ? 'All Shows (Open/Youth A/B/...)'
        : (section == null ? '' : _sectionLabel(section));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _themedBottomSheetShell(
        context,
        child: _CheckInGeneratorSheet(
          showId: widget.showId,
          showName: widget.showName,
          sections: _sections,
          sectionId: _combineSections ? null : _selectedSectionId,
          sectionLabel: sectionName,
          includeScratched: _includeScratched,
          combineSections: _combineSections,
        ),
      ),
    );
  }

  void _openControlSheetsGeneratorForSection(Map<String, dynamic> section) {
    final sectionId = section['id']?.toString();
    final sectionName = _sectionLabel(section);

    if (sectionId == null || sectionId.isEmpty) {
      setState(() {
        _msg = 'That section is missing an ID.';
      });
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _themedBottomSheetShell(
        context,
        child: _ControlSheetsGeneratorSheet(
          showId: widget.showId,
          showName: widget.showName,
          sections: _sections,
          sectionId: sectionId,
          sectionLabel: sectionName,
          includeScratched: _includeScratched,
          combineSections: false,
        ),
      ),
    );
  }

  Widget _messageBanner() {
    if (_msg == null) return const SizedBox.shrink();

    final isSuccess = !_msg!.toLowerCase().contains('failed') &&
        !_msg!.toLowerCase().contains('missing') &&
        !_msg!.toLowerCase().contains('please');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSuccess
              ? Colors.green.withOpacity(.08)
              : Colors.red.withOpacity(.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSuccess
                ? Colors.green.withOpacity(.25)
                : Colors.red.withOpacity(.25),
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
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canOpenCheckIn = !_loading &&
        (_combineSections ||
            (_selectedSectionId != null && _selectedSectionId!.isNotEmpty));
    final hasSections = _sections.isNotEmpty;

    return RingMasterPageShell(
      title: 'RingMaster Show',
      subtitle: 'Print Packs — ${widget.showName}',
      showBackButton: true,
      showHomeButton: true,
      useScrollView: false,
      bodyPadding: EdgeInsets.zero,
      actions: [
        IconButton(
          tooltip: 'Reload sections',
          onPressed: _loading ? null : _loadSections,
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _messageBanner(),

                _buildSectionCard(
                  icon: Icons.description_outlined,
                  title: 'Control Sheets',
                  subtitle:
                      'Generate judge control sheets as PDF files. These are always built one section at a time.',
                  children: [
                    SwitchListTile(
                      value: _includeScratched,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (v) => setState(() => _includeScratched = v),
                      title: const Text('Include scratched entries'),
                    ),
                    const SizedBox(height: 8),
                    if (!hasSections)
                      const Text(
                        'No enabled show sections found.',
                        style: TextStyle(color: Colors.red),
                      )
                    else
                      ..._sections.map(
                        (section) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFD4A623),
                                foregroundColor: Colors.black87,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () =>
                                  _openControlSheetsGeneratorForSection(section),
                              icon: const Icon(Icons.download),
                              label: Text(
                                'Download Control Sheets — ${_sectionLabel(section)}',
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),

                _buildSectionCard(
                  icon: Icons.checklist_outlined,
                  title: 'Check-In Sheets',
                  subtitle: 'Generate exhibitor check-in sheets as PDF files.',
                  children: [
                    SwitchListTile(
                      value: _combineSections,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (v) {
                        setState(() {
                          _combineSections = v;
                          if (!v &&
                              (_selectedSectionId == null ||
                                  _selectedSectionId!.isEmpty) &&
                              _sections.isNotEmpty) {
                            _selectedSectionId = _sections.first['id']?.toString();
                          }
                        });
                      },
                      title: const Text('Combine sections'),
                      subtitle: const Text(
                        'One sheet per exhibitor across Open/Youth A/B/...',
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (!_combineSections) ...[
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: (_selectedSectionId != null &&
                                _sections.any((s) =>
                                    s['id']?.toString() == _selectedSectionId))
                            ? _selectedSectionId
                            : null,
                        hint: const Text('Select a section'),
                        decoration: const InputDecoration(
                          labelText: 'Show Letter / Section',
                          border: OutlineInputBorder(),
                        ),
                        items: _sections
                            .map(
                              (s) => DropdownMenuItem<String>(
                                value: s['id']?.toString(),
                                child: Text(_sectionLabel(s)),
                              ),
                            )
                            .toList(),
                        onChanged: _sections.isEmpty
                            ? null
                            : (v) => setState(() => _selectedSectionId = v),
                      ),
                      const SizedBox(height: 12),
                    ] else ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(.03),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Sections included: ${_sections.isEmpty ? '(none)' : _sections.map(_sectionLabel).join(', ')}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SwitchListTile(
                      value: _includeScratched,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (v) => setState(() => _includeScratched = v),
                      title: const Text('Include scratched entries'),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFD4A623),
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: canOpenCheckIn ? _openCheckInGenerator : null,
                        icon: const Icon(Icons.picture_as_pdf),
                        label: Text(
                          _combineSections
                              ? 'Generate Check-In Sheets (Combined)'
                              : 'Generate Check-In Sheets',
                        ),
                      ),
                    ),
                  ],
                ),

//                      _buildSectionCard(
//                        icon: Icons.sell_outlined,
//                        title: 'Coop Tags',
//                        subtitle: 'Optional feature coming next.',
//                        children: const [
//                          Text('Coop tag generation will be added here.'),
//                        ],
//                      ),
                      _buildSectionCard(
                        icon: Icons.rate_review_outlined,
                        title: 'Remark Cards - 🧪 IN DEVELOPMENT',
                        subtitle:
                            'Generate traditional rabbit show remark cards. Prints 2 cards per 8.5 x 11 sheet.',
                        children: [
                          SwitchListTile(
                            value: _includeScratched,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (v) => setState(() => _includeScratched = v),
                            title: const Text('Include scratched entries'),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFD4A623),
                                foregroundColor: Colors.black87,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: hasSections ? _openRemarkCardsGenerator : null,
                              icon: const Icon(Icons.picture_as_pdf),
                              label: const Text('Generate Remark Cards'),
                            ),
                          ),
                        ],
                      ),
                  ],
            ),
    );
  }
}

Widget _themedBottomSheetShell(BuildContext context, {required Widget child}) {
  return Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [
          Color(0xFF11285A),
          Color(0xFF0B1C43),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    child: SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        decoration: const BoxDecoration(
          color: Color(0xFFF4F6FB),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: child,
      ),
    ),
  );
}

// =======================================================
// CONTROL SHEETS GENERATOR
// =======================================================

class _ControlSheetsGeneratorSheet extends StatefulWidget {
  final String showId;
  final String showName;
  final List<Map<String, dynamic>> sections;
  final String? sectionId;
  final String sectionLabel;
  final bool includeScratched;
  final bool combineSections;

  const _ControlSheetsGeneratorSheet({
    required this.showId,
    required this.showName,
    required this.sections,
    required this.sectionId,
    required this.sectionLabel,
    required this.includeScratched,
    required this.combineSections,
  });

  @override
  State<_ControlSheetsGeneratorSheet> createState() =>
      _ControlSheetsGeneratorSheetState();
}

class _ControlSheetsGeneratorSheetState
    extends State<_ControlSheetsGeneratorSheet> {
  bool _building = false;
  String? _msg;

  String _qrResultsUrl({
    required String sectionId,
    required String breed,
  }) {
    final query = Uri(
      queryParameters: {
        'showId': widget.showId,
        if (sectionId.trim().isNotEmpty) 'sectionId': sectionId.trim(),
        if (breed.trim().isNotEmpty) 'breed': breed.trim(),
      },
    ).query;

    return '$kQrResultsEntryBaseUrl?$query';
  }

  String _safe(Map<String, dynamic> e, String k) =>
      (e[k] ?? '').toString().trim();

    int _toInt(dynamic value, [int fallback = 9999]) {
      if (value == null) return fallback;
      if (value is int) return value;
      return int.tryParse(value.toString()) ?? fallback;
    }

    String _cavySortKey(String breed, String variety) {
      return '${breed.trim().toLowerCase()}|${variety.trim().toLowerCase()}';
    }

    Future<Map<String, Map<String, int>>> _loadCavySopSortMap() async {
      final rows = await supabase
          .from('cavy_sop_variety_order')
          .select('breed_name, variety_name, breed_sort_order, variety_sort_order');

      final map = <String, Map<String, int>>{};

      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final breed = (row['breed_name'] ?? '').toString().trim();
        final variety = (row['variety_name'] ?? '').toString().trim();

        if (breed.isEmpty || variety.isEmpty) continue;

        map[_cavySortKey(breed, variety)] = {
          'breed': _toInt(row['breed_sort_order']),
          'variety': _toInt(row['variety_sort_order']),
        };
      }

      return map;
    }

    bool _isCavyRow(Map<String, dynamic> row) {
      return _safe(row, 'species').toLowerCase() == 'cavy';
    }

  String _ageOnly(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    final l = s.toLowerCase();

    if (l.contains('wool')) return 'Wool';
    if (l.contains('fur')) return 'Fur';

    if (l.contains('senior')) return 'Senior';
    if (l.contains('intermediate')) return 'Intermediate';
    if (l.contains('junior')) return 'Junior';
    return s;
  }

  bool _isFurOrWoolRow(Map<String, dynamic> row) {
    final className = _safe(row, 'class_name').toLowerCase();
    final groupName = _safe(row, 'group_name').toLowerCase();
    final variety = _safe(row, 'variety').toLowerCase();

    return className.contains('fur') ||
        className.contains('wool') ||
        groupName.contains('fur') ||
        groupName.contains('wool') ||
        variety.contains('fur') ||
        variety.contains('wool');
  }

  String _furWoolLabel(Map<String, dynamic> row) {
    final className = _safe(row, 'class_name').toLowerCase();
    final groupName = _safe(row, 'group_name').toLowerCase();
    final variety = _safe(row, 'variety').toLowerCase();

    if (className.contains('wool') ||
        groupName.contains('wool') ||
        variety.contains('wool')) {
      return 'Wool';
    }

    if (className.contains('fur') ||
        groupName.contains('fur') ||
        variety.contains('fur')) {
      return 'Fur';
    }

    return 'Fur/Wool';
  }

  int _classSortRankForPrint(String className) {
    final c = className.toLowerCase();
    if (c == 'senior') return 0;
    if (c == 'intermediate') return 1;
    if (c == 'junior') return 2;
    if (c == 'fur') return 1000;
    if (c == 'wool') return 1001;
    if (c == 'fur/wool') return 1002;
    return 99;
  }

  Future<List<Map<String, dynamic>>> _fetchEntries() async {
    final rows = await supabase.rpc(
      'report_control_sheet_entries',
      params: {
        'p_show_id': widget.showId,
        'p_section_id': widget.combineSections ? null : widget.sectionId,
        'p_include_scratched': widget.includeScratched,
      },
    );

    return (rows as List).cast<Map<String, dynamic>>();
  }

  String _sectionTitleFromRow(Map<String, dynamic> row) {
    final label = _safe(row, 'section_label');
    if (label.isNotEmpty) return label;

    final kind = _safe(row, 'section_kind').toLowerCase();
    final letter = _safe(row, 'section_letter').toUpperCase();

    String kindLabel;
    switch (kind) {
      case 'open':
        kindLabel = 'Open';
        break;
      case 'youth':
        kindLabel = 'Youth';
        break;
      default:
        kindLabel = 'Section';
    }

    return letter.isEmpty ? kindLabel : '$kindLabel $letter';
  }

  String _colorLabel(Map<String, dynamic> row) {
    final groupName = _safe(row, 'group_name');
    final variety = _safe(row, 'variety');

    if (groupName.isNotEmpty && variety.isNotEmpty) {
      return '$groupName / $variety';
    }
    if (groupName.isNotEmpty) return groupName;
    return variety;
  }

  List<String> _specialsForRow(Map<String, dynamic> row) {
    if (_isFurOrWoolRow(row)) {
      return const <String>[];
    }

    final usesGroupAwards = row['uses_group_awards'] == true;
    final usesVarietyAwards = row['uses_variety_awards'] == true;

    final out = <String>[];

    if (usesVarietyAwards) {
      out.addAll([
        'BOV',
        'BOSV',
      ]);
    }

    if (usesGroupAwards) {
      out.addAll([
        'BOG',
        'BOSG',
      ]);
    }

    out.addAll([
      'BOB',
      'BOS',
    ]);

    return out;
  }

    pw.Document _buildPdf(
      List<Map<String, dynamic>> rows,
      pw.ThemeData theme, {
      required bool includeQrCode,
      required Map<String, Map<String, int>> cavySopSortMap,
    }) {
      final doc = pw.Document(theme: theme);

      final bySection = <String, List<Map<String, dynamic>>>{};
      for (final row in rows) {
        final sid = _safe(row, 'section_id');
        bySection.putIfAbsent(sid, () => <Map<String, dynamic>>[]);
        bySection[sid]!.add(row);
      }

      final sectionRows = widget.combineSections
          ? bySection.entries.toList()
          : <MapEntry<String, List<Map<String, dynamic>>>>[
              MapEntry(widget.sectionId ?? '', rows),
            ];

      final allPages = <Map<String, dynamic>>[];

      for (final sectionEntry in sectionRows) {
        final sectionEntries = sectionEntry.value;
        if (sectionEntries.isEmpty) continue;

        final grouped = <String, List<Map<String, dynamic>>>{};

        for (final row in sectionEntries) {
          final breed = _safe(row, 'breed');

          final isFurOrWool = _isFurOrWoolRow(row);

          final color = isFurOrWool ? '' : _colorLabel(row);
          final cls = isFurOrWool
              ? _furWoolLabel(row)
              : _ageOnly(_safe(row, 'class_name'));
          final sex = isFurOrWool ? '' : _safe(row, 'sex');

          final key = [
            breed.toLowerCase(),
            color.toLowerCase(),
            cls.toLowerCase(),
            sex.toLowerCase(),
          ].join('|');

          grouped.putIfAbsent(key, () => <Map<String, dynamic>>[]);
          grouped[key]!.add(row);
        }

        final keys = grouped.keys.toList()
          ..sort((a, b) {
            final aRows = grouped[a] ?? const <Map<String, dynamic>>[];
            final bRows = grouped[b] ?? const <Map<String, dynamic>>[];

            final aFirst = aRows.isEmpty ? <String, dynamic>{} : aRows.first;
            final bFirst = bRows.isEmpty ? <String, dynamic>{} : bRows.first;

            final aIsCavy = _isCavyRow(aFirst);
            final bIsCavy = _isCavyRow(bFirst);

            if (aIsCavy != bIsCavy) {
              return aIsCavy ? 1 : -1;
            }

            if (aIsCavy && bIsCavy) {
              final aBreed = _safe(aFirst, 'breed');
              final bBreed = _safe(bFirst, 'breed');
              final aVariety = _safe(aFirst, 'variety');
              final bVariety = _safe(bFirst, 'variety');

              final aMap = cavySopSortMap[_cavySortKey(aBreed, aVariety)];
              final bMap = cavySopSortMap[_cavySortKey(bBreed, bVariety)];

              final aBreedSort = aIsCavy ? (aMap?['breed'] ?? 9999) : 9999;
              final bBreedSort = bIsCavy ? (bMap?['breed'] ?? 9999) : 9999;

              final breedSortCmp = aBreedSort.compareTo(bBreedSort);
              if (breedSortCmp != 0) return breedSortCmp;

              final aVarietySort = aIsCavy ? (aMap?['variety'] ?? 9999) : 9999;
              final bVarietySort = bIsCavy ? (bMap?['variety'] ?? 9999) : 9999;

              final varietySortCmp = aVarietySort.compareTo(bVarietySort);
              if (varietySortCmp != 0) return varietySortCmp;
            }

            final aParts = a.split('|');
            final bParts = b.split('|');

            final aBreed = aParts.isNotEmpty ? aParts[0] : '';
            final bBreed = bParts.isNotEmpty ? bParts[0] : '';
            final breedCmp = aBreed.compareTo(bBreed);
            if (breedCmp != 0) return breedCmp;

            final aColor = aParts.length > 1 ? aParts[1] : '';
            final bColor = bParts.length > 1 ? bParts[1] : '';

            final aClass = aParts.length > 2 ? aParts[2] : '';
            final bClass = bParts.length > 2 ? bParts[2] : '';

            final aSex = aParts.length > 3 ? aParts[3] : '';
            final bSex = bParts.length > 3 ? bParts[3] : '';

            final aIsFurOrWool = _classSortRankForPrint(aClass) >= 1000;
            final bIsFurOrWool = _classSortRankForPrint(bClass) >= 1000;

            if (aIsFurOrWool != bIsFurOrWool) {
              return aIsFurOrWool ? 1 : -1;
            }

            if (!aIsFurOrWool && !bIsFurOrWool) {
              final colorCmp = aColor.compareTo(bColor);
              if (colorCmp != 0) return colorCmp;

              final classCmp = _classSortRankForPrint(aClass)
                  .compareTo(_classSortRankForPrint(bClass));
              if (classCmp != 0) return classCmp;

              return aSex.compareTo(bSex);
            }

            final furClassCmp = _classSortRankForPrint(aClass)
                .compareTo(_classSortRankForPrint(bClass));
            if (furClassCmp != 0) return furClassCmp;

            return aColor.compareTo(bColor);
          });

        for (final key in keys) {
          final groupRows = grouped[key]!;
          if (groupRows.isEmpty) continue;

          final first = groupRows.first;
          final exhibitorIds = <String>{};

          for (final row in groupRows) {
            final exId = _safe(row, 'exhibitor_id');
            if (exId.isNotEmpty) exhibitorIds.add(exId);
          }

          final isFurOrWool = _isFurOrWoolRow(first);

          allPages.add({
            'sectionId': _safe(first, 'section_id'),
            'sectionTitle': widget.combineSections
                ? _sectionTitleFromRow(first)
                : widget.sectionLabel,
            'breed': _safe(first, 'breed'),
            'color': isFurOrWool ? '' : _colorLabel(first),
            'class': isFurOrWool
                ? _furWoolLabel(first)
                : _ageOnly(_safe(first, 'class_name')),
            'sex': isFurOrWool ? '' : _safe(first, 'sex'),
            'rabbitCount': groupRows.length,
            'exhibitorCount': exhibitorIds.length,
            'rows': groupRows,
            'specials': _specialsForRow(first),
            'isFurOrWool': isFurOrWool,
          });
        }
      }

      final totalPages = allPages.length;

      pw.Widget _topHeader({
        required String showHeader,
        required String pageText,
      }) {
        final titleStyle =
            pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold);
        final pageStyle = pw.TextStyle(fontSize: 10);

        return pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                children: [
                  pw.Text(
                    showHeader,
                    style: titleStyle,
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'Judging Sheet - Breed Class',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 12, top: 2),
              child: pw.Text(pageText, style: pageStyle),
            ),
          ],
        );
      }

      pw.Widget _underlinedValue(String label, String value) {
        final textStyle =
            pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold);

        return pw.Row(
          mainAxisSize: pw.MainAxisSize.min,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('$label: ', style: textStyle),
            pw.Container(
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(width: 0.8),
                ),
              ),
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Text(value, style: textStyle),
            ),
          ],
        );
      }

      pw.Widget _classHeaderBlock({
        required String breed,
        required String color,
        required String cls,
        required String sex,
        required int rabbitCount,
        required int exhibitorCount,
      }) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _underlinedValue('Breed', breed),
                      pw.SizedBox(height: 10),
                      _underlinedValue('Color', color),
                    ],
                  ),
                ),
                pw.SizedBox(width: 18),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      children: [
                        _underlinedValue('Class', cls),
                        pw.SizedBox(width: 20),
                        _underlinedValue('Sex', sex),
                      ],
                    ),
                    pw.SizedBox(height: 10),
                    pw.Row(
                      children: [
                        _underlinedValue('No. in Class', rabbitCount.toString()),
                        pw.SizedBox(width: 20),
                        _underlinedValue(
                          'No. Exhibitors',
                          exhibitorCount.toString(),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
      }

      pw.Widget _judgingTable({
        required List<Map<String, dynamic>> groupEntries,
        required List<String> specialsList,
        required bool isFurOrWool,
      }) {
        final h = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
        final c = pw.TextStyle(fontSize: 9);
        final specialsText = specialsList.join(', ');

        if (isFurOrWool) {
          return pw.Table(
            border: pw.TableBorder.all(width: 0.8),
            columnWidths: {
              0: const pw.FixedColumnWidth(80),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FixedColumnWidth(150),
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
                    child: pw.Text('Exhibitor', style: h),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text('Place / DQ', style: h),
                  ),
                ],
              ),
              ...groupEntries.map((row) {
                return pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(_safe(row, 'tattoo'), style: c),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(_safe(row, 'exhibitor_label'), style: c),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('', style: c),
                    ),
                  ],
                );
              }),
            ],
          );
        }

        return pw.Table(
          border: pw.TableBorder.all(width: 0.8),
          columnWidths: {
            0: const pw.FixedColumnWidth(80),
            1: const pw.FlexColumnWidth(1),
            2: const pw.FixedColumnWidth(150),
            3: const pw.FixedColumnWidth(140),
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
                  child: pw.Text('Exhibitor', style: h),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text('Place / DQ', style: h),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text('Specials', style: h),
                ),
              ],
            ),
            ...groupEntries.map((row) {
              return pw.TableRow(
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text(_safe(row, 'tattoo'), style: c),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text(_safe(row, 'exhibitor_label'), style: c),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text('', style: c),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text(specialsText, style: c),
                  ),
                ],
              );
            }),
          ],
        );
      }

      pw.Widget qrResultsBlock({
        required String sectionId,
        required String breed,
      }) {
        final url = _qrResultsUrl(
          sectionId: sectionId,
          breed: breed,
        );

        return pw.Container(
          margin: const pw.EdgeInsets.only(top: 10, bottom: 10),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey500, width: 0.7),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: url,
                width: 62,
                height: 62,
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Text(
                  'Scan to enter results directly into RingMaster Show. Please also fill out control sheet in full',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      }

      for (var i = 0; i < allPages.length; i++) {
        final p = allPages[i];
        final isFurOrWool = p['isFurOrWool'] == true;

        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.letter,
            margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 28),
            theme: theme,
            build: (_) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  _topHeader(
                    showHeader:
                        '${widget.showName}   ${(p['sectionTitle'] ?? '').toString()}',
                    pageText: 'Page ${i + 1} of $totalPages',
                  ),
                  if (includeQrCode)
                    qrResultsBlock(
                      sectionId: (p['sectionId'] ?? '').toString(),
                      breed: (p['breed'] ?? '').toString(),
                    ),
                  pw.SizedBox(height: includeQrCode ? 8 : 18),
                  _classHeaderBlock(
                    breed: (p['breed'] ?? '').toString(),
                    color: (p['color'] ?? '').toString(),
                    cls: (p['class'] ?? '').toString(),
                    sex: (p['sex'] ?? '').toString(),
                    rabbitCount: (p['rabbitCount'] as int?) ?? 0,
                    exhibitorCount: (p['exhibitorCount'] as int?) ?? 0,
                  ),
                  if (isFurOrWool) ...[
                    pw.SizedBox(height: 6),
                    pw.Text(
                      'Fur/Wool Sheet — placements only',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                  pw.SizedBox(height: 14),
                  _judgingTable(
                    groupEntries:
                        (p['rows'] as List).cast<Map<String, dynamic>>(),
                    specialsList:
                        (p['specials'] as List).map((x) => x.toString()).toList(),
                    isFurOrWool: isFurOrWool,
                  ),
                ],
              );
            },
          ),
        );
      }
      return doc;
    }

  Future<void> _generatePdf({required bool includeQrCode}) async {
    if (_building) return;

    setState(() {
      _building = true;
      _msg = null;
    });

    try {
      final rows = await _fetchEntries();

      if (rows.isEmpty) {
        if (!mounted) return;
        setState(() {
          _building = false;
          _msg = 'No entries found for this selection.';
        });
        return;
      }

      final cavySopSortMap = await _loadCavySopSortMap();

      final theme = await _buildPdfTheme();
      final doc = _buildPdf(
        rows,
        theme,
        includeQrCode: includeQrCode,
        cavySopSortMap: cavySopSortMap,
      );
      final bytes = await doc.save();

      final name = widget.combineSections
          ? 'control_${widget.showName}_ALL_SECTIONS${includeQrCode ? '_QR' : ''}.pdf'
          : 'control_${widget.showName}_${widget.sectionLabel}${includeQrCode ? '_QR' : ''}.pdf';

      final savedPath = await _savePdfToUserChosenLocation(
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
    final isSuccess = _msg != null &&
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
              'Generate Control Sheets',
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
                  ? 'Mode: Combined (pages grouped by class)'
                  : 'Mode: Single section',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_msg != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSuccess
                      ? Colors.green.withOpacity(.08)
                      : Colors.red.withOpacity(.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSuccess
                        ? Colors.green.withOpacity(.25)
                        : Colors.red.withOpacity(.25),
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
              onPressed: _building ? null : () => _generatePdf(includeQrCode: false),
              icon: const Icon(Icons.picture_as_pdf),
              label: Text(_building ? 'Building PDF…' : 'Generate PDF'),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E0),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFD4A623)),
              ),
              child: const Text(
                'QR Code Option: adds a secure results-entry QR code to each judging sheet so writers can enter results directly into the system.',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B4E00),
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF11285A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _building ? null : () => _generatePdf(includeQrCode: true),
              icon: const Icon(Icons.qr_code_2),
              label: Text(
                _building ? 'Building PDF…' : 'Generate PDF with QR Code',
              ),
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

class _CheckInGeneratorSheet extends StatefulWidget {
  final String showId;
  final String showName;
  final List<Map<String, dynamic>> sections;
  final String? sectionId;
  final String sectionLabel;
  final bool includeScratched;
  final bool combineSections;

  const _CheckInGeneratorSheet({
    required this.showId,
    required this.showName,
    required this.sections,
    required this.sectionId,
    required this.sectionLabel,
    required this.includeScratched,
    required this.combineSections,
  });

  @override
  State<_CheckInGeneratorSheet> createState() =>
      _CheckInGeneratorSheetState();
}

class _CheckInGeneratorSheetState extends State<_CheckInGeneratorSheet> {
  bool _building = false;
  String? _msg;
  Map<String, dynamic>? _showRow;

  Future<void> _loadShowContact() async {
    final row = await supabase
        .from('shows')
        .select('id, secretary_name, secretary_phone, secretary_email')
        .eq('id', widget.showId)
        .single();

    _showRow = row as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> _fetchEntries() async {
    final rows = await supabase.rpc(
      'report_checkin_entries',
      params: {
        'p_show_id': widget.showId,
        'p_section_id': widget.combineSections ? null : widget.sectionId,
        'p_include_scratched': widget.includeScratched,
      },
    );

    return (rows as List).cast<Map<String, dynamic>>();
  }

  bool _emailing = false;

  String _money(dynamic value) {
    final n = value is num ? value : num.tryParse(value?.toString() ?? '');
    if (n == null) return r'$—';
    return '\$${n.toStringAsFixed(2)}';
  }
    
  String _emailForExhibitor(List<Map<String, dynamic>> entries) {
    for (final e in entries) {
      final email = _safe(e, 'email');
      if (email.isNotEmpty && email.contains('@')) return email;

      final exhibitorEmail = _safe(e, 'exhibitor_email');
      if (exhibitorEmail.isNotEmpty && exhibitorEmail.contains('@')) {
        return exhibitorEmail;
      }
    }
    return '';
  }

  String _safeFileName(String value) {
    return value
        .replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  Future<Uint8List> _buildPdfBytesForEntries(
    List<Map<String, dynamic>> entries,
  ) async {
    await _loadShowContact();

    final theme = await _buildPdfTheme();
    final doc = _buildPdf(
      entries: entries,
      theme: theme,
    );

    return Uint8List.fromList(await doc.save());
  }

  Future<void> _emailCheckInSheets() async {
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

        if (response.status < 200 || response.status >= 300) {
          throw Exception('Email failed for $exhibitorName: ${response.data}');
        }

        sent++;
      }

      if (!mounted) return;
      setState(() {
        _emailing = false;
        _msg = 'Email complete. Sent: $sent. Skipped with no email: $skipped.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _emailing = false;
        _msg = 'Email failed: $e';
      });
    }
  }

  String _safe(Map<String, dynamic> e, String k) =>
      (e[k] ?? '').toString().trim();

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
      List<Map<String, dynamic>> entries) {
    final map = <String, List<Map<String, dynamic>>>{};

    for (final e in entries) {
      final exId = (e['exhibitor_id'] ?? '').toString();
      final key = exId.isEmpty ? '_unknown' : exId;
      map.putIfAbsent(key, () => <Map<String, dynamic>>[]);
      map[key]!.add(e);
    }

    for (final k in map.keys) {
      map[k]!.sort((a, b) {
        final at = _safe(a, 'tattoo').toLowerCase();
        final bt = _safe(b, 'tattoo').toLowerCase();
        final c1 = at.compareTo(bt);
        if (c1 != 0) return c1;

        final breedCmp = _safe(a, 'breed')
            .toLowerCase()
            .compareTo(_safe(b, 'breed').toLowerCase());
        if (breedCmp != 0) return breedCmp;

        return _groupVarietyLabel(a)
            .toLowerCase()
            .compareTo(_groupVarietyLabel(b).toLowerCase());
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
      List<Map<String, dynamic>> exEntries) {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final e in exEntries) {
      final sid = (e['section_id'] ?? '').toString();
      map.putIfAbsent(sid, () => <Map<String, dynamic>>[]);
      map[sid]!.add(e);
    }
    return map;
  }

  List<Map<String, dynamic>> _sortedSectionsForExhibitor(
      List<Map<String, dynamic>> exEntries) {
    final map = <String, Map<String, dynamic>>{};
    for (final e in exEntries) {
      final sid = (e['section_id'] ?? '').toString();
      map[sid] = {
        'id': sid,
        'display_name': (e['section_label'] ?? '').toString(),
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
            return 0;
          case 'youth':
            return 1;
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
      final asoI =
          (aso is int) ? aso : int.tryParse(aso?.toString() ?? '') ?? 9999;
      final bsoI =
          (bso is int) ? bso : int.tryParse(bso?.toString() ?? '') ?? 9999;
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
        kindLabel =
            kind.isEmpty ? 'Section' : kind[0].toUpperCase() + kind.substring(1);
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
        final aName =
            aList.isEmpty ? '' : _exhibitorNameFromEntry(aList.first).toLowerCase();
        final bName =
            bList.isEmpty ? '' : _exhibitorNameFromEntry(bList.first).toLowerCase();
        return aName.compareTo(bName);
      });

    final totalPages = exhibitorKeys.length;

    pw.Widget _grayBar({required String left, required String right}) {
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
          ],
        ),
      );
    }

    pw.Widget _balanceBox({required String allShows, required String thisShow}) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'Balance Due',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                decoration: pw.TextDecoration.underline,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'All Shows: $allShows',
              style:
                  pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'This Show: $thisShow',
              style:
                  pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      );
    }

    pw.Widget _infoBlockLeft(Map<String, dynamic> ex) {
      final a1 = _safe(ex, 'address_line1');
      final a2 = _safe(ex, 'address_line2');
      final city = _safe(ex, 'city');
      final st = _safe(ex, 'state');
      final zip = _safe(ex, 'zip');
      final phone = _safe(ex, 'phone');
      final email = _safe(ex, 'email');

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
        children:
            lines.map((x) => pw.Text(x, style: pw.TextStyle(fontSize: 9))).toList(),
      );
    }

    pw.Widget _infoBlockRight() {
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
        lines.add(pw.Text(phone, style: pw.TextStyle(fontSize: 9)));
      }
      if (email.isNotEmpty) {
        lines.add(pw.Text(email, style: pw.TextStyle(fontSize: 9)));
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

    pw.Widget _instructions() {
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
              '»  Fur column: B = entered in breed fur, C = entered in commercial fur.',
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

    pw.Widget _entriesTable(List<Map<String, dynamic>> exEntries) {
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

              return pw.TableRow(
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text(_safe(e, 'tattoo'), style: style),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text('', style: style),
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
                    child: pw.Text('', style: style),
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
      final numberEntered = exEntries.length;
      final allShows = _money(exMap['balance_due_all_shows']);
      final thisShow = _money(exMap['balance_due_this_show']);
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
              pw.Row(
                children: [
                  pw.Spacer(),
                  _balanceBox(allShows: allShows, thisShow: thisShow),
                ],
              ),
            );

            widgets.add(pw.SizedBox(height: 8));
            widgets.add(
              _grayBar(
                left: exName,
                right: 'Number Entered  $numberEntered',
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
                  pw.Expanded(child: _infoBlockLeft(exMap)),
                  pw.SizedBox(width: 24),
                  pw.Container(width: 190, child: _infoBlockRight()),
                ],
              ),
            );

            widgets.add(_instructions());

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
                widgets.add(_entriesTable(blockEntries));
              }
            } else {
              widgets.add(_entriesTable(exEntries));
            }

            widgets.add(pw.SizedBox(height: 12));
            widgets.add(
              pw.Row(
                children: [
                  pw.Text(
                    'RingMaster Show',
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

      final theme = await _buildPdfTheme();
      final doc = _buildPdf(
        entries: entries,
        theme: theme,
      );
      final bytes = await doc.save();

      final name = widget.combineSections
          ? 'check_in_${widget.showName}_ALL_SECTIONS.pdf'
          : 'check_in_${widget.showName}_${widget.sectionLabel}.pdf';

      final savedPath = await _savePdfToUserChosenLocation(
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

    final isSuccess = _msg != null &&
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
            if (_msg != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSuccess
                      ? Colors.green.withOpacity(.08)
                      : Colors.red.withOpacity(.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSuccess
                        ? Colors.green.withOpacity(.25)
                        : Colors.red.withOpacity(.25),
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
              onPressed: _building ? null : _generatePdf,
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
              onPressed: (_building || _emailing) ? null : () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemarkCardsGeneratorSheet extends StatefulWidget {
  final String showId;
  final String showName;
  final List<Map<String, dynamic>> sections;
  final bool includeScratched;

  const _RemarkCardsGeneratorSheet({
    required this.showId,
    required this.showName,
    required this.sections,
    required this.includeScratched,
  });

  @override
  State<_RemarkCardsGeneratorSheet> createState() =>
      _RemarkCardsGeneratorSheetState();
}

class _RemarkCardsGeneratorSheetState extends State<_RemarkCardsGeneratorSheet> {
  bool _building = false;
  String? _msg;

  String? _selectedSectionId;
  bool _useCoopNumberInsteadOfName = false;

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

  String _displayClass(Map<String, dynamic> row) {
    final raw = _safe(row, 'class_name');
    final lower = raw.toLowerCase();

    if (lower.contains('pre')) return 'Pre Jr.';
    if (lower.contains('senior')) return 'Sr.';
    if (lower.contains('intermediate')) return '6/8';
    if (lower.contains('junior')) return 'Jr.';
    if (lower.contains('fryer')) return 'Fryer';
    if (lower.contains('meat')) return 'Meat Pen';
    if (lower.contains('fur')) return 'Fur';
    if (lower.contains('wool')) return 'Fur';

    return raw;
  }

  String _displaySex(Map<String, dynamic> row) {
    final sex = _safe(row, 'sex').toLowerCase();
    if (sex.startsWith('buck')) return 'Buck';
    if (sex.startsWith('doe')) return 'Doe';
    return _safe(row, 'sex');
  }

  String _exhibitorDisplay(Map<String, dynamic> row) {
    final coop = _safe(row, 'coop_number');
    final exhibitor = _safe(row, 'exhibitor_label');

    if (_useCoopNumberInsteadOfName) {
      return coop.isEmpty ? 'Coop No.' : 'Coop No. $coop';
    }

    return exhibitor;
  }

  Future<List<Map<String, dynamic>>> _fetchEntries() async {
    final rows = await supabase.rpc(
      'report_checkin_entries',
      params: {
        'p_show_id': widget.showId,
        'p_section_id': _selectedSectionId,
        'p_include_scratched': widget.includeScratched,
      },
    );

    final out = (rows as List).cast<Map<String, dynamic>>();

    out.sort((a, b) {
      int cmp(String ak, String bk) =>
          ak.toLowerCase().compareTo(bk.toLowerCase());

      final breedCmp = cmp(_safe(a, 'breed'), _safe(b, 'breed'));
      if (breedCmp != 0) return breedCmp;

      final varietyCmp = cmp(_groupVarietyLabel(a), _groupVarietyLabel(b));
      if (varietyCmp != 0) return varietyCmp;

      final classCmp = cmp(_safe(a, 'class_name'), _safe(b, 'class_name'));
      if (classCmp != 0) return classCmp;

      final coopCmp = cmp(_safe(a, 'coop_number'), _safe(b, 'coop_number'));
      if (coopCmp != 0) return coopCmp;

      return cmp(_safe(a, 'tattoo'), _safe(b, 'tattoo'));
    });

    return out;
  }

  pw.Widget _lineField({
    required String label,
    required String value,
    double labelSize = 8,
    double valueSize = 8,
    double height = 16,
    double? width,
  }) {
    return pw.Container(
      width: width,
      height: height,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: labelSize,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(width: 3),
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.only(left: 2, bottom: 2),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(width: .7),
                ),
              ),
              child: pw.Text(
                value,
                maxLines: 1,
                style: pw.TextStyle(fontSize: valueSize),
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _checkRow(List<String> labels, String selected) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: labels.map((label) {
        final isSelected = selected.toLowerCase() == label.toLowerCase();
        return pw.Text(
          isSelected ? '[$label]' : label,
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: isSelected ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        );
      }).toList(),
    );
  }

  pw.Widget _scoreGrid(List<String> rows, {bool fourCols = true}) {
    final headers = fourCols ? ['VG', 'G', 'F', 'P'] : ['VG', 'G', 'F'];

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 72,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(height: 12),
              ...rows.map(
                (r) => pw.Container(
                  height: 15,
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text(
                    r,
                    style: pw.TextStyle(
                      fontSize: 7.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        pw.Expanded(
          child: pw.Column(
            children: [
              pw.Row(
                children: headers
                    .map(
                      (h) => pw.Expanded(
                        child: pw.Center(
                          child: pw.Text(
                            h,
                            style: pw.TextStyle(
                              fontSize: 7,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              pw.Table(
                border: pw.TableBorder.all(width: .55),
                children: rows
                    .map(
                      (_) => pw.TableRow(
                        children: headers
                            .map(
                              (_) => pw.Container(height: 15),
                            )
                            .toList(),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _remarkCard(Map<String, dynamic> row) {
    final sex = _displaySex(row);
    final cls = _displayClass(row);

    final leftRows = [
      'Head',
      'Ears',
      'Crown',
      'Bone',
      'Type',
      'Shoulders',
      'Midsection',
      'Hindquarters',
      'Fur/Wool',
      'Sheen',
      'Density',
      'Texture',
      'Color',
    ];

    final rightRows = [
      'Condition',
      'Butterfly',
      'Eye Circles',
      'Cheek Spots',
      'Ear Base',
      'Side Markings',
      'Spine/Herringbone',
      'Blaze',
      'Cheeks',
      'Neck',
      'Saddle',
      'Undercut',
      'Stops',
    ];

    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(14, 10, 14, 8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: .8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            'RABBIT SHOW REMARK CARD',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Text(
            'American Rabbit Breeders Association, Inc.',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 10.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 7),

          pw.Row(
            children: [
              pw.Expanded(
                child: _lineField(label: 'Ear No.', value: _safe(row, 'tattoo')),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _lineField(
                  label: 'Coop No.',
                  value: _safe(row, 'coop_number'),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _lineField(
                  label: 'Entry No.',
                  value: _safe(row, 'entry_number'),
                ),
              ),
            ],
          ),

          _lineField(label: 'Exhibitor', value: _exhibitorDisplay(row)),
          _lineField(label: 'Address', value: _safe(row, 'address_line1')),

          pw.Row(
            children: [
              pw.Expanded(
                flex: 3,
                child: _lineField(label: 'Show', value: widget.showName),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                flex: 2,
                child: _lineField(label: 'Date', value: ''),
              ),
            ],
          ),

          pw.Row(
            children: [
              pw.Expanded(
                child: _lineField(label: 'Breed', value: _safe(row, 'breed')),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _lineField(
                  label: 'Variety',
                  value: _groupVarietyLabel(row),
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 5),
          _checkRow(
            ['Buck', 'Doe', 'Sr.', '6/8', 'Jr.', 'Pre Jr.', 'Fryer', 'Meat Pen', 'Fur'],
            sex.isNotEmpty ? sex : cls,
          ),
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 3, bottom: 5),
            height: .8,
            color: PdfColors.black,
          ),

          pw.Row(
            children: [
              pw.Expanded(
                child: _lineField(label: 'No. in Class', value: ''),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _lineField(label: 'Award', value: ''),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _lineField(label: 'No. Exhibitors', value: ''),
              ),
            ],
          ),

          pw.SizedBox(height: 4),
          _checkRow(['B.O.B.', 'B.O.S.', 'B.O.G.', 'B.O.S.G.', 'B.O.V.', 'B.O.S.V.'], ''),
          pw.SizedBox(height: 4),
          _checkRow(['Best Sr.', 'Best 6/8', 'Best Jr.', 'Best Pre-Jr.'], ''),

          pw.SizedBox(height: 4),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: _scoreGrid(leftRows, fourCols: true)),
              pw.SizedBox(width: 10),
              pw.Expanded(child: _scoreGrid(rightRows, fourCols: false)),
            ],
          ),

          pw.SizedBox(height: 5),
          _lineField(label: 'Remarks', value: '', height: 15),
          _lineField(label: '', value: '', height: 13),
          _lineField(label: 'Judge', value: '', height: 15),
        ],
      ),
    );
  }

  pw.Document _buildPdf({
    required List<Map<String, dynamic>> entries,
    required pw.ThemeData theme,
  }) {
    final doc = pw.Document(theme: theme);

    for (var i = 0; i < entries.length; i += 2) {
      final first = entries[i];
      final second = i + 1 < entries.length ? entries[i + 1] : null;

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.letter,
          margin: const pw.EdgeInsets.fromLTRB(20, 20, 20, 20),
          build: (_) {
            return pw.Column(
              children: [
                pw.Expanded(child: _remarkCard(first)),
                pw.SizedBox(height: 14),
                pw.Expanded(
                  child: second == null
                      ? pw.Container()
                      : _remarkCard(second),
                ),
              ],
            );
          },
        ),
      );
    }

    return doc;
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

      final theme = await _buildPdfTheme();
      final doc = _buildPdf(entries: entries, theme: theme);
      final bytes = await doc.save();

      final section = widget.sections.firstWhere(
        (s) => s['id']?.toString() == _selectedSectionId,
        orElse: () => <String, dynamic>{},
      );

      final sectionName =
          section.isEmpty ? 'SECTION' : _sectionLabel(section);

      final name = 'remark_cards_${widget.showName}_$sectionName.pdf';

      final savedPath = await _savePdfToUserChosenLocation(
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
    final isSuccess = _msg != null &&
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
              '${widget.showName} • 2 cards per letter-size sheet',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              isExpanded: true,
              value: (_selectedSectionId != null &&
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

            const SizedBox(height: 8),

            SwitchListTile(
              value: _useCoopNumberInsteadOfName,
              contentPadding: EdgeInsets.zero,
              onChanged: (v) =>
                  setState(() => _useCoopNumberInsteadOfName = v),
              title: const Text('Use coop numbers instead of exhibitor names'),
              subtitle: const Text(
                'Keeps exhibitor data saved, but hides names on printed cards.',
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
                      ? Colors.green.withOpacity(.08)
                      : Colors.red.withOpacity(.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSuccess
                        ? Colors.green.withOpacity(.25)
                        : Colors.red.withOpacity(.25),
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