import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/models/show_addon.dart';

void main() {
  test(
    'registration dates inherit by default and custom ranges round trip in UTC',
    () {
      final item = ShowAddon(kind: 'contest');
      expect(item.useShowEntryDates, isTrue);
      expect(item.validateRegistrationWindow(), isNull);
      item.useShowEntryDates = false;
      expect(item.validateRegistrationWindow(), isNotNull);
      item.registrationOpenAt = DateTime.parse('2026-11-01T01:30:00-04:00');
      item.registrationCloseAt = DateTime.parse('2026-11-01T01:30:00-05:00');
      expect(item.validateRegistrationWindow(), isNull);
      final restored = ShowAddon.fromJson(item.toJson());
      expect(
        restored.registrationCloseAt!.difference(restored.registrationOpenAt!),
        const Duration(hours: 1),
      );
      restored.registrationCloseAt = restored.registrationOpenAt;
      expect(restored.validateRegistrationWindow(), isNotNull);
      item.useShowEntryDates = true;
      expect(item.toJson()['registration_open_at'], isNull);
      expect(item.toJson()['registration_close_at'], isNull);
    },
  );
  test('prices use exact cents and reject ambiguous or out-of-range input', () {
    expect(addonPriceCents('0'), 0);
    expect(addonPriceCents('5.5'), 550);
    expect(addonPriceCents(' 12.34 '), 1234);
    expect(addonPriceCents('99999.99'), 9999999);
    for (final input in ['', '-5', '1.005', '1e3', 'NaN', '100000', '1,000']) {
      expect(addonPriceCents(input), isNull, reason: input);
    }
  });
  test(
    'contest answers validate required choices, dates and acknowledgments',
    () {
      final choice = ContestField(
        label: 'Division',
        type: 'select',
        required: true,
        options: ['Junior', 'Senior'],
      );
      expect(choice.validate(null), isNotNull);
      expect(choice.validate('Unknown'), isNotNull);
      expect(choice.validate('Junior'), isNull);
      final date = ContestField(label: 'Birth date', type: 'date');
      expect(date.validate(''), isNull);
      expect(date.validate('2026-02-30'), isNotNull);
      expect(date.validate('2024-02-29'), isNull);
      expect(date.validate('9/16/2026'), isNotNull);
      final acknowledgment = ContestField(
        label: 'Agree',
        type: 'checkbox',
        required: true,
      );
      expect(acknowledgment.validate(false), isNotNull);
      expect(acknowledgment.validate(true), isNull);
      expect(
        ContestField(label: 'Age', type: 'number').validate('12 years'),
        isNotNull,
      );
    },
  );
}
