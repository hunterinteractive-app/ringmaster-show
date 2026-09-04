import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/utils/entry_discount.dart';

void main() {
  group('calculatePerEntryDiscount', () {
    test('supports fixed rate, amount, and percent pricing', () {
      expect(
        calculatePerEntryDiscount(
          entryFee: 6,
          discountType: 'fixed_rate',
          discountValue: 4,
        ),
        2,
      );
      expect(
        calculatePerEntryDiscount(
          entryFee: 6,
          discountType: 'amount',
          discountValue: 1.5,
        ),
        1.5,
      );
      expect(
        calculatePerEntryDiscount(
          entryFee: 6,
          discountType: 'percent',
          discountValue: 25,
        ),
        1.5,
      );
    });

    test('never discounts below zero or above the entry fee', () {
      expect(
        calculatePerEntryDiscount(
          entryFee: 4,
          discountType: 'amount',
          discountValue: 10,
        ),
        4,
      );
      expect(
        calculatePerEntryDiscount(
          entryFee: 4,
          discountType: 'fixed_rate',
          discountValue: 8,
        ),
        0,
      );
    });
  });

  test('selectBetterDiscount chooses one discount without stacking', () {
    expect(selectBetterDiscount(4, 6), 6);
    expect(selectBetterDiscount(6, 4), 6);
    expect(selectBetterDiscount(-1, 3), 3);
  });

  group('isCanadianExhibitorAddress', () {
    test('accepts province codes and names', () {
      expect(isCanadianExhibitorAddress(stateOrProvince: 'ON'), isTrue);
      expect(
        isCanadianExhibitorAddress(stateOrProvince: 'British Columbia'),
        isTrue,
      );
      expect(isCanadianExhibitorAddress(stateOrProvince: 'Québec'), isTrue);
    });

    test('accepts Canadian postal codes when province is absent', () {
      expect(isCanadianExhibitorAddress(postalCode: 'K1A 0B1'), isTrue);
      expect(isCanadianExhibitorAddress(postalCode: 'V6B-1A1'), isTrue);
    });

    test('does not mistake a US state or ZIP code for Canada', () {
      expect(
        isCanadianExhibitorAddress(stateOrProvince: 'CA', postalCode: '90210'),
        isFalse,
      );
    });
  });
}
