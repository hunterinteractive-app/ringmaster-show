import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/entry_management_search.dart';

void main() {
  test('matches an entry by coop number', () {
    expect(
      entryManagementSearchMatches(
        entry: {'coop_number': 'O-127', 'tattoo': 'ABC'},
        exhibitorName: 'Alice Exhibitor',
        query: 'o-127',
      ),
      isTrue,
    );
  });

  test('keeps existing ear number and exhibitor searches', () {
    final entry = {'coop_number': 'Y-22', 'tattoo': 'LEFT-9'};

    expect(
      entryManagementSearchMatches(
        entry: entry,
        exhibitorName: 'Taylor Example',
        query: 'left-9',
      ),
      isTrue,
    );
    expect(
      entryManagementSearchMatches(
        entry: entry,
        exhibitorName: 'Taylor Example',
        query: 'taylor',
      ),
      isTrue,
    );
  });
}
