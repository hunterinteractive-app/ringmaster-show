import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:ringmaster_show/services/ringmaster_backend.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:ringmaster_show/utils/file_download.dart';
import 'package:ringmaster_show/reporting_core/assets/flutter_report_asset_loader.dart';
import '../models/report_artifact_summary.dart';
import '../models/base/report_request.dart';
import '../data/loaders/exhibitor_mailing_labels_loader.dart';
import '../pdf/builders/exhibitor_mailing_labels_pdf.dart';

/// Review is explicit: printing/downloading never records physical delivery.
Future<bool> showManualReportDelivery(
  BuildContext context, {
  required String showId,
  String? sectionId,
  bool beforeEmail = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: AppTheme.surfaceDialogTheme(Theme.of(context)),
        child: Dialog(
          child: SizedBox(
            width: 850,
            height: MediaQuery.sizeOf(context).height * .85,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Print/mail reports',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(context, false),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ManualReportDeliveryPanel(
                    showId: showId,
                    sectionId: sectionId,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(beforeEmail ? 'Continue with emails' : 'Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ) ??
    false;

class ManualReportDeliveryPanel extends StatefulWidget {
  const ManualReportDeliveryPanel({
    super.key,
    required this.showId,
    this.sectionId,
  });
  final String showId;
  final String? sectionId;
  @override
  State<ManualReportDeliveryPanel> createState() =>
      _ManualReportDeliveryPanelState();
}

class _ManualReportDeliveryPanelState extends State<ManualReportDeliveryPanel> {
  bool _loading = true, _busy = false;
  String? _error;
  String _family = 'results';
  List<ReportArtifactSummary> _artifacts = [];
  Map<String, Map<String, dynamic>> _contacts = {};
  Map<String, String> _delivered = {};
  Map<String, dynamic>? _pack;
  Timer? _poll;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  String _key(ReportArtifactSummary a) => '${a.id}:${a.generation}';
  String _id(ReportArtifactSummary a) => '${a.metadata['exhibitor_id'] ?? ''}';
  String _name(String id) {
    final c = _contacts[id]!;
    return [
          c['showing_name'],
          c['display_name'],
          '${c['first_name'] ?? ''} ${c['last_name'] ?? ''}',
        ]
        .map((v) => (v ?? '').toString().trim())
        .firstWhere((v) => v.isNotEmpty, orElse: () => 'Exhibitor');
  }

  Map<String, List<ReportArtifactSummary>> get _groups {
    final groups = <String, List<ReportArtifactSummary>>{};
    for (final a in _artifacts) {
      final c = _contacts[_id(a)];
      if (c != null && (c['email'] ?? '').toString().trim().isEmpty) {
        groups.putIfAbsent(_id(a), () => []).add(a);
      }
    }
    return groups;
  }

  Future<void> _load() async {
    try {
      final rows = <Map<String, dynamic>>[];
      for (var offset = 0; ; offset += 500) {
        final page = await ringMasterClient
            .from('show_report_artifacts')
            .select()
            .eq('show_id', widget.showId)
            .eq('is_current', true)
            .inFilter(
              'report_name',
              _family == 'results'
                  ? ['exhibitor_report', 'legs']
                  : ['checkin_sheet'],
            )
            .order('id')
            .range(offset, offset + 499);
        rows.addAll(List<Map<String, dynamic>>.from(page));
        if (page.length < 500) break;
      }
      final artifacts = rows
          .map(ReportArtifactSummary.fromJson)
          .where(
            (a) =>
                widget.sectionId == null ||
                a.sectionIds.contains(widget.sectionId) ||
                a.metadata['section_id'] == widget.sectionId,
          )
          .toList();
      final ids = artifacts
          .map(_id)
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final contacts = <String, Map<String, dynamic>>{};
      for (var offset = 0; offset < ids.length; offset += 100) {
        final rows = await ringMasterClient
            .from('exhibitors')
            .select(
              'id,email,showing_name,display_name,first_name,last_name,address_line1,address_line2,city,state,zip,phone,arba_number',
            )
            .inFilter('id', ids.skip(offset).take(100).toList());
        for (final row in rows) {
          contacts['${row['id']}'] = Map<String, dynamic>.from(row);
        }
      }
      if (ids.any((id) => !contacts.containsKey(id))) {
        throw StateError(
          'Some exhibitor contacts could not be loaded. Refresh before sending or printing.',
        );
      }
      final deliveries = <String, String>{};
      for (var offset = 0; ; offset += 500) {
        final page = await ringMasterClient
            .from('report_manual_deliveries')
            .select('artifact_id,generation,method')
            .eq('show_id', widget.showId)
            .order('artifact_id')
            .order('generation')
            .range(offset, offset + 499);
        for (final row in page) {
          deliveries['${row['artifact_id']}:${row['generation']}'] =
              '${row['method']}';
        }
        if (page.length < 500) break;
      }
      if (!mounted) return;
      setState(() {
        _artifacts = artifacts;
        _contacts = contacts;
        _delivered = deliveries;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Unable to load print/mail reports: $e';
        });
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _queue() async {
    final id = await ringMasterClient.rpc(
      'queue_manual_report_print_pack',
      params: {
        'p_show_id': widget.showId,
        'p_section_id': widget.sectionId,
        'p_family': _family,
      },
    );
    await _readPack('$id');
  }

  Future<void> _readPack(String id) async {
    _poll?.cancel();
    try {
      final row = await ringMasterClient
          .from('exhibitor_print_packs')
          .select()
          .eq('id', id)
          .single();
      if (!mounted) return;
      setState(() => _pack = Map<String, dynamic>.from(row));
      if (['queued', 'running'].contains(row['artifact_status'])) {
        _poll = Timer(const Duration(seconds: 5), () => _readPack(id));
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = 'Unable to check packet progress. Reopen or retry: $e',
        );
      }
    }
  }

  Future<void> _openPack({required bool print}) async {
    final pack = _pack!;
    // Revalidate the manifest before handing out an existing packet.
    final id = await ringMasterClient.rpc(
      'queue_manual_report_print_pack',
      params: {
        'p_show_id': widget.showId,
        'p_section_id': widget.sectionId,
        'p_family': _family,
      },
    );
    if (id != pack['id']) {
      await _readPack('$id');
      throw StateError(
        'Reports or contacts changed. An updated packet is being prepared.',
      );
    }
    final bytes = await ringMasterClient.storage
        .from('${pack['storage_bucket']}')
        .download('${pack['storage_path']}');
    if (print && mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => Theme(
          data: AppTheme.surfaceDialogTheme(Theme.of(context)),
          child: Dialog(
            child: SizedBox(
              width: 850,
              height: MediaQuery.sizeOf(context).height * .85,
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close preview'),
                    ),
                  ),
                  Expanded(
                    child: PdfPreview(
                      build: (_) => bytes,
                      pdfFileName: '${pack['file_name']}',
                      allowSharing: false,
                      canChangePageFormat: false,
                      canChangeOrientation: false,
                      canDebug: false,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } else if (!print) {
      await downloadFileBytes(
        bytes,
        fileName: '${pack['file_name']}',
        mimeType: 'application/pdf',
      );
    }
  }

  Future<void> _labels() async {
    final labels = buildExhibitorMailingLabels([
      for (final id in _groups.keys)
        {'exhibitor_id': id, 'exhibitors': _contacts[id]},
    ]);
    final result =
        await ExhibitorMailingLabelsPdf(
          assets: FlutterReportAssetLoader(),
        ).buildFile(
          labels,
          ReportRequest(
            showId: widget.showId,
            reportName: 'exhibitor_mailing_labels',
            finalizeRunId: '',
          ),
          mode: MailingLabelMode.address,
          sort: MailingLabelSort.lastName,
        );
    await downloadFileBytes(
      Uint8List.fromList(result.bytes),
      fileName: result.fileName,
      mimeType: 'application/pdf',
    );
  }

  Future<void> _mark(
    String id,
    List<ReportArtifactSummary> reports,
    String method,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: AppTheme.surfaceDialogTheme(Theme.of(context)),
        child: AlertDialog(
          title: Text(
            method == 'pending'
                ? 'Mark delivery outstanding?'
                : 'Confirm report delivery',
          ),
          content: Text(
            method == 'pending'
                ? 'Reopen delivery for ${_name(id)}?'
                : 'Have all ${reports.length} report files for ${_name(id)} been ${method == 'mailed' ? 'mailed' : 'handed out'}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    await ringMasterClient.rpc(
      'mark_report_manual_delivery',
      params: {
        'p_show_id': widget.showId,
        'p_artifacts': [
          for (final a in reports) {'id': a.id, 'generation': a.generation},
        ],
        'p_method': method,
      },
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups.entries.toList()
      ..sort((a, b) => _name(a.key).compareTo(_name(b.key)));
    final pending = groups
        .where((g) => g.value.any((a) => !_delivered.containsKey(_key(a))))
        .length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _family,
          decoration: const InputDecoration(labelText: 'Reports'),
          items: const [
            DropdownMenuItem(
              value: 'results',
              child: Text('Exhibitor reports and legs'),
            ),
            DropdownMenuItem(value: 'checkin', child: Text('Check-in sheets')),
          ],
          onChanged: _busy || _loading
              ? null
              : (v) {
                  _poll?.cancel();
                  setState(() {
                    _family = v!;
                    _pack = null;
                    _loading = true;
                  });
                  _load();
                },
        ),
        const SizedBox(height: 12),
        const Text(
          'No email — print or download reports. Printing does not mark reports as delivered. Record when they are mailed or handed out.',
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _run(_load),
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
        ),
        if (!_loading && _error == null) ...[
          Text(
            '${groups.length} exhibitors without email • $pending print/mail outstanding',
          ),
          if (groups.isEmpty)
            const Text(
              'No no-email reports in this selection. Generate the reports first if they are not listed.',
            ),
          if (groups.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : () => _run(_queue),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Prepare print packet'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _run(_labels),
                  icon: const Icon(Icons.mail_outline),
                  label: const Text('Mailing labels'),
                ),
              ],
            ),
          if (_pack != null) ...[
            Text('Print packet: ${_pack!['artifact_status']}'),
            if (_pack!['artifact_status'] == 'queued' ||
                _pack!['artifact_status'] == 'running')
              const Text(
                'The server is preparing the packet. You can continue sending emails and return here.',
              ),
            if (_pack!['error_message'] != null)
              Text('${_pack!['error_message']}'),
            if (_pack!['artifact_status'] == 'generated')
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(() => _openPack(print: true)),
                    icon: const Icon(Icons.print),
                    label: const Text('Print reports'),
                  ),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() => _openPack(print: false)),
                    child: const Text('Download packet'),
                  ),
                ],
              ),
          ],
          for (final group in groups)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _name(group.key),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${group.value.length} report files • ${group.value.where((a) => _delivered.containsKey(_key(a))).length} delivered',
                    ),
                    if (['address_line1', 'city', 'state', 'zip'].any(
                      (key) => (_contacts[group.key]![key] ?? '')
                          .toString()
                          .trim()
                          .isEmpty,
                    ))
                      const Text(
                        'Mailing address incomplete — update exhibitor details before mailing.',
                      ),
                    for (final a in group.value)
                      Text(
                        '${a.reportName == 'legs'
                            ? 'Leg certificates'
                            : a.reportName == 'checkin_sheet'
                            ? 'Check-in sheet'
                            : 'Exhibitor report'}: ${a.artifactStatus != 'generated'
                            ? 'Awaiting generation'
                            : _delivered[_key(a)] == 'mailed'
                            ? 'Mailed'
                            : _delivered[_key(a)] == 'handed_out'
                            ? 'Handed out'
                            : 'Print/mail required'}',
                      ),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final method in [
                          'mailed',
                          'handed_out',
                          'pending',
                        ])
                          TextButton(
                            onPressed:
                                _busy ||
                                    group.value.any(
                                      (a) => a.artifactStatus != 'generated',
                                    )
                                ? null
                                : () => _run(
                                    () => _mark(group.key, group.value, method),
                                  ),
                            child: Text(
                              method == 'mailed'
                                  ? 'Mark mailed'
                                  : method == 'handed_out'
                                  ? 'Mark handed out'
                                  : 'Mark outstanding',
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}
