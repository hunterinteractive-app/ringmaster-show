import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/delivery_failure_message.dart';

void main() {
  test('explains a nonexistent recipient without exposing provider JSON', () {
    const raw = '''
{"bounce":{"diagnosticCode":["smtp; 550-5.1.1 The email account that you tried to reach does not exist"],"message":"Hard bounce"}}
''';

    expect(
      friendlyDeliveryFailureMessage(raw),
      'The recipient email account does not exist. Correct the address, then retry.',
    );
  });

  test('explains relay access denial without exposing provider JSON', () {
    const raw = '''
{"bounce":{"diagnosticCode":["smtp; 554 5.7.1 relay access denied"],"message":"General bounce"}}
''';

    expect(
      friendlyDeliveryFailureMessage(raw),
      'The recipient mail server rejected this address (relay access denied). Correct the address, then retry.',
    );
  });

  test('keeps a short plain provider error readable', () {
    expect(
      friendlyDeliveryFailureMessage('Temporary provider outage.'),
      'Temporary provider outage.',
    );
  });
}
