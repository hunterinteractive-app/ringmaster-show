// lib/screens/legal/terms_screen.dart

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/rm_widgets.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

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
      appBar: AppBar(title: const Text('Terms of Service')),
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
                        Text('RingMaster Show – Terms of Service', style: titleStyle),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Effective Date: May 2026 (v2026-05)',
                          style: bodyStyle?.copyWith(color: AppColors.muted),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'By creating an account or using RingMaster Show, you agree to the following:',
                          style: bodyStyle,
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        _section(
                          '1. Use of Platform',
                          'RingMaster Show provides tools for managing animal shows, including entries, judging workflows, reporting, and related show management services.\n\n'
                              'You agree to use the platform only for lawful and intended show management purposes.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '2. Eligibility',
                          'You must be at least 13 years old to use RingMaster Show. By using the platform, you represent that you meet this requirement.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '3. User Accounts & Security',
                          'You are responsible for maintaining the confidentiality of your account and login access.\n\n'
                              'You agree not to share your account access with others and to notify RingMaster Show support if you believe your account has been accessed without authorization.\n\n'
                              'RingMaster Show is not responsible for actions taken under your account.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '4. Data Accuracy & User Responsibility',
                          'All users, including secretaries, judges, exhibitors, and writers, are solely responsible for the accuracy and completeness of any data entered, submitted, reviewed, imported, or managed within the system.\n\n'
                              'This includes:\n'
                              '• Manual entries\n'
                              '• QR Code submissions\n'
                              '• Imported or edited results\n'
                              '• System-generated or modified data\n'
                              '• Exhibitor, animal, class, payment, and reporting information\n\n'
                              'RingMaster Show does not guarantee the accuracy, completeness, or validity of submitted data.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '5. QR Code Entry Disclaimer',
                          'QR Code features are provided to assist with faster and more efficient data entry.\n\n'
                              'By using QR Code entry:\n'
                              '• You acknowledge entries may be submitted from external or personal devices\n'
                              '• You understand QR Code submissions may require review before being treated as final\n'
                              '• You agree all QR-submitted results must be reviewed before finalization\n'
                              '• You accept responsibility for verifying correctness and completeness',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '6. Finalization of Results',
                          'When a show is finalized:\n'
                              '• Results are considered locked and official within the system\n'
                              '• Further edits may be restricted or prevented\n'
                              '• The user performing finalization confirms that all data, including QR Code submissions, has been reviewed and verified\n\n'
                              'RingMaster Show is not responsible for errors that were not identified and corrected prior to finalization.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '7. Acceptable Use',
                          'You agree not to:\n'
                              '• Use the platform in a way that disrupts or interferes with shows or other users\n'
                              '• Attempt unauthorized access to accounts, data, systems, or restricted areas\n'
                              '• Submit false, misleading, abusive, or unlawful information intentionally\n'
                              '• Introduce harmful code, abuse system features, or interfere with platform security\n'
                              '• Use RingMaster Show for any purpose outside intended show management use',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '8. Payments & Fees',
                          'Certain features, services, show access, or platform tools may require payment.\n\n'
                              'Unless otherwise stated, fees are non-refundable. RingMaster Show may, at its discretion, issue credits or refunds on a case-by-case basis.\n\n'
                              'We reserve the right to establish, modify, or discontinue pricing, fees, features, or service plans at any time.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '9. Data Storage & Retention',
                          'Show, account, exhibitor, animal, result, report, and related data may be stored for operational, historical, reporting, audit, and legal purposes.\n\n'
                              'Show data may be retained for a limited time, such as up to one (1) year, unless a longer retention period is required or reasonably necessary.\n\n'
                              'Certain records, including finalized results, reports, audit logs, and event history, may be retained to preserve the integrity of shows and records.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '10. Service Availability',
                          'We aim to provide reliable service, but RingMaster Show does not guarantee uninterrupted, error-free, or continuously available operation.\n\n'
                              'We may modify, suspend, restrict, or discontinue portions of the platform at any time as needed for maintenance, security, improvements, or business reasons.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '11. Intellectual Property',
                          'RingMaster Show, including its name, design, software, features, workflows, reports, branding, and related materials, is owned by RingMaster Show or its licensors.\n\n'
                              'You may not copy, reproduce, modify, distribute, reverse engineer, or create derivative works from the platform except as expressly permitted.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '12. Third-Party Services',
                          'RingMaster Show may rely on third-party providers for hosting, authentication, payments, email, storage, analytics, or other operational services.\n\n'
                              'We are not responsible for third-party services, websites, outages, terms, policies, or actions outside our control.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '13. Disclaimer of Warranties',
                          'RingMaster Show is provided “as is” and “as available,” without warranties of any kind, express or implied.\n\n'
                              'We do not warrant that the platform will be accurate, reliable, uninterrupted, error-free, secure, or meet every user expectation.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '14. Limitation of Liability',
                          'To the fullest extent permitted by law, RingMaster Show is not liable for:\n'
                              '• Data entry errors or omissions\n'
                              '• Missed placements or incorrect results\n'
                              '• Loss of awards, standings, reports, or records\n'
                              '• Operational delays or disruptions\n'
                              '• Loss of data, revenue, business, goodwill, or opportunity\n'
                              '• Indirect, incidental, special, consequential, or punitive damages',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '15. Governing Law',
                          'These Terms are governed by the laws of the State of Indiana, without regard to conflict of law principles.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '16. Changes to Terms',
                          'These Terms may be updated at any time as the platform evolves. When material changes are made, users may be required to review and accept the updated Terms before continuing to use the platform.\n\n'
                              'Continued use of RingMaster Show constitutes acceptance of the current Terms.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '17. Contact',
                          'For questions, concerns, support requests, or notices regarding these Terms, please contact RingMaster Show support.',
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