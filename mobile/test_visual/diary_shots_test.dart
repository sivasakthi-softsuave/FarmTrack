import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmtrack/core/errors/api_exception.dart';
import 'package:farmtrack/core/models/models.dart';
import 'package:farmtrack/core/network/mock_api_client.dart';
import 'package:farmtrack/core/network/mock_data.dart';
import 'package:farmtrack/core/offline/offline_queue.dart';
import 'package:farmtrack/core/router/app_router.dart';
import 'package:farmtrack/core/router/routes.dart';
import 'package:farmtrack/features/diary/date_words.dart';
import 'package:farmtrack/features/diary/diary_providers.dart';
import 'package:farmtrack/features/scan/scan_flow.dart';

import '../test/support/feature_fakes.dart';
import '../test/support/harness.dart';

/// Renders the diary screens (list, write a spray, confirm, day chooser, saved with and without warnings) to PNG files, to
/// compare them with the approved mockup (`docs/design/ui-redesign-mockup.html`, 390 x 844 phones).
///
///     flutter test test_visual/diary_shots_test.dart --dart-define=SHOT_DIR=C:\some\folder
///
/// One folder per language (`en`, `hi`), one `NN-name.png` per screen, 780 x 1688 pixels (2x). Not part of `flutter test`.
/// The phone's clock is 12 May 2026 (the mock server's demo day).
const _shotDir = String.fromEnvironment('SHOT_DIR');

/// A mock server that can answer a diary entry with three warnings, so that state can be shown.
class _Api extends MockApiClient {
  _Api() : super(latency: Duration.zero);

  bool manyWarnings = false;

  @override
  Future<SprayLogOut> createSprayLog(SprayLogIn log, {String? idempotencyKey}) async {
    final out = await super.createSprayLog(log, idempotencyKey: idempotencyKey);
    if (!manyWarnings) return out;
    final warnings = [
      ...MockData.sprayWarnings(freeText: 'Miravis'),
      ...MockData.sprayWarnings(freeText: 'Mancozeb'),
      ...MockData.sprayWarnings(freeText: 'unknown product'),
    ];
    return SprayLogOut(
      id: out.id,
      cropId: out.cropId,
      productId: out.productId,
      productName: out.productName,
      sprayedAt: out.sprayedAt,
      adviceId: out.adviceId,
      warnings: warnings,
      syncedToZoho: true,
      spoken: MockData.sprayLogSpoken(warnings),
    );
  }
}

typedef _Prepare = FutureOr<void> Function(ProviderContainer c, _Api api, ScanFlowNotifier flow);
typedef _After = Future<void> Function(WidgetTester tester);

class _Shot {
  const _Shot(this.name, this.route, {this.prepare, this.after});

  final String name;
  final String route;
  final _Prepare? prepare;
  final _After? after;
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

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await _settle(tester);
}

Future<void> _type(WidgetTester tester, String name) async {
  final field = find.byKey(const ValueKey('diary-name-field'));
  await tester.tap(field); // focus: the field draws its green glow
  await tester.pump();
  await tester.enterText(field, name);
  await _settle(tester);
}

DateTime _day(int month, int day) => DateTime.utc(2026, month, day, 12);

/// Crop, name, "next": the confirm screen of a spray that was written by hand.
Future<void> _toSummary(WidgetTester tester, String name) async {
  await _tap(tester, 'crop-apple');
  await _type(tester, name);
  await _tap(tester, 'diary-next');
}

/// The "I sprayed" confirm screen of an advice with two medicines.
ScanOut _twoMedicineScan() {
  final base = MockData.scabAdvice('scan-1');
  final product = base.products.single;
  return ScanOut.fromJson({
    ...MockData.okScan('scan-1').toJson(),
    'advice': {
      ...base.toJson(),
      'products': [
        product.toJson(),
        {
          ...product.toJson(),
          'product_id': 'P006',
          'active_ingredient': {'en': 'Propineb', 'hi': 'प्रोपीनेब'},
          'brand_examples': ['Antracol'],
          'dose_text': {'en': 'Two grams in one litre of water.', 'hi': 'एक लीटर पानी में दो ग्राम।'},
        },
      ],
    },
  });
}

