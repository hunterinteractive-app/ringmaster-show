// lib/screens/admin/admin_print_packs_screen.dart

import 'dart:typed_data';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';
import 'package:ringmaster_show/services/app_session.dart';

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
  bool _pairOpenYouthByLetter = false;
  bool _youthFirst = false;
  bool _autoEmailCheckInSheets = false;
  bool _savingAutoEmailCheckInSheets = false;
  DateTime? _entryCloseAt;
  DateTime? _checkInSheetsAutoEmailedAt;
  String? _checkInSheetsAutoEmailError;

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
      final showRow = await supabase
          .from('shows')
          .select(
            'id, entry_close_at, auto_email_checkin_sheets, checkin_sheets_auto_emailed_at, checkin_sheets_auto_email_error',
          )
          .eq('id', widget.showId)
          .maybeSingle();

      final rows = await supabase
          .from('show_sections')
          .select('id,letter,display_name,kind,is_enabled,sort_order')
          .eq('show_id', widget.showId)
          .eq('is_enabled', true);

      final show = (showRow as Map<String, dynamic>?) ?? <String, dynamic>{};
      final rawEntryCloseAt = (show['entry_close_at'] ?? '').toString();
      final rawAutoEmailedAt =
          (show['checkin_sheets_auto_emailed_at'] ?? '').toString();

      _entryCloseAt = rawEntryCloseAt.isEmpty
          ? null
          : DateTime.tryParse(rawEntryCloseAt)?.toLocal();
      _autoEmailCheckInSheets = show['auto_email_checkin_sheets'] == true;
      _checkInSheetsAutoEmailedAt = rawAutoEmailedAt.isEmpty
          ? null
          : DateTime.tryParse(rawAutoEmailedAt)?.toLocal();
      _checkInSheetsAutoEmailError =
          (show['checkin_sheets_auto_email_error'] ?? '').toString().trim();
      if (_checkInSheetsAutoEmailError != null &&
          _checkInSheetsAutoEmailError!.isEmpty) {
        _checkInSheetsAutoEmailError = null;
      }

      _sections = (rows as List).cast<Map<String, dynamic>>();
      _sortSections();

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
  void _sortSections() {
    _sections.sort((a, b) {
      int kindRank(String k) {
        switch (k.toLowerCase()) {
          case 'open':
            return _youthFirst ? 1 : 0;
          case 'youth':
            return _youthFirst ? 0 : 1;
          default:
            return 99;
        }
      }

      int toInt(dynamic value) {
        if (value is int) return value;
        return int.tryParse(value?.toString() ?? '') ?? 9999;
      }

      final ak = (a['kind'] ?? '').toString().toLowerCase();
      final bk = (b['kind'] ?? '').toString().toLowerCase();
      final al = (a['letter'] ?? '').toString().trim().toUpperCase();
      final bl = (b['letter'] ?? '').toString().trim().toUpperCase();
      final asoI = toInt(a['sort_order']);
      final bsoI = toInt(b['sort_order']);

      if (_pairOpenYouthByLetter) {
        final sortCmp = asoI.compareTo(bsoI);
        if (sortCmp != 0) return sortCmp;

        final letterCmp = al.compareTo(bl);
        if (letterCmp != 0) return letterCmp;

        final kindCmp = kindRank(ak).compareTo(kindRank(bk));
        if (kindCmp != 0) return kindCmp;
      } else {
        final kindCmp = kindRank(ak).compareTo(kindRank(bk));
        if (kindCmp != 0) return kindCmp;

        final sortCmp = asoI.compareTo(bsoI);
        if (sortCmp != 0) return sortCmp;

        final letterCmp = al.compareTo(bl);
        if (letterCmp != 0) return letterCmp;
      }

      return _sectionLabel(a).compareTo(_sectionLabel(b));
    });
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

  Future<void> _setAutoEmailCheckInSheets(bool value) async {
    if (_savingAutoEmailCheckInSheets) return;

    if (value && _entryCloseAt == null) {
      setState(() {
        _msg = 'Set an entry deadline before enabling automatic check-in sheet emails.';
      });
      return;
    }

    setState(() {
      _savingAutoEmailCheckInSheets = true;
      _msg = null;
    });

    try {
      await supabase.from('shows').update({
        'auto_email_checkin_sheets': value,
        if (value) 'checkin_sheets_auto_email_error': null,
      }).eq('id', widget.showId);

      if (!mounted) return;
      setState(() {
        _autoEmailCheckInSheets = value;
        if (value) _checkInSheetsAutoEmailError = null;
        _savingAutoEmailCheckInSheets = false;
        _msg = value
            ? 'Automatic check-in sheet emails enabled.'
            : 'Automatic check-in sheet emails disabled.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingAutoEmailCheckInSheets = false;
        _msg = 'Failed to update automatic check-in sheet email setting: $e';
      });
    }
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
          pairOpenYouthByLetter: _pairOpenYouthByLetter,
          youthFirst: _youthFirst,
        ),
      ),
    );
  }

  void _openControlSheetsGeneratorForSection(Map<String, dynamic> section) {
    _openControlSheetsGeneratorForSections(
      sections: [section],
      sectionLabel: _sectionLabel(section),
    );
  }

  void _openControlSheetsGeneratorForSections({
    required List<Map<String, dynamic>> sections,
    required String sectionLabel,
  }) {
    final sectionIds = sections
        .map((s) => s['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();

    if (sectionIds.isEmpty) {
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
          sectionIds: sectionIds,
          sectionId: sectionIds.first,
          sectionLabel: sectionLabel,
          includeScratched: _includeScratched,
          // One generated PDF can include both Open and Youth, but the PDF
          // content still keeps Open and Youth as separate sheet sections.
          combineSections: sectionIds.length > 1,
          youthFirst: _youthFirst,
        ),
      ),
    );
  }

  List<List<Map<String, dynamic>>> _controlSheetButtonGroups() {
    if (!_pairOpenYouthByLetter) {
      return _sections.map((s) => [s]).toList();
    }

    final byLetter = <String, List<Map<String, dynamic>>>{};
    for (final section in _sections) {
      final letter = (section['letter'] ?? '').toString().trim().toUpperCase();
      final key = letter.isEmpty ? _sectionLabel(section) : letter;
      byLetter.putIfAbsent(key, () => <Map<String, dynamic>>[]);
      byLetter[key]!.add(section);
    }

    return byLetter.values.toList();
  }

  String _controlSheetButtonLabel(List<Map<String, dynamic>> sections) {
    if (sections.isEmpty) return 'Section';
    if (sections.length == 1) return _sectionLabel(sections.first);

    final letter = (sections.first['letter'] ?? '').toString().trim().toUpperCase();
    if (letter.isNotEmpty) return 'Show $letter';

    return sections.map(_sectionLabel).join(' / ');
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
      subtitle: 'Print Show Sheets — ${widget.showName}',
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
                  icon: Icons.sort_outlined,
                  title: 'Print Order',
                  subtitle:
                      'Choose whether Control Sheets list Open or Youth first and how they are printed.',
                  children: [
                    SwitchListTile(
                      value: _pairOpenYouthByLetter,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (v) {
                        setState(() {
                          _pairOpenYouthByLetter = v;
                          _sortSections();
                        });
                      },
                      title: const Text('Pair Open/Youth by show letter'),
                      subtitle: Text(
                        _pairOpenYouthByLetter
                            ? (_youthFirst
                                ? 'Print order: Youth A, Open A, Youth B, Open B…'
                                : 'Print order: Open A, Youth A, Open B, Youth B…')
                            : (_youthFirst
                                ? 'Print order: all Youth sections, then all Open sections.'
                                : 'Print order: all Open sections, then all Youth sections.'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment<bool>(
                          value: false,
                          label: Text('Open first'),
                          icon: Icon(Icons.workspace_premium_outlined),
                        ),
                        ButtonSegment<bool>(
                          value: true,
                          label: Text('Youth first'),
                          icon: Icon(Icons.school_outlined),
                        ),
                      ],
                      selected: {_youthFirst},
                      onSelectionChanged: (values) {
                        setState(() {
                          _youthFirst = values.first;
                          _sortSections();
                        });
                      },
                    ),
                  ],
                ),

                _buildSectionCard(
                  icon: Icons.description_outlined,
                  title: 'Control Sheets',
                  subtitle:
                      'Generate judge control sheets as PDF files. Paired Open/Youth sections save as one PDF, but print as separate Open and Youth sheets inside it.',
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
                      ..._controlSheetButtonGroups().map(
                        (sectionGroup) => Padding(
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
                              onPressed: () => _openControlSheetsGeneratorForSections(
                                sections: sectionGroup,
                                sectionLabel: _controlSheetButtonLabel(sectionGroup),
                              ),
                              icon: const Icon(Icons.download),
                              label: Text(
                                'Download Control Sheets — ${_controlSheetButtonLabel(sectionGroup)}',
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
                      value: _autoEmailCheckInSheets,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (_savingAutoEmailCheckInSheets ||
                              _entryCloseAt == null ||
                              _checkInSheetsAutoEmailedAt != null)
                          ? null
                          : _setAutoEmailCheckInSheets,
                      title: const Text(
                        'Automatically email check-in sheets when entries close',
                      ),
                      subtitle: Text(
                        _checkInSheetsAutoEmailedAt != null
                            ? 'Already emailed on ${_checkInSheetsAutoEmailedAt!.toLocal()}'
                            : _entryCloseAt == null
                                ? 'Set an entry deadline before enabling this.'
                                : 'Entry deadline: ${_entryCloseAt!.toLocal()}',
                      ),
                    ),
                    if (_checkInSheetsAutoEmailError != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Last automatic email error: $_checkInSheetsAutoEmailError',
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
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
  final List<String> sectionIds;
  final String sectionLabel;
  final bool includeScratched;
  final bool combineSections;
  final bool youthFirst;

  const _ControlSheetsGeneratorSheet({
    required this.showId,
    required this.showName,
    required this.sections,
    required this.sectionId,
    required this.sectionIds,
    required this.sectionLabel,
    required this.includeScratched,
    required this.combineSections,
    required this.youthFirst,
  });

  @override
  State<_ControlSheetsGeneratorSheet> createState() =>
      _ControlSheetsGeneratorSheetState();
}

class _ControlSheetsGeneratorSheetState
    extends State<_ControlSheetsGeneratorSheet> {
  bool _building = false;
  String? _msg;

  double _fontScale = 1.0;

  double _scaled(double base, {double max = 16}) {
    final value = base * _fontScale;
    return value > max ? max : value;
  }

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

  String _animalPrintLabel(Map<String, dynamic> row) {
    final name = _safe(row, 'animal_name');
    final tattoo = _safe(row, 'tattoo').toUpperCase();

    // Rabbits should print ear/tattoo only. Cavies may include the animal
    // name because duplicate ear tags are more common there.
    if (!_isCavyRow(row)) return tattoo;

    if (name.isNotEmpty && name.toUpperCase() != tattoo) {
      return '$name • $tattoo';
    }

    if (name.isNotEmpty) return name;
    return tattoo;
  }

  String _safe(Map<String, dynamic> e, String k) =>
      (e[k] ?? '').toString().trim();

    int _toInt(dynamic value, [int fallback = 9999]) {
      if (value == null) return fallback;
      if (value is int) return value;
      return int.tryParse(value.toString()) ?? fallback;
    }

    int _sortValue(Map<String, dynamic> row, String key) {
      return _toInt(row[key], 9999);
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
    final raw = <Map<String, dynamic>>[];
    final idsToFetch = widget.sectionIds.isNotEmpty
        ? widget.sectionIds
        : [if ((widget.sectionId ?? '').isNotEmpty) widget.sectionId!];

    int kindRankForSectionId(String sectionId) {
      final section = widget.sections.firstWhere(
        (s) => (s['id'] ?? '').toString() == sectionId,
        orElse: () => const <String, dynamic>{},
      );

      final kind = (section['kind'] ?? '').toString().toLowerCase();
      switch (kind) {
        case 'open':
          return widget.youthFirst ? 1 : 0;
        case 'youth':
          return widget.youthFirst ? 0 : 1;
        default:
          return 99;
      }
    }

    int sortOrderForSectionId(String sectionId) {
      final section = widget.sections.firstWhere(
        (s) => (s['id'] ?? '').toString() == sectionId,
        orElse: () => const <String, dynamic>{},
      );
      final value = section['sort_order'];
      if (value is int) return value;
      return int.tryParse(value?.toString() ?? '') ?? 9999;
    }

    String letterForSectionId(String sectionId) {
      final section = widget.sections.firstWhere(
        (s) => (s['id'] ?? '').toString() == sectionId,
        orElse: () => const <String, dynamic>{},
      );
      return (section['letter'] ?? '').toString().trim().toUpperCase();
    }

    final sortedIdsToFetch = [...idsToFetch]
      ..sort((a, b) {
        final sortCmp = sortOrderForSectionId(a).compareTo(sortOrderForSectionId(b));
        if (sortCmp != 0) return sortCmp;

        final letterCmp = letterForSectionId(a).compareTo(letterForSectionId(b));
        if (letterCmp != 0) return letterCmp;

        final kindCmp = kindRankForSectionId(a).compareTo(kindRankForSectionId(b));
        if (kindCmp != 0) return kindCmp;

        return a.compareTo(b);
      });

    for (final sectionId in sortedIdsToFetch) {
      final rows = await supabase.rpc(
        'report_control_sheet_entries',
        params: {
          'p_show_id': widget.showId,
          'p_section_id': sectionId,
          'p_include_scratched': widget.includeScratched,
        },
      );
      raw.addAll((rows as List).cast<Map<String, dynamic>>());
    }

    final byEntryId = <String, Map<String, dynamic>>{};

    for (final row in raw) {
      final entryId = _safe(row, 'entry_id').isNotEmpty
          ? _safe(row, 'entry_id')
          : _safe(row, 'id');

      if (entryId.isEmpty) {
        byEntryId['fallback_${byEntryId.length}'] = row;
        continue;
      }

      byEntryId.putIfAbsent(entryId, () => row);
    }

    return byEntryId.values.toList();
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

  bool _supportsBestAgeAwards(String breedName) {
    final b = breedName.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return b == 'american sable' ||
        b == 'american sables' ||
        b == 'himalayan' ||
        b == 'checkered giant';
  }

  String _ageSpecialForRow(Map<String, dynamic> row) {
    if (_isFurOrWoolRow(row)) return '';

    final cls = _ageOnly(_safe(row, 'class_name')).toLowerCase();
    final isCavy = _isCavyRow(row);
    final breed = _safe(row, 'breed');

    final needsAgeSpecials = isCavy || _supportsBestAgeAwards(breed);
    if (!needsAgeSpecials) return '';

    if (cls == 'senior') return 'Best Sr';
    if (cls == 'intermediate') return 'Best Int';
    if (cls == 'junior') return 'Best Jr';

    return '';
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
              final groupSortCmp = _sortValue(aFirst, 'group_sort_order')
                  .compareTo(_sortValue(bFirst, 'group_sort_order'));
              if (groupSortCmp != 0) return groupSortCmp;

              final varietySortCmp = _sortValue(aFirst, 'variety_sort_order')
                  .compareTo(_sortValue(bFirst, 'variety_sort_order'));
              if (varietySortCmp != 0) return varietySortCmp;

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
            'sectionKind': _safe(first, 'section_kind').toLowerCase(),
            'sectionLetter': _safe(first, 'section_letter').toUpperCase(),
            'sectionSortOrder': _toInt(first['section_sort_order']),
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
            'ageSpecial': _ageSpecialForRow(first),
            'isFurOrWool': isFurOrWool,
            'groupSortOrder': _sortValue(first, 'group_sort_order'),
            'varietySortOrder': _sortValue(first, 'variety_sort_order'),
            'classSortRank': _classSortRankForPrint(
              isFurOrWool
                  ? _furWoolLabel(first)
                  : _ageOnly(_safe(first, 'class_name')),
            ),
          });
        }
      }

      // BEGIN REPLACEMENT BLOCK
      String sectionKindForPage(Map<String, dynamic> page) {
        final rawKind = (page['sectionKind'] ?? '').toString().trim().toLowerCase();
        if (rawKind == 'open' || rawKind == 'youth') return rawKind;

        final title = (page['sectionTitle'] ?? '').toString().trim().toLowerCase();
        if (title.startsWith('open') || title.contains(' open ')) return 'open';
        if (title.startsWith('youth') || title.contains(' youth ')) return 'youth';

        return rawKind;
      }

      int sectionKindRank(Map<String, dynamic> page) {
        final kind = sectionKindForPage(page);
        switch (kind) {
          case 'open':
            return widget.youthFirst ? 1 : 0;
          case 'youth':
            return widget.youthFirst ? 0 : 1;
          default:
            return 99;
        }
      }

      String sectionLetterForPage(Map<String, dynamic> page) {
        final rawLetter = (page['sectionLetter'] ?? '').toString().trim().toUpperCase();
        if (rawLetter.isNotEmpty) return rawLetter;

        final title = (page['sectionTitle'] ?? '').toString().trim().toUpperCase();
        final match = RegExp(r'\b([A-Z])$').firstMatch(title);
        return match?.group(1) ?? '';
      }

      int pageInt(Map<String, dynamic> page, String key) {
        final value = page[key];
        if (value is int) return value;
        return int.tryParse(value?.toString() ?? '') ?? 9999;
      }

      int compareControlPages(Map<String, dynamic> a, Map<String, dynamic> b) {
        if (widget.combineSections) {
          // Paired control sheets should be ordered by breed, then by section.
          // This keeps Open A American Fuzzy Lop together, then Youth A
          // American Fuzzy Lop together, instead of splitting the same breed
          // into repeated Open/Youth runs by class or sex.
          final breedCmp = (a['breed'] ?? '')
              .toString()
              .toLowerCase()
              .compareTo((b['breed'] ?? '').toString().toLowerCase());
          if (breedCmp != 0) return breedCmp;

          final kindCmp = sectionKindRank(a).compareTo(sectionKindRank(b));
          if (kindCmp != 0) return kindCmp;

          final sectionSortCmp = pageInt(a, 'sectionSortOrder')
              .compareTo(pageInt(b, 'sectionSortOrder'));
          if (sectionSortCmp != 0) return sectionSortCmp;

          final sectionLetterCmp = sectionLetterForPage(a).compareTo(sectionLetterForPage(b));
          if (sectionLetterCmp != 0) return sectionLetterCmp;

          final titleCmp = (a['sectionTitle'] ?? '')
              .toString()
              .compareTo((b['sectionTitle'] ?? '').toString());
          if (titleCmp != 0) return titleCmp;
          // Stop further sorting so paired control sheets stay grouped by breed.
          return 0;
        } else {
          final kindCmp = sectionKindRank(a).compareTo(sectionKindRank(b));
          if (kindCmp != 0) return kindCmp;

          final sectionSortCmp = pageInt(a, 'sectionSortOrder').compareTo(pageInt(b, 'sectionSortOrder'));
          if (sectionSortCmp != 0) return sectionSortCmp;

          final sectionLetterCmp = sectionLetterForPage(a).compareTo(sectionLetterForPage(b));
          if (sectionLetterCmp != 0) return sectionLetterCmp;

          final breedCmp = (a['breed'] ?? '')
              .toString()
              .toLowerCase()
              .compareTo((b['breed'] ?? '').toString().toLowerCase());
          if (breedCmp != 0) return breedCmp;
        }

        // Only use the fallback sorting when not combining sections
        if (!widget.combineSections) {
          final groupCmp = pageInt(a, 'groupSortOrder').compareTo(pageInt(b, 'groupSortOrder'));
          if (groupCmp != 0) return groupCmp;

          final varietyCmp = pageInt(a, 'varietySortOrder').compareTo(pageInt(b, 'varietySortOrder'));
          if (varietyCmp != 0) return varietyCmp;

          final colorCmp = (a['color'] ?? '')
              .toString()
              .toLowerCase()
              .compareTo((b['color'] ?? '').toString().toLowerCase());
          if (colorCmp != 0) return colorCmp;

          final classCmp = pageInt(a, 'classSortRank').compareTo(pageInt(b, 'classSortRank'));
          if (classCmp != 0) return classCmp;

          final sexCmp = (a['sex'] ?? '').toString().toLowerCase().compareTo(
                (b['sex'] ?? '').toString().toLowerCase(),
              );
          if (sexCmp != 0) return sexCmp;

          return (a['sectionTitle'] ?? '').toString().compareTo((b['sectionTitle'] ?? '').toString());
        }

        return 0;
      }

      final sortedAllPages = [...allPages]..sort(compareControlPages);

      final sortedSectionGroups = <MapEntry<String, List<Map<String, dynamic>>>>[];

      if (widget.combineSections) {
        // Keep Open and Youth as separate sheet sections inside the same PDF,
        // while preserving the sorted Open/Youth-by-breed flow. Repeated section
        // titles are allowed here because each run gets its own PDF header.
        String? currentTitle;
        List<Map<String, dynamic>> currentPages = <Map<String, dynamic>>[];

        void flushCurrentRun() {
          if (currentTitle == null || currentPages.isEmpty) return;
          sortedSectionGroups.add(MapEntry(currentTitle!, currentPages));
          currentPages = <Map<String, dynamic>>[];
        }

        for (final p in sortedAllPages) {
          final sectionTitle = (p['sectionTitle'] ?? '').toString().trim().isEmpty
              ? 'Section'
              : (p['sectionTitle'] ?? '').toString().trim();

          if (currentTitle != null && currentTitle != sectionTitle) {
            flushCurrentRun();
          }

          currentTitle = sectionTitle;
          currentPages.add(p);
        }

        flushCurrentRun();
      } else {
        final sectionPageGroups = <String, List<Map<String, dynamic>>>{};
        for (final p in sortedAllPages) {
          final sectionTitle = (p['sectionTitle'] ?? '').toString();
          sectionPageGroups.putIfAbsent(sectionTitle, () => <Map<String, dynamic>>[]);
          sectionPageGroups[sectionTitle]!.add(p);
        }
        sortedSectionGroups.addAll(sectionPageGroups.entries);
      }

      pw.Widget _topHeader({required String showHeader}) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Text(
                showHeader,
                style: pw.TextStyle(
                  fontSize: _scaled(12),
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Center(
              child: pw.Text(
                'Judging Sheet - Breed Class • Compact',
                style: pw.TextStyle(
                  fontSize: _scaled(12),
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.SizedBox(height: 5),
            pw.Row(
              children: [
                pw.Text(
                  'Writer: ',
                  style: pw.TextStyle(
                    fontSize: _scaled(9),
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Expanded(
                  child: pw.Container(
                    height: 10,
                    decoration: pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(width: 0.6, color: PdfColors.black),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
          ],
        );
      }

      pw.Widget _compactClassHeaderBlock({
        required int blockIndex,
        required int totalBlocks,
        required String sectionTitle,
        required String breed,
        required String color,
        required String cls,
        required String sex,
        required int breedCount,
        required int breedExhibitorCount,
        required int groupCount,
        required int groupExhibitorCount,
        required int rabbitCount,
        required int exhibitorCount,
      }) {
        final label = pw.TextStyle(fontSize: _scaled(8.5), fontWeight: pw.FontWeight.bold);
        final small = pw.TextStyle(fontSize: _scaled(8));
        final title = pw.TextStyle(fontSize: _scaled(9.5), fontWeight: pw.FontWeight.bold);

        return pw.Container(
          margin: const pw.EdgeInsets.only(top: 4, bottom: 4),
          padding: const pw.EdgeInsets.only(bottom: 4),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(width: .4, color: PdfColors.grey400),
            ),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      sectionTitle.trim().isEmpty
                          ? 'Breed: $breed'
                          : '$sectionTitle — $breed',
                      style: title,
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Text('Breed Class ${blockIndex + 1} of $totalBlocks', style: small),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'No. in Breed: $breedCount   Breed Exhibitors: $breedExhibitorCount',
                style: small,
              ),
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Group: ${color.trim().isEmpty ? 'Standard' : color}',
                    style: title,
                  ),
                  pw.Text(
                    'No. in Group: $groupCount   Group Exhibitors: $groupExhibitorCount',
                    style: small,
                  ),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('No. in Class: $rabbitCount   Class Exhibitors: $exhibitorCount', style: small),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Row(
                children: [
                  pw.Expanded(child: pw.Text('Class: $cls', style: label)),
                  pw.Expanded(child: pw.Text('Sex: $sex', style: label)),
                ],
              ),
            ],
          ),
        );
      }

      pw.Widget _breedHeaderBlock({
        required String breed,
        required int breedIndex,
        required int totalBreeds,
        String? sectionHint,
      }) {
        return pw.Container(
          margin: const pw.EdgeInsets.only(top: 4, bottom: 6),
          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey200,
            border: pw.Border.all(width: 0.5, color: PdfColors.grey600),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Breed: $breed',
                style: pw.TextStyle(fontSize: _scaled(11), fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'Breed ${breedIndex + 1} of $totalBreeds',
                style: pw.TextStyle(fontSize: _scaled(8.5)),
              ),
            ],
          ),
        );
      }

      pw.Widget _compactJudgingTable({
        required List<Map<String, dynamic>> groupEntries,
        required List<String> specialsList,
        required String ageSpecial,
        required bool isFurOrWool,
      }) {
        final h = pw.TextStyle(fontSize: _scaled(13), fontWeight: pw.FontWeight.bold);
        final c = pw.TextStyle(fontSize: _scaled(12.5), fontWeight: pw.FontWeight.bold);
        final specialsCell = pw.TextStyle(
          fontSize: _scaled(9, max: 10),
          fontWeight: pw.FontWeight.bold,
        );
        final specialsText = specialsList.join(', ');
        final specialsHeader = ageSpecial.isNotEmpty
            ? 'Specials\n$ageSpecial'
            : 'Specials';

        if (isFurOrWool) {
          return pw.Table(
            border: pw.TableBorder.all(width: 0.4),
            columnWidths: {
              0: const pw.FixedColumnWidth(64),
              1: const pw.FlexColumnWidth(.85),
              2: const pw.FixedColumnWidth(110),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(3),
                    child: pw.Text('Ear #', style: h),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(3),
                    child: pw.Text('Exhibitor', style: h),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(3),
                    child: pw.Text('Place / DQ', style: h),
                  ),
                ],
              ),
              ...groupEntries.map((row) {
                return pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      child: pw.Text(_animalPrintLabel(row), style: c),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      child: pw.Text(_safe(row, 'exhibitor_label'), style: c),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      child: pw.Text('', style: c),
                    ),
                  ],
                );
              }),
            ],
          );
        }

        return pw.Table(
          border: pw.TableBorder.all(width: 0.4),
          columnWidths: {
            0: const pw.FixedColumnWidth(64),
            1: const pw.FlexColumnWidth(.85),
            2: const pw.FixedColumnWidth(105),
            3: const pw.FixedColumnWidth(78),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey300),
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.all(3),
                  child: pw.Text('Ear #', style: h),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(3),
                  child: pw.Text('Exhibitor', style: h),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(3),
                  child: pw.Text('Place / DQ', style: h),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(3),
                  child: pw.Text(specialsHeader, style: h),
                ),
              ],
            ),
            ...groupEntries.map((row) {
              return pw.TableRow(
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(3),
                    child: pw.Text(_animalPrintLabel(row), style: c),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(3),
                    child: pw.Text(_safe(row, 'exhibitor_label'), style: c),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(3),
                    child: pw.Text('', style: c),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(3),
                    child: pw.Text(specialsText, style: specialsCell),
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
          margin: const pw.EdgeInsets.only(top: 5, bottom: 5),
          padding: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey500, width: 0.5),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: url,
                width: 42,
                height: 42,
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Text(
                  'Scan to enter results directly into RingMaster Show. Please also fill out control sheet in full.',
                  style: pw.TextStyle(fontSize: _scaled(7.5), fontWeight: pw.FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      }

      double _estimatedClassBlockHeight({
        required int rowCount,
        required bool includeQr,
        required bool isFurOrWool,
      }) {
        // Conservative estimate in PDF points. Text in the Ear #, Exhibitor,
        // and Specials cells can wrap to multiple lines, so this intentionally
        // estimates taller than a simple one-line table row. The goal is to
        // start a class on a new page before the pdf package is forced to split
        // the class table between pages.
        final headerHeight = 84.0;
        final qrHeight = includeQr ? 64.0 : 0.0;
        final furNoteHeight = isFurOrWool ? 18.0 : 0.0;
        final tableHeaderHeight = 28.0;
        final rowHeight = 28.0;
        final bottomGap = 12.0;
        return headerHeight + qrHeight + furNoteHeight + tableHeaderHeight + (rowCount * rowHeight) + bottomGap;
      }

      for (final sectionGroup in sortedSectionGroups) {
        final sectionTitle = sectionGroup.key;
        final pages = sectionGroup.value;

        doc.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.letter,
            margin: const pw.EdgeInsets.fromLTRB(42, 24, 18, 26),
            theme: theme,
            header: (_) => _topHeader(
              showHeader: '${widget.showName}   $sectionTitle',
            ),
            footer: (context) => pw.Row(
              children: [
                pw.Text('RingMaster Show', style: pw.TextStyle(fontSize: _scaled(8))),
                pw.Spacer(),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: pw.TextStyle(fontSize: _scaled(8)),
                ),
                pw.Spacer(),
                pw.Text('${DateTime.now().toLocal()}', style: pw.TextStyle(fontSize: _scaled(8))),
              ],
            ),
            build: (_) {
              final widgets = <pw.Widget>[];
              // Keep this below the physical page body height because wrapped
              // table text can make the real rendered height larger than the
              // simple estimate below.
              const estimatedUsablePageHeight = 535.0;
              const estimatedBreedHeaderHeight = 42.0;
              var estimatedRemainingHeight = estimatedUsablePageHeight;

              final breedGroups = <String, List<Map<String, dynamic>>>{};
              for (final p in pages) {
                final breed = (p['breed'] ?? '').toString().trim();
                final breedKey = breed.isEmpty ? '(Unknown Breed)' : breed;
                breedGroups.putIfAbsent(breedKey, () => <Map<String, dynamic>>[]);
                breedGroups[breedKey]!.add(p);
              }

              final breedNames = breedGroups.keys.toList();

              final breedStats = <String, Map<String, int>>{};
              final groupStats = <String, Map<String, int>>{};

              for (final breedName in breedNames) {
                final breedPagesForStats = breedGroups[breedName] ?? const <Map<String, dynamic>>[];
                final breedEntryIds = <String>{};
                final breedExhibitorIds = <String>{};
                final groupEntryIdsByLabel = <String, Set<String>>{};
                final groupExhibitorIdsByLabel = <String, Set<String>>{};

                for (final p in breedPagesForStats) {
                  final groupLabel = ((p['color'] ?? '').toString().trim().isEmpty)
                      ? 'Standard'
                      : (p['color'] ?? '').toString().trim();
                  final rowsForStats = (p['rows'] as List).cast<Map<String, dynamic>>();

                  groupEntryIdsByLabel.putIfAbsent(groupLabel, () => <String>{});
                  groupExhibitorIdsByLabel.putIfAbsent(groupLabel, () => <String>{});

                  for (var rowIndex = 0; rowIndex < rowsForStats.length; rowIndex++) {
                    final row = rowsForStats[rowIndex];
                    final entryId = _safe(row, 'entry_id').isNotEmpty
                        ? _safe(row, 'entry_id')
                        : _safe(row, 'id').isNotEmpty
                            ? _safe(row, 'id')
                            : '$breedName|$groupLabel|$rowIndex';
                    final exhibitorId = _safe(row, 'exhibitor_id');

                    breedEntryIds.add(entryId);
                    groupEntryIdsByLabel[groupLabel]!.add(entryId);

                    if (exhibitorId.isNotEmpty) {
                      breedExhibitorIds.add(exhibitorId);
                      groupExhibitorIdsByLabel[groupLabel]!.add(exhibitorId);
                    }
                  }
                }

                breedStats[breedName] = {
                  'entries': breedEntryIds.length,
                  'exhibitors': breedExhibitorIds.length,
                };

                for (final groupLabel in groupEntryIdsByLabel.keys) {
                  groupStats['$breedName|$groupLabel'] = {
                    'entries': groupEntryIdsByLabel[groupLabel]!.length,
                    'exhibitors': groupExhibitorIdsByLabel[groupLabel]?.length ?? 0,
                  };
                }
              }

              for (var breedIndex = 0; breedIndex < breedNames.length; breedIndex++) {
                final breed = breedNames[breedIndex];
                final breedPages = breedGroups[breed] ?? const <Map<String, dynamic>>[];
                if (breedPages.isEmpty) continue;

                if (widgets.isNotEmpty) {
                  widgets.add(pw.NewPage());
                }

                widgets.add(
                  _breedHeaderBlock(
                    breed: breed,
                    breedIndex: breedIndex,
                    totalBreeds: breedNames.length,
                    sectionHint: null,
                  ),
                );
                estimatedRemainingHeight = estimatedUsablePageHeight - estimatedBreedHeaderHeight;

                for (var i = 0; i < breedPages.length; i++) {
                  final p = breedPages[i];
                  final isFurOrWool = p['isFurOrWool'] == true;

                  final classBlockWidgets = <pw.Widget>[
                    _compactClassHeaderBlock(
                      blockIndex: i,
                      totalBlocks: breedPages.length,
                      sectionTitle: (p['sectionTitle'] ?? '').toString(),
                      breed: breed,
                      color: (p['color'] ?? '').toString(),
                      cls: (p['class'] ?? '').toString(),
                      sex: (p['sex'] ?? '').toString(),
                      breedCount: breedStats[breed]?['entries'] ?? 0,
                      breedExhibitorCount: breedStats[breed]?['exhibitors'] ?? 0,
                      groupCount: groupStats['$breed|${((p['color'] ?? '').toString().trim().isEmpty) ? 'Standard' : (p['color'] ?? '').toString().trim()}']?['entries'] ?? 0,
                      groupExhibitorCount: groupStats['$breed|${((p['color'] ?? '').toString().trim().isEmpty) ? 'Standard' : (p['color'] ?? '').toString().trim()}']?['exhibitors'] ?? 0,
                      rabbitCount: (p['rabbitCount'] as int?) ?? 0,
                      exhibitorCount: (p['exhibitorCount'] as int?) ?? 0,
                    ),
                  ];

                  if (includeQrCode) {
                    classBlockWidgets.add(
                      qrResultsBlock(
                        sectionId: (p['sectionId'] ?? '').toString(),
                        breed: breed,
                      ),
                    );
                  }

                  if (isFurOrWool) {
                    classBlockWidgets.add(
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 4),
                        child: pw.Text(
                          'Fur/Wool Sheet — placements only',
                          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                        ),
                      ),
                    );
                  }

                  classBlockWidgets.add(
                    _compactJudgingTable(
                      groupEntries: (p['rows'] as List).cast<Map<String, dynamic>>(),
                      specialsList: (p['specials'] as List).map((x) => x.toString()).toList(),
                      ageSpecial: (p['ageSpecial'] ?? '').toString(),
                      isFurOrWool: isFurOrWool,
                    ),
                  );

                  classBlockWidgets.add(pw.SizedBox(height: 8));

                  final classRowCount = ((p['rows'] as List?) ?? const []).length;
                  final estimatedClassHeight = _estimatedClassBlockHeight(
                    rowCount: classRowCount,
                    includeQr: includeQrCode,
                    isFurOrWool: isFurOrWool,
                  );

                  // If a class will not fit in the estimated remaining page space,
                  // start it on a fresh page. This avoids orphaned class headers
                  // where the header prints at the bottom of one page and all
                  // animals continue on the next page.
                  if (estimatedRemainingHeight < estimatedClassHeight && widgets.isNotEmpty) {
                    widgets.add(pw.NewPage());
                    widgets.add(
                      _breedHeaderBlock(
                        breed: breed,
                        breedIndex: breedIndex,
                        totalBreeds: breedNames.length,
                        sectionHint: null,
                      ),
                    );
                    estimatedRemainingHeight = estimatedUsablePageHeight - estimatedBreedHeaderHeight;
                  }

                  widgets.addAll(classBlockWidgets);
                  estimatedRemainingHeight -= estimatedClassHeight;
                }
              }

              return widgets;
            },
          ),
        );
      }
      // END REPLACEMENT BLOCK
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

      final name = 'control_compact_${widget.showName}_${widget.sectionLabel}${includeQrCode ? '_QR' : ''}.pdf';

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
                  ? 'Mode: Paired PDF — Open and Youth remain separate sheets'
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
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Font Size Scale',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Adjust judging sheet text size for clubs that prefer larger print.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('100%'),
                      Expanded(
                        child: Slider(
                          value: _fontScale,
                          min: 1.0,
                          max: 2.0,
                          divisions: 10,
                          label: '${(_fontScale * 100).round()}%',
                          onChanged: _building
                              ? null
                              : (v) {
                                  setState(() {
                                    _fontScale = v;
                                  });
                                },
                        ),
                      ),
                      Text('${(_fontScale * 100).round()}%'),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Maximum rendered font size is capped at 16 pt.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD4A623),
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _building ? null : () => _generatePdf(includeQrCode: false),
              icon: const Icon(Icons.picture_as_pdf),
              label: Text(_building ? 'Building Compact PDF…' : 'Generate Compact PDF'),
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
                _building ? 'Building Compact PDF…' : 'Generate Compact PDF with QR Code',
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
  final bool pairOpenYouthByLetter;
  final bool youthFirst;

  const _CheckInGeneratorSheet({
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
        .maybeSingle();

    _showRow = (row as Map<String, dynamic>?) ?? <String, dynamic>{};
  }

    Future<List<Map<String, dynamic>>> _fetchEntries() async {
      const pageSize = 1000;
      final list = <Map<String, dynamic>>[];

      for (var from = 0;; from += pageSize) {
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

      assert(() {
        debugPrint('CHECK-IN FETCHED ROWS: ${list.length}');
        debugPrint(
          'CHECK-IN SPENCER ROWS: ${list.where((e) => _safe(e, 'exhibitor_label').toLowerCase().contains('spencer baitz')).length}',
        );
        return true;
      }());

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

        final sectionKindCmp = kindRank(_safe(a, 'section_kind'))
            .compareTo(kindRank(_safe(b, 'section_kind')));
        final sectionSortCmp = toInt(a['section_sort_order'])
            .compareTo(toInt(b['section_sort_order']));
        final sectionLetterCmp = _safe(a, 'section_letter')
            .toUpperCase()
            .compareTo(_safe(b, 'section_letter').toUpperCase());

        if (widget.pairOpenYouthByLetter) {
          if (sectionSortCmp != 0) return sectionSortCmp;
          if (sectionLetterCmp != 0) return sectionLetterCmp;
          if (sectionKindCmp != 0) return sectionKindCmp;
        } else {
          if (sectionKindCmp != 0) return sectionKindCmp;
          if (sectionSortCmp != 0) return sectionSortCmp;
          if (sectionLetterCmp != 0) return sectionLetterCmp;
        }

        final exhibitorCmp = _safe(a, 'exhibitor_label')
            .toLowerCase()
            .compareTo(_safe(b, 'exhibitor_label').toLowerCase());
        if (exhibitorCmp != 0) return exhibitorCmp;

        final breedCmp = _safe(a, 'breed')
            .toLowerCase()
            .compareTo(_safe(b, 'breed').toLowerCase());
        if (breedCmp != 0) return breedCmp;

        final varietyCmp = _groupVarietyLabel(a)
            .toLowerCase()
            .compareTo(_groupVarietyLabel(b).toLowerCase());
        if (varietyCmp != 0) return varietyCmp;

        final classSortCmp = toInt(a['class_sort_order'])
            .compareTo(toInt(b['class_sort_order']));
        if (classSortCmp != 0) return classSortCmp;

        final sexCmp = _safe(a, 'sex')
            .toLowerCase()
            .compareTo(_safe(b, 'sex').toLowerCase());
        if (sexCmp != 0) return sexCmp;

        return _safe(a, 'tattoo')
            .toLowerCase()
            .compareTo(_safe(b, 'tattoo').toLowerCase());
      });

      return list;
    }

  bool _emailing = false;

  String _money(dynamic value) {
    final n = value is num ? value : num.tryParse(value?.toString() ?? '');
    if (n == null) return r'$—';
    return '\$${n.toStringAsFixed(2)}';
  }

    String _checkInBalanceDue(List<Map<String, dynamic>> entries) {
      if (entries.isEmpty) return r'$—';

      for (final e in entries) {
        final allShows = e['balance_due_all_shows'];
        if (allShows != null && allShows.toString().trim().isNotEmpty) {
          return _money(allShows);
        }
      }

      for (final e in entries) {
        final thisShow = e['balance_due_this_show'];
        if (thisShow != null && thisShow.toString().trim().isNotEmpty) {
          return _money(thisShow);
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

  // Loads show secretary/contact details before building each check-in sheet PDF.
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
              return 0;
            case 'youth':
              return 1;
            default:
              return 99;
          }
        }

        final sectionKindCmp = kindRank(_safe(a, 'section_kind'))
            .compareTo(kindRank(_safe(b, 'section_kind')));
        if (sectionKindCmp != 0) return sectionKindCmp;

        final sectionSortCmp = toInt(a['section_sort_order'])
            .compareTo(toInt(b['section_sort_order']));
        if (sectionSortCmp != 0) return sectionSortCmp;

        final sectionLetterCmp = _safe(a, 'section_letter')
            .toUpperCase()
            .compareTo(_safe(b, 'section_letter').toUpperCase());
        if (sectionLetterCmp != 0) return sectionLetterCmp;

        final breedSortCmp =
            toInt(a['breed_sort_order']).compareTo(toInt(b['breed_sort_order']));
        if (breedSortCmp != 0) return breedSortCmp;

        final breedCmp = _safe(a, 'breed')
            .toLowerCase()
            .compareTo(_safe(b, 'breed').toLowerCase());
        if (breedCmp != 0) return breedCmp;

        final groupSortCmp =
            toInt(a['group_sort_order']).compareTo(toInt(b['group_sort_order']));
        if (groupSortCmp != 0) return groupSortCmp;

        final varietySortCmp = toInt(a['variety_sort_order'])
            .compareTo(toInt(b['variety_sort_order']));
        if (varietySortCmp != 0) return varietySortCmp;

        final varietyCmp = _groupVarietyLabel(a)
            .toLowerCase()
            .compareTo(_groupVarietyLabel(b).toLowerCase());
        if (varietyCmp != 0) return varietyCmp;

        final classSortCmp =
            toInt(a['class_sort_order']).compareTo(toInt(b['class_sort_order']));
        if (classSortCmp != 0) return classSortCmp;

        final sexCmp =
            _safe(a, 'sex').toLowerCase().compareTo(_safe(b, 'sex').toLowerCase());
        if (sexCmp != 0) return sexCmp;

        return _safe(a, 'tattoo')
            .toLowerCase()
            .compareTo(_safe(b, 'tattoo').toLowerCase());
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

    pw.Widget _balanceBox({required String balanceDue}) {
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
              balanceDue,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget _infoBlockLeft(Map<String, dynamic> ex) {
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
              final furMark = _safe(e, 'is_fur').toLowerCase() == 'true' ||
                      _safe(e, 'class_name').toLowerCase().contains('fur')
                  ? 'X'
                  : '';

              return pw.TableRow(
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: 
                    pw.Text(
                      _safe(e, 'tattoo'),
                      style: style,
                    ),
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
                    child: pw.Text(
                      furMark,
                      style: style,
                    ),
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
              pw.Row(
                children: [
                  pw.Spacer(),
                  _balanceBox(balanceDue: balanceDue),
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
        pw.MultiPage(
          pageFormat: PdfPageFormat.letter,
          margin: const pw.EdgeInsets.fromLTRB(20, 20, 20, 20),
          build: (_) {
            return [
              pw.Column(
              children: [
                pw.Expanded(child: _remarkCard(first)),
                pw.SizedBox(height: 14),
                pw.Expanded(
                  child: second == null
                      ? pw.Container()
                      : _remarkCard(second),
                ),
              ],
            ),
            ];
          },
        )
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