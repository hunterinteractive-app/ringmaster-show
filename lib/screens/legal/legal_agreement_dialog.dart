import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'privacy_policy_screen.dart';
import 'terms_screen.dart';

class LegalAgreementDialog extends StatefulWidget {
  const LegalAgreementDialog({super.key});

  @override
  State<LegalAgreementDialog> createState() => _LegalAgreementDialogState();
}

class _LegalAgreementDialogState extends State<LegalAgreementDialog> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final bodyStyle = textTheme.bodyLarge?.copyWith(
      color: AppColors.text,
      height: 1.4,
    );

    return AppTheme.surfaceTextScope(
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
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const TermsScreen()),
                      ),
                      child: const Text('View Terms of Service'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.push(
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
                  onChanged: (value) =>
                      setState(() => _checked = value ?? false),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              disabledForegroundColor: AppColors.muted,
              disabledBackgroundColor: AppColors.neutralBadgeBg,
            ),
            onPressed: _checked ? () => Navigator.pop(context, true) : null,
            child: const Text('Agree & Continue'),
          ),
        ],
      ),
    );
  }
}
