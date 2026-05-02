// lib/screens/legal/terms_screen.dart

import 'package:flutter/material.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terms of Service')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Text(
'''
RingMaster Show – Terms of Service
Effective Date: May 2026 (v2026-05)

By creating an account or using RingMaster Show, you agree to the following:

1. Use of Platform
RingMaster Show provides tools for managing animal shows, including entries, judging workflows, and reporting.

You agree to use the platform only for lawful and intended show management purposes.

2. Data Accuracy & User Responsibility
All users (including secretaries, judges, exhibitors, and writers) are solely responsible for the accuracy and completeness of any data entered into the system.

This includes:
• Manual entries
• QR Code submissions
• Imported or edited results
• System-generated or modified data

RingMaster Show does not guarantee the accuracy or completeness of submitted data.

3. QR Code Entry Disclaimer (Important)
QR Code features are provided to assist with faster data entry.

By using QR Code entry:
• You acknowledge entries may be submitted from external devices
• You agree all results must be reviewed before finalization
• You accept responsibility for verifying correctness

4. Finalization of Results
When a show is finalized:
• Results are considered locked and official within the system
• The user performing finalization confirms all data has been reviewed

RingMaster Show is not responsible for errors not corrected prior to finalization.

5. Limitation of Liability
RingMaster Show is provided “as is” without warranties of any kind.

We are not liable for:
• Data entry errors
• Missed placements
• Incorrect results
• Loss of awards, standings, or records

6. Service Availability
We aim for reliable service but do not guarantee uninterrupted operation.

7. Changes to Terms
These terms may be updated at any time. Continued use of the platform constitutes acceptance of changes.

8. Contact
For questions, please contact RingMaster Show support.
''',
            style: TextStyle(height: 1.5),
          ),
        ),
      ),
    );
  }
}