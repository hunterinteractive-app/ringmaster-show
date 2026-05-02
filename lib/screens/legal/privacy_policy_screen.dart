// lib/screens/legal/privacy_policy_screen.dart

import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Text(
'''
RingMaster Show – Privacy Policy
Effective Date: May 2026 (v2026-05)

RingMaster Show respects your privacy and is committed to protecting your information.

1. Information We Collect
We may collect:
• Name and contact information
• Account credentials
• Show-related data (entries, exhibitors, animals, results)
• Device and usage data

2. How We Use Information
We use data to:
• Operate the platform
• Manage shows and results
• Improve performance and reliability
• Maintain security

3. Data Responsibility
Users (clubs, secretaries, etc.) are responsible for the data they enter and manage.

4. Data Sharing
We do not sell user data.

Data may be shared:
• With authorized show participants (e.g., secretaries, judges)
• When required by law
• With service providers needed to operate the platform

5. Data Storage & Retention
Data is stored securely and may be retained for operational purposes.

Show data may be retained for a limited time (e.g., up to 1 year).

6. Security
We take reasonable steps to protect data but cannot guarantee absolute security.

7. Your Rights
You may request access to or deletion of your account data where applicable.

8. Changes to Policy
This policy may be updated at any time. Continued use constitutes acceptance of changes.

9. Contact
For questions, please contact RingMaster Show support.
''',
            style: TextStyle(height: 1.5),
          ),
        ),
      ),
    );
  }
}