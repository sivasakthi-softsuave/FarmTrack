import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmtrack/core/errors/api_exception.dart';
import 'package:farmtrack/core/models/models.dart';
import 'package:farmtrack/core/network/mock_api_client.dart';
import 'package:farmtrack/core/network/mock_data.dart';
import 'package:farmtrack/features/diary/date_words.dart';
import 'package:farmtrack/features/field/place_providers.dart';
import 'package:farmtrack/features/field/weather_words.dart';
import 'package:farmtrack/features/home/home_screen.dart';
import 'package:farmtrack/features/home/home_weather.dart';
import 'package:farmtrack/features/offline/last_result.dart';

import 'support/contrast.dart';
import 'support/feature_fakes.dart';
import 'support/finders.dart';
import 'support/harness.dart';

final _resources = loadResources();

String _en(String key, {Map<String, Object> args = const {}}) => _resources.t(key, 'en', args: args);

/// The hours of the answer, the first being the hour of [fixedNow] (the clock of these tests).
List<HourOut> _hours({int count = 12, int startAgo = 0}) {
  final start = DateTime.utc(
    fixedNow.toUtc().year,
    fixedNow.toUtc().month,
    fixedNow.toUtc().day,
    fixedNow.toUtc().hour,
  ).subtract(Duration(hours: startAgo));
  return [
    for (var i = 0; i < count; i++)
      HourOut(
        time: start.add(Duration(hours: i)),
        tempC: 27.4 - i * 0.5,
        sky: i < 4 ? 'partly_cloudy' : (i < 8 ? 'cloudy' : 'rain'),
        isDay: true,
        rainChancePct: [0, 0, 10, 10, 20, 30, 40, 60, 60, 50, 30, 20][i % 12],
        rainMm: 0,
        windKmh: 8,
      ),
  ];
}

/// The farmer's field of the mock server with the hours of these tests and what a test changes.
FieldOut _field({
  ReadingsOut? readings,
  ConditionsOut? conditions,
  List<HourOut>? hours,
  SprayOut? spray = MockData.sprayGo,
  List<ForecastDayOut>? forecast,
}) {
  final base = MockData.field();
  return FieldOut(
    stationId: base.stationId,
    village: base.village,
    asOf: fixedNow.toUtc(),
    readings: readings ?? base.readings,
    conditions: conditions ?? base.conditions,
    hours: hours ?? _hours(),
    spray: spray,
    forecast: forecast ?? base.forecast,
    risks: base.risks,
    spoken: base.spoken,
  );
}

ConditionsOut _conditions({String? sky = 'partly_cloudy', bool? isDay = true}) => ConditionsOut(
  sky: sky,
  isDay: isDay,
  feelsLikeC: 16,
  windKmh: 8,
  visibilityKm: 6,
  pressureHpa: 1012,
  dewPointC: 14,
  aqi: 64,
  uvIndex: 7,
  sunrise: DateTime.utc(2026, 5, 12, 0, 10),
  sunset: DateTime.utc(2026, 5, 12, 13, 40),
);

class _MetaApi extends MockApiClient {
  _MetaApi({required this.weather}) : super(latency: Duration.zero);

  final bool weather;

  @override
  Future<MetaOut> meta() async => MetaOut.fromJson({
    'app_version': '1',
    'supported_languages': ['hi', 'en'],
    'weather_enabled': weather,
    'place_weather_enabled': true,
  });
}

Future<TestEnv> _env({
  String language = 'en',
  FieldOut? field,
  FieldOut? place,
  bool weather = true,
  PickedPlace? picked,
}) async {
  final api = _MetaApi(weather: weather)..fieldOverride = field ?? _field();
  if (place != null) api.placeWeatherOverride = place;
  final env = await TestEnv.create(
    loggedIn: true,
    language: language,
    api: api,
    extraOverrides: [clockProvider.overrideWithValue(() => fixedNow), homeFieldSummaryProvider.overrideWithValue(true)],
  );
  await env.prefs.setBool('place_weather_enabled', true); // Home reads the saved answer under flutter test
  if (!weather) await env.prefs.setBool('weather_enabled', false);
  if (picked != null) await env.prefs.setString('picked_place_F001', jsonEncode(picked.toJson()));
  return env;
}

Future<void> _openHome(
  WidgetTester tester,
  TestEnv env, {
  Size size = const Size(390, 844),
  double textScale = 1.0,
}) async {
  useSmallPhone(tester, size: size, textScale: textScale);
  await pumpApp(tester, env, location: '/home');
}

String _plain(WidgetTester tester, String key) => tester.widget<Text>(keyed(key)).data!;

String _spanText(WidgetTester tester, String key) => tester.widget<Text>(keyed(key)).textSpan!.toPlainText();

LinearGradient _gradient(WidgetTester tester, String key) =>
    (tester.widget<DecoratedBox>(keyed(key)).decoration as BoxDecoration).gradient! as LinearGradient;

