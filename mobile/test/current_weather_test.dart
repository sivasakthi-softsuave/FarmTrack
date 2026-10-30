import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmtrack/core/models/models.dart';
import 'package:farmtrack/core/network/mock_api_client.dart';
import 'package:farmtrack/core/network/mock_data.dart';
import 'package:farmtrack/features/diary/date_words.dart';
import 'package:farmtrack/core/theme/app_theme.dart';
import 'package:farmtrack/features/field/weather_glyph.dart';
import 'package:farmtrack/features/field/weather_words.dart';

import 'support/feature_fakes.dart';
import 'support/finders.dart';
import 'support/harness.dart';

/// "Weather now": the temperature, the sky and the details of a weather app (air quality, wind, humidity, visibility, pressure, dew
/// point) on "My field", from the `conditions` of the server's field answer.
void main() {
  Future<TestEnv> envWith(FieldOut field, {String language = 'en'}) => TestEnv.create(
    loggedIn: true,
    language: language,
    api: MockApiClient(latency: Duration.zero)..fieldOverride = field,
    extraOverrides: [clockProvider.overrideWithValue(() => fixedNow)],
  );

  Future<void> openField(WidgetTester tester, TestEnv env, {double textScale = 1.0, Size? size}) async {
    useSmallPhone(tester, textScale: textScale, size: size ?? const Size(390, 844));
    await pumpApp(tester, env, location: '/home');
    await tapKey(tester, 'home-field');
  }

  String text(WidgetTester tester, String key) => tester.widget<Text>(keyed(key)).data!;

  group('the conditions of the server', () {
    test('every part is read, with the units the server uses', () {
      final c = ConditionsOut.fromJson(const {
        'sky': 'mostly_clear',
        'is_day': true,
        'feels_like_c': 37.2,
        'wind_kmh': 8,
        'visibility_km': 4.5,
        'pressure_hpa': 1008.4,
        'dew_point_c': 26,
        'aqi': 64,
      });
      expect(c.sky, 'mostly_clear');
      expect(c.isDay, isTrue);
      expect(c.feelsLikeC, 37.2);
      expect(c.windKmh, 8);
      expect(c.visibilityKm, 4.5);
      expect(c.pressureHpa, 1008.4);
      expect(c.dewPointC, 26);
      expect(c.aqi, 64);
      expect(c.isEmpty, isFalse);
      expect(ConditionsOut.fromJson(c.toJson()).toJson(), c.toJson(), reason: 'it survives the phone\'s own copy');
    });

    test('a missing part stays missing; an answer without conditions is fine', () {
      final c = ConditionsOut.fromJson(const {'sky': null, 'wind_kmh': 5, 'aqi': null});
      expect(c.sky, isNull);
      expect(c.isDay, isNull);
      expect(c.windKmh, 5);
      expect(c.aqi, isNull);
      expect(ConditionsOut.fromJson(const {}).isEmpty, isTrue);
      expect(FieldOut.fromJson(const {}).conditions, isNull, reason: 'an older server sends none');
      final field = FieldOut.fromJson(const {
        'conditions': {'sky': 'rain', 'aqi': 120},
      });
      expect(field.conditions!.sky, 'rain');
      expect(field.conditions!.aqi, 120);
    });
  });

  group('the words and pictures', () {
    test('the word for the sky, with the night names of the sunny skies', () {
      expect(skyWordKey('clear'), 'sky_clear');
      expect(skyWordKey('clear', isDay: false), 'sky_clear_night');
      expect(skyWordKey('mostly_clear', isDay: false), 'sky_mostly_clear_night');
      expect(skyWordKey('cloudy', isDay: false), 'sky_cloudy', reason: 'only the sunny skies change at night');
      expect(skyWordKey('thunderstorm'), 'sky_thunderstorm');
      expect(skyWordKey('hail'), isNull, reason: 'a sky the app has no word for');
      expect(skyWordKey(null), isNull);
    });

    test('the air quality bands are the bands of the US index', () {
      final bands = {
        0: AqiBand.good,
        50: AqiBand.good,
        51: AqiBand.moderate,
        100: AqiBand.moderate,
        101: AqiBand.sensitive,
        150: AqiBand.sensitive,
        151: AqiBand.unhealthy,
        200: AqiBand.unhealthy,
        201: AqiBand.veryUnhealthy,
        300: AqiBand.veryUnhealthy,
        301: AqiBand.hazardous,
        500: AqiBand.hazardous,
      };
      bands.forEach((aqi, band) => expect(aqiBand(aqi), band, reason: 'AQI $aqi'));
      expect(aqiSeverity(AqiBand.good), Severity.green);
      expect(aqiSeverity(AqiBand.moderate), Severity.yellow);
      expect(aqiSeverity(AqiBand.sensitive), Severity.yellow);
      expect(aqiSeverity(AqiBand.unhealthy), Severity.red);
      expect(aqiSeverity(AqiBand.hazardous), Severity.red);
      expect(aqiWordKey(AqiBand.veryUnhealthy), 'aqi_very_unhealthy');
    });

    test('numbers are written like a weather app writes them', () {
      expect(plainNumber(4), '4');
      expect(plainNumber(9.74), '9.7');
      expect(plainNumber(23.96), '24');
      expect(plainNumber(0.04), '0');
      expect(plainNumber(0.5), '0.5');
    });

    test('the picture follows the sky, and the moon replaces the sun at night', () {
      expect(weatherKindOfSky('clear'), WeatherKind.sun);
      expect(weatherKindOfSky('clear', isDay: false), WeatherKind.moon);
      expect(weatherKindOfSky('mostly_clear'), WeatherKind.partlySunny);
      expect(weatherKindOfSky('partly_cloudy'), WeatherKind.partlySunny);
      expect(weatherKindOfSky('partly_cloudy', isDay: false), WeatherKind.cloud);
      expect(weatherKindOfSky('cloudy'), WeatherKind.cloud);
      expect(weatherKindOfSky('fog'), WeatherKind.cloud);
      expect(weatherKindOfSky('drizzle'), WeatherKind.lightRain);
      expect(weatherKindOfSky('showers'), WeatherKind.lightRain);
      expect(weatherKindOfSky('rain'), WeatherKind.heavyRain);
      expect(weatherKindOfSky('heavy_rain'), WeatherKind.heavyRain);
      expect(weatherKindOfSky('thunderstorm'), WeatherKind.heavyRain);
      expect(weatherKindOfSky('snow'), WeatherKind.snow);
      expect(weatherKindOfSky(null), WeatherKind.cloud);
    });
  });

  group('the card on My field', () {
    testWidgets('the picture, the big temperature, the word, how it feels and the six details', (tester) async {
      await openField(tester, await envWith(MockData.field()));
      expect(keyed('weather-card'), findsOneWidget);
      expect(find.text('WEATHER NOW'), findsOneWidget);
      expect(tester.widget<Text>(keyed('weather-temp')).textSpan!.toPlainText(), '18°C', reason: '17.5 rounded');
      expect(text(tester, 'weather-sky'), 'Partly cloudy');
      expect(text(tester, 'weather-feels'), 'Feels like 16°');
      expect(tester.widget<WeatherGlyph>(keyed('weather-glyph')).kind, WeatherKind.partlySunny);

      expect(text(tester, 'weather-value-aqi'), '64');
      expect(find.descendant(of: keyed('weather-detail-aqi'), matching: find.text('Moderate')), findsOneWidget);
      expect(text(tester, 'weather-value-wind'), '8 km/h');
      expect(text(tester, 'weather-value-humidity'), '82 %');
      expect(text(tester, 'weather-value-visibility'), '6 km');
      expect(text(tester, 'weather-value-pressure'), '1012 mb');
      expect(text(tester, 'weather-value-dew'), '14°');
      for (final label in ['Air quality', 'Wind', 'Humidity', 'Visibility', 'Pressure', 'Dew point']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }

      // Three details in a row, in the weather app's order.
      final ids = ['aqi', 'wind', 'humidity', 'visibility', 'pressure', 'dew'];
      final rects = [for (final id in ids) tester.getRect(keyed('weather-detail-$id'))];
      for (var i = 1; i < 3; i++) {
        expect(rects[i].left, greaterThan(rects[i - 1].left));
        expect(rects[i].top, closeTo(rects[0].top, 0.5), reason: 'first row');
        expect(rects[i + 3].top, closeTo(rects[3].top, 0.5), reason: 'second row');
      }
      expect(rects[3].top, greaterThan(rects[0].top));
      expect(rects[3].left, closeTo(rects[0].left, 0.5), reason: 'the rows line up');

      // The air quality has a dot in the colour of its band (amber for "moderate"); the weather comes first, the week after it.
      final dot = find.descendant(
        of: keyed('weather-detail-aqi'),
        matching: find.byWidgetPredicate(
          (w) => w is Container && (w.decoration as BoxDecoration?)?.color == AppColors.amber,
        ),
      );
      expect(dot, findsOneWidget);
      expect(tester.getTopLeft(keyed('weather-card')).dy, lessThan(tester.getTopLeft(keyed('forecast-strip')).dy));
    });

    testWidgets('the words and units are in the language of the farmer', (tester) async {
      await openField(tester, await envWith(MockData.field(), language: 'hi'));
      expect(text(tester, 'weather-sky'), 'कुछ बादल');
      expect(text(tester, 'weather-feels'), 'महसूस हो रहा है 16°');
      expect(text(tester, 'weather-value-wind'), '8 किमी/घंटा');
      expect(text(tester, 'weather-value-visibility'), '6 किमी');
      expect(find.text('हवा की गुणवत्ता'), findsOneWidget);
      expect(find.text('अभी का मौसम'), findsOneWidget);
    });

    testWidgets('only what the server knows is shown; at night the sun is the moon', (tester) async {
      final field = FieldOut(
        readings: const ReadingsOut(tempC: 12),
        conditions: const ConditionsOut(sky: 'clear', isDay: false, windKmh: 3),
        forecast: MockData.field().forecast,
      );
      await openField(tester, await envWith(field));
      expect(text(tester, 'weather-sky'), 'Clear');
      expect(tester.widget<WeatherGlyph>(keyed('weather-glyph')).kind, WeatherKind.moon);
      expect(keyed('weather-feels'), findsNothing);
      expect(text(tester, 'weather-value-wind'), '3 km/h');
      for (final id in ['aqi', 'humidity', 'visibility', 'pressure', 'dew']) {
        expect(keyed('weather-detail-$id'), findsNothing, reason: id);
      }
    });

    testWidgets('an air quality in a bad band gets a red dot and its word', (tester) async {
      final field = FieldOut(
        readings: const ReadingsOut(tempC: 30, rhPct: 40),
        conditions: const ConditionsOut(aqi: 180),
      );
      await openField(tester, await envWith(field));
      expect(find.descendant(of: keyed('weather-detail-aqi'), matching: find.text('Unhealthy')), findsOneWidget);
      final red = find.descendant(
        of: keyed('weather-detail-aqi'),
        matching: find.byWidgetPredicate(
          (w) => w is Container && (w.decoration as BoxDecoration?)?.color == AppColors.red,
        ),
      );
      expect(red, findsOneWidget);
      expect(keyed('weather-glyph'), findsNothing, reason: 'no sky, no picture');
      expect(keyed('weather-sky'), findsNothing);
    });

    testWidgets('a server without the details (an older one) still gives the temperature and the humidity', (
      tester,
    ) async {
      final field = FieldOut(readings: const ReadingsOut(tempC: 20.4, rhPct: 61), forecast: MockData.field().forecast);
      await openField(tester, await envWith(field));
      expect(tester.widget<Text>(keyed('weather-temp')).textSpan!.toPlainText(), '20°C');
      expect(text(tester, 'weather-value-humidity'), '61 %');
      expect(keyed('weather-glyph'), findsNothing);
      expect(keyed('weather-detail-wind'), findsNothing);
    });

    testWidgets('nothing known about the weather: no card (the soil sensor alone does not make one)', (tester) async {
      final field = FieldOut(readings: const ReadingsOut(soilMoisturePct: 31), forecast: MockData.field().forecast);
      await openField(tester, await envWith(field));
      expect(keyed('weather-card'), findsNothing);
      expect(find.text('WEATHER NOW'), findsNothing);
      expect(keyed('forecast-strip'), findsOneWidget);
    });

    for (final (name, size, scale) in [
      ('360 x 640', const Size(360, 640), 1.0),
      ('320 x 568 at 1.6 times the text', const Size(320, 568), 1.6),
      ('320 x 568 at twice the text', const Size(320, 568), 2.0),
    ]) {
      testWidgets('it fits a small phone: $name', (tester) async {
        for (final language in ['en', 'hi']) {
          await openField(
            tester,
            await envWith(MockData.field(), language: language),
            textScale: scale,
            size: size,
          );
          expect(keyed('weather-card'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: '$language: no overflow');
          expectBigTouchTargets(tester);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      });
    }
  });
}
