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
  test(
    'new entry workflows route natural questions without confusing profiles or age classes',
    () {
      final fur = assistantPreparedAnswer(
        'How can I add fur classes to rabbits already entered?',
      )!;
      expect(fur, contains('My Entries'));
      expect(fur, contains('Add Fur/Wool'));
      expect(fur, contains('Continue to checkout'));
      expect(
        fur,
        contains('does not submit them or charge a card automatically'),
      );
      final wool = assistantPreparedAnswer('How do I enter a wool class?')!;
      expect(wool, contains('separate competition'));
      expect(wool, contains('While creating an entry'));
      final tattoo = assistantPreparedAnswer(
        'How can I change my rabbit tattoo?',
      )!;
      expect(tattoo, contains('Tattoo / ear number'));
      expect(tattoo, contains('Choose other show sections'));
      expect(tattoo, contains('saved My Animals profile stays unchanged'));
      final profile = assistantPreparedAnswer(
        'How do I change a tattoo in My Animals?',
      )!;
      expect(profile, startsWith('Open My Animals'));
      expect(
        assistantPreparedAnswer('How do I enter a meat pen without tattoos?'),
        contains('Tattoos not yet assigned'),
      );
    },
  );
  test(
    'current guidance preserves deadlines, payment and delivery boundaries',
    () {
      expect(
        assistantPreparedAnswer('How do I correct an entry?'),
        contains('locked or finalized'),
      );
      expect(
        assistantPreparedAnswer(
          'What happens to the balance when I scratch an unpaid entry?',
        ),
        contains('Paid entries are not automatically refunded'),
      );
      expect(
        assistantPreparedAnswer('How do I resend reports?'),
        contains('requires a message'),
      );
      expect(
        assistantPreparedAnswer(
          'How do I resend reports?',
          updatedLayout: true,
        ),
        contains('Reports & Closeout'),
      );
      expect(
        assistantPreparedAnswer(
          'Why does it say only youth exhibitors may be used?',
        ),
        contains('Do not create duplicate exhibitors'),
      );
      expect(
        assistantPreparedAnswer(
          'How do I check which show sections I entered?',
        ),
        contains('A before B'),
      );
      for (final question in [
        'Can you check whether my fur entry was submitted?',
        'Is my rabbit entered in wool?',
        'Did my tattoo change save?',
        'Did my payment go through?',
      ]) {
        expect(assistantPreparedAnswer(question), isNull, reason: question);
      }
    },
  );
}
