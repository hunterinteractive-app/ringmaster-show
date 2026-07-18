import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

class CloseoutFinalizeActionButton extends StatelessWidget {
  final bool reportsBlocked;
  final bool finalized;
  final bool reportsStale;
  final String tooltipScope;
  final VoidCallback? onPressed;

  const CloseoutFinalizeActionButton({
    super.key,
    required this.reportsBlocked,
    required this.finalized,
    required this.reportsStale,
    required this.tooltipScope,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: finalized
          ? 'Reports are finalized for $tooltipScope'
          : 'Finalize reports for $tooltipScope',
      child: FilledButton.icon(
        key: const ValueKey('closeout-finalize-button'),
        style: FilledButton.styleFrom(
          backgroundColor: reportsBlocked
              ? Colors.grey
              : reportsStale
              ? AppColors.gold
              : Colors.green,
          foregroundColor: AppColors.text,
          disabledForegroundColor: AppColors.text.withValues(alpha: .62),
          disabledBackgroundColor: finalized
              ? Colors.green.withValues(alpha: .32)
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
        onPressed: onPressed,
        icon: Icon(finalized ? Icons.check_circle_outline : Icons.auto_awesome),
        label: Text(
          reportsBlocked
              ? 'Finish Results Before Finalize'
              : finalized
              ? 'Scope Finalized'
              : 'Finalize Selected Scope',
        ),
      ),
    );
  }
}

class CloseoutGenerateRemainingButton extends StatelessWidget {
  final int count;
  final CloseoutGenerationProgress progress;
  final VoidCallback? onPressed;

  const CloseoutGenerateRemainingButton({
    super.key,
    required this.count,
    this.progress = const CloseoutGenerationProgress(),
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: const ValueKey('closeout-generate-remaining-button'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.secondaryButton,
        disabledForegroundColor: AppColors.muted.withValues(alpha: .72),
        side: BorderSide(
          color: AppColors.secondaryButton.withValues(alpha: .78),
          width: 1.4,
        ),
      ),
      onPressed: onPressed,
      icon: Icon(
        progress.isActive ? Icons.autorenew : Icons.play_circle_outline,
      ),
      label: Text(
        progress.isActive
            ? 'Generating Reports — ${progress.completed} of ${progress.total}'
            : 'Generate Remaining ($count)',
      ),
    );
  }
}

Duration? estimateCloseoutTimeRemaining({
  required int initialRemaining,
  required int remaining,
  required Duration elapsed,
}) {
  final processed = initialRemaining - remaining;
  if (initialRemaining <= 0 ||
      remaining <= 0 ||
      processed <= 0 ||
      elapsed < const Duration(seconds: 3)) {
    return null;
  }
  final estimatedMilliseconds = (elapsed.inMilliseconds * remaining / processed)
      .round();
  return Duration(milliseconds: estimatedMilliseconds);
}

class CloseoutGenerationProgress {
  final int queued;
  final int running;
  final int completed;
  final int failed;
  final int remaining;
  final int initialRemainingTotal;
  final int reportTotal;
  final int reportGenerated;
  final int reportFailed;
  final Duration? estimatedTimeRemaining;
  final DateTime? lastActivityAt;
  final DateTime? completedAt;
  final bool isStalled;

  const CloseoutGenerationProgress({
    this.queued = 0,
    this.running = 0,
    this.completed = 0,
    this.failed = 0,
    this.remaining = 0,
    this.initialRemainingTotal = 0,
    this.reportTotal = 0,
    this.reportGenerated = 0,
    this.reportFailed = 0,
    this.estimatedTimeRemaining,
    this.lastActivityAt,
    this.completedAt,
    this.isStalled = false,
  });

