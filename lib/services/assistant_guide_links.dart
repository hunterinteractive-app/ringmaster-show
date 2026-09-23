import 'assistant_guide_catalog.dart';

final _guideMarker = RegExp(r'\[\[guide:([^\]]+)\]\]');
String assistantVisibleAnswer(String answer) =>
    answer.replaceAll(_guideMarker, '').trim();

Map<String, String> assistantGuideLinks(String answer) {
  final links = <String, String>{};
  for (final match in _guideMarker.allMatches(answer)) {
    final guide = assistantGuideCatalog[match.group(1)];
    if (guide != null && links.length < 3) {
      links[guide['label']!] = guide['url']!;
    }
  }
  return links;
}

String preparedGuideCitation(String question) {
  final q = question.toLowerCase();
  String? id;
  if (q.contains('add an animal')) {
    id = 'animals';
  } else if (q.contains('configure open and youth')) {
    id = 'divisions';
  } else if (q.contains('set up show sections')) {
    id = 'setup';
  } else if (q.contains('prepare reports to close')) {
    id = 'closeout';
  } else if (q.contains('report generation fails')) {
    id = 'generate';
  } else if (q.contains('reports have been emailed')) {
    id = 'email';
  } else if (q.contains('opening entries')) {
    id = 'publish';
  } else if (q.contains('enter a show') ||
      q.contains('enter shows a') ||
      q.contains('before checkout') ||
      q.contains('cart before') ||
      q.contains('entries were submitted')) {
    id = 'entry';
  }
  return id == null ? '' : '\n\n[[guide:$id]]';
}
