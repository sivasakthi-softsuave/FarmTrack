import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmtrack/core/errors/api_exception.dart';
import 'package:farmtrack/core/location/device_location.dart';
import 'package:farmtrack/core/models/models.dart';
import 'package:farmtrack/core/network/mock_api_client.dart';
import 'package:farmtrack/core/network/mock_data.dart';
import 'package:farmtrack/features/diary/date_words.dart';
import 'package:farmtrack/core/widgets/design.dart';
import 'package:farmtrack/features/field/place_providers.dart';

import 'support/feature_fakes.dart';
import 'support/finders.dart';
import 'support/harness.dart';

/// A phone whose position (or reason for having none) the test decides.
class PlaceGps implements DeviceLocation {
  PlaceGps({this.point, this.failure});

  final GeoPoint? point;
  final LocationFailure? failure;
  int calls = 0;

  @override
  Future<GeoPoint> current() async {
    calls++;
    final f = failure;
    if (f != null) throw DeviceLocationException(f);
    return point!;
  }
}

/// A server that has the place picker switched off (an older server, or PLACE_WEATHER_PROVIDER / PLACES_PROVIDER = none).
class _NoPlacesApi extends MockApiClient {
  _NoPlacesApi({this.weather = false}) : super(latency: Duration.zero);

  final bool weather;

  @override
  Future<MetaOut> meta() async => MetaOut(appVersion: '0.1.0', env: 'mock', placeWeatherEnabled: weather);
}

Future<TestEnv> placeEnv({MockApiClient? api, PlaceGps? gps, String language = 'en', bool savedFlag = true}) async {
  final env = await _createPlaceEnv(api: api, gps: gps, language: language);
  // Home reads the SAVED answer of the server (it never asks by itself under flutter test): the mock server has the picker on.
  if (savedFlag) await env.prefs.setBool('place_weather_enabled', true);
  return env;
}

Future<TestEnv> _createPlaceEnv({MockApiClient? api, PlaceGps? gps, String language = 'en'}) => TestEnv.create(
  loggedIn: true,
  language: language,
  api: api ?? MockApiClient(latency: Duration.zero),
  extraOverrides: [
    clockProvider.overrideWithValue(() => fixedNow),
    mapTileUrlProvider.overrideWithValue(null), // no tile downloads in tests; the credit line is still drawn
    if (gps != null) deviceLocationProvider.overrideWithValue(gps),
  ],
);

Future<void> openField(WidgetTester tester, TestEnv env, {double textScale = 1.0, Size? size}) async {
  useSmallPhone(tester, textScale: textScale, size: size ?? const Size(360, 640));
  await pumpApp(tester, env, location: '/home');
  env.voice.clear();
  await tapKey(tester, 'home-field');
}

Future<void> openPicker(WidgetTester tester) async {
  await tapKey(tester, 'place-bar');
  expect(keyed('place-gps'), findsOneWidget, reason: 'the picker is open');
}

String placeName(WidgetTester tester) => tester.widget<Text>(keyed('place-name')).data!;

