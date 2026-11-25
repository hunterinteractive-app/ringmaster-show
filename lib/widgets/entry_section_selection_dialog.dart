import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/entry_section_service.dart';

Future<List<String>?> chooseEntrySections(
  BuildContext context, {
  required Map<String, dynamic> entry,
  required String action,
}) async {
  final sections = await EntrySectionService.sectionsFor(entry);
  if (!context.mounted) return null;
  return showDialog<List<String>>(
    context: context,
    builder: (context) => Theme(
      data: AppTheme.surfaceDialogTheme(Theme.of(context)),
      child: EntrySectionSelectionDialog(
        sections: sections,
        currentSectionId: entry['section_id'].toString(),
        action: action,
      ),
    ),
  );
}

class EntrySectionSelectionDialog extends StatefulWidget {
  const EntrySectionSelectionDialog({
    super.key,
    required this.sections,
    required this.currentSectionId,
    required this.action,
  });
  final List<Map<String, dynamic>> sections;
  final String currentSectionId, action;
  @override
  State<EntrySectionSelectionDialog> createState() => _SelectionState();
}

class _SelectionState extends State<EntrySectionSelectionDialog> {
  late final Set<String> selected = {
    if (widget.sections.any((s) => s['id'] == widget.currentSectionId))
      widget.currentSectionId,
  };
  String label(Map<String, dynamic> section) {
    final display = (section['display_name'] ?? '').toString().trim();
    if (display.isNotEmpty) return display;
    final kind = (section['kind'] ?? 'Show').toString();
    if (kind.isEmpty) return 'Show ${section['letter'] ?? ''}';
    return '${kind[0].toUpperCase()}${kind.substring(1)} ${section['letter']}';
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.action} across sections'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose the show sections for this animal and exhibitor. Class and fur entries in the selected sections are included.',
            ),
            if (widget.action == 'Scratch') ...[
              const SizedBox(height: 12),
              const Text(
                'Unpaid entry fees scratched before the deadline are removed from the balance. Paid entries are not automatically refunded.',
              ),
            ],
            TextButton(
              onPressed: () => setState(() {
                if (selected.length == widget.sections.length) {
                  selected.clear();
                  if (widget.action == 'Apply edits') {
                    selected.add(widget.currentSectionId);
                  }
                } else {
                  selected.addAll(
                    widget.sections.map((s) => s['id'].toString()),
                  );
                }
              }),
              child: Text(
                selected.length == widget.sections.length
                    ? 'Clear selection'
                    : 'Select all sections',
              ),
            ),
            for (final section in widget.sections)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  label(section),
                  style: const TextStyle(color: AppColors.text),
                ),
                subtitle: Text(
                  '${section['entry_count']} entries',
                  style: const TextStyle(color: AppColors.muted),
                ),
                value: selected.contains(section['id']),
                onChanged:
                    widget.action == 'Apply edits' &&
                        section['id'] == widget.currentSectionId
                    ? null
                    : (value) => setState(() {
                        if (value == true) {
                          selected.add(section['id'].toString());
                        } else {
                          selected.remove(section['id']);
                        }
                      }),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: selected.isEmpty
            ? null
            : () => Navigator.pop(context, selected.toList()),
        child: Text(
          '${widget.action} ${selected.length} ${selected.length == 1 ? 'section' : 'sections'}',
        ),
      ),
    ],
  );
}

/// A light control surface remains readable inside the purple entry sheet.
Widget buildAdminEntrySectionChoice(
  BuildContext context, {
  required bool value,
  required ValueChanged<bool?>? onChanged,
}) => AppTheme.surfaceTextScope(
  context,
  child: Material(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(AppRadius.sm),
    child: CheckboxListTile(
      title: const Text('Choose show sections for these edits'),
      subtitle: const Text(
        'Choose Open A, Open B, Youth A, etc. Fur/Wool choices stay with their individual show entries.',
      ),
      value: value,
      onChanged: onChanged,
    ),
  ),
);
