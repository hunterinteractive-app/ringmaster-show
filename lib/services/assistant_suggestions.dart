/// Reviewed prompts selected locally from explicit screen metadata.
/// No record queries or AI calls are needed to display these.
List<String> assistantSuggestions(String title) {
  final page = title.toLowerCase();
  if (page.contains('entry cart') ||
      page.contains('checkout') ||
      page.contains('square payment')) {
    return const [
      'How do I review my cart before submitting?',
      'How do I know my entries were submitted?',
      'What should I do if checkout does not finish?',
    ];
  }
  if (page.contains('my entries')) {
    return const [
      'How do I check which show sections I entered?',
      'How do I correct an entry?',
      'Why is an entry missing from my list?',
    ];
  }
  if (page.contains('enter show')) {
    return const [
      'How do I enter shows A, B and C?',
      'Why is an animal unavailable for this section?',
      'How do I review my entries before checkout?',
    ];
  }
  if (page.contains('closeout') || page.contains('close show')) {
    return const [
      'How do I prepare reports to close this show?',
      'What should I check if report generation fails?',
      'How do I know whether reports have been emailed?',
    ];
  }
  if (page.contains('past reports') || page.contains('past show reports')) {
    return const [
      'Where can I find my legs?',
      'How do I download a report?',
      'Why is a report missing?',
    ];
  }
  if (page.contains('show settings') ||
      page.contains('show sections') ||
      page.contains('create show') ||
      page.contains('manage shows')) {
    return const [
      'How do I set up show sections?',
      'How do I configure Open and Youth shows?',
      'What should I check before opening entries?',
    ];
  }
  if (page.contains('household')) {
    return const [
      'How do I invite someone to my household?',
      'Why can’t I see a shared exhibitor?',
      'How do I switch between household exhibitors?',
    ];
  }
  if (page.contains('account settings') || page.contains('profile')) {
    return const [
      'How do I update my exhibitor information?',
      'How do I set up household access?',
      'What should I do if my records are linked incorrectly?',
    ];
  }
  if (page.contains('my animals')) {
    return const [
      'How do I add an animal?',
      'Does saving an animal enter it in a show?',
      'How do I correct my animal’s information?',
    ];
  }
  if (page.contains('upcoming shows')) {
    return const [
      'How do I enter a show?',
      'How do I find a show’s entry deadline?',
      'Where can I see my submitted entries?',
    ];
  }
  return const [
    'How do I check my entries?',
    'Where can I find my legs?',
    'How do I set up show sections?',
  ];
}

