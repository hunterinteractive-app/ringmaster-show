import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/config/convention_demo.dart';

void main() {
  test('demo build rejects a hosted API', () {
    expect(ConventionDemo.enabled, isTrue);
    expect(
      () => ConventionDemo.validate(
        'https://production.supabase.co',
        Uri.parse('http://127.0.0.1:8787'),
      ),
      throwsStateError,
    );
  }, skip: !ConventionDemo.enabled);
  test('demo build rejects a hosted frontend', () {
    expect(
      () => ConventionDemo.validate(
        'http://127.0.0.1:55321',
        Uri.parse('https://show.ringmasterone.com'),
      ),
      throwsStateError,
    );
  }, skip: !ConventionDemo.enabled);
  test('demo build accepts only local services', () {
    expect(
      () => ConventionDemo.validate(
        'http://127.0.0.1:55321',
        Uri.parse('http://127.0.0.1:8787'),
      ),
      returnsNormally,
    );
  }, skip: !ConventionDemo.enabled);
}
