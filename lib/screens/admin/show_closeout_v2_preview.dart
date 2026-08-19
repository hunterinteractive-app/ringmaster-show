import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/arba_report_presentation.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/report_artifact_summary.dart';
import 'package:ringmaster_show/screens/admin/closeout/results_entry_fix_launcher.dart';
import 'package:ringmaster_show/screens/admin/show_checkin_roster_screen.dart';
import 'package:ringmaster_show/services/locked_show_data_export.dart';
import 'package:ringmaster_show/services/report_email_service.dart';
import 'package:ringmaster_show/utils/file_download.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _activeDeliveryProgress = ValueNotifier<_ActiveDeliveryProgress?>(null);

class _ActiveDeliveryProgress {
  final String recipientType;
  final int totalBatches;
  final int completedBatches;

  const _ActiveDeliveryProgress({
    required this.recipientType,
    required this.totalBatches,
    required this.completedBatches,
  });

  double get progress =>
      totalBatches == 0 ? 0 : completedBatches / totalBatches;
}

/// The current closeout workflow.
///
/// Report generation, delivery, and ARBA-closeout edits are being promoted
/// incrementally; ARBA submission and final locking remain protected.
class ShowCloseoutV2PreviewPage extends StatefulWidget {
  final String showId;
  final String showName;
  final bool canFinalizeShow;

  const ShowCloseoutV2PreviewPage({
    super.key,
    required this.showId,
    required this.showName,
    required this.canFinalizeShow,
  });

  @override
  State<ShowCloseoutV2PreviewPage> createState() =>
      _ShowCloseoutV2PreviewPageState();
}

class _ShowCloseoutV2PreviewPageState extends State<ShowCloseoutV2PreviewPage> {
  static const _steps = <String>[
    'Show ARBA Details',
    'Needs Fixed',
    'Review Warnings',
    'Financial and Payout Review',
    'Generate Reports',
    'Send Results',
    'Report Delivery Status',
    'Submit ARBA Report and Lock Show',
  ];

  int _selectedStep = 0;
  _CloseoutCubeStatus _cubeStatus = const _CloseoutCubeStatus();

  @override
  void initState() {
    super.initState();
    _refreshCubeStatus();
  }

