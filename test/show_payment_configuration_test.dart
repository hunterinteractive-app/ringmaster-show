import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/services/show_payment_configuration_service.dart';

void main() {
  test('missing or invalid timing cannot silently become pay at show', () {
    for (final value in [null, '', 'unexpected']) {
      expect(
        () => ShowPaymentConfiguration.fromJson({'payment_timing_mode': value}),
        throwsFormatException,
      );
    }
  });
  test('preserves each explicitly saved payment timing mode', () {
    for (final mode in [
      'online_only',
      'online_or_at_show',
      'pay_at_show_only',
    ]) {
      expect(
        ShowPaymentConfiguration.fromJson({
          'payment_timing_mode': mode,
        }).paymentTimingMode,
        mode,
      );
    }
  });
}
