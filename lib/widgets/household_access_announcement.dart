import 'package:flutter/material.dart';

class HouseholdAccessAnnouncement extends StatelessWidget {
  const HouseholdAccessAnnouncement({super.key});
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Your family can use their own logins'),
    content: const SingleChildScrollView(
      child: Text(
        'You have several active exhibitors. In Account Settings, update each adult’s email to their own email address. Youth aged 14 or older can also have their own login when their birth date is recorded. Younger youth continue using a parent’s login.\n\n'
        'Saving a new eligible email sends an invitation. They verify their email and accept under Household Access to share your exhibitors, animals, entries, and reports—without sharing login codes.\n\n'
        'Their existing household stays separate. Show Secretary and admin rights stay with each individual login.',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Got it'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Open Household Access'),
      ),
    ],
  );
}
