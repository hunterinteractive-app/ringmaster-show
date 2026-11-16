import 'package:flutter/material.dart';
import '../services/ringmaster_backend.dart';
import '../theme/app_theme.dart';

const meatPenLaterInstructions =
    'After checkout, open My Entries, choose this show and exhibitor, find your Pen ID, '
    'then select Add tattoos. Enter all 3 tattoos and Save. You can update them later '
    'using the same Pen ID until the show’s entry deadline. '
    'The show secretary can also update them in Entry Management.';

bool hasMeatPenId(Map<String, dynamic> entry) =>
    (entry['meat_pen_id'] ?? '').toString().isNotEmpty;

List<String> meatPenTattoos(Map<String, dynamic> entry) =>
    (entry['meat_pen_tattoos'] as List? ?? const [])
        .map((v) => v.toString())
        .toList();

String meatPenTattooSummary(Map<String, dynamic> entry) {
  if (entry['meat_pen_tattoos'] == null) {
    return (entry['tattoo'] ?? '').toString();
  }
  final tattoos = meatPenTattoos(entry);
  return tattoos.isEmpty
      ? 'Tattoos not yet assigned'
      : 'Tattoos: ${tattoos.join(' / ')}';
}

String meatPenTattooAction(Map<String, dynamic> entry) =>
    meatPenTattoos(entry).isEmpty ? 'Add tattoos' : 'Update tattoos';

String? validateMeatPenTattoos(List<String> tattoos) {
  if (tattoos.length != 3 || tattoos.any((t) => t.trim().isEmpty)) {
    return 'Enter all 3 tattoos.';
  }
  if (tattoos.any((t) => t.length > 40 || t.contains(RegExp(r'[|/]')))) {
    return 'Use up to 40 characters per tattoo, without / or |.';
  }
  return null;
}

class MeatPenTattooFields extends StatelessWidget {
  const MeatPenTattooFields({
    super.key,
    required this.controllers,
    this.enabled = true,
  });
  final List<TextEditingController> controllers;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < 3; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextField(
            controller: controllers[i],
            enabled: enabled,
            textCapitalization: TextCapitalization.characters,
            maxLength: 40,
            decoration: InputDecoration(
              labelText: 'Tattoo ${i + 1}',
              counterText: '',
            ),
          ),
        ),
    ],
  );
}

Future<bool> showMeatPenTattooUpdate(
  BuildContext context,
  Map<String, dynamic> entry,
) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Theme(
        data: AppTheme.surfaceDialogTheme(Theme.of(dialogContext)),
        child: MeatPenTattooUpdateDialog(entry: entry),
      ),
    ) ??
    false;

class MeatPenTattooUpdateDialog extends StatefulWidget {
  const MeatPenTattooUpdateDialog({super.key, required this.entry});
  final Map<String, dynamic> entry;
  @override
  State<MeatPenTattooUpdateDialog> createState() =>
      _MeatPenTattooUpdateDialogState();
}

class _MeatPenTattooUpdateDialogState extends State<MeatPenTattooUpdateDialog> {
  late final List<TextEditingController> _controllers;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final values = meatPenTattoos(widget.entry);
    _controllers = List.generate(
      3,
      (i) => TextEditingController(text: i < values.length ? values[i] : ''),
    );
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final values = _controllers
        .map((c) => c.text.trim().toUpperCase())
        .toList();
    final error = validateMeatPenTattoos(values);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ringMasterClient.rpc(
        'update_meat_pen_tattoos',
        params: {'p_entry_id': widget.entry['id'], 'p_tattoos': values},
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is PostgrestException
              ? e.message
              : 'Could not save tattoos. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      '${meatPenTattooAction(widget.entry)} — ${widget.entry['meat_pen_id']}',
    ),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the actual tattoo for each rabbit. Your Pen ID and entry stay the same.',
            ),
            const SizedBox(height: 16),
            MeatPenTattooFields(controllers: _controllers, enabled: !_saving),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Save'),
      ),
    ],
  );
}
