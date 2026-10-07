import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/show_addon_report_service.dart';
import '../utils/csv_exporter.dart';
import '../utils/file_download.dart';

class ShowAddonReportDownloads extends StatefulWidget {
  const ShowAddonReportDownloads({
    super.key,
    required this.showId,
    required this.showName,
    required this.reportName,
    this.service,
  });
  final String showId, showName, reportName;
  final ShowAddonReportService? service;
  @override
  State<ShowAddonReportDownloads> createState() =>
      _ShowAddonReportDownloadsState();
}

class _ShowAddonReportDownloadsState extends State<ShowAddonReportDownloads> {
  String? _format, _error;
  Future<void> _download(bool csv) async {
    if (_format != null) return;
    setState(() {
      _format = csv ? 'CSV' : 'PDF';
      _error = null;
    });
    try {
      final file = await (widget.service ?? ShowAddonReportService()).build(
        showId: widget.showId,
        showName: widget.showName,
        reportName: widget.reportName,
        asCsv: csv,
      );
      if (csv) {
        await exportCsvBytes(bytes: file.bytes, suggestedName: file.fileName);
      } else {
        await downloadFileBytes(
          Uint8List.fromList(file.bytes),
          fileName: file.fileName,
          mimeType: file.mimeType,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Unable to generate this report: $e');
      }
    } finally {
      if (mounted) setState(() => _format = null);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
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
          ShowAddonReportService.title(widget.reportName),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Available at any time. Each download generates a current report for the entire show.',
        ),
        const SizedBox(height: 8),
        Text(
          widget.reportName == ShowAddonReportService.purchases
              ? 'Includes submitted add-on orders, quantities, exhibitor names and numbers, emails, amounts, and payment status. Items still in carts are excluded.'
              : 'Includes submitted contest registrations, exhibitors, divisions, teams or projects, animal choices, check-in, approval, and payment status. Drafts are excluded.',
        ),
        const SizedBox(height: 12),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final csv in [false, true])
              OutlinedButton.icon(
                key: ValueKey(
                  csv
                      ? 'other-reports-download-csv'
                      : 'other-reports-download-pdf',
                ),
                onPressed: _format != null ? null : () => _download(csv),
                icon: _format == (csv ? 'CSV' : 'PDF')
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        csv
                            ? Icons.table_view_outlined
                            : Icons.download_outlined,
                      ),
                label: Text(
                  _format == (csv ? 'CSV' : 'PDF')
                      ? 'Preparing $_format…'
                      : 'Download ${csv ? 'CSV' : 'PDF'}',
                ),
              ),
          ],
        ),
      ],
    ),
  );
}
