import 'package:flutter/material.dart';
import '../utils/household_eligibility.dart';

class HouseholdExhibitorInviteRow extends StatefulWidget {
  final Map<String, dynamic> exhibitor;
  final bool enabled;
  final Future<String> Function(String email) onSave;
  const HouseholdExhibitorInviteRow({
    super.key,
    required this.exhibitor,
    required this.enabled,
    required this.onSave,
  });
  @override
  State<HouseholdExhibitorInviteRow> createState() =>
      _HouseholdExhibitorInviteRowState();
}

class _HouseholdExhibitorInviteRowState
    extends State<HouseholdExhibitorInviteRow> {
  late final TextEditingController _email;
  bool _saving = false;
  String? _message;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _email = TextEditingController(
      text: (widget.exhibitor['email'] ?? '').toString(),
    );
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final email = _email.text.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email) ||
        email.length > 254) {
      setState(() {
        _failed = true;
        _message = 'Enter a valid email address.';
      });
      return;
    }
    setState(() {
      _saving = true;
      _message = null;
      _failed = false;
    });
    try {
      final message = await widget.onSave(email);
      if (mounted) setState(() => _message = message);
    } catch (e) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.exhibitor;
    final showing = (e['showing_name'] ?? '').toString().trim();
    final name = showing.isEmpty
        ? (e['display_name'] ?? 'Exhibitor').toString()
        : showing;
    final eligible = canInviteHouseholdExhibitor(
      (e['type'] ?? '').toString(),
      DateTime.tryParse((e['birth_date'] ?? '').toString()),
    );
    final nameWidget = Text(
      name,
      style: const TextStyle(
        color: Colors.black87,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    );
    final emailWidget = TextField(
      controller: _email,
      enabled: widget.enabled && !_saving && eligible,
      style: const TextStyle(color: Colors.black87),
      keyboardType: TextInputType.emailAddress,
      decoration: const InputDecoration(
        labelText: 'Login email',
        border: OutlineInputBorder(),
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth < 480
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        nameWidget,
                        const SizedBox(height: 12),
                        emailWidget,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: nameWidget),
                        const SizedBox(width: 20),
                        Expanded(flex: 2, child: emailWidget),
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            if (eligible)
              FilledButton(
                onPressed: widget.enabled && !_saving ? _save : null,
                child: Text(_saving ? 'Saving and sending…' : 'Save and Send'),
              )
            else
              Text(
                (e['type'] ?? '') == 'group'
                    ? 'Group exhibitors do not have a separate login.'
                    : 'Youth need a recorded birth date and must be 14 or older for their own login.',
                style: const TextStyle(color: Colors.black87),
              ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _message!,
                  style: TextStyle(
                    color: _failed
                        ? Colors.red.shade800
                        : Colors.green.shade800,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
