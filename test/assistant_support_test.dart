import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/services/assistant_support.dart';

void main() {
  test(
    'support includes the entire ordered chat, guides, and unsent draft',
    () {
      final messages = <Map<String, String>>[
        for (var i = 0; i < 12; i++)
          {'role': i.isEven ? 'user' : 'assistant', 'content': 'Message $i'},
        {'role': 'assistant', 'content': 'Read this. [[guide:entry]]'},
      ];
      final body = assistantSupportBody(
        page: 'Upcoming Shows',
        topic: 'General questions',
        conversationId: 'test-chat',
        messages: messages,
        draft: 'One more question',
      );
      for (var i = 0; i < 12; i++) {
        expect(body, contains('Message $i'));
      }
      expect(body.indexOf('Message 0'), lessThan(body.indexOf('Message 11')));
      expect(body, contains('Chester'));
      expect(body, contains('Steps 26–33'));
      expect(body, isNot(contains('[[guide:')));
      expect(body, contains('UNSENT DRAFT\nOne more question'));
      final uri = assistantSupportEmail('Upcoming Shows', body);
      expect(uri.toString(), contains('Upcoming%20Shows'));
      expect(uri.toString(), isNot(contains('+')));
      expect(uri.queryParameters['body'], body);
    },
  );
}
