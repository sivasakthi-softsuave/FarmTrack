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
import 'package:farmtrack/core/router/app_router.dart';
import 'package:farmtrack/core/router/routes.dart';
import 'package:farmtrack/features/diary/diary_providers.dart';
import 'package:farmtrack/features/scan/scan_flow.dart';

import '../test/support/finders.dart';
import '../test/support/harness.dart';

/// Renders the result screens (Advice and the expert / "Not sure" screen) in every state to PNG files, to compare them
/// with the approved mockup (`docs/design/ui-redesign-mockup.html`, 390 x 844 phones).
///
///     flutter test test_visual/result_shots_test.dart --dart-define=SHOT_DIR=C:\some\folder
///
/// One folder per language (`en`, `hi`), one `NN-name.png` per state, 780 x 1688 pixels (2x). Not part of `flutter test`.
const _shotDir = String.fromEnvironment('SHOT_DIR');

/// `--dart-define=SMALL=true` draws a 320 x 568 phone; `--dart-define=SCALE=2.0` sets the text size (1.0 by default).
const _small = bool.fromEnvironment('SMALL');
final _scale = double.tryParse(const String.fromEnvironment('SCALE')) ?? 1;

class _Shot {
  const _Shot(this.name, this.route, this.scan, {this.after});

  final String name;
  final String route;
  final ScanOut Function() scan;
  final Future<void> Function(WidgetTester tester, ProviderContainer c)? after;
}

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

/// The mock's apple scab advice with another severity and timing (as the real server would send them).
ScanOut _advice({required String severity, required TimingOut? timing}) {
  final base = MockData.okScan('scan-1');
  return ScanOut.fromJson({
    ...base.toJson(),
    'advice': {...base.advice!.toJson(), 'severity': severity, 'timing': timing?.toJson()},
  });
}

Future<void> _scroll(WidgetTester tester, double dy) async {
  await tester.drag(find.byType(SingleChildScrollView).first, Offset(0, -dy));
  await _settle(tester);
}

void main() {
  final shots = <_Shot>[
    _Shot('advice', Routes.scanAdvice, () => MockData.okScan('scan-1')),
    _Shot(
      'advice-scrolled',
      Routes.scanAdvice,
      () => MockData.okScan('scan-1'),
      after: (tester, c) => _scroll(tester, 520),
    ),
    _Shot(
      'advice-more-open',
      Routes.scanAdvice,
      () => MockData.okScan('scan-1'),
      after: (tester, c) async {
        await tapKey(tester, 'advice-more');
        await _scroll(tester, 900);
      },
    ),
    _Shot(
      'advice-red-wait',
      Routes.scanAdvice,
      () => _advice(
        severity: 'red',
        timing: TimingOut(
          action: TimingAction.wait,
          text: LocalizedText.pair(
            en: 'Wait. Rain is expected in the next twelve hours.',
            hi: 'रुकिए। अगले बारह घंटे में बारिश की उम्मीद है।',
          ),
          rainNext12hMm: 6,
        ),
      ),
    ),
    _Shot(
      'advice-green-repeat',
      Routes.scanAdvice,
      () => _advice(
        severity: 'green',
        timing: TimingOut(
          action: TimingAction.repeatWithinDays,
          text: LocalizedText.pair(
            en: 'Heavy rain washed the spray off. Spray again within seven days.',
            hi: 'तेज़ बारिश से दवा धुल गई। सात दिन के अंदर दोबारा छिड़काव कीजिए।',
          ),
          repeatWithinDays: 7,
        ),
      ),
    ),
    _Shot(
      'advice-not-needed',
      Routes.scanAdvice,
      () => _advice(
        severity: 'green',
        timing: TimingOut(
          action: TimingAction.notNeeded,
          text: LocalizedText.pair(en: 'No spray is needed now.', hi: 'अभी छिड़काव की ज़रूरत नहीं है।'),
        ),
      ),
    ),
    _Shot(
      'advice-sprayed',
      Routes.scanAdvice,
      () => MockData.okScan('scan-1'),
      after: (tester, c) async {
        await c.read(sprayedAdvicesProvider.notifier).add('adv-scan-1');
        await _settle(tester);
      },
    ),
    _Shot('expert', Routes.scanExpert, () => MockData.needsExpertScan('s1')),
    _Shot(
      'expert-sent',
      Routes.scanExpert,
      () => MockData.needsExpertScan('s1'),
      after: (tester, c) => tapKey(tester, 'ask-expert'),
    ),
    _Shot('expert-no-data', Routes.scanExpert, () => MockData.noApprovedDataScan('s1')),
    _Shot(
      'expert-no-data-sent',
      Routes.scanExpert,
      () => MockData.noApprovedDataScan('s1'),
      after: (tester, c) => tapKey(tester, 'ask-expert'),
    ),
    _Shot('expert-not-disease', Routes.scanExpert, () => MockData.notADiseaseScan('s1')),
    _Shot(
      'expert-with-advice',
      Routes.scanExpert,
      () =>
          ScanOut.fromJson({...MockData.needsExpertScan('s1').toJson(), 'advice': MockData.scabAdvice('s1').toJson()}),
    ),
  ];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  for (final language in const ['en', 'hi']) {
    testWidgets('result screens in $language', (tester) async {
      if (_shotDir.isEmpty) fail('pass --dart-define=SHOT_DIR=<folder>');
      tester.view
        ..physicalSize = _small ? const Size(640, 1136) : const Size(780, 1688)
        ..devicePixelRatio = 2
        ..padding =
            const FakeViewPadding(top: 60) // the 30 dp status bar of the mockup's phone
        ..viewPadding = const FakeViewPadding(top: 60);
      tester.platformDispatcher.textScaleFactorTestValue = _scale;
      addTearDown(() {
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
        tester.view.resetViewPadding();
      });

      var n = 0;
      for (final shot in shots) {
        // A fresh app per state: the sprayed mark and the saved case must not leak into the next picture.
        final api = MockApiClient(latency: Duration.zero);
        final env = await TestEnv.create(language: language, loggedIn: true, api: api);
        await tester.pumpWidget(
          RepaintBoundary(
            key: _boundary,
            child: env.app(location: '/home'),
          ),
        );
        await tester.pumpAndSettle();
        final container = containerOf(tester);
        final scan = shot.scan();
        api.scans[scan.id] = scan;
        container.read(scanFlowProvider.notifier)
          ..reset()
          ..showResult(scan);
        container.read(routerProvider).go(shot.route);
        await _settle(tester);
        await shot.after?.call(tester, container);
        await _settle(tester);
        n++;
        await _save(tester, '$_shotDir/$language/${n.toString().padLeft(2, '0')}-${shot.name}.png');
        final error = tester.takeException();
        if (error != null) debugPrint('NOTE ${shot.name}: ${error.toString().split('\n').first}');
        await tester.pumpWidget(const SizedBox());
      }
    });
  }
}
