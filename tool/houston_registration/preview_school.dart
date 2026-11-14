import 'package:flutter/material.dart';
import 'package:ringmaster_show/screens/admin/admin_entry_management_screen.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

// Visual review only. Uses synthetic data and never connects to the backend.
void main() => runApp(
  MaterialApp(
    theme: AppTheme.onGradientTheme(AppTheme.lightTheme),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: SizedBox(
            width: 390,
            child: buildAdminExhibitorSheet(
              context,
              showId: 'preview',
              exhibitor: const {
                'id': 'preview',
                'showing_name': 'Sample Youth Exhibitor',
                'first_name': 'Sample',
                'last_name': 'Exhibitor',
              },
              schoolInformationLoader: () async => {
                'applicable': true,
                'school': {
                  'school_name':
                      'A Long School Name That Should Wrap On A Phone',
                  'city': 'Houston',
                  'state': 'TX',
                },
              },
            ),
          ),
        ),
      ),
    ),
  ),
);
