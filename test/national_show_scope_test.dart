import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/base/report_request.dart';

void main() {
  group('national show report scope', () {
    test('uses the selected national section only', () {
      expect(
        reportScopeIsNationalShow(
          isNationalShow: true,
          nationalShowSectionId: 'open-b',
          sectionId: 'open-a',
          sectionIds: const ['open-a'],
        ),
        isFalse,
      );
      expect(
        reportScopeIsNationalShow(
          isNationalShow: true,
          nationalShowSectionId: 'open-b',
          sectionId: 'open-b',
        ),
        isTrue,
      );
    });

    test('recognizes a selected section inside a combined scope', () {
      expect(
        reportScopeIsNationalShow(
          isNationalShow: true,
          nationalShowSectionId: 'youth-a',
          sectionIds: const ['open-a', 'youth-a'],
        ),
        isTrue,
      );
    });

    test('keeps legacy national events working until a section is chosen', () {
      expect(reportScopeIsNationalShow(isNationalShow: true), isTrue);
      expect(
        reportScopeIsNationalShow(
          isNationalShow: false,
          nationalShowSectionId: 'open-a',
          sectionId: 'open-a',
        ),
        isFalse,
      );
    });
  });
}
