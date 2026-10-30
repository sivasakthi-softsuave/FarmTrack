import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmtrack/core/errors/api_exception.dart';
import 'package:farmtrack/core/models/models.dart';
import 'package:farmtrack/core/network/mock_api_client.dart';
import 'package:farmtrack/features/diary/date_words.dart';

import 'support/feature_fakes.dart';
import 'support/finders.dart';
import 'support/harness.dart';

/// A server whose `/v1/meta` says [weatherEnabled] (null: the old answer without the field), or is unreachable.
class _MetaApi extends MockApiClient {
  _MetaApi({this.weatherEnabled, this.unreachable = false}) : super(latency: Duration.zero);

  bool? weatherEnabled;
  bool unreachable;

  @override
  Future<MetaOut> meta() async {
    if (unreachable) throw const ApiException.network('offline');
    return MetaOut.fromJson({
      'app_version': '1',
      'supported_languages': ['hi', 'en'],
      if (weatherEnabled != null) 'weather_enabled': weatherEnabled,
    });
  }
}

Future<TestEnv> _env(MockApiClient api) =>
    TestEnv.create(loggedIn: true, api: api, extraOverrides: [clockProvider.overrideWithValue(() => fixedNow)]);

Future<void> _openField(WidgetTester tester, TestEnv env) async {
  useSmallPhone(tester);
  await pumpApp(tester, env, location: '/home');
  await tapKey(tester, 'home-field');
}

void main() {
  test('MetaOut: weather_enabled is read, and a missing field means true', () {
    expect(MetaOut.fromJson({'weather_enabled': false}).weatherEnabled, isFalse);
    expect(MetaOut.fromJson({'weather_enabled': true}).weatherEnabled, isTrue);
    expect(MetaOut.fromJson({'app_version': '1'}).weatherEnabled, isTrue);
    expect(MetaOut.fromJson({'weather_enabled': 'no'}).weatherEnabled, isTrue, reason: 'only a real boolean counts');
    expect(MetaOut.fromJson(MetaOut.fromJson({'weather_enabled': false}).toJson()).weatherEnabled, isFalse);
  });

  group('My field with weather switched off on the server', () {
    testWidgets('weather tiles and the forecast are hidden, the soil sensor and the risks stay', (tester) async {
      final env = await _env(_MetaApi(weatherEnabled: false));
      await _openField(tester, env);
      expect(keyed('reading-temp'), findsNothing);
      expect(keyed('reading-humidity'), findsNothing);
      expect(keyed('reading-rain'), findsNothing);
      expect(keyed('reading-leaf'), findsNothing);
      expect(keyed('reading-soil'), findsOneWidget);
      expect(keyed('forecast-strip'), findsNothing);
      expect(keyed('weather-card'), findsNothing, reason: 'the weather card is weather too');
      expect(env.prefs.getBool('weather_enabled'), isFalse, reason: 'remembered for the next time offline');
    });

    testWidgets('the soil tile stays in the same blue card language, under its label', (tester) async {
      final api = _MetaApi(weatherEnabled: false);
      final env = await _env(api);
      await _openField(tester, env);
      expect(find.text('अभी आपके खेत में'), findsOneWidget, reason: 'the label of the tiles');
      expect(find.text('अगले सात दिन'), findsNothing, reason: 'no week card without weather');
      final soil = tester.getRect(keyed('reading-soil'));
      expect(soil.width, closeTo((360 - 32 - 10) / 2, 0.5), reason: 'half the width, like every tile');
    });

    testWidgets('with no soil reading either, there is no empty "Now in your field" label: the no-data card shows', (
      tester,
    ) async {
      final api = _MetaApi(weatherEnabled: false)
        ..fieldOverride = FieldOut(
          village: 'Kotgarh',
          asOf: DateTime.utc(2026, 5, 12, 2, 30),
          readings: const ReadingsOut(tempC: 20, rhPct: 60),
        );
      final env = await _env(api);
      await _openField(tester, env);
      expect(keyed('reading-temp'), findsNothing);
      expect(find.text('अभी आपके खेत में'), findsNothing);
      expect(keyed('field-no-data'), findsOneWidget, reason: 'never a blank page');
    });

    testWidgets('the round arrow asks the server again: weather switched on meanwhile shows the weather', (
      tester,
    ) async {
      final api = _MetaApi(weatherEnabled: false);
      final env = await _env(api);
      await _openField(tester, env);
      expect(keyed('reading-temp'), findsNothing);
      expect(keyed('forecast-strip'), findsNothing);
      expect(keyed('weather-card'), findsNothing, reason: 'the weather card is weather too');

      api.weatherEnabled = true;
      await tapKey(tester, 'field-reload');
      expect(keyed('reading-temp'), findsOneWidget);
      expect(keyed('reading-leaf'), findsOneWidget);
      expect(keyed('forecast-strip'), findsOneWidget);
      expect(keyed('weather-card'), findsOneWidget);
      expect(env.prefs.getBool('weather_enabled'), isTrue);
    });

    testWidgets('weather on (or a server that does not know the field) shows everything', (tester) async {
      for (final enabled in [true, null]) {
        final env = await _env(_MetaApi(weatherEnabled: enabled));
        await _openField(tester, env);
        expect(keyed('reading-temp'), findsOneWidget, reason: 'weather_enabled=$enabled');
        expect(keyed('reading-rain'), findsOneWidget);
        expect(keyed('forecast-strip'), findsOneWidget);
        expect(keyed('weather-card'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('offline, the last answer of the server is used; with none, weather is shown', (tester) async {
      final api = _MetaApi(unreachable: true);
      var env = await _env(api);
      await _openField(tester, env);
      expect(keyed('reading-temp'), findsOneWidget, reason: 'never heard: shown');
      await tester.pumpWidget(const SizedBox());

      env = await _env(api);
      await env.prefs.setBool('weather_enabled', false);
      await _openField(tester, env);
      expect(keyed('reading-temp'), findsNothing, reason: 'the server said off the last time');
      expect(keyed('reading-soil'), findsOneWidget);
    });
  });
}
