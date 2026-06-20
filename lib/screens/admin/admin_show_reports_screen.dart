// lib/screens/admin/admin_show_reports_screen.dart
import 'package:flutter/material.dart';
import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';
import 'package:ringmaster_show/services/app_session.dart';

import 'entries_by_breed_section_table.dart';

class AdminShowReportsScreen extends StatefulWidget {
  final String showId;
  final String showName;

  const AdminShowReportsScreen({
    super.key,
    required this.showId,
    required this.showName,
  });

  @override
  State<AdminShowReportsScreen> createState() => _AdminShowReportsScreenState();
}

class _AdminShowReportsScreenState extends State<AdminShowReportsScreen> {
  bool _includeScratched = false;

  @override
  Widget build(BuildContext context) {
    return RingMasterPageShell(
      title: 'RingMaster Show',
      subtitle: 'Breed Counts — ${widget.showName}',
      showBackButton: true,
      showHomeButton: true,
      useScrollView: false,
      bodyPadding: EdgeInsets.zero,
      actions: [
        IconButton(
          tooltip: 'Reload',
          icon: const Icon(Icons.refresh),
          onPressed: () => setState(() {}),
        ),
      ],
      body: Column(
        children: [
          if (AppSession.isSupportMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.support_agent, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Support Mode — Viewing breed count reports as an admin while viewing another user.',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .05),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Report Options',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Toggle whether scratched entries should be included in breed count totals.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Include scratched',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Switch(
                        value: _includeScratched,
                        onChanged: (v) =>
                            setState(() => _includeScratched = v),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .05),
                      blurRadius: 12,
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: EntriesByBreedSectionTable(
                  showId: widget.showId,
                  showName: widget.showName,
                  includeScratched: _includeScratched,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}