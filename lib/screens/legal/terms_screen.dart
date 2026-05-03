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
                        Text(
                          'RingMaster Show – Terms of Service',
                          style: titleStyle,
                        ),
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
                          'RingMaster Show provides tools for managing animal shows, including entries, judging workflows, and reporting.\n\n'
                              'You agree to use the platform only for lawful and intended show management purposes.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '2. Data Accuracy & User Responsibility',
                          'All users (including secretaries, judges, exhibitors, and writers) are solely responsible for the accuracy and completeness of any data entered into the system.\n\n'
                              'This includes:\n'
                              '• Manual entries\n'
                              '• QR Code submissions\n'
                              '• Imported or edited results\n'
                              '• System-generated or modified data\n\n'
                              'RingMaster Show does not guarantee the accuracy or completeness of submitted data.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '3. QR Code Entry Disclaimer (Important)',
                          'QR Code features are provided to assist with faster data entry.\n\n'
                              'By using QR Code entry:\n'
                              '• You acknowledge entries may be submitted from external devices\n'
                              '• You agree all results must be reviewed before finalization\n'
                              '• You accept responsibility for verifying correctness',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '4. Finalization of Results',
                          'When a show is finalized:\n'
                              '• Results are considered locked and official within the system\n'
                              '• The user performing finalization confirms all data has been reviewed\n\n'
                              'RingMaster Show is not responsible for errors not corrected prior to finalization.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '5. Limitation of Liability',
                          'RingMaster Show is provided “as is” without warranties of any kind.\n\n'
                              'We are not liable for:\n'
                              '• Data entry errors\n'
                              '• Missed placements\n'
                              '• Incorrect results\n'
                              '• Loss of awards, standings, or records',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '6. Service Availability',
                          'We aim for reliable service but do not guarantee uninterrupted operation.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '7. Changes to Terms',
                          'These terms may be updated at any time. Continued use of the platform constitutes acceptance of changes.',
                          sectionStyle,
                          bodyStyle,
                        ),

                        _section(
                          '8. Contact',
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