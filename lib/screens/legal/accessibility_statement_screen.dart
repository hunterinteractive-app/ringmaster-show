import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_theme.dart';
import '../../widgets/rm_widgets.dart';

class AccessibilityStatementScreen extends StatelessWidget {
  const AccessibilityStatementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleLarge;
    final sectionStyle = Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);
    final bodyStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(height: 1.6);

    return Scaffold(
      appBar: AppBar(title: const Text('Accessibility Statement')),
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
                          'RingMaster Show – Accessibility Statement',
                          style: titleStyle,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Last updated: August 26, 2026',
                          style: bodyStyle?.copyWith(color: AppColors.muted),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'RingMaster Show is committed to making its web application accessible to everyone, including people with disabilities.',
                          style: bodyStyle,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _section(
                          'Our accessibility commitment',
                          'We are actively working toward conformance with the Web Content Accessibility Guidelines (WCAG) 2.2 Level AA. On August 26, 2026, RingMaster Show completed accessibility improvements and testing of key exhibitor and show-secretary workflows. We continue to review, test, and improve accessibility across the application.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          'Feedback and assistance',
                          'If you experience an accessibility barrier, need assistance using RingMaster Show, or would like to request an accessible alternative, please contact us.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        TextButton.icon(
                          onPressed: () => launchUrl(
                            Uri(
                              scheme: 'mailto',
                              path: 'support@ringmasterone.com',
                            ),
                          ),
                          icon: const Icon(Icons.email_outlined),
                          label: const Text('support@ringmasterone.com'),
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
