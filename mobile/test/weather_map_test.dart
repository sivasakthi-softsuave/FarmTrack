import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:farmtrack/core/models/models.dart';
import 'package:farmtrack/core/network/mock_api_client.dart';
import 'package:farmtrack/features/diary/date_words.dart';
import 'package:farmtrack/features/field/place_providers.dart';
import 'package:farmtrack/features/field/weather_map_data.dart';
import 'package:farmtrack/features/field/weather_map_screen.dart';

import 'support/feature_fakes.dart';
import 'support/finders.dart';
import 'support/harness.dart';
import 'support/map_fakes.dart';

/// An in-memory Dio adapter for the free map sources.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.answer);

  final ResponseBody Function(RequestOptions options) answer;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return answer(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _status(int code) => ResponseBody.fromString('', code);

ResponseBody _json(Object body) => ResponseBody.fromString(
  jsonEncode(body),
  200,
  headers: {
    'content-type': ['application/json'],
  },
);

/// A feed on a fake network. The sources' own Dio is made by the app's provider, so its settings are the real ones.
(HttpWeatherMapFeed, _Adapter, ProviderContainer) _feed(ResponseBody Function(RequestOptions options) answer) {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final adapter = _Adapter(answer);
  final dio = container.read(weatherMapDioProvider)..httpClientAdapter = adapter;
  return (HttpWeatherMapFeed(dio), adapter, container);
}

/// The moment in a NASA tile address (`.../default/2026-10-29T14:00:00Z/...`).
DateTime _momentOf(RequestOptions options) =>
    DateTime.parse(RegExp(r'/default/([^/]+)/').firstMatch(options.uri.toString())!.group(1)!);

String _t(String key, {Map<String, Object> args = const {}}) =>
    args.isEmpty ? key : '$key ${args.entries.map((e) => '${e.key}=${e.value}').join(' ')}';

Future<(TestEnv, FakeMapFeed, List<String>)> _env({
  String language = 'en',
  FakeMapFeed? feed,
  bool weather = true,
}) async {
  feed ??= FakeMapFeed();
  final tiles = <String>[];
  final env = await TestEnv.create(
    loggedIn: true,
    language: language,
    api: _MetaApi(weather: weather),
    extraOverrides: [
      clockProvider.overrideWithValue(() => fixedNow),
      mapTileUrlProvider.overrideWithValue(
        null,
      ), // the map under the pictures downloads nothing; its credit line is still drawn
      ...mapOverrides(feed, tiles),
    ],
  );
  await env.prefs.setBool('place_weather_enabled', true);
  return (env, feed, tiles);
}

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

/// Opens My field and then the weather map. [settle] false leaves the map's progress bar running (the pictures are still coming).
Future<void> _openMap(
  WidgetTester tester,
  TestEnv env, {
  bool settle = true,
  Size size = const Size(360, 640),
  double textScale = 1,
}) async {
  useSmallPhone(tester, size: size, textScale: textScale);
  await pumpApp(tester, env, location: '/home');
  await tapKey(tester, 'home-field');
  env.voice.clear();
  final card = keyed('field-map-open');
  expect(card, findsOneWidget, reason: 'My field offers the map');
  await tester.ensureVisible(card);
  await tester.pump();
  await tester.tap(card);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
}

String _time(WidgetTester tester) => tester.widget<Text>(keyed('wmap-time')).data!;

Future<void> _tick(WidgetTester tester, [int times = 1]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 900));
  }
}

const _radarSays =
    'This is the rain radar. Blue places had rain in the last two hours. Press the play button to see how the rain moved.';
const _cloudsSays =
    'These are the clouds seen from space. White and blue places are under thick clouds. Press the play button to see how the clouds moved.';
const _rainSays =
    'This shows how hard it rained, measured from space. Green is a little rain and red is very heavy rain. This picture is a few hours old.';

