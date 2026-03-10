// lib/screens/admin/admin_show_reports_screen.dart
import 'package:flutter/material.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: Text('Breed Counts — ${widget.showName}'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                const Text('Include scratched'),
                const SizedBox(width: 8),
                Switch(
                  value: _includeScratched,
                  onChanged: (v) => setState(() => _includeScratched = v),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: EntriesByBreedSectionTable(
              showId: widget.showId,
              showName: widget.showName,
              includeScratched: _includeScratched,
            ),
          ),
        ],
      ),
    );
  }
}