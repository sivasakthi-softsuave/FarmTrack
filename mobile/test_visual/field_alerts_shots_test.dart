import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmtrack/core/models/models.dart';
import 'package:farmtrack/core/network/mock_api_client.dart';
import 'package:farmtrack/core/network/mock_data.dart';
import 'package:farmtrack/core/providers.dart';
import 'package:farmtrack/core/router/app_router.dart';
import 'package:farmtrack/core/router/routes.dart';
import 'package:farmtrack/features/alerts/alerts_providers.dart';

import '../test/support/harness.dart';

/// "My field" and "Alerts" in all their states, rendered to PNG to compare with the mockup (390 x 844 phones):
///
///     flutter test test_visual/field_alerts_shots_test.dart --dart-define=SHOT_DIR=C:\some\folder
///
/// One folder per language (`en`, `hi`), one `NN-name.png` per state, 780 x 1688 pixels (2x).
const _shotDir = String.fromEnvironment('SHOT_DIR');

class _Shot {
  const _Shot(this.name, this.route, {this.prepare, this.weatherOn = true});

  final String name;
  final String route;
  final FutureOr<void> Function(ProviderContainer c, MockApiClient api)? prepare;
  final bool weatherOn;
}

final _boundary = GlobalKey();

Future<void> _loadFonts() async {
  const weights = ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold'];
  final families = <String, List<String>>{
    'NotoSans': [for (final w in weights) 'assets/fonts/NotoSans-$w.ttf'],
    'NotoSansDevanagari': [for (final w in weights) 'assets/fonts/NotoSansDevanagari-$w.ttf'],
    'FarmTrackIcons': ['assets/fonts/FarmTrackIcons.ttf'],
  };
  for (final entry in families.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      loader.addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
    }
    await loader.load();
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 120));
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

/// The three alerts of the mockup: urgent rain, scab weather, result ready.
List<AlertOut> _mockupAlerts() {
  final now = DateTime.now();
  return [
    AlertOut(
      id: 'a1',
      kind: 'rain_washoff',
      level: Severity.red,
      title: LocalizedText.pair(en: 'Heavy rain after your spray', hi: 'छिड़काव के बाद तेज़ बारिश'),
      body: LocalizedText.pair(
        en: 'Spray again within seven days. Do not use the same medicine.',
        hi: 'सात दिन के अंदर दोबारा छिड़काव कीजिए। वही दवा न डालें।',
      ),
      spoken: SpokenOut(
        text: LocalizedText.pair(en: 'Heavy rain after your spray.', hi: 'छिड़काव के बाद तेज़ बारिश।'),
      ),
      createdAt: DateTime(now.year, now.month, now.day, 7, 30),
      scanId: MockData.alertScanId,
    ),
    AlertOut(
      id: 'a2',
      kind: 'scab_infection_risk',
      level: Severity.yellow,
      title: LocalizedText.pair(en: 'Scab weather', hi: 'स्कैब का मौसम'),
      body: LocalizedText.pair(en: 'The leaves stayed wet for many hours.', hi: 'पत्तियाँ कई घंटे गीली रहीं।'),
      createdAt: DateTime(now.year, now.month, now.day, 7).subtract(const Duration(days: 1)),
    ),
    AlertOut(
      id: 'a3',
      kind: 'expert_advice',
      level: Severity.green,
      title: LocalizedText.pair(en: 'Result ready: tap to see', hi: 'नतीजा आ गया: देखने के लिए दबाइए'),
      body: LocalizedText.pair(en: 'Apple scab', hi: 'सेब का स्कैब'),
      createdAt: DateTime(now.year, now.month - 5 < 1 ? 1 : now.month - 5, 12),
      readAt: DateTime(now.year, now.month - 5 < 1 ? 1 : now.month - 5, 12, 9),
      scanId: 'x',
    ),
  ];
}

/// Puts [items] on the mock server and waits until the list has loaded them (it keeps the old list while it reloads).
Future<void> _setAlerts(ProviderContainer c, MockApiClient api, List<AlertOut> items) async {
  api.alertItems = items;
  c.invalidate(alertsProvider);
  await c.read(alertsProvider.future);
}

