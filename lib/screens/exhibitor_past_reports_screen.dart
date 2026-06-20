// lib/screens/exhibitor_past_reports_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_session.dart';
import '../theme/app_theme.dart';
import '../utils/date_time_utils.dart';
import '../widgets/rm_widgets.dart';

final supabase = Supabase.instance.client;

class ExhibitorPastReportsScreen extends StatefulWidget {
  const ExhibitorPastReportsScreen({super.key});

  @override
  State<ExhibitorPastReportsScreen> createState() =>
      _ExhibitorPastReportsScreenState();
}

class _ExhibitorPastReportsScreenState
    extends State<ExhibitorPastReportsScreen> {
  late Future<List<_PastShowReport>> _future;
  final Set<String> _downloadingArtifactIds = <String>{};
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';

  String? get _supportTargetUserId {
    final userId = AppSession.impersonatedUserId;
    if (!AppSession.isSupportMode || userId == null || userId.isEmpty) {
      return null;
    }
    return userId;
  }

  bool get _isViewingAs => _supportTargetUserId != null;

  String get _introText {
    return _isViewingAs
        ? 'Viewing exhibitor reports and ARBA legs. Reports will be available for up to 1 year after they are generated.'
        : 'Download exhibitor reports and ARBA legs from your past shows. Reports will be available for up to 1 year after they are generated.';
  }

  @override
  void initState() {
    super.initState();
    _future = _loadReports();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<_PastShowReport>> _loadReports() async {
    final targetUserId = _supportTargetUserId;

    final rows = targetUserId == null
        ? await supabase.rpc('exhibitor_past_show_reports')
        : await supabase.rpc(
            'support_exhibitor_past_show_reports',
            params: {'p_target_user_id': targetUserId},
          );

    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(_PastShowReport.fromMap)
        .toList();
  }

  Future<void> _refresh() async {
    final future = _loadReports();

    setState(() {
      _future = future;
    });

    await future;
  }

  Future<void> _downloadReport(_PastShowReport report) async {
    if (_downloadingArtifactIds.contains(report.artifactId)) return;

    setState(() {
      _downloadingArtifactIds.add(report.artifactId);
    });

    try {
      final targetUserId = _supportTargetUserId;
      final rows = targetUserId == null
          ? await supabase.rpc(
              'exhibitor_report_download_info',
              params: {'p_artifact_id': report.artifactId},
            )
          : await supabase.rpc(
              'support_exhibitor_report_download_info',
              params: {
                'p_artifact_id': report.artifactId,
                'p_target_user_id': targetUserId,
              },
            );

      final list = (rows as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) {
        throw Exception('Report is not available for download.');
      }

      final row = list.first;
      final bucket = (row['storage_bucket'] ?? '').toString();
      final path = (row['storage_path'] ?? '').toString();

      if (bucket.isEmpty || path.isEmpty) {
        throw Exception('Report storage path is missing.');
      }

      final signedUrl = await supabase.storage
          .from(bucket)
          .createSignedUrl(path, 300);

      final uri = Uri.parse(signedUrl);
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);

      if (!opened) {
        throw Exception('Could not open the report download.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to download report: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloadingArtifactIds.remove(report.artifactId);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Past Show Reports'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<List<_PastShowReport>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snap.hasError) {
            return _ErrorState(
              message: snap.error.toString(),
              onRetry: _refresh,
            );
          }

          final reports = snap.data ?? const <_PastShowReport>[];
          final filteredReports = _filterReports(reports);
          final grouped = _groupReportsByShow(filteredReports);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                if (_isViewingAs) ...[
                  const _SupportModeNotice(),
                  const SizedBox(height: AppSpacing.md),
                ],
                Text(
                  _introText,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: AppSpacing.md),
                _ReportsSearchField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() {
                      _searchText = value.trim();
                    });
                  },
                  onClear: () {
                    _searchController.clear();
                    setState(() {
                      _searchText = '';
                    });
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                if (reports.isEmpty)
                  _EmptyState(isViewingAs: _isViewingAs)
                else if (filteredReports.isEmpty)
                  _NoSearchResultsState(searchText: _searchText)
                else
                  for (final showReports in grouped)
                    _PastShowReportCard(
                      reports: showReports,
                      downloadingArtifactIds: _downloadingArtifactIds,
                      onDownload: _downloadReport,
                    ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<List<_PastShowReport>> _groupReportsByShow(
    List<_PastShowReport> reports,
  ) {
    final map = <String, List<_PastShowReport>>{};

    for (final report in reports) {
      map.putIfAbsent(report.showId, () => <_PastShowReport>[]).add(report);
    }

    final groups = map.values.toList();

    groups.sort((a, b) {
      final aDate = a.first.showStartDate;
      final bDate = b.first.showStartDate;

      if (aDate != null && bDate != null) {
        return bDate.compareTo(aDate);
      }

      if (aDate != null) return -1;
      if (bDate != null) return 1;

      return a.first.showName.compareTo(b.first.showName);
    });

    for (final group in groups) {
      group.sort((a, b) {
        final aRank = a.reportName == 'exhibitor_report' ? 0 : 1;
        final bRank = b.reportName == 'exhibitor_report' ? 0 : 1;

        if (aRank != bRank) return aRank.compareTo(bRank);

        return a.reportLabel.compareTo(b.reportLabel);
      });
    }

    return groups;
  }

  List<_PastShowReport> _filterReports(List<_PastShowReport> reports) {
    final query = _searchText.toLowerCase();
    if (query.isEmpty) return reports;

    return reports.where((report) {
      final haystack = [
        report.showName,
        report.showLocation,
        report.reportLabel,
        report.reportName,
        report.exhibitorName,
        report.fileName,
      ].join(' ').toLowerCase();

      return haystack.contains(query);
    }).toList();
  }
}

class _ReportsSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _ReportsSearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        suffixIcon: controller.text.trim().isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close),
                onPressed: onClear,
              ),
        labelText: 'Search past show reports',
        hintText: 'Search by show, exhibitor, report, location, or file name',
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _SupportModeNotice extends StatelessWidget {
  const _SupportModeNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.55)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.visibility_outlined),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'View As mode is active. Reports are being loaded for the selected user.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _PastShowReportCard extends StatelessWidget {
  final List<_PastShowReport> reports;
  final Set<String> downloadingArtifactIds;
  final Future<void> Function(_PastShowReport report) onDownload;

  const _PastShowReportCard({
    required this.reports,
    required this.downloadingArtifactIds,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final first = reports.first;
    final dateText = _showDateText(first);
    final exhibitorCount = reports.map((r) => r.exhibitorId).toSet().length;
    final reportCount = reports.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: RMCard(
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: false,
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: AppSpacing.sm),
            leading: const Icon(Icons.event_note_outlined),
            title: Text(
              first.showName,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (dateText.isNotEmpty) Text(dateText),
                if (first.showLocation.isNotEmpty) Text(first.showLocation),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '$reportCount report${reportCount == 1 ? '' : 's'} • $exhibitorCount exhibitor${exhibitorCount == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            children: [
              for (final report in reports)
                _ReportRow(
                  report: report,
                  downloading: downloadingArtifactIds.contains(
                    report.artifactId,
                  ),
                  onDownload: onDownload,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _showDateText(_PastShowReport report) {
    final start = formatLocalDateTime(report.showStartDate?.toIso8601String());
    final end = formatLocalDateTime(report.showEndDate?.toIso8601String());

    if (start.isEmpty && end.isEmpty) return '';
    if (end.isEmpty || start == end) return start;

    return '$start - $end';
  }
}

class _ReportRow extends StatelessWidget {
  final _PastShowReport report;
  final bool downloading;
  final Future<void> Function(_PastShowReport report) onDownload;

  const _ReportRow({
    required this.report,
    required this.downloading,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final isLegs = report.reportName == 'legs';
    final subtitle = <String>[
      if (report.exhibitorName.isNotEmpty) report.exhibitorName,
      if (report.generatedAt != null)
        'Generated ${_formatDate(report.generatedAt)}',
    ].join(' • ');

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        leading: Icon(
          isLegs
              ? Icons.workspace_premium_outlined
              : Icons.description_outlined,
        ),
        title: Text(
          report.reportLabel,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: subtitle.isEmpty ? null : Text(subtitle),
        trailing: downloading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                tooltip: 'Download',
                icon: const Icon(Icons.download),
                onPressed: () => onDownload(report),
              ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return formatLocalDateTime(date.toIso8601String());
  }
}

class _EmptyState extends StatelessWidget {
  final bool isViewingAs;

  const _EmptyState({required this.isViewingAs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Center(
        child: RMCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.folder_copy_outlined,
                size: 44,
                color: AppColors.muted,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                isViewingAs
                    ? 'No reports for this View As user'
                    : 'No past show reports yet',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                isViewingAs
                    ? 'This means the selected user does not currently match any finalized exhibitor reports or ARBA legs through entries, owner profile, or claimed profile.'
                    : 'Finalized exhibitor reports and ARBA legs will appear here after a show secretary generates closeout reports. Reports will be available for up to 1 year after they are generated.',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: RMCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 44,
                color: AppColors.danger,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Unable to load reports',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PastShowReport {
  final String artifactId;
  final String showId;
  final String showName;
  final DateTime? showStartDate;
  final DateTime? showEndDate;
  final String showLocation;
  final String reportName;
  final String reportLabel;
  final String exhibitorId;
  final String exhibitorName;
  final String fileName;
  final String storageBucket;
  final String storagePath;
  final DateTime? generatedAt;
  final int? legsCount;

  const _PastShowReport({
    required this.artifactId,
    required this.showId,
    required this.showName,
    required this.showStartDate,
    required this.showEndDate,
    required this.showLocation,
    required this.reportName,
    required this.reportLabel,
    required this.exhibitorId,
    required this.exhibitorName,
    required this.fileName,
    required this.storageBucket,
    required this.storagePath,
    required this.generatedAt,
    required this.legsCount,
  });

  factory _PastShowReport.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      return DateTime.tryParse(value.toString());
    }

    int? parseInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      return int.tryParse(value.toString());
    }

    return _PastShowReport(
      artifactId: map['artifact_id']?.toString() ?? '',
      showId: map['show_id']?.toString() ?? '',
      showName: map['show_name']?.toString() ?? 'Show',
      showStartDate: parseDate(map['show_start_date']),
      showEndDate: parseDate(map['show_end_date']),
      showLocation: map['show_location']?.toString() ?? '',
      reportName: map['report_name']?.toString() ?? '',
      reportLabel: map['report_label']?.toString() ?? 'Report',
      exhibitorId: map['exhibitor_id']?.toString() ?? '',
      exhibitorName: map['exhibitor_name']?.toString() ?? '',
      fileName: map['file_name']?.toString() ?? '',
      storageBucket: map['storage_bucket']?.toString() ?? '',
      storagePath: map['storage_path']?.toString() ?? '',
      generatedAt: parseDate(map['generated_at']),
      legsCount: parseInt(map['legs_count']),
    );
  }
}

class _NoSearchResultsState extends StatelessWidget {
  final String searchText;

  const _NoSearchResultsState({required this.searchText});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Center(
        child: RMCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_outlined, size: 44, color: AppColors.muted),
              const SizedBox(height: AppSpacing.md),
              Text(
                'No matching reports',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'No reports matched “$searchText”. Try searching by show name, exhibitor name, report type, location, or file name.',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
