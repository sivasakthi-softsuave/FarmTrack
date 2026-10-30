import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmtrack/core/providers.dart';
import 'package:farmtrack/core/router/app_router.dart';
import 'package:farmtrack/core/router/routes.dart';
import 'package:farmtrack/core/settings/app_settings.dart';
import 'package:farmtrack/core/voice/utterance.dart';
import 'package:farmtrack/features/scan/capture_design_a.dart';
import 'package:farmtrack/features/scan/capture_widgets.dart';
import 'package:farmtrack/features/scan/photo_picker.dart';
import 'package:farmtrack/features/scan/scan_flow.dart';

import '../test/support/harness.dart';

/// The camera screen in its two looks (A and B), rendered to PNG at 390 x 844, 2x, in English and Hindi: empty, with two
/// photos, with the camera not allowed, and (A only) each of the three tips being spoken. The test renderer does not
/// animate (the screen stands still under `flutter test`), so the scan line and the moving dashes are not in the pictures.
///
///     flutter test test_visual/capture_shots_test.dart --dart-define=SHOT_DIR=C:\some\folder
const _shotDir = String.fromEnvironment('SHOT_DIR');

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
  for (var i = 0; i < 8; i++) {
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

/// A 390 x 844 phone at 2x with the status bar and the gesture bar taken off the top and bottom.
void _phone(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(780, 1688)
    ..devicePixelRatio = 2
    ..padding = const FakeViewPadding(top: 60, bottom: 40)
    ..viewPadding = const FakeViewPadding(top: 60, bottom: 40);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  for (final language in const ['en', 'hi']) {
    testWidgets('camera screen in $language', (tester) async {
      if (_shotDir.isEmpty) fail('pass --dart-define=SHOT_DIR=<folder>');
      _phone(tester);
      final env = await TestEnv.create(language: language, loggedIn: true);
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
      for (final design in CaptureDesign.values) {
        await container.read(settingsProvider.notifier).setCaptureDesign(design);
        final name = design.name.toUpperCase();
        for (final (label, photos, denied) in const [
          ('empty', 0, false),
          ('two-photos', 2, false),
          ('denied', 0, true),
        ]) {
          router.go(Routes.home);
          await _settle(tester);
          flow.reset();
          tester.takeException();
          for (var i = 0; i < photos; i++) {
            flow.addPhoto('/tmp/leaf_$i.jpg');
          }
          if (denied) env.picker.script.add(const CameraPermissionDenied());
          env.voice.clear();
          router.go(Routes.scan);
          await _settle(tester);
          if (denied) {
            await tester.tap(find.byKey(const ValueKey('camera-button')));
            await _settle(tester);
          }
          n++;
          await _save(tester, '$_shotDir/$language/${n.toString().padLeft(2, '0')}-$name-$label.png');
          final error = tester.takeException();
          if (error != null) debugPrint('NOTE $name $label: ${error.toString().split('\n').first}');
        }
      }
    });

    testWidgets('design A with each tip being spoken in $language', (tester) async {
      if (_shotDir.isEmpty) fail('pass --dart-define=SHOT_DIR=<folder>');
      _phone(tester);
      final env = await TestEnv.create(language: language, loggedIn: true);
      var n = 10;
      for (final tip in CaptureTip.values) {
        final owner = Object();
        await tester.pumpWidget(
          RepaintBoundary(
            key: _boundary,
            child: ProviderScope(
              retry: (_, _) => null,
              overrides: env.overrides,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeData(fontFamily: 'NotoSans'),
                home: Scaffold(
                  backgroundColor: CaptureColors.ground,
                  body: SafeArea(child: CaptureViewA(owner: owner, denied: false)),
                ),
              ),
            ),
          ),
        );
        await env.voice.speak([PromptUtterance(tip.promptId)], owner: owner);
        await _settle(tester);
        n++;
        await _save(tester, '$_shotDir/$language/${n.toString().padLeft(2, '0')}-A-tip-${tip.name}.png');
      }
    });
  }
}
