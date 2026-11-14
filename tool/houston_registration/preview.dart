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
                        'I agree to the Houston Livestock Show and Rodeo rules listed in the 2027 Exhibitor Handbook and all terms and conditions listed on the Houston Livestock Show and Rodeo website.',
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
