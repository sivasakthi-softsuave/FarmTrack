import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmtrack/core/models/models.dart';
import 'package:farmtrack/core/network/api_client.dart';
import 'package:farmtrack/core/network/mock_api_client.dart';
import 'package:farmtrack/core/network/mock_data.dart';
import 'package:farmtrack/core/router/app_router.dart';
import 'package:farmtrack/core/router/routes.dart';
import 'package:farmtrack/features/alerts/alerts_providers.dart';
import 'package:farmtrack/features/ask/ask_flow.dart';
import 'package:farmtrack/features/ask/ask_suggestions.dart';
import 'package:farmtrack/features/home/home_screen.dart';
import 'package:farmtrack/features/scan/scan_flow.dart';

import '../test/support/harness.dart';

/// Renders the screens of the real app to PNG files, to compare them with the approved mockup
/// (`docs/design/ui-redesign-mockup.html`, 390 x 844 phones).
///
///     flutter test test_visual/screens_shots_test.dart --dart-define=SHOT_DIR=C:\some\folder
///
/// One folder per language (`en`, `hi`), one `NN-name.png` per screen, 780 x 1688 pixels (2x). Not part of `flutter test`
/// (that runs `test/` only). The fonts are the app's own (Noto Sans, the icon font), so what you see is what the phone draws.
const _shotDir = String.fromEnvironment('SHOT_DIR');

class _Api extends MockApiClient {
  _Api() : super(latency: Duration.zero);

  /// The photos never finish going up: the "Looking at your leaf" screen stays.
  bool hangCreate = false;

  @override
  Future<ScanOut> createScan({
    required List<String> photoPaths,
    String? clientCrop,
    double? clientConfidence,
    DateTime? takenAt,
    double? lat,
    double? lon,
    String? idempotencyKey,
    UploadProgressCallback? onProgress,
    CancelHandle? cancel,
  }) async {
    if (hangCreate) await Completer<void>().future;
    return super.createScan(photoPaths: photoPaths, idempotencyKey: idempotencyKey);
  }
}

class _Shot {
  const _Shot(this.name, this.route, {this.prepare});

  final String name;
  final String route;
  final FutureOr<void> Function(ProviderContainer c, _Api api, ScanFlowNotifier flow)? prepare;
}

/// `--dart-define=SMALL=true` draws a 320 x 568 phone; `--dart-define=SCALE=1.5` sets the text size (1.0 by default).
const _small = bool.fromEnvironment('SMALL');
final _scale = double.tryParse(const String.fromEnvironment('SCALE')) ?? 1;

final _boundary = GlobalKey();

/// `flutter test` draws every glyph as a box unless the fonts are loaded by hand.
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
  final suggestions = parseAskSuggestions(File('assets/l10n/ask_suggestions.json').readAsStringSync());
  final fixedSuggestions = askSuggestionsProvider.overrideWith((ref) => suggestions);

  final shots = <_Shot>[
    const _Shot('home', Routes.home),
    const _Shot('settings', Routes.settings),
    const _Shot('camera', Routes.scan),
    _Shot(
      'camera-photos-taken',
      Routes.scan,
      prepare: (c, api, flow) {
        flow
          ..reset()
          ..addPhoto('/tmp/leaf_0.jpg')
          ..addPhoto('/tmp/leaf_1.jpg');
      },
    ),
    _Shot(
      'review',
      Routes.scanReview,
      prepare: (c, api, flow) {
        flow
          ..reset()
          ..addPhoto('/tmp/leaf_0.jpg')
          ..addPhoto('/tmp/leaf_1.jpg');
      },
    ),
    _Shot(
      'analysing',
      Routes.scanUploading,
      prepare: (c, api, flow) {
        api.hangCreate = true;
        flow
          ..reset()
          ..addPhoto('/tmp/leaf_0.jpg');
      },
    ),
    _Shot('retake', Routes.scanRetake, prepare: (c, api, flow) => flow.showResult(MockData.photoUnusableScan('s1'))),
    _Shot(
      'cannot-identify-the-leaf',
      Routes.scanRetake,
      prepare: (c, api, flow) => flow.showResult(MockData.confirmCropScan('s1')),
    ),
    _Shot('advice', Routes.scanAdvice, prepare: (c, api, flow) => flow.showResult(MockData.okScan('scan-1'))),
    _Shot('expert', Routes.scanExpert, prepare: (c, api, flow) => flow.showResult(MockData.needsExpertScan('s1'))),
    const _Shot('saved-offline', Routes.scanSaved),
    _Shot(
      'diary',
      Routes.diary,
      prepare: (c, api, flow) async {
        await api.createSprayLog(const SprayLogIn(cropId: 'apple', freeText: 'Captan'));
        await api.createSprayLog(const SprayLogIn(cropId: 'apple', adviceId: 'adv-1'));
      },
    ),
    _Shot(
      'diary-confirm',
      Routes.diaryFor(adviceId: 'adv-scan-1', cropId: 'apple'),
      prepare: (c, api, flow) => flow.showResult(MockData.okScan('scan-1')),
    ),
    const _Shot('diary-add', Routes.diaryAdd),
    const _Shot('field', Routes.field),
    const _Shot('alerts', Routes.alerts),
    _Shot('alert-detail', Routes.alertDetailFor('alert-1')),
    const _Shot('ask', Routes.ask),
    const _Shot('ask-type', Routes.askType),
    _Shot(
      'ask-answer',
      Routes.askAnswer,
      prepare: (c, api, flow) => c.read(askFlowProvider.notifier).ask('When does apple scab spread?'),
    ),
    const _Shot('logout-question', Routes.settingsLogout),
  ];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  for (final language in const ['en', 'hi']) {
    testWidgets('screens in $language', (tester) async {
      if (_shotDir.isEmpty) fail('pass --dart-define=SHOT_DIR=<folder>');
      tester.view
        ..physicalSize = _small ? const Size(640, 1136) : const Size(780, 1688)
        ..devicePixelRatio = 2
        ..padding =
            const FakeViewPadding(top: 60) // the 30 dp status bar of the mockup's phone
        ..viewPadding = const FakeViewPadding(top: 60);
      tester.platformDispatcher.textScaleFactorTestValue = _scale;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
        tester.view.resetViewPadding();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });

      final api = _Api();
      final env = await TestEnv.create(
        language: language,
        loggedIn: true,
        api: api,
        extraOverrides: [fixedSuggestions, homeFieldSummaryProvider.overrideWithValue(true)],
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
        router.go(Routes.home);
        await _settle(tester);
        flow.reset();
        container.read(askFlowProvider.notifier).reset();
        api.hangCreate = false;
        tester.takeException();
        await shot.prepare?.call(container, api, flow);
        router.go(shot.route);
        await _settle(tester);
        n++;
        await _save(tester, '$_shotDir/$language/${n.toString().padLeft(2, '0')}-${shot.name}.png');
        final error = tester.takeException();
        if (error != null) debugPrint('NOTE ${shot.name}: ${error.toString().split('\n').first}');
      }
      container.read(alertsProvider); // keep the import used
    });
  }
}
