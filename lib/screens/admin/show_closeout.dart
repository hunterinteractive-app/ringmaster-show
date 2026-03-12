// lib/screens/admin/show_closeout.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'edit_show_settings_screen.dart';
import 'results/admin_results_entry_screen.dart';

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
    bool _shouldDisplayIssue(ValidationIssue issue) {
      // Hide noisy informational warnings that should not block closeout UI.
      const hiddenWarningCodes = <String>{
        'points_skipped_entry',
      };

      if (hiddenWarningCodes.contains(issue.issueCode)) {
        return false;
      }

      return true;
    }

    List<ValidationIssue> _dedupeIssues(List<ValidationIssue> issues) {
      final seen = <String>{};
      final result = <ValidationIssue>[];

      for (final issue in issues) {
        final key = [
          issue.level,
          issue.issueCode,
          issue.issueMessage.trim(),
          issue.reportName ?? '',
          issue.entryId ?? '',
          issue.classKey ?? '',
          issue.exhibitorId ?? '',
          issue.animalId ?? '',
        ].join('|');

        if (seen.add(key)) {
          result.add(issue);
        }
      }

      return result;
    }

    Future<void> _processQueuedReports() async {
      setState(() {
        _loading = true;
        _error = null;
      });

      try {
        await _drainFinalizeQueue();
        await _loadData();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Queued reports processed.')),
        );
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _error = e.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Processing failed: $e')),
        );
      } finally {
        if (mounted) {
          setState(() {
            _loading = false;
          });
        }
      }
    }

    List<ValidationIssue> _cleanIssues(List<ValidationIssue> issues) {
      final visible = issues.where(_shouldDisplayIssue).toList();
      final deduped = _dedupeIssues(visible);

      deduped.sort((a, b) {
        int levelRank(String level) {
          switch (level) {
            case 'blocking':
              return 0;
            case 'error':
              return 1;
            case 'warning':
              return 2;
            default:
              return 99;
          }
        }

        final lr = levelRank(a.level).compareTo(levelRank(b.level));
        if (lr != 0) return lr;

        final rr = (a.reportName ?? '').compareTo(b.reportName ?? '');
        if (rr != 0) return rr;

        return a.issueMessage.compareTo(b.issueMessage);
      });

      return deduped;
    }
  bool _loading = true;
  bool _finalizing = false;
  String? _error;

  CloseoutDashboard? _dashboard;
  List<ValidationIssue> _validationIssues = const [];

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

  List<ReportArtifactSummary> _reportsFor(Set<String> keys) {
    final reports = _dashboard?.reports ?? const <ReportArtifactSummary>[];
    return reports.where((r) => keys.contains(r.reportName)).toList()
      ..sort((a, b) => _friendlyReportName(a.reportName)
          .compareTo(_friendlyReportName(b.reportName)));
  }

  List<ReportArtifactSummary> _otherReports() {
    final reports = _dashboard?.reports ?? const <ReportArtifactSummary>[];
    return reports.where((r) {
      return !_exhibitorReportKeys.contains(r.reportName) &&
          !_clubReportKeys.contains(r.reportName) &&
          !_arbaReportKeys.contains(r.reportName);
    }).toList()
      ..sort((a, b) => _friendlyReportName(a.reportName)
          .compareTo(_friendlyReportName(b.reportName)));
  }

  bool _allGenerated(List<ReportArtifactSummary> reports) {
    if (reports.isEmpty) return false;
    return reports.every((r) => r.artifactStatus == 'generated');
  }

  Future<void> _sendExhibitorReports() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Send Exhibitor Reports coming next.')),
    );
  }

  Future<void> _sendClubReports() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Send Club Reports coming next.')),
    );
  }

  Future<void> _sendArbaReports() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Send ARBA Reports coming next.')),
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadData());
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

      final issuesResp = await supabase.rpc(
        'get_show_validation_issues',
        params: {'p_show_id': widget.showId},
      );

      final dashboardJson = Map<String, dynamic>.from(dashboardResp as Map);
      final issuesJson = List<Map<String, dynamic>>.from(
        ((issuesResp as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map)),
      );

      final dashboard = CloseoutDashboard.fromJson(dashboardJson);
      final allIssues = issuesJson.map(ValidationIssue.fromJson).toList();

      final latestRunId = dashboard.latestFinalize.id;
      final latestRunIssues = latestRunId == null || latestRunId.isEmpty
          ? allIssues
          : allIssues.where((i) => i.finalizeRunId == latestRunId).toList();

      final cleanedIssues = _cleanIssues(latestRunIssues);

      setState(() {
        _dashboard = dashboard;
        _validationIssues = cleanedIssues;
      });
    } catch (e) {
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

  Future<void> _runFinalize() async {
    setState(() {
      _finalizing = true;
      _error = null;
    });

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('You must be signed in to finalize a show.');
      }

      await supabase.rpc(
        'run_show_finalize_pipeline',
        params: {
          'p_show_id': widget.showId,
          'p_triggered_by_user_id': userId,
        },
      );

      await _drainFinalizeQueue();
      await _loadData();

      if (!mounted) return;
      _showFinalizeSummary();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Finalize failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _finalizing = false;
        });
      }
    }
  }

    Future<void> _drainFinalizeQueue() async {
    const maxAttempts = 60;

    for (var i = 0; i < maxAttempts; i++) {
      final queued = await supabase
          .from('show_task_queue')
          .select('id, task_type, task_status')
          .eq('show_id', widget.showId)
          .inFilter('task_status', ['queued', 'claimed']);

      final rows = (queued as List).cast<Map<String, dynamic>>();
      if (rows.isEmpty) {
        break;
      }

      final resp = await supabase.functions.invoke(
        'process-show-task',
        body: {},
      );

      if (resp.status >= 400) {
        throw Exception('Worker invocation failed: ${resp.data}');
      }

      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
  }

    Future<void> _openIssueFix(ValidationIssue issue) async {
      switch (issue.issueCode) {
        case 'no_judges_assigned':
          // Most useful place for this warning is Results Entry,
          // because that's where class-level judged_by_show_judge_id gets assigned.
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AdminResultsEntryScreen(
                showId: widget.showId,
                showName: widget.showName,
              ),
            ),
          );
          await _loadData();
          return;

        case 'missing_secretary_email':
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EditShowSettingsScreen(showId: widget.showId),
            ),
          );
          await _loadData();
          return;

        case 'points_skipped_entry':
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AdminResultsEntryScreen(
                showId: widget.showId,
                showName: widget.showName,
              ),
            ),
          );
          await _loadData();
          return;

        default:
          _showIssueDetails(issue);
          return;
      }
    }

  void _showIssueDetails(ValidationIssue issue) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  issue.issueMessage,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _IssueLevelChip(level: issue.level),
                    Chip(label: Text(_friendlyReportName(issue.reportName))),
                    Chip(label: Text(issue.issueCode)),
                  ],
                ),
                const SizedBox(height: 16),
                if (issue.entryId != null && issue.entryId!.isNotEmpty)
                  Text('Entry ID: ${issue.entryId}'),
                if (issue.rawPlacement != null && issue.rawPlacement!.isNotEmpty)
                  Text('Raw placement: ${issue.rawPlacement}'),
                if (issue.classKey != null && issue.classKey!.isNotEmpty)
                  Text('Class: ${issue.classKey}'),
                if (issue.exhibitorId != null && issue.exhibitorId!.isNotEmpty)
                  Text('Exhibitor ID: ${issue.exhibitorId}'),
                if (issue.animalId != null && issue.animalId!.isNotEmpty)
                  Text('Animal ID: ${issue.animalId}'),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _openIssueFix(issue);
                    },
                    icon: const Icon(Icons.build_circle_outlined),
                    label: const Text('Fix Issue'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAllIssuesSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'All Validation Issues',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _validationIssues.isEmpty
                      ? 'No validation issues found.'
                      : '${_validationIssues.length} issue${_validationIssues.length == 1 ? '' : 's'} found.',
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _validationIssues.isEmpty
                    ? const Align(
                        alignment: Alignment.topLeft,
                        child: Text('Everything looks good so far.'),
                      )
                    : ListView.separated(
                        itemCount: _validationIssues.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final issue = _validationIssues[index];
                          return _IssueTile(
                            issue: issue,
                            onTap: () {
                              Navigator.pop(context);
                              _openIssueFix(issue);
                            },
                            onFix: () {
                              Navigator.pop(context);
                              _openIssueFix(issue);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFinalizeSummary() {
    final blocking =
        _validationIssues.where((i) => i.level == 'blocking').length;
    final errors = _validationIssues.where((i) => i.level == 'error').length;
    final warnings =
        _validationIssues.where((i) => i.level == 'warning').length;

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finalize Complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Blocking issues: $blocking'),
            Text('Errors: $errors'),
            Text('Warnings: $warnings'),
            const SizedBox(height: 12),
            Text(_dashboard?.dashboard.closeout.lastFinalizeMessage ?? ''),
          ],
        ),
        actions: [
          if (_validationIssues.isNotEmpty)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showAllIssuesSheet();
              },
              child: const Text('View Issues'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
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
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _CloseoutStatusCard(
                        dashboard: _dashboard!,
                        onFinalize: _finalizing ? null : _runFinalize,
                        onProcessQueuedReports: _loading ? null : _processQueuedReports,
                        finalizing: _finalizing,
                      ),
                      const SizedBox(height: 16),
                      _ValidationSummaryCard(
                        issues: _validationIssues,
                        onIssueTap: _openIssueFix,
                        onViewAll: _validationIssues.isEmpty
                            ? null
                            : _showAllIssuesSheet,
                      ),
                      const SizedBox(height: 16),
                      _DistributionAndReportsCard(
                        exhibitorReports: _reportsFor(_exhibitorReportKeys),
                        clubReports: _reportsFor(_clubReportKeys),
                        arbaReports: _reportsFor(_arbaReportKeys),
                        otherReports: _otherReports(),
                        onSendExhibitor: _sendExhibitorReports,
                        onSendClub: _sendClubReports,
                        onSendArba: _sendArbaReports,
                        canSendExhibitor: _allGenerated(_reportsFor(_exhibitorReportKeys)),
                        canSendClub: _allGenerated(_reportsFor(_clubReportKeys)),
                        canSendArba: _allGenerated(_reportsFor(_arbaReportKeys)),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _CloseoutStatusCard extends StatelessWidget {
  final CloseoutDashboard dashboard;
  final VoidCallback? onFinalize;
  final VoidCallback? onProcessQueuedReports;
  final bool finalizing;

  const _CloseoutStatusCard({
    required this.dashboard,
    required this.onFinalize,
    required this.onProcessQueuedReports,
    required this.finalizing,
  });

  Color _statusColor(BuildContext context, String status) {
    switch (status) {
      case 'in_sync':
        return Colors.green;
      case 'warning':
        return Colors.orange;
      case 'error':
        return Colors.red;
      case 'dirty':
        return Colors.amber.shade800;
      case 'archived':
        return Colors.deepPurple;
      default:
        return Theme.of(context).colorScheme.outline;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'in_sync':
        return 'In Sync';
      case 'warning':
        return 'Warnings';
      case 'error':
        return 'Errors Found';
      case 'dirty':
        return 'Out of Sync';
      case 'archived':
        return 'Archived';
      case 'in_progress':
        return 'In Progress';
      default:
        return 'Not Ready';
    }
  }

  @override
  Widget build(BuildContext context) {
    final closeout = dashboard.dashboard.closeout;
    final statusColor = _statusColor(context, closeout.syncStatus);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Show Closeout Status',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                Chip(
                  label: Text(_statusLabel(closeout.syncStatus)),
                  backgroundColor: statusColor.withOpacity(0.12),
                  side: BorderSide(color: statusColor.withOpacity(0.35)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                _StatTile(
                  label: 'Results Version',
                  value: '${dashboard.dashboard.resultsVersion}',
                ),
                _StatTile(
                  label: 'Warnings',
                  value: '${closeout.warningCount}',
                ),
                _StatTile(
                  label: 'Errors',
                  value: '${closeout.errorCount}',
                ),
                _StatTile(
                  label: 'Blocking',
                  value: '${closeout.blockingErrorCount}',
                ),
                _StatTile(
                  label: 'Reports',
                  value: '${closeout.reportsGeneratedCount}',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Last message: ${closeout.lastFinalizeMessage ?? '-'}'),
            const SizedBox(height: 6),
            Text(
              'Results changed: ${_fmt(closeout.resultsLastChangedAt ?? dashboard.dashboard.resultsLastChangedAt)}',
            ),
            Text('Finalized: ${_fmt(closeout.finalizedAt)}'),
            Text('Points generated: ${_fmt(closeout.pointsGeneratedAt)}'),
            Text('Reports generated: ${_fmt(closeout.reportsGeneratedAt)}'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onFinalize,
                    icon: finalizing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.task_alt),
                    label: Text(finalizing ? 'Finalizing…' : 'Finalize Show'),
                    style: FilledButton.styleFrom(
                      backgroundColor: statusColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: onProcessQueuedReports,
                  icon: const Icon(Icons.sync),
                  label: const Text('Process Queued Reports'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ValidationSummaryCard extends StatelessWidget {
  final List<ValidationIssue> issues;
  final Future<void> Function(ValidationIssue issue) onIssueTap;
  final VoidCallback? onViewAll;

  const _ValidationSummaryCard({
    required this.issues,
    required this.onIssueTap,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final blocking = issues.where((e) => e.level == 'blocking').toList();
    final errors = issues.where((e) => e.level == 'error').toList();
    final warnings = issues.where((e) => e.level == 'warning').toList();

    final previewIssues = issues.take(8).toList();
    final hasMore = issues.length > previewIssues.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Validation Issues',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _CountChip(
                  label: 'Blocking',
                  count: blocking.length,
                  color: Colors.red,
                ),
                _CountChip(
                  label: 'Errors',
                  count: errors.length,
                  color: Colors.deepOrange,
                ),
                _CountChip(
                  label: 'Warnings',
                  count: warnings.length,
                  color: Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (issues.isEmpty)
              const Text('No validation issues found.')
            else ...[
              ...previewIssues.map(
                (issue) => _IssueTile(
                  issue: issue,
                  onTap: () => onIssueTap(issue),
                  onFix: () => onIssueTap(issue),
                ),
              ),
              if (hasMore || onViewAll != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onViewAll,
                    icon: const Icon(Icons.list_alt),
                    label: Text(
                      hasMore
                          ? 'View all ${issues.length} issues'
                          : 'View all issues',
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _IssueTile extends StatelessWidget {
  final ValidationIssue issue;
  final VoidCallback onTap;
  final VoidCallback onFix;

  const _IssueTile({
    required this.issue,
    required this.onTap,
    required this.onFix,
  });

  IconData _iconForLevel(String level) {
    switch (level) {
      case 'blocking':
        return Icons.block;
      case 'error':
        return Icons.error_outline;
      default:
        return Icons.warning_amber_rounded;
    }
  }

  Color _colorForLevel(String level) {
    switch (level) {
      case 'blocking':
        return Colors.red;
      case 'error':
        return Colors.deepOrange;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorForLevel(issue.level);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_iconForLevel(issue.level), color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    issue.issueMessage,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _IssueLevelChip(level: issue.level),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(_friendlyReportName(issue.reportName)),
                      ),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(issue.issueCode),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: onFix,
              icon: const Icon(Icons.build_circle_outlined),
              label: const Text('Fix'),
            ),
          ],
        ),
      ),
    );
  }
}

class _IssueLevelChip extends StatelessWidget {
  final String level;

  const _IssueLevelChip({required this.level});

  Color _color() {
    switch (level) {
      case 'blocking':
        return Colors.red;
      case 'error':
        return Colors.deepOrange;
      default:
        return Colors.orange;
    }
  }

  String _label() {
    switch (level) {
      case 'blocking':
        return 'Blocking';
      case 'error':
        return 'Error';
      default:
        return 'Warning';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(_label()),
      backgroundColor: color.withOpacity(0.12),
      side: BorderSide(color: color.withOpacity(0.3)),
    );
  }
}

class _GeneratedReportsCard extends StatelessWidget {
  final List<ReportArtifactSummary> reports;

  const _GeneratedReportsCard({required this.reports});

  IconData _iconForStatus(String status) {
    switch (status) {
      case 'generated':
        return Icons.check_circle;
      case 'warning':
        return Icons.warning_amber_rounded;
      case 'failed':
        return Icons.error;
      default:
        return Icons.schedule;
    }
  }

  Color? _colorForStatus(String status) {
    switch (status) {
      case 'generated':
        return Colors.green;
      case 'warning':
        return Colors.orange;
      case 'failed':
        return Colors.red;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sortedReports = [...reports]
      ..sort((a, b) => _friendlyReportName(a.reportName)
          .compareTo(_friendlyReportName(b.reportName)));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Generated Reports',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (sortedReports.isEmpty)
              const Text('No reports found.')
            else
              ...sortedReports.map((report) {
                final hasFile = (report.storageBucket?.isNotEmpty == true) &&
                    (report.storagePath?.isNotEmpty == true);

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _iconForStatus(report.artifactStatus),
                    color: _colorForStatus(report.artifactStatus),
                  ),
                  title: Text(_friendlyReportName(report.reportName)),
                  subtitle: Text(report.artifactStatus),
                  trailing: hasFile
                      ? TextButton.icon(
                          onPressed: () async {
                            final url = supabase.storage
                                .from(report.storageBucket!)
                                .getPublicUrl(report.storagePath!);

                            await launchUrlString(
                              url,
                              mode: LaunchMode.externalApplication,
                            );
                          },
                          icon: const Icon(Icons.download),
                          label: const Text('Open'),
                        )
                      : Text(_fmt(report.generatedAt)),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _DistributionAndReportsCard extends StatelessWidget {
  final List<ReportArtifactSummary> exhibitorReports;
  final List<ReportArtifactSummary> clubReports;
  final List<ReportArtifactSummary> arbaReports;
  final List<ReportArtifactSummary> otherReports;
  final Future<void> Function() onSendExhibitor;
  final Future<void> Function() onSendClub;
  final Future<void> Function() onSendArba;
  final bool canSendExhibitor;
  final bool canSendClub;
  final bool canSendArba;

  const _DistributionAndReportsCard({
    required this.exhibitorReports,
    required this.clubReports,
    required this.arbaReports,
    required this.otherReports,
    required this.onSendExhibitor,
    required this.onSendClub,
    required this.onSendArba,
    required this.canSendExhibitor,
    required this.canSendClub,
    required this.canSendArba,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reports & Distribution',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              const TabBar(
                tabs: [
                  Tab(text: 'Distribution'),
                  Tab(text: 'Other Reports'),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 520,
                child: TabBarView(
                  children: [
                    ListView(
                      children: [
                        _ReportSectionTile(
                          title: 'Exhibitor Reports',
                          subtitle: 'Final exhibitor report and legs.',
                          reports: exhibitorReports,
                          buttonLabel: 'Send Exhibitor Reports',
                          onPressed: canSendExhibitor ? onSendExhibitor : null,
                        ),
                        _ReportSectionTile(
                          title: 'Club Reports',
                          subtitle: 'Breed/state club and points-related reports.',
                          reports: clubReports,
                          buttonLabel: 'Send Club Reports',
                          onPressed: canSendClub ? onSendClub : null,
                        ),
                        _ReportSectionTile(
                          title: 'ARBA Reports',
                          subtitle: 'Official ARBA report delivery.',
                          reports: arbaReports,
                          buttonLabel: 'Send ARBA Reports',
                          onPressed: canSendArba ? onSendArba : null,
                        ),
                      ],
                    ),
                    ListView(
                      children: [
                        _ReportSectionTile(
                          title: 'Other Generated Reports',
                          subtitle: 'Additional generated reports available for download.',
                          reports: otherReports,
                          buttonLabel: null,
                          onPressed: null,
                          initiallyExpanded: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportSectionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<ReportArtifactSummary> reports;
  final String? buttonLabel;
  final Future<void> Function()? onPressed;
  final bool initiallyExpanded;

  const _ReportSectionTile({
    required this.title,
    required this.subtitle,
    required this.reports,
    required this.buttonLabel,
    required this.onPressed,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 12),
      title: Text(title),
      subtitle: Text(subtitle),
      children: [
        if (reports.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('No reports in this section.'),
            ),
          )
        else
          ...reports.map((report) => _ReportRow(report: report)),
        if (buttonLabel != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.send),
              label: Text(buttonLabel!),
            ),
          ),
        ],
      ],
    );
  }
}

class _ReportRow extends StatelessWidget {
  final ReportArtifactSummary report;

  const _ReportRow({required this.report});

  IconData _iconForStatus(String status) {
    switch (status) {
      case 'generated':
        return Icons.check_circle;
      case 'warning':
        return Icons.warning_amber_rounded;
      case 'failed':
        return Icons.error;
      default:
        return Icons.schedule;
    }
  }

  Color? _colorForStatus(String status) {
    switch (status) {
      case 'generated':
        return Colors.green;
      case 'warning':
        return Colors.orange;
      case 'failed':
        return Colors.red;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasFile = (report.storageBucket?.isNotEmpty == true) &&
        (report.storagePath?.isNotEmpty == true);

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        _iconForStatus(report.artifactStatus),
        color: _colorForStatus(report.artifactStatus),
      ),
      title: Text(_friendlyReportName(report.reportName)),
      subtitle: Text(
        report.artifactStatus == 'generated'
            ? 'Generated ${_fmt(report.generatedAt)}'
            : report.artifactStatus,
      ),
      trailing: hasFile
          ? TextButton.icon(
              onPressed: () async {
                final url = supabase.storage
                    .from(report.storageBucket!)
                    .getPublicUrl(report.storagePath!);

                await launchUrlString(
                  url,
                  mode: LaunchMode.externalApplication,
                );
              },
              icon: const Icon(Icons.download),
              label: const Text('Download'),
            )
          : null,
    );
  }
}


class _StatTile extends StatelessWidget {
  final String label;
  final String value;

  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _CountChip({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $count'),
      backgroundColor: color.withOpacity(0.12),
      side: BorderSide(color: color.withOpacity(0.3)),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorView({required this.message, required this.onRetry});

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
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  } catch (_) {
    return value;
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
          .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
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

class ValidationIssue {
  final String id;
  final String level;
  final String issueCode;
  final String issueMessage;
  final String? reportName;
  final String? finalizeRunId;
  final Map<String, dynamic> issueDetails;
  final String? exhibitorId;
  final String? animalId;
  final String? classKey;

  ValidationIssue({
    required this.id,
    required this.level,
    required this.issueCode,
    required this.issueMessage,
    required this.reportName,
    required this.finalizeRunId,
    required this.issueDetails,
    required this.exhibitorId,
    required this.animalId,
    required this.classKey,
  });

  String? get entryId => issueDetails['entry_id']?.toString();
  String? get rawPlacement => issueDetails['raw_placement']?.toString();

  factory ValidationIssue.fromJson(Map<String, dynamic> json) {
    final rawDetails = json['issue_details'];
    final details = rawDetails is Map
        ? Map<String, dynamic>.from(rawDetails)
        : <String, dynamic>{};

    return ValidationIssue(
      id: (json['id'] ?? '') as String,
      level: (json['level'] ?? 'warning') as String,
      issueCode: (json['issue_code'] ?? '') as String,
      issueMessage: (json['issue_message'] ?? '') as String,
      reportName: json['report_name'] as String?,
      finalizeRunId: json['finalize_run_id'] as String?,
      issueDetails: details,
      exhibitorId: json['exhibitor_id']?.toString(),
      animalId: json['animal_id']?.toString(),
      classKey: json['class_key']?.toString(),
    );
  }
}