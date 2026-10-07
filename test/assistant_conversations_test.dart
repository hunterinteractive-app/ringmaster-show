import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/super_admin/assistant_conversations_screen.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-key',
      debug: false,
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());
  testWidgets('review paginates without dropping earlier messages', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AssistantConversationsScreen(
          conversationId: 'sample',
          label: 'Test exhibitor',
          loadRows: (_, offset) async => [
            for (var i = offset; i < (offset == 0 ? 100 : 101); i++)
              {
                'role': i.isEven ? 'user' : 'assistant',
                'source': 'prepared',
                'page': 'My Entries',
                'topic': 'entries',
                'content': 'Message $i',
                'created_at': '2026-09-19T12:00:00Z',
              },
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Message 0'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Load more'),
      500,
      maxScrolls: 80,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Message 100'),
      400,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Message 100'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('review displays failure without claiming an empty archive', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AssistantConversationsScreen(
          loadRows: (_, _) async => throw Exception('denied'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Unable to load conversations.'),
      findsOneWidget,
    );
    expect(find.textContaining('No saved conversations yet.'), findsNothing);
  });
}
