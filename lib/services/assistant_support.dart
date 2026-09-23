import 'assistant_guide_links.dart';

String assistantSupportBody({
  required String page,
  required String topic,
  required String conversationId,
  String? show,
  required List<Map<String, String>> messages,
  String draft = '',
}) {
  final body = StringBuffer()
    ..writeln('CHESTER SUPPORT REQUEST')
    ..writeln()
    ..writeln('Screen: $page')
    ..writeln('Topic: $topic')
    ..writeln('Show: ${show ?? "Not selected"}')
    ..writeln('Conversation: $conversationId')
    ..writeln()
    ..writeln('ADDITIONAL DETAILS')
    ..writeln('Please describe what you still need help with:')
    ..writeln()
    ..writeln()
    ..writeln('FULL CHAT WITH CHESTER')
    ..writeln('----------------------');
  if (messages.isEmpty) body.writeln('No messages yet.');
  for (var i = 0; i < messages.length; i++) {
    final message = messages[i];
    final content = message['content'] ?? '';
    body
      ..writeln()
      ..writeln(
        '${i + 1}. ${message['role'] == 'user' ? 'Exhibitor / secretary' : 'Chester'}',
      )
      ..writeln(assistantVisibleAnswer(content));
    for (final guide in assistantGuideLinks(content).entries) {
      body
        ..writeln()
        ..writeln('${guide.key}:')
        ..writeln(guide.value);
    }
  }
  if (draft.trim().isNotEmpty) {
    body
      ..writeln()
      ..writeln('UNSENT DRAFT')
      ..writeln(draft);
  }
  return body.toString();
}

Uri assistantSupportEmail(String page, String body) => Uri(
  scheme: 'mailto',
  path: 'support@ringmasterone.com',
  query:
      'subject=${Uri.encodeComponent('RingMaster Show help: $page')}'
      '&body=${Uri.encodeComponent(body)}',
);