  Future<void> _refreshCubeStatus() async {
    try {
      final client = Supabase.instance.client;
      final values = await Future.wait<dynamic>([
        client
            .from('shows')
            .select(
              'secretary_name,secretary_address,secretary_email,secretary_phone',
            )
            .eq('id', widget.showId)
            .maybeSingle(),
        client
            .from('show_arba_report_details')
            .select(
              'superintendent_name,superintendent_arba_number,sweepstakes_issue,sweepstakes_club,official_protest,arba_report_filed',
            )
            .eq('show_id', widget.showId)
            .maybeSingle(),
        client
            .from('show_sections')
            .select('id')
            .eq('show_id', widget.showId)
            .eq('is_enabled', true),
        client
            .from('show_sanctions')
            .select(
              'section_id,sanctioning_body,breed_name,sanction_number,request_status,use_arba_number',
            )
            .eq('show_id', widget.showId),
        client.rpc(
          'report_results_entry_rows',
          params: {
            'p_show_id': widget.showId,
            'p_section_id': null,
            'p_show_letter': null,
          },
        ),
        client
            .from('show_report_artifacts')
            .select('report_name,artifact_status,metadata')
            .eq('show_id', widget.showId)
            .eq('is_current', true),
        client
            .from('show_closeout_state')
            .select('exhibitor_emails_sent_at,club_reports_sent_at')
            .eq('show_id', widget.showId)
            .maybeSingle(),
        client
            .from('show_email_deliveries')
            .select('id')
            .eq('show_id', widget.showId)
            .inFilter('delivery_status', const [
              'failed',
              'bounced',
              'complained',
              'suppressed',
            ])
            .limit(1),
      ]);
      if (!mounted) return;

      final show = Map<String, dynamic>.from(values[0] as Map? ?? const {});
      final arba = Map<String, dynamic>.from(values[1] as Map? ?? const {});
      final sections = (values[2] as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      final sanctions = (values[3] as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      final placementRows = (values[4] as List).map(
        (row) => Map<String, dynamic>.from(row as Map),
      );
      final artifacts = (values[5] as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      final closeout = Map<String, dynamic>.from(values[6] as Map? ?? const {});
      final deliveriesNeedingResend = (values[7] as List).isNotEmpty;
      String text(Map<String, dynamic> row, String key) =>
          row[key]?.toString().trim() ?? '';

      final arbaDetailsIncomplete =
          [
            text(show, 'secretary_name'),
            text(show, 'secretary_address'),
            text(show, 'secretary_email'),
            text(show, 'secretary_phone'),
            text(arba, 'superintendent_name'),
            text(arba, 'superintendent_arba_number'),
          ].any((value) => value.isEmpty) ||
          (arba['sweepstakes_issue'] == true &&
              text(arba, 'sweepstakes_club').isEmpty) ||
          (arba['official_protest'] == true &&
              arba['arba_report_filed'] != true);

      final hasPlacementIssue = placementRows.any((row) {
        final status =
            '${row['result_status'] ?? row['status'] ?? ''} ${row['disqualified_reason'] ?? ''}'
                .toLowerCase();
        final eligible =
            (row['scratched_at'] ?? '').toString().trim().isEmpty &&
            row['is_shown'] != false &&
            row['is_disqualified'] != true &&
            !const [
              'no show',
              'scratch',
              'disqual',
              'wrong sex',
              'wrong variety',
              'wrong class',
              'overweight',
              'unworthy',
            ].any(status.contains);
        return eligible && (row['placement'] ?? '').toString().trim().isEmpty;
      });

      final hasWarning =
          sections.any((section) {
            final sectionId = text(section, 'id');
            return !sanctions.any(
              (sanction) =>
                  text(sanction, 'section_id') == sectionId &&
                  text(sanction, 'sanctioning_body').toLowerCase() == 'arba' &&
                  text(sanction, 'sanction_number').isNotEmpty,
            );
          }) ||
          sanctions.any((sanction) {
            final body = text(sanction, 'sanctioning_body').toLowerCase();
            final breed = text(sanction, 'breed_name');
            final number = text(sanction, 'sanction_number');
            final status = text(sanction, 'request_status').toLowerCase();
            return body != 'arba' &&
                breed.isNotEmpty &&
                number.isEmpty &&
                sanction['use_arba_number'] != true &&
                (status.contains('requested') ||
                    status.contains('waiting') ||
                    number.isEmpty);
          });

      final nonArbaArtifacts = artifacts
          .where((artifact) => text(artifact, 'report_name') != 'arba_report')
          .toList();
      final reportsGenerated =
          nonArbaArtifacts.isNotEmpty &&
          nonArbaArtifacts.every(
            (artifact) => text(artifact, 'artifact_status') == 'generated',
          );
      final reportsWaitingToSend = nonArbaArtifacts.any((artifact) {
        if (text(artifact, 'artifact_status') != 'generated') return false;
        final metadata = Map<String, dynamic>.from(
          artifact['metadata'] as Map? ?? const {},
        );
        final hasClubRecipient = (metadata['sweepstakes_email'] ?? '')
            .toString()
            .trim()
            .isNotEmpty;
        final isExhibitorReport =
            text(artifact, 'report_name') == 'exhibitor_report' ||
            text(artifact, 'report_name') == 'legs';
        final hasExhibitorRecipient = (metadata['exhibitor_email'] ?? '')
            .toString()
            .trim()
            .isNotEmpty;
        return hasClubRecipient || (isExhibitorReport && hasExhibitorRecipient);
      });
      final reportsSent =
          DateTime.tryParse(text(closeout, 'exhibitor_emails_sent_at')) !=
              null &&
          DateTime.tryParse(text(closeout, 'club_reports_sent_at')) != null;

      setState(() {
        _cubeStatus = _CloseoutCubeStatus(
          arbaDetailsIncomplete: arbaDetailsIncomplete,
          placementIssues: hasPlacementIssue,
          warnings: hasWarning,
          reportsReadyToSend:
              reportsGenerated && reportsWaitingToSend && !reportsSent,
          deliveriesNeedingResend: deliveriesNeedingResend,
        );
      });
    } catch (_) {
      // Keep the neutral cube colors if the status check is temporarily unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.canFinalizeShow) {
      return const Scaffold(
        body: Center(
          child: Text(
            'You do not have permission to close this show or manage reports.',
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('${widget.showName} • Close Show/Reports V2')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CloseoutStepper(
            steps: _steps,
            selectedIndex: _selectedStep,
            status: _cubeStatus,
            onSelected: (index) {
              setState(() => _selectedStep = index);
              _refreshCubeStatus();
            },
          ),
          const SizedBox(height: 20),
          _buildSelectedPanel(),
          const SizedBox(height: 24),
          _LiveReportDownloads(showId: widget.showId),
        ],
      ),
    );
  }

  Widget _buildSelectedPanel() {
    switch (_selectedStep) {
      case 0:
        return _ArbaDetailsPreviewPanel(
          showId: widget.showId,
          onSaved: _refreshCubeStatus,
        );
      case 1:
        return _MustFixPanel(
          showId: widget.showId,
          showName: widget.showName,
          onChanged: _refreshCubeStatus,
        );
      case 2:
        return _ReviewWarningsPanel(showId: widget.showId);
      case 3:
        return _FinancialPayoutReviewPanel(showId: widget.showId);
      case 4:
        return _GenerateReportsPanel(showId: widget.showId);
      case 5:
        return _PublishResultsPanel(
          showId: widget.showId,
          showName: widget.showName,
        );
      case 6:
        return _DeliveryStatusPanel(showId: widget.showId);
      case 7:
        return _FinalCloseoutPreviewPanel(
          showId: widget.showId,
          showName: widget.showName,
        );
      default:
        return _ComingSoonPanel(title: _steps[_selectedStep]);
    }
  }
}

class _CloseoutStepper extends StatelessWidget {
  final List<String> steps;
  final int selectedIndex;
  final _CloseoutCubeStatus status;
  final ValueChanged<int> onSelected;

  const _CloseoutStepper({
    required this.steps,
    required this.selectedIndex,
    required this.status,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: List<Widget>.generate(steps.length, (index) {
      final selected = index == selectedIndex;
      final cubeColor = _cubeColor(context, index, selected);
      final foregroundColor = _cubeForegroundColor(context, index, selected);
      return Semantics(
        button: true,
        selected: selected,
        label: steps[index],
        child: InkWell(
          key: ValueKey('closeout-v2-step-$index'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => onSelected(index),
          child: Ink(
            width: 142,
            height: 104,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cubeColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : _cubeBorderColor(context, index),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: foregroundColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  steps[index],
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foregroundColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }),
  );

  Color _cubeColor(BuildContext context, int index, bool selected) {
    final colors = Theme.of(context).colorScheme;
    if (selected) return colors.primary;
    if (index == 0 && status.arbaDetailsIncomplete) {
      return colors.errorContainer;
    }
    if (index == 1 && status.placementIssues) {
      return colors.errorContainer;
    }
    if (index == 2 && status.warnings) return Colors.amber.shade100;
    if (index == 5 && status.reportsReadyToSend) {
      return Colors.green.shade100;
    }
    if (index == 6 && status.deliveriesNeedingResend) {
      return colors.errorContainer;
    }
    return colors.surfaceContainerHighest;
  }

  Color? _cubeForegroundColor(BuildContext context, int index, bool selected) {
    final colors = Theme.of(context).colorScheme;
    if (selected) return Colors.white;
    if ((index == 0 && status.arbaDetailsIncomplete) ||
        (index == 1 && status.placementIssues)) {
      return colors.onErrorContainer;
    }
    if (index == 2 && status.warnings) return Colors.amber.shade900;
    if (index == 5 && status.reportsReadyToSend) return Colors.green.shade900;
    if (index == 6 && status.deliveriesNeedingResend) {
      return colors.onErrorContainer;
    }
    return null;
  }

  Color _cubeBorderColor(BuildContext context, int index) {
    final colors = Theme.of(context).colorScheme;
    if ((index == 0 && status.arbaDetailsIncomplete) ||
        (index == 1 && status.placementIssues)) {
      return colors.error;
    }
    if (index == 2 && status.warnings) return Colors.amber.shade800;
    if (index == 5 && status.reportsReadyToSend) return Colors.green.shade700;
    if (index == 6 && status.deliveriesNeedingResend) return colors.error;
    return Theme.of(context).dividerColor;
  }
}

class _CloseoutCubeStatus {
  final bool arbaDetailsIncomplete;
  final bool placementIssues;
  final bool warnings;
  final bool reportsReadyToSend;
  final bool deliveriesNeedingResend;

  const _CloseoutCubeStatus({
    this.arbaDetailsIncomplete = false,
    this.placementIssues = false,
    this.warnings = false,
    this.reportsReadyToSend = false,
    this.deliveriesNeedingResend = false,
  });
}

class _PreviewCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;

  const _PreviewCard({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(subtitle),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );
}

class _ArbaDetailsPreviewPanel extends StatefulWidget {
  final String showId;
  final Future<void> Function() onSaved;

  const _ArbaDetailsPreviewPanel({required this.showId, required this.onSaved});

  @override
  State<_ArbaDetailsPreviewPanel> createState() =>
      _ArbaDetailsPreviewPanelState();
}

class _ArbaDetailsPreviewPanelState extends State<_ArbaDetailsPreviewPanel> {
  bool _sweepstakesIssue = false;
  bool _officialProtest = false;
  bool _arbaReportFiled = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, String> _values = const {};

  @override
  void initState() {
    super.initState();
    _loadSavedDetails();
  }

  Future<void> _loadSavedDetails() async {
    try {
      final client = Supabase.instance.client;
      final results = await Future.wait<dynamic>([
        client
            .from('shows')
            .select(
              'secretary_name, secretary_address, secretary_email, secretary_phone',
            )
            .eq('id', widget.showId)
            .maybeSingle(),
        client
            .from('show_arba_report_details')
            .select(
              'secretary_name, secretary_address, secretary_email, secretary_phone, superintendent_name, superintendent_arba_number, sweepstakes_issue, sweepstakes_club, official_protest, arba_report_filed',
            )
            .eq('show_id', widget.showId)
            .maybeSingle(),
        client
            .from('show_closeout_state')
            .select('exhibitor_emails_sent_at, club_reports_sent_at')
            .eq('show_id', widget.showId)
            .maybeSingle(),
      ]);
      if (!mounted) return;
      final show = Map<String, dynamic>.from(results[0] as Map? ?? {});
      final arba = Map<String, dynamic>.from(results[1] as Map? ?? {});
      final closeout = Map<String, dynamic>.from(results[2] as Map? ?? {});
      String first(Object? primary, Object? fallback) {
        final value = primary?.toString().trim() ?? '';
        return value.isNotEmpty ? value : (fallback?.toString().trim() ?? '');
      }

      setState(() {
        _values = {
          'Show Secretary Name': first(
            show['secretary_name'],
            arba['secretary_name'],
          ),
          'Secretary Address': first(
            show['secretary_address'],
            arba['secretary_address'],
          ),
          'Secretary Email': first(
            show['secretary_email'],
            arba['secretary_email'],
          ),
          'Secretary Phone': first(
            show['secretary_phone'],
            arba['secretary_phone'],
          ),
          'Superintendent Name': arba['superintendent_name']?.toString() ?? '',
          'Superintendent ARBA Number':
              arba['superintendent_arba_number']?.toString() ?? '',
          'Date Reports Were Sent to Exhibitors': _formatDate(
            closeout['exhibitor_emails_sent_at'],
          ),
          'Date Sweepstakes Reports Were Filed with Clubs': _formatDate(
            closeout['club_reports_sent_at'],
          ),
          'Affected Sweepstakes Club':
              arba['sweepstakes_club']?.toString() ?? '',
        };
        _sweepstakesIssue = arba['sweepstakes_issue'] == true;
        _officialProtest = arba['official_protest'] == true;
        _arbaReportFiled =
            _officialProtest && arba['arba_report_filed'] == true;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  String _formatDate(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '';
    return '${date.month}/${date.day}/${date.year}';
  }

  void _setValue(String key, String value) =>
      setState(() => _values = {..._values, key: value});

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final client = Supabase.instance.client;
      await client
          .from('shows')
          .update({
            'secretary_name': _values['Show Secretary Name']?.trim(),
            'secretary_address': _values['Secretary Address']?.trim(),
            'secretary_email': _values['Secretary Email']?.trim(),
            'secretary_phone': _values['Secretary Phone']?.trim(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', widget.showId);
      await client.from('show_arba_report_details').upsert({
        'show_id': widget.showId,
        'secretary_name': _values['Show Secretary Name']?.trim(),
        'secretary_address': _values['Secretary Address']?.trim(),
        'secretary_email': _values['Secretary Email']?.trim(),
        'secretary_phone': _values['Secretary Phone']?.trim(),
        'superintendent_name': _values['Superintendent Name']?.trim(),
        'superintendent_arba_number': _values['Superintendent ARBA Number']
            ?.trim(),
        'sweepstakes_issue': _sweepstakesIssue,
        'sweepstakes_club': _sweepstakesIssue
            ? _values['Affected Sweepstakes Club']?.trim()
            : null,
        'official_protest': _officialProtest,
        'arba_report_filed': _officialProtest ? _arbaReportFiled : null,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ARBA closeout information saved.')),
      );
      await widget.onSaved();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to save ARBA closeout information: $error'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => _PreviewCard(
    title: 'ARBA Final Closeout Confirmation',
    subtitle: 'Complete the required show and protest information',
    children: [
      if (_loading)
        const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          ),
        )
      else if (_error != null)
        Text('Unable to load saved ARBA closeout details: $_error')
      else ...[
        _ArbaPreviewTextField(
          label: 'Show Secretary Name',
          initialValue: _values['Show Secretary Name'],
          onChanged: (value) => _setValue('Show Secretary Name', value),
        ),
        const SizedBox(height: 12),
        _ArbaPreviewTextField(
          label: 'Secretary Address',
          maxLines: 2,
          initialValue: _values['Secretary Address'],
          onChanged: (value) => _setValue('Secretary Address', value),
        ),
        const SizedBox(height: 12),
        _ArbaPreviewTextField(
          label: 'Secretary Email',
          keyboardType: TextInputType.emailAddress,
          initialValue: _values['Secretary Email'],
          onChanged: (value) => _setValue('Secretary Email', value),
        ),
        const SizedBox(height: 12),
        _ArbaPreviewTextField(
          label: 'Secretary Phone',
          keyboardType: TextInputType.phone,
          initialValue: _values['Secretary Phone'],
          onChanged: (value) => _setValue('Secretary Phone', value),
        ),
        const SizedBox(height: 12),
        _ArbaPreviewTextField(
          label: 'Superintendent Name',
          initialValue: _values['Superintendent Name'],
          onChanged: (value) => _setValue('Superintendent Name', value),
        ),
        const SizedBox(height: 12),
        _ArbaPreviewTextField(
          label: 'Superintendent ARBA Number',
          initialValue: _values['Superintendent ARBA Number'],
          onChanged: (value) => _setValue('Superintendent ARBA Number', value),
        ),
        const SizedBox(height: 12),
        _ArbaPreviewTextField(
          label: 'Date Reports Were Sent to Exhibitors',
          hintText: 'Recorded from the first successful send',
          initialValue: _values['Date Reports Were Sent to Exhibitors'],
        ),
        const SizedBox(height: 12),
        _ArbaPreviewTextField(
          label: 'Date Sweepstakes Reports Were Filed with Clubs',
          hintText: 'Recorded from the first successful send',
          initialValue:
              _values['Date Sweepstakes Reports Were Filed with Clubs'],
        ),
        const SizedBox(height: 16),
        _ArbaQuestion(
          title: 'Sweepstakes Sanction Issues',
          question:
              'Did you have any trouble receiving sweepstakes sanctions from national specialty clubs?',
          value: _sweepstakesIssue,
          onChanged: (value) => setState(() => _sweepstakesIssue = value),
        ),
        if (_sweepstakesIssue) ...[
          const SizedBox(height: 12),
          _ArbaPreviewTextField(
            label: 'Affected Sweepstakes Club',
            initialValue: _values['Affected Sweepstakes Club'],
            onChanged: (value) => _setValue('Affected Sweepstakes Club', value),
          ),
        ],
        const SizedBox(height: 12),
        _ArbaQuestion(
          title: 'Official Protest',
          question: 'Was there an official protest filed at this show?',
          value: _officialProtest,
          onChanged: (value) => setState(() => _officialProtest = value),
        ),
        if (_officialProtest) ...[
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('ARBA report filed for this protest'),
            value: _arbaReportFiled,
            onChanged: (value) =>
                setState(() => _arbaReportFiled = value ?? false),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Saving…' : 'Save ARBA Closeout Info'),
        ),
      ],
    ],
  );
}

class _ArbaPreviewTextField extends StatelessWidget {
  final String label;
  final String? hintText;
  final String? initialValue;
  final int maxLines;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  const _ArbaPreviewTextField({
    required this.label,
    this.hintText,
    this.initialValue,
    this.maxLines = 1,
    this.keyboardType,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
    initialValue: initialValue,
    maxLines: maxLines,
    keyboardType: keyboardType,
    onChanged: onChanged,
    decoration: InputDecoration(
      labelText: label,
      hintText: hintText,
      border: const OutlineInputBorder(),
    ),
  );
}

class _ArbaQuestion extends StatelessWidget {
  final String title;
  final String question;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ArbaQuestion({
    required this.title,
    required this.question,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).dividerColor),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(question),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(value ? 'Yes' : 'No'),
          value: value,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

class _MustFixPanel extends StatefulWidget {
  final String showId;
  final String showName;
  final Future<void> Function() onChanged;
  const _MustFixPanel({
    required this.showId,
    required this.showName,
    required this.onChanged,
  });

  @override
  State<_MustFixPanel> createState() => _MustFixPanelState();
}

class _MustFixPanelState extends State<_MustFixPanel> {
  bool _loading = true;
  String? _error;
  List<_PlacementIssue> _issues = const [];

  @override
  void initState() {
    super.initState();
    _loadIssues();
  }

  Future<void> _loadIssues() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await Supabase.instance.client.rpc(
        'report_results_entry_rows',
        params: {
          'p_show_id': widget.showId,
          'p_section_id': null,
          'p_show_letter': null,
        },
      );
      final issues = <_PlacementIssue>[];
      for (final raw in rows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final status =
            '${row['result_status'] ?? row['status'] ?? ''} ${row['disqualified_reason'] ?? ''}'
                .toLowerCase();
        final eligible =
            (row['scratched_at'] ?? '').toString().trim().isEmpty &&
            row['is_shown'] != false &&
            row['is_disqualified'] != true &&
            !const [
              'no show',
              'scratch',
              'disqual',
              'wrong sex',
              'wrong variety',
              'wrong class',
              'overweight',
              'unworthy',
            ].any(status.contains);
        if (eligible && (row['placement'] ?? '').toString().trim().isEmpty) {
          issues.add(_PlacementIssue.fromRow(row));
        }
      }
      issues.sort((a, b) => a.description.compareTo(b.description));
      if (!mounted) return;
      setState(() {
        _issues = issues;
        _loading = false;
      });
      await widget.onChanged();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _fix(_PlacementIssue issue) async {
    if (issue.entryId.isEmpty) return;
    await openResultsEntryFix(
      context,
      showId: widget.showId,
      showName: widget.showName,
      entryId: issue.entryId,
    );
    if (mounted) _loadIssues();
  }

  @override
  Widget build(BuildContext context) => _PreviewCard(
    title: 'Needs Fixed',
    subtitle: 'Please correct any issues listed before continuing.',
    children: [
      if (_loading)
        const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          ),
        )
      else if (_error != null)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Unable to load placement issues: $_error'),
            OutlinedButton.icon(
              onPressed: _loadIssues,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        )
      else if (_issues.isEmpty)
        const Text('No missing eligible placements found.')
      else
        ..._issues.map(
          (issue) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.error_outline, color: Colors.red),
            title: Text(issue.tattoo.isEmpty ? '(No ear #)' : issue.tattoo),
            subtitle: Text(issue.description),
            trailing: TextButton.icon(
              onPressed: issue.entryId.isEmpty ? null : () => _fix(issue),
              icon: const Icon(Icons.build_outlined),
              label: const Text('Fix now'),
            ),
          ),
        ),
    ],
  );
}

class _PlacementIssue {
  final String entryId;
  final String tattoo;
  final String description;
  const _PlacementIssue({
    required this.entryId,
    required this.tattoo,
    required this.description,
  });
  factory _PlacementIssue.fromRow(Map<String, dynamic> row) {
    String value(String key) => row[key]?.toString().trim() ?? '';
    return _PlacementIssue(
      entryId: value('entry_id'),
      tattoo: value('tattoo'),
      description: [
        value('section_label'),
        value('breed_name'),
        value('group_name'),
        value('variety_name'),
        value('class_name'),
        value('sex'),
        value('exhibitor_label'),
      ].where((part) => part.isNotEmpty).join(' • '),
    );
  }
}

class _ReviewWarningsPanel extends StatefulWidget {
  final String showId;

  const _ReviewWarningsPanel({required this.showId});

  @override
  State<_ReviewWarningsPanel> createState() => _ReviewWarningsPanelState();
}

class _ReviewWarningsPanelState extends State<_ReviewWarningsPanel> {
  bool _loading = true;
  String? _error;
  List<_CloseoutWarning> _warnings = const [];

  @override
  void initState() {
    super.initState();
    _loadWarnings();
  }

  Future<void> _loadWarnings() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final results = await Future.wait<dynamic>([
        client
            .from('show_sections')
            .select('id,display_name,kind,letter')
            .eq('show_id', widget.showId)
            .eq('is_enabled', true)
            .order('sort_order')
            .order('letter'),
        client
            .from('show_sanctions')
            .select(
              'section_id,sanctioning_body,club_name,breed_name,sanction_number,request_status,use_arba_number',
            )
            .eq('show_id', widget.showId),
        client
            .from('show_arba_report_details')
            .select(
              'superintendent_arba_number,sweepstakes_issue,sweepstakes_club,official_protest,arba_report_filed',
            )
            .eq('show_id', widget.showId)
            .maybeSingle(),
        client
            .from('shows')
            .select(
              'secretary_name,secretary_address,secretary_email,secretary_phone',
            )
            .eq('id', widget.showId)
            .maybeSingle(),
      ]);

      String value(Map<String, dynamic> row, String key) =>
          row[key]?.toString().trim() ?? '';
      final sections = (results[0] as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      final sanctions = (results[1] as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      final arbaDetails = Map<String, dynamic>.from(results[2] as Map? ?? {});
      final show = Map<String, dynamic>.from(results[3] as Map? ?? {});
      final sectionNameById = <String, String>{
        for (final section in sections)
          value(section, 'id'): _sectionLabel(section),
      };
      final warnings = <_CloseoutWarning>[];

      for (final section in sections) {
        final sectionId = value(section, 'id');
        final hasArbaNumber = sanctions.any(
          (sanction) =>
              value(sanction, 'section_id') == sectionId &&
              value(sanction, 'sanctioning_body').toLowerCase() == 'arba' &&
              value(sanction, 'sanction_number').isNotEmpty,
        );
        if (!hasArbaNumber) {
          warnings.add(
            _CloseoutWarning(
              title: 'Missing ARBA sanction number',
              detail:
                  '${_sectionLabel(section)} does not have an ARBA sanction number.',
              icon: Icons.badge_outlined,
            ),
          );
        }
      }

      for (final sanction in sanctions) {
        final body = value(sanction, 'sanctioning_body').toLowerCase();
        final breed = value(sanction, 'breed_name');
        final number = value(sanction, 'sanction_number');
        final status = value(sanction, 'request_status').toLowerCase();
        final usesArbaNumber = sanction['use_arba_number'] == true;
        if (body == 'arba' ||
            breed.isEmpty ||
            number.isNotEmpty ||
            usesArbaNumber) {
          continue;
        }

        final section =
            sectionNameById[value(sanction, 'section_id')] ?? 'This section';
        final club = value(sanction, 'club_name');
        final sanctionLabel = [
          club,
          breed,
        ].where((part) => part.isNotEmpty).join(' • ');
        if (_isWaitingOn(status)) {
          warnings.add(
            _CloseoutWarning(
              title:
                  'Breed sanction is still waiting on ${_waitingOnLabel(status)}',
              detail:
                  '$sanctionLabel in $section is marked ${_statusLabel(status)} and has no sanction number yet.',
              icon: Icons.hourglass_top_outlined,
            ),
          );
        } else {
          warnings.add(
            _CloseoutWarning(
              title: 'Breed sanction has no number',
              detail:
                  '$sanctionLabel in $section has no sanction number recorded.',
              icon: Icons.confirmation_number_outlined,
            ),
          );
        }
      }

      if (value(arbaDetails, 'superintendent_arba_number').isEmpty) {
        warnings.add(
          const _CloseoutWarning(
            title: 'Superintendent ARBA number is missing',
            detail: 'Review the Show ARBA Details before the final closeout.',
            icon: Icons.person_search_outlined,
          ),
        );
      }

      final missingSecretaryFields = <String>[];
      if (value(show, 'secretary_name').isEmpty) {
        missingSecretaryFields.add('name');
      }
      if (value(show, 'secretary_address').isEmpty) {
        missingSecretaryFields.add('address');
      }
      if (value(show, 'secretary_email').isEmpty) {
        missingSecretaryFields.add('email');
      }
      if (value(show, 'secretary_phone').isEmpty) {
        missingSecretaryFields.add('phone');
      }
      if (missingSecretaryFields.isNotEmpty) {
        warnings.add(
          _CloseoutWarning(
            title: 'Show secretary details are incomplete',
            detail:
                'Missing ${missingSecretaryFields.join(', ')} in Show ARBA Details.',
            icon: Icons.contact_page_outlined,
          ),
        );
      }

      if (arbaDetails['sweepstakes_issue'] == true &&
          value(arbaDetails, 'sweepstakes_club').isEmpty) {
        warnings.add(
          const _CloseoutWarning(
            title: 'Sweepstakes sanction issue needs a club',
            detail:
                'A sweepstakes issue is recorded, but no affected club is identified.',
            icon: Icons.flag_outlined,
          ),
        );
      }
      if (arbaDetails['official_protest'] == true &&
          arbaDetails['arba_report_filed'] != true) {
        warnings.add(
          const _CloseoutWarning(
            title: 'Official protest report is not marked filed',
            detail: 'Review the protest information in Show ARBA Details.',
            icon: Icons.gavel_outlined,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _warnings = warnings;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  String _sectionLabel(Map<String, dynamic> section) {
    final displayName = section['display_name']?.toString().trim() ?? '';
    if (displayName.isNotEmpty) return displayName;
    final kind = section['kind']?.toString().trim() ?? 'Section';
    final letter = section['letter']?.toString().trim() ?? '';
    return letter.isEmpty ? kind : '$kind $letter';
  }

  bool _isWaitingOn(String status) =>
      status.contains('requested') || status.contains('waiting');

  String _waitingOnLabel(String status) {
    if (status.contains('exhibitor')) return 'the exhibitor';
    if (status.contains('secretary')) return 'the secretary';
    return 'a response';
  }

  String _statusLabel(String status) {
    if (status == 'exhibitor_requested') return 'waiting on exhibitor';
    if (status == 'secretary_requested') return 'waiting on secretary';
    return status.replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context) => _PreviewCard(
    title: 'Review Warnings',
    subtitle:
        'These issues will not prevent you from sending reports but you should review each one before continuing.',
    children: [
      if (_loading)
        const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          ),
        )
      else if (_error != null)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Unable to load closeout warnings: $_error'),
            OutlinedButton.icon(
              onPressed: _loadWarnings,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        )
      else if (_warnings.isEmpty)
        const Text('No sanction or ARBA details need review.')
      else
        ..._warnings.map(
          (warning) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(warning.icon, color: Colors.amber.shade900),
            title: Text(warning.title),
            subtitle: Text(warning.detail),
          ),
        ),
    ],
  );
}

class _CloseoutWarning {
  final String title;
  final String detail;
  final IconData icon;

  const _CloseoutWarning({
    required this.title,
    required this.detail,
    required this.icon,
  });
}

class _FinancialPayoutReviewPanel extends StatefulWidget {
  final String showId;

  const _FinancialPayoutReviewPanel({required this.showId});

  @override
  State<_FinancialPayoutReviewPanel> createState() =>
      _FinancialPayoutReviewPanelState();
}

class _FinancialPayoutReviewPanelState
    extends State<_FinancialPayoutReviewPanel> {
  bool _loading = true;
  String? _error;
  _FinancialCloseoutSummary? _summary;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final sectionsRaw = await client
          .from('show_sections')
          .select('id')
          .eq('show_id', widget.showId)
          .eq('is_enabled', true)
          .order('sort_order')
          .order('letter');
      final sectionIds = (sectionsRaw as List)
          .map((row) => (row as Map)['id']?.toString().trim() ?? '')
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
      if (sectionIds.isEmpty) {
        throw StateError('No enabled show sections were found.');
      }
      final checkinSettings = await client
          .from('show_checkin_settings')
          .select('is_enabled,opens_at,closes_at')
          .eq('show_id', widget.showId)
          .maybeSingle();

      final balanceRows =
          await _loadPagedRpc('report_show_exhibitor_balances_scoped', {
            'p_show_id': widget.showId,
            'p_section_ids': sectionIds,
            'p_submitted_only': true,
          });
      final paybackRowsBySection = await Future.wait(
        sectionIds.map(
          (sectionId) => _loadPagedRpc('report_payback_rows', {
            'p_show_id': widget.showId,
            'p_section_id': sectionId,
          }),
        ),
      );
      final paybackRows = paybackRowsBySection.expand((rows) => rows).toList();
      if (!mounted) return;
      setState(() {
        _summary = _FinancialCloseoutSummary.fromRows(
          balanceRows: balanceRows,
          paybackRows: paybackRows,
          checkinActive: _isCheckinActive(checkinSettings),
        );
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  bool _isCheckinActive(Map<String, dynamic>? settings) {
    if (settings?['is_enabled'] != true) return false;
    final now = DateTime.now().toUtc();
    final opensAt = DateTime.tryParse(
      '${settings?['opens_at'] ?? ''}',
    )?.toUtc();
    final closesAt = DateTime.tryParse(
      '${settings?['closes_at'] ?? ''}',
    )?.toUtc();
    return (opensAt == null || !now.isBefore(opensAt)) &&
        (closesAt == null || !now.isAfter(closesAt));
  }

  Future<List<Map<String, dynamic>>> _loadPagedRpc(
    String rpcName,
    Map<String, dynamic> params,
  ) async {
    const pageSize = 1000;
    final allRows = <Map<String, dynamic>>[];
    for (var from = 0; ; from += pageSize) {
      final rows = await Supabase.instance.client
          .rpc(rpcName, params: params)
          .range(from, from + pageSize - 1);
      final batch = (rows as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      allRows.addAll(batch);
      if (batch.length < pageSize) return allRows;
    }
  }

  @override
  Widget build(BuildContext context) => _PreviewCard(
    title: 'Financial and Payout Review',
    subtitle:
        'Live, read-only totals from the current balance and payback data. No payments or payouts can be changed here.',
    children: [
      if (_loading)
        const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          ),
        )
      else if (_error != null)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Unable to load financial closeout data: $_error'),
            OutlinedButton.icon(
              onPressed: _loadSummary,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        )
      else if (_summary != null) ...[
        _FinancialTotalGrid(summary: _summary!),
        const SizedBox(height: 16),
        Text('Items to review', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        if (_summary!.reviewItems.isEmpty)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.check_circle_outline, color: Colors.green),
            title: Text(
              'No balance allocation or outstanding-balance issues found.',
            ),
          )
        else
          ..._summary!.reviewItems.map(
            (item) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(item.icon, color: Colors.amber.shade900),
              title: Text(item.title),
              subtitle: Text(item.detail),
              trailing: item.opensBalanceDueCheckIn && _summary!.checkinActive
                  ? TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ShowCheckinRosterScreen(
                            showId: widget.showId,
                            initialStatus: 'balance_due',
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open Check-In'),
                    )
                  : null,
            ),
          ),
      ],
    ],
  );
}

class _FinancialTotalGrid extends StatelessWidget {
  final _FinancialCloseoutSummary summary;

  const _FinancialTotalGrid({required this.summary});

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 12,
    children: [
      _FinancialTotalTile(
        label: 'Entry fees',
        amountCents: summary.calculatedTotalCents,
      ),
      _FinancialTotalTile(
        label: 'Payments received',
        amountCents: summary.paymentsReceivedCents,
      ),
      _FinancialTotalTile(label: 'Refunds', amountCents: summary.refundsCents),
      _FinancialTotalTile(
        label: 'Outstanding balance',
        amountCents: summary.outstandingBalanceCents,
        emphasize: summary.outstandingBalanceCents > 0,
        note:
            'Cash taken at the show must be recorded in Check-In before this balance will change.',
      ),
      _FinancialTotalTile(
        label: 'Paybacks to distribute',
        amountCents: summary.paybackTotalCents,
      ),
    ],
  );
}

class _FinancialTotalTile extends StatelessWidget {
  final String label;
  final int amountCents;
  final bool emphasize;
  final String? note;

  const _FinancialTotalTile({
    required this.label,
    required this.amountCents,
    this.emphasize = false,
    this.note,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: emphasize ? Colors.amber.shade50 : null,
        border: Border.all(
          color: emphasize
              ? Colors.amber.shade700
              : Theme.of(context).dividerColor,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              _currency(amountCents),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (note != null) ...[
              const SizedBox(height: 6),
              Text(note!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    ),
  );

  String _currency(int cents) {
    final absolute = (cents.abs() / 100).toStringAsFixed(2);
    return cents < 0 ? '-\$$absolute' : '\$$absolute';
  }
}

class _FinancialCloseoutSummary {
  final int calculatedTotalCents;
  final int paymentsReceivedCents;
  final int refundsCents;
  final int outstandingBalanceCents;
  final int paybackTotalCents;
  final bool checkinActive;
  final List<_FinancialReviewItem> reviewItems;

  const _FinancialCloseoutSummary({
    required this.calculatedTotalCents,
    required this.paymentsReceivedCents,
    required this.refundsCents,
    required this.outstandingBalanceCents,
    required this.paybackTotalCents,
    required this.checkinActive,
    required this.reviewItems,
  });

  factory _FinancialCloseoutSummary.fromRows({
    required List<Map<String, dynamic>> balanceRows,
    required List<Map<String, dynamic>> paybackRows,
    required bool checkinActive,
  }) {
    int cents(Object? value) {
      if (value is num) return value.round();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    String text(Map<String, dynamic> row, String key) =>
        row[key]?.toString().trim() ?? '';
    int sum(String key) =>
        balanceRows.fold(0, (total, row) => total + cents(row[key]));
    final calculatedTotal = sum('calculated_total_cents');
    final paidOnline = sum('paid_online_cents');
    final paidManual = sum('paid_manual_cents');
    final refunds = sum('refunded_cents');
    final outstanding = sum('balance_due_cents');
    final paybacks = paybackRows.fold(
      0,
      (total, row) => total + cents(row['amount_cents']).clamp(0, 1 << 62),
    );
    final reviewItems = <_FinancialReviewItem>[];

    final ambiguousRows = balanceRows
        .where(
          (row) =>
              text(row, 'payment_allocation_status').toLowerCase() ==
              'ambiguous',
        )
        .toList();
    if (ambiguousRows.isNotEmpty) {
      reviewItems.add(
        _FinancialReviewItem(
          title:
              '${ambiguousRows.length} payment allocation${ambiguousRows.length == 1 ? '' : 's'} need review',
          detail:
              'Those payments or discounts are recorded at the whole-show level and cannot be allocated reliably to a section.',
          icon: Icons.account_balance_outlined,
        ),
      );
    }

    final unpaidRows =
        balanceRows.where((row) => cents(row['balance_due_cents']) > 0).toList()
          ..sort(
            (a, b) => cents(
              b['balance_due_cents'],
            ).compareTo(cents(a['balance_due_cents'])),
          );
    if (unpaidRows.isNotEmpty) {
      final names = unpaidRows
          .take(3)
          .map((row) => text(row, 'exhibitor_name'))
          .where((name) => name.isNotEmpty)
          .join(', ');
      reviewItems.add(
        _FinancialReviewItem(
          title:
              '${unpaidRows.length} exhibitor${unpaidRows.length == 1 ? '' : 's'} still ha${unpaidRows.length == 1 ? 's' : 've'} a balance due',
          detail: names.isEmpty
              ? 'Outstanding balances total ${_money(outstanding)}.${checkinActive ? '' : ' Check-In is not active for this show.'}'
              : '$names${unpaidRows.length > 3 ? ', and more' : ''}. Outstanding balances total ${_money(outstanding)}.${checkinActive ? '' : ' Check-In is not active for this show.'}',
          icon: Icons.payments_outlined,
          opensBalanceDueCheckIn: true,
        ),
      );
    }
    final overpaidRows = balanceRows
        .where((row) => cents(row['balance_due_cents']) < 0)
        .length;
    if (overpaidRows > 0) {
      reviewItems.add(
        _FinancialReviewItem(
          title:
              '$overpaidRows overpaid balance${overpaidRows == 1 ? '' : 's'} found',
          detail: 'Review refunds or manual-payment records before closeout.',
          icon: Icons.currency_exchange_outlined,
        ),
      );
    }

    return _FinancialCloseoutSummary(
      calculatedTotalCents: calculatedTotal,
      paymentsReceivedCents: paidOnline + paidManual,
      refundsCents: refunds,
      outstandingBalanceCents: outstanding,
      paybackTotalCents: paybacks,
      checkinActive: checkinActive,
      reviewItems: reviewItems,
    );
  }

  static String _money(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';
}

class _FinancialReviewItem {
  final String title;
  final String detail;
  final IconData icon;
  final bool opensBalanceDueCheckIn;

  const _FinancialReviewItem({
    required this.title,
    required this.detail,
    required this.icon,
    this.opensBalanceDueCheckIn = false,
  });
}

class _GenerateReportsPanel extends StatefulWidget {
  final String showId;

  const _GenerateReportsPanel({required this.showId});

  @override
  State<_GenerateReportsPanel> createState() => _GenerateReportsPanelState();
}

class _GenerateReportsPanelState extends State<_GenerateReportsPanel> {
  Timer? _poller;
  bool _loading = true;
  bool _starting = false;
  String? _error;
  _ReportGenerationState? _state;
  DateTime? _startedAt;
  int _initialReportTotal = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadAllQueueTasks(
    String finalizeRunId,
  ) async {
    const batchSize = 100;
    final tasks = <Map<String, dynamic>>[];
    for (var from = 0; ; from += batchSize) {
      final rows = await Supabase.instance.client
          .from('show_task_queue')
          .select('task_status')
          .eq('show_id', widget.showId)
          .eq('finalize_run_id', finalizeRunId)
          .order('created_at')
          .range(from, from + batchSize - 1);
      final batch = (rows as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      tasks.addAll(batch);
      if (batch.length < batchSize) return tasks;
    }
  }

  Future<void> _refresh() async {
    try {
      final sectionsRaw = await Supabase.instance.client
          .from('show_sections')
          .select('id')
          .eq('show_id', widget.showId)
          .eq('is_enabled', true)
          .order('sort_order')
          .order('letter');
      final sectionIds =
          (sectionsRaw as List)
              .map((row) => (row as Map)['id']?.toString().trim() ?? '')
              .where((id) => id.isNotEmpty)
              .toList()
            ..sort();
      if (sectionIds.isEmpty) {
        throw StateError('No enabled show sections found.');
      }
      final dashboard = await Supabase.instance.client.rpc(
        'get_closeout_dashboard_scoped_for_species',
        params: {
          'p_show_id': widget.showId,
          'p_scope_key': '${widget.showId}:${sectionIds.join(',')}',
          'p_section_ids': sectionIds,
          'p_artifact_limit': 100,
          'p_artifact_offset': 0,
          'p_species_filter': null,
        },
      );
      var next = _ReportGenerationState.fromJson(
        Map<String, dynamic>.from(dashboard as Map),
        sectionIds: sectionIds,
      );
      if (next.finalizeRunId.isNotEmpty) {
        final liveRows = await Future.wait<dynamic>([
          _loadAllQueueTasks(next.finalizeRunId),
          Supabase.instance.client
              .from('show_report_artifacts')
              .select('artifact_status,report_name')
              .eq('show_id', widget.showId)
              .eq('finalize_run_id', next.finalizeRunId)
              .eq('is_current', true)
              .neq('report_name', 'arba_report'),
        ]);
        next = next.withLiveQueue(
          tasks: liveRows[0] as List,
          artifacts: liveRows[1] as List,
        );
      }
      if (!mounted) return;
      if (_startedAt == null && next.isActive) {
        _startedAt = DateTime.now();
      }
      final observedTotal = next.reportTotal > 0
          ? next.reportTotal
          : next.taskTotal;
      if (observedTotal > _initialReportTotal) {
        _initialReportTotal = observedTotal;
      }
      setState(() {
        _state = next;
        _loading = false;
        _error = null;
      });
      _updatePolling(next.isActive);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _updatePolling(bool active) {
    if (active) {
      _poller ??= Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
    } else {
      _poller?.cancel();
      _poller = null;
    }
  }

  Future<void> _start() async {
    final state = _state;
    if (state == null || !state.ready || state.isActive) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final action = state.finalizeRunId.isEmpty
          ? 'finalize'
          : state.hasFailures
          ? 'generate_remaining'
          : 'regenerate_all';
      final response = await Supabase.instance.client.functions.invoke(
        'run-closeout',
        body: {
          'show_id': widget.showId,
          if (state.finalizeRunId.isNotEmpty)
            'finalize_run_id': state.finalizeRunId,
          'section_ids': state.sectionIds,
          'scope_label': 'Entire show',
          'scope_key': state.scopeKey,
          'action': action,
          'caller': 'closeoutV2Preview',
        },
      );
      if (response.status >= 400) {
        final data = response.data;
        throw StateError(
          data is Map && data['error'] != null
              ? data['error'].toString()
              : 'Closeout queue request failed.',
        );
      }
      _startedAt = DateTime.now();
      _initialReportTotal = 0;
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) => _PreviewCard(
    title: 'Generate Reports',
    subtitle:
        'All non-ARBA reports are prepared and generated for distribution. ARBA reports are generated in Step 8 after delivery dates are recorded.',
    children: [
      if (_loading)
        const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          ),
        )
      else if (_error != null)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Unable to load report generation status: $_error'),
            OutlinedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        )
      else if (_state != null) ...[
        _GenerationProgressPanel(
          state: _state!,
          startedAt: _startedAt,
          initialReportTotal: _initialReportTotal,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: !_state!.ready || _state!.isActive || _starting
              ? null
              : _start,
          icon: Icon(
            _state!.finalizeRunId.isEmpty
                ? Icons.auto_awesome
                : Icons.play_circle_outline,
          ),
          label: Text(
            _starting
                ? 'Queueing reports…'
                : _state!.finalizeRunId.isEmpty
                ? 'Finalize & Queue Reports'
                : _state!.hasFailures
                ? 'Queue Remaining Reports'
                : 'Requeue All Reports',
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'You can leave this page while reports generate; progress will continue on the server.',
        ),
      ],
    ],
  );
}

class _GenerationProgressPanel extends StatelessWidget {
  final _ReportGenerationState state;
  final DateTime? startedAt;
  final int initialReportTotal;

  const _GenerationProgressPanel({
    required this.state,
    required this.startedAt,
    required this.initialReportTotal,
  });

  @override
  Widget build(BuildContext context) {
    final total = state.reportTotal > 0 ? state.reportTotal : state.taskTotal;
    final complete = state.reportTotal > 0
        ? state.generated + state.reportFailed
        : state.completed + state.failed;
    final progress = total == 0 ? 0.0 : (complete / total).clamp(0.0, 1.0);
    final eta = _eta(
      total: initialReportTotal > 0 ? initialReportTotal : total,
      complete: complete,
    );
    final title = state.isActive
        ? 'Report generation is running'
        : state.finalizeRunId.isEmpty
        ? 'Ready to finalize and queue reports'
        : state.hasFailures
        ? 'Report generation is blocked by failed reports'
        : total > 0
        ? 'Report generation is complete'
        : 'Reports are ready to be queued';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: state.hasFailures ? Colors.orange.shade50 : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 8),
          Text(
            '$complete of $total reports complete • ${state.queued} queued • ${state.running} running • ${state.failed + state.reportFailed} failed',
          ),
          if (eta != null)
            Text('Estimated time remaining: ${_formatDuration(eta)}'),
          if (!state.ready) ...[
            const SizedBox(height: 8),
            Text(
              'Blocked: ${state.readinessMessage}',
              style: TextStyle(color: Colors.red.shade800),
            ),
          ],
        ],
      ),
    );
  }

  Duration? _eta({required int total, required int complete}) {
    final elapsed = startedAt == null
        ? Duration.zero
        : DateTime.now().difference(startedAt!);
    if (total <= 0 ||
        complete <= 0 ||
        complete >= total ||
        elapsed < const Duration(seconds: 3)) {
      return null;
    }
    return Duration(
      milliseconds: (elapsed.inMilliseconds * (total - complete) / complete)
          .round(),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration < const Duration(minutes: 1)) return 'less than a minute';
    final minutes = (duration.inSeconds / 60).ceil();
    return minutes < 60
        ? 'about $minutes minutes'
        : 'about ${minutes ~/ 60} hr ${minutes % 60} min';
  }
}

class _ReportGenerationState {
  final List<String> sectionIds;
  final String scopeKey;
  final String finalizeRunId;
  final bool ready;
  final String readinessMessage;
  final int queued;
  final int running;
  final int completed;
  final int failed;
  final int reportTotal;
  final int generated;
  final int reportFailed;

  const _ReportGenerationState({
    required this.sectionIds,
    required this.scopeKey,
    required this.finalizeRunId,
    required this.ready,
    required this.readinessMessage,
    required this.queued,
    required this.running,
    required this.completed,
    required this.failed,
    required this.reportTotal,
    required this.generated,
    required this.reportFailed,
  });

  factory _ReportGenerationState.fromJson(
    Map<String, dynamic> json, {
    required List<String> sectionIds,
  }) {
    final readiness = Map<String, dynamic>.from(
      json['results_readiness'] as Map? ?? {},
    );
    final tasks = Map<String, dynamic>.from(json['task_counts'] as Map? ?? {});
    final artifacts = Map<String, dynamic>.from(
      json['artifact_counts'] as Map? ?? {},
    );
    final latest = Map<String, dynamic>.from(
      json['latest_finalize'] as Map? ?? {},
    );
    int number(Map<String, dynamic> map, String key) =>
        (map[key] as num?)?.toInt() ?? int.tryParse('${map[key] ?? 0}') ?? 0;
    final problems = <String>[];
    for (final entry in <String, String>{
      'missing_placement_count': 'missing placements',
      'missing_judge_count': 'missing judges',
      'duplicate_placement_group_count': 'duplicate placements',
      'missing_final_award_count': 'missing final awards',
      'duplicate_final_award_count': 'duplicate final awards',
    }.entries) {
      final count = number(readiness, entry.key);
      if (count > 0) problems.add('$count ${entry.value}');
    }
    return _ReportGenerationState(
      sectionIds: sectionIds,
      scopeKey:
          '${json['dashboard'] is Map ? (json['dashboard'] as Map)['show_id'] ?? '' : ''}:${sectionIds.join(',')}',
      finalizeRunId: '${latest['id'] ?? ''}'.trim(),
      ready: readiness['ready'] == true,
      readinessMessage: problems.isEmpty
          ? 'Results are not ready.'
          : problems.join(', '),
      queued: number(tasks, 'queued'),
      running: number(tasks, 'running'),
      completed: number(tasks, 'completed'),
      failed: number(tasks, 'failed'),
      reportTotal: number(artifacts, 'total'),
      generated: number(artifacts, 'generated'),
      reportFailed: number(artifacts, 'failed'),
    );
  }

  int get taskTotal => queued + running + completed + failed;
  bool get isActive => queued > 0 || running > 0;
  bool get hasFailures => failed > 0 || reportFailed > 0;

  _ReportGenerationState withLiveQueue({
    required List tasks,
    required List artifacts,
  }) {
    int countStatus(List rows, String field, String value) => rows
        .where((row) => (row as Map)[field]?.toString().toLowerCase() == value)
        .length;
    int countAnyStatus(List rows, String field, Set<String> values) => rows
        .where(
          (row) =>
              values.contains((row as Map)[field]?.toString().toLowerCase()),
        )
        .length;

    // The task feed is eventually consistent while the renderer works. The
    // artifact rows are created with the run and therefore give Step 5 an
    // authoritative view of reports still waiting to be rendered.
    final taskQueued = countStatus(tasks, 'task_status', 'queued');
    final taskRunning = countStatus(tasks, 'task_status', 'running');
    final artifactQueued = countAnyStatus(artifacts, 'artifact_status', {
      'queued',
      'pending',
      'claimed',
    });
    final artifactRunning = countAnyStatus(artifacts, 'artifact_status', {
      'running',
      'processing',
      'rendering',
      'uploading',
      'generating',
    });
    return _ReportGenerationState(
      sectionIds: sectionIds,
      scopeKey: scopeKey,
      finalizeRunId: finalizeRunId,
      ready: ready,
      readinessMessage: readinessMessage,
      queued: taskQueued > artifactQueued ? taskQueued : artifactQueued,
      running: taskRunning > artifactRunning ? taskRunning : artifactRunning,
      completed: countStatus(tasks, 'task_status', 'completed'),
      failed: countStatus(tasks, 'task_status', 'failed'),
      reportTotal: artifacts.length,
      generated: countStatus(artifacts, 'artifact_status', 'generated'),
      reportFailed: countStatus(artifacts, 'artifact_status', 'failed'),
    );
  }
}

class _PublishResultsPanel extends StatefulWidget {
  final String showId;
  final String showName;

  const _PublishResultsPanel({required this.showId, required this.showName});

  @override
  State<_PublishResultsPanel> createState() => _PublishResultsPanelState();
}

class _PublishResultsPanelState extends State<_PublishResultsPanel> {
  bool _loading = true;
  bool _sending = false;
  String? _error;
  List<ReportArtifactSummary> _artifacts = const [];
  List<Map<String, dynamic>> _sections = const [];
  String _scopeId = 'all';
  final _additionalMessageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadArtifacts();
  }

  @override
  void dispose() {
    _additionalMessageController.dispose();
    super.dispose();
  }

  Future<void> _loadArtifacts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final responses = await Future.wait<dynamic>([
        Supabase.instance.client
            .from('show_report_artifacts')
            .select(
              'id,show_id,finalize_run_id,report_name,artifact_status,file_name,storage_bucket,storage_path,generated_at,is_current,scope_key,section_ids,generation,created_at,error_count,metadata',
            )
            .eq('show_id', widget.showId)
            .eq('is_current', true),
        Supabase.instance.client
            .from('show_sections')
            .select('id,display_name,kind,letter,sort_order')
            .eq('show_id', widget.showId)
            .eq('is_enabled', true)
            .order('sort_order')
            .order('letter'),
      ]);
      final artifacts = (responses[0] as List)
          .map(
            (row) => ReportArtifactSummary.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();
      final exhibitorIds = artifacts
          .where(
            (artifact) =>
                artifact.reportName == 'exhibitor_report' ||
                artifact.reportName == 'legs',
          )
          .map((artifact) => artifact.metadata['exhibitor_id']?.toString())
          .whereType<String>()
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      if (exhibitorIds.isNotEmpty) {
        final rows = await Supabase.instance.client
            .from('exhibitors')
            .select('id,email')
            .inFilter('id', exhibitorIds);
        final emailsByExhibitorId = <String, String>{
          for (final raw in rows as List)
            (raw as Map)['id']?.toString().trim() ?? '': (raw['email'] ?? '')
                .toString()
                .trim(),
        }..removeWhere((id, email) => id.isEmpty || email.isEmpty);
        for (final artifact in artifacts) {
          final metadata = artifact.metadata;
          final existingEmail =
              (metadata['exhibitor_email'] ?? metadata['email'] ?? '')
                  .toString()
                  .trim();
          if (existingEmail.isNotEmpty) continue;
          final exhibitorId = metadata['exhibitor_id']?.toString().trim() ?? '';
          final email = emailsByExhibitorId[exhibitorId];
          if (email != null) metadata['exhibitor_email'] = email;
        }
      }
      if (!mounted) return;
      setState(() {
        _artifacts = artifacts;
        _sections = (responses[1] as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  int _generatedWhere(bool Function(ReportArtifactSummary artifact) test) =>
      _artifacts
          .where((artifact) => artifact.artifactStatus == 'generated')
          .where(test)
          .length;

  bool _inScope(ReportArtifactSummary artifact) =>
      _scopeId == 'all' ||
      artifact.sectionIds.contains(_scopeId) ||
      artifact.metadata['section_id']?.toString() == _scopeId;

  String _sectionLabel(Map<String, dynamic> section) {
    final name = section['display_name']?.toString().trim() ?? '';
    if (name.isNotEmpty) return name;
    final kind = section['kind']?.toString().trim() ?? 'Show';
    final letter = section['letter']?.toString().trim() ?? '';
    return letter.isEmpty ? kind : '$kind $letter';
  }

  String? _recipientEmail(
    ReportArtifactSummary artifact, {
    required bool clubs,
  }) {
    final value =
        (clubs
                ? artifact.metadata['sweepstakes_email']
                : artifact.metadata['exhibitor_email'] ??
                      artifact.metadata['email'])
            ?.toString()
            .trim()
            .toLowerCase();
    return value?.isEmpty ?? true ? null : value;
  }

  Map<String, List<ReportArtifactSummary>> _deliveryGroups(
    List<ReportArtifactSummary> artifacts, {
    required bool clubs,
  }) {
    final groups = <String, List<ReportArtifactSummary>>{};
    for (final artifact in artifacts) {
      final email = _recipientEmail(artifact, clubs: clubs);
      if (email == null) continue;

      // Club packages are keyed by the club identity as well as its address.
      // This keeps reports for two different clubs separate when they happen
      // to share one mailbox, while grouping every report for one club.
      final metadata = artifact.metadata;
      final clubKey = [
        metadata['sanctioning_body'],
        metadata['club_name'],
        metadata['breed_name'],
        metadata['species'],
        email,
      ].map((value) => value?.toString().trim().toLowerCase() ?? '').join('|');
      final key = clubs ? clubKey : email;
      groups.putIfAbsent(key, () => []).add(artifact);
    }
    return groups;
  }

  Future<void> _sendReports({required bool clubs}) async {
    final additionalMessage = _additionalMessageController.text.trim();
    final eligible = _artifacts
        .where((artifact) => artifact.artifactStatus == 'generated')
        .where(_inScope)
        .where(
          (artifact) => clubs
              ? artifact.metadata['sweepstakes_email']
                            ?.toString()
                            .trim()
                            .isNotEmpty ==
                        true &&
                    artifact.reportName != 'arba_report'
              : artifact.metadata['exhibitor_email']
                            ?.toString()
                            .trim()
                            .isNotEmpty ==
                        true &&
                    (artifact.reportName == 'exhibitor_report' ||
                        artifact.reportName == 'legs'),
        )
        .toList();
    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No generated ${clubs ? 'club' : 'exhibitor'} reports are ready to send.',
          ),
        ),
      );
      return;
    }
    final groups = _deliveryGroups(eligible, clubs: clubs);
    final recipientCount = groups.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Send ${clubs ? 'Club' : 'Exhibitor'} Reports?'),
        content: Text(
          clubs
              ? 'This will send one email to each of $recipientCount club ${recipientCount == 1 ? 'recipient' : 'recipients'}. Each email includes that club\'s generated report package.'
              : 'This will send one email to each of $recipientCount exhibitor ${recipientCount == 1 ? 'recipient' : 'recipients'}, including their generated reports.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send Reports'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _sending = true);
    _activeDeliveryProgress.value = _ActiveDeliveryProgress(
      recipientType: clubs ? 'club' : 'exhibitor',
      totalBatches: groups.length,
      completedBatches: 0,
    );
    try {
      final emailService = ReportEmailService();
      var successful = 0;
      for (final entry in groups.entries) {
        final recipient = _recipientEmail(entry.value.first, clubs: clubs);
        if (recipient == null) continue;
        if (clubs) {
          await emailService.sendClubReportEmail(
            showId: widget.showId,
            artifactIds: entry.value.map((artifact) => artifact.id).toList(),
            to: recipient,
            subject: '${widget.showName} - Club Reports',
            message: additionalMessage,
            // A secretary note changes the content of a prior package, so it
            // must not be absorbed by the recipient/subject duplicate check.
            forceResend: additionalMessage.isNotEmpty,
          );
        } else {
          await emailService.sendExhibitorReportEmail(
            showId: widget.showId,
            artifactIds: entry.value.map((artifact) => artifact.id).toList(),
            to: recipient,
            subject: '${widget.showName} - Exhibitor Reports',
            message: additionalMessage,
            allowLegs: true,
            forceResend: additionalMessage.isNotEmpty,
          );
        }
        successful++;
        _activeDeliveryProgress.value = _ActiveDeliveryProgress(
          recipientType: clubs ? 'club' : 'exhibitor',
          totalBatches: groups.length,
          completedBatches: successful,
        );
      }
      await Supabase.instance.client.from('show_closeout_state').upsert({
        'show_id': widget.showId,
        clubs ? 'club_reports_sent_at' : 'exhibitor_emails_sent_at':
            DateTime.now().toUtc().toIso8601String(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$successful ${clubs ? 'club' : 'exhibitor'} email batch${successful == 1 ? '' : 'es'} sent.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Report send failed: $error')));
    } finally {
      _activeDeliveryProgress.value = null;
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final exhibitorReports = _generatedWhere(
      (artifact) =>
          _inScope(artifact) &&
          (artifact.reportName == 'exhibitor_report' ||
              artifact.reportName == 'legs'),
    );
    final clubReports = _generatedWhere(
      (artifact) =>
          _inScope(artifact) &&
          (artifact.reportName == 'sweepstakes_report' ||
              artifact.metadata['club_name'] != null),
    );
    final clubRecipients = _deliveryGroups(
      _artifacts
          .where((artifact) => artifact.artifactStatus == 'generated')
          .where(_inScope)
          .where((artifact) => artifact.reportName != 'arba_report')
          .where((artifact) => _recipientEmail(artifact, clubs: true) != null)
          .toList(),
      clubs: true,
    ).length;
    return _PreviewCard(
      title: 'Send Results',
      subtitle:
          'Review the generated report package and intended recipients before sending.',
      children: [
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_error != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Unable to load publish results: $_error'),
              OutlinedButton.icon(
                onPressed: _loadArtifacts,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          )
        else ...[
          DropdownButtonFormField<String>(
            initialValue: _scopeId,
            decoration: const InputDecoration(
              labelText: 'Send scope',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: 'all', child: Text('All shows')),
              ..._sections.map(
                (section) => DropdownMenuItem(
                  value: section['id']?.toString(),
                  child: Text(_sectionLabel(section)),
                ),
              ),
            ],
            onChanged: (value) => setState(() => _scopeId = value ?? 'all'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _additionalMessageController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Optional message from the show secretary',
              hintText:
                  'Add a note to include with every selected report email.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          _PublishTargetTile(
            icon: Icons.people_outline,
            title: 'Exhibitors',
            detail:
                '$exhibitorReports generated exhibitor or legs report files would be sent for this show.',
            buttonLabel: 'Send Exhibitor Reports',
            onPressed: _sending ? null : () => _sendReports(clubs: false),
          ),
          _PublishTargetTile(
            icon: Icons.groups_outlined,
            title: 'Clubs',
            detail:
                '$clubRecipients club recipient${clubRecipients == 1 ? '' : 's'} would receive $clubReports generated report file${clubReports == 1 ? '' : 's'} for this show.',
            buttonLabel: 'Send Club Reports',
            onPressed: _sending ? null : () => _sendReports(clubs: true),
          ),
          const SizedBox(height: 8),
          const Text(
            'Each send requires confirmation. Step 7 will show each result.',
          ),
        ],
      ],
    );
  }
}

class _PublishTargetTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final String buttonLabel;
  final VoidCallback? onPressed;

  const _PublishTargetTile({
    required this.icon,
    required this.title,
    required this.detail,
    required this.buttonLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(detail),
    trailing: OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.send_outlined),
      label: Text(buttonLabel),
    ),
  );
}

class _DeliveryStatusPanel extends StatefulWidget {
  final String showId;
  const _DeliveryStatusPanel({required this.showId});

  @override
  State<_DeliveryStatusPanel> createState() => _DeliveryStatusPanelState();
}

class _DeliveryStatusPanelState extends State<_DeliveryStatusPanel> {
  Timer? _poller;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _deliveries = const [];
  Map<String, Map<String, dynamic>> _artifactMetadata = const {};
  final _search = TextEditingController();
  int _page = 0;
  static const _pageSize = 10;

  @override
  void initState() {
    super.initState();
    _activeDeliveryProgress.addListener(_onActiveDeliveryChanged);
    _load();
  }

  @override
  void dispose() {
    _poller?.cancel();
    _activeDeliveryProgress.removeListener(_onActiveDeliveryChanged);
    _search.dispose();
    super.dispose();
  }

  void _onActiveDeliveryChanged() {
    if (!mounted) return;
    if (_activeDeliveryProgress.value != null) {
      _poller ??= Timer.periodic(const Duration(seconds: 3), (_) => _load());
    }
    setState(() {});
  }

  Future<void> _load() async {
    try {
      final allRows = <Map<String, dynamic>>[];
      const batchSize = 1000;
      for (var from = 0; ; from += batchSize) {
        final rows = await Supabase.instance.client
            .from('show_email_deliveries')
            .select(
              'id,artifact_id,recipient_name,recipient_email,report_name,delivery_status,error_message,sent_at,created_at',
            )
            .eq('show_id', widget.showId)
            .order('created_at', ascending: false)
            .range(from, from + batchSize - 1);
        final batch = (rows as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
        allRows.addAll(batch);
        if (batch.length < batchSize) break;
      }
      final artifacts = await Supabase.instance.client
          .from('show_report_artifacts')
          .select('id,metadata')
          .eq('show_id', widget.showId);
      if (!mounted) return;
      final deliveries = allRows;
      final active = deliveries.any((row) {
        final status = (row['delivery_status'] ?? '').toString().toLowerCase();
        return status == 'pending' ||
            status == 'sending' ||
            status == 'processing';
      });
      setState(() {
        _deliveries = deliveries;
        _artifactMetadata = {
          for (final raw in artifacts as List)
            (raw as Map)['id']?.toString() ?? '': Map<String, dynamic>.from(
              (raw['metadata'] as Map?) ?? const {},
            ),
        };
        _loading = false;
        _error = null;
      });
      if (active || _activeDeliveryProgress.value != null) {
        _poller ??= Timer.periodic(const Duration(seconds: 3), (_) => _load());
      } else {
        _poller?.cancel();
        _poller = null;
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final batchProgress = _activeDeliveryProgress.value;
    final total = _deliveries.length;
    final sent = _deliveries
        .where(
          (row) =>
              (row['delivery_status'] ?? '').toString().toLowerCase() == 'sent',
        )
        .length;
    final active = _deliveries
        .where(
          (row) => const [
            'pending',
            'sending',
            'processing',
          ].contains((row['delivery_status'] ?? '').toString().toLowerCase()),
        )
        .length;
    final filtered =
        _deliveries.where((row) {
          final query = _search.text.trim().toLowerCase();
          if (query.isEmpty) return true;
          return '${_deliveryType(row)} ${row['recipient_name'] ?? ''} ${row['recipient_email'] ?? ''} ${row['report_name'] ?? ''}'
              .toLowerCase()
              .contains(query);
        }).toList()..sort((a, b) {
          final aSentAt = DateTime.tryParse(
            '${a['sent_at'] ?? a['created_at'] ?? ''}',
          );
          final bSentAt = DateTime.tryParse(
            '${b['sent_at'] ?? b['created_at'] ?? ''}',
          );
          final fallback = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
          return (bSentAt ?? fallback).compareTo(aSentAt ?? fallback);
        });
    final pageCount = (filtered.length / _pageSize).ceil().clamp(1, 1 << 20);
    final currentPage = _page.clamp(0, pageCount - 1);
    final pageRows = filtered
        .skip(currentPage * _pageSize)
        .take(_pageSize)
        .toList();
    return _PreviewCard(
      title: 'Report Delivery Status',
      subtitle: active > 0 || batchProgress != null
          ? 'Delivery is in progress and refreshes every few seconds.'
          : 'Live delivery history. Retry and resend remain disabled in this preview.',
      children: [
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_error != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Unable to load delivery status: $_error'),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          )
        else if (total == 0)
          const Text('No report deliveries have been recorded yet.')
        else ...[
          if (batchProgress != null) ...[
            LinearProgressIndicator(value: batchProgress.progress),
            const SizedBox(height: 8),
            Text(
              '${batchProgress.completedBatches} of ${batchProgress.totalBatches} '
              '${batchProgress.recipientType} email batches sent',
            ),
            const SizedBox(height: 8),
          ] else if (active > 0) ...[
            LinearProgressIndicator(value: sent / total),
            const SizedBox(height: 8),
            Text('$sent of $total deliveries sent • $active in progress'),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: _search,
            decoration: const InputDecoration(
              labelText: 'Search deliveries',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() => _page = 0),
          ),
          const SizedBox(height: 8),
          ...pageRows.map(_deliveryTile),
          if (filtered.length > _pageSize)
            Row(
              children: [
                Text('Page ${currentPage + 1} of $pageCount'),
                const Spacer(),
                IconButton(
                  onPressed: currentPage == 0
                      ? null
                      : () => setState(() => _page = currentPage - 1),
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  onPressed: currentPage >= pageCount - 1
                      ? null
                      : () => setState(() => _page = currentPage + 1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
        ],
      ],
    );
  }

  Widget _deliveryTile(Map<String, dynamic> row) {
    final status = (row['delivery_status'] ?? 'unknown').toString();
    final normalized = status.toLowerCase();
    final failed = const [
      'failed',
      'bounced',
      'complained',
      'suppressed',
    ].contains(normalized);
    final pending = const [
      'pending',
      'sending',
      'processing',
    ].contains(normalized);
    final color = failed
        ? Colors.red
        : pending
        ? Colors.orange
        : Colors.green;
    final recipient =
        (row['recipient_name'] ?? row['recipient_email'] ?? 'Recipient')
            .toString();
    final reason = (row['error_message'] ?? '').toString().trim();
    final sentAt = row['sent_at'];
    final timestamp = _formatDeliveryTime(sentAt ?? row['created_at']);
    return _DeliveryTile(
      icon: failed
          ? Icons.error_outline
          : pending
          ? Icons.schedule_outlined
          : Icons.check_circle_outline,
      color: color,
      status: '${_deliveryType(row)} • $status — $recipient',
      reason: reason.isEmpty
          ? pending
                ? 'The delivery provider is still processing this message.'
                : 'Accepted by the recipient mail server.'
          : reason,
      timestamp: timestamp.isEmpty
          ? null
          : '${sentAt == null ? 'Created' : 'Sent'}: $timestamp',
      showRetry: failed,
      needsResend: failed,
    );
  }

  String _formatDeliveryTime(Object? value) {
    final dateTime = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (dateTime == null) return '';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final meridiem = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '${months[dateTime.month - 1]} ${dateTime.day}, ${dateTime.year} at $hour:$minute $meridiem';
  }

  String _deliveryType(Map<String, dynamic> row) {
    final report = (row['report_name'] ?? '').toString();
    if (report == 'arba_report') return 'ARBA';
    final metadata =
        _artifactMetadata[row['artifact_id']?.toString()] ?? const {};
    final type =
        '${metadata['club_type'] ?? metadata['sanctioning_body'] ?? metadata['club_kind'] ?? ''}'
            .toLowerCase();
    if (type.contains('national')) return 'National Breed Club';
    if (type.contains('state breed')) return 'State Breed Club';
    if (type.contains('state')) return 'State Club';
    return report == 'exhibitor_report' || report == 'legs'
        ? 'Exhibitor'
        : 'National Breed Club';
  }
}

class _DeliveryTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String status;
  final String reason;
  final String? timestamp;
  final bool showRetry;
  final bool needsResend;
  const _DeliveryTile({
    required this.icon,
    required this.color,
    required this.status,
    required this.reason,
    required this.timestamp,
    required this.showRetry,
    required this.needsResend,
  });
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 2),
    decoration: needsResend
        ? BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(8),
          )
        : null,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Icon(icon, color: color),
      title: Text(status),
      subtitle: Text(timestamp == null ? reason : '$reason\n$timestamp'),
      trailing: showRetry
          ? const Tooltip(
              message: 'Retry is unavailable for this delivery.',
              child: OutlinedButton(
                onPressed: null,
                child: Text('Retry / resend'),
              ),
            )
          : null,
    ),
  );
}

class _FinalCloseoutPreviewPanel extends StatefulWidget {
  final String showId;
  final String showName;

  const _FinalCloseoutPreviewPanel({
    required this.showId,
    required this.showName,
  });

  @override
  State<_FinalCloseoutPreviewPanel> createState() =>
      _FinalCloseoutPreviewPanelState();
}

class _FinalCloseoutPreviewPanelState
    extends State<_FinalCloseoutPreviewPanel> {
  bool _loading = true;
  bool _savingLock = false;
  bool _downloadingLockedData = false;
  bool _isLocked = false;
  bool _isFinalized = false;
  String? _error;
  _FinalCloseoutReadiness? _readiness;

  List<ReportArtifactSummary> _currentArbaReports(List rows) {
    final reports = rows.map((row) {
      final raw = Map<String, dynamic>.from(row as Map);
      final metadata = Map<String, dynamic>.from(
        raw['metadata'] as Map? ?? const {},
      );
      raw['metadata'] = metadata;
      return ReportArtifactSummary.fromJson(raw);
    }).toList();
    final seenSections = <String>{};
    return reports.where((report) {
      final sectionId = report.metadata['section_id']?.toString().trim();
      return seenSections.add(
        sectionId == null || sectionId.isEmpty ? report.id : sectionId,
      );
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sections = await Supabase.instance.client
          .from('show_sections')
          .select('id')
          .eq('show_id', widget.showId)
          .eq('is_enabled', true)
          .order('sort_order')
          .order('letter');
      final sectionIds =
          (sections as List)
              .map((row) => (row as Map)['id']?.toString().trim() ?? '')
              .where((id) => id.isNotEmpty)
              .toList()
            ..sort();
      if (sectionIds.isEmpty) {
        throw StateError('No enabled show sections found.');
      }
      final values = await Future.wait<Object?>([
        Supabase.instance.client.rpc(
          'get_closeout_dashboard_scoped_for_species',
          params: {
            'p_show_id': widget.showId,
            'p_scope_key': '${widget.showId}:${sectionIds.join(',')}',
            'p_section_ids': sectionIds,
            'p_artifact_limit': 1,
            'p_artifact_offset': 0,
            'p_species_filter': null,
          },
        ),
        Supabase.instance.client
            .from('show_arba_report_details')
            .select(
              'secretary_name,secretary_address,secretary_email,secretary_phone,superintendent_name,superintendent_arba_number,sweepstakes_issue,sweepstakes_club,official_protest,arba_report_filed',
            )
            .eq('show_id', widget.showId)
            .maybeSingle(),
        Supabase.instance.client
            .from('show_report_artifacts')
            .select(
              'id,show_id,finalize_run_id,report_name,artifact_status,file_name,storage_bucket,storage_path,generated_at,is_current,scope_key,section_ids,generation,created_at,error_count,metadata',
            )
            .eq('show_id', widget.showId)
            .eq('report_name', 'arba_report')
            .eq('is_current', true)
            .order('generated_at', ascending: false)
            .order('created_at', ascending: false),
        Supabase.instance.client
            .from('show_closeout_state')
            .select('exhibitor_emails_sent_at,club_reports_sent_at')
            .eq('show_id', widget.showId)
            .maybeSingle(),
        Supabase.instance.client
            .from('shows')
            .select('is_locked,finalized_at')
            .eq('id', widget.showId)
            .maybeSingle(),
      ]);
      if (!mounted) return;
      setState(() {
        _readiness = _FinalCloseoutReadiness.fromJson(
          dashboard: Map<String, dynamic>.from(values[0] as Map),
          arba: values[1] == null
              ? const <String, dynamic>{}
              : Map<String, dynamic>.from(values[1] as Map),
          arbaReports: _currentArbaReports(values[2] as List),
          exhibitorReportsSentAt:
              (values[3] as Map?)?['exhibitor_emails_sent_at']?.toString(),
          clubReportsSentAt: (values[3] as Map?)?['club_reports_sent_at']
              ?.toString(),
        );
        final show = Map<String, dynamic>.from(values[4] as Map? ?? const {});
        _isLocked = show['is_locked'] == true;
        _isFinalized = (show['finalized_at'] ?? '')
            .toString()
            .trim()
            .isNotEmpty;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _toggleShowLock() async {
    if (_savingLock || _isFinalized) return;
    final nextLocked = !_isLocked;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(nextLocked ? 'Lock Show?' : 'Unlock Show?'),
            content: Text(
              nextLocked
                  ? 'This will prevent setup changes like sections, fees, judges, sanctions, rules, and show details.\n\nShow data and report files may be retained on the server for up to 1 year.\n\nYou can unlock it at any time.'
                  : 'This will allow setup changes again. Only unlock if corrections are needed.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(nextLocked ? 'Lock Show' : 'Unlock Show'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    setState(() => _savingLock = true);
    try {
      await Supabase.instance.client
          .from('shows')
          .update({
            'is_locked': nextLocked,
            'locked_at': nextLocked
                ? DateTime.now().toUtc().toIso8601String()
                : null,
          })
          .eq('id', widget.showId);
      if (!mounted) return;
      setState(() => _isLocked = nextLocked);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(nextLocked ? 'Show locked.' : 'Show unlocked.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to update show lock: $error')),
      );
    } finally {
      if (mounted) setState(() => _savingLock = false);
    }
  }

  Future<void> _downloadLockedShowData() async {
    if (!_isLocked || _downloadingLockedData) return;
    setState(() => _downloadingLockedData = true);
    try {
      await downloadLockedShowDataExport(
        showId: widget.showId,
        showName: widget.showName,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Locked show ZIP downloaded.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to download locked show data: $error')),
      );
    } finally {
      if (mounted) setState(() => _downloadingLockedData = false);
    }
  }

  @override
  Widget build(BuildContext context) => _PreviewCard(
    title: 'Submit ARBA Report and Lock Show',
    subtitle:
        'Review the final readiness check before ARBA submission and locking the show.',
    children: [
      if (_loading)
        const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          ),
        )
      else if (_error != null)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Unable to load final closeout readiness: $_error'),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        )
      else if (_readiness != null) ...[
        _FinalReadinessSummary(readiness: _readiness!),
        const SizedBox(height: 16),
        _ArbaReportActions(
          showId: widget.showId,
          showName: widget.showName,
          reports: _readiness!.arbaReports,
          exhibitorReportsSentAt: _readiness!.exhibitorReportsSentAt,
          clubReportsSentAt: _readiness!.clubReportsSentAt,
          onChanged: _load,
        ),
        const SizedBox(height: 20),
        Text('Lock Show', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text(
          'Prevent further setup changes before closeout. This will prevent setup changes like sections, fees, judges, sanctions, rules, and show details. You can unlock it at any time.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: _savingLock || _isFinalized ? null : _toggleShowLock,
              icon: Icon(
                _isLocked ? Icons.lock_open_outlined : Icons.lock_outline,
              ),
              label: Text(
                _savingLock
                    ? 'Saving…'
                    : _isFinalized
                    ? 'Show Finalized'
                    : _isLocked
                    ? 'Unlock Show'
                    : 'Lock Show',
              ),
            ),
            if (_isLocked)
              FilledButton.icon(
                onPressed: _downloadingLockedData
                    ? null
                    : _downloadLockedShowData,
                icon: const Icon(Icons.download_for_offline_outlined),
                label: Text(
                  _downloadingLockedData
                      ? 'Preparing ZIP…'
                      : 'Download Locked Show Data',
                ),
              ),
          ],
        ),
      ],
    ],
  );
}

class _FinalCloseoutReadiness {
  final List<String> blockingItems;
  final List<String> reviewItems;
  final int reportTotal;
  final int reportsGenerated;
  final int reportsFailed;
  final List<ReportArtifactSummary> arbaReports;
  final String? exhibitorReportsSentAt;
  final String? clubReportsSentAt;

  const _FinalCloseoutReadiness({
    required this.blockingItems,
    required this.reviewItems,
    required this.reportTotal,
    required this.reportsGenerated,
    required this.reportsFailed,
    required this.arbaReports,
    required this.exhibitorReportsSentAt,
    required this.clubReportsSentAt,
  });

  bool get readyToSubmit =>
      blockingItems.isEmpty &&
      reportTotal > 0 &&
      reportsGenerated >= reportTotal &&
      reportsFailed == 0;

  factory _FinalCloseoutReadiness.fromJson({
    required Map<String, dynamic> dashboard,
    required Map<String, dynamic> arba,
    required List<ReportArtifactSummary> arbaReports,
    required String? exhibitorReportsSentAt,
    required String? clubReportsSentAt,
  }) {
    int number(Map<String, dynamic> map, String key) =>
        (map[key] as num?)?.toInt() ?? int.tryParse('${map[key] ?? 0}') ?? 0;
    final results = Map<String, dynamic>.from(
      dashboard['results_readiness'] as Map? ?? const {},
    );
    final artifacts = Map<String, dynamic>.from(
      dashboard['artifact_counts'] as Map? ?? const {},
    );
    final blocking = <String>[];
    for (final entry in <String, String>{
      'missing_placement_count': 'missing placements',
      'missing_judge_count': 'missing judge assignments',
      'duplicate_placement_group_count': 'duplicate placements',
      'missing_final_award_count': 'missing final awards',
      'duplicate_final_award_count': 'duplicate final awards',
    }.entries) {
      final count = number(results, entry.key);
      if (count > 0) blocking.add('$count ${entry.value}');
    }
    String text(String key) => (arba[key] ?? '').toString().trim();
    for (final entry in <String, String>{
      'secretary_name': 'Show Secretary Name',
      'secretary_address': 'Secretary Address',
      'secretary_email': 'Secretary Email',
      'secretary_phone': 'Secretary Phone',
      'superintendent_name': 'Superintendent Name',
      'superintendent_arba_number': 'Superintendent ARBA Number',
    }.entries) {
      if (text(entry.key).isEmpty) blocking.add('Missing ${entry.value}');
    }
    if (arba['official_protest'] == true && arba['arba_report_filed'] != true) {
      blocking.add('Official protest has not been marked filed with ARBA');
    }
    final review = <String>[];
    if (arba['sweepstakes_issue'] == true) {
      final club = text('sweepstakes_club');
      review.add(
        club.isEmpty
            ? 'Sweepstakes sanction issue needs club details'
            : 'Sweepstakes sanction issue: $club',
      );
    }
    final failed = number(artifacts, 'failed');
    final total = number(artifacts, 'total');
    final generated = number(artifacts, 'generated');
    if (failed > 0) {
      review.add('$failed report${failed == 1 ? '' : 's'} failed to generate');
    }
    if (total > generated + failed) {
      review.add(
        '${total - generated - failed} report${total - generated - failed == 1 ? '' : 's'} still waiting to generate',
      );
    }
    return _FinalCloseoutReadiness(
      blockingItems: blocking,
      reviewItems: review,
      reportTotal: total,
      reportsGenerated: generated,
      reportsFailed: failed,
      arbaReports: arbaReports,
      exhibitorReportsSentAt: exhibitorReportsSentAt,
      clubReportsSentAt: clubReportsSentAt,
    );
  }
}

class _ArbaReportActions extends StatefulWidget {
  final String showId;
  final String showName;
  final List<ReportArtifactSummary> reports;
  final String? exhibitorReportsSentAt;
  final String? clubReportsSentAt;
  final Future<void> Function() onChanged;

  const _ArbaReportActions({
    required this.showId,
    required this.showName,
    required this.reports,
    required this.exhibitorReportsSentAt,
    required this.clubReportsSentAt,
    required this.onChanged,
  });

  @override
  State<_ArbaReportActions> createState() => _ArbaReportActionsState();
}

class _ArbaReportActionsState extends State<_ArbaReportActions> {
  final Set<String> _viewedIds = <String>{};
  final Set<String> _downloadingIds = <String>{};
  bool _queueing = false;
  bool _sending = false;

  bool get _hasDeliveryDates =>
      DateTime.tryParse(widget.exhibitorReportsSentAt ?? '') != null &&
      DateTime.tryParse(widget.clubReportsSentAt ?? '') != null;

  bool _canView(ReportArtifactSummary artifact) =>
      artifact.artifactStatus == 'generated' &&
      artifact.storageBucket?.isNotEmpty == true &&
      artifact.storagePath?.isNotEmpty == true;

  Future<void> _generateReports() async {
    final reportsToQueue = widget.reports.where((report) => !_canView(report));
    if (!_hasDeliveryDates || reportsToQueue.isEmpty) return;
    setState(() => _queueing = true);
    try {
      final runScopeKeys = <String, String>{};
      for (final report in reportsToQueue) {
        final showId = report.showId?.trim() ?? '';
        final runId = report.finalizeRunId?.trim() ?? '';
        if (showId.isEmpty || runId.isEmpty) {
          throw StateError('This ARBA report is missing its closeout scope.');
        }
        final runScopeKey =
            runScopeKeys[runId] ??
            await _loadFinalizeRunScopeKey(showId: showId, runId: runId);
        runScopeKeys[runId] = runScopeKey;
        await Supabase.instance.client.rpc(
          'requeue_closeout_artifacts',
          params: {
            'p_show_id': showId,
            'p_finalize_run_id': runId,
            'p_scope_key': runScopeKey,
            'p_report_name': 'arba_report',
            'p_artifact_id': report.id,
          },
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ARBA reports queued for generation.')),
      );
      await widget.onChanged();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to queue ARBA reports: $error')),
      );
    } finally {
      if (mounted) setState(() => _queueing = false);
    }
  }

  Future<String> _loadFinalizeRunScopeKey({
    required String showId,
    required String runId,
  }) async {
    final row = await Supabase.instance.client
        .from('show_finalize_runs')
        .select('scope_key')
        .eq('id', runId)
        .eq('show_id', showId)
        .maybeSingle();
    final scopeKey = (row?['scope_key'] ?? '').toString().trim();
    if (scopeKey.isEmpty) {
      throw StateError('This ARBA report is missing its finalize run scope.');
    }
    return scopeKey;
  }

  Future<void> _viewReport(ReportArtifactSummary artifact) async {
    if (!_canView(artifact)) return;
    setState(() => _downloadingIds.add(artifact.id));
    try {
      final bytes = await Supabase.instance.client.storage
          .from(artifact.storageBucket!)
          .download(artifact.storagePath!);
      await downloadFileBytes(
        bytes,
        fileName: artifact.fileName?.trim().isNotEmpty == true
            ? artifact.fileName!.trim()
            : 'ARBA Report.pdf',
        mimeType: 'application/pdf',
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to open ARBA report: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _downloadingIds.remove(artifact.id);
          _viewedIds.add(artifact.id);
        });
      }
    }
  }

  Future<String?> _loadArbaEmailTarget() async {
    final rows = await Supabase.instance.client
        .from('show_sanctions')
        .select('sweepstakes_email')
        .eq('show_id', widget.showId)
        .ilike('sanctioning_body', 'ARBA');
    for (final raw in rows as List) {
      final email = (raw as Map)['sweepstakes_email']?.toString().trim() ?? '';
      if (email.isNotEmpty) return email;
    }
    return null;
  }

  Future<void> _sendAllArbaReports() async {
    if (_sending || widget.reports.isEmpty) return;
    final email = await _loadArbaEmailTarget();
    if (!mounted) return;
    if (email == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No ARBA email is configured. Add the ARBA sweepstakes email to the ARBA sanction record first.',
          ),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send All ARBA Reports?'),
        content: Text(
          'This will send one email to $email with all ${widget.reports.length} generated ARBA report${widget.reports.length == 1 ? '' : 's'} attached.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Send Reports'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _sending = true);
    _activeDeliveryProgress.value = const _ActiveDeliveryProgress(
      recipientType: 'ARBA',
      totalBatches: 1,
      completedBatches: 0,
    );
    try {
      final result = await ReportEmailService().sendArbaReportEmail(
        showId: widget.showId,
        artifactIds: widget.reports.map((report) => report.id).toList(),
        to: email,
        subject: '${widget.showName} - ARBA Show Report',
        message:
            'Attached ${widget.reports.length == 1 ? 'is the ARBA show report' : 'are the ARBA show reports'} for ${widget.showName}.',
      );
      if (!mounted) return;
      _activeDeliveryProgress.value = const _ActiveDeliveryProgress(
        recipientType: 'ARBA',
        totalBatches: 1,
        completedBatches: 1,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.alreadySent
                ? 'These ARBA reports were already sent to $email.'
                : '${widget.reports.length} ARBA report${widget.reports.length == 1 ? '' : 's'} sent to $email.',
          ),
        ),
      );
      await widget.onChanged();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to send ARBA reports: $error')),
      );
    } finally {
      _activeDeliveryProgress.value = null;
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reports = widget.reports;
    final allViewed =
        reports.isNotEmpty &&
        reports.every((report) => _viewedIds.contains(report.id));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ARBA Report', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            _hasDeliveryDates
                ? 'Exhibitor reports sent: ${_formatDateTime(widget.exhibitorReportsSentAt)}\nClub reports sent: ${_formatDateTime(widget.clubReportsSentAt)}'
                : 'Generate ARBA reports after Step 6 records the exhibitor and club report delivery dates.',
          ),
          const SizedBox(height: 8),
          if (reports.isEmpty)
            const Text('No ARBA reports have been prepared yet.')
          else
            ...reports.map(
              (report) => Text(
                '${arbaSectionDisplayName(metadata: report.metadata)} — ${closeoutReportStatusLabel(closeoutReportUiStatus(report.artifactStatus))}${report.artifactStatus == 'failed' && (report.metadata['error_message']?.toString().trim().isNotEmpty ?? false) ? ': ${report.metadata['error_message']}' : ''}',
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              Tooltip(
                message: _hasDeliveryDates
                    ? 'ARBA reports are generated separately after Step 6.'
                    : 'Record both report-delivery dates in Step 6 first.',
                child: FilledButton.icon(
                  onPressed: _queueing || !_hasDeliveryDates || reports.isEmpty
                      ? null
                      : _generateReports,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: Text(
                    _queueing
                        ? 'Queueing ARBA Reports…'
                        : 'Generate ARBA Reports',
                  ),
                ),
              ),
              if (allViewed)
                FilledButton.icon(
                  onPressed: _sending ? null : _sendAllArbaReports,
                  icon: const Icon(Icons.send_outlined),
                  label: Text(
                    _sending
                        ? 'Sending ARBA Reports…'
                        : 'Send All ARBA Reports',
                  ),
                ),
            ],
          ),
          if (reports.any(_canView)) ...[
            const SizedBox(height: 12),
            const Text('View each ARBA report before sending.'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: reports.where(_canView).map((report) {
                final label = arbaSectionDisplayName(metadata: report.metadata);
                return OutlinedButton.icon(
                  onPressed: _downloadingIds.contains(report.id)
                      ? null
                      : () => _viewReport(report),
                  icon: const Icon(Icons.visibility_outlined),
                  label: Text(
                    _viewedIds.contains(report.id)
                        ? 'Viewed $label'
                        : 'View $label',
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDateTime(String? value) {
    final dateTime = DateTime.tryParse(value ?? '')?.toLocal();
    if (dateTime == null) return 'Not recorded';
    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final meridiem = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '${dateTime.month}/${dateTime.day}/${dateTime.year} at $hour:$minute $meridiem';
  }
}

class _FinalReadinessSummary extends StatelessWidget {
  final _FinalCloseoutReadiness readiness;

  const _FinalReadinessSummary({required this.readiness});

  @override
  Widget build(BuildContext context) {
    final ready = readiness.readyToSubmit;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ready ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ready ? Colors.green.shade300 : Colors.orange.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ready ? Icons.check_circle_outline : Icons.error_outline,
                color: ready ? Colors.green.shade700 : Colors.orange.shade800,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ready
                      ? 'Ready for final closeout review'
                      : 'Final closeout needs attention',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${readiness.reportsGenerated} of ${readiness.reportTotal} reports generated${readiness.reportsFailed > 0 ? ' • ${readiness.reportsFailed} failed' : ''}',
          ),
          if (readiness.blockingItems.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Must be completed'),
            ...readiness.blockingItems.map(
              (item) => _FinalReadinessItem(
                icon: Icons.cancel_outlined,
                color: Colors.red,
                text: item,
              ),
            ),
          ],
          if (readiness.reviewItems.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Review before submitting'),
            ...readiness.reviewItems.map(
              (item) => _FinalReadinessItem(
                icon: Icons.warning_amber_outlined,
                color: Colors.orange,
                text: item,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FinalReadinessItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _FinalReadinessItem({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _ComingSoonPanel extends StatelessWidget {
  final String title;
  const _ComingSoonPanel({required this.title});
  @override
  Widget build(BuildContext context) => _PreviewCard(
    title: title,
    subtitle:
        'This step is represented in the preview but does not yet have a working demo panel.',
    children: const [Text('Demo actions remain disabled.')],
  );
}

class _LiveReportDownloads extends StatefulWidget {
  final String showId;

  const _LiveReportDownloads({required this.showId});

  @override
  State<_LiveReportDownloads> createState() => _LiveReportDownloadsState();
}

class _LiveReportDownloadsState extends State<_LiveReportDownloads> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  String? _downloadingArtifactId;
  List<ReportArtifactSummary> _artifacts = const [];
  String? _selectedGroup;
  String? _selectedReportName;
  String? _selectedArbaArtifactId;
  String? _selectedExhibitorId;
  String? _selectedBreedName;
  String? _selectedClubName;
  String? _selectedShowLetter;
  String? _selectedScope;
  final _additionalMessageController = TextEditingController();

  static const _groupOrder = ['arba', 'exhibitor', 'club', 'other'];
  static const _manualOtherReports = {
    'unpaid_balances_report',
    'paid_exhibitor_report',
    'entered_exhibitors_contact_report',
    'entered_exhibitors_list_report',
    'ribbon_payout_report',
    'judge_report',
    'breed_judged_totals_report',
    'payback_report',
  };

  @override
  void initState() {
    super.initState();
    _loadArtifacts();
  }

  @override
  void dispose() {
    _additionalMessageController.dispose();
    super.dispose();
  }

  Future<void> _loadArtifacts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _supabase
          .from('show_report_artifacts')
          .select(
            'id, show_id, finalize_run_id, report_name, artifact_status, file_name, storage_bucket, storage_path, generated_at, is_current, scope_key, section_ids, generation, created_at, error_count, metadata',
          )
          .eq('show_id', widget.showId)
          .eq('is_current', true)
          .order('generated_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _artifacts = (rows as List)
            .map(
              (row) => ReportArtifactSummary.fromJson(
                Map<String, dynamic>.from(row as Map),
              ),
            )
            .toList();
        _selectedGroup = _groupOrder.first;
        final reportNames = _reportNamesFor(_selectedGroup);
        _selectedReportName = reportNames.isEmpty ? null : reportNames.first;
        _selectedArbaArtifactId = _arbaArtifacts.isEmpty
            ? null
            : _arbaArtifacts.first.id;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  List<String> get _availableGroups => _groupOrder;

  List<String> _reportNamesFor(String? group) {
    if (group == null) return const [];
    final reportNames =
        _artifacts
            .where((artifact) => _groupFor(artifact.reportName) == group)
            .map((artifact) => artifact.reportName)
            .toSet()
            .toList()
          ..sort();
    if (group == 'other') {
      for (final reportName in _manualOtherReports) {
        if (!reportNames.contains(reportName)) reportNames.add(reportName);
      }
    }
    reportNames.sort();
    return reportNames;
  }

  List<ReportArtifactSummary> get _arbaArtifacts {
    final artifacts =
        _artifacts
            .where((artifact) => artifact.reportName == 'arba_report')
            .toList()
          ..sort(compareCloseoutReportArtifacts);
    return artifacts;
  }

  ReportArtifactSummary? get _selectedArtifact {
    final reportName = _selectedReportName;
    if (reportName == null) return null;
    if (reportName == 'arba_report') {
      return _arbaArtifacts.cast<ReportArtifactSummary?>().firstWhere(
        (artifact) => artifact?.id == _selectedArbaArtifactId,
        orElse: () => null,
      );
    }
    final matches = _filteredReportArtifacts.toList()
      ..sort(compareCloseoutReportArtifacts);
    return matches.isEmpty ? null : matches.first;
  }

  bool get _needsExhibitor => const {
    'exhibitor_report',
    'legs',
    'checkin_sheet',
  }.contains(_selectedReportName);
  bool get _needsBreed => const {
    'sweepstakes_report',
    'breed_results_detail_report',
  }.contains(_selectedReportName);
  bool get _needsClub => const {
    'details_by_breed',
    'exh_by_breed',
    'best_display_report',
  }.contains(_selectedReportName);

  List<ReportArtifactSummary> get _selectedReportArtifacts => _artifacts
      .where((artifact) => artifact.reportName == _selectedReportName)
      .toList();

  List<ReportArtifactSummary> get _filteredReportArtifacts =>
      _selectedReportArtifacts
          .where(
            (a) =>
                !_needsExhibitor ||
                _selectedExhibitorId == null ||
                a.metadata['exhibitor_id']?.toString() == _selectedExhibitorId,
          )
          .where(
            (a) =>
                !_needsBreed ||
                _selectedBreedName == null ||
                a.metadata['breed_name']?.toString() == _selectedBreedName,
          )
          .where(
            (a) =>
                !_needsClub ||
                _selectedClubName == null ||
                a.metadata['club_name']?.toString() == _selectedClubName,
          )
          .where(
            (a) =>
                (!_needsBreed && !_needsClub) ||
                _selectedShowLetter == null ||
                a.metadata['show_letter']?.toString() == _selectedShowLetter,
          )
          .where(
            (a) =>
                (!_needsBreed && !_needsClub) ||
                _selectedScope == null ||
                a.metadata['scope']?.toString().toUpperCase() == _selectedScope,
          )
          .toList();

  List<String> _metadataValues(String key) =>
      _selectedReportArtifacts
          .map((a) => a.metadata[key]?.toString().trim() ?? '')
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

  String _groupFor(String reportName) {
    if (reportName == 'arba_report') return 'arba';
    if (const {
      'exhibitor_report',
      'legs',
      'checkin_sheet',
    }.contains(reportName)) {
      return 'exhibitor';
    }
    if (const {
      'sweepstakes_report',
      'breed_results_detail_report',
      'details_by_breed',
      'exh_by_breed',
      'best_display_report',
    }.contains(reportName)) {
      return 'club';
    }
    return 'other';
  }

  String _friendlyReportName(String reportName) => switch (reportName) {
    'arba_report' => 'ARBA Report',
    'entered_exhibitors_list_report' => 'Exhibitor Number Lookup Report',
    'entered_exhibitors_contact_report' => 'Entered Exhibitors Contact Report',
    'unpaid_balances_report' => 'Unpaid Exhibitor Balances',
    'paid_exhibitor_report' => 'Paid Exhibitor Report',
    'ribbon_payout_report' => 'Ribbon Report',
    'payback_report' => 'Paybacks Report',
    _ =>
      reportName
          .split('_')
          .where((word) => word.isNotEmpty)
          .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
          .join(' '),
  };

  String _arbaLabel(ReportArtifactSummary artifact) =>
      arbaSectionDisplayName(metadata: artifact.metadata);

  String _groupLabel(String group) => switch (group) {
    'arba' => 'ARBA Reports',
    'exhibitor' => 'Exhibitor Reports',
    'club' => 'Club Reports',
    _ => 'Other Reports',
  };

  Future<void> _download(ReportArtifactSummary artifact) async {
    if (artifact.artifactStatus != 'generated' ||
        artifact.storageBucket?.isEmpty != false ||
        artifact.storagePath?.isEmpty != false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This report does not have a downloadable file yet.'),
        ),
      );
      return;
    }
    setState(() => _downloadingArtifactId = artifact.id);
    try {
      final bytes = await _supabase.storage
          .from(artifact.storageBucket!)
          .download(artifact.storagePath!);
      await downloadFileBytes(
        bytes,
        fileName: artifact.fileName?.trim().isNotEmpty == true
            ? artifact.fileName!.trim()
            : '${_friendlyReportName(artifact.reportName)}.pdf',
        mimeType: 'application/pdf',
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Download failed: $error')));
    } finally {
      if (mounted) setState(() => _downloadingArtifactId = null);
    }
  }

  Widget _metadataDropdown({
    required String label,
    required String? value,
    required List<String> values,
    required ValueChanged<String?> onChanged,
    String Function(String value)? display,
  }) {
    final selectedValue = values.contains(value) ? value : null;
    return DropdownButtonFormField<String>(
      key: ValueKey('closeout-v2-$label-$_selectedReportName'),
      initialValue: selectedValue,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: values
          .map(
            (item) => DropdownMenuItem(
              value: item,
              child: Text(display?.call(item) ?? item),
            ),
          )
          .toList(),
      onChanged: values.isEmpty ? null : onChanged,
    );
  }

  @override
  Widget build(BuildContext context) => _PreviewCard(
    title: 'Reports & Distribution',
    subtitle: 'View and download generated reports for this show.',
    children: [
      if (_loading)
        const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          ),
        )
      else if (_error != null)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Unable to load generated reports: $_error'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _loadArtifacts,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        )
      else ...[
        DropdownButtonFormField<String>(
          key: const ValueKey('closeout-v2-report-group'),
          initialValue: _selectedGroup,
          decoration: const InputDecoration(
            labelText: 'Report Group',
            border: OutlineInputBorder(),
          ),
          items: _availableGroups
              .map(
                (group) => DropdownMenuItem(
                  value: group,
                  child: Text(_groupLabel(group)),
                ),
              )
              .toList(),
          onChanged: (group) {
            if (group == null) return;
            final reportNames = _reportNamesFor(group);
            setState(() {
              _selectedGroup = group;
              _selectedReportName = reportNames.isEmpty
                  ? null
                  : reportNames.first;
              _selectedArbaArtifactId =
                  group == 'arba' && _arbaArtifacts.isNotEmpty
                  ? _arbaArtifacts.first.id
                  : null;
              _selectedExhibitorId = null;
              _selectedBreedName = null;
              _selectedClubName = null;
              _selectedShowLetter = null;
              _selectedScope = null;
            });
          },
        ),
        const SizedBox(height: 12),
        if (_selectedGroup == 'arba')
          DropdownButtonFormField<String>(
            key: ValueKey('closeout-v2-arba-picker-$_selectedArbaArtifactId'),
            initialValue: _selectedArbaArtifactId,
            decoration: const InputDecoration(
              labelText: 'ARBA Report',
              border: OutlineInputBorder(),
            ),
            items: _arbaArtifacts
                .map(
                  (artifact) => DropdownMenuItem(
                    value: artifact.id,
                    child: Text(_arbaLabel(artifact)),
                  ),
                )
                .toList(),
            onChanged: _arbaArtifacts.isEmpty
                ? null
                : (artifactId) =>
                      setState(() => _selectedArbaArtifactId = artifactId),
          )
        else
          DropdownButtonFormField<String>(
            key: ValueKey('closeout-v2-report-picker-$_selectedGroup'),
            initialValue: _selectedReportName,
            decoration: const InputDecoration(
              labelText: 'Report',
              border: OutlineInputBorder(),
            ),
            items: _reportNamesFor(_selectedGroup)
                .map(
                  (reportName) => DropdownMenuItem(
                    value: reportName,
                    child: Text(_friendlyReportName(reportName)),
                  ),
                )
                .toList(),
            onChanged: (reportName) => setState(() {
              _selectedReportName = reportName;
              _selectedExhibitorId = null;
              _selectedBreedName = null;
              _selectedClubName = null;
              _selectedShowLetter = null;
              _selectedScope = null;
            }),
          ),
        if (_needsExhibitor) ...[
          const SizedBox(height: 12),
          _metadataDropdown(
            label: 'Exhibitor',
            value: _selectedExhibitorId,
            values: _metadataValues('exhibitor_id'),
            display: (id) {
              final artifact = _selectedReportArtifacts.firstWhere(
                (a) => a.metadata['exhibitor_id']?.toString() == id,
              );
              return (artifact.metadata['exhibitor_name'] ?? id).toString();
            },
            onChanged: (value) => setState(() => _selectedExhibitorId = value),
          ),
        ],
        if (_needsBreed || _needsClub) ...[
          const SizedBox(height: 12),
          _metadataDropdown(
            label: 'Show Letter',
            value: _selectedShowLetter,
            values: _metadataValues('show_letter'),
            onChanged: (value) => setState(() => _selectedShowLetter = value),
          ),
          const SizedBox(height: 12),
          _metadataDropdown(
            label: _needsBreed ? 'Breed Name' : 'Club Name',
            value: _needsBreed ? _selectedBreedName : _selectedClubName,
            values: _metadataValues(_needsBreed ? 'breed_name' : 'club_name'),
            onChanged: (value) => setState(() {
              if (_needsBreed) {
                _selectedBreedName = value;
              } else {
                _selectedClubName = value;
              }
            }),
          ),
          const SizedBox(height: 12),
          _metadataDropdown(
            label: 'Scope',
            value: _selectedScope,
            values: _metadataValues(
              'scope',
            ).map((v) => v.toUpperCase()).toSet().toList(),
            onChanged: (value) => setState(() => _selectedScope = value),
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _additionalMessageController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Optional message from the show secretary',
            hintText: 'Add a note to include when emailing this report.',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        _SelectedReportStatus(
          artifact: _selectedArtifact,
          reportName: _selectedReportName,
          friendlyReportName: _friendlyReportName,
          downloading: _downloadingArtifactId == _selectedArtifact?.id,
          onDownload: _selectedArtifact?.artifactStatus == 'generated'
              ? () => _download(_selectedArtifact!)
              : null,
        ),
      ],
    ],
  );
}

class _SelectedReportStatus extends StatelessWidget {
  final ReportArtifactSummary? artifact;
  final String? reportName;
  final String Function(String reportName) friendlyReportName;
  final bool downloading;
  final VoidCallback? onDownload;

  const _SelectedReportStatus({
    required this.artifact,
    required this.reportName,
    required this.friendlyReportName,
    required this.downloading,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final selectedReportName = reportName;
    final status = closeoutReportStatusLabel(
      closeoutReportUiStatus(artifact?.artifactStatus),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            selectedReportName == null
                ? 'No report selected'
                : friendlyReportName(selectedReportName),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text('Status: $status'),
          if (artifact?.generatedAt?.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text('Generated: ${_formatGeneratedAt(artifact!.generatedAt!)}'),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: downloading ? null : onDownload,
            icon: downloading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
            label: const Text('Download'),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _disabledEmailButtons(selectedReportName),
          ),
        ],
      ),
    );
  }

  List<Widget> _disabledEmailButtons(String? reportName) {
    final labels = switch (reportName) {
      'arba_report' => const ['Email All to ARBA'],
      'exhibitor_report' => const [
        'Email Exhibitor Reports',
        'Email Exhibitor Reports & Legs',
      ],
      'legs' => const [
        'Email Exhibitor Legs',
        'Email Exhibitor Reports & Legs',
      ],
      'checkin_sheet' => const ['Email Check-In Sheet'],
      _ => const ['Email This Show', 'Email All Shows'],
    };
    return labels
        .map(
          (label) => Tooltip(
            message: 'Email is unavailable for this report.',
            child: OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.email_outlined),
              label: Text(label),
            ),
          ),
        )
        .toList();
  }

  String _formatGeneratedAt(String value) {
    final dateTime = DateTime.tryParse(value)?.toLocal();
    if (dateTime == null) return value;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final meridiem = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '${months[dateTime.month - 1]} ${dateTime.day}, ${dateTime.year} at $hour:$minute $meridiem';
  }
}
