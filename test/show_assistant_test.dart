import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/services/show_assistant_service.dart';
import 'package:ringmaster_show/widgets/show_assistant.dart';

class FakeGateway implements AssistantGateway {
  int calls = 0;
  bool fail = false;
  String? lastTopic;
  String? lastShow;
  String? lastMessage;
  @override
  bool canAsk = true;
  @override
  Future<List<Map<String, dynamic>>> shows(String query) async => [
    {'id': 'test-show', 'name': 'Autumn Show'},
  ];
  @override
  Future<Map<String, dynamic>> ask({
    required String message,
    required String conversationId,
    required String topic,
    required String page,
    String? showId,
    required List<Map<String, String>> history,
  }) async {
    calls++;
    lastTopic = topic;
    lastShow = showId;
    lastMessage = message;
    if (fail) throw Exception('offline');
    return {'answer': 'Your selected entries were checked.', 'checked': true};
  }
}

class FakeReviewedGateway extends FakeGateway implements ReviewedAnswerGateway {
  String? answer;
  bool lookupFails = false;
  @override
  Future<String?> reviewedAnswer(String question) async {
    if (lookupFails) throw Exception('offline');
    return answer;
  }
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    FakeGateway gateway, {
    String pageTitle = 'RingMaster Show',
    AssistantChatSession? chat,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: AssistantPanel(
              gateway: gateway,
              chat: chat,
              page: AssistantPage(title: pageTitle),
              onClose: () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('published answer takes precedence and avoids AI calls', (
    tester,
  ) async {
    final gateway = FakeReviewedGateway()
      ..answer = 'Reviewed setup steps for everyone.';
    await mount(tester, gateway);
    await tester.tap(find.text('How do I check my entries?'));
    await tester.pumpAndSettle();
    expect(find.text('Reviewed setup steps for everyone.'), findsOneWidget);
    expect(gateway.calls, 0);
  });
  testWidgets('reviewed lookup failure preserves free built-in answers', (
    tester,
  ) async {
    final gateway = FakeReviewedGateway()..lookupFails = true;
    await mount(tester, gateway);
    await tester.tap(find.text('How do I check my entries?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Open My Entries, expand'), findsOneWidget);
    expect(gateway.calls, 0);
  });

  testWidgets('chat and draft survive closing and reopening on another page', (
    tester,
  ) async {
    final gateway = FakeGateway();
    final chat = AssistantChatSession();
    await mount(tester, gateway, chat: chat);
    await tester.tap(find.text('How do I check my entries?'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'My follow-up draft');
    final conversationId = chat.conversationId;
    await tester.pumpWidget(const SizedBox());
    await mount(tester, gateway, chat: chat, pageTitle: 'My Entries');
    await tester.pumpAndSettle();
    expect(find.text('How do I check my entries?'), findsOneWidget);
    expect(find.text('My follow-up draft'), findsOneWidget);
    expect(chat.conversationId, conversationId);
    expect(gateway.calls, 0);
    await tester.tap(find.text('Clear chat'));
    await tester.pumpAndSettle();
    expect(chat.messages, isEmpty);
    expect(chat.draft, isEmpty);
    expect(chat.conversationId, isNot(conversationId));
  });
  test('privacy reset detaches previous chat data', () {
    final controller = ShowAssistantController.instance;
    final previous = controller.chat;
    previous.messages.add({'role': 'user', 'content': 'Private question'});
    previous.draft = 'Private draft';
    controller.resetChat();
    expect(controller.chat.messages, isEmpty);
    expect(controller.chat.draft, isEmpty);
    previous.messages.add({'role': 'assistant', 'content': 'Late response'});
    expect(controller.chat.messages, isEmpty);
  });
  testWidgets('prepared reply renders verified guide step links', (
    tester,
  ) async {
    await mount(tester, FakeGateway(), pageTitle: 'Upcoming Shows');
    await tester.tap(find.text('How do I enter a show?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Steps 26–33'), findsOneWidget);
    expect(find.textContaining('[[guide:'), findsNothing);
  });
  testWidgets('FAQ search shows prepared answers and preserves chat', (
    tester,
  ) async {
    final gateway = FakeGateway();
    await mount(tester, gateway);
    await tester.tap(find.text('How do I check my entries?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FAQ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'saving an animal');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Does saving an animal enter it in a show?'),
      100,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Does saving an animal enter it in a show?'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No. Saving an animal adds it to My Animals.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'My Animals'), findsOneWidget);
    expect(gateway.calls, 0);
    await tester.tap(find.text('Back to chat'));
    await tester.pumpAndSettle();
    expect(find.text('How do I check my entries?'), findsOneWidget);
  });
  testWidgets('suggestions follow screen context without paid calls', (
    tester,
  ) async {
    final gateway = FakeGateway();
    await mount(tester, gateway, pageTitle: 'Upcoming Shows');
    expect(find.text('How do I enter a show?'), findsOneWidget);
    expect(find.text('How do I set up show sections?'), findsNothing);
    await mount(tester, gateway, pageTitle: 'Autumn Show — Entry Cart');
    expect(
      find.text('How do I review my cart before submitting?'),
      findsOneWidget,
    );
    expect(find.text('How do I enter a show?'), findsNothing);
    await mount(tester, gateway, pageTitle: 'Show Settings');
    expect(
      find.text('How do I configure Open and Youth shows?'),
      findsOneWidget,
    );
    expect(gateway.calls, 0);
    await tester.tap(find.text('How do I set up show sections?'));
    await tester.pumpAndSettle();
    expect(gateway.calls, 0);
    expect(find.text('Help guide · No AI used'), findsNothing);
  });
  testWidgets('prepared answers work signed out and follow-ups can use AI', (
    tester,
  ) async {
    final gateway = FakeGateway()..canAsk = false;
    await mount(tester, gateway);
    await tester.tap(find.text('How do I check my entries?'));
    await tester.pumpAndSettle();
    expect(gateway.calls, 0);
    expect(find.text('Help guide · No AI used'), findsNothing);
    expect(find.widgetWithText(TextButton, 'My Entries'), findsOneWidget);
    gateway.canAsk = true;
    await mount(tester, gateway);
    await tester.enterText(
      find.byType(TextField),
      'What if the screen shows an unexpected error?',
    );
    await tester.tap(find.byTooltip('Send question'));
    await tester.pumpAndSettle();
    expect(gateway.calls, 1);
  });
  testWidgets('opening and reading built-in help never invokes AI', (
    tester,
  ) async {
    final gateway = FakeGateway();
    await mount(tester, gateway);
    await tester.tap(find.text('FAQ'));
    await tester.pump();
    expect(find.text('Frequently asked questions'), findsOneWidget);
    expect(gateway.calls, 0);
  });
  testWidgets('question sends once and renders verified answer', (
    tester,
  ) async {
    final gateway = FakeGateway();
    await mount(tester, gateway);
    await tester.enterText(
      find.byType(TextField),
      'How do I troubleshoot an unexpected message?',
    );
    await tester.tap(find.byTooltip('Send question'));
    await tester.pump();
    await tester.pump();
    expect(gateway.calls, 1);
    expect(find.text('Your selected entries were checked.'), findsOneWidget);
  });
  testWidgets(
    'record question asks for show and resumes the original question',
    (tester) async {
      final gateway = FakeGateway();
      await mount(tester, gateway);
      expect(find.text('Information I want help with'), findsNothing);
      await tester.enterText(find.byType(TextField), 'Is my entry in?');
      await tester.tap(find.byTooltip('Send question'));
      await tester.pumpAndSettle();
      expect(gateway.calls, 0);
      expect(find.textContaining('Which show is this about?'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Choose a show'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Autumn Show'));
      await tester.pumpAndSettle();
      expect(gateway.calls, 1);
      expect(gateway.lastTopic, 'entries');
      expect(gateway.lastShow, 'test-show');
      expect(gateway.lastMessage, 'Is my entry in?');
      expect(find.text('Is my entry in?'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField),
        'How do I troubleshoot an unexpected message?',
      );
      await tester.tap(find.byTooltip('Send question'));
      await tester.pumpAndSettle();
      expect(gateway.lastTopic, 'help');
    },
  );
  testWidgets('cancel show follow-up allows a new general question', (
    tester,
  ) async {
    final gateway = FakeGateway();
    await mount(tester, gateway);
    await tester.enterText(find.byType(TextField), 'Are my reports ready?');
    await tester.tap(find.byTooltip('Send question'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ask something else'));
    await tester.enterText(
      find.byType(TextField),
      'How do I troubleshoot an unexpected message?',
    );
    await tester.tap(find.byTooltip('Send question'));
    await tester.pumpAndSettle();
    expect(gateway.calls, 1);
    expect(gateway.lastTopic, 'help');
  });
  testWidgets('unavailable AI preserves guide and support', (tester) async {
    final gateway = FakeGateway()..fail = true;
    await mount(tester, gateway);
    await tester.enterText(find.byType(TextField), 'Help');
    await tester.tap(find.byTooltip('Send question'));
    await tester.pump();
    expect(find.textContaining('AI help is unavailable'), findsOneWidget);
    expect(find.text('FAQ'), findsOneWidget);
    expect(find.text('Contact support'), findsOneWidget);
  });
  testWidgets('signed-out users have help without a paid call', (tester) async {
    final gateway = FakeGateway()..canAsk = false;
    await mount(tester, gateway);
    await tester.tap(find.byTooltip('Send question'));
    await tester.pump();
    expect(gateway.calls, 0);
    expect(find.text('Contact support'), findsOneWidget);
  });
  testWidgets('mobile layout stays usable with keyboard-sized space', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 340);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, FakeGateway());
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Send question'), findsOneWidget);
    expect(find.text('Contact support'), findsOneWidget);
  });
  testWidgets('global overlay opens without upfront topic menus', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://assistant-test.example.invalid',
      anonKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
    );
    final controller = ShowAssistantController.instance;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: controller.navigatorKey,
        navigatorObservers: [controller.navigation],
        builder: (context, child) => MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: ShowAssistantOverlay(child: child!),
        ),
        home: const Scaffold(body: Text('Show screen')),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('assistant-launcher')));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.text('A friendly ring assistant'), findsOneWidget);
    expect(tester.takeException(), isNull);
    controller.close();
    await tester.pumpWidget(const SizedBox());
    await Supabase.instance.dispose();
  });
  testWidgets('capture mobile assistant preview', (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: boundary,
            child: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: AssistantPanel(
                gateway: FakeGateway(),
                page: const AssistantPage(title: 'RingMaster Show'),
                onClose: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = await Directory.systemTemp.createTemp('chester-preview-');
      try {
        final preview = File('${directory.path}/assistant.png');
        await preview.writeAsBytes(bytes!.buffer.asUint8List());
        expect(await preview.length(), greaterThan(0));
      } finally {
        image.dispose();
        await directory.delete(recursive: true);
      }
    });
  });
}