  int get total => queued + running + completed + failed;
  bool get hasPersistedReportCounts => reportTotal > 0;
  int get reportPending =>
      (reportTotal - reportGenerated - reportFailed).clamp(0, reportTotal);
  bool get isActive => queued > 0 || running > 0;
  bool get hasFailures => failed > 0;
  int get needsReview => failed > remaining ? failed : remaining;
  bool get isWaitingToStart =>
      queued > 0 && running == 0 && completed == 0 && failed == 0;
  bool get isWaitingToGenerate =>
      total == 0 &&
      (hasPersistedReportCounts ? reportPending > 0 : remaining > 0) &&
      completed == 0 &&
      failed == 0;
  bool get isComplete =>
      total > 0 && !isActive && !hasFailures && remaining == 0;
  double get percentComplete => total == 0 ? 0 : completed / total;
  int get inferredProcessed => total == 0 && initialRemainingTotal > remaining
      ? initialRemainingTotal - remaining
      : 0;
  double get displayedPercentComplete {
    if (hasPersistedReportCounts) return reportGenerated / reportTotal;
    if (total > 0) return !isActive ? 1 : percentComplete;
    if (initialRemainingTotal <= 0) return 0;
    return inferredProcessed / initialRemainingTotal;
  }

  int get displayedGenerated =>
      hasPersistedReportCounts ? reportGenerated : inferredProcessed;
  int get displayedRemaining =>
      hasPersistedReportCounts ? reportPending : remaining;
}

class CloseoutGenerationStatusBanner extends StatelessWidget {
  final CloseoutGenerationProgress progress;
  final VoidCallback? onRetryFailed;
  final VoidCallback? onViewReportsNeedingReview;

  const CloseoutGenerationStatusBanner({
    super.key,
    required this.progress,
    this.onRetryFailed,
    this.onViewReportsNeedingReview,
  });

