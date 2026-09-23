import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/super_admin/assistant_answers_screen.dart';

void main() {
  testWidgets('publishing requires renewed review after edits', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000,1200));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home:AssistantAnswerEditor(draft:{'id':'draft','version':1,'question':'How do I enter a show?','answer':'Open Upcoming Shows, then choose Enter Show.','aliases':<String>[],'published_at':null})));
    await tester.pumpAndSettle();
    final publish=find.widgetWithText(FilledButton,'Approve and publish');
    expect(tester.widget<FilledButton>(publish).onPressed,isNull);
    await tester.tap(find.byType(CheckboxListTile).last);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(publish).onPressed,isNotNull);
    await tester.enterText(find.byType(TextField).first,'How can I enter a show?');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(publish).onPressed,isNull);
    expect(tester.takeException(),isNull);
  });
}
