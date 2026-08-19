import 'package:flutter/material.dart';
import 'package:ringmaster_show/screens/admin/results/admin_results_entry_screen.dart';

Future<void> openResultsEntryFix(
  BuildContext context, {
  required String showId,
  required String showName,
  required String entryId,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AdminResultsEntryScreen(
        showId: showId,
        showName: showName,
        initialEntryId: entryId,
      ),
    ),
  );
}
