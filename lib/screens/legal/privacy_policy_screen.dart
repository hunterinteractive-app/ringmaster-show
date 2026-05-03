// lib/screens/legal/privacy_policy_screen.dart

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/rm_widgets.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleLarge;
    final sectionStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        );
    final bodyStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          height: 1.6,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: RMCard(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RingMaster Show – Privacy Policy',
                          style: titleStyle,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Effective Date: May 2026 (v2026-05)',
                          style: bodyStyle?.copyWith(color: AppColors.muted),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'RingMaster Show respects your privacy and is committed to protecting your information.',
                          style: bodyStyle,
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        _section(
                          '1. Information We Collect',
                          'We may collect:\n'
                              '• Name and contact information\n'
                              '• Account credentials\n'
                              '• Show-related data (entries, exhibitors, animals, results)\n'
                              '• Device and usage data',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '2. How We Use Information',
                          'We use data to:\n'
                              '• Operate the platform\n'
                              '• Manage shows and results\n'
                              '• Improve performance and reliability\n'
                              '• Maintain security',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '3. Data Responsibility',
                          'Users (clubs, secretaries, etc.) are responsible for the data they enter and manage.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '4. Data Sharing',
                          'We do not sell user data.\n\n'
                              'Data may be shared:\n'
                              '• With authorized show participants (e.g., secretaries, judges)\n'
                              '• When required by law\n'
                              '• With service providers needed to operate the platform',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '5. Data Storage & Retention',
                          'Data is stored securely and may be retained for operational purposes.\n\n'
                              'Show data may be retained for a limited time (e.g., up to 1 year).',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '6. Security',
                          'We take reasonable steps to protect data but cannot guarantee absolute security.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '7. Your Rights',
                          'You may request access to or deletion of your account data where applicable.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '8. Changes to Policy',
                          'This policy may be updated at any time. Continued use constitutes acceptance of changes.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '9. Contact',
                          'For questions, please contact RingMaster Show support.',
                          sectionStyle,
                          bodyStyle,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(
    String title,
    String body,
    TextStyle? titleStyle,
    TextStyle? bodyStyle,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: titleStyle),
          const SizedBox(height: AppSpacing.xs),
          Text(body, style: bodyStyle),
        ],
      ),
    );
  }
}