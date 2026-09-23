/// One planning assignment per judging decision, not per reserve placement.
Map<String, String> finalAwardPlanningOptions(String mode) => switch (mode) {
  'four_six_bis' => const {'BEST4': 'Best 4', 'BEST6': 'Best 6', 'BIS': 'BIS'},
  'bis_ris' => const {'FINALS': 'BIS / RIS'},
  'bis_1ris_2ris' => const {'FINALS': 'BIS / RIS / 2RIS'},
  'bis_1ris_2ris_bbos' => const {'FINALS': 'BIS / RIS / 2RIS / BBOS'},
  _ => const {},
};