/// A tap on the map is told apart from a double tap, so it arrives a moment later.
Future<void> tapMap(WidgetTester tester) async {
  await tester.tap(keyed('place-map'));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

void main() {
  group('place picker: the data', () {
    test('a place is the same question as another within about a kilometre', () {
      const a = PickedPlace(label: 'A', lat: 31.1197, lon: 77.3567);
      const b = PickedPlace(label: 'B', lat: 31.1202, lon: 77.3571);
      const far = PickedPlace(label: 'A', lat: 31.2, lon: 77.4);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(far));
    });

    test('the map zooms further in on a village than on a state', () {
      expect(zoomForKind('state'), lessThan(zoomForKind('district')));
      expect(zoomForKind('district'), lessThan(zoomForKind('tehsil')));
      expect(zoomForKind('tehsil'), lessThan(zoomForKind('town')));
      expect(zoomForKind('town'), lessThan(zoomForKind('village')));
      expect(zoomForKind('something new'), zoomForKind('place'));
    });

    test('the contract: places, and the two meta flags (an older server has neither: off)', () {
      final out = PlaceSearchOut.fromJson({
        'items': [
          {'name': 'Theog', 'label': 'Theog, Shimla, Himachal Pradesh', 'kind': 'tehsil', 'lat': 31.12, 'lon': 77.36},
        ],
      });
      expect(out.items.single.label, 'Theog, Shimla, Himachal Pradesh');
      expect(out.items.single.kind, 'tehsil');
      expect(out.items.single.lat, 31.12);
      expect(PlaceSearchOut.fromJson({}).items, isEmpty);
      expect(PlaceOut.fromJson({'name': 'X', 'label': 'X', 'lat': 1, 'lon': 2}).kind, 'place');

      final old = MetaOut.fromJson({'app_version': '1', 'env': 'x'});
      expect(old.placeWeatherEnabled, isFalse);
      expect(old.placesSearchEnabled, isFalse);
      final on = MetaOut.fromJson({'place_weather_enabled': true, 'places_search_enabled': true});
      expect(on.placeWeatherEnabled && on.placesSearchEnabled, isTrue);
      expect(
        MetaOut.fromJson(on.toJson()).placesSearchEnabled,
        isTrue,
        reason: 'it survives being saved and read back',
      );
    });

    test('the mock server offers both and finds places by any part of the label', () {
      final meta = MockData.meta();
      expect(meta.placeWeatherEnabled && meta.placesSearchEnabled, isTrue);
      expect(MockData.placeSearch('theog').items.single.name, 'Theog');
      expect(MockData.placeSearch('shimla').items.length, greaterThan(1));
      expect(MockData.placeSearch('shimla', limit: 1).items.length, 1);
      expect(MockData.placeSearch('zzz').items, isEmpty);
    });
  });

  group('My field: the place bar', () {
    testWidgets('names my field, and opens the picker with search, my location, the map and its credit', (
      tester,
    ) async {
      final env = await placeEnv();
      await openField(tester, env);

      expect(keyed('place-bar'), findsOneWidget);
      expect(placeName(tester), 'My own field');
      expect(keyed('place-clear'), findsNothing, reason: 'nothing to go back from');
      expect(keyed('reading-leaf'), findsOneWidget, reason: 'the farmer\'s own field is shown as before');

      await openPicker(tester);
      expect(keyed('place-search'), findsOneWidget);
      expect(keyed('place-map'), findsOneWidget);
      expect(
        find.text('© OpenStreetMap contributors'),
        findsOneWidget,
        reason: 'the map data licence needs this credit',
      );
      expect(
        tester.widget<Text>(find.descendant(of: keyed('place-confirm'), matching: find.byType(Text))).data,
        'Show weather here',
      );
      expect(env.voice.spokenTexts.last, 'Search a name, use your location, or touch the map.');
    });

    testWidgets('a server without the place picker shows the field exactly as before', (tester) async {
      final env = await placeEnv(api: _NoPlacesApi());
      await openField(tester, env);
      expect(keyed('place-bar'), findsNothing);
      expect(keyed('reading-leaf'), findsOneWidget);
    });

    testWidgets('weather of a place but no name search: the picker has no search box', (tester) async {
      final env = await placeEnv(api: _NoPlacesApi(weather: true));
      await openField(tester, env);
      await openPicker(tester);
      expect(keyed('place-search'), findsNothing);
      expect(keyed('place-gps'), findsOneWidget);
      expect(keyed('place-map'), findsOneWidget);
    });
  });

  group('choosing a place by name', () {
    testWidgets('the weather of the chosen place replaces the field; its name is said first', (tester) async {
      final api = MockApiClient(latency: Duration.zero);
      final env = await placeEnv(api: api);
      await openField(tester, env);
      await openPicker(tester);

      await tester.enterText(keyed('place-search'), 'Theog');
      await tapKey(tester, 'place-search-go');
      expect(keyed('place-results'), findsOneWidget);
      expect(api.placeQueries.single, (
        query: 'Theog',
        lang: 'en',
        limit: 5,
      ), reason: 'asked once, on submit, not per letter');
      expect(find.text('Theog, Shimla, Himachal Pradesh'), findsOneWidget);

      env.voice.clear();
      await tapKey(tester, 'place-result-0');

      expect(keyed('place-results'), findsNothing, reason: 'back on My field');
      expect(placeName(tester), 'Theog, Shimla, Himachal Pradesh');
      expect(keyed('place-clear'), findsOneWidget);
      expect(api.weatherAtCalls.single.lat, closeTo(31.11989, 1e-6));
      expect(api.weatherAtCalls.single.lon, closeTo(77.36362, 1e-6));
      expect(tester.widget<Text>(keyed('reading-digits-temp')).data, '12 °C');
      expect(tester.widget<Text>(keyed('reading-digits-rain')).data, '0.4 mm');
      expect(keyed('reading-leaf'), findsNothing, reason: 'a place has no leaf sensor');
      expect(keyed('reading-soil'), findsNothing);
      expect(keyed('forecast-strip'), findsOneWidget);
      expect(find.text('NOW AT THIS PLACE'), findsOneWidget, reason: 'not "Now in your field"');
      // The weather of the place has the same card: the sky, how it feels, the air quality ("Good" at 32) and the rest.
      expect(find.text('Mostly sunny'), findsOneWidget);
      expect(tester.widget<Text>(keyed('weather-value-aqi')).data, '32');
      expect(tester.widget<Text>(keyed('weather-value-visibility')).data, '24 km');
      expect(find.text('NOW IN YOUR FIELD'), findsNothing);
      expect(env.voice.spokenTexts, ['Theog, Shimla, Himachal Pradesh', MockData.placeWeather().spoken.text.en]);
      expect(env.voice.spokenIds, isEmpty, reason: 'not "this is your field"');
    });

    testWidgets('the language of the app is the language of the search', (tester) async {
      final api = MockApiClient(latency: Duration.zero);
      final env = await placeEnv(api: api, language: 'hi');
      await openField(tester, env);
      await openPicker(tester);
      await tester.enterText(keyed('place-search'), 'Kullu');
      await tapKey(tester, 'place-search-go');
      expect(api.placeQueries.single.lang, 'hi');
    });

    testWidgets('a very short word is not searched', (tester) async {
      final api = MockApiClient(latency: Duration.zero);
      final env = await placeEnv(api: api);
      await openField(tester, env);
      await openPicker(tester);
      await tester.enterText(keyed('place-search'), 'T');
      await tapKey(tester, 'place-search-go');
      expect(api.placeQueries, isEmpty);
    });

    testWidgets('no place found says so, and the map is one touch away', (tester) async {
      final env = await placeEnv();
      await openField(tester, env);
      await openPicker(tester);
      env.voice.clear();
      await tester.enterText(keyed('place-search'), 'zzzz');
      await tapKey(tester, 'place-search-go');
      expect(keyed('place-no-results'), findsOneWidget);
      expect(env.voice.spokenTexts, ['No place found. Try another name.']);
      await tapKey(tester, 'place-results-close');
      expect(keyed('place-map'), findsOneWidget);
    });

    testWidgets('a search that fails says so and keeps the picker', (tester) async {
      final api = MockApiClient(latency: Duration.zero)
        ..failWith(
          const ApiException(kind: ApiErrorKind.server, code: 'places_unavailable', statusCode: 503),
          ops: {'searchPlaces'},
        );
      final env = await placeEnv(api: api);
      await openField(tester, env);
      await openPicker(tester);
      env.voice.clear();
      await tester.enterText(keyed('place-search'), 'Theog');
      await tapKey(tester, 'place-search-go');
      expect(tester.widget<Text>(keyed('place-message')).data, 'The search is not working now. Please try again.');
      expect(env.voice.spokenTexts, ['The search is not working now. Please try again.']);
      expect(keyed('place-map'), findsOneWidget, reason: 'the farmer can still use the map');
    });
  });

  group('my location', () {
    testWidgets('one touch: the phone\'s position is the place', (tester) async {
      final api = MockApiClient(latency: Duration.zero);
      final gps = PlaceGps(point: (lat: 31.2, lon: 77.4));
      final env = await placeEnv(api: api, gps: gps);
      await openField(tester, env);
      await openPicker(tester);
      await tapKey(tester, 'place-gps');
      expect(gps.calls, 1);
      expect(
        placeName(tester),
        'Kotgarh, Kumharsain, Shimla, Himachal Pradesh',
        reason: 'the real name of the area, not "My location"',
      );
      expect(api.reverseCalls.single, (lat: 31.2, lon: 77.4, lang: 'en'));
      expect(api.weatherAtCalls.single, (lat: 31.2, lon: 77.4));
    });

    for (final (reason, words) in [
      (LocationFailure.denied, 'Allow location for this app in the phone settings.'),
      (LocationFailure.deniedForever, 'Allow location for this app in the phone settings.'),
      (LocationFailure.serviceOff, 'Turn on the location (GPS) of the phone.'),
      (LocationFailure.timeout, 'Could not find your location. Try again in the open.'),
      (LocationFailure.unknown, 'Could not find your location. Try again in the open.'),
    ]) {
      testWidgets('$reason: says what to do and stays on the picker', (tester) async {
        final api = MockApiClient(latency: Duration.zero);
        final env = await placeEnv(
          api: api,
          gps: PlaceGps(failure: reason),
        );
        await openField(tester, env);
        await openPicker(tester);
        env.voice.clear();
        await tapKey(tester, 'place-gps');
        expect(tester.widget<Text>(keyed('place-message')).data, words);
        expect(env.voice.spokenTexts, [words]);
        expect(api.weatherAtCalls, isEmpty);
        expect(keyed('place-map'), findsOneWidget);
      });
    }
  });

  group('touching the map', () {
    testWidgets('a touch drops a pin; the weather is shown only after "Show weather here"', (tester) async {
      final api = MockApiClient(latency: Duration.zero);
      final env = await placeEnv(api: api);
      await openField(tester, env);
      await openPicker(tester);

      expect(keyed('place-pin'), findsNothing);
      expect(tester.widget<AppButton>(keyed('place-confirm')).onPressed, isNull, reason: 'nothing chosen yet');
      await tapMap(tester);
      expect(keyed('place-pin'), findsOneWidget);
      expect(
        tester.widget<AppButton>(keyed('place-confirm')).onPressed,
        isNotNull,
        reason: 'now there is a point to confirm',
      );
      expect(api.weatherAtCalls, isEmpty, reason: 'a touch alone is not the choice');

      expect(
        api.reverseCalls,
        isEmpty,
        reason: 'the name is asked once, when the point is confirmed, not for every touch',
      );
      await tapKey(tester, 'place-confirm');
      expect(placeName(tester), 'Kotgarh, Kumharsain, Shimla, Himachal Pradesh', reason: 'not "A point on the map"');
      expect(api.reverseCalls.length, 1);
      expect(
        api.weatherAtCalls.single.lat,
        closeTo(himachalCenter.lat, 0.05),
        reason: 'the middle of the map was touched',
      );
      expect(api.weatherAtCalls.single.lon, closeTo(himachalCenter.lon, 0.05));
    });
  });

  group('the real name of a point', () {
    const kotgarh = 'Kotgarh, Kumharsain, Shimla, Himachal Pradesh';

    String homePill(WidgetTester tester) => tester.widget<Text>(keyed('home-place-text')).data!;

    testWidgets('the phone\'s position is named by its area, and the Home pill shows the short name', (tester) async {
      final api = MockApiClient(latency: Duration.zero);
      final env = await placeEnv(
        api: api,
        gps: PlaceGps(point: (lat: 31.2, lon: 77.4)),
      );
      useSmallPhone(tester);
      await pumpApp(tester, env, location: '/home');
      await tapKey(tester, 'home-place');
      await tapKey(tester, 'place-gps');
      expect(placeName(tester), kotgarh);
      await goBack(tester);
      expect(homePill(tester), 'Kotgarh', reason: 'beside three buttons a 360 dp phone has room for the village');
      expect(
        env.prefs.getString('picked_place_F001'),
        contains('Kotgarh'),
        reason: 'the saved choice has the real name too',
      );
    });

    testWidgets('the name is asked for in the farmer\'s language', (tester) async {
      final api = MockApiClient(latency: Duration.zero);
      final env = await placeEnv(
        api: api,
        gps: PlaceGps(point: (lat: 31.2, lon: 77.4)),
        language: 'hi',
      );
      await openField(tester, env);
      await openPicker(tester);
      await tapKey(tester, 'place-gps');
      expect(api.reverseCalls.single.lang, 'hi');
    });

    for (final (width, shown) in [(360.0, 'Kotgarh'), (411.0, 'Kotgarh'), (700.0, 'Kotgarh, Kumharsain')]) {
      testWidgets('the Home pill shows as many parts of the name as fit beside the three buttons: $width dp wide', (
        tester,
      ) async {
        final env = await placeEnv();
        await env.prefs.setString(
          'picked_place_F001',
          jsonEncode(const PickedPlace(label: kotgarh, lat: 31.2, lon: 77.4, kind: 'village').toJson()),
        );
        useSmallPhone(tester, size: Size(width, 900));
        final handle = tester.ensureSemantics();
        await pumpApp(tester, env, location: '/home');
        expect(homePill(tester), shown, reason: 'never fewer than the village, as many more as fit');
        expect(
          tester.getSemantics(keyed('home-place')).label,
          contains('Kotgarh, Kumharsain'),
          reason: 'a screen reader always gets the whole short name',
        );
        expectBigTouchTargets(tester);
        handle.dispose();
      });
    }

    for (final (why, error) in [
      ('there is no internet', const ApiException.network()),
      (
        'the lookup is down',
        const ApiException(kind: ApiErrorKind.server, code: 'places_unavailable', statusCode: 503),
      ),
      (
        'nothing is known at the point',
        const ApiException(kind: ApiErrorKind.client, code: 'place_not_found', statusCode: 404),
      ),
    ]) {
      testWidgets('when $why the generic words are used and the choice still works', (tester) async {
        final api = MockApiClient(latency: Duration.zero)..failWith(error, ops: {'reversePlace'});
        final env = await placeEnv(
          api: api,
          gps: PlaceGps(point: (lat: 31.2, lon: 77.4)),
        );
        await openField(tester, env);
        await openPicker(tester);
        await tapKey(tester, 'place-gps');
        expect(placeName(tester), 'My location');
        expect(api.weatherAtCalls.single, (lat: 31.2, lon: 77.4), reason: 'the weather is shown all the same');

        await tapKey(tester, 'place-bar');
        await tapMap(tester);
        await tapKey(tester, 'place-confirm');
        expect(placeName(tester), 'A point on the map');
        expect(
          api.weatherAtCalls.length,
          1,
          reason: 'the same spot (about 1 km): the weather is not asked again, only the name changed',
        );
      });
    }

    testWidgets('a server that cannot name places is not asked', (tester) async {
      final api = _NoPlacesApi(weather: true);
      final env = await placeEnv(
        api: api,
        gps: PlaceGps(point: (lat: 31.2, lon: 77.4)),
      );
      await openField(tester, env);
      await openPicker(tester);
      await tapKey(tester, 'place-gps');
      expect(placeName(tester), 'My location');
      expect(api.reverseCalls, isEmpty);
    });

    test('the short name is the first two parts of the label', () {
      PickedPlace named(String label) => PickedPlace(label: label, lat: 31, lon: 77);
      expect(named('Kotgarh, Kumharsain, Shimla, Himachal Pradesh').shortLabel, 'Kotgarh, Kumharsain');
      expect(named('Kullu, Himachal Pradesh').shortLabel, 'Kullu, Himachal Pradesh');
      expect(named('My location').shortLabel, 'My location');
      expect(
        named(' Theog ,  , Shimla , Himachal Pradesh ').shortLabel,
        'Theog, Shimla',
        reason: 'empty parts and spaces are dropped',
      );
    });
  });

  group('back to my field, and trouble', () {
    testWidgets('"Back to my field" shows the farmer\'s own field again', (tester) async {
      final env = await placeEnv();
      await openField(tester, env);
      await openPicker(tester);
      await tester.enterText(keyed('place-search'), 'Kullu');
      await tapKey(tester, 'place-search-go');
      await tapKey(tester, 'place-result-0');
      expect(keyed('reading-leaf'), findsNothing);

      await tapKey(tester, 'place-clear');
      expect(placeName(tester), 'My own field');
      expect(keyed('place-clear'), findsNothing);
      expect(keyed('reading-leaf'), findsOneWidget);
    });

    testWidgets('weather that cannot be read is a card with "Try again", not an error screen', (tester) async {
      final api = MockApiClient(latency: Duration.zero);
      final env = await placeEnv(
        api: api,
        gps: PlaceGps(point: (lat: 31.2, lon: 77.4)),
      );
      await openField(tester, env);
      await openPicker(tester);
      api.failWith(
        const ApiException(kind: ApiErrorKind.server, code: 'weather_unavailable', statusCode: 503),
        ops: {'weatherAt'},
      );
      env.voice.clear();
      await tapKey(tester, 'place-gps');

      expect(keyed('place-weather-error'), findsOneWidget);
      expect(
        find.descendant(
          of: keyed('place-weather-error'),
          matching: find.text('The weather of this place is not available now.'),
        ),
        findsOneWidget,
      );
      expect(
        env.voice.spokenTexts.last,
        'The weather of this place is not available now.',
        reason: 'it is said, not only written',
      );
      expect(keyed('place-bar'), findsOneWidget, reason: 'the farmer can still choose another place');
      expect(keyed('place-clear'), findsOneWidget, reason: 'or go back to the field');
      expect(keyed('forecast-strip'), findsNothing);

      api.clearFailure();
      await tapKey(tester, 'place-retry');
      expect(keyed('place-weather-error'), findsNothing);
      expect(keyed('forecast-strip'), findsOneWidget);
      expect(tester.widget<Text>(keyed('reading-digits-temp')).data, '12 °C');
    });

    testWidgets('the reload arrow looks at the chosen place again', (tester) async {
      final api = MockApiClient(latency: Duration.zero);
      final env = await placeEnv(
        api: api,
        gps: PlaceGps(point: (lat: 31.2, lon: 77.4)),
      );
      await openField(tester, env);
      await openPicker(tester);
      await tapKey(tester, 'place-gps');
      expect(api.weatherAtCalls.length, 1);
      await tapKey(tester, 'field-reload');
      expect(api.weatherAtCalls.length, 2);
      expect(api.calls.where((c) => c == 'field').length, 1, reason: 'the farmer\'s own field is not asked again');
    });

    testWidgets('a place with no data says so', (tester) async {
      final api = MockApiClient(latency: Duration.zero)
        ..placeWeatherOverride = FieldOut(asOf: DateTime.utc(2026, 5, 12));
      final env = await placeEnv(
        api: api,
        gps: PlaceGps(point: (lat: 31.2, lon: 77.4)),
      );
      await openField(tester, env);
      await openPicker(tester);
      await tapKey(tester, 'place-gps');
      expect(keyed('field-no-data'), findsOneWidget);
    });
  });

  group('the location line of Home', () {
    Future<void> openHome(WidgetTester tester, TestEnv env) async {
      useSmallPhone(tester);
      await pumpApp(tester, env, location: '/home');
    }

    String homePlace(WidgetTester tester) => tester.widget<Text>(keyed('home-place-text')).data!;

    /// Home, the location button, a search for Kullu, the first result: ends on My field.
    Future<void> chooseKullu(WidgetTester tester) async {
      await tapKey(tester, 'home-place');
      await tester.enterText(keyed('place-search'), 'Kullu');
      await tapKey(tester, 'place-search-go');
      await tapKey(tester, 'place-result-0');
    }

    testWidgets('names the farmer\'s village and district, as a button that opens the picker', (tester) async {
      final env = await placeEnv();
      await openHome(tester, env);
      expect(homePlace(tester), 'Kotgarh', reason: 'the village; the district fits only on a wide phone');
      expectBigTouchTargets(tester);
      await tapKey(tester, 'home-place');
      expect(keyed('place-gps'), findsOneWidget, reason: 'the map and search window');
      expect(keyed('place-map'), findsOneWidget);
      expect(keyed('place-search'), findsOneWidget);
    });

    testWidgets('a place chosen there becomes the location of Home and the weather of My field', (tester) async {
      final api = MockApiClient(latency: Duration.zero);
      final env = await placeEnv(api: api);
      await openHome(tester, env);
      await chooseKullu(tester);

      expect(placeName(tester), 'Kullu, Himachal Pradesh', reason: 'the weather page is the next thing to see');
      expect(api.weatherAtCalls.single.lat, closeTo(31.9579, 1e-4));
      expect(tester.widget<Text>(keyed('reading-digits-temp')).data, '12 °C');

      await goBack(tester); // the Home button of the bottom bar
      expect(homePlace(tester), 'Kullu', reason: 'the location line of Home changed');
    });

    testWidgets('the chosen location is still there after the app was closed and opened again', (tester) async {
      final api = MockApiClient(latency: Duration.zero);
      final env = await placeEnv(api: api);
      await openHome(tester, env);
      await chooseKullu(tester);
      expect(env.prefs.getKeys().where((k) => k.startsWith('picked_place_')), [
        'picked_place_F001',
      ], reason: 'one entry per farmer');

      await tester.pumpWidget(const SizedBox.shrink()); // close the app
      await tester.pumpWidget(env.app(location: '/home')); // open it again (the phone's memory stays)
      await tester.pumpAndSettle();
      expect(homePlace(tester), 'Kullu');
      await tapKey(tester, 'home-field');
      expect(placeName(tester), 'Kullu, Himachal Pradesh');
      expect(api.weatherAtCalls.length, 2, reason: 'the weather is read again, it is live');
    });

    testWidgets('"Back to my field" returns the location to the farmer\'s own village and forgets the choice', (
      tester,
    ) async {
      final env = await placeEnv();
      await openHome(tester, env);
      await chooseKullu(tester);
      await tapKey(tester, 'place-clear');
      expect(placeName(tester), 'My own field');
      expect(env.prefs.getString('picked_place_F001'), isNull);
      await goBack(tester);
      expect(homePlace(tester), 'Kotgarh');
    });

    testWidgets('on a server without the place picker the location is plain text, not a button', (tester) async {
      final env = await placeEnv(api: _NoPlacesApi(), savedFlag: false); // the server said no: nothing saved as "on"
      await openHome(tester, env);
      expect(find.text('Kotgarh, Shimla'), findsOneWidget);
      expect(keyed('home-place'), findsNothing);
    });

    test('a damaged saved place is the same as none, a good one comes back as it was', () {
      const place = PickedPlace(label: 'Kullu, Himachal Pradesh', lat: 31.9579, lon: 77.10892, kind: 'town');
      final back = PickedPlace.tryParse(jsonEncode(place.toJson()))!;
      expect((back.label, back.lat, back.lon, back.kind), ('Kullu, Himachal Pradesh', 31.9579, 77.10892, 'town'));
      for (final bad in [
        null,
        '',
        'not json',
        '[1, 2]',
        '{}',
        '{"label": "", "lat": 31, "lon": 77}',
        '{"label": "X", "lat": "31", "lon": 77}',
        '{"label": "X", "lat": 95, "lon": 77}',
        '{"label": "X", "lat": 31, "lon": 190}',
      ]) {
        expect(PickedPlace.tryParse(bad), isNull, reason: 'damaged: $bad');
      }
      expect(
        PickedPlace.tryParse('{"label": "X", "lat": 31, "lon": 77}')!.kind,
        'place',
        reason: 'an old entry without a kind',
      );
    });
  });

  group('small phones and big text', () {
    for (final (name, size, scale) in [
      ('360x640 at 1.0', const Size(360, 640), 1.0),
      ('320x568 at 1.6', const Size(320, 568), 1.6),
    ]) {
      testWidgets('picker and the field with a chosen place fit $name', (tester) async {
        final env = await placeEnv(gps: PlaceGps(point: (lat: 31.2, lon: 77.4)));
        await openField(tester, env, textScale: scale, size: size);
        expect(tester.takeException(), isNull);
        expectBigTouchTargets(tester);

        await openPicker(tester);
        expect(tester.takeException(), isNull);
        expectBigTouchTargets(tester);

        await tapKey(tester, 'place-gps');
        expect(tester.takeException(), isNull);
        expectBigTouchTargets(tester);
        expect(keyed('place-clear'), findsOneWidget);
      });
    }
  });
}
