@TestOn('browser')
library;

import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;
import 'package:flutter/rendering.dart';
import 'package:ringmaster_show/widgets/exhibitor_builder_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/enter_show_screen.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

void main() {
  final captureKey = GlobalKey();
  const owner = 'aaaaaaaa-0000-4000-8000-000000000001';
  var youthAvailable = true;
  var groupYouth = false;
  final writes = <String>[];
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://youth-fixture.invalid',
      anonKey: 'fixture',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((req) async {
        final path = req.url.path.split('/').last;
        if (req.method != 'GET' &&
            !req.url.path.contains('/rpc/') &&
            path != 'animal-sync') {
          writes.add(path);
        }
        Object? data = [];
        if (path == 'shows') {
          data = {
            'id': 'show',
            'start_date': '2099-12-01',
            'owner_user_id': 'secretary',
            'entry_open_at': '2020-01-01',
            'entry_close_at': '2099-11-30',
          };
        }
        if (path == 'get_show_addons') data = {'items': []};
        if (path == 'show_payment_settings' || path == 'entry_carts') {
          data = null;
        }
        if (path == 'breeds') {
          data = [
            {
              'id': 'rex',
              'name': 'Rex',
              'species': 'rabbit',
              'class_system': 'four',
              'is_active': true,
            },
          ];
        }
        if (path == 'exhibitors') {
          data = [
            {'id': 'adult', 'showing_name': 'Adult Exhibitor', 'type': 'adult'},
            if (youthAvailable) ...[
              {
                'id': 'youth-1',
                'showing_name': 'Youth One',
                'type': groupYouth ? 'group' : 'youth',
                'group_shows_as_youth': groupYouth,
              },
              {'id': 'youth-2', 'showing_name': 'Youth Two', 'type': 'youth'},
            ],
          ];
        }
        if (path == 'show_sections') {
          data = [
            for (final kind in ['open', 'youth'])
              for (final letter in ['A', 'B'])
                {
                  'id': '$kind-$letter',
                  'kind': kind,
                  'letter': letter,
                  'is_enabled': true,
                  'breed_scope': 'all',
                  'sort_order': 0,
                },
          ];
        }
        if (path == 'animals') {
          data = [
            {
              'id': 'rabbit',
              'species': 'rabbit',
              'name': 'Sample Rabbit',
              'tattoo': 'T1',
              'breed': 'Rex',
              'variety': 'Black',
              'sex': 'Buck',
              'birth_date': '2098-01-01',
              'is_dob_unknown': false,
            },
          ];
        }
        return http.Response(
          jsonEncode(data),
          200,
          request: req,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    String encode(Object o) =>
        base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
    final exp =
        DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch ~/
        1000;
    await Supabase.instance.client.auth.recoverSession(
      jsonEncode({
        'access_token':
            '${encode({'alg': 'HS256'})}.${encode({'sub': owner, 'exp': exp, 'role': 'authenticated'})}.fixture',
        'refresh_token': 'fixture',
        'token_type': 'bearer',
        'expires_at': exp,
        'expires_in': 7200,
        'user': {
          'id': owner,
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
          'app_metadata': {},
          'user_metadata': {},
        },
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  Future<void> mount(WidgetTester tester, double width) async {
    writes.clear();
    await tester.runAsync(() async {
      const font = String.fromEnvironment('YOUTH_FONT_BASE64');
      if (font.isNotEmpty) {
        final previous = ui_web.TestEnvironment.instance;
        ui_web.TestEnvironment.setUp(
          ui_web.TestEnvironment(
            ignorePlatformMessages: previous.ignorePlatformMessages,
            disableFontFallbacks: previous.disableFontFallbacks,
            keepSemanticsDisabledOnUpdate:
                previous.keepSemanticsDisabledOnUpdate,
            defaultToTestUrlStrategy: previous.defaultToTestUrlStrategy,
          ),
        );
        addTearDown(() => ui_web.TestEnvironment.setUp(previous));
        const icons = String.fromEnvironment('YOUTH_ICONS_BASE64');
        if (icons.isNotEmpty) {
          await ui.loadFontFromList(
            base64Decode(icons),
            fontFamily: 'MaterialIcons',
          );
        }
        await ui.loadFontFromList(base64Decode(font), fontFamily: 'Roboto');
      }
    });
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const EnterShowScreen(
            showId: 'show',
            showName: 'Youth Selection Fixture',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('YOUTH_SCREENSHOT')) return;
    await tester.runAsync(() async {
      final boundary =
          captureKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      // Synthetic fixture only; optional local visual QA, never customer data.
      // ignore: avoid_print
      print('YOUTH_PNG_$name:${base64Encode(bytes!.buffer.asUint8List())}');
      image.dispose();
    });
  }

  Finder exhibitorField() => find.byWidgetPredicate(
    (w) =>
        w is DropdownButtonFormField<String> &&
        (w.key?.toString().contains('entry-exhibitor') ?? false),
  );
  Future<void> section(WidgetTester tester, String label) async {
    final chip = find.widgetWithText(FilterChip, label);
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  for (final width in [390.0, 1200.0]) {
    testWidgets(
      'Youth A/B keeps eligible exhibitor and reaches review at $width',
      (tester) async {
        youthAvailable = true;
        groupYouth = false;
        await mount(tester, width);
        expect(
          tester.state<FormFieldState<String>>(exhibitorField()).value,
          'adult',
        );
        await section(tester, 'Youth A');
        expect(
          tester.state<FormFieldState<String>>(exhibitorField()).value,
          'youth-1',
        );
        expect(
          find.text(
            'Youth sections selected. Only youth exhibitors may be used.',
          ),
          findsNothing,
        );
        expect(
          find.text(
            'Youth sections selected. Please choose a youth exhibitor.',
          ),
          findsNothing,
        );
        final notice = find.text(
          'Youth exhibitor selected. Choose your animals below.',
        );
        expect(notice, findsOneWidget);
        await Scrollable.ensureVisible(
          tester.element(exhibitorField()),
          alignment: .5,
        );
        await tester.pumpAndSettle();
        if (width == 390) await capture(tester, 'valid');
        final text = tester.widget<Text>(notice);
        final color = text.style!.color!;
        final luminance = color.computeLuminance();
        expect(
          (AppColors.surface.computeLuminance() + .05) / (luminance + .05),
          greaterThanOrEqualTo(4.5),
        );
        await Scrollable.ensureVisible(
          tester.element(exhibitorField()),
          alignment: .5,
        );
        await tester.pumpAndSettle();
        await tester.tap(exhibitorField());
        await tester.pumpAndSettle();
        expect(find.text('Adult Exhibitor'), findsNothing);
        await tester.tap(find.text('Youth Two').last);
        await tester.pumpAndSettle();
        await section(tester, 'Youth B');
        expect(
          tester.state<FormFieldState<String>>(exhibitorField()).value,
          'youth-2',
        );
        final animal = find.byType(Checkbox).first;
        await tester.ensureVisible(animal);
        await tester.tap(animal);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add Selected to Cart'));
        await tester.pumpAndSettle();
        expect(find.text('Review Entry Summary'), findsOneWidget);
        expect(find.text('Exhibitor: Youth Two'), findsOneWidget);
        expect(find.text('Sections selected: 2'), findsOneWidget);
        if (width == 390) await capture(tester, 'review');
        expect(writes, isEmpty);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('adult-only household cannot use youth and recovers on Open', (
    tester,
  ) async {
    youthAvailable = false;
    groupYouth = false;
    await mount(tester, 390);
    await section(tester, 'Youth A');
    expect(
      tester.state<FormFieldState<String>>(exhibitorField()).value,
      isNull,
    );
    expect(
      find.text('Add a youth exhibitor to enter Youth sections.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Add Selected to Cart'));
    await tester.pumpAndSettle();
    expect(find.text('Select an exhibitor.'), findsOneWidget);
    await capture(tester, 'validation');
    expect(find.text('Review Entry Summary'), findsNothing);
    expect(writes, isEmpty);
    await section(tester, 'Youth A');
    await section(tester, 'Open A');
    expect(
      tester.state<FormFieldState<String>>(exhibitorField()).value,
      'adult',
    );
    expect(
      find.text('Add a youth exhibitor to enter Youth sections.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('new youth exhibitor stays selected after refresh and rebuild', (
    tester,
  ) async {
    youthAvailable = false;
    groupYouth = false;
    await mount(
      tester,
      const bool.fromEnvironment('YOUTH_SCREENSHOT') ? 390 : 1200,
    );
    await section(tester, 'Youth A');
    final add = find.widgetWithText(OutlinedButton, 'Add Exhibitor');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(find.byType(ExhibitorBuilderDialog), findsOneWidget);
    await capture(tester, 'add_exhibitor');
    final scroll = find.descendant(
      of: find.byType(ExhibitorBuilderDialog),
      matching: find.byType(SingleChildScrollView),
    );
    await tester.drag(scroll, const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Simulate the dialog returning a saved record; no live records are written.
    youthAvailable = true;
    Navigator.of(
      tester.element(find.byType(ExhibitorBuilderDialog)),
    ).pop({'id': 'youth-2'});
    await tester.pumpAndSettle();
    expect(
      tester.state<FormFieldState<String>>(exhibitorField()).value,
      'youth-2',
    );
    await section(tester, 'Youth B');
    expect(
      tester.state<FormFieldState<String>>(exhibitorField()).value,
      'youth-2',
    );
    expect(writes, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('youth group remains eligible', (tester) async {
    youthAvailable = true;
    groupYouth = true;
    await mount(tester, 390);
    await section(tester, 'Youth A');
    expect(
      tester.state<FormFieldState<String>>(exhibitorField()).value,
      'youth-1',
    );
    expect(
      find.text('Youth exhibitor selected. Choose your animals below.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
