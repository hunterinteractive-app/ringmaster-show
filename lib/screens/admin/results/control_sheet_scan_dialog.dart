import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:ringmaster_show/services/results/control_sheet_scan.dart';
import 'package:ringmaster_show/services/results_entry_validation.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

typedef ScanResultChange = ({
  Map<String, dynamic> entry,
  String? placement,
  ControlSheetOutcome? outcome,
  Set<String> awards,
});

class ControlSheetScanDialog extends StatefulWidget {
  const ControlSheetScanDialog({
    super.key,
    required this.showId,
    required this.loadSection,
    required this.validate,
  });

  final String showId;
  final Future<List<Map<String, dynamic>>> Function(String sectionId)
  loadSection;
  final Future<int> Function(List<ScanResultChange> changes) validate;

  @override
  State<ControlSheetScanDialog> createState() => _ControlSheetScanDialogState();
}

class _DraftRow {
  _DraftRow(
    this.entry,
    this.options,
    this.placementCount,
    ControlSheetScanRow row,
  ) {
    final places = row.marks
        .where((mark) => mark == 'NP' || int.tryParse(mark) != null)
        .toList();
    final outcomes = ControlSheetOutcome.values
        .where((outcome) => row.marks.contains(outcome.code))
        .toList();
    final overLimit = places.any(
      (mark) => (int.tryParse(mark) ?? 0) > scanSheetPlacementsPerPage,
    );
    if (places.length == 1) {
      placement = places.single == 'NP' || overLimit ? '0' : places.single;
    }
    if (places.isEmpty &&
        outcomes.isEmpty &&
        !ControlSheetOutcome.values.any(
          (outcome) => row.uncertain.contains(outcome.code),
        )) {
      final possiblePlaces = row.uncertain.where(
        (mark) =>
            mark == 'NP' ||
            (int.tryParse(mark) ?? scanSheetPlacementsPerPage + 1) <=
                scanSheetPlacementsPerPage,
      );
      if (possiblePlaces.length == 1) {
        placement = possiblePlaces.single == 'NP' ? '0' : possiblePlaces.single;
      }
    }
    outcome = outcomes.length == 1 ? outcomes.single : null;
    awards = row.marks.intersection(options);
    final conflictingOutcome =
        outcomes.isNotEmpty &&
        (places.isNotEmpty || awards.isNotEmpty || outcomes.length > 1);
    review =
        row.uncertain.isNotEmpty ||
        places.length > 1 ||
        conflictingOutcome ||
        overLimit ||
        (placement == null && awards.isNotEmpty);
    uncertain = {
      if (places.length > 1 || overLimit || conflictingOutcome) ...places,
      if (conflictingOutcome) ...outcomes.map((outcome) => outcome.status),
      if (conflictingOutcome) ...awards,
      for (final mark in row.uncertain)
        ControlSheetOutcome.values
                .where((outcome) => outcome.code == mark)
                .firstOrNull
                ?.status ??
            (mark == 'BOS' ? 'BOSB' : mark),
    }.join(', ');
  }

  final Map<String, dynamic> entry;
  final Set<String> options;
  final int placementCount;
  String? placement;
  ControlSheetOutcome? outcome;
  late Set<String> awards;
  late bool review;
  late String uncertain;
  bool skipped = false;

  bool get hasResults =>
      placement != null || outcome != null || awards.isNotEmpty;
  ScanResultChange get change =>
      (entry: entry, placement: placement, outcome: outcome, awards: awards);
}

class _DraftPage {
  _DraftPage(this.title, this.bytes, this.rows, this.layouts, this.specials);

  final String title;
  final Uint8List bytes;
  final List<_DraftRow> rows;
  final List<ControlSheetScanPage> layouts;
  final List<String> specials;
  bool specialsReviewed = false;

  bool get hasUnreviewedSpecials => specials.isNotEmpty && !specialsReviewed;
}

class _ControlSheetScanDialogState extends State<ControlSheetScanDialog> {
  final _sections = <String, List<Map<String, dynamic>>>{};
  final _pages = <_DraftPage>[];
  final _errors = <String>[];
  var _issues = <String>[];
  bool _working = false;
  bool _showBlank = false;
  bool _preview = false;

