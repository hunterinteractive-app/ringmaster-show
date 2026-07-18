import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/utils/section_breed_scope.dart';

void main() {
  group('sectionAllowsBreed', () {
    test('all-breed and meat sections accept any breed', () {
      expect(sectionAllowsBreed({'breed_scope': 'all'}, 'Havana'), isTrue);
      expect(
        sectionAllowsBreed({'breed_scope': 'meat_only'}, 'New Zealand'),
        isTrue,
      );
    });

    test('single-breed scope only accepts its configured breed', () {
      final section = {
        'breed_scope': 'single',
        'allowed_breed_names': ['Havana'],
      };

      expect(sectionAllowsBreed(section, ' havana '), isTrue);
      expect(sectionAllowsBreed(section, 'Dutch'), isFalse);
    });

    test('selected-breeds scope accepts every configured breed only', () {
      final section = {
        'breed_scope': 'limited',
        'allowed_breed_names': ['Havana', 'Dutch'],
      };

      expect(sectionAllowsBreed(section, 'Dutch'), isTrue);
      expect(sectionAllowsBreed(section, 'Havana'), isTrue);
      expect(sectionAllowsBreed(section, 'Mini Rex'), isFalse);
    });

    test('restricted scope fails closed when configuration is empty', () {
      expect(
        sectionAllowsBreed({'breed_scope': 'single'}, 'Havana'),
        isFalse,
      );
      expect(
        sectionAllowsBreed({'breed_scope': 'unexpected'}, 'Havana'),
        isFalse,
      );
    });
  });
}