double _top(WidgetTester tester, String key) => tester.getTopLeft(keyed(key)).dy;

void main() {
  group('the words', () {
    test('wind: the bands only choose a word', () {
      expect(windWordKey(0), 'home_wind_calm');
      expect(windWordKey(2.9), 'home_wind_calm');
      expect(windWordKey(3), 'home_wind_light');
      expect(windWordKey(11.9), 'home_wind_light');
      expect(windWordKey(12), 'home_wind_breeze');
      expect(windWordKey(19.9), 'home_wind_breeze');
      expect(windWordKey(20), 'home_wind_windy');
      expect(windWordKey(28.9), 'home_wind_windy');
      expect(windWordKey(29), 'home_wind_very_windy');
    });

    test('UV and how far one sees', () {
      expect(
        [
          for (final v in [0.0, 2.9, 3.0, 5.9, 6.0, 7.9, 8.0, 10.9, 11.0, 14.0]) uvWordKey(v),
        ],
        [
          'home_uv_low',
          'home_uv_low',
          'home_uv_moderate',
          'home_uv_moderate',
          'home_uv_high',
          'home_uv_high',
          'home_uv_very_high',
          'home_uv_very_high',
          'home_uv_extreme',
          'home_uv_extreme',
        ],
      );
      expect(visibilityWordKey(24), 'home_vis_clear');
      expect(visibilityWordKey(10), 'home_vis_clear');
      expect(visibilityWordKey(9.9), 'home_vis_hazy');
      expect(visibilityWordKey(4), 'home_vis_hazy');
      expect(visibilityWordKey(3.9), 'home_vis_poor');
    });

    test('the big card takes its colour from the sky', () {
      expect(heroSkyOf(sky: 'clear', isDay: true, tempC: 27), HeroSky.sunny);
      expect(heroSkyOf(sky: 'partly_cloudy', isDay: true, tempC: 30), HeroSky.sunny);
      expect(heroSkyOf(sky: 'clear', isDay: true, tempC: 33), HeroSky.hot);
      expect(heroSkyOf(sky: 'clear', isDay: true, tempC: 32.9), HeroSky.sunny);
      expect(heroSkyOf(sky: 'cloudy', isDay: true, tempC: 36), HeroSky.cloud, reason: 'a cloudy day is not a hot sun');
      expect(heroSkyOf(sky: 'fog', isDay: true), HeroSky.cloud);
      expect(heroSkyOf(sky: 'snow', isDay: true), HeroSky.cloud);
      for (final rainy in ['drizzle', 'rain', 'heavy_rain', 'showers', 'thunderstorm']) {
        expect(heroSkyOf(sky: rainy, isDay: true), HeroSky.rain, reason: rainy);
      }
      expect(heroSkyOf(sky: 'clear', isDay: false, tempC: 40), HeroSky.night, reason: 'night wins');
      expect(heroSkyOf(sky: 'rain', isDay: false), HeroSky.night);
      expect(heroSkyOf(tempC: 36), HeroSky.hot, reason: 'no sky word: the temperature alone');
      expect(heroSkyOf(), HeroSky.sunny);
      expect(heroSkyOf(sky: 'something new', isDay: true, tempC: 20), HeroSky.sunny);
    });

    test('white words are readable on every sky, at the bottom (the lightest end) of its gradient', () {
      for (final sky in HeroSky.values) {
        final colors = heroColors(sky);
        expect(contrast(Colors.white, colors.bottom), greaterThanOrEqualTo(4.5), reason: sky.name);
        expect(contrast(Colors.white, colors.top), greaterThanOrEqualTo(4.5), reason: sky.name);
      }
    });

    test('what the voice says about spraying and rain has no digit, in either language', () {
      final digit = RegExp('[0-9०-९]');
      for (final lang in ['en', 'hi']) {
        for (final key in [
          'spray_speak_go',
          'spray_speak_wind',
          'spray_speak_hot',
          'spray_speak_rain_soon',
          'spray_speak_rain_later',
          'spray_speak_raining',
          'home_rain_say_today',
          'home_rain_say_none',
        ]) {
          expect(_resources.t(key, lang), isNot(contains(digit)), reason: '$lang $key');
        }
        expect(_resources.t('home_rain_say_next', lang, args: {'day': 'Thursday'}), isNot(contains(digit)));
      }
    });

    test('every spray answer has a sentence for the eyes and one for the ear', () {
      const rain = SprayCheckOut(status: SprayStatus.stop, value: 8, hours: 2);
      final cases = <(String, SprayOut, String, String)>[
        (
          'calm_dry',
          const SprayOut(state: SprayStatus.ok, rain: SprayCheckOut(hours: 5)),
          'Calm and dry for the next 5 hours.',
          'Good time to spray. The air is calm and no rain is coming soon.',
        ),
        (
          'calm_dry, no rain found in the hours known',
          const SprayOut(state: SprayStatus.ok),
          'Calm and dry for the next 12 hours.',
          'Good time to spray. The air is calm and no rain is coming soon.',
        ),
        (
          'windy',
          const SprayOut(state: SprayStatus.care, headline: 'windy'),
          'It is windy now. Spray can drift to the next field. Wait for calmer air.',
          'Be careful. It is windy. Wait for calmer air before you spray.',
        ),
        (
          'hot',
          const SprayOut(state: SprayStatus.care, headline: 'hot'),
          'It is very hot. Spray in the cool of the morning or evening.',
          'Be careful. It is very hot. Spray in the cool of the morning or evening.',
        ),
        (
          'rain_soon (not now)',
          const SprayOut(state: SprayStatus.stop, headline: 'rain_soon', rain: rain),
          'Rain is coming within 2 hours. A spray would be washed off.',
          'Not now. Rain is coming soon and would wash the spray off.',
        ),
        (
          'rain_soon (later)',
          const SprayOut(
            state: SprayStatus.care,
            headline: 'rain_soon',
            rain: SprayCheckOut(status: SprayStatus.care, hours: 4),
          ),
          'Rain is coming within 4 hours. A spray would be washed off.',
          'Be careful. Rain may come in a few hours. Spray early, or wait.',
        ),
        (
          'raining',
          const SprayOut(state: SprayStatus.stop, headline: 'raining', rain: rain),
          'It is raining now. Do not spray.',
          'Not now. It is raining.',
        ),
      ];
      for (final (name, spray, say, speak) in cases) {
        final words = sprayWords(_en, spray, hoursKnown: 12);
        expect(words.say, say, reason: name);
        expect(words.speak, speak, reason: name);
      }
      // A reason the app does not know, with a state that is not "good": the title alone (no made-up sentence).
      final unknown = sprayWords(_en, const SprayOut(state: SprayStatus.care, headline: 'new_reason'), hoursKnown: 12);
      expect(unknown.say, 'Be careful');
      expect(unknown.speak, 'Be careful');
    });
  });

  group('the contract', () {
    test('hours, the spray check, UV and the sun come through, and what is wrong is left out', () {
      final field = FieldOut.fromJson({
        'conditions': {'uv_index': 7.5, 'sunrise': '2026-05-12T00:10:00Z', 'sunset': '2026-05-12T13:40:00Z'},
        'hours': [
          {
            'time': '2026-05-12T06:00:00Z',
            'temp_c': 27.4,
            'sky': 'cloudy',
            'is_day': true,
            'rain_chance_pct': 10,
            'rain_mm': 0.2,
            'wind_kmh': 4.6,
          },
          {'temp_c': 1},
          'x',
          {'time': 'not a time'},
          {'time': '2026-05-12T07:00:00Z'},
        ],
        'spray': {
          'state': 'stop',
          'headline': 'rain_soon',
          'wind': {'kmh': 4.6, 'status': 'ok'},
          'rain': {'dry_hours': 2, 'mm_next_3h': 8.2, 'status': 'stop'},
          'heat': {'temp_c': 19.0, 'status': 'ok'},
        },
      });
      expect(field.conditions!.uvIndex, 7.5);
      expect(field.conditions!.sunrise, DateTime.utc(2026, 5, 12, 0, 10));
      expect(field.conditions!.sunset, DateTime.utc(2026, 5, 12, 13, 40));
      expect(field.hours, hasLength(2), reason: 'only the hours with a time');
      expect(field.hours.first.tempC, 27.4);
      expect(field.hours.first.rainChancePct, 10);
      expect(field.hours.last.tempC, isNull);
      final spray = field.spray!;
      expect(spray.state, SprayStatus.stop);
      expect(spray.headline, 'rain_soon');
      expect(spray.wind.value, 4.6);
      expect(spray.rain.hours, 2);
      expect(spray.rain.value, 8.2);
      expect(spray.rain.status, SprayStatus.stop);
      expect(spray.heat.value, 19);
      // And back again.
      final again = FieldOut.fromJson(field.toJson());
      expect(again.hours.map((h) => h.time), field.hours.map((h) => h.time));
      expect(again.spray!.rain.hours, 2);
      expect(again.conditions!.sunset, field.conditions!.sunset);
    });

    test('an older server sends none of it: no hours, no check', () {
      final field = FieldOut.fromJson({
        'readings': {'temp_c': 20},
      });
      expect(field.hours, isEmpty);
      expect(field.spray, isNull);
      expect(field.conditions, isNull);
    });

    test(
      'the server says go, care or stop; a state the app does not know shows nothing; an unknown part is "be careful"',
      () {
        expect(SprayOut.tryParse({'state': 'go'})!.state, SprayStatus.ok, reason: '"go" on the wire is a good time');
        expect(SprayOut.tryParse({'state': 'care'})!.state, SprayStatus.care);
        expect(SprayOut.tryParse({'state': 'stop'})!.state, SprayStatus.stop);
        expect(SprayOut.tryParse({'state': 'ok'}), isNull, reason: '"ok" is a word of the parts, not of the state');
        expect(SprayOut.tryParse({'state': 'maybe'}), isNull);
        expect(SprayOut.tryParse({'state': 1}), isNull);
        expect(SprayOut.tryParse(null), isNull);
        expect(
          SprayOut.tryParse({'state': 'go'})!.toJson()['state'],
          'go',
          reason: 'and back again as the server writes it',
        );
        final care = SprayOut.tryParse({
          'state': 'go',
          'wind': {'kmh': 3, 'status': 'brand-new'},
        })!;
        expect(care.wind.status, SprayStatus.care, reason: 'never safer than the server said');
        expect(care.rain.status, SprayStatus.care, reason: 'a part the server left out is read as "be careful" too');
      },
    );
  });

  group('Home, weather first', () {
    testWidgets('the big card: the day in one picture, with air, rain and wind inside it', (tester) async {
      final env = await _env();
      await _openHome(tester, env);
      expect(_spanText(tester, 'home-hero-temp'), '18°C', reason: '17.5 rounds to 18');
      expect(_plain(tester, 'home-hero-sky'), 'Partly cloudy');
      expect(_plain(tester, 'home-hero-feels'), 'Feels like 16°');
      expect(_plain(tester, 'home-hero-range'), 'Day 8° – 18°', reason: "today's low and high from the week");
      expect(keyed('home-hero-glyph'), findsOneWidget);
      expect(_plain(tester, 'home-chip-value-air'), '82 %');
      expect(find.descendant(of: keyed('home-chip-air'), matching: find.text('Damp')), findsOneWidget);
      expect(_plain(tester, 'home-chip-value-rain'), '6.5 mm');
      expect(find.descendant(of: keyed('home-chip-rain'), matching: find.text('Light rain')), findsOneWidget);
      expect(_plain(tester, 'home-chip-value-wind'), '8 km/h');
      expect(find.descendant(of: keyed('home-chip-wind'), matching: find.text('Light breeze')), findsOneWidget);
      expect(
        _plain(tester, 'home-hero-place'),
        startsWith('Kotgarh, Shimla · '),
        reason: 'the place of the header line',
      );
      expect(find.text('NOW IN YOUR FIELD'), findsOneWidget);
    });

    testWidgets('the colour of the card follows the sky', (tester) async {
      for (final (sky, isDay, temp, expected) in [
        ('clear', true, 27.0, HeroSky.sunny),
        ('clear', true, 36.0, HeroSky.hot),
        ('cloudy', true, 22.0, HeroSky.cloud),
        ('rain', true, 14.0, HeroSky.rain),
        ('clear', false, 9.0, HeroSky.night),
      ]) {
        final env = await _env(
          field: _field(
            readings: ReadingsOut(tempC: temp, rhPct: 60, rain24hMm: 0),
            conditions: _conditions(sky: sky, isDay: isDay),
          ),
        );
        await _openHome(tester, env);
        final colors = _gradient(tester, 'home-hero').colors;
        expect(colors, [heroColors(expected).top, heroColors(expected).bottom], reason: '$sky $temp');
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('a reading the server does not have is not shown: no wind, no chip; no sky, no picture', (
      tester,
    ) async {
      final env = await _env(
        field: _field(
          readings: const ReadingsOut(tempC: 20, rhPct: 55),
          conditions: const ConditionsOut(feelsLikeC: 19),
        ),
      );
      await _openHome(tester, env);
      expect(_plain(tester, 'home-chip-value-air'), '55 %');
      expect(keyed('home-chip-rain'), findsNothing);
      expect(keyed('home-chip-wind'), findsNothing);
      expect(keyed('home-hero-glyph'), findsNothing);
      expect(keyed('home-hero-sky'), findsNothing);
      expect(_plain(tester, 'home-hero-feels'), 'Feels like 19°');
    });

    testWidgets('the blocks come in the order of the design: card, hours, spray, rain of the week, the air', (
      tester,
    ) async {
      final env = await _env();
      await _openHome(tester, env);
      final order = [
        _top(tester, 'home-hero'),
        _top(tester, 'home-hours'),
        _top(tester, 'home-spray-ok'),
        _top(tester, 'home-rain-week'),
        _top(tester, 'home-air-grid'),
      ];
      expect([...order]..sort(), order, reason: 'top to bottom');
      for (final title in ['NEXT HOURS', 'CAN I SPRAY TODAY?', 'RAIN IN THE NEXT DAYS', 'MORE ABOUT THE AIR']) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
    });

    testWidgets('a result that is ready stays under the camera card, the last advice goes below the weather', (
      tester,
    ) async {
      final env = await _env();
      await LastResultCache(env.prefs, 'F001').save(MockData.okScan('scan-1'), fixedNow);
      await _openHome(tester, env);
      expect(keyed('last-result-card'), findsOneWidget);
      expect(_top(tester, 'home-scan'), lessThan(_top(tester, 'home-hero')));
      expect(_top(tester, 'home-air-grid'), lessThan(_top(tester, 'last-result-card')), reason: 'under the weather');
      expect(find.text('LAST ADVICE'), findsOneWidget);
    });

    testWidgets('a place the farmer chose: the heading and the weather are that place\'s', (tester) async {
      const place = PickedPlace(label: 'Theog, Shimla, Himachal Pradesh', lat: 31.12, lon: 77.36, kind: 'tehsil');
      final env = await _env(picked: place);
      await _openHome(tester, env);
      expect(find.text('NOW AT THIS PLACE'), findsOneWidget);
      expect(find.text('NOW IN YOUR FIELD'), findsNothing);
      expect(
        _spanText(tester, 'home-hero-temp'),
        '12°C',
        reason: 'the weather of the place, not of the own field (18)',
      );
      expect(_plain(tester, 'home-hero-place'), startsWith('Theog, Shimla · '));
      expect(env.api.weatherAtCalls.single.lat, 31.12);
    });

    testWidgets('the card opens My field', (tester) async {
      final env = await _env();
      await _openHome(tester, env);
      await tester.tap(keyed('home-hero'));
      await tester.pumpAndSettle();
      expect(keyed('field-reload'), findsOneWidget);
    });

    group('the place in the heading row', () {
      test('only the first part of the name is kept', () {
        expect(shortPlaceName('Navalur, Tamil Nadu'), 'Navalur');
        expect(shortPlaceName('Kotgarh, Shimla'), 'Kotgarh');
        expect(shortPlaceName('  Theog  '), 'Theog');
        expect(shortPlaceName('Navalur'), 'Navalur');
        expect(shortPlaceName(''), '');
        expect(shortPlaceName('कोटगढ़, शिमला'), 'कोटगढ़');
      });

      testWidgets('the farmer\'s own place: the village, not a link', (tester) async {
        final env = await _env();
        await _openHome(tester, env);
        expect(_plain(tester, 'home-weather-place'), 'Kotgarh');
        expect(find.text('Open my field'), findsNothing);
        expect(find.text('NOW IN YOUR FIELD'), findsOneWidget);
      });

      testWidgets('a place the farmer chose: its first name', (tester) async {
        const place = PickedPlace(label: 'Navalur, Thiruporur, Tamil Nadu', lat: 12.85, lon: 80.22, kind: 'tehsil');
        final env = await _env(picked: place);
        await _openHome(tester, env);
        expect(_plain(tester, 'home-weather-place'), 'Navalur');
        expect(find.text('NOW AT THIS PLACE'), findsOneWidget);
      });

      testWidgets('a name that is too wide is cut with an ellipsis, the heading keeps all its words', (tester) async {
        const place = PickedPlace(
          label: 'Thiruvananthapuramkuzhiyamkuzhiyam, Kerala',
          lat: 8.5,
          lon: 76.9,
          kind: 'tehsil',
        );
        final env = await _env(picked: place);
        await _openHome(tester, env, size: const Size(320, 568), textScale: 1.6);
        final text = tester.widget<Text>(keyed('home-weather-place'));
        expect(text.data, 'Thiruvananthapuramkuzhiyamkuzhiyam');
        expect(text.overflow, TextOverflow.ellipsis);
        expect(text.maxLines, 1);
        final box = tester.getRect(keyed('home-weather-place'));
        expect(box.width, lessThan(320 * 0.4), reason: 'the heading is not pushed out');
        expect(find.text('NOW AT THIS PLACE'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('with weather switched off on the server the old white card of sensor readings stays', (tester) async {
      final env = await _env(
        weather: false,
        field: _field(readings: const ReadingsOut(tempC: 17.5, rhPct: 82, soilMoisturePct: 31)),
      );
      await _openHome(tester, env);
      expect(keyed('home-hero'), findsNothing);
      expect(keyed('home-hours'), findsNothing);
      expect(keyed('home-field-card'), findsOneWidget);
      expect(tester.widget<Text>(keyed('home-reading-value-soil')).data, '31 %');
      expect(
        find.descendant(of: keyed('home-field-card'), matching: find.byType(Text)),
        findsNWidgets(3),
        reason: 'one reading',
      );
    });

    testWidgets('an answer without any temperature or condition shows the sensor card, not an empty big card', (
      tester,
    ) async {
      final env = await _env(
        field: FieldOut(
          asOf: fixedNow.toUtc(),
          readings: const ReadingsOut(soilMoisturePct: 31),
          forecast: MockData.field().forecast,
        ),
      );
      await _openHome(tester, env);
      expect(keyed('home-hero'), findsNothing);
      expect(keyed('home-field-card'), findsOneWidget);
    });
  });

  group('next hours', () {
    testWidgets('the first column is "Now", the others have the clock of the phone; the rain chance is under each', (
      tester,
    ) async {
      final env = await _env();
      await _openHome(tester, env);
      final t = _en;
      final hours = _hours();
      expect(find.descendant(of: keyed('home-hour-0'), matching: find.text('Now')), findsOneWidget);
      expect(find.descendant(of: keyed('home-hour-0'), matching: find.text('27°')), findsOneWidget);
      expect(
        find.descendant(of: keyed('home-hour-0'), matching: find.text('–')),
        findsOneWidget,
        reason: 'no rain chance',
      );
      expect(
        find.descendant(of: keyed('home-hour-2'), matching: find.text(clockText(t, hours[2].time, minutes: false))),
        findsOneWidget,
      );
      expect(find.descendant(of: keyed('home-hour-2'), matching: find.text('10 %')), findsOneWidget);
      expect(find.descendant(of: keyed('home-hour-2'), matching: find.text('26°')), findsOneWidget);
    });

    testWidgets('the strip moves sideways to the hours that do not fit', (tester) async {
      final env = await _env();
      await _openHome(tester, env);
      expect(keyed('home-hour-11'), findsNothing, reason: 'not built before it is near');
      await tester.dragUntilVisible(keyed('home-hour-11'), keyed('home-hours'), const Offset(-200, 0));
      expect(keyed('home-hour-11'), findsOneWidget);
    });

    testWidgets('hours that are over are dropped (the first left is "Now"); none left, no strip', (tester) async {
      var env = await _env(field: _field(hours: _hours(startAgo: 3)));
      await _openHome(tester, env);
      expect(find.descendant(of: keyed('home-hour-0'), matching: find.text('Now')), findsOneWidget);
      // The hour of 3 hours ago, 2 and 1 ago are over; the hour that began 3 - 3 = 0 hours ago (this one) is the first.
      expect(find.descendant(of: keyed('home-hour-0'), matching: find.text('27°')), findsNothing);
      expect(
        find.descendant(of: keyed('home-hour-0'), matching: find.text('26°')),
        findsOneWidget,
        reason: '27.4 - 3 * 0.5',
      );
      await tester.pumpWidget(const SizedBox());

      env = await _env(field: _field(hours: _hours(count: 3, startAgo: 10)));
      await _openHome(tester, env);
      expect(keyed('home-hours'), findsNothing);
      expect(find.text('NEXT HOURS'), findsNothing);
    });

    testWidgets('without hours (an older server) the block is not there, the rest is', (tester) async {
      final env = await _env(field: _field(hours: const []));
      await _openHome(tester, env);
      expect(keyed('home-hours'), findsNothing);
      expect(keyed('home-hero'), findsOneWidget);
      expect(keyed('home-spray-ok'), findsOneWidget);
    });
  });

  group('can I spray today?', () {
    for (final (name, spray, state, title, say, checks) in [
      (
        'good',
        MockData.sprayGo,
        'ok',
        'Good time to spray',
        'Calm and dry for the next 6 hours.',
        {'wind': '8 km/h, light breeze', 'rain': 'none for 6 hours', 'heat': '18°, fine'},
      ),
      (
        'be careful: wind',
        const SprayOut(
          state: SprayStatus.care,
          headline: 'windy',
          wind: SprayCheckOut(status: SprayStatus.care, value: 22),
          rain: SprayCheckOut(value: 0, hours: 6),
          heat: SprayCheckOut(value: 24),
        ),
        'care',
        'Be careful',
        'It is windy now. Spray can drift to the next field. Wait for calmer air.',
        {'wind': '22 km/h, windy', 'rain': 'none for 6 hours', 'heat': '24°, fine'},
      ),
      (
        'be careful: heat',
        const SprayOut(
          state: SprayStatus.care,
          headline: 'hot',
          wind: SprayCheckOut(value: 5),
          rain: SprayCheckOut(value: 0),
          heat: SprayCheckOut(status: SprayStatus.care, value: 34),
        ),
        'care',
        'Be careful',
        'It is very hot. Spray in the cool of the morning or evening.',
        {'wind': '5 km/h, light breeze', 'rain': 'none expected', 'heat': '34°, hot'},
      ),
      (
        'not now: rain soon',
        const SprayOut(
          state: SprayStatus.stop,
          headline: 'rain_soon',
          wind: SprayCheckOut(value: 5),
          rain: SprayCheckOut(status: SprayStatus.stop, value: 8.2, hours: 2),
          heat: SprayCheckOut(value: 19),
        ),
        'stop',
        'Not now',
        'Rain is coming within 2 hours. A spray would be washed off.',
        {'wind': '5 km/h, light breeze', 'rain': '8.2 mm in 3 hours', 'heat': '19°, fine'},
      ),
      (
        'not now: raining',
        const SprayOut(
          state: SprayStatus.stop,
          headline: 'raining',
          wind: SprayCheckOut(value: 2),
          rain: SprayCheckOut(status: SprayStatus.stop, value: 3, hours: 0),
          heat: SprayCheckOut(value: 15),
        ),
        'stop',
        'Not now',
        'It is raining now. Do not spray.',
        {'wind': '2 km/h, calm', 'rain': 'raining now', 'heat': '15°, fine'},
      ),
    ]) {
      testWidgets(name, (tester) async {
        final env = await _env(field: _field(spray: spray));
        await _openHome(tester, env);
        expect(keyed('home-spray-$state'), findsOneWidget);
        expect(_plain(tester, 'home-spray-title'), title);
        expect(_plain(tester, 'home-spray-say'), say);
        for (final e in checks.entries) {
          expect(_plain(tester, 'home-spray-value-${e.key}'), e.value, reason: e.key);
        }
      });
    }

    testWidgets('a touch on the card says it aloud, without digits', (tester) async {
      final env = await _env(
        field: _field(
          spray: const SprayOut(
            state: SprayStatus.stop,
            headline: 'rain_soon',
            rain: SprayCheckOut(status: SprayStatus.stop, value: 8, hours: 2),
          ),
        ),
      );
      await _openHome(tester, env);
      env.voice.clear();
      await tapKey(tester, 'home-spray-stop');
      expect(env.voice.spokenTexts, ['Not now. Rain is coming soon and would wash the spray off.']);
      expect(env.voice.spokenTexts.single, isNot(contains(RegExp('[0-9]'))));
    });

    testWidgets('a server with the check switched off, or one the app does not understand: no card', (tester) async {
      var env = await _env(field: _field(spray: null));
      await _openHome(tester, env);
      expect(find.text('CAN I SPRAY TODAY?'), findsNothing);
      expect(keyed('home-spray-ok'), findsNothing);
      await tester.pumpWidget(const SizedBox());

      // The answer as the server writes it, with a state from the future.
      final fromJson = FieldOut.fromJson({
        ..._field().toJson(),
        'spray': {'state': 'maybe', 'headline': 'x'},
      });
      env = await _env(field: fromJson);
      await _openHome(tester, env);
      expect(find.text('CAN I SPRAY TODAY?'), findsNothing);
    });

    testWidgets('an old answer (kept on the phone) never says "good time to spray"', (tester) async {
      final env = await _env();
      await _openHome(tester, env);
      expect(keyed('home-spray-ok'), findsOneWidget, reason: 'online it does');
      await tester.pumpWidget(const SizedBox());
      // The same farmer, no internet: the answer comes from the phone's memory.
      env.api.failWith(const ApiException.network(), ops: {'field'});
      await tester.pumpWidget(env.app(location: '/home'));
      await tester.pumpAndSettle();
      expect(keyed('home-hero'), findsOneWidget, reason: 'the old weather is still shown');
      expect(keyed('home-spray-ok'), findsNothing);
      expect(find.text('CAN I SPRAY TODAY?'), findsNothing);
    });
  });

  group('rain of the week', () {
    testWidgets('seven bars, today first, the wet days taller; the sentence says the next rain', (tester) async {
      final env = await _env();
      await _openHome(tester, env);
      final days = MockData.field().forecast;
      expect(days, hasLength(7));
      for (final day in days) {
        expect(keyed('home-rain-${day.day}'), findsOneWidget, reason: day.day);
      }
      expect(find.descendant(of: keyed('home-rain-2026-05-12'), matching: find.text('Today')), findsOneWidget);
      expect(find.descendant(of: keyed('home-rain-2026-05-14'), matching: find.text('12')), findsOneWidget);
      expect(find.descendant(of: keyed('home-rain-2026-05-12'), matching: find.text('0')), findsOneWidget);
      final wet = tester.getSize(
        find.descendant(of: keyed('home-rain-2026-05-14'), matching: find.byType(Container)).first,
      );
      final dry = tester.getSize(
        find.descendant(of: keyed('home-rain-2026-05-13'), matching: find.byType(Container)).first,
      );
      expect(wet.height, greaterThan(dry.height * 5));
      expect(_plain(tester, 'home-rain-sentence'), 'Next rain on Thursday. About 24 mm in the week.');
    });

    testWidgets('a touch on the sentence says it without the number', (tester) async {
      final env = await _env();
      await _openHome(tester, env);
      env.voice.clear();
      await tapKey(tester, 'home-rain-say');
      expect(env.voice.spokenTexts, ['The next rain is on Thursday.']);
    });

    testWidgets('rain today, and no rain at all', (tester) async {
      var env = await _env(
        field: _field(
          forecast: [
            for (var i = 0; i < 7; i++)
              ForecastDayOut(day: '2026-05-${12 + i}', tminC: 8, tmaxC: 18, rainMm: i == 0 ? 4 : 0),
          ],
        ),
      );
      await _openHome(tester, env);
      expect(_plain(tester, 'home-rain-sentence'), 'It rains today. About 4 mm in the week.');
      await tester.pumpWidget(const SizedBox());

      env = await _env(
        field: _field(
          forecast: [for (var i = 0; i < 7; i++) ForecastDayOut(day: '2026-05-${12 + i}', tminC: 8, tmaxC: 18)],
        ),
      );
      await _openHome(tester, env);
      expect(_plain(tester, 'home-rain-sentence'), 'No rain is expected in the next days.');
      env.voice.clear();
      await tapKey(tester, 'home-rain-say');
      expect(env.voice.spokenTexts, ['No rain is expected this week.']);
    });

    testWidgets('no week, no chart', (tester) async {
      final env = await _env(field: _field(forecast: const []));
      await _openHome(tester, env);
      expect(keyed('home-rain-week'), findsNothing);
      expect(find.text('RAIN IN THE NEXT DAYS'), findsNothing);
    });
  });

  group('the air and the sun', () {
    testWidgets('six tiles with their words', (tester) async {
      final env = await _env();
      await _openHome(tester, env);
      Finder inTile(String id, String text) => find.descendant(of: keyed('home-tile-$id'), matching: find.text(text));
      expect(_plain(tester, 'home-tile-value-aqi'), '64');
      expect(inTile('aqi', 'Moderate'), findsOneWidget);
      expect(_plain(tester, 'home-tile-value-visibility'), '6 km');
      expect(inTile('visibility', 'Hazy'), findsOneWidget);
      expect(_plain(tester, 'home-tile-value-dew'), '14°');
      expect(inTile('dew', 'Dew forms when it gets this cold'), findsOneWidget);
      expect(_plain(tester, 'home-tile-value-pressure'), '1012 mb');
      expect(inTile('pressure', 'Sea level'), findsOneWidget);
      expect(_plain(tester, 'home-tile-value-sun'), clockText(_en, DateTime.utc(2026, 5, 12, 0, 10)));
      expect(inTile('sun', 'Sets at ${clockText(_en, DateTime.utc(2026, 5, 12, 13, 40))}'), findsOneWidget);
      expect(_plain(tester, 'home-tile-value-uv'), '7');
      expect(inTile('uv', 'High: wear a hat'), findsOneWidget);
    });

    testWidgets('a tile the server has no number for is not there; none at all, no block', (tester) async {
      var env = await _env(
        field: _field(conditions: const ConditionsOut(sky: 'clear', isDay: true, aqi: 40, uvIndex: 2)),
      );
      await _openHome(tester, env);
      expect(keyed('home-tile-aqi'), findsOneWidget);
      expect(keyed('home-tile-uv'), findsOneWidget);
      expect(keyed('home-tile-visibility'), findsNothing);
      expect(keyed('home-tile-sun'), findsNothing);
      await tester.pumpWidget(const SizedBox());

      env = await _env(
        field: _field(conditions: const ConditionsOut(sky: 'clear', isDay: true)),
      );
      await _openHome(tester, env);
      expect(keyed('home-air-grid'), findsNothing);
      expect(find.text('MORE ABOUT THE AIR'), findsNothing);
    });
  });

  group('every size and language', () {
    for (final (size, scale) in [
      (const Size(320, 568), 2.0),
      (const Size(360, 640), 1.0),
      (const Size(390, 844), 1.0),
      (const Size(411, 900), 1.6),
    ]) {
      for (final language in ['en', 'hi']) {
        testWidgets('${size.width.toInt()}x${size.height.toInt()}, text size $scale, $language', (tester) async {
          final handle = tester.ensureSemantics();
          final env = await _env(language: language);
          await _openHome(tester, env, size: size, textScale: scale);
          expect(tester.takeException(), isNull);
          expect(keyed('home-hero'), findsOneWidget);
          // Every block, scrolled to: nothing overflows at any size.
          for (final key in ['home-spray-ok', 'home-rain-week', 'home-air-grid']) {
            await tester.ensureVisible(keyed(key));
            await tester.pump();
            expect(tester.takeException(), isNull, reason: key);
          }
          expectBigTouchTargets(tester);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          handle.dispose();
        });
      }
    }

    testWidgets('Hindi: the blocks have their Hindi headings and words', (tester) async {
      final env = await _env(language: 'hi');
      await _openHome(tester, env);
      expect(find.text('अगले घंटे'), findsOneWidget);
      expect(find.text('क्या आज छिड़काव ठीक है?'), findsOneWidget);
      expect(find.text('अगले दिनों की बारिश'), findsOneWidget);
      expect(find.text('हवा के बारे में और'), findsOneWidget);
      expect(find.text('छिड़काव का अच्छा समय'), findsOneWidget);
      expect(find.descendant(of: keyed('home-hour-0'), matching: find.text('अभी')), findsOneWidget);
    });
  });
}
