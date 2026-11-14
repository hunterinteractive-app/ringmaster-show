import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/ringmaster_backend.dart';
import '../theme/app_theme.dart';

Future<bool> completeCartRegistrationRequirements(
  BuildContext context,
  String cartId,
) async {
  final data = Map<String, dynamic>.from(
    await ringMasterClient.rpc(
          'get_cart_registration_requirements',
          params: {'p_cart_id': cartId},
        )
        as Map,
  );
  if (!context.mounted) return false;
  if (data['required'] != true) return true;
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => Theme(
          data: AppTheme.surfaceDialogTheme(Theme.of(dialogContext)),
          child: CartRegistrationRequirementsDialog(
            requirements: data,
            save: (schools) async {
              await ringMasterClient.rpc(
                'save_cart_registration_requirements',
                params: {
                  'p_cart_id': cartId,
                  'p_version': data['version'],
                  'p_agreed': true,
                  'p_schools': schools,
                },
              );
            },
          ),
        ),
      ) ??
      false;
}

class CartRegistrationRequirementsDialog extends StatefulWidget {
  const CartRegistrationRequirementsDialog({
    super.key,
    required this.requirements,
    required this.save,
  });
  final Map<String, dynamic> requirements;
  final Future<void> Function(List<Map<String, dynamic>>) save;

  @override
  State<CartRegistrationRequirementsDialog> createState() =>
      _CartRegistrationRequirementsDialogState();
}

class _CartRegistrationRequirementsDialogState
    extends State<CartRegistrationRequirementsDialog> {
  final _form = GlobalKey<FormState>();
  late final List<Map<String, dynamic>> _schools =
      (widget.requirements['exhibitors'] as List? ?? [])
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
  bool _agreed = false;
  bool _saving = false;
  String? _error;

  Future<void> _continue() async {
    if (_saving || !_form.currentState!.validate()) return;
    _form.currentState!.save();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.save([
        for (final s in _schools)
          {
            'exhibitor_id': s['exhibitor_id'],
            'school_name': s['school_name'],
            'city': s['city'],
            'state': s['state'],
          },
      ]);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not save. Please try again. $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _open(String key) async {
    final uri = Uri.tryParse(widget.requirements[key]?.toString() ?? '');
    if (uri == null ||
        uri.scheme != 'https' ||
        !await launchUrl(uri, webOnlyWindowName: '_blank')) {
      if (mounted) {
        setState(() => _error = 'The link could not open. Please try again.');
      }
    }
  }

  Widget _field(
    Map<String, dynamic> school,
    String key,
    String label,
    int max,
  ) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextFormField(
      key: ValueKey('${school['exhibitor_id']}-$key'),
      initialValue: school[key]?.toString() ?? (key == 'state' ? 'TX' : ''),
      enabled: !_saving,
      maxLength: max,
      textCapitalization: key == 'state'
          ? TextCapitalization.characters
          : TextCapitalization.words,
      inputFormatters: key == 'state'
          ? [FilteringTextInputFormatter.allow(RegExp('[a-zA-Z]'))]
          : null,
      decoration: InputDecoration(labelText: '$label *', counterText: ''),
      validator: (v) {
        if ((v ?? '').trim().isEmpty) return '$label is required.';
        if (key == 'state' && !RegExp(r'^[A-Za-z]{2}$').hasMatch(v!.trim())) {
          return 'Enter the two-letter state.';
        }
        return null;
      },
      onSaved: (v) =>
          school[key] = key == 'state' ? v!.trim().toUpperCase() : v!.trim(),
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('Before checkout'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_schools.isNotEmpty)
                  const Text(
                    'Houston requires school information for each youth exhibitor.',
                  ),
                for (final school in _schools) ...[
                  const SizedBox(height: 18),
                  Text(
                    '${school['name']} • Exhibitor #${school['number']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  _field(school, 'school_name', 'School name', 200),
                  _field(school, 'city', 'School city', 120),
                  _field(school, 'state', 'School state', 2),
                ],
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  children: [
                    TextButton.icon(
                      onPressed: () => _open('handbook_url'),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Read the Exhibitor Handbook'),
                    ),
                    TextButton.icon(
                      onPressed: () => _open('website_url'),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Houston website and terms'),
                    ),
                  ],
                ),
                FormField<bool>(
                  initialValue: false,
                  validator: (_) =>
                      _agreed ? null : 'Agreement is required before checkout.',
                  builder: (field) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _agreed,
                        onChanged: _saving
                            ? null
                            : (v) {
                                setState(() => _agreed = v ?? false);
                                field.didChange(_agreed);
                              },
                        title: Text(widget.requirements['agreement'] as String),
                      ),
                      if (field.hasError)
                        Text(
                          field.errorText!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
                if (_error != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Back to cart'),
        ),
        FilledButton(
          onPressed: _saving ? null : _continue,
          child: Text(_saving ? 'Saving…' : 'Continue to checkout'),
        ),
      ],
    ),
  );
}
