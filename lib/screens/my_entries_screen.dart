// lib/screens/my_entries_screen.dart

import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:html' as html;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';

import 'my_animals_screen.dart';
import 'account_settings_screen.dart';
import 'package:ringmaster_show/screens/admin/entries_by_breed_section_table.dart';
import '../services/app_session.dart';
import '../theme/app_theme.dart';
import '../utils/date_time_utils.dart';
import '../widgets/rm_widgets.dart';

final supabase = Supabase.instance.client;

class MyEntriesScreen extends StatefulWidget {
  const MyEntriesScreen({super.key});

  @override
  State<MyEntriesScreen> createState() => _MyEntriesScreenState();
}

class _MyEntriesScreenState extends State<MyEntriesScreen> {
  bool _loading = true;
  String? _msg;

  final Map<String, Map<String, dynamic>> _showsById = {};
  final Map<String, Map<String, dynamic>> _sectionsById = {};
  final Map<String, Map<String, dynamic>> _exhibitorsById = {};

  List<Map<String, dynamic>> _entries = [];
  final Set<String> _expandedShowIds = {};

  void _handleStripeSuccessReturn() {
    final uri = Uri.base;
    final fragment = uri.fragment;

    if (!fragment.contains('stripe=success')) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      await _load(); // use your existing entries reload method

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Payment Successful'),
          content: const Text(
            'Your payment was received and your entries have been submitted successfully.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      html.window.history.replaceState(null, '', '${Uri.base.origin}/#/entries');
    });
  }

  @override
  void initState() {
    super.initState();
    final hasStripeSuccessReturn = Uri.base.fragment.contains('stripe=success');

    if (hasStripeSuccessReturn) {
      _handleStripeSuccessReturn();
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    final userId = AppSession.effectiveUserId;
    if (userId == null) {
      setState(() {
        _loading = false;
        _msg = 'Not signed in.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      final myExhibitorRows = await supabase
          .from('exhibitors')
          .select('id')
          .eq('owner_user_id', userId);

      final myExhibitorIds = (myExhibitorRows as List)
          .map((e) => (e['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet();

      final selectColumns =
          'id,show_id,exhibitor_id,animal_id,species,tattoo,breed,variety,sex,'
          'class_name,status,section_id,created_at,exhibitor_user_id';

      final rowsById = <String, Map<String, dynamic>>{};

      final accountRows = await supabase
          .from('entries')
          .select(selectColumns)
          .eq('exhibitor_user_id', userId)
          .order('created_at', ascending: true);

      for (final row in (accountRows as List).cast<Map<String, dynamic>>()) {
        final id = (row['id'] ?? '').toString();
        if (id.isNotEmpty) rowsById[id] = row;
      }

      if (myExhibitorIds.isNotEmpty) {
        final exhibitorRows = await supabase
            .from('entries')
            .select(selectColumns)
            .inFilter('exhibitor_id', myExhibitorIds.toList())
            .order('created_at', ascending: true);

        for (final row in (exhibitorRows as List).cast<Map<String, dynamic>>()) {
          final id = (row['id'] ?? '').toString();
          if (id.isNotEmpty) rowsById[id] = row;
        }
      }

      _entries = rowsById.values.toList()
        ..sort((a, b) => (a['created_at'] ?? '').toString().compareTo(
              (b['created_at'] ?? '').toString(),
            ));

      final showIds = _entries
          .map((e) => (e['show_id'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toSet();

      if (showIds.isNotEmpty) {
        final shows = await supabase
            .from('shows')
            .select(
              'id,name,start_date,entry_close_at,'
              'superintendent_judge_order_published,'
              'superintendent_judge_order_published_at',
            )
            .inFilter('id', showIds.toList());

        _showsById
          ..clear()
          ..addAll({
            for (final s in (shows as List).cast<Map<String, dynamic>>())
              s['id'].toString(): s,
          });

        final sections = await supabase
            .from('show_sections')
            .select('id,show_id,display_name,kind,letter,sort_order')
            .inFilter('show_id', showIds.toList());

        _sectionsById
          ..clear()
          ..addAll({
            for (final s in (sections as List).cast<Map<String, dynamic>>())
              s['id'].toString(): s,
          });
      }

      final exhibitorIds = _entries
          .map((e) => (e['exhibitor_id'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toSet();

      if (exhibitorIds.isNotEmpty) {
        final exRows = await supabase
            .from('exhibitors')
            .select('id,showing_name,display_name')
            .inFilter('id', exhibitorIds.toList());

        _exhibitorsById
          ..clear()
          ..addAll({
            for (final e in (exRows as List).cast<Map<String, dynamic>>())
              e['id'].toString(): e,
          });
      }

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _msg = 'Load failed: $e';
      });
    }
  }

  DateTime? _parseTs(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  DateTime? _showStartDate(String showId) {
    return _parseTs(_showsById[showId]?['start_date']);
  }

  String _showTitle(String showId) {
    final s = _showsById[showId];
    if (s == null) return 'Show';
    final name = (s['name'] ?? 'Show').toString();
    final sd = _parseTs(s['start_date']);
    final date = sd == null ? '' : ' (${sd.toIso8601String().substring(0, 10)})';
    return '$name$date';
  }

  bool _deadlinePassedForShow(String showId) {
    final closeAt = _parseTs(_showsById[showId]?['entry_close_at']);
    if (closeAt == null) return false;
    return DateTime.now().isAfter(closeAt.toLocal());
  }

  bool _hideShowAfter48h(String showId) {
    final sd = _showStartDate(showId);
    if (sd == null) return false;
    final cutoff = sd.toLocal().add(const Duration(hours: 48));
    return DateTime.now().isAfter(cutoff);
  }

  String _exhibitorLabelById(String? exhibitorId) {
    final id = (exhibitorId ?? '').toString();
    if (id.isEmpty) return '(Unknown Exhibitor)';
    final e = _exhibitorsById[id];
    if (e == null) return '(Unknown Exhibitor)';
    final sn = (e['showing_name'] ?? '').toString().trim();
    if (sn.isNotEmpty) return sn;
    final dn = (e['display_name'] ?? '').toString().trim();
    if (dn.isNotEmpty) return dn;
    return '(Unknown Exhibitor)';
  }

  String _sectionLabel(String? sectionId) {
    final id = (sectionId ?? '').toString();
    final s = _sectionsById[id];
    if (s == null) return 'Section';
    final dn = (s['display_name'] ?? '').toString().trim();
    if (dn.isNotEmpty) return dn;

    final kind = (s['kind'] ?? '').toString().trim();
    final letter = (s['letter'] ?? '').toString().trim();
    if (kind.isNotEmpty && letter.isNotEmpty) {
      return '${kind[0].toUpperCase()}${kind.substring(1)} $letter';
    }
    return 'Section';
  }

  Future<void> _scratchEntry(Map<String, dynamic> entry) async {
    final id = entry['id']?.toString() ?? '';
    if (id.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Scratch Entry'),
        content: const Text(
          'This will mark the entry as scratched. You can restore it again before the entry deadline.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Scratch'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await supabase
          .from('entries')
          .update({'status': 'scratched'})
          .eq('id', id);

      await _load();

      if (!mounted) return;
      setState(() {
        _msg = 'Entry scratched.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Scratch failed: $e');
    }
  }

  Future<void> _restoreEntry(Map<String, dynamic> entry) async {
    final id = entry['id']?.toString() ?? '';
    if (id.isEmpty) return;

    final showId = entry['show_id']?.toString() ?? '';
    if (showId.isEmpty) return;

    if (_deadlinePassedForShow(showId)) {
      setState(() {
        _msg = 'Entry deadline passed. Scratched entries can no longer be restored.';
      });
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restore Entry'),
        content: const Text(
          'This will restore the scratched entry back into the show.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await supabase
          .from('entries')
          .update({'status': 'entered'})
          .eq('id', id);

      await _load();

      if (!mounted) return;
      setState(() {
        _msg = 'Entry restored.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Restore failed: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _loadMyAnimals({String? currentAnimalId}) async {
    final userId = AppSession.effectiveUserId;
    if (userId == null) return [];

    final myExhibitorRows = await supabase
        .from('exhibitors')
        .select('id')
        .eq('owner_user_id', userId);

    final myExhibitorIds = (myExhibitorRows as List)
        .map((e) => (e['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();

    final selectColumns = 'id,species,name,tattoo,breed,variety,sex,birth_date';
    final animalsById = <String, Map<String, dynamic>>{};

    final ownedRows = await supabase
        .from('animals')
        .select(selectColumns)
        .eq('owner_user_id', userId)
        .order('created_at', ascending: false);

    for (final row in (ownedRows as List).cast<Map<String, dynamic>>()) {
      final id = (row['id'] ?? '').toString();
      if (id.isNotEmpty) animalsById[id] = row;
    }

    if (myExhibitorIds.isNotEmpty) {
      final exhibitorAnimalRows = await supabase
          .from('animals')
          .select(selectColumns)
          .inFilter('exhibitor_id', myExhibitorIds.toList())
          .order('created_at', ascending: false);

      for (final row
          in (exhibitorAnimalRows as List).cast<Map<String, dynamic>>()) {
        final id = (row['id'] ?? '').toString();
        if (id.isNotEmpty) animalsById[id] = row;
      }
    }

    final animals = animalsById.values.toList();

    final existingId = (currentAnimalId ?? '').trim();
    final alreadyLoaded = animals.any(
      (a) => (a['id'] ?? '').toString() == existingId,
    );

    if (existingId.isNotEmpty && !alreadyLoaded) {
      final currentRows = await supabase
          .from('animals')
          .select(selectColumns)
          .eq('id', existingId)
          .limit(1);

      final currentAnimals = (currentRows as List).cast<Map<String, dynamic>>();
      if (currentAnimals.isNotEmpty) {
        animals.insert(0, currentAnimals.first);
      }
    }

    return animals;
  }

  Future<List<Map<String, dynamic>>> _loadMyExhibitors() async {
    final userId = AppSession.effectiveUserId;
    if (userId == null) return [];

    final rows = await supabase
        .from('exhibitors')
        .select('id,showing_name,display_name')
        .eq('owner_user_id', userId)
        .order('display_name', ascending: true);

    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<void> _editEntry(Map<String, dynamic> entry) async {
    final showId = entry['show_id']?.toString() ?? '';
    if (showId.isEmpty) return;

    if (_deadlinePassedForShow(showId)) {
      setState(() => _msg =
          'Entry deadline passed. Editing is locked. You can still scratch entries.');
      return;
    }

    final currentAnimalId = (entry['animal_id'] ?? '').toString();
    final animals = await _loadMyAnimals(currentAnimalId: currentAnimalId);
    final exhibitors = await _loadMyExhibitors();

    if (!mounted) return;
    final showSections = _sectionsById.values
        .where((s) => (s['show_id'] ?? '').toString() == showId)
        .toList()
      ..sort((a, b) {
        int kindRank(dynamic value) {
          final v = (value ?? '').toString().trim().toLowerCase();
          if (v == 'open') return 0;
          if (v == 'youth') return 1;
          return 99;
        }

        int toInt(dynamic value, [int fallback = 9999]) {
          if (value == null) return fallback;
          if (value is int) return value;
          return int.tryParse(value.toString()) ?? fallback;
        }

        final kindCmp = kindRank(a['kind']).compareTo(kindRank(b['kind']));
        if (kindCmp != 0) return kindCmp;

        final sortCmp = toInt(a['sort_order']).compareTo(toInt(b['sort_order']));
        if (sortCmp != 0) return sortCmp;

        return (a['letter'] ?? '').toString().compareTo(
              (b['letter'] ?? '').toString(),
            );
      });

    final result = await showDialog<_EditEntryResult>(
      context: context,
      builder: (_) => _EditEntryDialogV2(
        initialClassName: (entry['class_name'] ?? '').toString(),
        initialAnimalId: (entry['animal_id'] ?? '').toString(),
        initialSectionId: (entry['section_id'] ?? '').toString(),
        initialExhibitorId: (entry['exhibitor_id'] ?? '').toString(),
        animals: animals,
        exhibitors: exhibitors,
        sections: showSections,
        sectionLabel: _sectionLabel,
        onAddNewAnimal: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyAnimalsScreen()),
          );
        },
        reloadAnimals: () => _loadMyAnimals(currentAnimalId: currentAnimalId),
      ),
    );

    if (result == null) return;

    final newClass = result.className.trim();
    if (newClass.isEmpty) {
      setState(() => _msg = 'Class is required.');
      return;
    }

    final newSectionId = result.sectionId.trim();
    if (newSectionId.isEmpty) {
      setState(() => _msg = 'Show section is required.');
      return;
    }

    final newExhibitorId = result.exhibitorId.trim();
    if (newExhibitorId.isEmpty) {
      setState(() => _msg = 'Exhibitor is required.');
      return;
    }

    final exhibitorBelongsToAccount = exhibitors.any(
      (e) => (e['id'] ?? '').toString() == newExhibitorId,
    );
    if (!exhibitorBelongsToAccount) {
      setState(() => _msg = 'Selected exhibitor was not found on your account.');
      return;
    }

    final selectedSection = showSections
        .where((s) => (s['id'] ?? '').toString() == newSectionId)
        .toList();
    if (selectedSection.isEmpty) {
      setState(() => _msg = 'Selected show section was not found.');
      return;
    }

    final selectedExhibitor = exhibitors
        .where((e) => (e['id'] ?? '').toString() == newExhibitorId)
        .toList();
    if (selectedExhibitor.isEmpty) {
      setState(() => _msg = 'Selected exhibitor was not found on your account.');
      return;
    }

    // Youth eligibility is enforced when entries are created. This screen does
    // not select exhibitors.is_youth because that column does not exist in the
    // current exhibitors table.

    final picked = animals
        .where((a) => (a['id'] ?? '').toString() == result.animalId)
        .toList();
    if (picked.isEmpty) {
      setState(() => _msg = 'Selected animal not found.');
      return;
    }

    final a = picked.first;
    final rawSpecies = (a['species'] ?? '').toString().trim().toLowerCase();
    final species =
        (rawSpecies == 'rabbit' || rawSpecies == 'cavy') ? rawSpecies : null;

    if (species == null) {
      setState(() => _msg = 'Animal species must be rabbit or cavy.');
      return;
    }

    try {
      await supabase.from('entries').update({
        'animal_id': a['id'],
        'species': species,
        'tattoo': a['tattoo'],
        'breed': a['breed'],
        'variety': a['variety'],
        'sex': a['sex'],
        'class_name': newClass,
        'section_id': newSectionId,
        'exhibitor_id': newExhibitorId,
      }).eq('id', entry['id']);

      await _load();
    } catch (e) {
      setState(() => _msg = 'Edit failed: $e');
    }
  }

  Map<String, Map<String, List<Map<String, dynamic>>>> _grouped() {
    final Map<String, Map<String, List<Map<String, dynamic>>>> out = {};
    for (final e in _entries) {
      final showId = (e['show_id'] ?? '').toString();
      final exhibitorId = (e['exhibitor_id'] ?? '').toString();

      if (showId.isEmpty) continue;
      out.putIfAbsent(showId, () => {});
      out[showId]!.putIfAbsent(exhibitorId, () => []);
      out[showId]![exhibitorId]!.add(e);
    }

    return out;
  }

  void _openAnimals(BuildContext context) {
    if (AppSession.isSupportMode) {
      setState(() {
        _msg = 'Animal management is disabled while viewing in support mode.';
      });
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MyAnimalsScreen()),
    );
  }

  void _openAccount(BuildContext context) {
    if (AppSession.isSupportMode) {
      setState(() {
        _msg = 'Account settings are disabled while viewing in support mode.';
      });
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AccountSettingsScreen()),
    );
  }

  void _openBreedCounts(BuildContext context, String showId, String showName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text('Breed Counts - $showName'),
          ),
          body: EntriesByBreedSectionTable(
            showId: showId,
            showName: showName,
            includeScratched: false,
            showExportButton: false,
            showExhibitorCounts: true,
            title: 'Breed Counts',
          ),
        ),
      ),
    );
  }

  bool _judgeOrderPublishedForShow(String showId) {
    return _showsById[showId]?['superintendent_judge_order_published'] == true;
  }

  String _publishedJudgeOrderTimestamp(String showId) {
    final raw = _showsById[showId]?['superintendent_judge_order_published_at'];
    if (raw == null) return '';
    return formatLocalDateTime(raw.toString());
  }

  Future<void> _openJudgeOrder(
    BuildContext context,
    String showId,
    String showName,
  ) async {
    if (!_judgeOrderPublishedForShow(showId)) {
      setState(() {
        _msg = 'Judge order has not been published for this show yet.';
      });
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (_) => _JudgeOrderDialog(
        showId: showId,
        showName: showName,
        publishedAt: _publishedJudgeOrderTimestamp(showId),
        sectionLabel: _sectionLabel,
      ),
    );
  }

  void _downloadEntriesForShow(String showId, String showName) {
    final grouped = _grouped();
    final exhibitorBuckets =
        grouped[showId] ?? const <String, List<Map<String, dynamic>>>{};

    if (exhibitorBuckets.isEmpty) {
      setState(() => _msg = 'No entries found to download for this show.');
      return;
    }

    String esc(dynamic value) => htmlEscape.convert((value ?? '').toString());

    int classRank(dynamic value) {
      final v = (value ?? '').toString().trim().toLowerCase();
      if (v.contains('senior') || v.contains('sr')) return 0;
      if (v.contains('intermediate') || v.contains('int')) return 1;
      if (v.contains('junior') || v.contains('jr')) return 2;
      return 99;
    }

    int sexRank(dynamic value) {
      final v = (value ?? '').toString().trim().toLowerCase();
      if (v == 'buck' || v == 'boar') return 0;
      if (v == 'doe' || v == 'sow') return 1;
      return 99;
    }

    int compareText(dynamic a, dynamic b) {
      return (a ?? '').toString().trim().toLowerCase().compareTo(
            (b ?? '').toString().trim().toLowerCase(),
          );
    }

    int compareEntries(Map<String, dynamic> a, Map<String, dynamic> b) {
      final sectionCmp = _sectionLabel(a['section_id']).toLowerCase().compareTo(
            _sectionLabel(b['section_id']).toLowerCase(),
          );
      if (sectionCmp != 0) return sectionCmp;

      final breedCmp = compareText(a['breed'], b['breed']);
      if (breedCmp != 0) return breedCmp;

      final varietyCmp = compareText(a['variety'], b['variety']);
      if (varietyCmp != 0) return varietyCmp;

      final classRankCmp =
          classRank(a['class_name']).compareTo(classRank(b['class_name']));
      if (classRankCmp != 0) return classRankCmp;

      final classCmp = compareText(a['class_name'], b['class_name']);
      if (classCmp != 0) return classCmp;

      final sexRankCmp = sexRank(a['sex']).compareTo(sexRank(b['sex']));
      if (sexRankCmp != 0) return sexRankCmp;

      final sexCmp = compareText(a['sex'], b['sex']);
      if (sexCmp != 0) return sexCmp;

      return compareText(a['tattoo'], b['tattoo']);
    }

    final exhibitorIds = exhibitorBuckets.keys.toList()
      ..sort(
        (a, b) => _exhibitorLabelById(a).toLowerCase().compareTo(
          _exhibitorLabelById(b).toLowerCase(),
        ),
      );

    final totalEntries = exhibitorBuckets.values.fold<int>(
      0,
      (sum, list) => sum + list.length,
    );

    final generatedAt = formatLocalDateTime(DateTime.now().toIso8601String());
    final closeAt = _parseTs(_showsById[showId]?['entry_close_at']);
    final deadlineText = closeAt == null
        ? 'Entry deadline not set'
        : 'Entry deadline: ${formatLocalDateTime(closeAt.toIso8601String())}';

    final buffer = StringBuffer();

    buffer.writeln('''
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>${esc(showName)} Entries</title>
  <style>
    @page { size: letter; margin: 0.45in; }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: Arial, Helvetica, sans-serif;
      color: #111827;
      background: #ffffff;
      font-size: 12px;
    }
    .header {
      border: 2px solid #0f2d52;
      border-radius: 12px;
      padding: 16px 18px;
      margin-bottom: 16px;
      background: #f8fafc;
    }
    .brand {
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 1.5px;
      color: #0f2d52;
      font-weight: 700;
      margin-bottom: 4px;
    }
    h1 {
      margin: 0;
      font-size: 24px;
      color: #0f2d52;
    }
    .subtitle {
      margin-top: 6px;
      color: #374151;
      font-size: 13px;
    }
    .summary {
      display: flex;
      gap: 10px;
      flex-wrap: wrap;
      margin-top: 12px;
    }
    .pill {
      border: 1px solid #cbd5e1;
      border-radius: 999px;
      padding: 6px 10px;
      background: #ffffff;
      font-weight: 700;
      color: #1f2937;
    }
    .notice {
      border-left: 5px solid #d4a623;
      padding: 10px 12px;
      margin: 0 0 16px 0;
      background: #fffbeb;
      color: #374151;
      line-height: 1.4;
    }
    .exhibitor {
      break-inside: avoid;
      page-break-inside: avoid;
      margin-bottom: 18px;
      border: 1px solid #d1d5db;
      border-radius: 12px;
      overflow: hidden;
    }
    .exhibitor-head {
      background: #0f2d52;
      color: #ffffff;
      padding: 10px 12px;
      display: flex;
      justify-content: space-between;
      gap: 12px;
      align-items: center;
      font-weight: 700;
    }
    .entry-count {
      font-size: 11px;
      background: rgba(255,255,255,.16);
      border-radius: 999px;
      padding: 4px 8px;
      white-space: nowrap;
    }
    table {
      width: 100%;
      border-collapse: collapse;
    }
    th {
      background: #e5e7eb;
      color: #111827;
      text-align: left;
      font-size: 10px;
      text-transform: uppercase;
      letter-spacing: .4px;
      padding: 7px 6px;
      border-bottom: 1px solid #9ca3af;
    }
    td {
      padding: 7px 6px;
      border-bottom: 1px solid #e5e7eb;
      vertical-align: top;
    }
    tr:last-child td { border-bottom: none; }
    tr:nth-child(even) td { background: #f9fafb; }
    .status-scratched {
      color: #991b1b;
      font-weight: 700;
    }
    .footer {
      margin-top: 18px;
      padding-top: 10px;
      border-top: 1px solid #d1d5db;
      color: #6b7280;
      font-size: 10px;
      display: flex;
      justify-content: space-between;
      gap: 12px;
    }
    @media print {
      .no-print { display: none; }
      body { font-size: 11px; }
      .exhibitor { break-inside: avoid; page-break-inside: avoid; }
    }
  </style>
</head>
<body>
  <div class="header">
    <div class="brand">RingMaster Show</div>
    <h1>${esc(showName)}</h1>
    <div class="subtitle">Exhibitor Entries Report</div>
    <div class="summary">
      <div class="pill">${exhibitorIds.length} exhibitor${exhibitorIds.length == 1 ? '' : 's'}</div>
      <div class="pill">$totalEntries entr${totalEntries == 1 ? 'y' : 'ies'}</div>
      <div class="pill">${esc(deadlineText)}</div>
    </div>
  </div>

  <div class="notice">
    Please review all entries carefully. If anything is incorrect, contact the show secretary before judging begins.
    This report is intended to match the check-in style used by show administration.
  </div>
''');

    for (final exhibitorId in exhibitorIds) {
      final exhibitorName = _exhibitorLabelById(exhibitorId);
      final entries = List<Map<String, dynamic>>.from(
        exhibitorBuckets[exhibitorId] ?? const [],
      )..sort(compareEntries);

      buffer.writeln('''
  <section class="exhibitor">
    <div class="exhibitor-head">
      <div>${esc(exhibitorName)}</div>
      <div class="entry-count">${entries.length} entr${entries.length == 1 ? 'y' : 'ies'}</div>
    </div>
    <table>
      <thead>
        <tr>
          <th>Section</th>
          <th>Animal</th>
          <th>Tattoo / Ear #</th>
          <th>Breed</th>
          <th>Variety</th>
          <th>Class</th>
          <th>Sex</th>
          <th>Status</th>
        </tr>
      </thead>
      <tbody>
''');

      for (final e in entries) {
        final rawStatus = (e['status'] ?? 'entered').toString().trim();
        final status = rawStatus.isEmpty ? 'entered' : rawStatus;
        final statusClass = status.toLowerCase() == 'scratched'
            ? ' class="status-scratched"'
            : '';

        buffer.writeln('''
        <tr>
          <td>${esc(_sectionLabel(e['section_id']))}</td>
          <td>${esc(e['animal_name'])}</td>
          <td>${esc(e['tattoo'])}</td>
          <td>${esc(e['breed'])}</td>
          <td>${esc(e['variety'])}</td>
          <td>${esc(e['class_name'])}</td>
          <td>${esc(e['sex'])}</td>
          <td$statusClass>${esc(status)}</td>
        </tr>
''');
      }

      buffer.writeln('''
      </tbody>
    </table>
  </section>
''');
    }

    buffer.writeln('''
  <div class="footer">
    <div>Generated by RingMaster Show</div>
    <div>$generatedAt</div>
  </div>
  <script>
    window.addEventListener('load', function () {
      setTimeout(function () { window.print(); }, 350);
    });
  </script>
</body>
</html>
''');

    final blob = html.Blob([buffer.toString()], 'text/html;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.window.open(url, '_blank');

    Future.delayed(const Duration(seconds: 5), () {
      html.Url.revokeObjectUrl(url);
    });
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped();

    final visibleShowIds = grouped.keys
        .where((showId) => !_hideShowAfter48h(showId))
        .toList()
      ..sort((a, b) {
        final aDate = _showStartDate(a);
        final bDate = _showStartDate(b);

        if (aDate != null && bDate != null) {
          return aDate.compareTo(bDate);
        } else if (aDate != null) {
          return -1;
        } else if (bDate != null) {
          return 1;
        }

        return _showTitle(a).compareTo(_showTitle(b));
      });

    return RingMasterPageShell(
      title: 'RingMaster Show',
      subtitle: 'My Entries',
      showBackButton: true,
      useScrollView: false,
      actions: [
        IconButton(
          tooltip: AppSession.isSupportMode
              ? 'Animals disabled in support mode'
              : 'Animals',
          icon: const Icon(Icons.pets),
          onPressed: AppSession.isSupportMode
              ? null
              : () => _openAnimals(context),
        ),
        IconButton(
          tooltip: AppSession.isSupportMode
              ? 'Account disabled in support mode'
              : 'Account',
          icon: const Icon(Icons.manage_accounts),
          onPressed: AppSession.isSupportMode
              ? null
              : () => _openAccount(context),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : visibleShowIds.isEmpty
              ? const RMEmptyState(
                  title: 'No recent entries',
                  subtitle: 'Shows disappear here 48 hours after their show date.',
                  icon: Icons.receipt_long_outlined,
                )
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    if (AppSession.isSupportMode)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: RMCard(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Icon(Icons.lock_outline, color: Colors.orange),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'You are viewing this account in support mode. Entry editing is disabled until you exit support mode.',
                                  style: TextStyle(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_msg != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: RMCard(
                          child: Text(
                            _msg!,
                            style: TextStyle(
                              color: _msg!.toLowerCase().contains('failed') ||
                                      _msg!.toLowerCase().contains('error') ||
                                      _msg!.toLowerCase().contains('required') ||
                                      _msg!.toLowerCase().contains('locked') ||
                                      _msg!.toLowerCase().contains('disabled')
                                  ? AppColors.danger
                                  : AppColors.success,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    for (final showId in visibleShowIds) ...[
                      _ShowExpansionCard(
                        title: _showTitle(showId),
                        showId: showId,
                        onBreedCounts: _openBreedCounts,
                        onDownloadEntries: _downloadEntriesForShow,
                        onJudgeOrder: _openJudgeOrder,
                        judgeOrderPublished: _judgeOrderPublishedForShow(showId),
                        deadlinePassed: _deadlinePassedForShow(showId),
                        closeAt: _parseTs(_showsById[showId]?['entry_close_at']),
                        readOnly: AppSession.isSupportMode,
                        exhibitorBuckets: grouped[showId] ?? const {},
                        exhibitorLabel: _exhibitorLabelById,
                        sectionLabel: _sectionLabel,
                        onEdit: _editEntry,
                        onScratch: _scratchEntry,
                        onRestore: _restoreEntry,
                        initiallyExpanded: _expandedShowIds.contains(showId),
                        onExpandedChanged: (expanded) {
                          setState(() {
                            if (expanded) {
                              _expandedShowIds.add(showId);
                            } else {
                              _expandedShowIds.remove(showId);
                            }
                          });
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                  ],
                ),
    );
  }
}

class _ShowExpansionCard extends StatelessWidget {
  final String title;
  final String showId;
  final bool deadlinePassed;
  final DateTime? closeAt;
  final bool readOnly;
  final Map<String, List<Map<String, dynamic>>> exhibitorBuckets;
  final String Function(String? exhibitorId) exhibitorLabel;
  final String Function(String? sectionId) sectionLabel;
  final Future<void> Function(Map<String, dynamic> entry) onEdit;
  final Future<void> Function(Map<String, dynamic> entry) onScratch;
  final Future<void> Function(Map<String, dynamic> entry) onRestore;
  final bool initiallyExpanded;
  final ValueChanged<bool> onExpandedChanged;
  final void Function(BuildContext context, String showId, String showName) onBreedCounts;
  final void Function(String showId, String showName) onDownloadEntries;
  final void Function(BuildContext context, String showId, String showName) onJudgeOrder;
  final bool judgeOrderPublished;

  const _ShowExpansionCard({
    required this.title,
    required this.showId,
    required this.onBreedCounts,
    required this.onDownloadEntries,
    required this.onJudgeOrder,
    required this.judgeOrderPublished,
    required this.deadlinePassed,
    required this.closeAt,
    required this.readOnly,
    required this.exhibitorBuckets,
    required this.exhibitorLabel,
    required this.sectionLabel,
    required this.onEdit,
    required this.onScratch,
    required this.onRestore,
    required this.initiallyExpanded,
    required this.onExpandedChanged,
  });

  String _safeLower(dynamic value) {
    return (value ?? '').toString().trim().toLowerCase();
  }

  int _toInt(dynamic value, [int fallback = 9999]) {
    if (value == null) return fallback;
    if (value is int) return value;
    return int.tryParse(value.toString()) ?? fallback;
  }

  int _sectionKindRank(dynamic value) {
    switch (_safeLower(value)) {
      case 'open':
        return 0;
      case 'youth':
        return 1;
      default:
        return 99;
    }
  }

  int _classRank(dynamic value) {
    final v = _safeLower(value);
    if (v.contains('senior') || v.contains('sr')) return 0;
    if (v.contains('intermediate') || v.contains('int')) return 1;
    if (v.contains('junior') || v.contains('jr')) return 2;
    return 99;
  }

  int _sexRank(dynamic value) {
    final v = _safeLower(value);
    if (v == 'buck' || v == 'boar') return 0;
    if (v == 'doe' || v == 'sow') return 1;
    return 99;
  }

  int _compareEntriesForShowOrder(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final sectionA = sectionLabel(a['section_id']);
    final sectionB = sectionLabel(b['section_id']);

    final sectionKindCmp = _sectionKindRank(sectionA).compareTo(
      _sectionKindRank(sectionB),
    );
    if (sectionKindCmp != 0) return sectionKindCmp;

    final sectionLabelCmp = sectionA.toLowerCase().compareTo(
          sectionB.toLowerCase(),
        );
    if (sectionLabelCmp != 0) return sectionLabelCmp;

    final breedSortCmp = _toInt(a['breed_sort_order']).compareTo(
      _toInt(b['breed_sort_order']),
    );
    if (breedSortCmp != 0) return breedSortCmp;

    final breedCmp = _safeLower(a['breed']).compareTo(_safeLower(b['breed']));
    if (breedCmp != 0) return breedCmp;

    final groupSortCmp = _toInt(a['group_sort_order']).compareTo(
      _toInt(b['group_sort_order']),
    );
    if (groupSortCmp != 0) return groupSortCmp;

    final varietySortCmp = _toInt(a['variety_sort_order']).compareTo(
      _toInt(b['variety_sort_order']),
    );
    if (varietySortCmp != 0) return varietySortCmp;

    final varietyCmp = _safeLower(a['variety']).compareTo(
      _safeLower(b['variety']),
    );
    if (varietyCmp != 0) return varietyCmp;

    final classSortCmp = _toInt(a['class_sort_order']).compareTo(
      _toInt(b['class_sort_order']),
    );
    if (classSortCmp != 0) return classSortCmp;

    final classRankCmp = _classRank(a['class_name']).compareTo(
      _classRank(b['class_name']),
    );
    if (classRankCmp != 0) return classRankCmp;

    final classCmp = _safeLower(a['class_name']).compareTo(
      _safeLower(b['class_name']),
    );
    if (classCmp != 0) return classCmp;

    final sexRankCmp = _sexRank(a['sex']).compareTo(_sexRank(b['sex']));
    if (sexRankCmp != 0) return sexRankCmp;

    final sexCmp = _safeLower(a['sex']).compareTo(_safeLower(b['sex']));
    if (sexCmp != 0) return sexCmp;

    return _safeLower(a['tattoo']).compareTo(_safeLower(b['tattoo']));
  }

  String _safeLabel(dynamic value, String fallback) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  Map<String, Map<String, Map<String, Map<String, List<Map<String, dynamic>>>>>>
      _groupEntriesForDisplay(List<Map<String, dynamic>> entries) {
    final grouped =
        <String, Map<String, Map<String, Map<String, List<Map<String, dynamic>>>>>>{};

    final sorted = List<Map<String, dynamic>>.from(entries)
      ..sort(_compareEntriesForShowOrder);

    for (final e in sorted) {
      final breed = _safeLabel(e['breed'], '(No Breed)');
      final variety = _safeLabel(e['variety'], '(No Variety)');
      final className = _safeLabel(e['class_name'], '(No Class)');
      final sex = _safeLabel(e['sex'], '(No Sex)');

      grouped.putIfAbsent(breed, () => {});
      grouped[breed]!.putIfAbsent(variety, () => {});
      grouped[breed]![variety]!.putIfAbsent(className, () => {});
      grouped[breed]![variety]![className]!.putIfAbsent(sex, () => []);
      grouped[breed]![variety]![className]![sex]!.add(e);
    }

    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final exhibitorIds = exhibitorBuckets.keys.toList()
      ..sort(
        (a, b) => exhibitorLabel(a).toLowerCase().compareTo(
          exhibitorLabel(b).toLowerCase(),
        ),
      );

    final deadlineText = closeAt == null
        ? '(deadline not set)'
        : formatLocalDateTime(closeAt!.toIso8601String());

    final totalEntries =
        exhibitorBuckets.values.fold<int>(0, (sum, list) => sum + list.length);

    return RMCard(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          onExpansionChanged: onExpandedChanged,
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
          title: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                RMBadge(
                  text: '$totalEntries entr${totalEntries == 1 ? 'y' : 'ies'}',
                  icon: Icons.receipt_long,
                ),
                RMBadge(
                  text: deadlinePassed
                      ? 'Deadline Passed'
                      : 'Deadline: $deadlineText',
                  icon: Icons.event_available,
                  danger: deadlinePassed,
                  success: !deadlinePassed,
                ),
              ],
            ),
          ),
          children: [
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                OutlinedButton.icon(
                  onPressed: () => onBreedCounts(context, showId, title),
                  icon: const Icon(Icons.bar_chart),
                  label: const Text('Breed Counts'),
                ),
                if (judgeOrderPublished)
                  OutlinedButton.icon(
                    onPressed: () => onJudgeOrder(context, showId, title),
                    icon: const Icon(Icons.assignment_ind_outlined),
                    label: const Text('Judge Order'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => onDownloadEntries(showId, title),
                  icon: const Icon(Icons.download),
                  label: const Text('Download Entries'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            for (final exId in exhibitorIds) ...[
              Builder(
                builder: (context) {
                  final groupedEntries =
                      _groupEntriesForDisplay(exhibitorBuckets[exId]!);

                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          exhibitorLabel(exId),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ...groupedEntries.entries.map((breedEntry) {
                          final breed = breedEntry.key;
                          final varieties = breedEntry.value;

                          final varietyKeys = varieties.keys.toList()
                            ..sort((a, b) =>
                                a.toLowerCase().compareTo(b.toLowerCase()));

                          return Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  breed,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                ...varietyKeys.map((variety) {
                                  final classes = varieties[variety]!;
                                  final classKeys = classes.keys.toList()
                                    ..sort((a, b) => a.toLowerCase()
                                        .compareTo(b.toLowerCase()));

                                  return Padding(
                                    padding: const EdgeInsets.only(
                                      left: 12,
                                      bottom: AppSpacing.sm,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          variety,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        const SizedBox(height: 6),
                                        ...classKeys.map((className) {
                                          final sexes = classes[className]!;
                                          final sexKeys = sexes.keys.toList()
                                            ..sort((a, b) => a.toLowerCase()
                                                .compareTo(b.toLowerCase()));

                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              left: 12,
                                              bottom: 8,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  className,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                ),
                                                const SizedBox(height: 4),
                                                ...sexKeys.map((sex) {
                                                  final entries = sexes[sex]!;
                                                  return Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                      left: 12,
                                                      bottom: 8,
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          sex,
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .bodyMedium,
                                                        ),
                                                        const SizedBox(height: 6),
                                                        ...entries.map((e) {
                                                          final section =
                                                              sectionLabel(
                                                                  e['section_id']);
                                                          final tattoo =
                                                              (e['tattoo'] ?? '')
                                                                  .toString()
                                                                  .trim();
                                                          final rawStatus =
                                                              (e['status'] ?? '')
                                                                  .toString()
                                                                  .trim();
                                                          final normalizedStatus =
                                                              rawStatus.isEmpty
                                                                  ? 'entered'
                                                                  : rawStatus;
                                                          final scratched =
                                                              normalizedStatus
                                                                      .toLowerCase() ==
                                                                  'scratched';

                                                          final canEdit =
                                                              !readOnly &&
                                                                  !deadlinePassed &&
                                                                  !scratched;
                                                          final canScratch =
                                                              !readOnly &&
                                                                  !scratched;
                                                          final canRestore =
                                                              !readOnly &&
                                                                  scratched &&
                                                                  !deadlinePassed;

                                                          return Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .only(
                                                              bottom: AppSpacing
                                                                  .sm,
                                                            ),
                                                            child: Material(
                                                              color: Colors.white,
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                AppRadius.sm,
                                                              ),
                                                              child: InkWell(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                  AppRadius.sm,
                                                                ),
                                                                onTap: canEdit
                                                                    ? () => onEdit(e)
                                                                    : null,
                                                                child: Container(
                                                                  decoration:
                                                                      BoxDecoration(
                                                                    color: Colors
                                                                        .transparent,
                                                                    borderRadius:
                                                                        BorderRadius
                                                                            .circular(
                                                                      AppRadius.sm,
                                                                    ),
                                                                    border: Border.all(
                                                                      color: canEdit
                                                                          ? Theme.of(context).colorScheme.primary.withOpacity(0.35)
                                                                          : Colors.grey.shade200,
                                                                    ),
                                                                  ),
                                                                  child: Padding(
                                                                    padding:
                                                                        const EdgeInsets
                                                                            .fromLTRB(
                                                                      12,
                                                                      8,
                                                                      8,
                                                                      8,
                                                                    ),
                                                            child: Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                Row(
                                                                  crossAxisAlignment:
                                                                      CrossAxisAlignment
                                                                          .start,
                                                                  children: [
                                                                    Expanded(
                                                                      child:
                                                                          Column(
                                                                        crossAxisAlignment:
                                                                            CrossAxisAlignment.start,
                                                                        children: [
                                                                          Text(
                                                                            tattoo.isEmpty ? '(No tattoo)' : tattoo,
                                                                            style: TextStyle(
                                                                              fontWeight: FontWeight.w600,
                                                                              decoration: scratched ? TextDecoration.lineThrough : null,
                                                                            ),
                                                                          ),
                                                                          const SizedBox(height: 6),
                                                                          Text(
                                                                            'Status: $normalizedStatus\nSection: $section',
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ),
                                                                    if (readOnly)
                                                                      const Tooltip(
                                                                        message:
                                                                            'Actions are disabled while viewing in support mode',
                                                                        child:
                                                                            Padding(
                                                                          padding: EdgeInsets.only(left: 8),
                                                                          child: Icon(
                                                                            Icons.lock_outline,
                                                                            color: Colors.grey,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                  ],
                                                                ),
                                                                if (!readOnly &&
                                                                    (canEdit ||
                                                                        canScratch ||
                                                                        canRestore)) ...[
                                                                  const SizedBox(
                                                                      height:
                                                                          8),
                                                                  Wrap(
                                                                    spacing:
                                                                        8,
                                                                    runSpacing:
                                                                        8,
                                                                    children: [
                                                                      if (canEdit)
                                                                        FilledButton.icon(
                                                                          onPressed: () => onEdit(e),
                                                                          icon: const Icon(Icons.edit, size: 18),
                                                                          label: const Text('Edit Entry'),
                                                                        ),
                                                                      if (canScratch)
                                                                        OutlinedButton.icon(
                                                                          onPressed: () => onScratch(e),
                                                                          icon: const Icon(Icons.remove_circle_outline, size: 18),
                                                                          label: const Text('Scratch'),
                                                                        ),
                                                                      if (canRestore)
                                                                        OutlinedButton.icon(
                                                                          onPressed: () => onRestore(e),
                                                                          icon: const Icon(Icons.undo, size: 18),
                                                                          label: const Text('Restore'),
                                                                        ),
                                                                    ],
                                                                  ),
                                                                ] else if (readOnly) ...[
                                                                  const SizedBox(height: 8),
                                                                  Text(
                                                                    'Editing is disabled while viewing in support mode.',
                                                                    style: Theme.of(context)
                                                                        .textTheme
                                                                        .bodySmall
                                                                        ?.copyWith(
                                                                          color: AppColors.muted,
                                                                          fontStyle: FontStyle.italic,
                                                                        ),
                                                                  ),
                                                                ] else if (deadlinePassed && !scratched) ...[
                                                                  const SizedBox(height: 8),
                                                                  Text(
                                                                    'Editing is locked because the entry deadline has passed.',
                                                                    style: Theme.of(context)
                                                                        .textTheme
                                                                        .bodySmall
                                                                        ?.copyWith(
                                                                          color: AppColors.muted,
                                                                          fontStyle: FontStyle.italic,
                                                                        ),
                                                                  ),
                                                                ],
                                                              ],
                                                            ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          );
                                                        }),
                                                      ],
                                                    ),
                                                  );
                                                }),
                                              ],
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        ),
      ),
    );
  }
}

class _EditEntryResult {
  final String animalId;
  final String className;
  final String sectionId;
  final String exhibitorId;

  _EditEntryResult({
    required this.animalId,
    required this.className,
    required this.sectionId,
    required this.exhibitorId,
  });
}

class _EditEntryDialogV2 extends StatefulWidget {
  final String initialAnimalId;
  final String initialClassName;
  final String initialSectionId;
  final String initialExhibitorId;
  final List<Map<String, dynamic>> animals;
  final List<Map<String, dynamic>> exhibitors;
  final List<Map<String, dynamic>> sections;
  final String Function(String? sectionId) sectionLabel;
  final Future<void> Function() onAddNewAnimal;
  final Future<List<Map<String, dynamic>>> Function() reloadAnimals;

  const _EditEntryDialogV2({
    required this.initialAnimalId,
    required this.initialClassName,
    required this.initialSectionId,
    required this.initialExhibitorId,
    required this.animals,
    required this.exhibitors,
    required this.sections,
    required this.sectionLabel,
    required this.onAddNewAnimal,
    required this.reloadAnimals,
  });

  @override
  State<_EditEntryDialogV2> createState() => _EditEntryDialogV2State();
}

class _EditEntryDialogV2State extends State<_EditEntryDialogV2> {
  late List<Map<String, dynamic>> _animals;
  late String _animalId;
  late String _sectionId;
  late String _exhibitorId;
  late TextEditingController _classCtrl;
  String? _dialogError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _animals = widget.animals;
    _animalId = widget.initialAnimalId;
    _sectionId = widget.initialSectionId;
    _exhibitorId = widget.initialExhibitorId;
    _classCtrl = TextEditingController(text: widget.initialClassName);
  }

  @override
  void dispose() {
    _classCtrl.dispose();
    super.dispose();
  }

  String _animalLabel(Map<String, dynamic> a) {
    final tattoo = (a['tattoo'] ?? '').toString().trim();
    final name = (a['name'] ?? '').toString().trim();
    final breed = (a['breed'] ?? '').toString().trim();
    final variety = (a['variety'] ?? '').toString().trim();
    final sex = (a['sex'] ?? '').toString().trim();
    final top = tattoo.isNotEmpty
        ? tattoo
        : (name.isNotEmpty ? name : (a['id'] ?? '').toString());

    final details = [breed, variety, sex]
        .where((part) => part.trim().isNotEmpty)
        .join(' • ');

    return details.isEmpty ? top : '$top — $details';
  }

  String _exhibitorLabel(Map<String, dynamic> e) {
    final showingName = (e['showing_name'] ?? '').toString().trim();
    if (showingName.isNotEmpty) return showingName;

    final displayName = (e['display_name'] ?? '').toString().trim();
    if (displayName.isNotEmpty) return displayName;

    return (e['id'] ?? '').toString();
  }

  bool _isYouthSectionId(String sectionId) {
    final match = widget.sections.where(
      (s) => (s['id'] ?? '').toString() == sectionId,
    );
    if (match.isEmpty) return false;
    return (match.first['kind'] ?? '').toString().trim().toLowerCase() == 'youth';
  }

  bool _isYouthExhibitor(Map<String, dynamic> e) {
    // The exhibitors table currently does not expose an is_youth column here.
    // Treat exhibitors as selectable and let the save/update rules validate.
    return true;
  }

  Future<void> _addNewAnimal() async {
    setState(() => _busy = true);
    try {
      await widget.onAddNewAnimal();
      final refreshed = await widget.reloadAnimals();
      if (!mounted) return;

      setState(() {
        _animals = refreshed;
        final exists =
            _animals.any((a) => (a['id'] ?? '').toString() == _animalId);
        if (!exists && _animals.isNotEmpty) {
          _animalId = (_animals.first['id'] ?? '').toString();
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasSelected =
        _animals.any((a) => (a['id'] ?? '').toString() == _animalId);
    final hasSelectedSection = widget.sections.any(
      (s) => (s['id'] ?? '').toString() == _sectionId,
    );
    final hasSelectedExhibitor = widget.exhibitors.any(
      (e) => (e['id'] ?? '').toString() == _exhibitorId,
    );

    return AlertDialog(
      title: const Text('Edit Entry'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_dialogError != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: AppColors.danger.withOpacity(0.35),
                    ),
                  ),
                  child: Text(
                    _dialogError!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              DropdownButtonFormField<String>(
                value: hasSelectedSection ? _sectionId : null,
                items: widget.sections.map((s) {
                  final id = (s['id'] ?? '').toString();
                  return DropdownMenuItem<String>(
                    value: id,
                    child: Text(widget.sectionLabel(id)),
                  );
                }).toList(),
                onChanged: _busy
                    ? null
                    : (v) {
                        if (v == null) return;
                        setState(() {
                          _sectionId = v;
                        });
                      },
                decoration: const InputDecoration(
                  labelText: 'Show / Section',
                  helperText: 'Move this entry to another open/youth show section.',
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: hasSelectedExhibitor ? _exhibitorId : null,
                items: widget.exhibitors.map((e) {
                  final id = (e['id'] ?? '').toString();
                  final label = _exhibitorLabel(e);

                  return DropdownMenuItem<String>(
                    value: id,
                    child: Text(label),
                  );
                }).toList(),
                onChanged: _busy
                    ? null
                    : (v) {
                        if (v == null) return;
                        setState(() => _exhibitorId = v);
                      },
                decoration: const InputDecoration(
                  labelText: 'Exhibitor',
                  helperText: 'Move this entry to another exhibitor on your account.',
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: hasSelected ? _animalId : null,
                isExpanded: true,
                items: _animals.map((a) {
                  final id = (a['id'] ?? '').toString();
                  return DropdownMenuItem<String>(
                    value: id,
                    child: Text(
                      _animalLabel(a),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  );
                }).toList(),
                onChanged: _busy
                    ? null
                    : (v) => setState(() {
                          _animalId = v ?? _animalId;
                          _dialogError = null;
                        }),
                decoration: const InputDecoration(
                  labelText: 'Animal',
                  helperText: 'Swap to an existing animal from My Animals.',
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy ? null : _addNewAnimal,
                  icon: const Icon(Icons.add),
                  label: const Text('Add new animal'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _classCtrl,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Class (required)',
                  hintText: 'Example: Jr Buck, Sr Doe, Int Buck, Open Sow',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy
              ? null
              : () {
                  final hasValidAnimal = _animals.any(
                    (a) => (a['id'] ?? '').toString() == _animalId,
                  );
                  final hasValidSection = widget.sections.any(
                    (s) => (s['id'] ?? '').toString() == _sectionId,
                  );
                  final hasValidExhibitor = widget.exhibitors.any(
                    (e) => (e['id'] ?? '').toString() == _exhibitorId,
                  );

                  if (!hasValidSection) {
                    setState(() => _dialogError = 'Select a show / section.');
                    return;
                  }

                  if (!hasValidExhibitor) {
                    setState(() => _dialogError = 'Select an exhibitor.');
                    return;
                  }

                  if (!hasValidAnimal) {
                    setState(() => _dialogError = 'Select an animal.');
                    return;
                  }

                  if (_classCtrl.text.trim().isEmpty) {
                    setState(() => _dialogError = 'Class is required.');
                    return;
                  }

                  Navigator.pop(
                    context,
                    _EditEntryResult(
                      animalId: _animalId,
                      className: _classCtrl.text,
                      sectionId: _sectionId,
                      exhibitorId: _exhibitorId,
                    ),
                  );
                },
          child: Text(_busy ? 'Working…' : 'Save'),
        ),
      ],
    );
  }
}
// --- Judge Order Dialog and supporting classes ---

class _JudgeOrderDialog extends StatefulWidget {
  final String showId;
  final String showName;
  final String publishedAt;
  final String Function(String? sectionId) sectionLabel;

  const _JudgeOrderDialog({
    required this.showId,
    required this.showName,
    required this.publishedAt,
    required this.sectionLabel,
  });

  @override
  State<_JudgeOrderDialog> createState() => _JudgeOrderDialogState();
}

class _JudgeOrderDialogState extends State<_JudgeOrderDialog> {
  late Future<List<_JudgeOrderRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadJudgeOrder();
  }

  Future<List<_JudgeOrderRow>> _loadJudgeOrder() async {
    final assignmentRows = await supabase
        .from('show_judging_assignments')
        .select(
          'id,section_id,table_number,sort_order,breed_id,variety_key,judge_id,is_judge_change,notes',
        )
        .eq('show_id', widget.showId)
        .order('table_number', ascending: true)
        .order('sort_order', ascending: true);

    final assignments = (assignmentRows as List)
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();

    final sectionRows = await supabase
        .from('show_sections')
        .select('id,display_name,kind,letter,sort_order')
        .eq('show_id', widget.showId)
        .order('sort_order', ascending: true);

    final sectionsById = <String, Map<String, dynamic>>{};
    for (final raw in sectionRows as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final id = (row['id'] ?? '').toString().trim();
      if (id.isNotEmpty) sectionsById[id] = row;
    }

    String formatSectionLabel(Map<String, dynamic> section) {
      final displayName = (section['display_name'] ?? '').toString().trim();
      if (displayName.isNotEmpty) return displayName;

      final kind = (section['kind'] ?? '').toString().trim();
      final letter = (section['letter'] ?? '').toString().trim();

      if (kind.isNotEmpty && letter.isNotEmpty) {
        return '${kind[0].toUpperCase()}${kind.substring(1)} $letter';
      }

      if (letter.isNotEmpty) return 'Show $letter';
      return 'Section';
    }

    String? inferredLetterFromAssignment(Map<String, dynamic> assignment) {
      final valuesToCheck = <String>[
        (assignment['breed_id'] ?? '').toString().trim(),
        (assignment['variety_key'] ?? '').toString().trim(),
        (assignment['notes'] ?? '').toString().trim(),
      ];

      for (final value in valuesToCheck) {
        if (value.isEmpty) continue;

        final pipeParts = value.split('|');
        if (pipeParts.length > 1) {
          final possibleLetter = pipeParts.first.trim();
          if (possibleLetter.length <= 3 && RegExp(r'^[A-Za-z]+$').hasMatch(possibleLetter)) {
            return possibleLetter.toUpperCase();
          }
        }

        final match = RegExp(r'\b(?:show\s*)?([A-Za-z])\b', caseSensitive: false)
            .firstMatch(value);
        if (match != null) return match.group(1)!.toUpperCase();
      }

      return null;
    }

    String? inferredKindFromAssignment(Map<String, dynamic> assignment) {
      final haystack = [
        assignment['breed_id'],
        assignment['variety_key'],
        assignment['notes'],
      ].map((value) => (value ?? '').toString().toLowerCase()).join(' ');

      if (haystack.contains('youth')) return 'youth';
      if (haystack.contains('open')) return 'open';
      return null;
    }

    String showLabelForAssignment(Map<String, dynamic> assignment) {
      final sectionId = (assignment['section_id'] ?? '').toString().trim();

      if (sectionId.isNotEmpty) {
        final section = sectionsById[sectionId];
        if (section != null) {
          return formatSectionLabel(section);
        }

        final parentLabel = widget.sectionLabel(sectionId);
        if (parentLabel.trim().isNotEmpty && parentLabel != 'Section') {
          return parentLabel;
        }
      }

      final inferredLetter = inferredLetterFromAssignment(assignment);
      final inferredKind = inferredKindFromAssignment(assignment);

      if (inferredLetter != null) {
        final matchingSections = sectionsById.values.where((section) {
          final sectionLetter = (section['letter'] ?? '').toString().trim().toUpperCase();
          final sectionKind = (section['kind'] ?? '').toString().trim().toLowerCase();

          if (sectionLetter != inferredLetter) return false;
          if (inferredKind != null && sectionKind != inferredKind) return false;
          return true;
        }).toList();

        if (matchingSections.length == 1) {
          return formatSectionLabel(matchingSections.first);
        }

        if (matchingSections.isNotEmpty) {
          matchingSections.sort((a, b) {
            int kindRank(Map<String, dynamic> section) {
              final kind = (section['kind'] ?? '').toString().trim().toLowerCase();
              if (kind == 'open') return 0;
              if (kind == 'youth') return 1;
              return 99;
            }

            final kindCmp = kindRank(a).compareTo(kindRank(b));
            if (kindCmp != 0) return kindCmp;

            final aSort = int.tryParse((a['sort_order'] ?? '').toString()) ?? 9999;
            final bSort = int.tryParse((b['sort_order'] ?? '').toString()) ?? 9999;
            return aSort.compareTo(bSort);
          });

          return formatSectionLabel(matchingSections.first);
        }
      }

      if (sectionsById.length == 1) {
        return formatSectionLabel(sectionsById.values.first);
      }

      return inferredLetter == null ? 'Show not set' : 'Show $inferredLetter';
    }

    final judgeIds = assignments
        .map((row) => (row['judge_id'] ?? '').toString().trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final judgesById = <String, Map<String, dynamic>>{};
    if (judgeIds.isNotEmpty) {
      final judgeRows = await supabase
          .from('judges')
          .select('id,display_name,name,first_name,last_name,arba_judge_number')
          .inFilter('id', judgeIds);

      for (final raw in judgeRows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = (row['id'] ?? '').toString();
        if (id.isNotEmpty) judgesById[id] = row;
      }
    }

    String judgeLabel(String? judgeId) {
      final id = (judgeId ?? '').trim();
      if (id.isEmpty) return 'Judge not set';

      final judge = judgesById[id];
      if (judge == null) return 'Judge not set';

      final displayName = (judge['display_name'] ?? '').toString().trim();
      final name = (judge['name'] ?? '').toString().trim();
      final first = (judge['first_name'] ?? '').toString().trim();
      final last = (judge['last_name'] ?? '').toString().trim();
      final number = (judge['arba_judge_number'] ?? '').toString().trim();

      final baseName = displayName.isNotEmpty
          ? displayName
          : name.isNotEmpty
              ? name
              : [first, last].where((part) => part.isNotEmpty).join(' ');

      if (baseName.trim().isEmpty) return 'Judge not set';
      if (number.isNotEmpty && !baseName.contains('#$number')) {
        return '$baseName (#$number)';
      }

      return baseName;
    }

    final rows = <_JudgeOrderRow>[];
    String? activeJudgeId;

    for (final assignment in assignments) {
      final isJudgeChange = assignment['is_judge_change'] == true ||
          (assignment['breed_id'] ?? '').toString() == '__judge_change__';

      if (isJudgeChange) {
        final judgeId = (assignment['judge_id'] ?? '').toString().trim();
        if (judgeId.isNotEmpty) activeJudgeId = judgeId;
        continue;
      }

      final breed = (assignment['breed_id'] ?? '').toString().trim();
      final cleanBreed = breed.contains('|')
          ? breed.split('|').last.trim()
          : breed;
      if (cleanBreed.isEmpty || cleanBreed == '__judge_change__') continue;

      final variety = (assignment['variety_key'] ?? '').toString().trim();

      int parseIntValue(dynamic value, int fallback) {
        if (value is int) return value;
        if (value is num) return value.toInt();
        return int.tryParse((value ?? '').toString().trim()) ?? fallback;
      }

      final tableNumber = parseIntValue(assignment['table_number'], 0);
      final sortOrder = parseIntValue(assignment['sort_order'], 9999);

      rows.add(
        _JudgeOrderRow(
          tableNumber: tableNumber,
          showLabel: showLabelForAssignment(assignment),
          judgeLabel: judgeLabel(activeJudgeId),
          breed: cleanBreed,
          variety: variety,
          sortOrder: sortOrder,
        ),
      );
    }

    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = screenSize.width < 760 ? screenSize.width - 24 : 720.0;
    final dialogHeight = screenSize.height < 720 ? screenSize.height * 0.86 : 640.0;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      titlePadding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
      contentPadding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      title: Text(
        '${widget.showName} Judge Order',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: screenSize.width < 520 ? 20 : null,
            ),
      ),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: FutureBuilder<List<_JudgeOrderRow>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Judge order failed to load: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              );
            }

            final rows = snapshot.data ?? const <_JudgeOrderRow>[];
            if (rows.isEmpty) {
              return const Center(
                child: Text('No judge order has been added yet.'),
              );
            }

            final groupedByTable = <int, List<_JudgeOrderRow>>{};
            for (final row in rows) {
              groupedByTable.putIfAbsent(row.tableNumber, () => <_JudgeOrderRow>[]);
              groupedByTable[row.tableNumber]!.add(row);
            }

            final tableNumbers = groupedByTable.keys.toList()..sort();

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.publishedAt.trim().isNotEmpty) ...[
                        Text(
                          'Published ${widget.publishedAt}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      Text(
                        'Assignments may change at the show table.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
                for (final tableNumber in tableNumbers) ...[
                  SliverToBoxAdapter(
                    child: _JudgeOrderTableBlock(
                      tableNumber: tableNumber,
                      rows: List<_JudgeOrderRow>.from(
                        groupedByTable[tableNumber] ?? const <_JudgeOrderRow>[],
                      )..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 10)),
                ],
              ],
            );
          },
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _JudgeOrderTableBlock extends StatelessWidget {
  final int tableNumber;
  final List<_JudgeOrderRow> rows;

  const _JudgeOrderTableBlock({
    required this.tableNumber,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    final label = tableNumber <= 0 ? 'Table' : 'Table $tableNumber';
    final sortedRows = List<_JudgeOrderRow>.from(rows)
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          ...sortedRows.map((row) {
            final breedLabel = row.variety.isEmpty
                ? row.breed
                : '${row.breed} • ${row.variety}';

            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    breedLabel,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 10,
                    runSpacing: 2,
                    children: [
                      Text('Show: ${row.showLabel}'),
                      Text('Judge: ${row.judgeLabel}'),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _JudgeOrderRow {
  final int tableNumber;
  final String showLabel;
  final String judgeLabel;
  final String breed;
  final String variety;
  final int sortOrder;

  const _JudgeOrderRow({
    required this.tableNumber,
    required this.showLabel,
    required this.judgeLabel,
    required this.breed,
    required this.variety,
    required this.sortOrder,
  });
}