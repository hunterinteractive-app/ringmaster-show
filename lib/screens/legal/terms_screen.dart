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
                          'Effective Date: September 2026 (v2026-09)',
                          style: bodyStyle?.copyWith(color: AppColors.muted),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'RingMaster Show is provided by Hunter Interactive LLC, doing business as RingMaster One (“Company,” “we,” “us,” or “our”). RingMaster Show is the platform covered by these Terms of Service (“Terms”).\n\n'
                              'By creating an account or using RingMaster Show, you agree to these Terms with Hunter Interactive LLC:',
                          style: bodyStyle,
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        _section(
                          '1. Use of Platform',
                          'Through RingMaster Show, the Company provides tools for managing animal shows, including entries, judging workflows, reporting, and related show management services.\n\n'
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
                              'You agree not to share your account access with others and to notify our RingMaster Show support team if you believe your account has been accessed without authorization.\n\n'
                              'The Company is not responsible for actions taken under your account.',
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
                              'The Company does not guarantee the accuracy, completeness, or validity of submitted data.',
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
                              'The Company is not responsible for errors that were not identified and corrected prior to finalization.',
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
                              'Unless otherwise stated, fees are non-refundable. The Company may, at its discretion, issue credits or refunds on a case-by-case basis.\n\n'
                              'We reserve the right to establish, modify, or discontinue pricing, fees, features, or service plans at any time.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '9. Data Storage & Retention',
                          'Show, account, exhibitor, animal, result, report, and related information may be retained for the purposes and periods described in the Privacy Policy. Our general retention target for show data, including finalized results and reports, is up to two (2) years after the show ends, subject to applicable law and the limited retention extensions described in that policy. This target does not guarantee continuous availability throughout that period.\n\n'
                              'ARBA Official Show Rules, Section 36(B), require the show sponsor to retain official show records for at least one (1) year. Clubs and show sponsors remain responsible for meeting that requirement and any other applicable recordkeeping obligations. Authorized club representatives can download available show data and reports and should retain their own copies.\n\n'
                              'Account deletion requests and any retention of associated official show records are addressed in the Privacy Policy and under applicable law.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '10. Service Availability',
                          'We aim to provide reliable service, but we do not guarantee uninterrupted, error-free, or continuously available operation.\n\n'
                              'We may modify, suspend, restrict, or discontinue portions of the platform at any time as needed for maintenance, security, improvements, or business reasons.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '11. Intellectual Property',
                          'RingMaster Show, including its name, design, software, features, workflows, reports, branding, and related materials, is owned by Hunter Interactive LLC or its licensors.\n\n'
                              'You may not copy, reproduce, modify, distribute, reverse engineer, or create derivative works from the platform except as expressly permitted.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '12. Third-Party Services',
                          'We may rely on third-party providers for hosting, authentication, payments, email, storage, analytics, or other operational services.\n\n'
                              'We are not responsible for third-party services, websites, outages, terms, policies, or actions outside our control.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '13. Disclaimer of Warranties',
                          'RingMaster Show is provided by the Company “as is” and “as available,” without warranties of any kind, express or implied.\n\n'
                              'We do not warrant that the platform will be accurate, reliable, uninterrupted, error-free, secure, or meet every user expectation.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '14. Limitation of Liability',
                          'To the fullest extent permitted by law, the Company is not liable for:\n'
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
                          '15. Liability Cap',
                          'To the fullest extent permitted by law, the total aggregate liability of Hunter Interactive LLC, doing business as RingMaster One and providing RingMaster Show, arising out of or related to the platform, services, these Terms, or any show or event shall not exceed the amount actually paid to the Company by you or your organization for the affected show, event, subscription, or service during the twelve (12) months preceding the claim.\n\n'
                              'This limitation applies regardless of the legal theory of liability, including contract, tort, negligence, strict liability, or otherwise.\n\n'
                              'Nothing in these Terms excludes or limits liability that cannot lawfully be excluded or limited.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '16. Force Majeure',
                          'To the fullest extent permitted by law, the Company is not responsible or liable for any delay, interruption, failure, or inability to perform caused by events beyond its reasonable control, including severe weather, fire, flood, natural disasters, power outages, internet or telecommunications failures, hosting provider outages, payment processor outages, third-party service failures, labor disputes, war, terrorism, civil unrest, government action, or emergency conditions.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '17. Severability',
                          'If a court of competent jurisdiction finds any provision of these Terms invalid, illegal, or unenforceable, the remaining provisions will remain in full force and effect. The affected provision will be limited to the extent necessary and permitted by law to preserve its original intent as closely as possible. If it cannot lawfully be enforced, it will be severed from these Terms.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '18. Entire Agreement / Integration',
                          'These Terms, together with any applicable order forms, invoices, service plans, policies, or written agreements expressly incorporated by reference, constitute the entire agreement between you and the Company regarding use of RingMaster Show. They supersede all prior or contemporaneous understandings, communications, representations, proposals, or agreements, whether oral or written, relating to the platform.\n\n'
                              'Except for updates under Section 20, no statement, promise, demonstration, email, message, or other communication modifies these Terms unless expressly agreed to in writing by you and an authorized representative of the Company.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '19. Governing Law & Venue',
                          'These Terms are governed by the laws of the State of Indiana, without regard to conflict of law principles.\n\n'
                              'Except where applicable law requires otherwise, any action or proceeding arising out of or relating to these Terms, RingMaster Show, or the services must be brought exclusively in the state courts located in Delaware County, Indiana, or, if federal subject-matter jurisdiction exists, in the United States District Court for the Southern District of Indiana, Indianapolis Division.\n\n'
                              'You and the Company consent to the personal jurisdiction of those courts and, to the extent permitted by law, waive objections based on venue or inconvenient forum.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '20. Changes to Terms',
                          'These Terms may be updated at any time as the platform evolves. When material changes are made, users may be required to review and accept the updated Terms before continuing to use the platform.\n\n'
                              'Continued use of RingMaster Show constitutes acceptance of the current Terms.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '21. Contact',
                          'For questions, concerns, support requests, or notices regarding these Terms, please contact Hunter Interactive LLC (doing business as RingMaster One) through RingMaster Show support.',
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