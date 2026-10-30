import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmtrack/core/models/models.dart';
import 'package:farmtrack/core/network/mock_api_client.dart';
import 'package:farmtrack/core/router/app_router.dart';
import 'package:farmtrack/core/router/routes.dart';
import 'package:farmtrack/features/diary/date_words.dart';

import '../test/support/feature_fakes.dart';
import '../test/support/harness.dart';

/// The diary page (the crop circles, this week, the timeline) and its month sheet, rendered to PNG at 390 x 844 (2x), in English and
/// Hindi, to compare with `docs/design/diary-combined-proposals.html` (design 2).
///
///     flutter test test_visual/diary_timeline_shots_test.dart --dart-define=SHOT_DIR=C:\some\folder
const _shotDir = String.fromEnvironment('SHOT_DIR');

final _boundary = GlobalKey();

Future<void> _loadFonts() async {
  const weights = ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold'];
  final families = <String, List<String>>{
    'NotoSans': [for (final w in weights) 'assets/fonts/NotoSans-$w.ttf'],
    'NotoSansDevanagari': [for (final w in weights) 'assets/fonts/NotoSansDevanagari-$w.ttf'],
    'FarmTrackIcons': ['assets/fonts/FarmTrackIcons.ttf'],
    // The icons of Flutter itself (the "All" circle): the test renderer has no icon font of its own.
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

DateTime _day(int month, int day) => DateTime.utc(2026, month, day, 12);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  for (final language in const ['en', 'hi']) {
    for (final shot in const ['page', 'apple', 'month']) {
      if (language == 'hi' && shot == 'apple') continue;
      testWidgets('Diary timeline: $shot in $language', (tester) async {
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
        for (final (crop, name, at) in [
          ('apple', 'Score', _day(5, 12)),
          ('tomato', 'Mancozeb', _day(5, 12)),
          ('apple', 'Score', _day(5, 11)),
          ('apple', 'Miravis Duo', _day(5, 8)),
          ('tomato', 'Score', _day(4, 20)),
        ]) {
          await api.createSprayLog(SprayLogIn(cropId: crop, freeText: name, sprayedAt: at));
        }
        final env = await TestEnv.create(
          language: language,
          loggedIn: true,
          api: api,
          extraOverrides: [clockProvider.overrideWithValue(() => fixedNow)],
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: _boundary,
            child: env.app(location: '/home'),
          ),
        );
        await tester.pumpAndSettle();
        tester.takeException();
        containerOf(tester).read(routerProvider).go(Routes.diary);
        await tester.pumpAndSettle();
        if (shot == 'apple') {
          await tester.tap(find.byKey(const ValueKey('diary-crop-apple')));
          await tester.pumpAndSettle();
        }
        if (shot == 'month') {
          await tester.tap(find.byKey(const ValueKey('diary-week')));
          await tester.pumpAndSettle();
        }
        await _save(tester, '$_shotDir/$language/$shot.png');
        final error = tester.takeException();
        if (error != null) debugPrint('NOTE $shot: ${error.toString().split('\n').first}');
      });
    }
  }
}
