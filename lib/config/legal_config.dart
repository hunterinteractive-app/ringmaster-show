// lib/config/legal_config.dart

class LegalConfig {
  static const String currentTermsVersion = '2026-09';
  static const String currentPrivacyVersion = '2026-10-25-locality';

  // Publication order, also used by the profile acceptance preservation trigger.
  // Add genuinely new policies here and in the trigger when publishing them.
  static const termsVersions = ['2026-05', '2026-09'];
  static const privacyVersions = [
    '2026-05',
    '2026-09',
    '2026-10',
    '2026-10-25-locality',
  ];

  static const String termsUrl = 'https://show.ringmasterone.com/terms';
  static const String privacyUrl = 'https://show.ringmasterone.com/privacy';
}

// Change when policy changes!