void main() {
  final confirmRoute = Routes.diaryFor(adviceId: 'adv-scan-1', cropId: 'apple');

  final shots = <_Shot>[
    // The list as the mockup draws it: a waiting entry today, one with a warning on 2 May, a saved one on 24 April.
    _Shot(
      'diary',
      Routes.diary,
      prepare: (c, api, flow) async {
        await api.createSprayLog(SprayLogIn(cropId: 'apple', freeText: 'Captan', sprayedAt: _day(5, 2)));
        await api.createSprayLog(SprayLogIn(cropId: 'apple', freeText: 'Score', sprayedAt: _day(4, 24)));
        c
            .read(pendingSpraysProvider.notifier)
            .add(
              PendingSpray(
                key: 'k1',
                log: SprayLogIn(cropId: 'apple', productId: 'P007', sprayedAt: fixedNow.toUtc()),
                name: 'Difenoconazole (Score)',
              ),
            );
      },
    ),
    // Serious, careful and "not recognised" warnings, a long name, a vegetable crop.
    _Shot(
      'diary-warnings',
      Routes.diary,
      prepare: (c, api, flow) async {
        await api.createSprayLog(SprayLogIn(cropId: 'apple', freeText: 'Miravis Duo', sprayedAt: _day(5, 12)));
        await api.createSprayLog(SprayLogIn(cropId: 'potato', freeText: 'Mancozeb', sprayedAt: _day(5, 11)));
        await api.createSprayLog(
          SprayLogIn(
            cropId: 'apple',
            freeText: 'A medicine with a very long name that has to wrap on a small phone',
            sprayedAt: _day(5, 9),
          ),
        );
      },
    ),
    const _Shot('diary-empty', Routes.diary),
    // No internet: the pending entry and the list the phone kept (none here), with the offline row.
    _Shot(
      'diary-offline',
      Routes.diary,
      prepare: (c, api, flow) {
        c
            .read(pendingSpraysProvider.notifier)
            .add(
              PendingSpray(
                key: 'k1',
                log: SprayLogIn(cropId: 'apple', freeText: 'Score', sprayedAt: fixedNow.toUtc()),
                name: 'Score',
              ),
            );
        api.failWith(const ApiException.network(), ops: {'listSprayLogs'});
      },
    ),
    // Write a spray: crop, medicine, confirm, other day.
    const _Shot('diary-add', Routes.diaryAdd),
    _Shot('diary-add-page-2', Routes.diaryAdd, after: (tester) => _tap(tester, 'crops-next')),
    _Shot(
      'diary-add-medicine',
      Routes.diaryAdd,
      prepare: (c, api, flow) async {
        await api.createSprayLog(SprayLogIn(cropId: 'apple', freeText: 'Score', sprayedAt: _day(5, 9)));
        await api.createSprayLog(SprayLogIn(cropId: 'apple', freeText: 'Antracol', sprayedAt: _day(5, 10)));
      },
      after: (tester) => _tap(tester, 'crop-apple'),
    ),
    _Shot(
      'diary-add-typing',
      Routes.diaryAdd,
      after: (tester) async {
        await _tap(tester, 'crop-apple');
        await _type(tester, 'Mancozeb');
      },
    ),
    _Shot('diary-add-summary', Routes.diaryAdd, after: (tester) => _toSummary(tester, 'Mancozeb')),
    _Shot(
      'diary-add-day',
      Routes.diaryAdd,
      after: (tester) async {
        await _toSummary(tester, 'Mancozeb');
        await _tap(tester, 'day-other');
      },
    ),
    // The confirm screen after "I sprayed" (one medicine, two medicines with one chosen).
    _Shot('diary-confirm', confirmRoute, prepare: (c, api, flow) => flow.showResult(MockData.okScan('scan-1'))),
    _Shot(
      'diary-confirm-two',
      confirmRoute,
      prepare: (c, api, flow) => flow.showResult(_twoMedicineScan()),
      after: (tester) => _tap(tester, 'diary-product-P006'),
    ),
    // Saved: no warning, one warning, three warnings, no internet.
    _Shot(
      'diary-saved',
      Routes.diaryAdd,
      after: (tester) async {
        await _toSummary(tester, 'Score');
        await _tap(tester, 'diary-save');
      },
    ),
    _Shot(
      'diary-saved-one-warning',
      Routes.diaryAdd,
      after: (tester) async {
        await _toSummary(tester, 'Mancozeb');
        await _tap(tester, 'diary-save');
      },
    ),
    _Shot(
      'diary-saved-warnings',
      confirmRoute,
      prepare: (c, api, flow) {
        api.manyWarnings = true;
        flow.showResult(MockData.okScan('scan-1'));
      },
      after: (tester) => _tap(tester, 'diary-save'),
    ),
    _Shot(
      'diary-saved-offline',
      confirmRoute,
      prepare: (c, api, flow) {
        flow.showResult(MockData.okScan('scan-1'));
        api.failWith(const ApiException.network(), ops: {'createSprayLog'});
      },
      after: (tester) => _tap(tester, 'diary-save'),
    ),
  ];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  for (final language in const ['en', 'hi']) {
    testWidgets('diary screens in $language', (tester) async {
      if (_shotDir.isEmpty) fail('pass --dart-define=SHOT_DIR=<folder>');
      tester.view
        ..physicalSize = const Size(780, 1688)
        ..devicePixelRatio = 2
        ..padding =
            const FakeViewPadding(top: 60) // the 30 dp status bar of the mockup's phone
        ..viewPadding = const FakeViewPadding(top: 60);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
        tester.view.resetViewPadding();
        tester.view.resetViewInsets();
      });

      var n = 0;
      for (final shot in shots) {
        final api = _Api();
        final env = await TestEnv.create(
          language: language,
          loggedIn: true,
          api: api,
          extraOverrides: [
            clockProvider.overrideWithValue(() => fixedNow),
            offlineQueueProvider.overrideWithValue(FakeOfflineQueue()),
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
        flow.reset();
        tester.takeException();
        await shot.prepare?.call(container, api, flow);
        router.go(shot.route);
        await _settle(tester);
        await shot.after?.call(tester);
        n++;
        await _save(tester, '$_shotDir/$language/${n.toString().padLeft(2, '0')}-${shot.name}.png');
        final error = tester.takeException();
        if (error != null) debugPrint('NOTE ${shot.name}: ${error.toString().split('\n').first}');
        tester.view.resetViewInsets();
        await tester.pumpWidget(const SizedBox());
      }
    });
  }
}
