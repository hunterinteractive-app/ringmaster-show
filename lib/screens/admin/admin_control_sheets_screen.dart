// lib/screens/admin/admin_control_sheets_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

final supabase = Supabase.instance.client;

class AdminControlSheetsScreen extends StatefulWidget {
  final String showId;
  final String showName;

  const AdminControlSheetsScreen({
    super.key,
    required this.showId,
    required this.showName,
  });

  @override
  State<AdminControlSheetsScreen> createState() => _AdminControlSheetsScreenState();
}

class _AdminControlSheetsScreenState extends State<AdminControlSheetsScreen> {
  bool _loading = true;
  bool _building = false;
  String? _msg;

  List<Map<String, dynamic>> _sections = [];
  String? _selectedSectionId;
  bool _includeScratched = false;

  // show header bits
  Map<String, dynamic>? _showRow;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      _showRow = await supabase
          .from('shows')
          .select('id,name,location_name,start_date,end_date')
          .eq('id', widget.showId)
          .single();

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
        final asoI = (aso is int) ? aso : int.tryParse(aso?.toString() ?? '') ?? 9999;
        final bsoI = (bso is int) ? bso : int.tryParse(bso?.toString() ?? '') ?? 9999;
        final soCmp = asoI.compareTo(bsoI);
        if (soCmp != 0) return soCmp;

