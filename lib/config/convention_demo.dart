import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Compile-time opt-in for the isolated convention build only.
class ConventionDemo {
  static const enabled = bool.fromEnvironment('CONVENTION_DEMO');

  static void validate(String apiUrl, Uri browserUrl) {
    if (!enabled) return;
    bool local(Uri uri) =>
        uri.scheme == 'http' &&
        (uri.host == '127.0.0.1' || uri.host == 'localhost');
    if (!local(Uri.parse(apiUrl)) || !local(browserUrl)) {
      throw StateError('The convention demo requires local services.');
    }
  }

  static Future<void> selectPersona() async {
    if (!enabled) return;
    final fonts = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    await fonts.load();
    final role = Uri.base.queryParameters['demo_role'];
    final email = switch (role) {
      'secretary' => 'secretary@example.invalid',
      'exhibitor' => 'exhibitor1@example.invalid',
      _ => null,
    };
    if (email == null) return;
    await Supabase.instance.client.auth.signInWithPassword(
      email: email,
      password: 'Convention-Demo-Only-2026!',
    );
  }
}
