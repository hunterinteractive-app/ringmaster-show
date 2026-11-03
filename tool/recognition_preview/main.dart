import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/config/supabase_config.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:ringmaster_show/screens/super_admin/breed_catalog_screen.dart';
import 'package:ringmaster_show/screens/super_admin/recognition_timeline_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  final backend = Uri.parse(SupabaseConfig.url);
  if (backend.scheme != 'http' ||
      !{'127.0.0.1', 'localhost'}.contains(backend.host) ||
      !{'127.0.0.1', 'localhost'}.contains(Uri.base.host)) {
    throw StateError(
      'Recognition preview requires a local browser and local database.',
    );
  }
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );
  await Supabase.instance.client.auth.signInWithPassword(
    email: const String.fromEnvironment('PREVIEW_EMAIL'),
    password: const String.fromEnvironment('PREVIEW_PASSWORD'),
  );
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      builder: (context, child) => Column(
        children: [
          const Material(
            color: Color(0xffffe6a0),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  width: double.infinity,
                  child: Text(
                    'LOCAL TEST ONLY • Separate test database • Nothing deployed',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: child!),
        ],
      ),
      home: const RecognitionPreviewHome(),
    ),
  );
}

class RecognitionPreviewHome extends StatelessWidget {
  const RecognitionPreviewHome({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xfff3f4f6),
    appBar: AppBar(title: const Text('Recognition status preview')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Test COD → Recognized → Retired',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          'Open an example and compare November 30 with December 1, 2026. Then add a future Retired status with its own date and preview that date. Changes are saved only in the local test database.',
        ),
        const SizedBox(height: 8),
        const Text(
          'The sample COD start date is test data, not an assertion of the historical recognition date. These examples test status eligibility; AOV classification is separate catalog configuration.',
        ),
        const SizedBox(height: 20),
        for (final target in const [
          ['Velveteen Lop (COD)', 'Solid'],
          ['Velveteen Lop (COD)', 'Broken'],
          ['French Lop', 'Otter (COD)'],
          ['Mini Rex', 'Brindle (COD)'],
          ['Satin', 'Silver Marten (COD)'],
          ['Netherland Dwarf', 'Frosty (COD)'],
        ])
          Card(
            child: ListTile(
              title: Text('${target[0]} — ${target[1]}'),
              subtitle: Text(
                target[1] == 'Broken'
                    ? 'Remains COD after December 1'
                    : 'Recognized from December 1, 2026',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RecognitionTimelineScreen(
                    species: 'rabbit',
                    breedName: target[0],
                    varietyName: target[1],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 20),
        FilledButton.icon(
          icon: const Icon(Icons.list),
          label: const Text('Open full Super Admin breed catalog'),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BreedCatalogScreen()),
          ),
        ),
      ],
    ),
  );
}