/// Static guidance only: never implies that a user's live records were checked.
const assistantPreparedAnswers = <String, String>{
  'How do I review my cart before submitting?':
      'Review the animals, exhibitors, show sections and fees in your Entry Cart before completing checkout. Items in the cart are not submitted entries. After checkout, open My Entries to verify what was saved.',
  'How do I know my entries were submitted?':
      'Open My Entries and expand the show to review your submitted entries and sections. A saved animal or an item in your cart is not confirmation of an entry. Confirmation email timing can vary by show.',
  'What should I do if checkout does not finish?':
      'First check My Entries to see whether the submission completed before trying checkout again. If the result is unclear, contact support with the show name and the message you saw. I have not checked your payment or entry status.',
  'How do I check which show sections I entered?':
      'Open My Entries, expand the show, and review the sections listed for each entry. Check each intended show letter and Open or Youth section. Adding an animal to one section does not confirm it is entered in the others.',
  'How do I correct an entry?':
      'Open My Entries and locate the entry under its show. Use the available entry actions to review your options. If changes are unavailable or the show has closed entries, contact the show secretary or support before creating a duplicate entry.',
  'Why is an entry missing from my list?':
      'Check that you are viewing the correct household exhibitor and show. Then check whether the animal is still in your cart. Saving an animal alone does not enter it in a show. If it still looks wrong, tell me which show you mean so we can look into it.',
  'How do I enter shows A, B and C?':
      'Choose the intended show section, then select the animals for that section. Repeat for the other sections you want to enter. Review your cart before checkout and My Entries afterward to confirm the sections submitted.',
  'Why is an animal unavailable for this section?':
      'Review the selected section’s breed scope and Open or Youth division, then check the animal and exhibitor information. Section requirements can affect which animals appear. Tell me the show, section and what you see if you need more help.',
  'How do I review my entries before checkout?':
      'Open the Entry Cart and review each exhibitor, animal and show section, along with the displayed fees. Make sure every intended section is represented before submitting. Then verify the submitted entries in My Entries.',
  'How do I prepare reports to close this show?':
      'Open Close Show/Reports and work through preparation, review and distribution. Resolve the readiness items shown on that screen before generating reports, and wait for generation to finish before reviewing or distributing them.',
  'What should I check if report generation fails?':
      'Read the error or readiness message in Close Show/Reports. Check the relevant sanctions, judges, awards and results, then follow the available next step. If the cause is unclear, contact support with the exact message rather than repeatedly starting generation.',
  'How do I know whether reports have been emailed?':
      'Review the distribution status in Close Show/Reports. A generated report is not proof that it was emailed or delivered. Some shows hand out reports instead. Ask the secretary or support if the delivery status is unclear.',
  'Where can I find my legs?':
      'Open Past Show Reports, choose the show, and look for the available legs and exhibitor reports. Use the download arrow for the report you need. If nothing is available yet, the show may still be preparing or distributing its reports.',
  'How do I download a report?':
      'Open Past Show Reports, select the show, then click the download arrow beside the report. If the file is ready but does not open, try clicking its download button directly and check your browser’s download notifications.',
  'Why is a report missing?':
      'Check the selected household exhibitor and show in Past Show Reports. The show may still be preparing reports or may distribute them another way. Tell me which show and report you mean if you would like more help.',
  'How do I set up show sections?':
      'Open Show Sections in your show’s management area. Configure the Open or Youth division, show letter and breed scope for each section. Judging dates must fall within the show dates; a one-day show uses its single date.',
  'How do I configure Open and Youth shows?':
      'Use Show Sections to create and review the intended Open and Youth sections. Check the division, show letter, breed scope and judging date for each one before accepting entries.',
  'What should I check before opening entries?':
      'Review the show dates, entry deadline, location, sections, breed scope and fees. Check the Open and Youth divisions and judging dates. Preview the exhibitor entry flow to confirm it matches the show you intend to run.',
  'How do I invite someone to my household?':
      'Open Account Settings → Household Access and use the invitation controls. The other person must accept the invitation before shared access is available. Household sharing does not grant show-secretary permissions.',
  'Why can’t I see a shared exhibitor?':
      'Check Household Access to confirm that the invitation was accepted and access has not been revoked. Then check your selected household. Contact support if records appear linked to the wrong person.',
  'How do I switch between household exhibitors?':
      'Use the household switcher to select the household you want to work with, then select the appropriate exhibitor in the entry flow. Only households with authorized access should be available.',
  'How do I update my exhibitor information?':
      'Open Account Settings and review your exhibitor information. Use the available edit controls and save your changes. If a field cannot be changed or records appear linked incorrectly, contact support.',
  'How do I set up household access?':
      'Open Account Settings → Household Access to manage invitations and shared access. Invitations must be accepted before sharing becomes active. Household permissions do not include secretary access to a show.',
  'What should I do if my records are linked incorrectly?':
      'Contact support with a description of the mismatch and the affected show or exhibitor. Avoid creating duplicate accounts or entries as a workaround. Chester cannot merge accounts or change record ownership.',
  'How do I add an animal?':
      'Open My Animals and use the add-animal action. Enter and review the required identification and class information before saving. To enter the animal in a show, continue through that show’s entry and checkout process.',
  'Does saving an animal enter it in a show?':
      'No. Saving an animal adds it to My Animals. You still need to choose a show and section, add the animal to your entry, and complete submission. Check My Entries afterward.',
  'How do I correct my animal’s information?':
      'Open My Animals, locate the animal, and use its edit controls. If it is already entered in a show, also review that submitted entry; do not assume an animal-profile edit changed an existing entry.',
  'How do I enter a show?':
      'Find the show under Upcoming Shows and choose Enter Show. Select the exhibitor, show section and animals, then review your cart and complete submission. Open My Entries afterward to confirm your entries.',
  'How do I find a show’s entry deadline?':
      'Look at the show’s listing for its displayed entry deadline and any entry-closed notice. Check the timezone notice in RingMaster when comparing dates and times. Contact the secretary if the deadline is unclear.',
  'Where can I see my submitted entries?':
      'Open My Entries and expand the show. Check that the intended animals and sections are listed for the correct exhibitor. Items still in your cart are not submitted entries.',
  'How do I check my entries?':
      'Open My Entries, expand the show, and review the animals and sections listed for your exhibitor. Check your household selection if something is missing. Saving an animal or leaving it in the cart does not submit an entry.',
};

String? assistantPreparedAnswer(String question) {
  final normalized = question
      .trim()
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAll(RegExp(r'[?!.]+$'), '');
  for (final entry in assistantPreparedAnswers.entries) {
    if (entry.key
            .toLowerCase()
            .replaceAll('’', "'")
            .replaceAll(RegExp(r'[?!.]+$'), '') ==
        normalized) {
      return entry.value;
    }
  }
  return null;
}
