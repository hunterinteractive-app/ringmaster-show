import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'privacy_policy_screen.dart';
import 'terms_screen.dart';

class LegalAgreementDialog extends StatefulWidget {
  const LegalAgreementDialog({super.key, this.onAccept});
  final Future<void> Function()? onAccept;

  @override
  State<LegalAgreementDialog> createState() => _LegalAgreementDialogState();
}

class _LegalAgreementDialogState extends State<LegalAgreementDialog> {
  bool _checked = false;
  bool _saving = false;
  String? _error;

  Future<void> _accept() async {
    if (!_checked || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onAccept?.call();
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Your agreement could not be saved. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final bodyStyle = textTheme.bodyLarge?.copyWith(
      color: AppColors.text,
      height: 1.4,
    );

    return PopScope(
      canPop: !_saving,
      child: AppTheme.surfaceTextScope(
        context,
        child: AlertDialog(
          backgroundColor: AppColors.surface,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: textTheme.titleLarge?.copyWith(
            color: AppColors.text,
            fontWeight: FontWeight.w800,
          ),
          contentTextStyle: bodyStyle,
          title: const Text('Terms & Privacy Agreement'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Our Terms of Service or Privacy Policy have changed. '
                    'Please review and agree before continuing.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: [
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const TermsScreen(),
                                ),
                              ),
                        child: const Text('View Terms of Service'),
                      ),
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const PrivacyPolicyScreen(),
                                ),
                              ),
                        child: const Text('View Privacy Policy'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  CheckboxListTile(
                    value: _checked,
                    controlAffinity: ListTileControlAffinity.leading,
                    titleAlignment: ListTileTitleAlignment.top,
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppColors.secondaryButton,
                    checkColor: AppColors.headerForeground,
                    side: const BorderSide(color: AppColors.text, width: 2),
                    title: Text(
                      'I have reviewed and agree to the current Terms of Service and Privacy Policy.',
                      style: bodyStyle,
                    ),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _checked = value ?? false),
                  ),
                  if (_error != null)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ),
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
              style: FilledButton.styleFrom(
                disabledForegroundColor: AppColors.muted,
                disabledBackgroundColor: AppColors.neutralBadgeBg,
              ),
              onPressed: _checked && !_saving ? _accept : null,
              child: Text(_saving ? 'Saving agreement…' : 'Agree & Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
