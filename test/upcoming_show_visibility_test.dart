import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/utils/upcoming_show_visibility.dart';

void main() {
  final opens = DateTime.parse('2026-11-15T06:01:00Z');
  final closes = DateTime.parse('2027-02-02T05:59:00Z');
  final houston = <String, dynamic>{
    'id': 'houston',
    'is_published': true,
    'entry_open_at': '2026-11-15T00:01:00-06:00',
    'entry_close_at': closes.toIso8601String(),
    'start_date': '2027-03-06',
  };

  test('Houston stays hidden until its exact Central-time opening', () {
    expect(
      visibleUpcomingShows([houston], now: DateTime.utc(2026, 11, 11)),
      isEmpty,
    );
    expect(
      visibleUpcomingShows([
        houston,
      ], now: opens.subtract(const Duration(microseconds: 1))),
      isEmpty,
    );
    expect(visibleUpcomingShows([houston], now: opens).single['id'], 'houston');
    expect(visibleUpcomingShows([houston], now: closes), hasLength(1));
    expect(
      visibleUpcomingShows([
        houston,
      ], now: closes.add(const Duration(microseconds: 1))),
      isEmpty,
    );
  });

  test('unpublished shows stay hidden even during the entry window', () {
    for (final published in [false, null]) {
      expect(
        visibleUpcomingShows([
          {...houston, 'is_published': published},
        ], now: opens),
        isEmpty,
      );
    }
  });

  test(
    'unset dates remain unrestricted; invalid dates do not enable entry',
    () {
      final undated = {
        ...houston,
        'entry_open_at': null,
        'entry_close_at': null,
      };
      expect(
        visibleUpcomingShows([undated], now: DateTime.utc(2026, 11, 11)),
        hasLength(1),
      );
      for (final field in ['entry_open_at', 'entry_close_at']) {
        expect(
          visibleUpcomingShows([
            {...undated, field: 'invalid'},
          ], now: opens),
          isEmpty,
        );
      }
    },
  );

  test(
    'open contests cannot reintroduce future, closed, or unpublished shows',
    () {
      final shows = [
        houston,
        {...houston, 'id': 'draft', 'is_published': false},
        {...houston, 'id': 'closed', 'entry_close_at': '2026-11-01T00:00:00Z'},
        {
          ...houston,
          'id': 'open',
          'entry_open_at': null,
          'start_date': '2026-12-12',
        },
      ];
      final visible = visibleUpcomingShows(
        shows,
        now: DateTime.utc(2026, 11, 11),
        contestShows: [
          for (final show in shows)
            {...show, 'contest_registration_open': true},
          {'id': 'contest-only', 'contest_registration_open': true},
        ],
      );
      expect(visible.map((show) => show['id']), ['open']);
      expect(visible.single['contest_registration_open'], true);
    },
  );

  test(
    'eligible shows retain date order and their authoritative show data',
    () {
      final visible = visibleUpcomingShows(
        [
          houston,
          {...houston, 'id': 'earlier', 'start_date': '2027-02-20'},
        ],
        now: opens,
        contestShows: [
          {
            'id': 'houston',
            'name': 'stale name',
            'contest_registration_open': true,
          },
        ],
      );
      expect(visible.map((show) => show['id']), ['earlier', 'houston']);
      expect(visible.first['contest_registration_open'], false);
      expect(visible.last['entry_open_at'], houston['entry_open_at']);
    },
  );
}
