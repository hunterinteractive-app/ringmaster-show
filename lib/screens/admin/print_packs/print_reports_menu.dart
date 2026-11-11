import 'package:flutter/material.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import '../closeout/data/loaders/exhibitor_mailing_labels_loader.dart';
import 'print_reports_service.dart';

/// Compact banner action; report generation stays separate from control sheets.
class PrintReportsMenu extends StatefulWidget {
  const PrintReportsMenu({
    super.key,
    required this.load,
    required this.download,
  });
  final Future<PrintReportAvailability> Function() load;
  final Future<void> Function(PrintReport, MailingLabelMode, MailingLabelSort)
  download;

  @override
  State<PrintReportsMenu> createState() => _PrintReportsMenuState();
}

class _PrintReportsMenuState extends State<PrintReportsMenu> {
  PrintReportAvailability _available = const PrintReportAvailability();
  bool _loading = true, _building = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    PrintReportAvailability result;
    try {
      result = await widget.load();
    } catch (_) {
      result = const PrintReportAvailability(errors: ['Reports']);
    }
    if (mounted) {
      setState(() {
        _available = result;
        _loading = false;
      });
    }
  }

  Future<void> _select(String value) async {
    if (value == 'refresh') {
      await _load();
      return;
    }
    final report = PrintReport.values.byName(value);
    var mode = MailingLabelMode.address;
    var sort = MailingLabelSort.lastName;
    if (report == PrintReport.labels) {
      mode = _available.labelModes.first;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => Theme(
          data: AppTheme.surfaceDialogTheme(Theme.of(dialogContext)),
          child: StatefulBuilder(
            builder: (context, update) => AlertDialog(
              title: const Text('Exhibitor Labels'),
              content: SizedBox(
                width: 320,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Avery 5160 / 8160 labels for entered exhibitors.',
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<MailingLabelMode>(
                        initialValue: mode,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Label contents',
                        ),
                        items: [
                          for (final option in MailingLabelMode.values)
                            if (_available.labelModes.contains(option))
                              DropdownMenuItem(
                                value: option,
                                child: Text(
                                  option == MailingLabelMode.address
                                      ? 'Mailing address'
                                      : 'Exhibitor number',
                                ),
                              ),
                        ],
                        onChanged: (v) => update(() => mode = v!),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<MailingLabelSort>(
                        initialValue: sort,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Sort by'),
                        items: const [
                          DropdownMenuItem(
                            value: MailingLabelSort.lastName,
                            child: Text('Last name'),
                          ),
                          DropdownMenuItem(
                            value: MailingLabelSort.exhibitorNumber,
                            child: Text('Exhibitor number'),
                          ),
                        ],
                        onChanged: (v) => update(() => sort = v!),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Exhibitors missing the required label details are omitted.',
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Download PDF'),
                ),
              ],
            ),
          ),
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _building = true);
    try {
      await widget.download(report, mode, sort);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to download ${report.label}: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _building = false);
        await _load();
      }
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: AppTheme.menuFocusTheme(Theme.of(context)),
    child: PopupMenuButton<String>(
      tooltip: _building ? 'Generating report' : 'Download reports',
      enabled: !_loading && !_building,
      color: AppColors.surface,
      onSelected: _select,
      itemBuilder: (_) => [
        for (final report in PrintReport.values)
          if (_available.reports.contains(report))
            PopupMenuItem(
              value: report.name,
              child: Text(
                report.label,
                style: const TextStyle(color: AppColors.text),
              ),
            ),
        if (_available.reports.isEmpty && _available.errors.isEmpty)
          const PopupMenuItem(
            enabled: false,
            child: Text(
              'No report data available yet',
              style: TextStyle(color: AppColors.muted),
            ),
          ),
        if (_available.errors.isNotEmpty)
          PopupMenuItem(
            enabled: false,
            child: Text(
              'Could not check: ${_available.errors.join(', ')}',
              style: const TextStyle(color: AppColors.text),
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'refresh',
          child: Text(
            'Refresh report list',
            style: TextStyle(color: AppColors.text),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_loading || _building)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.headerText,
                ),
              )
            else
              const Icon(
                Icons.description_outlined,
                color: AppColors.headerText,
                size: 20,
              ),
            const SizedBox(width: 4),
            Text(
              _building ? 'Preparing…' : 'Reports',
              style: const TextStyle(
                color: AppColors.headerText,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Icon(
              Icons.arrow_drop_down,
              color: AppColors.headerText,
              size: 20,
            ),
          ],
        ),
      ),
    ),
  );
}
