// lib/screens/admin/show_closeout.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:ringmaster_show/screens/admin/closeout/data/closeout_repository.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/arba_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/arba_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/registry/report_registry.dart';
import 'package:ringmaster_show/screens/admin/closeout/services/closeout_runner.dart';
import 'package:ringmaster_show/screens/admin/closeout/services/report_engine.dart';
import 'package:ringmaster_show/screens/admin/closeout/services/report_upload_service.dart';

final supabase = Supabase.instance.client;

class ShowCloseoutPage extends StatefulWidget {
  final String showId;
  final String showName;

  const ShowCloseoutPage({
    super.key,
    required this.showId,
    required this.showName,
  });

  @override
  State<ShowCloseoutPage> createState() => _ShowCloseoutPageState();
}

class _ShowCloseoutPageState extends State<ShowCloseoutPage> {
  final _secretaryNameController = TextEditingController();
  final _secretaryAddressController = TextEditingController();
  final _secretaryEmailController = TextEditingController();
  final _secretaryPhoneController = TextEditingController();
  final _superintendentController = TextEditingController();
  final _superintendentNumberController = TextEditingController();
  final _sweepstakesClubController = TextEditingController();

  bool _sweepstakesIssue = false;
  bool _officialProtest = false;
  bool _arbaReportFiled = false;

  bool _loading = true;
  bool _generatingReport = false;
  String? _error;

  CloseoutDashboard? _dashboard;

  static const Set<String> _exhibitorReportKeys = {
    'exhibitor_report',
    'legs',
  };

  static const Set<String> _clubReportKeys = {
    'cavy_points',
    'commercial_points',
    'details_by_breed',
    'exh_by_breed',
    'exh_total_points',
    'fur_points',
    'newsletter_show_report',
  };

  static const Set<String> _arbaReportKeys = {
    'arba_report',
  };

