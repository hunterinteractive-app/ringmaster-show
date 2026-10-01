/// Routing grants no access: the server independently checks every scope.
bool assistantIsFollowUp(String message) {
  final q = message.trim().toLowerCase().replaceAll(RegExp(r'[.!?]+$'), '');
  return RegExp(
    r'^(yes( please)?|no|okay|ok|open( show section)?|youth( show section)?|exhibitor|secretary|i am (an exhibitor|the secretary)|still (not working|the same)|it (still )?(doesn.t|won.t) (work|save)|for .+)$',
  ).hasMatch(q);
}

String assistantTopicForQuestion(
  String message, {
  String page = '',
  String previousTopic = 'help',
  bool hasHistory = false,
}) {
  final q = message.toLowerCase();
  if (hasHistory && assistantIsFollowUp(message)) return previousTopic;
  // A payment question needs clarification; entry status is not payment status.
  if (RegExp(r'\b(payment|paid|pay|balance|refund)\b').hasMatch(q)) {
    return 'help';
  }
  final personal = RegExp(
    r'\b(check|look up|lookup|verify|missing|unavailable|can.t|cannot|won.t|why|is my|are my|did my|have my|which.*my|what.*my|how many)\b',
  ).hasMatch(q);
  if (personal &&
      RegExp(
        r'\b(animal|animals|rabbit|rabbits|birthdate|birth date|dob|tattoo)\b',
      ).hasMatch(q) &&
      !RegExp(
        r'\b(entry|entries|entered|section|sections|cart)\b',
      ).hasMatch(q)) {
    return 'animals';
  }
  if (RegExp(r'\b(how do|how can|how to|where do|where can)\b').hasMatch(q) &&
      !personal) {
    return 'help';
  }
  if (RegExp(
    r'\b(closeout|close out|report status|reports generated)\b',
  ).hasMatch(q)) {
    return 'closeout';
  }
  if (RegExp(r'\b(report|reports|leg|legs)\b').hasMatch(q)) return 'reports';
  if (RegExp(
    r'\b(entry|entries|entered|registered|registration|section|sections)\b',
  ).hasMatch(q)) {
    // Merely mentioning a section must not send an exhibitor into secretary-only scope.
    if (RegExp(
      r'\b(configure|configuration|setup|set up|judging date)\b',
    ).hasMatch(q)) {
      return 'setup';
    }
    return 'entries';
  }
  if (RegExp(
    r'\b(household|exhibitor|exhibitors|linked accounts)\b',
  ).hasMatch(q)) {
    return 'household';
  }
  if (personal && page.toLowerCase().contains('my animals')) return 'animals';
  if (personal && page.toLowerCase().contains('my entries')) return 'entries';
  return 'help';
}

/// Preserve the current issue and recent dialogue without increasing the six
/// message API limit. The complete chat remains in the transcript for review.
List<Map<String, String>> assistantHistory(
  List<Map<String, String>> messages,
  String? originalQuestion,
) {
  final recent = messages.skip(messages.length > 5 ? messages.length - 5 : 0);
  return [
    if (originalQuestion != null &&
        !recent.any(
          (m) => m['role'] == 'user' && m['content'] == originalQuestion,
        ))
      {
        'role': 'user',
        'content': originalQuestion.substring(
          0,
          originalQuestion.length.clamp(0, 1800),
        ),
      },
    for (final m in recent)
      {
        'role': m['role']!,
        'content': m['content']!.substring(
          0,
          m['content']!.length.clamp(0, 1000),
        ),
      },
  ];
}

/// These troubleshooting prompts need facts when signed in; signed-out users
/// retain the general prepared guidance.
bool assistantQuestionNeedsRecords(String message) {
  final q = message.toLowerCase().replaceAll(RegExp(r'[?!.]+$'), '').trim();
  return const {
    'why is an entry missing from my list',
    'why is an animal unavailable for this section',
    'why is a report missing',
  }.contains(q);
}