  Iterable<_DraftRow> get _rows => _pages.expand((page) => page.rows);

  Future<void> _selectFiles() async {
    try {
      final files = await openFiles(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Photos and PDFs',
            extensions: ['jpg', 'jpeg', 'png', 'heic', 'heif', 'pdf'],
            mimeTypes: [
              'image/jpeg',
              'image/png',
              'image/heic',
              'image/heif',
              'application/pdf',
            ],
            uniformTypeIdentifiers: [
              'public.jpeg',
              'public.png',
              'public.heic',
              'public.heif',
              'com.adobe.pdf',
            ],
          ),
        ],
      );
      await _readFiles(files);
    } catch (error) {
      if (mounted) setState(() => _errors.add(_message(error)));
    }
  }

  Future<void> _selectPhoto() async {
    try {
      final photo = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Control sheet photo',
            extensions: ['jpg', 'jpeg', 'png', 'heic', 'heif'],
            mimeTypes: ['image/*'],
            uniformTypeIdentifiers: ['public.image'],
          ),
        ],
      );
      if (photo != null) await _readFiles([photo]);
    } catch (error) {
      if (mounted) setState(() => _errors.add(_message(error)));
    }
  }

  Future<void> _readFiles(List<XFile> files) async {
    if (files.isEmpty || !mounted || _working) return;
    setState(() {
      _working = true;
      _errors.clear();
      _issues = [];
    });
    for (final file in files) {
      try {
        if (await file.length() > 40 * 1024 * 1024) {
          throw const FormatException(
            'Split scans larger than 40 MB into smaller files.',
          );
        }
        final bytes = await file.readAsBytes();
        final name = file.name.toLowerCase();
        if (name.endsWith('.pdf') ||
            (bytes.length >= 4 &&
                String.fromCharCodes(bytes.take(4)) == '%PDF')) {
          if (!(await Printing.info()).canRaster) {
            throw const FormatException(
              'This device cannot open scanned PDFs. Upload JPG or PNG images.',
            );
          }
          var pageNumber = 0;
          await for (final page in Printing.raster(bytes, dpi: 180)) {
            pageNumber++;
            await _readPage(
              '${file.name} · page $pageNumber',
              await page.toPng(),
            );
            if (!mounted) return;
          }
        } else {
          final isHeif = name.endsWith('.heic') || name.endsWith('.heif');
          await _readPage(
            file.name,
            isHeif ? await _convertHeif(bytes) : bytes,
          );
        }
      } catch (error) {
        _errors.add('${file.name}: ${_message(error)}');
      }
      if (!mounted) return;
    }
    setState(() => _working = false);
  }

  Future<Uint8List> _convertHeif(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetHeight: 2200,
        allowUpscaling: false,
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          final data = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (data != null) return Uint8List.sublistView(data);
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } catch (_) {
      // HEIF is supported only when the device supplies that image codec.
    }
    throw const FormatException(
      'This device cannot read HEIC photos. Use a JPG or PNG copy.',
    );
  }

  Future<void> _readPage(String title, Uint8List bytes) async {
    try {
      final scan = await compute(readControlSheetScan, bytes);
      final first = scan.blocks.first.page;
      if (first.showId != widget.showId.toLowerCase()) {
        throw const FormatException(
          'This control sheet belongs to another show.',
        );
      }
      final sectionId = first.sectionId;
      final entries = _sections[sectionId] ??= await widget.loadSection(
        sectionId,
      );
      final byId = {for (final entry in entries) resultsEntryId(entry): entry};
      final imported = {
        for (final draft in _pages)
          for (final layout in draft.layouts)
            for (final id in layout.entryIds) (id, layout.firstPlacement),
      };

      final rows = <_DraftRow>[];
      final specials = <String>[];
      var duplicate = false;
      for (final block in scan.blocks) {
        final page = block.page;
        if (page.placementCount > entries.length) {
          throw const FormatException(
            'The class size on this sheet exceeds the entries in the section. Reprint the sheet.',
          );
        }
        final firstRowIndex = rows.length;
        for (final read in block.rows) {
          if (!imported.add((read.entryId, page.firstPlacement))) {
            duplicate = true;
            continue;
          }
          final entry = byId[read.entryId];
          if (entry == null) {
            if (read.marks.isNotEmpty || read.uncertain.isNotEmpty) {
              _errors.add(
                '$title: A marked row is no longer in the printed section.',
              );
            }
            continue;
          }
          rows.add(_DraftRow(entry, page.awards, page.placementCount, read));
        }
        if (block.unassignedAwards.isNotEmpty && rows.length > firstRowIndex) {
          final entry = rows[firstRowIndex].entry;
          final classLabel = [
            for (final key in ['breed', 'variety', 'class_name', 'sex'])
              if ((entry[key] ?? '').toString().trim().isNotEmpty)
                entry[key].toString(),
          ].join(' · ');
          final awards = block.unassignedAwards
              .map((award) => award == 'BOS' ? 'BOSB' : award)
              .join(', ');
          specials.add('$classLabel ($awards)');
        }
      }
      if (rows.isEmpty) {
        throw FormatException(
          duplicate
              ? 'These rows are already in the current review.'
              : 'The entries on this sheet are no longer in the section.',
        );
      }
      if (duplicate) {
        _errors.add('$title: Rows already in the current review were skipped.');
      }
      _pages.add(
        _DraftPage(
          title,
          scan.preview,
          rows,
          scan.blocks.map((block) => block.page).toList(),
          specials,
        ),
      );
    } catch (error) {
      _errors.add('$title: ${_message(error)}');
    }
  }

  String _message(Object error) {
    if (error is FormatException) return error.message;
    if (error is StateError) return error.message.toString();
    return error.toString();
  }

  Future<void> _validate() async {
    if (_working) return;
    final changes = _rows
        .where((row) => !row.skipped && row.hasResults)
        .map((row) => row.change)
        .toList();
    setState(() {
      _working = true;
      _issues = [];
    });
    try {
      final count = await widget.validate(changes);
      if (!mounted) return;
      Navigator.pop(context, count);
    } catch (error) {
      if (mounted) setState(() => _issues = [_message(error)]);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Widget _buildRow(_DraftRow row) {
    final entry = row.entry;
    final label = [
      for (final key in ['tattoo', 'breed', 'variety', 'class_name', 'sex'])
        if ((entry[key] ?? '').toString().trim().isNotEmpty)
          entry[key].toString(),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (row.skipped)
            TextButton(
              onPressed: _working
                  ? null
                  : () => setState(() => row.skipped = false),
              child: const Text('Include row'),
            )
          else ...[
            if (row.review)
              Text(
                row.uncertain.isEmpty
                    ? 'Check placement for the marked awards.'
                    : 'Check these marks: ${row.uncertain}.',
              ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                SizedBox(
                  width: 136,
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: row.placement ?? '',
                    onChanged: _working
                        ? null
                        : (value) => setState(() {
                            row.placement = (value ?? '').isEmpty
                                ? null
                                : value;
                            if (row.placement != null) row.outcome = null;
                            _issues = [];
                          }),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Placement'),
                      ),
                      for (
                        var place = 1;
                        place <= row.placementCount &&
                            place <= scanSheetPlacementsPerPage;
                        place++
                      )
                        DropdownMenuItem(
                          value: '$place',
                          child: Text('Place $place'),
                        ),
                      if (row.placementCount > scanSheetPlacementsPerPage)
                        const DropdownMenuItem(value: '0', child: Text('NP')),
                    ],
                  ),
                ),
                SizedBox(
                  width: 265,
                  child: DropdownButton<ControlSheetOutcome>(
                    isExpanded: true,
                    value: row.outcome,
                    hint: const Text(
                      'Scratch / No Show / DQ',
                      overflow: TextOverflow.ellipsis,
                    ),
                    onChanged: _working
                        ? null
                        : (value) => setState(() {
                            row.outcome = value;
                            if (value != null) {
                              row.placement = null;
                              row.awards.clear();
                            }
                            _issues = [];
                          }),
                    items: [
                      const DropdownMenuItem(child: Text('Clear outcome')),
                      for (final outcome in ControlSheetOutcome.values)
                        DropdownMenuItem(
                          value: outcome,
                          child: Text(
                            outcome == ControlSheetOutcome.scratch
                                ? 'Scratch'
                                : outcome.status.replaceFirst(
                                    'Disqualified - ',
                                    'DQ: ',
                                  ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                for (final award in row.options)
                  FilterChip(
                    label: Text(award == 'BOS' ? 'BOSB' : award),
                    selected: row.awards.contains(award),
                    onSelected: _working || row.outcome != null
                        ? null
                        : (value) => setState(() {
                            if (value) {
                              row.awards.add(award);
                            } else {
                              row.awards.remove(award);
                            }
                            _issues = [];
                          }),
                  ),
                if (row.review)
                  TextButton(
                    onPressed: _working
                        ? null
                        : () => setState(() => row.review = false),
                    child: const Text('Mark reviewed'),
                  ),
                TextButton(
                  onPressed: _working
                      ? null
                      : () => setState(() {
                          row.skipped = true;
                          _issues = [];
                        }),
                  child: const Text('Skip'),
                ),
              ],
            ),
          ],
          const Divider(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final results = _rows.where((row) => !row.skipped && row.hasResults).length;
    final pending =
        _rows.where((row) => !row.skipped && row.review).length +
        _pages.where((page) => page.hasUnreviewedSpecials).length;
    return PopScope(
      canPop: !_working,
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: const Text('Scan control sheets (pilot)'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: SizedBox(
            width: 660,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'This pilot checks scans against the show. It does not save results. Include all four corner markers in every photo or scan.',
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _working ? null : _selectPhoto,
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Photo'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _working ? null : _selectFiles,
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Choose scans'),
                      ),
                    ],
                  ),
                  if (_working) const LinearProgressIndicator(),
                  for (final error in [..._errors, ..._issues])
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (_pages.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('$results marked rows · $pending to review'),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilterChip(
                          label: const Text('Show blank rows'),
                          selected: _showBlank,
                          onSelected: (value) =>
                              setState(() => _showBlank = value),
                        ),
                        FilterChip(
                          label: const Text('Show scanned pages'),
                          selected: _preview,
                          onSelected: (value) =>
                              setState(() => _preview = value),
                        ),
                      ],
                    ),
                  ],
                  for (final page in _pages) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            page.title,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove scan',
                          onPressed: _working
                              ? null
                              : () => setState(() {
                                  _pages.remove(page);
                                  _issues = [];
                                }),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    if (_preview)
                      Image.memory(
                        page.bytes,
                        semanticLabel: 'Scanned control sheet',
                      ),
                    if (page.hasUnreviewedSpecials) ...[
                      Text(
                        'Check the marked specials for ${page.specials.join(' / ')}. '
                        'There was no clear first-place mark on this page. '
                        'Use Show blank rows if you need to enter the placement and awards.',
                      ),
                      TextButton(
                        onPressed: _working
                            ? null
                            : () =>
                                  setState(() => page.specialsReviewed = true),
                        child: const Text('Mark specials reviewed'),
                      ),
                    ],
                    for (final row in page.rows)
                      if (_showBlank || row.hasResults || row.review)
                        _buildRow(row),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _working ? null : () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: _working || pending > 0 || results == 0
                ? null
                : _validate,
            child: const Text('Check results'),
          ),
        ],
      ),
    );
  }
}

Future<int?> showControlSheetScanDialog(
  BuildContext context, {
  required String showId,
  required Future<List<Map<String, dynamic>>> Function(String sectionId)
  loadSection,
  required Future<int> Function(List<ScanResultChange> changes) validate,
}) => showDialog<int>(
  context: context,
  barrierDismissible: false,
  builder: (context) => Theme(
    data: AppTheme.surfaceDialogTheme(Theme.of(context)),
    child: ControlSheetScanDialog(
      showId: showId,
      loadSection: loadSection,
      validate: validate,
    ),
  ),
);
