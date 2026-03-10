class SupabaseConfig {
  // Local dev defaults (safe for public apps — this is anon key)
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://yzjoycrvqkyfrksmaixf.supabase.co',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl6am95Y3J2cWt5ZnJrc21haXhmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgyNTY1MzcsImV4cCI6MjA4MzgzMjUzN30.pGpYESQo9lRngJ5eQmxly0xVO1P2YhHx--gB59p09w0',
  );

  static void validate() {
    assert(
      url.isNotEmpty && anonKey.isNotEmpty,
      'Missing Supabase config',
    );
  }
}