void main() {
  group('the sources', () {
    test('RainViewer: the past frames, oldest first, as tile addresses of their blue scheme', () {
      final frames = parseRainViewerFrames({
        'version': '2.0',
        'host': 'https://tilecache.rainviewer.com',
        'radar': {
          'past': [
            {'time': 1793277600, 'path': '/v2/radar/b'},
            {'time': 1793277000, 'path': '/v2/radar/a'},
          ],
          'nowcast': [],
        },
      });
      expect(frames.map((f) => f.time.millisecondsSinceEpoch ~/ 1000), [1793277000, 1793277600]);
      expect(frames.first.time.isUtc, isTrue);
      expect(frames.first.urlTemplate, 'https://tilecache.rainviewer.com/v2/radar/a/256/{z}/{x}/{y}/2/1_1.png');
    });

    test('RainViewer: anything that does not look right is left out', () {
      expect(parseRainViewerFrames(null), isEmpty);
      expect(parseRainViewerFrames('x'), isEmpty);
      expect(parseRainViewerFrames({'host': 'https://tilecache.rainviewer.com'}), isEmpty);
      expect(
        parseRainViewerFrames({
          'host': 'https://tilecache.rainviewer.com',
          'radar': {'past': 'no'},
        }),
        isEmpty,
      );
      final frames = parseRainViewerFrames({
        'host': 'https://tilecache.rainviewer.com',
        'radar': {
          'past': [
            {'time': 'soon', 'path': '/v2/radar/a'},
            {'time': 1, 'path': 'no-slash'},
            {'time': 2},
            'x',
            {'time': 3, 'path': '/v2/radar/ok'},
          ],
        },
      });
      expect(frames.single.urlTemplate, contains('/v2/radar/ok/'));
      for (final host in [
        'http://tilecache.rainviewer.com',
        'https://evil.example.com',
        'https://rainviewer.com.evil.io',
      ]) {
        expect(
          parseRainViewerFrames({
            'host': host,
            'radar': {
              'past': [
                {'time': 1, 'path': '/v2/radar/a'},
              ],
            },
          }),
          isEmpty,
          reason: 'only RainViewer itself over https: $host',
        );
      }
    });

    test('radar: asks RainViewer for its list, with its own headers (no farmer login goes to a third party)', () async {
      final (feed, adapter, _) = _feed(
        (o) => _json({
          'host': 'https://tilecache.rainviewer.com',
          'radar': {
            'past': [
              {'time': 1793277000, 'path': '/v2/radar/a'},
            ],
          },
        }),
      );
      final frames = await feed.frames(MapLayer.radar, DateTime.utc(2026, 10, 29, 14, 49));
      expect(frames, hasLength(1));
      final request = adapter.requests.single;
      expect(request.uri.toString(), HttpWeatherMapFeed.rainViewerIndex);
      expect(request.headers['User-Agent'], 'com.softsuave.farmtrack');
      expect(request.headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
    });

    test('radar: an answer that is not 200 is no picture', () async {
      final (feed, _, _) = _feed((o) => _status(503));
      expect(await feed.frames(MapLayer.radar, DateTime.utc(2026, 10, 29, 14, 49)), isEmpty);
    });

    test('clouds: starts from the newest moment NASA has (14:00 at 14:49), two hours of ten minutes', () async {
      // NASA's newest Himawari picture was 14:00 when this was written; later moments are 404.
      final (feed, adapter, _) = _feed(
        (o) => _momentOf(o).isAfter(DateTime.utc(2026, 10, 29, 14, 0)) ? _status(404) : _status(200),
      );
      final frames = await feed.frames(MapLayer.clouds, DateTime.utc(2026, 10, 29, 14, 49));
      expect(frames, hasLength(12));
      expect(frames.last.time, DateTime.utc(2026, 10, 29, 14, 0));
      expect(frames.first.time, DateTime.utc(2026, 10, 29, 12, 10));
      expect(
        frames.last.urlTemplate,
        'https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/Himawari_AHI_Band13_Clean_Infrared/default/2026-10-29T14:00:00Z/'
        'GoogleMapsCompatible_Level6/{z}/{y}/{x}.png',
      );
      expect(frames.every((f) => f.time.isUtc), isTrue);
      expect(adapter.requests, hasLength(10), reason: 'ten moments asked at once, nothing more');
      expect(adapter.requests.every((r) => r.method == 'HEAD'), isTrue, reason: 'no picture is downloaded to find out');
    });

    test('rain amount: IMERG is about six hours old, half an hour apart', () async {
      final (feed, adapter, _) = _feed(
        (o) => _momentOf(o).isAfter(DateTime.utc(2026, 10, 29, 8, 30)) ? _status(404) : _status(200),
      );
      final frames = await feed.frames(MapLayer.rain, DateTime.utc(2026, 10, 29, 14, 49));
      expect(frames.map((f) => f.time.toIso8601String()), [
        '2026-10-29T06:00:00.000Z',
        '2026-10-29T06:30:00.000Z',
        '2026-10-29T07:00:00.000Z',
        '2026-10-29T07:30:00.000Z',
        '2026-10-29T08:00:00.000Z',
        '2026-10-29T08:30:00.000Z',
      ]);
      expect(frames.last.urlTemplate, contains('IMERG_Precipitation_Rate_30min/default/2026-10-29T08:30:00Z/'));
      expect(adapter.requests, hasLength(14));
    });

    test('NASA has nothing recent: no picture (not an error)', () async {
      final (feed, _, _) = _feed((o) => _status(404));
      expect(await feed.frames(MapLayer.clouds, DateTime.utc(2026, 10, 29, 14, 49)), isEmpty);
      expect(await feed.frames(MapLayer.rain, DateTime.utc(2026, 10, 29, 14, 49)), isEmpty);
    });

    test('no connection is an error, for every source (the screen offers "try again")', () async {
      final (feed, adapter, _) = _feed(
        (o) => throw DioException.connectionError(requestOptions: o, reason: 'no internet'),
      );
      for (final layer in MapLayer.values) {
        await expectLater(feed.frames(layer, DateTime.utc(2026, 10, 29, 14, 49)), throwsA(isA<DioException>()));
      }
      expect(adapter.requests, isNotEmpty);
    });

    test('one moment that fails among answers is only a moment that is not there', () async {
      var first = true;
      final (feed, _, _) = _feed((o) {
        if (first) {
          first = false;
          throw DioException.connectionError(requestOptions: o, reason: 'blip');
        }
        return _momentOf(o).isAfter(DateTime.utc(2026, 10, 29, 14, 0)) ? _status(404) : _status(200);
      });
      final frames = await feed.frames(MapLayer.clouds, DateTime.utc(2026, 10, 29, 14, 49));
      expect(frames.last.time, DateTime.utc(2026, 10, 29, 14, 0));
    });

    test('moments are rounded down to the step, and written as NASA writes them', () {
      expect(
        HttpWeatherMapFeed.roundDown(DateTime.utc(2026, 10, 29, 14, 29, 59), const Duration(minutes: 10)),
        DateTime.utc(2026, 10, 29, 14, 20),
      );
      expect(
        HttpWeatherMapFeed.roundDown(DateTime.utc(2026, 10, 29, 12, 49), const Duration(minutes: 30)),
        DateTime.utc(2026, 10, 29, 12, 30),
      );
      // A local time of the phone is turned into UTC first.
      expect(HttpWeatherMapFeed.gibsTime(DateTime.utc(2026, 1, 2, 3, 4, 5)), '2026-01-02T03:04:05Z');
    });

    test('every layer is drawn thinner than solid and has a native zoom its source really has', () {
      expect(mapLayerSpecs.keys.toSet(), MapLayer.values.toSet());
      expect(mapLayerSpecs[MapLayer.radar]!.maxNativeZoom, 7, reason: "RainViewer's free tiles stop at zoom 7");
      expect(mapLayerSpecs[MapLayer.clouds]!.maxNativeZoom, 6, reason: 'GoogleMapsCompatible_Level6');
      expect(mapLayerSpecs[MapLayer.rain]!.maxNativeZoom, 6);
      for (final spec in mapLayerSpecs.values) {
        expect(spec.opacity, inExclusiveRange(0.0, 1.0));
      }
    });
  });

  group('the words of a picture', () {
    test('how long ago', () {
      expect(mapAgo(_t, Duration.zero), 'weather_map_now');
      expect(mapAgo(_t, const Duration(minutes: 4)), 'weather_map_now');
      expect(
        mapAgo(_t, const Duration(minutes: -3)),
        'weather_map_now',
        reason: 'a clock a little behind is still "now"',
      );
      expect(mapAgo(_t, const Duration(minutes: 7)), 'weather_map_ago_min n=7');
      expect(mapAgo(_t, const Duration(minutes: 59)), 'weather_map_ago_min n=59');
      expect(mapAgo(_t, const Duration(minutes: 60)), 'weather_map_ago_h h=1');
      expect(
        mapAgo(_t, const Duration(minutes: 63)),
        'weather_map_ago_h h=1',
        reason: 'a few minutes over the hour are not said',
      );
      expect(mapAgo(_t, const Duration(minutes: 125)), 'weather_map_ago_hm h=2 m=5');
      expect(mapAgo(_t, const Duration(minutes: 118)), 'weather_map_ago_h h=2');
      expect(mapAgo(_t, const Duration(hours: 6, minutes: 30)), 'weather_map_ago_hm h=6 m=30');
    });

    test('the clock of the picture is the phone\'s, on 12 hours', () {
      final now = DateTime(2026, 5, 12, 15, 40);
      expect(mapFrameLabel(_t, DateTime(2026, 5, 12, 15, 5), now), '3:05 weather_map_pm · weather_map_ago_min n=35');
      expect(mapFrameLabel(_t, DateTime(2026, 5, 12, 0, 30), now).startsWith('12:30 weather_map_am'), isTrue);
      expect(mapFrameLabel(_t, DateTime(2026, 5, 12, 12, 0), now).startsWith('12:00 weather_map_pm'), isTrue);
      expect(mapFrameLabel(_t, DateTime(2026, 5, 12, 9, 7), now).startsWith('9:07 weather_map_am'), isTrue);
      // A picture that came as UTC is shown on the phone's clock.
      final utc = DateTime(2026, 5, 12, 15, 5).toUtc();
      expect(mapFrameLabel(_t, utc, now), mapFrameLabel(_t, DateTime(2026, 5, 12, 15, 5), now));
    });
  });

  group('the weather map screen', () {
    testWidgets('My field offers it, and it opens on the rain radar and says what it shows', (tester) async {
      final (env, feed, tiles) = await _env();
      await _openMap(tester, env);
      expect(find.text('Weather map'), findsWidgets);
      for (final layer in MapLayer.values) {
        expect(keyed('wmap-chip-${layer.name}'), findsOneWidget);
      }
      expect(find.text('Rain radar'), findsOneWidget);
      expect(find.text('Clouds'), findsOneWidget);
      expect(find.text('Rain amount'), findsOneWidget);
      expect(env.voice.spokenTexts, [_radarSays]);
      expect(feed.asked, [MapLayer.radar]);
      expect(_time(tester), '11:53 am · 7 min ago', reason: 'the newest picture, by the phone clock');
      expect(tiles.toSet(), {
        feed.frame(MapLayer.radar, 0).urlTemplate,
      }, reason: 'only the newest picture is on the map');
      expect(tester.widget<Text>(keyed('wmap-credit')).data, '© OpenStreetMap contributors · Radar: RainViewer');
      expect(find.text('Light rain'), findsOneWidget);
      expect(find.text('Heavy rain'), findsOneWidget);
      expect(keyed('wmap-pin'), findsNothing, reason: 'no place chosen: the map shows all of Himachal Pradesh');
      final map = tester.widget<FlutterMap>(keyed('weather-map'));
      expect(map.options.initialCenter, LatLng(himachalCenter.lat, himachalCenter.lon));
      expect(map.options.initialZoom, himachalZoom);
    });

    testWidgets('the card sits under the week, above the readings of the field', (tester) async {
      final (env, _, _) = await _env();
      useSmallPhone(tester);
      await pumpApp(tester, env, location: '/home');
      await tapKey(tester, 'home-field');
      final week = tester.getTopLeft(keyed('forecast-strip')).dy;
      final card = tester.getTopLeft(keyed('field-map-open')).dy;
      final readings = tester.getTopLeft(keyed('reading-temp')).dy;
      expect(card, greaterThan(week));
      expect(card, lessThan(readings));
    });

    testWidgets('the chosen layer is marked for a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      final (env, _, _) = await _env();
      await _openMap(tester, env);
      expect(
        tester.getSemantics(keyed('wmap-chip-radar')),
        isSemantics(label: 'Rain radar', isButton: true, isSelected: true),
      );
      expect(
        tester.getSemantics(keyed('wmap-chip-clouds')),
        isNot(isSemantics(isSelected: true)),
        reason: 'only the chosen layer is selected',
      );
      handle.dispose();
    });

    testWidgets('each button shows its layer: the voice says what it shows, the legend and the credit follow', (
      tester,
    ) async {
      final (env, feed, tiles) = await _env();
      await _openMap(tester, env);
      env.voice.clear();
      tiles.clear();

      await tapKey(tester, 'wmap-chip-clouds');
      expect(env.voice.spokenTexts, [_cloudsSays]);
      expect(feed.asked, [MapLayer.radar, MapLayer.clouds]);
      expect(tiles.toSet(), {feed.frame(MapLayer.clouds, 0).urlTemplate}, reason: 'the radar picture is gone');
      expect(find.text('Clear'), findsOneWidget);
      expect(find.text('Thick clouds'), findsOneWidget);
      expect(find.text('Light rain'), findsNothing);
      expect(
        tester.widget<Text>(keyed('wmap-credit')).data,
        '© OpenStreetMap contributors · Clouds: JMA Himawari, NASA GIBS',
      );

      env.voice.clear();
      tiles.clear();
      await tapKey(tester, 'wmap-chip-rain');
      expect(env.voice.spokenTexts, [_rainSays]);
      expect(tiles.toSet(), {feed.frame(MapLayer.rain, 0).urlTemplate});
      expect(tester.widget<Text>(keyed('wmap-credit')).data, '© OpenStreetMap contributors · Rain: NASA GPM IMERG');

      env.voice.clear();
      await tapKey(tester, 'wmap-chip-rain');
      expect(env.voice.spokenTexts, isEmpty, reason: 'the layer that is shown is not said again');
    });

    testWidgets('play runs the pictures from the oldest, one every second, and loads the next one in advance', (
      tester,
    ) async {
      final (env, feed, tiles) = await _env();
      await _openMap(tester, env);
      tiles.clear();

      await tester.tap(keyed('wmap-play'));
      await tester.pump();
      expect(_time(tester), '11:03 am · 57 min ago', reason: 'from the newest it starts again at the oldest');
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(tiles.toSet(), {
        feed.frame(MapLayer.radar, 5).urlTemplate,
        feed.frame(MapLayer.radar, 4).urlTemplate,
      }, reason: 'the picture shown, and the next one without being seen');

      await _tick(tester);
      expect(_time(tester), '11:13 am · 47 min ago');
      expect(
        tiles.toSet(),
        contains(feed.frame(MapLayer.radar, 3).urlTemplate),
        reason: 'the one after it is loaded now',
      );
      await _tick(tester, 4);
      expect(_time(tester), '11:53 am · 7 min ago', reason: 'the newest picture');
      await _tick(tester);
      expect(_time(tester), '11:03 am · 57 min ago', reason: 'then it goes round again');

      await tester.tap(keyed('wmap-play'));
      await tester.pump();
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      final stopped = _time(tester);
      await _tick(tester, 3);
      expect(_time(tester), stopped, reason: 'pause holds the picture');
    });

    testWidgets('the slider goes to a picture and stops the film', (tester) async {
      final (env, feed, tiles) = await _env();
      await _openMap(tester, env);
      await tester.tap(keyed('wmap-play'));
      await tester.pump();
      tiles.clear();

      tester.widget<Slider>(keyed('wmap-slider')).onChanged!(2);
      await tester.pump();
      expect(_time(tester), '11:23 am · 37 min ago');
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget, reason: 'moving the slider by hand pauses');
      expect(tiles.toSet(), {feed.frame(MapLayer.radar, 3).urlTemplate});
      await _tick(tester, 2);
      expect(_time(tester), '11:23 am · 37 min ago');
    });

    testWidgets('choosing another layer while it plays stops the film', (tester) async {
      final (env, _, _) = await _env();
      await _openMap(tester, env);
      await tester.tap(keyed('wmap-play'));
      await tester.pump();
      await tapKey(tester, 'wmap-chip-clouds');
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(_time(tester), '11:53 am · 7 min ago', reason: 'the newest picture of the new layer');
    });

    testWidgets('going back while it plays leaves no timer running', (tester) async {
      final (env, _, _) = await _env();
      await _openMap(tester, env);
      await tester.tap(keyed('wmap-play'));
      await tester.pump();
      await goBack(tester);
      expect(keyed('field-map-open'), findsOneWidget, reason: 'back on My field');
      // A running timer would fail the test at its end.
    });

    testWidgets('one picture only: the play button is off', (tester) async {
      final (env, _, _) = await _env(feed: FakeMapFeed(count: 1));
      await _openMap(tester, env);
      expect(tester.widget<Slider>(keyed('wmap-slider')).onChanged, isNull);
      await tester.tap(keyed('wmap-play'));
      await _tick(tester);
      expect(find.byIcon(Icons.pause_rounded), findsNothing);
      expect(_time(tester), '11:53 am · 7 min ago');
    });

    testWidgets('while the pictures come there is a progress bar, then the controls', (tester) async {
      final feed = FakeMapFeed()..hold = Completer<void>();
      final (env, _, _) = await _env(feed: feed);
      await _openMap(tester, env, settle: false);
      expect(keyed('wmap-busy'), findsOneWidget);
      expect(keyed('wmap-play'), findsNothing);
      expect(keyed('weather-map'), findsOneWidget, reason: 'the map itself is there at once');
      feed.hold!.complete();
      await tester.pumpAndSettle();
      expect(keyed('wmap-busy'), findsNothing);
      expect(keyed('wmap-play'), findsOneWidget);
    });

    testWidgets('no internet: it says so, the map stays, and "try again" asks again', (tester) async {
      final feed = FakeMapFeed()..fail = true;
      final (env, _, _) = await _env(feed: feed);
      await _openMap(tester, env);
      const words = 'The weather map could not be loaded. Check your internet and try again.';
      expect(tester.widget<Text>(keyed('wmap-message')).data, words);
      expect(env.voice.spokenTexts, [
        _radarSays,
        words,
      ], reason: 'what the layer shows, then that it did not come: the farmer may not read it');
      expect(keyed('wmap-play'), findsNothing);
      expect(keyed('weather-map'), findsOneWidget);

      feed.fail = false;
      await tapKey(tester, 'wmap-retry');
      expect(feed.asked, [MapLayer.radar, MapLayer.radar]);
      expect(keyed('wmap-message'), findsNothing);
      expect(_time(tester), '11:53 am · 7 min ago');
    });

    testWidgets('a source with no picture says so', (tester) async {
      final feed = FakeMapFeed()..empty = true;
      final (env, _, _) = await _env(feed: feed);
      await _openMap(tester, env);
      expect(tester.widget<Text>(keyed('wmap-message')).data, 'There is no picture of this right now.');
      expect(keyed('wmap-retry'), findsOneWidget);
      expect(keyed('wmap-play'), findsNothing);
    });

    testWidgets('a place chosen on My field: the map opens there, with the red pin', (tester) async {
      final (env, _, _) = await _env();
      await env.prefs.setString(
        'picked_place_F001',
        jsonEncode(
          const PickedPlace(label: 'Kotgarh, Kumharsain, Shimla', lat: 31.31, lon: 77.46, kind: 'village').toJson(),
        ),
      );
      await _openMap(tester, env);
      expect(keyed('wmap-pin'), findsOneWidget);
      final map = tester.widget<FlutterMap>(keyed('weather-map'));
      expect(map.options.initialCenter, const LatLng(31.31, 77.46));
      expect(map.options.initialZoom, 8);
    });

    testWidgets('in Hindi: the words, the clock and the voice', (tester) async {
      final (env, _, _) = await _env(language: 'hi');
      await _openMap(tester, env);
      expect(find.text('बारिश रडार'), findsOneWidget);
      expect(find.text('बादल'), findsOneWidget);
      expect(find.text('बारिश की मात्रा'), findsOneWidget);
      expect(_time(tester), '11:53 पूर्वाह्न · 7 मिनट पहले');
      expect(env.voice.spokenTexts.single, startsWith('यह बारिश का रडार है।'));
      expect(find.text('हल्की बारिश'), findsOneWidget);
    });

    testWidgets('My field without weather has no weather map', (tester) async {
      final (env, _, _) = await _env(weather: false);
      useSmallPhone(tester);
      await pumpApp(tester, env, location: '/home');
      await tapKey(tester, 'home-field');
      expect(keyed('field-reload'), findsOneWidget, reason: 'My field is open');
      expect(keyed('field-map-open'), findsNothing);
    });

    for (final (size, scale) in [
      (const Size(320, 568), 2.0),
      (const Size(360, 640), 1.0),
      (const Size(411, 900), 1.6),
    ]) {
      testWidgets('fits a ${size.width.toInt()}x${size.height.toInt()} phone at text size $scale', (tester) async {
        final handle = tester.ensureSemantics();
        final (env, _, _) = await _env();
        await _openMap(tester, env, size: size, textScale: scale);
        expect(tester.takeException(), isNull);
        expectBigTouchTargets(tester);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        final map = tester.getRect(keyed('weather-map'));
        expect(map.height, greaterThan(150), reason: 'the map keeps room to be a map');
        handle.dispose();
      });
    }
  });
}
