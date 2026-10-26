import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmtrack/core/network/mock_api_client.dart';
import 'package:farmtrack/core/network/mock_data.dart';
import 'package:farmtrack/core/offline/offline_status.dart';
import 'package:farmtrack/core/router/app_router.dart';
import 'package:farmtrack/core/router/routes.dart';
import 'package:farmtrack/features/home/home_screen.dart';
import 'package:farmtrack/features/offline/last_result.dart';
import 'package:farmtrack/features/scan/scan_flow.dart';

import '../test/support/harness.dart';

/// Home, the offline cards, settings, the log out question and the "saved" screen, rendered to PNG to compare with the
/// mockup (390 x 844, 2x). Like screens_shots_test.dart, with the states that file does not cover.
///
///     flutter test test_visual/home_settings_shots_test.dart --dart-define=SHOT_DIR=C:\some\folder
const _shotDir = String.fromEnvironment('SHOT_DIR');

/// What the offline queue "says" in the shots; a shot changes it and invalidates the provider.
OfflineStatus _status = const OfflineStatus();

class _FixedStatus extends OfflineStatusNotifier {
  @override
  OfflineStatus build() => _status;
}

class _Shot {
  const _Shot(this.name, this.route, {this.prepare, this.online = true});

  final String name;
  final String route;
  final FutureOr<void> Function(ProviderContainer c, ScanFlowNotifier flow)? prepare;
  final bool online;
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

void main() {
  final shots = <_Shot>[
    const _Shot('home-empty', Routes.home),
    // The mockup's Home: a last advice, the field, one saved photo waiting.
    _Shot(
      'home',
      Routes.home,
      prepare: (c, flow) async {
        await c.read(lastResultProvider.notifier).remember(MockData.okScan('scan-1'));
        _status = const OfflineStatus(pending: 1);
        c.invalidate(offlineStatusProvider);
      },
    ),
    _Shot(
      'home-ready',
      Routes.home,
      prepare: (c, flow) async {
        await c.read(lastResultProvider.notifier).remember(MockData.needsExpertScan('scan-2'));
        _status = OfflineStatus(
          pending: 12,
          ready: [
            ReadyResult(scanId: 'a', at: DateTime.now()),
            ReadyResult(scanId: 'b', at: DateTime.now()),
          ],
        );
        c.invalidate(offlineStatusProvider);
      },
      online: false,
    ),
    const _Shot('settings', Routes.settings),
    const _Shot('logout-question', Routes.settingsLogout),
    const _Shot('saved-offline', Routes.scanSaved),
  ];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  for (final language in const ['en', 'hi']) {
    testWidgets('screens in $language', (tester) async {
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

      _status = const OfflineStatus();
      final api = MockApiClient(latency: Duration.zero);
      final env = await TestEnv.create(
        language: language,
        loggedIn: true,
        api: api,
        extraOverrides: [
          homeFieldSummaryProvider.overrideWithValue(true),
          offlineStatusProvider.overrideWith(_FixedStatus.new),
        ],
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
      final flow = container.read(scanFlowProvider.notifier);

      var n = 0;
      for (final shot in shots) {
        _status = const OfflineStatus();
        container.invalidate(offlineStatusProvider);
        env.connectivity.online = true;
        router.go(Routes.home);
        await _settle(tester);
        flow.reset();
        tester.takeException();
        env.connectivity.online = shot.online;
        await shot.prepare?.call(container, flow);
        router.go(shot.route);
        await _settle(tester);
        n++;
        await _save(tester, '$_shotDir/$language/${n.toString().padLeft(2, '0')}-${shot.name}.png');
        final error = tester.takeException();
        if (error != null) debugPrint('NOTE ${shot.name}: ${error.toString().split('\n').first}');
      }
    });
  }
}