FieldOut _field({List<RiskOut>? risks, bool stale = false}) {
  final base = MockData.field();
  return FieldOut(
    stationId: base.stationId,
    village: 'Theog',
    asOf: DateTime.now(),
    stale: stale,
    readings: const ReadingsOut(tempC: 18, rhPct: 82, rain24hMm: 3, leafWetnessMin: 360, soilMoisturePct: 31),
    forecast: base.forecast,
    risks: risks ?? base.risks,
    spoken: base.spoken,
  );
}

void main() {
  final shots = <_Shot>[
    _Shot('field', Routes.field, prepare: (c, api) => api.fieldOverride = _field()),
    _Shot(
      'field-red-and-yellow',
      Routes.field,
      prepare: (c, api) => api.fieldOverride = _field(
        risks: [
          RiskOut(
            id: 'rain_wash',
            level: Severity.red,
            title: LocalizedText.pair(en: 'Rain washed your spray', hi: 'बारिश ने छिड़काव धो दिया'),
            text: LocalizedText.pair(en: 'Spray again within seven days.', hi: 'सात दिन के अंदर दोबारा छिड़काव कीजिए।'),
          ),
          ...MockData.field().risks,
        ],
      ),
    ),
    _Shot('field-old', Routes.field, prepare: (c, api) => api.fieldOverride = MockData.fieldStale()),
    _Shot('field-no-data', Routes.field, prepare: (c, api) => api.fieldOverride = MockData.fieldNoData()),
    _Shot('field-weather-off', Routes.field, weatherOn: false, prepare: (c, api) => api.fieldOverride = _field()),
    _Shot('alerts', Routes.alerts, prepare: (c, api) => _setAlerts(c, api, _mockupAlerts())),
    _Shot('alerts-empty', Routes.alerts, prepare: (c, api) => _setAlerts(c, api, [])),
    _Shot('alert-detail', Routes.alertDetailFor('a1'), prepare: (c, api) => _setAlerts(c, api, _mockupAlerts())),
    _Shot('alert-detail-yellow', Routes.alertDetailFor('a2'), prepare: (c, api) => _setAlerts(c, api, _mockupAlerts())),
    _Shot('alert-detail-green', Routes.alertDetailFor('a3'), prepare: (c, api) => _setAlerts(c, api, _mockupAlerts())),
  ];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  for (final language in const ['en', 'hi']) {
    for (final weatherOn in const [true, false]) {
      final mine = shots.where((s) => s.weatherOn == weatherOn).toList();
      if (mine.isEmpty) continue;
      testWidgets('field and alerts in $language, weather ${weatherOn ? 'on' : 'off'}', (tester) async {
        if (_shotDir.isEmpty) fail('pass --dart-define=SHOT_DIR=<folder>');
        tester.view
          ..physicalSize = const Size(780, 1688)
          ..devicePixelRatio = 2
          ..padding = const FakeViewPadding(top: 60)
          ..viewPadding = const FakeViewPadding(top: 60);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.resetPadding();
          tester.view.resetViewPadding();
        });

        final api = MockApiClient(latency: Duration.zero);
        final env = await TestEnv.create(
          language: language,
          loggedIn: true,
          api: api,
          extraOverrides: [if (!weatherOn) weatherOnProvider.overrideWithValue(false)],
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: _boundary,
            child: env.app(location: '/home'),
          ),
        );
        await tester.pumpAndSettle();
        final container = containerOf(tester);
        final router = container.read(routerProvider);

        for (final shot in mine) {
          router.go(Routes.home);
          await _settle(tester);
          tester.takeException();
          await shot.prepare?.call(container, api);
          router.go(shot.route);
          await _settle(tester);
          final n = (shots.indexOf(shot) + 1).toString().padLeft(2, '0');
          await _save(tester, '$_shotDir/$language/$n-${shot.name}.png');
          final error = tester.takeException();
          if (error != null) debugPrint('NOTE ${shot.name}: ${error.toString().split('\n').first}');
        }
      });
    }
  }
}
