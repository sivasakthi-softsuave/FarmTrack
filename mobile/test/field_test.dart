import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmtrack/core/errors/api_exception.dart';
import 'package:farmtrack/core/models/models.dart';
import 'package:farmtrack/core/network/mock_api_client.dart';
import 'package:farmtrack/core/network/mock_data.dart';
import 'package:farmtrack/features/diary/date_words.dart';
import 'package:farmtrack/features/field/field_providers.dart';
import 'package:farmtrack/features/field/field_words.dart';
import 'package:farmtrack/core/theme/app_theme.dart';
import 'package:farmtrack/features/field/weather_glyph.dart';
import 'package:farmtrack/core/widgets/design.dart';

import 'support/feature_fakes.dart';
import 'support/finders.dart';
import 'support/harness.dart';

Future<TestEnv> fieldEnv({MockApiClient? api, String language = 'hi'}) => TestEnv.create(
  loggedIn: true,
  language: language,
  api: api ?? MockApiClient(latency: Duration.zero),
  extraOverrides: [clockProvider.overrideWithValue(() => fixedNow)],
);

/// Opens "My field" from Home; afterwards the voice log holds what the field screen said.
Future<void> openField(WidgetTester tester, TestEnv env, {double textScale = 1.0, Size? size}) async {
  useSmallPhone(tester, textScale: textScale, size: size ?? const Size(360, 640));
  await pumpApp(tester, env, location: '/home');
  env.voice.clear();
  await tapKey(tester, 'home-field');
}

RiskOut risk(String id, Severity level) => RiskOut(
  id: id,
  level: level,
  title: LocalizedText.pair(en: 'Title $id', hi: 'शीर्षक $id'),
  text: LocalizedText.pair(en: 'Text $id.', hi: 'लिखा $id।'),
);

FieldOut fieldWith({
  ReadingsOut? readings,
  List<RiskOut> risks = const [],
  bool stale = false,
  List<ForecastDayOut>? forecast,
  String spokenEn = 'Some summary.',
  String spokenHi = 'कुछ सार।',
}) => FieldOut(
  stationId: 'ST08',
  village: 'Kotgarh',
  asOf: DateTime.utc(2026, 5, 12, 2, 30),
  stale: stale,
  readings: readings,
  forecast: forecast ?? MockData.field().forecast,
  risks: risks,
  spoken: SpokenOut(
    text: LocalizedText.pair(en: spokenEn, hi: spokenHi),
  ),
);