        final al = (a['letter'] ?? '').toString().toUpperCase();
        final bl = (b['letter'] ?? '').toString().toUpperCase();
        return al.compareTo(bl);
      });

      if (_sections.isNotEmpty) {
        _selectedSectionId ??= _sections.first['id']?.toString();
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

  String _sectionLabel(Map<String, dynamic> s) {
    final dn = (s['display_name'] ?? '').toString().trim();
    final letter = (s['letter'] ?? '').toString().trim();
    if (dn.isNotEmpty) return dn; // e.g. "Youth Show A"
    if (letter.isNotEmpty) return 'Show $letter';
    return 'Section';
  }

  Map<String, dynamic>? _selectedSection() {
    if (_selectedSectionId == null) return null;
    for (final s in _sections) {
      if (s['id']?.toString() == _selectedSectionId) return s;
    }
    return null;
  }

  // ---------------------------
  // Fetch entries for 1 section
  // ---------------------------

  Future<List<Map<String, dynamic>>> _fetchEntriesForSection(String sectionId) async {
    var q = supabase
        .from('entries')
        .select(
          'id,show_id,section_id,exhibitor_id,'
          'tattoo,animal_name,breed,variety,sex,class_name,notes,scratched_at,created_at,'
          'exhibitors!entries_exhibitor_id_fkey(id,display_name,first_name,last_name)',
        )
        .eq('show_id', widget.showId)
        .eq('section_id', sectionId);

    if (!_includeScratched) {
      q = q.isFilter('scratched_at', null);
    }

    final res = await q.order('created_at');
    return (res as List).cast<Map<String, dynamic>>();
  }

  String _animalEarLabel(Map<String, dynamic> e, {required bool isCavy}) {
    final tattoo = _safe(e, 'tattoo');
    final animalName = _safe(e, 'animal_name');

    if (!isCavy) return tattoo;

    if (animalName.isNotEmpty && tattoo.isNotEmpty) {
      return '$animalName • $tattoo';
    }

    if (animalName.isNotEmpty) return animalName;
    return tattoo;
  }

  String _safe(Map<String, dynamic> e, String k) => (e[k] ?? '').toString().trim();

  String _exhibitorName(Map<String, dynamic> entry) {
    final ex = entry['exhibitors'];
    if (ex is Map) {
      final dn = (ex['display_name'] ?? '').toString().trim();
      if (dn.isNotEmpty) return dn;

      final first = (ex['first_name'] ?? '').toString().trim();
      final last = (ex['last_name'] ?? '').toString().trim();
      final combined = ('$last, $first').replaceAll(RegExp(r'^\s*,\s*|\s+$'), '').trim();
      if (combined.isNotEmpty) return combined;
    }
    return '(Unknown Exhibitor)';
  }

  // ✅ Fix: ensure class prints ONLY Senior/Intermediate/Junior (no sex bleed)
  String _cleanClassName(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';

    final low = s.toLowerCase();

    // normalize common cases like "Senior Buck", "Junior Doe", etc.
    // Strip sex words from class_name if they appear inside it
    s = s.replaceAll(RegExp(r'\b(buck|doe)\b', caseSensitive: false), '').trim();

    // If stored as just "Sr", etc.
    if (low.contains('senior') || low == 'sr' || low == 's') return 'Senior';
    if (low.contains('intermediate') || low == 'int' || low == 'i') return 'Intermediate';
    if (low.contains('junior') || low == 'jr' || low == 'j') return 'Junior';

    // fallback: title-case whatever remains
    if (s.isEmpty) return '';
    return s[0].toUpperCase() + s.substring(1);
  }

  int _classRank(String className) {
    final c = className.toLowerCase();
    if (c.startsWith('senior')) return 0;
    if (c.startsWith('intermediate')) return 1;
    if (c.startsWith('junior')) return 2;
    return 99;
  }

  int _sexRank(String sex) {
    final s = sex.toLowerCase();
    if (s.contains('buck')) return 0;
    if (s.contains('doe')) return 1;
    return 99;
  }


  bool _supportsBestAgeAwards(String breedName) {
    final b = breedName.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return b == 'american sable' ||
        b == 'american sables' ||
        b == 'himalayan' ||
        b == 'checkered giant';
  }

  String _ageSpecialForClass({
    required String breed,
    required String className,
    required bool isCavy,
  }) {
    final cls = className.trim().toLowerCase();

    final needsAgeSpecials = isCavy || _supportsBestAgeAwards(breed);
    if (!needsAgeSpecials) return '';

    if (cls.startsWith('senior')) return 'Best Sr';
    if (cls.startsWith('intermediate')) return 'Best Int';
    if (cls.startsWith('junior')) return 'Best Jr';

    return '';
  }

  // ---------------------------
  // PDF build (Judging Sheet - Breed Class)
  // ---------------------------

  pw.Document _buildControlSheetsPdf({
    required String sectionLabel,
    required List<Map<String, dynamic>> entries,
  }) {
    final doc = pw.Document();

    // Group by Breed + Color/Variety + Class + Sex.
    final groups = <String, List<Map<String, dynamic>>>{};
    final meta = <String, Map<String, String>>{};

    for (final e in entries) {
      final breed = _safe(e, 'breed');
      final color = _safe(e, 'variety');
      final cls = _cleanClassName(_safe(e, 'class_name'));
      final sex = _safe(e, 'sex');

      final key = '${breed}||${color}||${cls}||${sex}'.toLowerCase();
      groups.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(e);

      meta[key] = {
        'breed': breed.isEmpty ? '(Unknown Breed)' : breed,
        'color': color.isEmpty ? '(Unknown Color)' : color,
        'class': cls.isEmpty ? '(Unknown Class)' : cls,
        'sex': sex.isEmpty ? '(Unknown Sex)' : sex,
      };
    }

    // Sort entries inside each group by tattoo then exhibitor
    for (final k in groups.keys) {
      groups[k]!.sort((a, b) {
        final at = _safe(a, 'tattoo').toLowerCase();
        final bt = _safe(b, 'tattoo').toLowerCase();
        final c1 = at.compareTo(bt);
        if (c1 != 0) return c1;
        return _exhibitorName(a).toLowerCase().compareTo(_exhibitorName(b).toLowerCase());
      });
    }

    // Detect cavy by breed names. Normalize spacing/case so cavy sorting and labels
    // still work if Supabase has small formatting differences.
    String normBreedName(String value) => value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

    final isCavy = entries.any((e) {
      final breed = normBreedName(_safe(e, 'breed'));
      return cavyBreedOrder.any((b) => normBreedName(b) == breed);
    });


    // Sort groups:
    // Rabbits = current alphabetical behavior
    // Cavies = ARBA SOP breed/variety order
    final groupKeys = groups.keys.toList()
      ..sort((a, b) {
        final ma = meta[a]!;
        final mb = meta[b]!;

        if (isCavy) {
          final cBreed = cavyBreedSortIndex(ma['breed']!)
              .compareTo(cavyBreedSortIndex(mb['breed']!));
          if (cBreed != 0) return cBreed;

          final cColor = cavyVarietySortIndex(ma['breed']!, ma['color']!)
              .compareTo(cavyVarietySortIndex(mb['breed']!, mb['color']!));
          if (cColor != 0) return cColor;
        } else {
          final cBreed =
              ma['breed']!.toLowerCase().compareTo(mb['breed']!.toLowerCase());
          if (cBreed != 0) return cBreed;

          final cColor =
              ma['color']!.toLowerCase().compareTo(mb['color']!.toLowerCase());
          if (cColor != 0) return cColor;
        }

        final cClass = _classRank(ma['class']!).compareTo(_classRank(mb['class']!));
        if (cClass != 0) return cClass;

        final cSex = _sexRank(ma['sex']!).compareTo(_sexRank(mb['sex']!));
        return cSex;
      });

    // Track “within breed: X of Y” for each Breed/Class block.
    final totalWithinBreed = <String, int>{};
    for (final k in groupKeys) {
      final breed = meta[k]!['breed']!;
      totalWithinBreed[breed] = (totalWithinBreed[breed] ?? 0) + 1;
    }

    final withinBreedCounter = <String, int>{};

    String showDatesLine() {
      String s2(String k) => (_showRow?[k] ?? '').toString().trim();
      final sd = s2('start_date');
      final ed = s2('end_date');
      if (sd.isEmpty && ed.isEmpty) return '';
      if (sd.isNotEmpty && ed.isNotEmpty) return '$sd - $ed';
      return sd.isNotEmpty ? sd : ed;
    }

    final locationLine = (_showRow?['location_name'] ?? '').toString().trim();

    final headerStyle = pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold);
    final small = pw.TextStyle(fontSize: 8);
    final tiny = pw.TextStyle(fontSize: 7.5);
    final label = pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold);
    final classTitle = pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold);

    pw.Widget line(String t) => pw.Padding(
          padding: pw.EdgeInsets.only(top: 1),
          child: pw.Text(t, style: small),
        );

    List<pw.Widget> buildClassBlock({
      required int blockIndex,
      required String breed,
      required String color,
      required String cls,
      required String sex,
      required int within,
      required int withinTotal,
      required List<Map<String, dynamic>> list,
    }) {
      final noInClass = list.length;
      final exhibitorsInClass = list
          .map(_exhibitorName)
          .where((name) => name.trim().isNotEmpty)
          .toSet()
          .length;

      final ageSpecial = _ageSpecialForClass(
        breed: breed,
        className: cls,
        isCavy: isCavy,
      );

      final widgets = <pw.Widget>[];

      widgets.add(
        pw.Container(
          margin: pw.EdgeInsets.only(top: 4, bottom: 4),
          padding: pw.EdgeInsets.only(bottom: 4),
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
                children: [
                  pw.Text(
                    'Breed Class ${blockIndex + 1} of ${groupKeys.length}',
                    style: small,
                  ),
                  pw.Text(
                    'within breed: $within of $withinTotal',
                    style: small,
                  ),
                ],
              ),
              pw.SizedBox(height: 3),
              pw.Text('$breed — $color', style: classTitle),
              pw.SizedBox(height: 2),
              pw.Row(
                children: [
                  pw.Expanded(child: pw.Text('Class: $cls', style: label)),
                  pw.Expanded(child: pw.Text('Sex: $sex', style: label)),
                  pw.Expanded(child: pw.Text('No. in Class: $noInClass', style: label)),
                  pw.Expanded(child: pw.Text('No. Exhibitors: $exhibitorsInClass', style: label)),
                ],
              ),
              pw.SizedBox(height: 4),
            ],
          ),
        ),
      );

      widgets.add(
        pw.Table(
          border: pw.TableBorder.all(width: 0.4),
          columnWidths: {
            0: pw.FixedColumnWidth(36),
            1: pw.FixedColumnWidth(isCavy ? 95 : 60),
            2: pw.FlexColumnWidth(1),
            3: pw.FixedColumnWidth(115),
            4: pw.FixedColumnWidth(55),
          },
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: PdfColors.grey300),
              children: [
                pw.Padding(
                  padding: pw.EdgeInsets.all(3),
                  child: pw.Text('Coop #', style: label),
                ),
                pw.Padding(
                  padding: pw.EdgeInsets.all(3),
                  child: pw.Text(
                    isCavy ? 'Animal Name • Ear #' : 'Ear #',
                    style: label,
                  ),
                ),
                pw.Padding(
                  padding: pw.EdgeInsets.all(3),
                  child: pw.Text('Exhibitor', style: label),
                ),
                pw.Padding(
                  padding: pw.EdgeInsets.all(3),
                  child: pw.Text('Place / DQ', style: label),
                ),
                pw.Padding(
                  padding: pw.EdgeInsets.all(3),
                  child: pw.Text(
                    ageSpecial.isNotEmpty
                        ? 'Specials\n$ageSpecial'
                        : 'Specials',
                    style: label,
                  ),
                ),
              ],
            ),
            ...List.generate(list.length, (idx) {
              final e = list[idx];
              final earLabel = _animalEarLabel(e, isCavy: isCavy);
              final exhibitor = _exhibitorName(e);

              return pw.TableRow(
                children: [
                  pw.Padding(
                    padding: pw.EdgeInsets.all(3),
                    child: pw.Text('', style: tiny),
                  ),
                  pw.Padding(
                    padding: pw.EdgeInsets.all(3),
                    child: pw.Text(earLabel, style: tiny),
                  ),
                  pw.Padding(
                    padding: pw.EdgeInsets.all(3),
                    child: pw.Text(exhibitor, style: tiny),
                  ),
                  pw.Padding(
                    padding: pw.EdgeInsets.all(3),
                    child: pw.Text('', style: tiny),
                  ),
                  pw.Padding(
                    padding: pw.EdgeInsets.all(3),
                    child: pw.Text('', style: tiny),
                  ),
                ],
              );
            }),
          ],
        ),
      );

      widgets.add(pw.SizedBox(height: 8));

      return widgets;
    }

    final classBlocks = <pw.Widget>[];

    for (var i = 0; i < groupKeys.length; i++) {
      final key = groupKeys[i];
      final m = meta[key]!;
      final breed = m['breed']!;
      final color = m['color']!;
      final cls = m['class']!;
      final sex = m['sex']!;
      final list = groups[key]!;

      withinBreedCounter[breed] = (withinBreedCounter[breed] ?? 0) + 1;
      final within = withinBreedCounter[breed]!;
      final withinTotal = totalWithinBreed[breed] ?? 1;

      final blockWidgets = buildClassBlock(
        blockIndex: i,
        breed: breed,
        color: color,
        cls: cls,
        sex: sex,
        within: within,
        withinTotal: withinTotal,
        list: list,
      );

      classBlocks.addAll(blockWidgets);
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: pw.EdgeInsets.fromLTRB(24, 24, 24, 28),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text('${widget.showName} $sectionLabel', style: headerStyle),
            pw.Text('Judging Sheet - Breed Class', style: headerStyle),
            if (showDatesLine().isNotEmpty) line(showDatesLine()),
            if (locationLine.isNotEmpty) line(locationLine),
            pw.SizedBox(height: 6),
          ],
        ),
        footer: (context) => pw.Row(
          children: [
            pw.Text('RingMaster Show', style: small),
            pw.Spacer(),
            pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: small),
            pw.Spacer(),
            pw.Text(DateTime.now().toLocal().toString(), style: small),
          ],
        ),
        build: (context) => classBlocks,
      ),
    );

    return doc;
  }

  Future<void> _generate() async {
    final section = _selectedSection();
    final sectionId = section?['id']?.toString();
    if (sectionId == null || sectionId.isEmpty) {
      setState(() => _msg = 'Select a section first.');
      return;
    }

    setState(() {
      _building = true;
      _msg = null;
    });

    try {
      final entries = await _fetchEntriesForSection(sectionId);
      if (entries.isEmpty) {
        if (!mounted) return;
        setState(() {
          _building = false;
          _msg = 'No entries found for this section.';
        });
        return;
      }

      final sectionLabel = _sectionLabel(section!);
      final doc = _buildControlSheetsPdf(sectionLabel: sectionLabel, entries: entries);
      final bytes = await doc.save();

      final filename = 'control_sheets_${widget.showName}_$sectionLabel.pdf';

      await Printing.layoutPdf(
        name: filename,
        onLayout: (_) async => bytes,
      );

      if (!mounted) return;
      setState(() => _building = false);
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
    final ready = !_loading && _sections.isNotEmpty;

    return RingMasterPageShell(
      title: 'RingMaster Show',
      subtitle: 'Control Sheets — ${widget.showName}',
      showBackButton: true,
      showHomeButton: true,
      useScrollView: false,
      bodyPadding: EdgeInsets.zero,
      actions: [
        IconButton(
          tooltip: 'Reload',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_msg != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.red.withOpacity(.25),
                      ),
                    ),
                    child: Text(
                      _msg!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                Container(
                  width: double.infinity,
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        value: _selectedSectionId,
                        decoration: const InputDecoration(
                          labelText: 'Show Section',
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
                      const SizedBox(height: 10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _includeScratched,
                        onChanged: (v) =>
                            setState(() => _includeScratched = v),
                        title: const Text('Include scratched entries'),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: (!ready || _building) ? null : _generate,
                        icon: const Icon(Icons.picture_as_pdf),
                        label: Text(
                          _building
                              ? 'Building PDF…'
                              : 'Generate Control Sheets (PDF)',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Format matches “Judging Sheet - Breed Class” style.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}