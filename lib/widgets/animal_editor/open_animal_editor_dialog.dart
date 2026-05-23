// lib/widgets/animal_editor/open_animal_editor_dialog.dart

import 'package:flutter/material.dart';

import 'animal_editor_dialog.dart';

Future<bool?> openAnimalEditorDialog(
  BuildContext context, {
  Map<String, dynamic>? existing,
  String? showId,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => AnimalEditorDialog(
      existing: existing,
      showId: showId,
    ),
  );
}