const bestOppositeFinalAwardMode = 'bis_1ris_2ris_bbos';
const bestOppositeAwardCode = 'BBOS';
const bestOppositeAwardLabel = 'Best of the Best Opposite';
const bestOppositeFinalAwardLabel =
    'Best in Show / 1st RIS / 2nd RIS / Best of the Best Opposite';

bool usesRankedReserveAwards(String mode) =>
    mode == 'bis_1ris_2ris' || mode == bestOppositeFinalAwardMode;

bool isValidFinalAwardMode(String mode) => const {
  'four_six_bis',
  'bis_ris',
  'bis_1ris_2ris',
  bestOppositeFinalAwardMode,
}.contains(mode);

String finalAwardFormatLabel(String mode) => switch (mode) {
  'bis_ris' => 'Best in Show / Reserve in Show',
  'bis_1ris_2ris' => 'Best in Show / 1st RIS / 2nd RIS',
  bestOppositeFinalAwardMode => bestOppositeFinalAwardLabel,
  _ => 'Best 4-Class / Best 6-Class / Best in Show',
};
