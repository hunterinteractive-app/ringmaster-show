import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/utils/entry_class_options.dart';

void main() {
  final animal = {
    'species': 'rabbit',
    'birth_date': '2026-05-31',
    'sex': 'Doe',
  };
  test('saved Havana uses age on show date', () {
    expect(
      suggestEntryClassFromDob(
        animal: animal,
        breed: {'name': 'Havana', 'class_system': 'four'},
        showDate: DateTime(2026, 9, 26),
      ),
      'Junior',
    );
    expect(
      suggestEntryClassFromDob(
        animal: animal,
        breed: {'name': 'Havana', 'class_system': 'four'},
        showDate: DateTime(2027, 1, 1),
      ),
      'Senior',
    );
  });
  test('six class uses intermediate and unknown DOB stays manual', () {
    expect(
      suggestEntryClassFromDob(
        animal: animal,
        breed: {'class_system': 'six'},
        showDate: DateTime(2027, 1, 1),
      ),
      'Intermediate',
    );
    expect(
      suggestEntryClassFromDob(
        animal: {...animal, 'is_dob_unknown': true},
        breed: {'class_system': 'six'},
        showDate: DateTime(2027, 1, 1),
      ),
      isNull,
    );
  });
  test('prejunior metadata and future DOB handled', () {
    expect(
      suggestEntryClassFromDob(
        animal: animal,
        breed: {
          'name': 'Giant Chinchilla',
          'has_prejunior': true,
          'prejunior_doe_age_max_months': 6,
        },
        showDate: DateTime(2026, 9, 26),
      ),
      'Pre-Junior',
    );
    expect(
      suggestEntryClassFromDob(
        animal: animal,
        breed: {'class_system': 'four'},
        showDate: DateTime(2026, 1, 1),
      ),
      isNull,
    );
  });
}
