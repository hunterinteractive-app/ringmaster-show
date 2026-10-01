import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/services/assistant_context.dart';
import 'package:ringmaster_show/services/assistant_suggestions.dart';

void main() {
  test('personal questions are routed to household-scoped records', () {
    expect(assistantTopicForQuestion('Is my entry in?'), 'entries');
    expect(
      assistantTopicForQuestion('How do I check if my rabbit is entered?'),
      'entries',
    );
    expect(
      assistantTopicForQuestion('Can you check my rabbit’s birthdate?'),
      'animals',
    );
    expect(
      assistantTopicForQuestion(
        'Why is my rabbit unavailable for this section?',
      ),
      'entries',
    );
    expect(assistantTopicForQuestion('How do I edit a birthdate?'), 'help');
    expect(
      assistantTopicForQuestion('How can I change my payment to online'),
      'help',
    );
  });
  test('brief follow-ups retain scope without forcing secretary access', () {
    for (final q in ['yes please', 'open', 'open show section']) {
      expect(
        assistantTopicForQuestion(q, previousTopic: 'help', hasHistory: true),
        'help',
      );
    }
    expect(
      assistantTopicForQuestion(
        'yes please',
        previousTopic: 'animals',
        hasHistory: true,
      ),
      'animals',
    );
    expect(
      assistantTopicForQuestion(
        'How do I add an animal?',
        previousTopic: 'entries',
        hasHistory: true,
      ),
      'help',
    );
  });
  test('long follow-ups keep original issue within existing API limit', () {
    final messages = <Map<String, String>>[
      {
        'role': 'user',
        'content': 'Entering a Satin Rabbit how do I get 6/8 class',
      },
      for (var i = 0; i < 10; i++)
        {'role': i.isEven ? 'assistant' : 'user', 'content': 'Follow-up $i'},
    ];
    final history = assistantHistory(messages, messages.first['content']);
    expect(history.length, 6);
    expect(history.first['content'], contains('6/8'));
    expect(history.last['content'], 'Follow-up 9');
  });
  test('reviewed guidance names actual controls', () {
    expect(
      assistantPreparedAnswer('How do I select the 6/8 class?'),
      contains('Intermediate'),
    );
    expect(
      assistantPreparedAnswer('How do I edit a birthdate?'),
      contains('Unknown DOB'),
    );
    expect(
      assistantPreparedAnswer('How do I enter shows A, B and C?'),
      contains('Select show(s) to enter'),
    );
  });
}
