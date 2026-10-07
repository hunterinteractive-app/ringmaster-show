import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/widgets/show_list_header.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

void main() {
  for (final width in [320.0, 390.0, 600.0, 1200.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('home header fits $width with text scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Builder(
              builder: (context) {
                final height = ShowListHeader.heightFor(
                  context,
                  demoMode: true,
                );
                return Scaffold(
                  appBar: PreferredSize(
                    preferredSize: Size.fromHeight(height),
                    child: ShowListHeader(
                      height: height,
                      demoMode: true,
                      actions: [
                        for (final name in [
                          'Secretary',
                          'Superintendent',
                          'Animals',
                          'More',
                        ])
                          IconButton(
                            tooltip: name,
                            onPressed: () {},
                            icon: const Icon(Icons.pets),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final text in ['RingMaster Show', 'Demo Mode — RingMaster Show']) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(text),
          );
          expect(paragraph.didExceedMaxLines, isFalse);
          expect(paragraph.size.width, greaterThan(150));
          final rect = tester.getRect(find.text(text));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
        }
        await tester.tap(find.byTooltip('More'));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
