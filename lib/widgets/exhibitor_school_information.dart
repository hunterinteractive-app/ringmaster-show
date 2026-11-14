import 'package:flutter/material.dart';
import 'package:ringmaster_show/services/ringmaster_backend.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

/// Show-specific school details, read only by authorized entry-management staff.
class ExhibitorSchoolInformation extends StatefulWidget {
  const ExhibitorSchoolInformation({
    super.key,
    required this.showId,
    required this.exhibitorId,
    this.loader,
  });

  final String showId;
  final String exhibitorId;
  final Future<Map<String, dynamic>> Function()? loader;

  @override
  State<ExhibitorSchoolInformation> createState() =>
      _ExhibitorSchoolInformationState();
}

class _ExhibitorSchoolInformationState
    extends State<ExhibitorSchoolInformation> {
  late Future<Map<String, dynamic>> _information;

  Future<Map<String, dynamic>> _load() async {
    if (widget.loader != null) return widget.loader!();
    final result = await ringMasterClient.rpc(
      'get_exhibitor_school_for_show',
      params: {
        'p_show_id': widget.showId,
        'p_exhibitor_id': widget.exhibitorId,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  @override
  void initState() {
    super.initState();
    _information = _load();
  }

  @override
  void didUpdateWidget(covariant ExhibitorSchoolInformation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showId != widget.showId ||
        oldWidget.exhibitorId != widget.exhibitorId) {
      _information = _load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _information,
    builder: (context, snapshot) {
      final done = snapshot.connectionState == ConnectionState.done;
      final data = done ? snapshot.data : null;
      if (done && !snapshot.hasError && data?['applicable'] != true) {
        return const SizedBox.shrink();
      }
      final school = data?['school'];
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: AppTheme.surfaceTextScope(
          context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'School Information',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
              const SizedBox(height: 8),
              if (!done)
                const Text('Loading school information…')
              else if (snapshot.hasError) ...[
                const Text('School information could not be loaded.'),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() {
                      _information = _load();
                    }),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ),
              ] else if (school is Map) ...[
                for (final field in const {
                  'school_name': 'School name',
                  'city': 'School city',
                  'state': 'School state',
                }.entries) ...[
                  Text(
                    field.value,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  SelectableText(
                    (school[field.key] ?? '').toString(),
                    style: const TextStyle(color: AppColors.text),
                  ),
                  const SizedBox(height: 8),
                ],
              ] else
                const Text(
                  'School information has not been provided for this show.',
                ),
            ],
          ),
        ),
      );
    },
  );
}
