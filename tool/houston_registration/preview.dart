import 'package:flutter/material.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:ringmaster_show/widgets/cart_registration_requirements_dialog.dart';

// Isolated visual review: save never calls a backend or payment provider.
void main() => runApp(
  MaterialApp(
    theme: AppTheme.onGradientTheme(AppTheme.lightTheme),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: FilledButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (dialogContext) => Theme(
                data: AppTheme.surfaceDialogTheme(Theme.of(dialogContext)),
                child: CartRegistrationRequirementsDialog(
                  requirements: {
                    'agreement':
                        'I have read and agree to the full 2027 Release of Liability and Indemnity linked above.',
                    'document': {
                      'title': '2027 Release of Liability and Indemnity',
                      'url':
                          'https://show.ringmasterone.com/documents/houston/2027-open-show-indemnity-c3e23a4c4021.docx',
                    },
                    'handbook_url':
                        'https://www.rodeohouston.com/wp-content/uploads/2026/10/2027-Exhibitor-Handbook-V2.pdf',
                    'website_url': 'https://www.rodeohouston.com',
                    'exhibitors': [
                      {
                        'exhibitor_id': 'preview',
                        'name': 'Sample Youth Exhibitor',
                        'number': 1234,
                        'state': 'TX',
                      },
                    ],
                  },
                  save: (_) async {},
                ),
              ),
            ),
            child: const Text(
              'Preview checkout requirements (no live changes)',
            ),
          ),
        ),
      ),
    ),
  ),
);
