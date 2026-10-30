import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmtrack/core/models/models.dart';
import 'package:farmtrack/core/network/mock_api_client.dart';
import 'package:farmtrack/core/network/mock_data.dart';
import 'package:farmtrack/features/diary/date_words.dart';
import 'package:farmtrack/features/home/home_screen.dart';
import 'package:farmtrack/features/offline/last_result.dart';

import '../test/support/harness.dart';

/// The weather of Home (the big card, the next hours, the spray check, the rain of the week, the details), rendered to PNG at the
/// width of the mockup (390, 2x) for the whole page in one tall picture, in English and Hindi, and in other weather.
///
///     flutter test test_visual/home_weather_shots_test.dart --dart-define=SHOT_DIR=C:\some\folder
const _shotDir = String.fromEnvironment('SHOT_DIR');

/// The pictures are taken at this moment (ten minutes after the mock server's own clock, so its hours are all still to come).
final _now = DateTime.utc(2026, 5, 12, 2, 40);

final _boundary = GlobalKey();

Future<void> _loadFonts() async {
  const weights = ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold'];
  final families = <String, List<String>>{
    'NotoSans': [for (final w in weights) 'assets/fonts/NotoSans-$w.ttf'],
    'NotoSansDevanagari': [for (final w in weights) 'assets/fonts/NotoSansDevanagari-$w.ttf'],
    'FarmTrackIcons': ['assets/fonts/FarmTrackIcons.ttf'],
    // The icons of Flutter itself (the wind, the sun and the eye of the details): the test renderer has no icon font of its own.
    'MaterialIcons': ['../../../tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf'],
  };
  for (final entry in families.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      final file = File(path);
      if (file.existsSync()) loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
    await loader.load();
  }
}

Future<void> _save(WidgetTester tester, String path) async {
  await tester.runAsync(() async {
    final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

FieldOut _field({
  double temp = 27,
  double humidity = 72,
  double rain = 0,
  String sky = 'partly_cloudy',
  bool isDay = true,
  SprayOut? spray,
  List<HourOut>? hours,
}) {
  final base = MockData.field();
  return FieldOut(
    stationId: base.stationId,
    village: base.village,
    asOf: _now,
    readings: ReadingsOut(tempC: temp, rhPct: humidity, rain24hMm: rain),
    conditions: ConditionsOut(
      sky: sky,
      isDay: isDay,
      feelsLikeC: temp + 4,
      windKmh: spray?.wind.value ?? 4,
      visibilityKm: 17.7,
      pressureHpa: 1012,
      dewPointC: 22,
      aqi: 141,
      uvIndex: 8,
      sunrise: DateTime.utc(2026, 5, 12, 0, 31),
      sunset: DateTime.utc(2026, 5, 12, 13, 18),
    ),
    hours:
        hours ??
        [
          for (final h in MockData.hours(start: temp))
            HourOut(
              time: h.time,
              tempC: h.tempC,
              sky: sky.contains('rain') ? 'rain' : (isDay ? h.sky : 'clear'),
              isDay: isDay,
              rainChancePct: sky.contains('rain') ? 80 : h.rainChancePct,
              rainMm: h.rainMm,
              windKmh: h.windKmh,
            ),
        ],
    spray: spray ?? MockData.sprayGo,
    forecast: base.forecast,
    risks: base.risks,
    spoken: base.spoken,
  );
}

class _Shot {
  const _Shot(this.name, this.field);

  final String name;
  final FieldOut field;

  /// The whole page in one picture (the phone's screen is 844 high; the page is about twice that).
  double get height => 1750;
}

void main() {
  final shots = <_Shot>[
    _Shot('sunny', _field()),
    _Shot(
      'hot-dry',
      _field(
        temp: 36,
        humidity: 28,
        sky: 'clear',
        spray: const SprayOut(
          state: SprayStatus.care,
          headline: 'hot',
          wind: SprayCheckOut(value: 12),
          rain: SprayCheckOut(value: 0),
          heat: SprayCheckOut(status: SprayStatus.care, value: 36),
        ),
      ),
    ),
    _Shot(
      'rain',
      _field(
        temp: 14,
        humidity: 95,
        rain: 24,
        sky: 'heavy_rain',
        spray: const SprayOut(
          state: SprayStatus.stop,
          headline: 'rain_soon',
          wind: SprayCheckOut(value: 9),
          rain: SprayCheckOut(status: SprayStatus.stop, value: 8.2, hours: 2),
          heat: SprayCheckOut(value: 14),
        ),
      ),
    ),
    _Shot('night', _field(temp: 9, humidity: 70, sky: 'clear', isDay: false)),
  ];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  for (final language in const ['en', 'hi']) {
    for (final shot in shots) {
      if (language == 'hi' && shot.name != 'sunny') continue;
      testWidgets('Home weather: ${shot.name} in $language', (tester) async {
        if (_shotDir.isEmpty) fail('pass --dart-define=SHOT_DIR=<folder>');
        tester.view
          ..physicalSize = Size(780, shot.height * 2)
          ..devicePixelRatio = 2
          ..padding = const FakeViewPadding(top: 60)
          ..viewPadding = const FakeViewPadding(top: 60);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.resetPadding();
          tester.view.resetViewPadding();
        });
        final api = MockApiClient(latency: Duration.zero)..fieldOverride = shot.field;
        final env = await TestEnv.create(
          language: language,
          loggedIn: true,
          api: api,
          extraOverrides: [
            clockProvider.overrideWithValue(() => _now),
            homeFieldSummaryProvider.overrideWithValue(true),
          ],
        );
        await LastResultCache(env.prefs, 'F001').save(MockData.okScan('scan-1'), _now);
        await tester.pumpWidget(
          RepaintBoundary(
            key: _boundary,
            child: env.app(location: '/home'),
          ),
        );
        await tester.pumpAndSettle();
        await _save(tester, '$_shotDir/$language/${shot.name}.png');
        final error = tester.takeException();
        if (error != null) debugPrint('NOTE ${shot.name}: ${error.toString().split('\n').first}');
      });
    }
  }
}
