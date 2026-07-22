import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/utils/open_youth_entry_policy.dart';

void main() {
  group('allowsSameLetterOpenYouthEntries', () {
    test('allows Beat the Heat 2026', () {
      expect(allowsSameLetterOpenYouthEntries(beatTheHeat2026ShowId), isTrue);
    });

    test('keeps the blocker for every other show', () {
      expect(
        allowsSameLetterOpenYouthEntries(
          '00000000-0000-0000-0000-000000000000',
        ),
        isFalse,
      );
    });
  });
}