  static const List<String> _reportDisplayOrder = [
    'arba_report',
    'exhibitor_report',
    'legs',
    'newsletter_show_report',
    'exh_total_points',
    'exh_by_breed',
    'details_by_breed',
    'fur_points',
    'cavy_points',
    'commercial_points',
    'judge_report',
    'finalized_show_report',
    'show_statistics',
    'overall_standings',
    'group_standings',
    'variety_standings',
    'class_standings',
    'points_report_csv',
    'control_sheet',
    'checkin_sheet',
    'commercial_class_points',
    'newsletter',
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_loadData());
  }

  @override
  void dispose() {
    _secretaryNameController.dispose();
    _secretaryAddressController.dispose();
    _secretaryEmailController.dispose();
    _secretaryPhoneController.dispose();
    _superintendentController.dispose();
    _superintendentNumberController.dispose();
    _sweepstakesClubController.dispose();
    super.dispose();
  }

  Future<void> _loadArbaDetails() async {
    final row = await supabase
        .from('show_arba_report_details')
        .select('''
          secretary_name,
          secretary_address,
          secretary_email,
          secretary_phone,
          superintendent_name,
          superintendent_arba_number,
          sweepstakes_issue,
          sweepstakes_club,
          official_protest,
          arba_report_filed
        ''')
        .eq('show_id', widget.showId)
        .maybeSingle();

    if (row == null) return;

    _secretaryNameController.text = (row['secretary_name'] ?? '').toString();
    _secretaryAddressController.text =
        (row['secretary_address'] ?? '').toString();
    _secretaryEmailController.text = (row['secretary_email'] ?? '').toString();
    _secretaryPhoneController.text = (row['secretary_phone'] ?? '').toString();
    _superintendentController.text =
        (row['superintendent_name'] ?? '').toString();
    _superintendentNumberController.text =
        (row['superintendent_arba_number'] ?? '').toString();

    _sweepstakesIssue = row['sweepstakes_issue'] == true;
    _sweepstakesClubController.text =
        (row['sweepstakes_club'] ?? '').toString();
    _officialProtest = row['official_protest'] == true;
    _arbaReportFiled = _officialProtest && row['arba_report_filed'] == true;
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final dashboardResp = await supabase.rpc(
        'get_show_closeout_dashboard',
        params: {'p_show_id': widget.showId},
      );

      final dashboardJson = Map<String, dynamic>.from(dashboardResp as Map);
      final dashboard = CloseoutDashboard.fromJson(dashboardJson);

      await _loadArbaDetails();

      if (!mounted) return;
      setState(() {
        _dashboard = dashboard;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveArbaDetails() async {
    try {
      await supabase.from('show_arba_report_details').upsert({
        'show_id': widget.showId,
        'secretary_name': _secretaryNameController.text.trim(),
        'secretary_address': _secretaryAddressController.text.trim(),
        'secretary_email': _secretaryEmailController.text.trim(),
        'secretary_phone': _secretaryPhoneController.text.trim(),
        'superintendent_name': _superintendentController.text.trim(),
        'superintendent_arba_number':
            _superintendentNumberController.text.trim(),
        'sweepstakes_issue': _sweepstakesIssue,
        'sweepstakes_club': _sweepstakesIssue
            ? _sweepstakesClubController.text.trim()
            : null,
        'official_protest': _officialProtest,
        'arba_report_filed': _officialProtest ? _arbaReportFiled : null,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ARBA closeout details saved.')),
      );

      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save ARBA details: $e')),
      );
    }
  }

  Future<void> _generateReportByName(String reportName) async {
    try {
      setState(() {
        _generatingReport = true;
        _error = null;
      });

      // Save latest ARBA form data before generating any report.
      await _saveArbaDetails();

      final repository = CloseoutRepository(supabase);
      final arbaLoader = ArbaReportLoader(repository);
      final arbaBuilder = ArbaReportPdfBuilder();

      final registry = ReportRegistry(
        arbaLoader: arbaLoader,
        arbaBuilder: arbaBuilder,
      );

      final engine = ReportEngine(registry);
      final uploadService = ReportUploadService(supabase);

      final runner = CloseoutRunner(
        engine: engine,
        uploadService: uploadService,
      );

      final artifact = (_dashboard?.reports ?? const <ReportArtifactSummary>[])
          .where((r) => r.reportName == reportName)
          .cast<ReportArtifactSummary?>()
          .firstWhere(
            (r) => r != null,
            orElse: () => null,
          );

      await runner.generateSingleReport(
        showId: widget.showId,
        finalizeRunId: _dashboard?.latestFinalize.id ?? 'manual-run',
        reportName: reportName,
        artifactId: artifact?.id ?? '${reportName}_manual',
      );

      await _loadData();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_friendlyReportName(reportName)} generated.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate report: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _generatingReport = false;
        });
      }
    }
  }

  Future<void> _downloadReportByName(String reportName) async {
    try {
      final reports = _dashboard?.reports ?? const <ReportArtifactSummary>[];

      final matches = reports
          .where((r) =>
              r.reportName == reportName &&
              r.artifactStatus == 'generated' &&
              (r.storageBucket?.isNotEmpty == true) &&
              (r.storagePath?.isNotEmpty == true))
          .toList()
        ..sort((a, b) {
          final aDt = DateTime.tryParse(a.generatedAt ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bDt = DateTime.tryParse(b.generatedAt ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bDt.compareTo(aDt);
        });

      if (matches.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('No generated ${_friendlyReportName(reportName)} found.'),
          ),
        );
        return;
      }

      final newest = matches.first;

      final signedUrl = await supabase.storage
          .from(newest.storageBucket!)
          .createSignedUrl(newest.storagePath!, 60 * 5);

      await launchUrlString(
        signedUrl,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    }
  }

  Future<void> _emailReportByName(String reportName) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Email ${_friendlyReportName(reportName)} coming next.',
        ),
      ),
    );
  }

  List<ReportArtifactSummary> _reportsForGroup(String groupKey) {
    final reports = _dashboard?.reports ?? const <ReportArtifactSummary>[];

    final filtered = switch (groupKey) {
      'arba' => reports.where((r) => _arbaReportKeys.contains(r.reportName)),
      'exhibitor' =>
        reports.where((r) => _exhibitorReportKeys.contains(r.reportName)),
      'club' => reports.where((r) => _clubReportKeys.contains(r.reportName)),
      'other' => reports.where((r) {
          return !_arbaReportKeys.contains(r.reportName) &&
              !_exhibitorReportKeys.contains(r.reportName) &&
              !_clubReportKeys.contains(r.reportName);
        }),
      _ => reports,
    }.toList();

    filtered.sort((a, b) {
      final aIndex = _reportDisplayOrder.indexOf(a.reportName);
      final bIndex = _reportDisplayOrder.indexOf(b.reportName);

      if (aIndex == -1 && bIndex == -1) {
        return _friendlyReportName(a.reportName)
            .compareTo(_friendlyReportName(b.reportName));
      }
      if (aIndex == -1) return 1;
      if (bIndex == -1) return -1;
      return aIndex.compareTo(bIndex);
    });

    return filtered;
  }

  List<String> _reportNamesForGroup(String groupKey) {
    final reports = _reportsForGroup(groupKey);
    final names = reports.map((r) => r.reportName).toSet().toList();

    if (groupKey == 'arba') {
      for (final name in _arbaReportKeys) {
        if (!names.contains(name)) names.add(name);
      }
    } else if (groupKey == 'exhibitor') {
      for (final name in _exhibitorReportKeys) {
        if (!names.contains(name)) names.add(name);
      }
    } else if (groupKey == 'club') {
      for (final name in _clubReportKeys) {
        if (!names.contains(name)) names.add(name);
      }
    }

    names.sort((a, b) {
      final aIndex = _reportDisplayOrder.indexOf(a);
      final bIndex = _reportDisplayOrder.indexOf(b);

      if (aIndex == -1 && bIndex == -1) {
        return _friendlyReportName(a).compareTo(_friendlyReportName(b));
      }
      if (aIndex == -1) return 1;
      if (bIndex == -1) return -1;
      return aIndex.compareTo(bIndex);
    });

    return names;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.showName} • Closeout'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadData,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _loadData)
              : _dashboard == null
                  ? const Center(child: Text('No closeout data found.'))
                  : RefreshIndicator(
                      onRefresh: _loadData,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _ArbaCloseoutCard(
                            secretaryNameController: _secretaryNameController,
                            secretaryAddressController:
                                _secretaryAddressController,
                            secretaryEmailController: _secretaryEmailController,
                            secretaryPhoneController: _secretaryPhoneController,
                            superintendentController: _superintendentController,
                            superintendentNumberController:
                                _superintendentNumberController,
                            sweepstakesIssue: _sweepstakesIssue,
                            sweepstakesClubController:
                                _sweepstakesClubController,
                            onSweepstakesChanged: (v) {
                              setState(() {
                                _sweepstakesIssue = v;
                                if (!v) {
                                  _sweepstakesClubController.clear();
                                }
                              });
                            },
                            onSweepstakesClubChanged: (_) {},
                            officialProtest: _officialProtest,
                            onOfficialProtestChanged: (v) {
                              setState(() {
                                _officialProtest = v;
                                if (!v) {
                                  _arbaReportFiled = false;
                                }
                              });
                            },
                            arbaReportFiled: _arbaReportFiled,
                            onArbaReportFiledChanged: (v) {
                              setState(() => _arbaReportFiled = v);
                            },
                            onSave: _saveArbaDetails,
                          ),
                          const SizedBox(height: 16),
                          _ReportActionsCard(
                            reports: _dashboard?.reports ??
                                const <ReportArtifactSummary>[],
                            groupedReportNames: {
                              'arba': _reportNamesForGroup('arba'),
                              'exhibitor': _reportNamesForGroup('exhibitor'),
                              'club': _reportNamesForGroup('club'),
                              'other': _reportNamesForGroup('other'),
                            },
                            onGenerate: _generateReportByName,
                            onDownload: _downloadReportByName,
                            onEmail: _emailReportByName,
                            loading: _generatingReport,
                          ),
                        ],
                      ),
                    ),
    );
  }
}

