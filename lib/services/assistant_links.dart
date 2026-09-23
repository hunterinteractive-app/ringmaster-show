/// Only application-owned destinations; never navigate to model-generated URLs.
Map<String, String> assistantPageLinks(String answer) {
  final links = <String, String>{};
  final text = answer.toLowerCase();
  if (text.contains('my entries')) links['My Entries'] = '/assistant/entries';
  if (text.contains('past show reports')) {
    links['Past Show Reports'] = '/assistant/reports';
  }
  if (text.contains('my animals')) links['My Animals'] = '/assistant/animals';
  if (text.contains('account settings')) {
    links['Account Settings'] = '/assistant/account';
  }
  if (text.contains('household access') || text.contains('household switcher')) {
    links['Household Access'] = '/assistant/household';
  }
  if (text.contains('upcoming shows') ||
      text.contains('enter show') ||
      text.contains('entry cart')) {
    links['Shows & entry carts'] = '/assistant/shows';
  }
  if (text.contains('show sections') || text.contains('close show/reports')) {
    links['Show management'] = '/assistant/manage';
  }
  if (text.contains('secretary resources')) {
    links['Secretary Resources'] = '/assistant/resources';
  }
  return links;
}
