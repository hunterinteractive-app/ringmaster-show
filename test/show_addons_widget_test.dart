// Run on Chrome: the shared page shell imports the web payment flow.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/models/show_addon.dart';
import 'package:ringmaster_show/screens/admin/show_addon_settings_screen.dart';
import 'package:ringmaster_show/screens/show_addons_screen.dart';
import 'package:ringmaster_show/services/show_addon_service.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:ringmaster_show/services/household_session.dart';

void main() {
  Map<String, dynamic>? saved;
  Map<String, dynamic>? registration;
  String? animalExhibitor;
  var pageFixture = false;
  var registrationStatus = 'open';
  var addonFixture = false;
  var deleted = false;
  var failDelete = false;
  Map<String, dynamic>? deletion;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://fixture.invalid',
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        Object? response;
        final path = request.url.path;
        if (request.url.path.endsWith('/save_show_addon')) {
          saved = Map<String, dynamic>.from(jsonDecode(request.body)['p_item']);
        }
        if (addonFixture && path.endsWith('/get_show_addons')) {
          response = {
            'extras_enabled': true,
            'currency': 'usd',
            'items': [
              if (!deleted)
                ShowAddon(
                  id: 'ticket',
                  kind: 'extra',
                  name: 'Banquet Ticket',
                ).toJson(),
            ],
          };
        }
        if (path.endsWith('/delete_show_addon')) {
          deletion = Map<String, dynamic>.from(jsonDecode(request.body));
          if (failDelete) {
            return http.Response(
              jsonEncode({
                'message': 'This show is locked or finalized.',
                'code': 'P0001',
              }),
              400,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          deleted = true;
        }
        if (pageFixture) {
          if (path.endsWith('/get_show_addons')) {
            response = {
              'currency': 'usd',
              'items': [
                ShowAddon(
                  id: 'contest',
                  kind: 'contest',
                  name: 'Showmanship',
                  divisions: ['Junior', 'Senior'],
                  animalSelection: 'required',
                ).toJson()..addAll({'registration_status': registrationStatus}),
              ],
            };
          }
          if (path.endsWith('/get_cart_addons') ||
              path.endsWith('/get_contest_drafts')) {
            response = [];
          }
          if (path.endsWith('/exhibitors')) {
            response = [
              {
                'id': 'ex1',
                'display_name': 'First Exhibitor',
                'exhibitor_number': 101,
              },
              {
                'id': 'ex2',
                'display_name': 'Second Exhibitor',
                'exhibitor_number': 102,
              },
            ];
          }
          if (path.endsWith('/get_contest_animals')) {
            animalExhibitor = jsonDecode(request.body)['p_exhibitor_id'];
            response = [
              {
                'key': 'animal-$animalExhibitor',
                'label': animalExhibitor == 'ex1'
                    ? 'Dutch • Ear #: A1'
                    : 'American • Ear #: B2',
              },
            ];
          }
          if (path.endsWith('/save_cart_addon') ||
              path.endsWith('/save_contest_registration')) {
            registration = Map<String, dynamic>.from(jsonDecode(request.body));
          }
        }
        return http.Response(
          jsonEncode(response),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() {
    saved = null;
    registration = null;
    animalExhibitor = null;
    pageFixture = false;
    registrationStatus = 'open';
    addonFixture = false;
    deleted = false;
    failDelete = false;
    deletion = null;
    HouseholdSession.selection.value = null;
  });
  Future<void> size(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'add-on deletion confirms, cancels, and refreshes after success',
    (tester) async {
      addonFixture = true;
      await size(tester, 430);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const ShowAddonSettingsScreen(
            showId: 'show',
            showName: 'Test Show',
            kind: 'extra',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byTooltip('Add-on options'));
      await tapVisible(tester, find.text('Delete'));
      expect(
        find.textContaining(
          'Existing orders and payment history will be kept.',
        ),
        findsOneWidget,
      );
      await tapVisible(tester, find.text('Cancel'));
      expect(deletion, isNull);
      expect(find.text('Banquet Ticket'), findsOneWidget);
      await tapVisible(tester, find.byTooltip('Add-on options'));
      await tapVisible(tester, find.text('Delete'));
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Delete'));
      expect(deletion, {'p_show_id': 'show', 'p_offering_id': 'ticket'});
      expect(find.text('Banquet Ticket'), findsNothing);
      expect(find.text('No add-ons added yet.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed add-on deletion keeps the offering and reports the error',
    (tester) async {
      addonFixture = true;
      failDelete = true;
      await size(tester, 430);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const ShowAddonSettingsScreen(
            showId: 'show',
            showName: 'Test Show',
            kind: 'extra',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byTooltip('Add-on options'));
      await tapVisible(tester, find.text('Delete'));
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Delete'));
      expect(find.text('Banquet Ticket'), findsOneWidget);
      expect(
        find.textContaining('This show is locked or finalized.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'template applies on mobile and can be customized before saving',
    (tester) async {
      await size(tester, 430);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: ShowAddonEditorScreen(
            showId: 'show',
            currency: 'usd',
            item: ShowAddon(kind: 'contest'),
            service: ShowAddonService(),
          ),
        ),
      );
      await tapVisible(
        tester,
        find.widgetWithText(ActionChip, 'Rabbit/Cavy Costume Contest'),
      );
      expect(saved, isNull);
      expect(
        find.widgetWithText(TextFormField, 'Rabbit/Cavy Costume Contest'),
        findsOneWidget,
      );
      expect(find.text('Costume category'), findsOneWidget);
      expect(find.text('Required animal selection'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Contest name'),
        'My Costume Contest',
      );
      await tapVisible(tester, find.text('Save'));
      expect(saved?['name'], 'My Costume Contest');
      expect(saved?['price_cents'], 0);
      expect(saved?['animal_selection'], 'required');
      expect(saved?['requires_animal_entry'], true);
      expect(saved?['use_show_entry_dates'], true);
      expect((saved?['fields'] as List).first, containsPair('required', true));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'replacing template needs confirmation and preserves price and dates',
    (tester) async {
      await size(tester, 430);
      final opening = DateTime.utc(2030, 5, 1, 12);
      final closing = DateTime.utc(2030, 5, 3, 12);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: ShowAddonEditorScreen(
            showId: 'show',
            currency: 'usd',
            item: ShowAddon(
              kind: 'contest',
              name: 'Existing contest',
              priceCents: 725,
              enabled: false,
              requiresAnimalEntry: true,
              animalSelection: 'required',
              useShowEntryDates: false,
              registrationOpenAt: opening,
              registrationCloseAt: closing,
              fields: [ContestField(label: 'Original field')],
            ),
            service: ShowAddonService(),
          ),
        ),
      );
      await tapVisible(
        tester,
        find.widgetWithText(ActionChip, 'Rabbit Judging (Individual)'),
      );
      expect(find.text('Replace contest details?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextFormField, 'Existing contest'),
        findsOneWidget,
      );
      expect(find.text('Original field'), findsOneWidget);
      await tapVisible(
        tester,
        find.widgetWithText(ActionChip, 'Rabbit Judging (Individual)'),
      );
      await tester.tap(find.text('Use Template'));
      await tester.pumpAndSettle();
      expect(find.text('Not used for this contest'), findsNothing);
      expect(find.text('Original field'), findsNothing);
      await tapVisible(tester, find.text('Save'));
      expect(saved?['name'], 'Rabbit Judging (Individual)');
      expect(saved?['animal_selection'], 'none');
      expect(saved?['requires_animal_entry'], false);
      expect(saved?['divisions'], ['Junior', 'Intermediate', 'Senior']);
      expect(saved?['price_cents'], 725);
      expect(saved?['enabled'], false);
      expect(saved?['use_show_entry_dates'], false);
      expect(DateTime.parse(saved!['registration_open_at']), opening);
      expect(DateTime.parse(saved!['registration_close_at']), closing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('custom window uses local date/time pickers and saves UTC', (
    tester,
  ) async {
    await size(tester, 430);
    final opening = DateTime.utc(2030, 5, 1, 12);
    final closing = DateTime.utc(2030, 5, 3, 12);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: ShowAddonEditorScreen(
          showId: 'show',
          currency: 'usd',
          item: ShowAddon(kind: 'contest', name: 'Window test'),
          service: ShowAddonService(),
          showEntryOpenAt: opening,
          showEntryCloseAt: closing,
        ),
      ),
    );
    expect(find.text('Set opening'), findsNothing);
    await tapVisible(tester, find.text('Use show entry dates'));
    expect(find.text('Set opening'), findsOneWidget);
    await tapVisible(tester, find.text('Set opening'));
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Save'));
    expect(saved?['use_show_entry_dates'], false);
    expect(DateTime.parse(saved!['registration_open_at']), opening);
    expect(DateTime.parse(saved!['registration_close_at']), closing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid custom dates block saving; default clears overrides', (
    tester,
  ) async {
    await size(tester, 1200);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: ShowAddonEditorScreen(
          showId: 'show',
          currency: 'usd',
          item: ShowAddon(
            kind: 'contest',
            name: 'Window test',
            useShowEntryDates: false,
            registrationOpenAt: DateTime.utc(2030, 5, 3),
            registrationCloseAt: DateTime.utc(2030, 5, 1),
          ),
          service: ShowAddonService(),
        ),
      ),
    );
    await tapVisible(tester, find.text('Save'));
    expect(saved, isNull);
    expect(
      find.text('Registration must close after it opens.'),
      findsOneWidget,
    );
    await tapVisible(tester, find.text('Use show entry dates'));
    await tapVisible(tester, find.text('Save'));
    expect(saved?['use_show_entry_dates'], true);
    expect(saved?['registration_open_at'], isNull);
    expect(saved?['registration_close_at'], isNull);
  });

  testWidgets(
    'secretary sets a fee, animal requirement and required dropdown',
    (tester) async {
      await size(tester, 1200);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: ShowAddonEditorScreen(
            showId: 'show',
            currency: 'usd',
            item: ShowAddon(kind: 'contest'),
            service: ShowAddonService(),
          ),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Contest name'),
        'Rabbit Showmanship',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Entry fee (USD)'),
        '5.25',
      );
      await tapVisible(tester, find.text('Additional setup options'));
      await tapVisible(tester, find.widgetWithText(FilterChip, 'Junior'));
      await tapVisible(tester, find.widgetWithText(FilterChip, 'Senior'));
      await tapVisible(
        tester,
        find.widgetWithText(
          DropdownButtonFormField<String>,
          'Choose an entered animal',
        ),
      );
      await tester.tap(find.text('Required animal selection').last);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Require an animal entry'));
      await tapVisible(tester, find.text('Add Question'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Question'),
        'Division',
      );
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'Answer format'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dropdown').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Choices (one per line)'),
        'Junior\nSenior',
      );
      await tester.tap(find.text('Required'));
      await tapVisible(tester, find.text('Save Question'));
      expect(find.text('Division'), findsOneWidget);
      await tapVisible(tester, find.text('Save'));
      expect(saved?['price_cents'], 525);
      expect(saved?['requires_animal_entry'], true);
      expect(saved?['max_per_exhibitor'], 1);
      expect(saved?['divisions'], ['Junior', 'Senior']);
      expect(saved?['animal_selection'], 'required');
      expect((saved?['fields'] as List).single, containsPair('required', true));
      expect(
        (saved?['fields'] as List).single,
        containsPair('options', ['Junior', 'Senior']),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'suggested extra supports custom name, exact price and limit on mobile',
    (tester) async {
      await size(tester, 430);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: ShowAddonEditorScreen(
            showId: 'show',
            currency: 'usd',
            item: ShowAddon(kind: 'extra', maxPerExhibitor: 99),
            service: ShowAddonService(),
          ),
        ),
      );
      await tapVisible(tester, find.text('Banquet Ticket'));
      expect(
        find.widgetWithText(TextFormField, 'Banquet Ticket'),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Item name'),
        'Saturday Banquet',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Unit price (USD)'),
        '12.34',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Maximum quantity per exhibitor'),
        '4',
      );
      await tapVisible(tester, find.text('Save'));
      expect(saved?['name'], 'Saturday Banquet');
      expect(saved?['price_cents'], 1234);
      expect(saved?['max_per_exhibitor'], 4);
      expect(saved?['fields'], isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'entry form requires configured answers before returning cart values',
    (tester) async {
      await size(tester, 430);
      AddonEntryValues? result;
      final item = ShowAddon(
        kind: 'contest',
        name: 'Costume Contest',
        priceCents: 500,
        fields: [
          ContestField(
            id: 'category',
            label: 'Category',
            type: 'select',
            required: true,
            options: ['Funny', 'Creative'],
          ),
          ContestField(
            id: 'agree',
            label: 'I accept the contest rules',
            type: 'checkbox',
            required: true,
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showDialog<AddonEntryValues>(
                    context: context,
                    builder: (_) =>
                        AddonEntryDialog(item: item, currency: 'usd'),
                  );
                },
                child: const Text('Register'),
              ),
            ),
          ),
        ),
      );
      await tapVisible(tester, find.text('Register'));
      await tapVisible(tester, find.text('Add to Cart'));
      expect(find.text('Category is required.'), findsOneWidget);
      expect(
        tester
            .widget<AlertDialog>(find.byType(AlertDialog))
            .titleTextStyle
            ?.color,
        AppColors.text,
      );
      expect(
        tester
            .widget<AlertDialog>(find.byType(AlertDialog))
            .contentTextStyle
            ?.color,
        AppColors.text,
      );
      expect(
        find.text('I accept the contest rules is required.'),
        findsOneWidget,
      );
      expect(result, isNull);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Creative').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('I accept the contest rules *'));
      await tapVisible(tester, find.text('Add to Cart'));
      expect(result?.quantity, 1);
      expect(result?.answers, {'category': 'Creative', 'agree': true});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('extras quantity cannot exceed the configured limit', (
    tester,
  ) async {
    await size(tester, 430);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: AddonEntryDialog(
            item: ShowAddon(
              kind: 'extra',
              name: 'Parking Pass',
              priceCents: 1000,
              maxPerExhibitor: 2,
            ),
            currency: 'usd',
          ),
        ),
      ),
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Quantity'), '3');
    await tapVisible(tester, find.text('Add to Cart'));
    expect(find.text('Enter a valid quantity.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'exhibitor choice drives animal options and registration identity',
    (tester) async {
      pageFixture = true;
      HouseholdSession.selection.value = 'owner';
      await size(tester, 430);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const ShowAddonsScreen(
            cartId: 'cart',
            showId: 'show',
            showName: 'Test Show',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapVisible(
        tester,
        find.widgetWithText(DropdownButtonFormField<String>, 'For exhibitor'),
      );
      await tester.tap(find.text('Second Exhibitor • #102').last);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Register'));
      expect(animalExhibitor, 'ex2');
      expect(find.text('Exhibitor: Second Exhibitor • #102'), findsOneWidget);
      await tapVisible(tester, find.text('Add to Cart'));
      expect(find.text('Choose a division.'), findsOneWidget);
      expect(find.text('Choose an entered animal.'), findsOneWidget);
      await tapVisible(
        tester,
        find.widgetWithText(DropdownButtonFormField<String>, 'Division *'),
      );
      await tester.tap(find.text('Senior').last);
      await tester.pumpAndSettle();
      await tapVisible(
        tester,
        find.widgetWithText(
          DropdownButtonFormField<String>,
          'Entered animal *',
        ),
      );
      expect(find.text('Dutch • Ear #: A1'), findsNothing);
      await tester.tap(find.text('American • Ear #: B2').last);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Add to Cart'));
      expect(registration?['p_exhibitor_id'], 'ex2');
      expect(registration?['p_division'], 'Senior');
      expect(registration?['p_animal_key'], 'animal-ex2');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('exhibitors can see a closed contest but cannot register', (
    tester,
  ) async {
    pageFixture = true;
    registrationStatus = 'closed';
    HouseholdSession.selection.value = 'owner';
    await size(tester, 430);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const ShowAddonsScreen(
          cartId: 'cart',
          showId: 'show',
          showName: 'Test Show',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Registration has closed.'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Register'),
    );
    expect(button.onPressed, isNull);
    expect(registration, isNull);
  });

  testWidgets(
    'removed animal is not silently retained when editing registration',
    (tester) async {
      await size(tester, 430);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: AddonEntryDialog(
              item: ShowAddon(
                kind: 'contest',
                name: 'Showmanship',
                divisions: ['Junior'],
                animalSelection: 'required',
              ),
              currency: 'usd',
              existing: const {'division': 'Junior', 'animal_key': 'removed'},
              animals: const [
                {'key': 'new', 'label': 'Dutch • Ear #: A1'},
              ],
            ),
          ),
        ),
      );
      await tapVisible(tester, find.text('Add to Cart'));
      expect(find.text('Choose an entered animal.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