class _ArbaCloseoutCard extends StatelessWidget {
  final TextEditingController secretaryNameController;
  final TextEditingController secretaryAddressController;
  final TextEditingController secretaryEmailController;
  final TextEditingController secretaryPhoneController;
  final TextEditingController superintendentController;
  final TextEditingController superintendentNumberController;
  final TextEditingController sweepstakesClubController;

  final bool sweepstakesIssue;
  final ValueChanged<bool> onSweepstakesChanged;
  final ValueChanged<String> onSweepstakesClubChanged;

  final bool officialProtest;
  final ValueChanged<bool> onOfficialProtestChanged;

  final bool arbaReportFiled;
  final ValueChanged<bool> onArbaReportFiledChanged;

  final Future<void> Function() onSave;

  const _ArbaCloseoutCard({
    required this.secretaryNameController,
    required this.secretaryAddressController,
    required this.secretaryEmailController,
    required this.secretaryPhoneController,
    required this.superintendentController,
    required this.superintendentNumberController,
    required this.sweepstakesIssue,
    required this.sweepstakesClubController,
    required this.onSweepstakesChanged,
    required this.onSweepstakesClubChanged,
    required this.officialProtest,
    required this.onOfficialProtestChanged,
    required this.arbaReportFiled,
    required this.onArbaReportFiledChanged,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ARBA Final Closeout Confirmation',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: secretaryNameController,
              decoration: const InputDecoration(
                labelText: 'Show Secretary Name',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: secretaryAddressController,
              decoration: const InputDecoration(
                labelText: 'Secretary Address',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: secretaryEmailController,
              decoration: const InputDecoration(
                labelText: 'Secretary Email',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: secretaryPhoneController,
              decoration: const InputDecoration(
                labelText: 'Secretary Phone',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: superintendentController,
              decoration: const InputDecoration(
                labelText: 'Superintendent Name',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: superintendentNumberController,
              decoration: const InputDecoration(
                labelText: 'Superintendent ARBA Number',
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'ANY TROUBLE RECEIVING SWEEPSTAKES SANCTIONS FROM NATIONAL SPECIALTY CLUBS?',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(sweepstakesIssue ? 'Yes' : 'No'),
              value: sweepstakesIssue,
              onChanged: onSweepstakesChanged,
            ),
            if (sweepstakesIssue)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: sweepstakesClubController,
                  decoration: const InputDecoration(
                    labelText: 'Which club(s)?',
                  ),
                  onChanged: onSweepstakesClubChanged,
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Was there an official protest filed at this show?',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(officialProtest ? 'Yes' : 'No'),
              value: officialProtest,
              onChanged: onOfficialProtestChanged,
            ),
            if (officialProtest)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(arbaReportFiled ? 'Yes' : 'No'),
                subtitle: const Text('Has a report been filed with ARBA?'),
                value: arbaReportFiled,
                onChanged: onArbaReportFiledChanged,
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.save),
              label: const Text('Save ARBA Closeout Info'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportActionsCard extends StatefulWidget {
  final List<ReportArtifactSummary> reports;
  final Map<String, List<String>> groupedReportNames;
  final Future<void> Function(String reportName) onGenerate;
  final Future<void> Function(String reportName) onDownload;
  final Future<void> Function(String reportName) onEmail;
  final bool loading;

  const _ReportActionsCard({
    required this.reports,
    required this.groupedReportNames,
    required this.onGenerate,
    required this.onDownload,
    required this.onEmail,
    required this.loading,
  });

  @override
  State<_ReportActionsCard> createState() => _ReportActionsCardState();
}

class _ReportActionsCardState extends State<_ReportActionsCard> {
  String _selectedGroup = 'arba';
  String? _selectedReportName = 'arba_report';

  static const Map<String, String> _groupLabels = {
    'arba': 'ARBA Reports',
    'exhibitor': 'Exhibitor Reports',
    'club': 'Club Reports',
    'other': 'Other Reports',
  };

  List<String> get _currentReports =>
      widget.groupedReportNames[_selectedGroup] ?? const [];

  ReportArtifactSummary? get _selectedArtifact {
    final reportName = _selectedReportName;
    if (reportName == null) return null;

    final matches = widget.reports
        .where((r) => r.reportName == reportName)
        .toList()
      ..sort((a, b) {
        final aDt = DateTime.tryParse(a.generatedAt ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDt = DateTime.tryParse(b.generatedAt ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bDt.compareTo(aDt);
      });

    if (matches.isEmpty) return null;
    return matches.first;
  }

  bool get _canDownload {
    final artifact = _selectedArtifact;
    return artifact != null &&
        artifact.artifactStatus == 'generated' &&
        (artifact.storageBucket?.isNotEmpty == true) &&
        (artifact.storagePath?.isNotEmpty == true);
  }

  @override
  void didUpdateWidget(covariant _ReportActionsCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    final reports = _currentReports;
    if (reports.isEmpty) {
      _selectedReportName = null;
      return;
    }

    if (_selectedReportName == null || !reports.contains(_selectedReportName)) {
      _selectedReportName = reports.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final artifact = _selectedArtifact;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reports & Distribution',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedGroup,
              decoration: const InputDecoration(
                labelText: 'Report Group',
                border: OutlineInputBorder(),
              ),
              items: _groupLabels.entries
                  .map(
                    (entry) => DropdownMenuItem<String>(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;

                final reports = widget.groupedReportNames[value] ?? const [];

                setState(() {
                  _selectedGroup = value;
                  _selectedReportName = reports.isEmpty ? null : reports.first;
                });
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _currentReports.contains(_selectedReportName)
                  ? _selectedReportName
                  : (_currentReports.isNotEmpty ? _currentReports.first : null),
              decoration: const InputDecoration(
                labelText: 'Report',
                border: OutlineInputBorder(),
              ),
              items: _currentReports
                  .map(
                    (reportName) => DropdownMenuItem<String>(
                      value: reportName,
                      child: Text(_friendlyReportName(reportName)),
                    ),
                  )
                  .toList(),
              onChanged: _currentReports.isEmpty
                  ? null
                  : (value) {
                      setState(() {
                        _selectedReportName = value;
                      });
                    },
            ),
            const SizedBox(height: 16),
            _ReportInfoTile(
              reportName: _selectedReportName == null
                  ? '-'
                  : _friendlyReportName(_selectedReportName),
              status: artifact?.artifactStatus ?? 'not_generated',
              generatedAt: artifact?.generatedAt,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: widget.loading || _selectedReportName == null
                      ? null
                      : () => widget.onGenerate(_selectedReportName!),
                  icon: widget.loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.picture_as_pdf),
                  label: Text(widget.loading ? 'Generating…' : 'Generate'),
                ),
                OutlinedButton.icon(
                  onPressed: _canDownload && _selectedReportName != null
                      ? () => widget.onDownload(_selectedReportName!)
                      : null,
                  icon: const Icon(Icons.download),
                  label: const Text('Download'),
                ),
                OutlinedButton.icon(
                  onPressed: _canDownload && _selectedReportName != null
                      ? () => widget.onEmail(_selectedReportName!)
                      : null,
                  icon: const Icon(Icons.email_outlined),
                  label: const Text('Email'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportInfoTile extends StatelessWidget {
  final String reportName;
  final String status;
  final String? generatedAt;

  const _ReportInfoTile({
    required this.reportName,
    required this.status,
    required this.generatedAt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(reportName, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Text('Status: ${_friendlyStatus(status)}'),
          const SizedBox(height: 4),
          Text('Last generated: ${_fmt(generatedAt)}'),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorView({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

String _fmt(String? value) {
  if (value == null || value.isEmpty) return '-';
  try {
    final dt = DateTime.parse(value).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  } catch (_) {
    return value;
  }
}

String _friendlyStatus(String status) {
  switch (status) {
    case 'generated':
      return 'Generated';
    case 'queued':
      return 'Queued';
    case 'failed':
      return 'Failed';
    case 'warning':
      return 'Warning';
    default:
      return status.isEmpty ? '-' : status;
  }
}

String _friendlyReportName(String? key) {
  switch (key) {
    case 'arba_report':
      return 'ARBA Report';
    case 'judge_report':
      return 'Judge Report';
    case 'finalized_show_report':
      return 'Finalized Show Report';
    case 'details_by_breed':
      return 'Details by Breed';
    case 'newsletter_show_report':
      return 'Newsletter Show Report';
    case 'show_statistics':
      return 'Show Statistics';
    case 'overall_standings':
      return 'Overall Standings';
    case 'group_standings':
      return 'Group Standings';
    case 'variety_standings':
      return 'Variety Standings';
    case 'class_standings':
      return 'Class Standings';
    case 'fur_points':
      return 'Fur Points';
    case 'cavy_points':
      return 'Cavy Points';
    case 'commercial_points':
      return 'Commercial Points';
    case 'points_report_csv':
      return 'Points Report CSV';
    case 'control_sheet':
      return 'Control Sheet';
    case 'checkin_sheet':
      return 'Check-In Sheet';
    case 'exhibitor_report':
      return 'Exhibitor Report';
    case 'legs':
      return 'Legs';
    case 'commercial_class_points':
      return 'Commercial Class Points';
    case 'exh_by_breed':
      return 'Exhibitor by Breed';
    case 'exh_total_points':
      return 'Exhibitor Total Points';
    case 'newsletter':
      return 'Newsletter';
    case null:
      return '-';
    default:
      return key
          .split('_')
          .map(
            (w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}',
          )
          .join(' ');
  }
}

class CloseoutDashboard {
  final DashboardEnvelope dashboard;
  final LatestFinalize latestFinalize;
  final List<ReportArtifactSummary> reports;
  final List<DeliveryRunSummary> deliveries;
  final ArchiveSummary? latestArchive;

  CloseoutDashboard({
    required this.dashboard,
    required this.latestFinalize,
    required this.reports,
    required this.deliveries,
    required this.latestArchive,
  });

  factory CloseoutDashboard.fromJson(Map<String, dynamic> json) {
    return CloseoutDashboard(
      dashboard: DashboardEnvelope.fromJson(
        Map<String, dynamic>.from(json['dashboard'] ?? const {}),
      ),
      latestFinalize: LatestFinalize.fromJson(
        Map<String, dynamic>.from(json['latest_finalize'] ?? const {}),
      ),
      reports: List<Map<String, dynamic>>.from(
        (json['reports'] ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map)),
      ).map(ReportArtifactSummary.fromJson).toList(),
      deliveries: List<Map<String, dynamic>>.from(
        (json['deliveries'] ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map)),
      ).map(DeliveryRunSummary.fromJson).toList(),
      latestArchive: json['latest_archive'] == null ||
              (json['latest_archive'] as Map).isEmpty
          ? null
          : ArchiveSummary.fromJson(
              Map<String, dynamic>.from(json['latest_archive'] as Map),
            ),
    );
  }
}

class DashboardEnvelope {
  final String showId;
  final String showName;
  final int resultsVersion;
  final String? resultsLastChangedAt;
  final CloseoutStateDto closeout;

  DashboardEnvelope({
    required this.showId,
    required this.showName,
    required this.resultsVersion,
    required this.resultsLastChangedAt,
    required this.closeout,
  });

  factory DashboardEnvelope.fromJson(Map<String, dynamic> json) {
    return DashboardEnvelope(
      showId: (json['show_id'] ?? '') as String,
      showName: (json['show_name'] ?? '') as String,
      resultsVersion: ((json['results_version'] ?? 0) as num).toInt(),
      resultsLastChangedAt: json['results_last_changed_at'] as String?,
      closeout: CloseoutStateDto.fromJson(
        Map<String, dynamic>.from(json['closeout'] ?? const {}),
      ),
    );
  }
}

class CloseoutStateDto {
  final String syncStatus;
  final bool isPointsStale;
  final bool isReportsStale;
  final bool hasWarnings;
  final bool hasBlockingErrors;
  final bool isArchived;
  final int warningCount;
  final int errorCount;
  final int blockingErrorCount;
  final int reportsGeneratedCount;
  final String? finalizedAt;
  final String? pointsGeneratedAt;
  final String? reportsGeneratedAt;
  final String? validationCheckedAt;
  final String? resultsLastChangedAt;
  final String? lastFinalizeMessage;

  CloseoutStateDto({
    required this.syncStatus,
    required this.isPointsStale,
    required this.isReportsStale,
    required this.hasWarnings,
    required this.hasBlockingErrors,
    required this.isArchived,
    required this.warningCount,
    required this.errorCount,
    required this.blockingErrorCount,
    required this.reportsGeneratedCount,
    required this.finalizedAt,
    required this.pointsGeneratedAt,
    required this.reportsGeneratedAt,
    required this.validationCheckedAt,
    required this.resultsLastChangedAt,
    required this.lastFinalizeMessage,
  });

  factory CloseoutStateDto.fromJson(Map<String, dynamic> json) {
    return CloseoutStateDto(
      syncStatus: (json['sync_status'] ?? 'not_ready') as String,
      isPointsStale: (json['is_points_stale'] ?? true) as bool,
      isReportsStale: (json['is_reports_stale'] ?? true) as bool,
      hasWarnings: (json['has_warnings'] ?? false) as bool,
      hasBlockingErrors: (json['has_blocking_errors'] ?? false) as bool,
      isArchived: (json['is_archived'] ?? false) as bool,
      warningCount: ((json['warning_count'] ?? 0) as num).toInt(),
      errorCount: ((json['error_count'] ?? 0) as num).toInt(),
      blockingErrorCount:
          ((json['blocking_error_count'] ?? 0) as num).toInt(),
      reportsGeneratedCount:
          ((json['reports_generated_count'] ?? 0) as num).toInt(),
      finalizedAt: json['finalized_at'] as String?,
      pointsGeneratedAt: json['points_generated_at'] as String?,
      reportsGeneratedAt: json['reports_generated_at'] as String?,
      validationCheckedAt: json['validation_checked_at'] as String?,
      resultsLastChangedAt: json['results_last_changed_at'] as String?,
      lastFinalizeMessage: json['last_finalize_message'] as String?,
    );
  }
}

class LatestFinalize {
  final String? id;
  final String? runStatus;
  final String? startedAt;
  final String? completedAt;

  LatestFinalize({
    this.id,
    this.runStatus,
    this.startedAt,
    this.completedAt,
  });

  factory LatestFinalize.fromJson(Map<String, dynamic> json) {
    return LatestFinalize(
      id: json['id'] as String?,
      runStatus: json['run_status'] as String?,
      startedAt: json['started_at'] as String?,
      completedAt: json['completed_at'] as String?,
    );
  }
}

class ReportArtifactSummary {
  final String id;
  final String reportName;
  final String artifactStatus;
  final String? fileName;
  final String? storageBucket;
  final String? storagePath;
  final String? generatedAt;

  ReportArtifactSummary({
    required this.id,
    required this.reportName,
    required this.artifactStatus,
    this.fileName,
    this.storageBucket,
    this.storagePath,
    this.generatedAt,
  });

  factory ReportArtifactSummary.fromJson(Map<String, dynamic> json) {
    return ReportArtifactSummary(
      id: (json['id'] ?? '') as String,
      reportName: (json['report_name'] ?? '') as String,
      artifactStatus: (json['artifact_status'] ?? 'queued') as String,
      fileName: json['file_name'] as String?,
      storageBucket: json['storage_bucket'] as String?,
      storagePath: json['storage_path'] as String?,
      generatedAt: json['generated_at'] as String?,
    );
  }
}

class DeliveryRunSummary {
  final String id;
  final String deliveryType;
  final String deliveryStatus;

  DeliveryRunSummary({
    required this.id,
    required this.deliveryType,
    required this.deliveryStatus,
  });

  factory DeliveryRunSummary.fromJson(Map<String, dynamic> json) {
    return DeliveryRunSummary(
      id: (json['id'] ?? '') as String,
      deliveryType: (json['delivery_type'] ?? '') as String,
      deliveryStatus: (json['delivery_status'] ?? '') as String,
    );
  }
}

class ArchiveSummary {
  final String id;
  final int archiveVersion;
  final String archiveStatus;

  ArchiveSummary({
    required this.id,
    required this.archiveVersion,
    required this.archiveStatus,
  });

  factory ArchiveSummary.fromJson(Map<String, dynamic> json) {
    return ArchiveSummary(
      id: (json['id'] ?? '') as String,
      archiveVersion: ((json['archive_version'] ?? 0) as num).toInt(),
      archiveStatus: (json['archive_status'] ?? '') as String,
    );
  }
}