void main() {
  group('My field', () {
    test('leaf wetness is written in whole hours from an hour on, else in minutes', () {
      expect(leafDuration(0), (number: '0', unitKey: 'field_unit_min'));
      expect(leafDuration(45), (number: '45', unitKey: 'field_unit_min'));
      expect(leafDuration(60), (number: '1', unitKey: 'field_unit_hour'));
      expect(leafDuration(340), (number: '6', unitKey: 'field_unit_hours'));
      expect(leafDuration(1500), (number: '25', unitKey: 'field_unit_hours'));
    });

    testWidgets('readings are big tiles with a word; the numbers are small and never spoken', (tester) async {
      final env = await fieldEnv();
      await openField(tester, env);

      // 17.5 degrees, 82 percent, 6.5 mm, 340 minutes, 31 percent.
      expect(find.text('अच्छा'), findsOneWidget, reason: 'pleasant');
      expect(find.text('नम'), findsOneWidget, reason: 'damp air');
      expect(find.text('हल्की बारिश'), findsWidgets, reason: 'light rain (tile and forecast days)');
      expect(find.descendant(of: keyed('reading-leaf'), matching: find.text('गीली')), findsOneWidget);
      expect(find.descendant(of: keyed('reading-soil'), matching: find.text('ठीक')), findsOneWidget);
      expect(tester.widget<Text>(keyed('reading-digits-temp')).data, '18 °C');
      expect(tester.widget<Text>(keyed('reading-digits-rain')).data, '6.5 mm');
      expect(tester.widget<Text>(keyed('reading-digits-leaf')).data, '6 घंटे', reason: '340 minutes, written in hours');
      // The warmth tile has the sun (the forecast has suns too, so look inside the tile).
      expect(find.descendant(of: keyed('reading-temp'), matching: find.byIcon(AppIcons.sun)), findsOneWidget);

      // Speech: the intro and the server's summary. No digits anywhere.
      expect(env.voice.spokenIds, ['field_intro']);
      expect(env.voice.spokenTexts, [MockData.field().spoken.text.hi]);
      expect(env.voice.log.where((s) => RegExp(r'\d').hasMatch(s)), isEmpty);
      expect(env.voice.unknownIds, isEmpty);
      expectBigTouchTargets(tester);
    });

    testWidgets('tapping a tile says its title and word, without the number', (tester) async {
      final env = await fieldEnv(language: 'en');
      await openField(tester, env);
      env.voice.clear();
      await tapKey(tester, 'reading-temp');
      expect(env.voice.spokenTexts, ['Warmth, Pleasant']);
      await tapKey(tester, 'reading-rain');
      expect(env.voice.spokenTexts.last, 'Rain, last day, Light rain');
    });

    for (final (name, readings, expected) in [
      (
        'cold, dry, no rain',
        const ReadingsOut(tempC: 2, rhPct: 30, rain24hMm: 0, leafWetnessMin: 0, soilMoisturePct: 5),
        {'temp': 'Cold', 'humidity': 'Dry', 'rain': 'No rain', 'leaf': 'Dry', 'soil': 'Dry'},
      ),
      (
        'hot, heavy rain, wet',
        const ReadingsOut(tempC: 36, rhPct: 65, rain24hMm: 25, leafWetnessMin: 120, soilMoisturePct: 55),
        {'temp': 'Hot', 'humidity': 'Normal', 'rain': 'Heavy rain', 'leaf': 'A little wet', 'soil': 'Wet'},
      ),
    ]) {
      testWidgets('the words follow the numbers: $name', (tester) async {
        final api = MockApiClient(latency: Duration.zero)..fieldOverride = fieldWith(readings: readings);
        final env = await fieldEnv(api: api, language: 'en');
        await openField(tester, env);
        for (final e in expected.entries) {
          expect(
            find.descendant(of: keyed('reading-${e.key}'), matching: find.text(e.value)),
            findsOneWidget,
            reason: e.key,
          );
        }
      });
    }

    testWidgets('a reading the server did not send has no tile', (tester) async {
      final api = MockApiClient(latency: Duration.zero)
        ..fieldOverride = fieldWith(readings: const ReadingsOut(tempC: 20));
      final env = await fieldEnv(api: api);
      await openField(tester, env);
      expect(keyed('reading-temp'), findsOneWidget);
      expect(keyed('reading-humidity'), findsNothing);
      expect(keyed('reading-soil'), findsNothing);
    });

    testWidgets('no village line and no danger cards on this page, whatever risks the server sends', (tester) async {
      final api = MockApiClient(latency: Duration.zero)
        ..fieldOverride = fieldWith(
          readings: const ReadingsOut(tempC: 20),
          risks: [
            risk('fine_one', Severity.green),
            risk('late_blight', Severity.yellow),
            risk('rain_wash', Severity.red),
            risk('scab_infection', Severity.yellow),
          ],
        );
      final env = await fieldEnv(api: api, language: 'en');
      await openField(tester, env);

      for (final id in ['fine_one', 'late_blight', 'rain_wash', 'scab_infection']) {
        expect(keyed('risk-$id'), findsNothing, reason: id);
      }
      expect(find.text('Title rain_wash'), findsNothing);
      expect(find.textContaining('Kotgarh'), findsNothing);
      expect(keyed('field-village'), findsNothing);
      expect(keyed('forecast-strip'), findsOneWidget);
      expect(keyed('reading-temp'), findsOneWidget);
      expectBigTouchTargets(tester);
    });

    testWidgets('the seven day strip has a picture and a name for every day', (tester) async {
      final env = await fieldEnv();
      await openField(tester, env);
      for (var i = 0; i < 7; i++) {
        expect(keyed('forecast-2026-05-${12 + i}'), findsOneWidget, reason: 'day $i');
      }
      // The demo clock is 12 May: today, then weekdays (13 May 2026 is a Wednesday).
      expect(find.descendant(of: keyed('forecast-2026-05-12'), matching: find.text('आज')), findsOneWidget);
      expect(find.descendant(of: keyed('forecast-2026-05-13'), matching: find.text('बुध')), findsOneWidget);
      // Rain on the 14th and 15th (12 mm): the rain cloud and "heavy rain" (in the semantics: the week card is pictures
      // and numbers only, as in the mockup); the 12th is dry: the sun.
      WeatherKind kindOf(String day) => tester.widget<WeatherGlyph>(keyed('forecast-glyph-$day')).kind;
      expect(kindOf('2026-05-14'), WeatherKind.heavyRain, reason: 'the rain cloud');
      final semantics = tester.ensureSemantics();
      expect(tester.getSemantics(keyed('forecast-2026-05-14')).label, 'गुरु, तेज़ बारिश');
      expect(kindOf('2026-05-12'), WeatherKind.sun, reason: 'the sun');
      semantics.dispose();
    });

    testWidgets('the week is one white card with seven equal columns: day, picture, high, low', (tester) async {
      final env = await fieldEnv(language: 'en');
      await openField(tester, env);
      final card = tester.getRect(keyed('forecast-strip'));
      final columns = [for (var i = 0; i < 7; i++) tester.getRect(keyed('forecast-2026-05-${12 + i}'))];
      // Equal columns side by side inside the card.
      for (var i = 1; i < 7; i++) {
        expect(
          columns[i].center.dx - columns[i - 1].center.dx,
          closeTo(columns[1].center.dx - columns[0].center.dx, 0.5),
        );
        expect(columns[i].top, closeTo(columns[0].top, 0.5));
      }
      expect(card.contains(columns.first.topLeft) && card.contains(columns.last.bottomRight), isTrue);

      // The style of a weather strip: the name on top in grey, the coloured picture, the high in bold, the low in grey.
      final day = keyed('forecast-2026-05-13');
      final name = tester.widget<Text>(find.descendant(of: day, matching: find.text('Wed')));
      expect(name.style!.color, AppColors.inkSoft);
      expect(name.style!.fontWeight, FontWeight.w600);
      final glyph = tester.widget<WeatherGlyph>(keyed('forecast-glyph-2026-05-13'));
      expect(glyph.size, 32);
      final high = tester.widget<Text>(find.descendant(of: day, matching: find.text('19°')));
      expect(high.style!.fontWeight, FontWeight.w700);
      expect(high.style!.color, AppColors.ink);
      final low = tester.widget<Text>(find.descendant(of: day, matching: find.text('9°')));
      expect(low.style!.color, AppColors.inkSoft);
      // Top to bottom: name, picture, high, low.
      final nameTop = tester.getTopLeft(find.descendant(of: day, matching: find.text('Wed'))).dy;
      final glyphTop = tester.getTopLeft(keyed('forecast-glyph-2026-05-13')).dy;
      final highTop = tester.getTopLeft(find.descendant(of: day, matching: find.text('19°'))).dy;
      final lowTop = tester.getTopLeft(find.descendant(of: day, matching: find.text('9°'))).dy;
      expect(nameTop, lessThan(glyphTop));
      expect(glyphTop, lessThan(highTop));
      expect(highTop, lessThan(lowTop));

      // Today is in bold ink and stands on a soft panel; the other days have no panel.
      final today = tester.widget<Text>(
        find.descendant(of: keyed('forecast-2026-05-12'), matching: find.text('Today')),
      );
      expect(today.style!.fontWeight, FontWeight.w800);
      expect(today.style!.color, AppColors.ink);
      BoxDecoration? panel(String id) => tester
          .widgetList<DecoratedBox>(find.ancestor(of: keyed('forecast-$id'), matching: find.byType(DecoratedBox)))
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .where((decoration) => decoration.borderRadius != null)
          .firstOrNull;
      expect(panel('2026-05-12')?.color, AppColors.paper, reason: 'today');
      expect(panel('2026-05-13')?.color, isNull, reason: 'another day');

      // The picture follows the rain: dry = sun, a little rain = cloud with a few drops, a lot = cloud with many.
      expect(weatherKindOfRain(0), WeatherKind.sun);
      expect(weatherKindOfRain(3), WeatherKind.lightRain);
      expect(weatherKindOfRain(12), WeatherKind.heavyRain);
    });

    testWidgets('a main page of the bottom bar: "My field", no back arrow, the refresh and the speaker', (
      tester,
    ) async {
      final env = await fieldEnv(language: 'en');
      await openField(tester, env);
      expect(find.text('My field'), findsOneWidget);
      expect(find.byIcon(AppIcons.back), findsNothing);
      expect(keyed('field-reload'), findsOneWidget);
      expect(keyed('voice-button'), findsOneWidget);
      // The page is the bottom bar's second tab.
      expect(keyed('nav-home'), findsOneWidget);
      // The owner's order: the week first, then the readings of now.
      expect(find.text('NOW IN YOUR FIELD'), findsOneWidget);
      expect(find.text('NEXT SEVEN DAYS'), findsOneWidget);
      final order = [
        tester.getTopLeft(find.text('NEXT SEVEN DAYS')).dy,
        tester.getTopLeft(keyed('forecast-strip')).dy,
        tester.getTopLeft(find.text('NOW IN YOUR FIELD')).dy,
        tester.getTopLeft(keyed('reading-temp')).dy,
      ];
      expect(order, [...order]..sort());
    });

    testWidgets('the readings are white cards, two in a row, 10 apart, each with a blue round picture', (tester) async {
      final env = await fieldEnv(language: 'en');
      await openField(tester, env);
      final temp = tester.getRect(keyed('reading-temp'));
      final humidity = tester.getRect(keyed('reading-humidity'));
      final rain = tester.getRect(keyed('reading-rain'));
      final soil = tester.getRect(keyed('reading-soil'));
      expect(humidity.left - temp.right, closeTo(10, 0.5));
      expect(humidity.top, closeTo(temp.top, 0.5));
      expect(humidity.height, closeTo(temp.height, 0.5), reason: 'cards of one row are as tall as each other');
      expect(rain.top - temp.bottom, closeTo(10, 0.5));
      expect(soil.left, closeTo(temp.left, 0.5), reason: 'the lone last tile keeps half the width, on the left');
      expect(soil.width, closeTo(temp.width, 0.5));
      final dot = tester.widget<Container>(
        find.descendant(of: keyed('reading-temp'), matching: find.byType(Container)).first,
      );
      expect((dot.decoration! as BoxDecoration).color, AppColors.blueSoft);
      expect(
        tester.getSize(find.descendant(of: keyed('reading-temp'), matching: find.byType(Container)).first),
        const Size(40, 40),
      );
      expect(
        tester.widget<Icon>(find.descendant(of: keyed('reading-temp'), matching: find.byType(Icon))).color,
        AppColors.blue,
      );
      expect(tester.widget<Text>(keyed('reading-word-temp')).style!.fontSize, 19);
      expect(tester.widget<Text>(keyed('reading-word-temp')).style!.fontWeight, FontWeight.w700);
    });

    testWidgets('only seven days are shown even if the server sends more', (tester) async {
      final days = [for (var i = 0; i < 10; i++) ForecastDayOut(day: '2026-05-${12 + i}', tminC: 8, tmaxC: 18)];
      final api = MockApiClient(latency: Duration.zero)
        ..fieldOverride = fieldWith(forecast: days, readings: const ReadingsOut(tempC: 20));
      final env = await fieldEnv(api: api);
      await openField(tester, env);
      expect(keyed('forecast-2026-05-18'), findsOneWidget);
      expect(keyed('forecast-2026-05-19'), findsNothing);
    });
  });

  group('old information and no data', () {
    testWidgets('a quiet sensor: the banner shows and the server\'s own stale sentence is not said twice', (
      tester,
    ) async {
      final api = MockApiClient(latency: Duration.zero)..fieldOverride = MockData.fieldStale();
      final env = await fieldEnv(api: api);
      await openField(tester, env);
      expect(keyed('field-old'), findsOneWidget);
      expect(find.descendant(of: keyed('field-old'), matching: find.byIcon(AppIcons.clock)), findsOneWidget);
      expect(find.descendant(of: keyed('field-old'), matching: find.text('पुरानी जानकारी')), findsOneWidget);
      // The mockup's warning card: amber-soft, flat, a thin amber line, the round amber dot with a dark picture.
      final banner =
          tester
                  .widget<DecoratedBox>(
                    find.descendant(of: keyed('field-old'), matching: find.byType(DecoratedBox)).first,
                  )
                  .decoration
              as BoxDecoration;
      expect(
        (banner.color, banner.border!.top.color, banner.boxShadow),
        (AppColors.amberSoft, AppColors.amberLine, null),
      );
      final dot = tester.widget<IconDot>(find.descendant(of: keyed('field-old'), matching: find.byType(IconDot)));
      expect((dot.background, dot.foreground, dot.round), (AppColors.amber, AppColors.ink, true));
      // The banner says when the old information is from (9 May).
      expect(find.descendant(of: keyed('field-old'), matching: find.text('9 मई')), findsOneWidget);
      // The spoken text starts with the stale sentence already: only the intro and that text.
      expect(env.voice.spokenIds, ['field_intro']);
      expect(env.voice.spokenTexts.single, startsWith('यह जानकारी पुरानी है।'));
    });

    testWidgets('stale data whose spoken text lacks the sentence gets the field_stale prompt first', (tester) async {
      final api = MockApiClient(latency: Duration.zero)
        ..fieldOverride = fieldWith(stale: true, readings: const ReadingsOut(tempC: 20));
      final env = await fieldEnv(api: api);
      await openField(tester, env);
      expect(env.voice.log, ['field_intro@hi', 'field_stale@hi', 'कुछ सार।@hi']);
    });

    testWidgets('fresh data: no banner, no stale prompt', (tester) async {
      final env = await fieldEnv();
      await openField(tester, env);
      expect(keyed('field-old'), findsNothing);
      expect(env.voice.spokenIds, isNot(contains('field_stale')));
    });

    testWidgets('no data: a picture and words, the server sentence once, then the hint for the round arrow', (
      tester,
    ) async {
      final api = MockApiClient(latency: Duration.zero)..fieldOverride = MockData.fieldNoData();
      final env = await fieldEnv(api: api);
      await openField(tester, env);
      expect(keyed('field-no-data'), findsOneWidget);
      expect(find.text('अभी जानकारी नहीं'), findsOneWidget);
      // A neutral (grey) flat card with the picture, in the mockup's language.
      final card =
          tester
                  .widget<DecoratedBox>(
                    find.descendant(of: keyed('field-no-data'), matching: find.byType(DecoratedBox)).first,
                  )
                  .decoration
              as BoxDecoration;
      expect((card.color, card.boxShadow), (AppColors.neutralSoft, null));
      expect(find.descendant(of: keyed('field-no-data'), matching: find.byIcon(AppIcons.offline)), findsOneWidget);
      expect(keyed('reading-temp'), findsNothing);
      expect(keyed('forecast-strip'), findsNothing);
      // Old data and no data at once: one banner would only repeat it, and the server's text says both.
      expect(keyed('field-old'), findsNothing);
      expect(env.voice.spokenIds, ['field_intro', 'field_reload']);
      expect(env.voice.spokenTexts.single, MockData.fieldNoData().spoken.text.hi);
      expect(env.voice.spokenTexts.single, endsWith('आपके खेत की जानकारी अभी नहीं है।'));
    });

    testWidgets('no data with another spoken text: field_no_data is said by the app', (tester) async {
      final api = MockApiClient(latency: Duration.zero)
        ..fieldOverride = fieldWith(spokenHi: '', spokenEn: '', forecast: const []);
      final env = await fieldEnv(api: api);
      await openField(tester, env);
      expect(env.voice.spokenIds, ['field_intro', 'field_no_data', 'field_reload']);
    });
  });

  group('no internet', () {
    testWidgets('the last answer is shown as old and field_stale is spoken (its own weather is not read out)', (
      tester,
    ) async {
      final api = MockApiClient(latency: Duration.zero);
      final env = await fieldEnv(api: api);
      final container = await pumpApp(tester, env, location: '/home');
      useSmallPhone(tester);
      await tapKey(tester, 'home-field'); // online: the answer is kept on the phone
      expect(env.prefs.getString('field_cache_F001'), isNotNull);
      // My field is a page of the bottom bar: it has no back arrow, the bar's Home tab leads back.
      await tapKey(tester, 'nav-home');
      expect(container, isNotNull);

      api.failWith(const ApiException.network(), ops: {'field'});
      env.voice.clear();
      await tapKey(tester, 'home-field');
      expect(keyed('field-old'), findsOneWidget);
      expect(keyed('reading-temp'), findsOneWidget, reason: 'the old readings are still shown');
      expect(env.voice.spokenIds, ['field_intro', 'field_stale']);
      expect(env.voice.spokenTexts, isEmpty);
    });

    testWidgets('without a saved answer it is the error screen with a retry that speaks error_no_internet', (
      tester,
    ) async {
      final api = MockApiClient(latency: Duration.zero)..failWith(const ApiException.network(), ops: {'field'});
      final env = await fieldEnv(api: api);
      await openField(tester, env);
      expect(keyed('retry-button'), findsOneWidget);
      expect(env.voice.spokenIds, ['error_no_internet']);
      api.clearFailure();
      await tapKey(tester, 'retry-button');
      expect(keyed('reading-temp'), findsOneWidget);
    });

    testWidgets('another farmer\'s saved answer is never shown', (tester) async {
      final api = MockApiClient(latency: Duration.zero)..failWith(const ApiException.network(), ops: {'field'});
      final env = await fieldEnv(api: api);
      await env.prefs.setString(
        'field_cache_SOMEONE_ELSE',
        jsonEncode({'saved_at': '2026-05-01T00:00:00Z', 'field': MockData.field().toJson()}),
      );
      await openField(tester, env);
      expect(keyed('retry-button'), findsOneWidget);
    });

    testWidgets('a damaged saved answer is treated as none', (tester) async {
      final api = MockApiClient(latency: Duration.zero)..failWith(const ApiException.network(), ops: {'field'});
      final env = await fieldEnv(api: api);
      await env.prefs.setString('field_cache_F001', '{not json');
      await openField(tester, env);
      expect(keyed('retry-button'), findsOneWidget);
    });

    testWidgets('a server error (not the internet) never falls back to the old answer', (tester) async {
      final api = MockApiClient(latency: Duration.zero)
        ..failWith(
          const ApiException(kind: ApiErrorKind.server, code: 'x', statusCode: 500),
          ops: {'field'},
        );
      final env = await fieldEnv(api: api);
      await env.prefs.setString(
        'field_cache_F001',
        jsonEncode({'saved_at': '2026-05-01T00:00:00Z', 'field': MockData.field().toJson()}),
      );
      await openField(tester, env);
      expect(keyed('retry-button'), findsOneWidget);
      expect(env.voice.spokenIds, ['error_try_again']);
    });
  });

  group('the round arrow', () {
    testWidgets('looks again, says field_updated_ok and then the new summary', (tester) async {
      final api = MockApiClient(latency: Duration.zero);
      final env = await fieldEnv(api: api);
      await openField(tester, env);
      final before = api.calls.where((c) => c == 'field').length;
      api.fieldOverride = fieldWith(readings: const ReadingsOut(tempC: 30), spokenEn: 'New.', spokenHi: 'नया।');
      env.voice.clear();
      await tapKey(tester, 'field-reload');
      expect(api.calls.where((c) => c == 'field').length, before + 1);
      expect(find.descendant(of: keyed('reading-temp'), matching: find.text('गर्म')), findsOneWidget);
      expect(env.voice.log, ['field_updated_ok@hi', 'नया।@hi']);
    });

    testWidgets('with no internet it keeps the old answer, marks it and says field_stale', (tester) async {
      final api = MockApiClient(latency: Duration.zero);
      final env = await fieldEnv(api: api);
      await openField(tester, env);
      api.failWith(const ApiException.network(), ops: {'field'});
      env.voice.clear();
      await tapKey(tester, 'field-reload');
      expect(keyed('field-old'), findsOneWidget);
      expect(env.voice.spokenIds, ['field_stale']);
    });

    testWidgets('a server error keeps what is shown and says error_try_again', (tester) async {
      final api = MockApiClient(latency: Duration.zero);
      final env = await fieldEnv(api: api);
      await openField(tester, env);
      api.failWith(
        const ApiException(kind: ApiErrorKind.server, code: 'x', statusCode: 500),
        ops: {'field'},
      );
      env.voice.clear();
      await tapKey(tester, 'field-reload');
      expect(keyed('reading-temp'), findsOneWidget);
      expect(env.voice.spokenIds, ['error_try_again']);
    });
  });

  group('layout', () {
    for (final (name, size, scale) in [
      ('320x568', const Size(320, 568), 1.0),
      ('360x640 at 1.6x text', const Size(360, 640), 1.6),
      ('320x568 at 1.6x text', const Size(320, 568), 1.6),
    ]) {
      testWidgets('the whole page fits on $name', (tester) async {
        final api = MockApiClient(latency: Duration.zero)
          ..fieldOverride = fieldWith(
            stale: true,
            readings: const ReadingsOut(
              tempC: 17.5,
              rhPct: 82,
              rain24hMm: 6.5,
              leafWetnessMin: 340,
              soilMoisturePct: 31,
            ),
            risks: [risk('scab_infection', Severity.red), risk('late_blight', Severity.yellow)],
          );
        final env = await fieldEnv(api: api);
        await openField(tester, env, textScale: scale, size: size);
        expect(tester.takeException(), isNull);
        expectBigTouchTargets(tester);
        await tester.ensureVisible(keyed('forecast-2026-05-18'));
        expect(tester.takeException(), isNull);
        // The round arrow stays on screen.
        final arrow = tester.getRect(keyed('field-reload'));
        expect(arrow.bottom, lessThanOrEqualTo(size.height));
      });
    }

    testWidgets('no data and the error screen fit on 320x568 at 1.6x text', (tester) async {
      final api = MockApiClient(latency: Duration.zero)..fieldOverride = MockData.fieldNoData();
      final env = await fieldEnv(api: api);
      await openField(tester, env, textScale: 1.6, size: const Size(320, 568));
      expect(tester.takeException(), isNull);
    });
  });

  group('words and cache', () {
    test('temperature, rain, air, leaf and soil limits', () {
      expect(
        [
          for (final c in [0.0, 5.0, 14.9, 15.0, 24.9, 25.0, 31.9, 32.0]) tempBand(c).name,
        ],
        ['cold', 'cool', 'cool', 'pleasant', 'pleasant', 'warm', 'warm', 'hot'],
      );
      expect(
        [
          for (final r in [0.0, 0.9, 1.0, 9.9, 10.0]) rainBand(r).name,
        ],
        ['none', 'none', 'light', 'light', 'heavy'],
      );
      expect(
        [
          for (final h in [10.0, 49.9, 50.0, 79.9, 80.0]) humidityBand(h).name,
        ],
        ['dry', 'dry', 'ok', 'ok', 'damp'],
      );
      expect(
        [
          for (final m in [0, 59, 60, 239, 240]) leafBand(m).name,
        ],
        ['dry', 'dry', 'damp', 'damp', 'wet'],
      );
      expect(
        [
          for (final s in [0.0, 14.9, 15.0, 39.9, 40.0]) soilBand(s).name,
        ],
        ['dry', 'dry', 'ok', 'ok', 'wet'],
      );
    });

    test('every word the tiles can show exists in both languages', () {
      final resources = loadResources();
      for (final lang in ['en', 'hi']) {
        for (final readings in const [
          ReadingsOut(tempC: 0, rhPct: 0, rain24hMm: 0, leafWetnessMin: 0, soilMoisturePct: 0),
          ReadingsOut(tempC: 20, rhPct: 60, rain24hMm: 5, leafWetnessMin: 100, soilMoisturePct: 30),
          ReadingsOut(tempC: 40, rhPct: 95, rain24hMm: 50, leafWetnessMin: 900, soilMoisturePct: 80),
        ]) {
          for (final tile in readingTiles(readings)) {
            for (final key in [tile.labelKey, tile.wordKey]) {
              expect(resources.t(key, lang), isNot(key), reason: '$lang $key');
              expect(resources.t(key, lang), isNot(matches(RegExp(r'\d'))), reason: 'the words have no digits');
            }
          }
        }
      }
    });

    test('the cache keeps one answer per farmer', () async {
      final env = await fieldEnv();
      final mine = FieldCache(env.prefs, 'F001');
      final other = FieldCache(env.prefs, 'F002');
      expect(mine.load(), isNull);
      await mine.save(MockData.field(), DateTime.utc(2026, 5, 12, 3));
      expect(other.load(), isNull);
      final loaded = mine.load()!;
      expect(loaded.fromCache, isTrue);
      expect(loaded.isOld, isTrue);
      expect(loaded.savedAt, DateTime.utc(2026, 5, 12, 3));
      expect(loaded.field.village, 'Kotgarh');
      expect(loaded.field.forecast, hasLength(7));
      // Nobody logged in: nothing is kept.
      await FieldCache(env.prefs, null).save(MockData.field(), DateTime.now());
      expect(FieldCache(env.prefs, null).load(), isNull);
      expect(env.prefs.getKeys().where((k) => k.startsWith('field_cache_')), {'field_cache_F001'});
    });

    test('FieldView knows empty and old answers', () {
      expect(FieldView(MockData.fieldNoData()).hasNoData, isTrue);
      expect(FieldView(MockData.field()).hasNoData, isFalse);
      expect(FieldView(MockData.field()).isOld, isFalse);
      expect(FieldView(MockData.fieldStale()).isOld, isTrue);
      expect(FieldView(MockData.field(), fromCache: true).isOld, isTrue);
    });
  });
}
