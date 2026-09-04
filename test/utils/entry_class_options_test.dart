import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/utils/entry_class_options.dart';

void main() {
  group('allowedEntryClassOptions', () {
    test('four-class rabbits without pre-junior use Junior and Senior', () {
      expect(
        allowedEntryClassOptions(
          species: 'rabbit',
          classSystem: 'four',
          hasPreJunior: false,
        ),
        ['Junior', 'Senior'],
      );
    });

    test('six-class rabbits include Intermediate', () {
      expect(
        allowedEntryClassOptions(
          species: 'rabbit',
          classSystem: 'six_class',
          hasPreJunior: false,
        ),
        ['Junior', 'Intermediate', 'Senior'],
      );
    });

    test('pre-junior is offered only when configured', () {
      expect(
        allowedEntryClassOptions(
          species: 'rabbit',
          classSystem: 'four',
          hasPreJunior: true,
        ),
        ['Pre-Junior', 'Junior', 'Senior'],
      );
    });

    test('cavies retain their three age classes', () {
      expect(
        allowedEntryClassOptions(
          species: 'cavy',
          classSystem: 'four',
          hasPreJunior: true,
        ),
        ['Junior', 'Intermediate', 'Senior'],
      );
    });
  });
}
