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
                          'Effective Date: September 2026 (v2026-09)',
                          style: bodyStyle?.copyWith(color: AppColors.muted),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'RingMaster Show is provided by Hunter Interactive LLC, doing business as RingMaster One (the “Company,” “we,” “us,” or “our”). This Privacy Policy explains how we collect, use, share, and retain personal information in connection with RingMaster Show.',
                          style: bodyStyle,
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        _section(
                          '1. Information We Collect',
                          'We may collect:\n'
                              '• Name and contact information, including email address, phone number, and mailing address\n'
                              '• Account and authentication information\n'
                              '• Display name, exhibitor and group profile information, membership numbers, and birth dates used for youth eligibility\n'
                              '• Show-related data, including entries, exhibitors, animals, judging, results, reports, and related event records\n'
                              '• Device, browser, and usage information\n'
                              '• Support messages, screenshots of the app captured when a help report is submitted, and related diagnostic information\n'
                              '• Payment and transaction-related information when paid features are used\n\n'
                              'Information may be provided directly by you, submitted by an authorized club representative or other user managing show records, or generated through your use of the platform.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '2. How We Use Information',
                          'We use information to:\n'
                              '• Operate the platform and maintain user accounts\n'
                              '• Manage shows, entries, judging workflows, results, and official records\n'
                              '• Generate, deliver, and make available show reports and exports\n'
                              '• Process payments and maintain transaction records\n'
                              '• Respond to support requests and diagnose problems\n'
                              '• Improve performance, reliability, and user experience\n'
                              '• Maintain security and prevent misuse\n'
                              '• Communicate important service updates and account-related notices\n'
                              '• Meet applicable legal obligations and address disputes',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '3. Data Responsibility',
                          'Users, clubs, secretaries, judges, exhibitors, and writers are responsible for the accuracy and completeness of the data they enter, submit, review, or manage within the platform. Users submitting information about another person must have appropriate authority to do so.\n\n'
                              'These responsibilities do not limit the obligations of Hunter Interactive LLC under applicable privacy and data protection laws.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '4. Data Sharing',
                          'We do not sell user data.\n\n'
                              'Data may be shared:\n'
                              '• With authorized show participants and officials, including secretaries, judges, writers, exhibitors, and show administrators, as needed for their roles and show activities\n'
                              '• With clubs, ARBA, other sanctioning or reporting organizations, and designated recipients through show reports, exports, or other authorized reporting workflows\n'
                              '• With service providers supporting hosting, authentication, email, payments, storage, analytics, or support, as needed to operate those services\n'
                              '• When required by law, court order, legal process, or governmental request\n'
                              '• When reasonably necessary to protect the rights, safety, security, or integrity of the Company, its users, or the public\n\n'
                              'The information shared depends on the recipient, purpose, applicable permissions, and report or export selected. Clubs and other organizations that receive copies are responsible for their own handling of those copies and their applicable privacy obligations.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '5. Data Storage & Retention',
                          'We retain personal information for the operational, reporting, support, security, and legal purposes described in this policy. Our general retention target for show data, including finalized results and reports, is up to two (2) years after the show ends. This target does not guarantee that data will remain continuously available throughout that period.\n\n'
                              'Specific records may be retained longer when required by law or reasonably necessary for an unresolved dispute, audit, security investigation, or applicable recordkeeping requirement. Any extension is limited to the records and period needed for that purpose. Account, contact, payment, and support information may have different retention periods based on the purpose for which it is needed and applicable law.\n\n'
                              'ARBA Official Show Rules, Section 36(B), require the show sponsor to retain official show records for at least one (1) year. Clubs and show sponsors remain responsible for satisfying this requirement and any other applicable recordkeeping rules. Authorized club representatives can download available show data and reports using the platform tools and should retain their own copies. RingMaster Show does not replace the club or show sponsor as the keeper of its official records.\n\n'
                              'An account deletion request does not necessarily require deletion of all associated official show records. We evaluate requests under applicable law and retain only information needed for a permitted purpose. Retention of an official result or report does not by itself justify retaining unrelated account or contact information. Copies already downloaded or received by a club, show sponsor, or reporting organization are managed by that recipient and are not removed when an account is deleted from RingMaster Show.',
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
                          'You may request access to, correction of, or deletion of your personal information, and exercise other rights available under applicable law, by emailing support@ringmasterone.com. Describe your request and identify the account or show records involved. We may need information to verify your identity and authority before responding.\n\n'
                              'Requests are evaluated under applicable law, including any permitted retention exceptions described in Section 5. If we cannot fully fulfill a request, we will explain the reason and any further options required by applicable law. Requests about copies held independently by a club or other organization may also need to be directed to that organization.\n\n'
                              'Nothing in this policy limits privacy rights that cannot lawfully be waived.',
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
                          'The Company uses third-party services for functions such as hosting, authentication, payments, email delivery, storage, and support. These providers process information relevant to the services they provide.\n\n'
                              'If you interact directly with a third-party service or follow a link to another website, review the privacy notice that applies to that service. This does not limit our obligations for information we disclose under this policy or applicable law.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '10. Changes to Policy',
                          'We may update this policy as our services, information practices, or legal obligations change. The effective date and version identify the current policy. We will provide notice of material changes through the platform or another appropriate method. Users may be required to review and acknowledge the updated policy before continuing to use the platform.\n\n'
                              'Where applicable law requires consent for a change in how personal information is collected, used, or disclosed, we will obtain that consent before applying the change. Updating this policy or recording an acknowledgment does not by itself authorize materially different uses of previously collected information that require separate consent.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '11. Governing Law & Your Privacy Rights',
                          'This policy describes our privacy practices and should be read with the RingMaster Show Terms of Service, including their Indiana governing-law and Delaware County, Indiana venue provisions and the designated federal court when federal jurisdiction exists. Those provisions apply only to the extent permitted by applicable law.\n\n'
                              'Nothing in this policy or the Terms of Service excludes applicable privacy laws, limits rights that cannot lawfully be waived, or restricts a right to contact a regulator.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '12. Contact',
                          'For privacy-related questions, requests, or concerns, contact Hunter Interactive LLC, doing business as RingMaster One, at support@ringmasterone.com.',
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