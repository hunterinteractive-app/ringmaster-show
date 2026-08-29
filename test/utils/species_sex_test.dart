import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/utils/species_sex.dart';

void main() {
  group('cavy sex presentation', () {
    test('maps legacy and current male labels to Boar', () {
      for (final value in ['Buck', 'Boar', 'Male', 'B']) {
        expect(displaySexForSpecies(species: 'cavy', sex: value), 'Boar');
      }
    });

    test('maps legacy and current female labels to Sow', () {
      for (final value in ['Doe', 'Sow', 'Female', 'D', 'F']) {
        expect(displaySexForSpecies(species: 'cavy', sex: value), 'Sow');
      }
    });

    test('uses a legacy class label when the sex field is empty', () {
      expect(
        displaySexForSpecies(species: 'cavy', sex: '', className: 'Junior Doe'),
        'Sow',
      );
    });

    test('prefers the explicit sex when a class label is inconsistent', () {
      expect(
        displaySexForSpecies(
          species: 'cavy',
          sex: 'Doe',
          className: 'Senior Buck',
        ),
        'Sow',
      );
    });

    test('rewrites sex terms embedded in cavy class labels', () {
      expect(
        displayClassNameForSpecies(species: 'cavy', className: 'Senior Buck'),
        'Senior Boar',
      );
      expect(
        displayClassNameForSpecies(species: 'cavy', className: 'Junior Does'),
        'Junior Sows',
      );
    });

    test('does not alter rabbit terminology', () {
      expect(displaySexForSpecies(species: 'rabbit', sex: 'Buck'), 'Buck');
      expect(
        displayClassNameForSpecies(species: 'rabbit', className: 'Senior Doe'),
        'Senior Doe',
      );
    });

    test('normalizes report rows using alternate species keys', () {
      final row = <String, dynamic>{
        'entry_species': 'cavy',
        'sex': 'Doe',
        'class_name': 'Junior Doe',
      };

      normalizeSpeciesSexPresentation(row);

      expect(row['sex'], 'Sow');
      expect(row['class_name'], 'Junior Sow');
    });
  });
}
