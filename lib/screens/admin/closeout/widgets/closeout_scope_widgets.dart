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

class CloseoutGenerationProgress {
  final int queued;
  final int running;
  final int completed;
  final int failed;

  const CloseoutGenerationProgress({
    this.queued = 0,
    this.running = 0,
    this.completed = 0,
    this.failed = 0,
  });

  int get total => queued + running + completed + failed;
  bool get isActive => queued > 0 || running > 0;
  bool get hasFailures => failed > 0;
  bool get isComplete => total > 0 && !isActive && !hasFailures;
  double get percentComplete => total == 0 ? 0 : completed / total;
}

class CloseoutGenerationProgressCard extends StatelessWidget {
  final CloseoutGenerationProgress progress;
  final VoidCallback? onRetryFailed;

  const CloseoutGenerationProgressCard({
    super.key,
    required this.progress,
    this.onRetryFailed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('closeout-generation-progress-card'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: progress.hasFailures
              ? Colors.orange.withValues(alpha: .45)
              : AppColors.secondaryButton.withValues(alpha: .25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                progress.hasFailures
                    ? Icons.warning_amber_rounded
                    : Icons.cloud_sync_outlined,
                color: progress.hasFailures
                    ? Colors.orange
                    : AppColors.secondaryButton,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Generating reports',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${progress.completed} of ${progress.total} completed',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress.percentComplete.clamp(0.0, 1.0).toDouble(),
            minHeight: 7,
            borderRadius: BorderRadius.circular(99),
          ),
          const SizedBox(height: 8),
          Text(
            '${progress.queued} waiting • ${progress.running} rendering • ${progress.failed} failed',
          ),
          if (progress.hasFailures) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${progress.failed} report${progress.failed == 1 ? '' : 's'} failed to generate.',
                    style: const TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  key: const ValueKey('closeout-retry-failed-button'),
                  onPressed: onRetryFailed,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry Failed'),
                ),
              ],
            ),
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
