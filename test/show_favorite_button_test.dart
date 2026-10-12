import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/widgets/show_favorite_button.dart';

void main() {
  testWidgets('Favorite is visible without an icon font and responds to taps', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 160,
            child: ShowFavoriteButton(selected: false, onPressed: () => taps++),
          ),
        ),
      ),
    );
    expect(find.text('Favorite'), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
    await tester.tap(find.text('Favorite'));
    expect(taps, 1);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShowFavoriteButton(selected: true, onPressed: null),
        ),
      ),
    );
    expect(find.text('Favorited'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
