// lib/screens/admin/admin_control_sheets_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
          'tattoo,breed,variety,sex,class_name,notes,scratched_at,created_at,'
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

  // ---------------------------
  // PDF build (Judging Sheet - Breed Class)
  // ---------------------------

  pw.Document _buildControlSheetsPdf({
    required String sectionLabel,
    required List<Map<String, dynamic>> entries,
  }) {
    final doc = pw.Document();

    // Group key matches the example style: Breed + Color(variety) + Class + Sex  [oai_citation:2‡Show A Judging Sheet.pdf](sediment://file_000000000b00722f8c33e5674a8db463)
    final groups = <String, List<Map<String, dynamic>>>{};
    final meta = <String, Map<String, String>>{};

    for (final e in entries) {
      final breed = _safe(e, 'breed');
      final color = _safe(e, 'variety'); // this is “Color” in the sample  [oai_citation:3‡Show A Judging Sheet.pdf](sediment://file_000000000b00722f8c33e5674a8db463)
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

    // Sort groups: Breed, Color, Class order, Sex order
    final groupKeys = groups.keys.toList()
      ..sort((a, b) {
        final ma = meta[a]!;
        final mb = meta[b]!;
        final cBreed = ma['breed']!.toLowerCase().compareTo(mb['breed']!.toLowerCase());
        if (cBreed != 0) return cBreed;

        final cColor = ma['color']!.toLowerCase().compareTo(mb['color']!.toLowerCase());
        if (cColor != 0) return cColor;

        final cClass = _classRank(ma['class']!).compareTo(_classRank(mb['class']!));
        if (cClass != 0) return cClass;

        final cSex = _sexRank(ma['sex']!).compareTo(_sexRank(mb['sex']!));
        return cSex;
      });

    // For “within breed: X of Y” like the sample  [oai_citation:4‡Show A Judging Sheet.pdf](sediment://file_000000000b00722f8c33e5674a8db463)
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

    final totalPages = groupKeys.length;

    for (var i = 0; i < groupKeys.length; i++) {
      final key = groupKeys[i];
      final m = meta[key]!;
      final breed = m['breed']!;
      final color = m['color']!;
      final cls = m['class']!;
      final sex = m['sex']!;
      final list = groups[key]!;
      final noInClass = list.length;

      withinBreedCounter[breed] = (withinBreedCounter[breed] ?? 0) + 1;
      final within = withinBreedCounter[breed]!;
      final withinTotal = totalWithinBreed[breed] ?? 1;

      // “Entry #” can be a stable per-group sequence if you don’t store it yet
      // (You can swap to a real column later.)
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.letter,
          margin: pw.EdgeInsets.fromLTRB(28, 28, 28, 28),
          build: (context) {
            final headerStyle = pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold);
            final small = pw.TextStyle(fontSize: 9);
            final label = pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold);

            pw.Widget line(String t) => pw.Padding(
                  padding: pw.EdgeInsets.only(top: 1),
                  child: pw.Text(t, style: small),
                );

            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // Top block like sample  [oai_citation:5‡Show A Judging Sheet.pdf](sediment://file_000000000b00722f8c33e5674a8db463)
                pw.Text('Judging Sheet - Breed Class', style: headerStyle),
                if (showDatesLine().isNotEmpty) line(showDatesLine()),
                if (locationLine.isNotEmpty) line(locationLine),
                line('${widget.showName}'),
                line(sectionLabel),

                pw.SizedBox(height: 8),

                // Page counters like sample  [oai_citation:6‡Show A Judging Sheet.pdf](sediment://file_000000000b00722f8c33e5674a8db463)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Breed Class: pg. ${i + 1} of $totalPages', style: small),
                    pw.Text('within breed: $within of $withinTotal', style: small),
                  ],
                ),

                pw.SizedBox(height: 10),

                // Breed/Color/Class/Sex line items  [oai_citation:7‡Show A Judging Sheet.pdf](sediment://file_000000000b00722f8c33e5674a8db463)
                pw.Row(
                  children: [
                    pw.Expanded(child: pw.Text('Breed: $breed', style: label)),
                    pw.Expanded(child: pw.Text('Color: $color', style: label)),
                  ],
                ),
                pw.SizedBox(height: 2),
                pw.Row(
                  children: [
                    pw.Expanded(child: pw.Text('Class: $cls', style: label)),
                    pw.Expanded(child: pw.Text('Sex: $sex', style: label)),
                  ],
                ),
                pw.SizedBox(height: 2),
                pw.Text('No. in Class: $noInClass', style: label),

                pw.SizedBox(height: 10),

                // Table like sample: Coop #, Ear #, Entry #, Exhibitor, Place..., Specials  [oai_citation:8‡Show A Judging Sheet.pdf](sediment://file_000000000b00722f8c33e5674a8db463)
                pw.Table(
                  border: pw.TableBorder.all(width: 0.8),
                  columnWidths: {
                    0: pw.FixedColumnWidth(60), // Coop #
                    1: pw.FixedColumnWidth(60), // Ear #
                    2: pw.FixedColumnWidth(60), // Entry #
                    3: pw.FlexColumnWidth(1), // Exhibitor
                    4: pw.FixedColumnWidth(160), // Place or Reason Disqualified
                    5: pw.FixedColumnWidth(80), // Specials
                  },
                  children: [
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: PdfColors.grey300),
                      children: [
                        pw.Padding(padding: pw.EdgeInsets.all(6), child: pw.Text('Coop #', style: label)),
                        pw.Padding(padding: pw.EdgeInsets.all(6), child: pw.Text('Ear #', style: label)),
                        pw.Padding(padding: pw.EdgeInsets.all(6), child: pw.Text('Entry #', style: label)),
                        pw.Padding(padding: pw.EdgeInsets.all(6), child: pw.Text('Exhibitor', style: label)),
                        pw.Padding(padding: pw.EdgeInsets.all(6), child: pw.Text('Place or Reason Disqualified', style: label)),
                        pw.Padding(padding: pw.EdgeInsets.all(6), child: pw.Text('Specials', style: label)),
                      ],
                    ),
                    ...List.generate(list.length, (idx) {
                      final e = list[idx];
                      final tattoo = _safe(e, 'tattoo');
                      final exhibitor = _exhibitorName(e);

                      // placeholders unless you add these columns later
                      final coop = ''; // TODO: map to a coop assignment column when you have it
                      final entryNo = '${idx + 1}';

                      return pw.TableRow(
                        children: [
                          pw.Padding(padding: pw.EdgeInsets.all(6), child: pw.Text(coop, style: small)),
                          pw.Padding(padding: pw.EdgeInsets.all(6), child: pw.Text(tattoo, style: small)),
                          pw.Padding(padding: pw.EdgeInsets.all(6), child: pw.Text(entryNo, style: small)),
                          pw.Padding(padding: pw.EdgeInsets.all(6), child: pw.Text(exhibitor, style: small)),
                          pw.Padding(padding: pw.EdgeInsets.all(6), child: pw.Text('', style: small)),
                          pw.Padding(padding: pw.EdgeInsets.all(6), child: pw.Text('', style: small)),
                        ],
                      );
                    }),
                  ],
                ),

                pw.SizedBox(height: 10),

                // Judge/Writer line like sample  [oai_citation:9‡Show A Judging Sheet.pdf](sediment://file_000000000b00722f8c33e5674a8db463)
                pw.Row(
                  children: [
                    pw.Text('Judge: ____________________', style: small),
                    pw.SizedBox(width: 30),
                    pw.Text('Writer: ____________________', style: small),
                  ],
                ),

                pw.Spacer(),

                pw.Row(
                  children: [
                    pw.Text('RingMaster Show', style: small),
                    pw.Spacer(),
                    pw.Text(DateTime.now().toLocal().toString(), style: small),
                  ],
                ),
              ],
            );
          },
        ),
      );
    }

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

    return Scaffold(
      appBar: AppBar(
        title: Text('Control sheets — ${widget.showName}'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            onPressed: _loading ? null : _load,
            icon: Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.all(16),
              children: [
                if (_msg != null) ...[
                  Text(_msg!, style: TextStyle(color: Colors.red)),
                  SizedBox(height: 10),
                ],

                DropdownButtonFormField<String>(
                  value: _selectedSectionId,
                  decoration: InputDecoration(labelText: 'Show Section'),
                  items: _sections
                      .map(
                        (s) => DropdownMenuItem<String>(
                          value: s['id']?.toString(),
                          child: Text(_sectionLabel(s)),
                        ),
                      )
                      .toList(),
                  onChanged: _sections.isEmpty ? null : (v) => setState(() => _selectedSectionId = v),
                ),

                SizedBox(height: 10),

                SwitchListTile(
                  value: _includeScratched,
                  onChanged: (v) => setState(() => _includeScratched = v),
                  title: Text('Include scratched entries'),
                ),

                SizedBox(height: 12),

                FilledButton.icon(
                  onPressed: (!ready || _building) ? null : _generate,
                  icon: Icon(Icons.picture_as_pdf),
                  label: Text(_building ? 'Building PDF…' : 'Generate Control Sheets (PDF)'),
                ),

                SizedBox(height: 10),

                Text(
                  'Format matches “Judging Sheet - Breed Class” style (Breed + Color + Class + Sex).',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
    );
  }
}