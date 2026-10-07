import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/services/assistant_guide_catalog.dart';
import 'package:ringmaster_show/services/assistant_guide_links.dart';

void main() {
  test('client references match the verified server catalog', () {
    final catalog = jsonDecode(
      File('supabase/functions/show-assistant/guides.json').readAsStringSync(),
    );
    expect(assistantGuideCatalog.length, catalog['guides'].length);
    for (final g in catalog['guides']) {
      final client = assistantGuideCatalog[g['id']]!;
      expect(client['url'], g['url']);
      final steps = g['start'] == g['end']
          ? 'Step ${g['start']}'
          : 'Steps ${g['start']}–${g['end']}';
      expect(client['label'], '${g['title']} — $steps');
    }
  });
  test('only verified citation markers become links', () {
    const answer =
        'Review checkout. [[guide:entry]] [[guide:unknown]] [[guide:https://evil.example]]';
    final links = assistantGuideLinks(answer);
    expect(links.length, 1);
    expect(links.keys.single, contains('Steps 26–33'));
    expect(links.values.single, startsWith('https://scribehow.com/'));
    expect(assistantVisibleAnswer(answer), 'Review checkout.');
  });
  test(
    'prepared guidance cites relevant steps without guessing missing guides',
    () {
      expect(
        preparedGuideCitation('How do I add an animal?'),
        contains('[[guide:animals]]'),
      );
      expect(preparedGuideCitation('Where can I find my legs?'), isEmpty);
      expect(
        assistantGuideLinks('[[guide:generate]]').keys.single,
        contains('Step 30'),
      );
    },
  );
}
