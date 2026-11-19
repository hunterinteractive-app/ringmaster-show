import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/config/show_layout_rollout.dart';

void main() {
  test('only Super Admin opt-in can activate the private preview', () {
    final phase = ShowLayoutRollout.fromValue('super_admin_preview');
    expect(phase.canChoose(isSuperAdmin: false), isFalse);
    expect(phase.usesUpdated(isSuperAdmin: false, optedIn: true), isFalse);
    expect(phase.canChoose(isSuperAdmin: true), isTrue);
    expect(phase.usesUpdated(isSuperAdmin: true, optedIn: false), isFalse);
    expect(phase.usesUpdated(isSuperAdmin: true, optedIn: true), isTrue);
  });

  test('the public opt-in respects preference and launch overrides it', () {
    final optIn = ShowLayoutRollout.fromValue('opt_in');
    expect(optIn.canChoose(isSuperAdmin: false), isTrue);
    expect(optIn.usesUpdated(isSuperAdmin: false, optedIn: false), isFalse);
    expect(optIn.usesUpdated(isSuperAdmin: false, optedIn: true), isTrue);

    final launch = ShowLayoutRollout.fromValue('launched');
    expect(launch.canChoose(isSuperAdmin: false), isFalse);
    expect(launch.canChoose(isSuperAdmin: true), isFalse);
    expect(launch.usesUpdated(isSuperAdmin: false, optedIn: false), isTrue);

    for (final value in ['classic', 'unexpected-value']) {
      final phase = ShowLayoutRollout.fromValue(value);
      expect(phase.canChoose(isSuperAdmin: true), isFalse);
      expect(phase.usesUpdated(isSuperAdmin: true, optedIn: true), isFalse);
    }
  });
}
