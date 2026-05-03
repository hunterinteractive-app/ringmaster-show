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
                        Text('RingMaster Show – Privacy Policy', style: titleStyle),
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
                              '• Display name and profile information\n'
                              '• Show-related data (entries, exhibitors, animals, results)\n'
                              '• Device, browser, and usage data\n'
                              '• Payment or transaction-related information if paid features are used',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '2. How We Use Information',
                          'We use data to:\n'
                              '• Operate the platform\n'
                              '• Manage shows, entries, judging workflows, and results\n'
                              '• Create and maintain user accounts\n'
                              '• Improve performance, reliability, and user experience\n'
                              '• Maintain security and prevent misuse\n'
                              '• Communicate important service updates or account-related notices',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '3. Data Responsibility',
                          'Users, clubs, secretaries, judges, exhibitors, and writers are responsible for the data they enter, submit, review, or manage within the platform.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '4. Data Sharing',
                          'We do not sell user data.\n\n'
                              'Data may be shared:\n'
                              '• With authorized show participants and officials, such as secretaries, judges, writers, exhibitors, and show administrators\n'
                              '• With service providers needed to operate the platform, such as hosting, authentication, email, payment, storage, analytics, or support providers\n'
                              '• When required by law, court order, legal process, or governmental request\n'
                              '• When necessary to protect the rights, safety, security, or integrity of RingMaster Show, its users, or the public',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '5. Data Storage & Retention',
                          'Data is stored securely and may be retained for operational, historical, reporting, audit, and legal purposes.\n\n'
                              'Show data may be retained for a limited time, such as up to one (1) year, unless a longer retention period is required or reasonably necessary.\n\n'
                              'Certain records, including finalized results, reports, show history, audit logs, and records needed to preserve the integrity of an event, may be retained even if an account deletion request is made.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '6. Security',
                          'We take reasonable steps to protect data, including use of secured hosting, authentication controls, and access restrictions. However, no method of transmission or electronic storage is completely secure, and we cannot guarantee absolute security.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '7. Your Rights',
                          'You may request access to, correction of, or deletion of your account data where applicable.\n\n'
                              'Please note that some show-related records may be retained when needed to preserve official results, reports, competition history, legal obligations, dispute resolution, security, or system integrity.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '8. Children’s Privacy',
                          'RingMaster Show is not intended for users under the age of 13. We do not knowingly collect personal information from children under 13. If we become aware that such information has been collected, we will take reasonable steps to remove it.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '9. Third-Party Services',
                          'RingMaster Show may use third-party services for hosting, authentication, payments, email delivery, analytics, storage, or other operational needs. These providers may process limited information only as needed to provide their services.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '10. Changes to Policy',
                          'This policy may be updated at any time as the platform evolves. When material changes are made, users may be required to review and accept the updated Privacy Policy before continuing to use the platform.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '11. Contact',
                          'For privacy-related questions, requests, or concerns, please contact RingMaster Show support.',
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