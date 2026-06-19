// lib/screens/admin/admin_print_packs_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';
import 'package:ringmaster_show/services/app_session.dart';

import 'print_packs/check_in_generator_sheet.dart';
import 'print_packs/control_sheets_generator_sheet.dart';
import 'print_packs/coop_cards_generator_sheet.dart';
import 'print_packs/remark_cards_generator_sheet.dart';

final supabase = Supabase.instance.client;


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
  bool _savingSecretaryInfo = false;
  bool _secretaryInfoExpanded = true;
  final TextEditingController _secretaryNameController = TextEditingController();
  final TextEditingController _secretaryAddressController = TextEditingController();
  final TextEditingController _secretaryPhoneController = TextEditingController();
  final TextEditingController _secretaryEmailController = TextEditingController();
  bool _isSuperAdmin = false;
  bool _loadingSuperAdmin = true;
  DateTime? _entryCloseAt;
  DateTime? _checkInSheetsAutoEmailedAt;
  String? _checkInSheetsAutoEmailError;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _secretaryNameController.dispose();
    _secretaryAddressController.dispose();
    _secretaryPhoneController.dispose();
    _secretaryEmailController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    await Future.wait([
      _loadSuperAdminStatus(),
      _loadSections(),
    ]);
  }

  Future<void> _loadSuperAdminStatus() async {
    setState(() {
      _loadingSuperAdmin = true;
    });

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null || userId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _isSuperAdmin = false;
          _loadingSuperAdmin = false;
        });
        return;
      }

      final rows = await supabase
          .from('role_assignments')
          .select('id')
          .eq('user_id', userId)
          .eq('role', 'super_admin')
          .limit(1);

      if (!mounted) return;
      setState(() {
        _isSuperAdmin = (rows as List).isNotEmpty;
        _loadingSuperAdmin = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSuperAdmin = false;
        _loadingSuperAdmin = false;
      });
    }
  }

  bool get _showQrPrintFeatures => _isSuperAdmin;

  Future<void> _loadSections() async {
    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      final showRow = await supabase
          .from('shows')
          .select(
            'id, entry_close_at, auto_email_checkin_sheets, checkin_sheets_auto_emailed_at, checkin_sheets_auto_email_error, secretary_name, secretary_address, secretary_phone, secretary_email',
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

      _autoFillSecretaryInfoFromShow(show);

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

  void _autoFillSecretaryInfoFromShow(Map<String, dynamic> show) {
    final secretaryName = (show['secretary_name'] ?? '').toString().trim();
    final secretaryAddress = (show['secretary_address'] ?? '').toString().trim();
    final secretaryPhone = (show['secretary_phone'] ?? '').toString().trim();
    final secretaryEmail = (show['secretary_email'] ?? '').toString().trim();

    _secretaryNameController.text = secretaryName;
    _secretaryAddressController.text = secretaryAddress;
    _secretaryPhoneController.text = secretaryPhone;
    _secretaryEmailController.text = secretaryEmail;

    // Keep this section open by default only when it still needs attention.
    _secretaryInfoExpanded = !_secretaryInfoComplete;
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

  bool get _secretaryInfoComplete {
    return _secretaryNameController.text.trim().isNotEmpty &&
        _secretaryAddressController.text.trim().isNotEmpty &&
        _secretaryPhoneController.text.trim().isNotEmpty &&
        _secretaryEmailController.text.trim().isNotEmpty;
  }

  Future<void> _saveSecretaryInfo() async {
    if (_savingSecretaryInfo) return;

    if (AppSession.isSupportMode) {
      setState(() {
        _msg = 'Secretary information cannot be changed while viewing in support mode.';
      });
      return;
    }

    final name = _secretaryNameController.text.trim();
    final address = _secretaryAddressController.text.trim();
    final phone = _secretaryPhoneController.text.trim();
    final email = _secretaryEmailController.text.trim();

    if (name.isEmpty || address.isEmpty || phone.isEmpty || email.isEmpty) {
      setState(() {
        _secretaryInfoExpanded = true;
        _msg = 'Please enter the show secretary name, address, phone, and email.';
      });
      return;
    }

    setState(() {
      _savingSecretaryInfo = true;
      _msg = null;
    });

    try {
      await supabase.from('shows').update({
        'secretary_name': name,
        'secretary_address': address,
        'secretary_phone': phone,
        'secretary_email': email,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.showId);

      if (!mounted) return;
      setState(() {
        _savingSecretaryInfo = false;
        _secretaryInfoExpanded = false;
        _msg = 'Show secretary information saved.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingSecretaryInfo = false;
        _msg = 'Failed to save show secretary information: $e';
      });
    }
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
        child: RemarkCardsGeneratorSheet(
          showId: widget.showId,
          showName: widget.showName,
          sections: _sections,
          includeScratched: _includeScratched,
        ),
      ),
    );
  }

  void _openCoopCardsGenerator() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _themedBottomSheetShell(
        context,
        child: CoopCardsGeneratorSheet(
          showId: widget.showId,
          showName: widget.showName,
        ),
      ),
    );
  }

  void _openCheckInGenerator() {
    if (!_secretaryInfoComplete) {
      setState(() {
        _secretaryInfoExpanded = true;
        _msg = 'Please save show secretary information before generating check-in sheets.';
      });
      return;
    }
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
        child: CheckInGeneratorSheet(
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
    if (!_secretaryInfoComplete) {
      setState(() {
        _secretaryInfoExpanded = true;
        _msg = 'Please save show secretary information before generating control sheets.';
      });
      return;
    }
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
        child: ControlSheetsGeneratorSheet(
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

  Widget _buildSecretaryInfoCard() {
    final readOnly = AppSession.isSupportMode;
    final complete = _secretaryInfoComplete;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
      child: ExpansionTile(
        initiallyExpanded: _secretaryInfoExpanded || !complete,
        onExpansionChanged: (value) {
          setState(() => _secretaryInfoExpanded = value);
        },
        leading: Icon(
          complete ? Icons.check_circle_outline : Icons.info_outline,
          color: complete ? Colors.green : Colors.orange,
        ),
        title: const Text(
          'Show Secretary Information',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          complete
              ? 'Saved to the show record for printed sheets and email reports.'
              : 'Required for check-in sheets and emailed reports.',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const SizedBox(height: 8),
          TextField(
            controller: _secretaryNameController,
            readOnly: readOnly,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Show Secretary Name',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _secretaryAddressController,
            readOnly: readOnly,
            textInputAction: TextInputAction.next,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Show Secretary Address',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _secretaryPhoneController,
            readOnly: readOnly,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Show Secretary Phone',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _secretaryEmailController,
            readOnly: readOnly,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Show Secretary Email',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: readOnly || _savingSecretaryInfo
                  ? null
                  : _saveSecretaryInfo,
              icon: _savingSecretaryInfo
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(
                _savingSecretaryInfo ? 'Saving...' : 'Save Secretary Info',
              ),
            ),
          ),
        ],
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
      title: 'RingMaster One Show',
      subtitle: 'Print Show Sheets — ${widget.showName}',
      showBackButton: true,
      showHomeButton: true,
      useScrollView: false,
      bodyPadding: EdgeInsets.zero,
      actions: [
        IconButton(
          tooltip: 'Reload sections',
          onPressed: _loading ? null : _loadInitialData,
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: (_loading || _loadingSuperAdmin)
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _messageBanner(),
                if (AppSession.isSupportMode)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.support_agent, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Support Mode — You are generating print packs as an admin while viewing another user.',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),

                _buildSecretaryInfoCard(),

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

                _buildSectionCard(
                  icon: Icons.sell_outlined,
                  title: 'Coop Cards',
                  subtitle:
                      'Generate 4 in. × 4.5 in. coop cards, four cards per US Letter sheet, with cut borders.',
                  children: [
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
                        onPressed: hasSections ? _openCoopCardsGenerator : null,
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const Text('Generate Coop Cards'),
                      ),
                    ),
                  ],
                ),
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