  String _timestamp(BuildContext context, DateTime? value) {
    if (value == null) return 'Not available';
    final local = value.toLocal();
    final material = MaterialLocalizations.of(context);
    return '${material.formatShortDate(local)} at '
        '${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }

  String _estimatedTime(Duration value) {
    if (value < const Duration(minutes: 1)) return 'Less than a minute';
    final minutes = (value.inSeconds / 60).ceil();
    if (minutes < 60) return 'About $minutes minutes';
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    if (remainingMinutes == 0) {
      return 'About $hours hour${hours == 1 ? '' : 's'}';
    }
    return 'About $hours hr $remainingMinutes min';
  }

  @override
  Widget build(BuildContext context) {
    final isCompleteWithIssues =
        !progress.isActive && progress.total > 0 && progress.needsReview > 0;
    final isComplete =
        !progress.isActive && progress.total > 0 && progress.needsReview == 0;
    final title = switch ((
      progress.isStalled,
      progress.isWaitingToGenerate,
      progress.isWaitingToStart,
      isCompleteWithIssues,
      isComplete,
    )) {
      (true, _, _, _, _) => 'Report generation may be delayed',
      (_, true, _, _, _) =>
        '${progress.displayedRemaining} report${progress.displayedRemaining == 1 ? '' : 's'} waiting to be generated.',
      (_, _, true, _, _) => 'Reports are queued and waiting to begin.',
      (_, _, _, true, _) =>
        'Report generation is complete. ${progress.needsReview} report${progress.needsReview == 1 ? '' : 's'} need review.',
      (_, _, _, _, true) => 'Report generation is complete.',
      _ => 'Generating reports',
    };
    final bannerColor = progress.isStalled || isCompleteWithIssues
        ? Colors.orange
        : isComplete
        ? Colors.green
        : AppColors.secondaryButton;

    return Container(
      key: const ValueKey('closeout-generation-status-banner'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: bannerColor.withValues(alpha: .55), width: 2),
        boxShadow: [
          BoxShadow(
            color: bannerColor.withValues(alpha: .10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                progress.isStalled || isCompleteWithIssues
                    ? Icons.warning_amber_rounded
                    : isComplete
                    ? Icons.check_circle_outline
                    : progress.isWaitingToStart || progress.isWaitingToGenerate
                    ? Icons.schedule
                    : Icons.cloud_sync_outlined,
                color: bannerColor,
                size: 28,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          if (progress.total > 0 || progress.remaining > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Report generation progress',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '${(progress.displayedPercentComplete * 100).round()}%',
                  key: const ValueKey('closeout-generation-percent'),
                  style: TextStyle(
                    color: bannerColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              key: const ValueKey('closeout-generation-progress-bar'),
              value: progress.displayedPercentComplete
                  .clamp(0.0, 1.0)
                  .toDouble(),
              minHeight: 10,
              borderRadius: BorderRadius.circular(99),
              color: bannerColor,
            ),
            const SizedBox(height: 10),
            if (progress.total == 0)
              Text(
                '${progress.displayedGenerated} '
                '${progress.hasPersistedReportCounts ? 'generated' : 'processed'} • '
                '${progress.displayedRemaining} remaining',
                style: const TextStyle(fontWeight: FontWeight.w600),
              )
            else
              Text(
                '${progress.queued} queued • ${progress.running} running • '
                '${progress.completed} completed • ${progress.failed} failed',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            if (progress.isWaitingToGenerate) ...[
              const SizedBox(height: 6),
              Text(
                progress.estimatedTimeRemaining == null
                    ? 'Estimating time remaining…'
                    : 'Estimated time remaining: '
                          '${_estimatedTime(progress.estimatedTimeRemaining!)}',
                key: const ValueKey('closeout-generation-estimate'),
                style: const TextStyle(color: AppColors.muted),
              ),
            ],
          ],
          if (progress.isStalled) ...[
            const SizedBox(height: 10),
            Text(
              'No recent progress was detected. The reports remain queued; '
              'there is no need to queue them again.',
            ),
            const SizedBox(height: 4),
            Text(
              'Last activity: ${_timestamp(context, progress.lastActivityAt)}',
            ),
          ],
          if (isComplete) ...[
            const SizedBox(height: 10),
            Text('${progress.completed} reports generated.'),
            const SizedBox(height: 4),
            Text('Completed: ${_timestamp(context, progress.completedAt)}'),
          ],
          if (isCompleteWithIssues) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${progress.completed} generated • ${progress.failed} failed • '
                    '${progress.remaining} remaining',
                    style: const TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onRetryFailed != null) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('closeout-retry-failed-button'),
                    onPressed: onRetryFailed,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry Failed'),
                  ),
                ],
              ],
            ),
            if (onViewReportsNeedingReview != null) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const ValueKey('closeout-view-reports-needing-review'),
                onPressed: onViewReportsNeedingReview,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('View Reports Needing Review'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

enum CloseoutReviewGroup {
  retryableFailure,
  nonRetryableFailure,
  missing,
  active,
}

class CloseoutFailureDisplay {
  final String title;
  final String message;

  const CloseoutFailureDisplay({required this.title, required this.message});
}

CloseoutFailureDisplay closeoutFailureDisplay({
  required String errorCategory,
  String metadataLastError = '',
  String metadataErrorMessage = '',
  String taskErrorMessage = '',
  String taskLastError = '',
  String fallbackError = '',
  String missingField = '',
  String missingLabel = '',
  String exhibitorName = '',
  String sectionLabel = '',
}) {
  final details = <String>[
    metadataLastError,
    metadataErrorMessage,
    taskErrorMessage,
    taskLastError,
    fallbackError,
  ].map((value) => value.trim()).where((value) => value.isNotEmpty).toList();
  final searchable = details.join('\n');
  final normalizedMissingField = missingField.trim().toLowerCase();
  final isBestInShowAddress =
      normalizedMissingField == 'best_in_show_exhibitor_address' ||
      RegExp(
        r'best\s+in\s+show(?:\s+rabbit)?\s+(?:owner|exhibitor)\s+(?:city\s*/\s*state|address)',
        caseSensitive: false,
      ).hasMatch(searchable) ||
      RegExp(
        r'best\s+in\s+show\s+exhibitor\s+address',
        caseSensitive: false,
      ).hasMatch(searchable);

  if (isBestInShowAddress) {
    final label = missingLabel.trim().isNotEmpty
        ? missingLabel.trim()
        : 'Best In Show Exhibitor Address';
    final subject = exhibitorName.trim().isNotEmpty
        ? exhibitorName.trim()
        : 'The Best In Show exhibitor';
    return CloseoutFailureDisplay(
      title: 'Missing $label',
      message: exhibitorName.trim().isEmpty
          ? 'The Best In Show exhibitor is missing a city or state.'
          : '$subject is missing city or state. '
                'Update the exhibitor record, then regenerate this report.',
    );
  }

  final isMissingArbaSanction =
      errorCategory.trim().toLowerCase() == 'missing_sanction_number';
  if (isMissingArbaSanction) {
    final subject = sectionLabel.trim().isNotEmpty
        ? sectionLabel.trim()
        : 'The selected section';
    return CloseoutFailureDisplay(
      title: 'Missing ARBA Sanction Number',
      message:
          '$subject is missing its ARBA sanction number. Add the sanction '
          'number, then generate the ARBA report after exhibitor and club '
          'reports are sent.',
    );
  }

  final usefulDetails = details.where(
    (value) =>
        value.toLowerCase().replaceAll(RegExp(r'[.!]+$'), '') !=
        'the report could not be rendered',
  );
  final fallback = usefulDetails.isEmpty
      ? 'No additional error details are available.'
      : usefulDetails.first.replaceFirst(
          RegExp(r'^\s*exception\s*:\s*', caseSensitive: false),
          '',
        );
  final friendlyFallback = fallback.replaceAllMapped(
    RegExp(
      r'\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b',
      caseSensitive: false,
    ),
    (_) => sectionLabel.trim().isNotEmpty
        ? sectionLabel.trim()
        : 'the selected section',
  );
  return CloseoutFailureDisplay(
    title: 'The report could not be rendered',
    message: friendlyFallback.isEmpty
        ? 'No additional error details are available.'
        : friendlyFallback,
  );
}

class CloseoutReviewReport {
  final String artifactId;
  final String finalizeRunId;
  final String reportTitle;
  final String reportName;
  final String sectionId;
  final String sectionLabel;
  final String showLetter;
  final String scope;
  final String species;
  final String exhibitorName;
  final String breedName;
  final String clubName;
  final String sanctioningBody;
  final String artifactStatus;
  final String taskStatus;
  final String errorCategory;
  final String errorMessage;
  final String metadataLastError;
  final String metadataErrorMessage;
  final String taskErrorMessage;
  final String taskLastError;
  final String missingField;
  final String missingLabel;
  final String taskHistoryCategory;
  final String taskHistoryMessage;
  final bool retryable;
  final int attemptCount;
  final int maxAttempts;
  final DateTime? lastAttemptedAt;
  final CloseoutReviewGroup group;

  const CloseoutReviewReport({
    required this.artifactId,
    required this.finalizeRunId,
    required this.reportTitle,
    required this.reportName,
    this.sectionId = '',
    this.sectionLabel = '',
    this.showLetter = '',
    this.scope = '',
    this.species = '',
    this.exhibitorName = '',
    this.breedName = '',
    this.clubName = '',
    this.sanctioningBody = '',
    required this.artifactStatus,
    required this.taskStatus,
    this.errorCategory = '',
    this.errorMessage = '',
    this.metadataLastError = '',
    this.metadataErrorMessage = '',
    this.taskErrorMessage = '',
    this.taskLastError = '',
    this.missingField = '',
    this.missingLabel = '',
    this.taskHistoryCategory = '',
    this.taskHistoryMessage = '',
    required this.retryable,
    this.attemptCount = 0,
    this.maxAttempts = 0,
    this.lastAttemptedAt,
    required this.group,
  });

  factory CloseoutReviewReport.fromJson(Map<String, dynamic> json) {
    String text(String key) => (json[key] ?? '').toString().trim();
    final metadata = json['metadata'] is Map
        ? Map<String, dynamic>.from(json['metadata'] as Map)
        : const <String, dynamic>{};
    String metadataText(String key) => (metadata[key] ?? '').toString().trim();
    final group = switch (text('review_group')) {
      'retryable_failure' => CloseoutReviewGroup.retryableFailure,
      'non_retryable_failure' => CloseoutReviewGroup.nonRetryableFailure,
      'active' => CloseoutReviewGroup.active,
      _ => CloseoutReviewGroup.missing,
    };
    final reportName = text('report_name');
    final report = CloseoutReviewReport(
      artifactId: text('artifact_id'),
      finalizeRunId: text('finalize_run_id'),
      reportTitle: reportName,
      reportName: reportName,
      sectionId: text('section_id'),
      sectionLabel: metadataText('section_label').isNotEmpty
          ? metadataText('section_label')
          : text('section_label'),
      showLetter: text('show_letter'),
      scope: metadataText('scope').isNotEmpty
          ? metadataText('scope')
          : text('scope'),
      species: text('species'),
      exhibitorName: metadataText('exhibitor_name').isNotEmpty
          ? metadataText('exhibitor_name')
          : text('exhibitor_name'),
      breedName: text('breed_name'),
      clubName: text('club_name'),
      sanctioningBody: text('sanctioning_body'),
      artifactStatus: text('artifact_status'),
      taskStatus: text('task_status'),
      errorCategory: metadataText('error_category').isNotEmpty
          ? metadataText('error_category')
          : text('metadata_error_category').isNotEmpty
          ? text('metadata_error_category')
          : text('error_category'),
      errorMessage: text('error_message'),
      metadataLastError: metadataText('last_error').isNotEmpty
          ? metadataText('last_error')
          : text('metadata_last_error'),
      metadataErrorMessage: metadataText('error_message').isNotEmpty
          ? metadataText('error_message')
          : text('metadata_error_message'),
      taskErrorMessage: text('task_error_message').isNotEmpty
          ? text('task_error_message')
          : text('task_history_message'),
      taskLastError: text('task_last_error'),
      missingField: metadataText('missing_field').isNotEmpty
          ? metadataText('missing_field')
          : text('missing_field'),
      missingLabel: metadataText('missing_label').isNotEmpty
          ? metadataText('missing_label')
          : text('missing_label'),
      taskHistoryCategory: text('task_history_category'),
      taskHistoryMessage: text('task_history_message'),
      retryable: json['retryable'] == true,
      attemptCount: ((json['attempt_count'] ?? 0) as num).toInt(),
      maxAttempts: ((json['max_attempts'] ?? 0) as num).toInt(),
      lastAttemptedAt: DateTime.tryParse(text('last_attempted_at')),
      group: group,
    );
    if (kDebugMode) {
      debugPrint(
        'CloseoutReviewReport failure sources '
        'artifactId=${report.artifactId} '
        'metadataLastError=${report.metadataLastError} '
        'metadataErrorMessage=${report.metadataErrorMessage} '
        'taskErrorMessage=${report.taskErrorMessage} '
        'taskLastError=${report.taskLastError} '
        'errorMessage=${report.errorMessage}',
      );
    }
    return report;
  }

  CloseoutReviewReport withPresentation({
    required String reportTitle,
    required String sectionLabel,
  }) {
    return CloseoutReviewReport(
      artifactId: artifactId,
      finalizeRunId: finalizeRunId,
      reportTitle: reportTitle,
      reportName: reportName,
      sectionId: sectionId,
      sectionLabel: sectionLabel,
      showLetter: showLetter,
      scope: scope,
      species: species,
      exhibitorName: exhibitorName,
      breedName: breedName,
      clubName: clubName,
      sanctioningBody: sanctioningBody,
      artifactStatus: artifactStatus,
      taskStatus: taskStatus,
      errorCategory: errorCategory,
      errorMessage: errorMessage,
      metadataLastError: metadataLastError,
      metadataErrorMessage: metadataErrorMessage,
      taskErrorMessage: taskErrorMessage,
      taskLastError: taskLastError,
      missingField: missingField,
      missingLabel: missingLabel,
      taskHistoryCategory: taskHistoryCategory,
      taskHistoryMessage: taskHistoryMessage,
      retryable: retryable,
      attemptCount: attemptCount,
      maxAttempts: maxAttempts,
      lastAttemptedAt: lastAttemptedAt,
      group: group,
    );
  }
}

List<String> blockingArbaReviewSectionLabels({
  required List<CloseoutReviewReport> reports,
  required String finalizeRunId,
}) {
  final runId = finalizeRunId.trim();
  if (runId.isEmpty) return const <String>[];

  final labels =
      reports
          .where(
            (report) =>
                report.finalizeRunId == runId &&
                report.reportName == 'arba_report',
          )
          .map((report) {
            final sectionLabel = report.sectionLabel.trim();
            if (sectionLabel.isNotEmpty) return sectionLabel;
            final showLetter = report.showLetter.trim();
            return showLetter.isEmpty ? 'an ARBA section' : 'Show $showLetter';
          })
          .toSet()
          .toList()
        ..sort(
          (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
        );
  return labels;
}

String arbaEmailBlockedMessage(List<String> sectionLabels) {
  final labels = sectionLabels
      .where((label) => label.trim().isNotEmpty)
      .toList();
  if (labels.isEmpty) {
    return 'Fix all ARBA reports under Reports Needing Review before emailing ARBA.';
  }
  return 'Fix the ARBA report${labels.length == 1 ? '' : 's'} for '
      '${labels.join(', ')} under Reports Needing Review before emailing ARBA.';
}

class CloseoutReportsNeedingReviewPanel extends StatelessWidget {
  final List<CloseoutReviewReport> reports;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;

  const CloseoutReportsNeedingReviewPanel({
    super.key,
    required this.reports,
    required this.initiallyExpanded,
    this.onExpansionChanged,
  });

  String _timestamp(BuildContext context, DateTime? value) {
    if (value == null) return 'Not available';
    final local = value.toLocal();
    final material = MaterialLocalizations.of(context);
    return '${material.formatShortDate(local)} at '
        '${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }

  CloseoutFailureDisplay _failureFor(CloseoutReviewReport report) {
    final fallback = report.errorMessage.isNotEmpty
        ? report.errorMessage
        : switch (report.group) {
            CloseoutReviewGroup.missing =>
              'No render task is available for this report.',
            CloseoutReviewGroup.active =>
              'This report is still waiting for generation to finish.',
            _ => '',
          };
    return closeoutFailureDisplay(
      errorCategory: report.errorCategory,
      metadataLastError: report.metadataLastError,
      metadataErrorMessage: report.metadataErrorMessage,
      taskErrorMessage: report.taskErrorMessage,
      taskLastError: report.taskLastError,
      fallbackError: fallback,
      missingField: report.missingField,
      missingLabel: report.missingLabel,
      exhibitorName: report.exhibitorName,
      sectionLabel: report.sectionLabel,
    );
  }

  Widget _detail(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Text('$label: $value');
  }

  Widget _reportRow(BuildContext context, CloseoutReviewReport report) {
    final failure = _failureFor(report);
    final normalizedTitle = failure.title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
    final normalizedMessage = failure.message
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
    final showFailureMessage =
        normalizedMessage.isNotEmpty && normalizedMessage != normalizedTitle;
    final identity = <String>[
      if (report.sectionLabel.isNotEmpty) report.sectionLabel,
      if (report.showLetter.isNotEmpty) 'Show ${report.showLetter}',
      if (report.scope.isNotEmpty) report.scope,
      if (report.species.isNotEmpty) report.species,
    ].join(' • ');
    return Container(
      key: ValueKey('closeout-review-report-${report.artifactId}'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.muted.withValues(alpha: .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            report.reportTitle,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 2),
          Text(report.reportName, style: const TextStyle(fontSize: 12)),
          if (identity.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(identity, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
          _detail('Exhibitor', report.exhibitorName),
          _detail('Breed', report.breedName),
          _detail('Club', report.clubName),
          _detail('Sanctioning body', report.sanctioningBody),
          const SizedBox(height: 6),
          Text(
            'Artifact: ${report.artifactStatus} • Task: ${report.taskStatus} • '
            'Retryable: ${report.retryable ? 'Yes' : 'No'}',
          ),
          if (report.errorCategory.isNotEmpty)
            Text('Error category: ${report.errorCategory}'),
          const SizedBox(height: 4),
          Text(
            failure.title,
            style: const TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.w700,
              fontSize: 16,
              height: 1.3,
            ),
          ),
          if (showFailureMessage) ...[
            const SizedBox(height: 4),
            Text(
              failure.message,
              style: const TextStyle(
                color: Colors.orange,
                fontSize: 15,
                height: 1.35,
              ),
            ),
          ],
          if (report.taskHistoryCategory.isNotEmpty &&
              report.taskHistoryCategory != report.errorCategory) ...[
            const SizedBox(height: 4),
            Text(
              'Latest task category: ${report.taskHistoryCategory}',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Attempts: ${report.attemptCount}${report.maxAttempts > 0 ? ' of ${report.maxAttempts}' : ''} • '
            'Last attempted: ${_timestamp(context, report.lastAttemptedAt)}',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const groups = <(CloseoutReviewGroup, String)>[
      (CloseoutReviewGroup.retryableFailure, 'Retryable failures'),
      (CloseoutReviewGroup.nonRetryableFailure, 'Non-retryable failures'),
      (CloseoutReviewGroup.missing, 'Missing reports'),
      (CloseoutReviewGroup.active, 'Queued or running'),
    ];
    return Container(
      key: const ValueKey('closeout-reports-needing-review-panel'),
      margin: const EdgeInsets.only(top: 12, bottom: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withValues(alpha: .35)),
      ),
      child: ExpansionTile(
        key: ValueKey('closeout-review-panel-$initiallyExpanded'),
        initiallyExpanded: initiallyExpanded,
        onExpansionChanged: onExpansionChanged,
        leading: const Icon(Icons.fact_check_outlined, color: Colors.orange),
        title: const Text(
          'Reports Needing Review',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${reports.length} report${reports.length == 1 ? '' : 's'}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          for (final entry in groups)
            if (reports.any((report) => report.group == entry.$1)) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 8),
                  child: Text(
                    entry.$2,
                    key: ValueKey('closeout-review-group-${entry.$1.name}'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              for (final report in reports.where(
                (report) => report.group == entry.$1,
              ))
                _reportRow(context, report),
            ],
        ],
      ),
    );
  }
}

class CloseoutResponsiveActionArea extends StatelessWidget {
  final List<Widget> primaryActions;
  final List<Widget> distributionActions;

  const CloseoutResponsiveActionArea({
    super.key,
    required this.primaryActions,
    required this.distributionActions,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 600;

        Widget group(String key, List<Widget> actions) {
          if (narrow) {
            return Column(
              key: ValueKey(key),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < actions.length; index++) ...[
                  SizedBox(width: double.infinity, child: actions[index]),
                  if (index != actions.length - 1) const SizedBox(height: 8),
                ],
              ],
            );
          }

          return Wrap(
            key: ValueKey(key),
            spacing: 10,
            runSpacing: 10,
            children: actions,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            group('closeout-primary-actions', primaryActions),
            if (distributionActions.isNotEmpty) ...[
              const SizedBox(height: 12),
              group('closeout-distribution-actions', distributionActions),
            ],
          ],
        );
      },
    );
  }
}

class CloseoutSectionSelectionRow extends StatelessWidget {
  final bool selected;
  final String title;
  final String subtitle;
  final ValueChanged<bool> onChanged;

  const CloseoutSectionSelectionRow({
    super.key,
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        button: true,
        toggled: selected,
        label: '$title. $subtitle',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onChanged(!selected),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: selected,
                    onChanged: (value) => onChanged(value == true),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CloseoutScopeSummaryText extends StatelessWidget {
  final String primaryLabel;
  final String detailLabel;

  const CloseoutScopeSummaryText({
    super.key,
    required this.primaryLabel,
    required this.detailLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          primaryLabel,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(detailLabel),
      ],
    );
  }
}
