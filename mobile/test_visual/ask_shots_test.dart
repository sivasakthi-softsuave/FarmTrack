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
import 'package:farmtrack/core/router/app_router.dart';
import 'package:farmtrack/core/router/routes.dart';
import 'package:farmtrack/features/ask/ask_flow.dart';
import 'package:farmtrack/features/ask/ask_suggestions.dart';
import 'package:farmtrack/features/home/home_screen.dart';

import '../test/support/finders.dart';
import '../test/support/harness.dart';

/// The states of the Ask screens that the shared harness does not draw (typed text, waiting, long answer, refusal, expert
/// request sent), as PNG files:
///
///     flutter test test_visual/ask_shots_test.dart --dart-define=SHOT_DIR=C:\some\folder
const _shotDir = String.fromEnvironment('SHOT_DIR');

class _Api extends MockApiClient {
  _Api() : super(latency: Duration.zero);
  bool hangAsk = false;
  bool longAnswer = false;

  @override
  Future<AskOut> ask(AskIn question) async {
    if (hangAsk) await Completer<void>().future;
    if (longAnswer) {
      return AskOut(
        answer: List.filled(8, 'Keep the orchard floor clean and remove the fallen leaves.').join(' '),
        language: question.language,
        citations: const [
          CitationOut(noteId: 'N1', source: 'HP Horticulture Department / UHF Nauni Spray Schedule 2026'),
          CitationOut(noteId: 'N2', source: 'SKUAST-Kashmir 2026 guidance'),
        ],
      );
    }
    return super.ask(question);
  }
}

class _Shot {
  const _Shot(this.name, this.route, {this.prepare, this.after});

  final String name;
  final String route;
  final FutureOr<void> Function(ProviderContainer c, _Api api)? prepare;
  final Future<void> Function(WidgetTester tester)? after;
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
  final suggestions = parseAskSuggestions(File('assets/l10n/ask_suggestions.json').readAsStringSync());
  final fixedSuggestions = askSuggestionsProvider.overrideWith((ref) => suggestions);

  final shots = <_Shot>[
    const _Shot('list', Routes.ask),
    _Shot(
      'type-typed',
      Routes.askType,
      after: (tester) async {
        await tester.enterText(keyed('ask-field'), 'Why are the leaves of my apple tree turning yellow in June?');
        await tester.pump();
      },
    ),
    _Shot(
      'waiting',
      Routes.askAnswer,
      prepare: (c, api) {
        api.hangAsk = true;
        unawaited(c.read(askFlowProvider.notifier).ask('When does apple scab spread?'));
      },
    ),
    _Shot(
      'answer-long',
      Routes.askAnswer,
      prepare: (c, api) async {
        api.longAnswer = true;
        await c.read(askFlowProvider.notifier).ask('When does apple scab spread?');
      },
    ),
    _Shot(
      'refused',
      Routes.askAnswer,
      prepare: (c, api) => c.read(askFlowProvider.notifier).ask('Who wins the lottery?'),
    ),
    _Shot(
      'refused-sent',
      Routes.askAnswer,
      prepare: (c, api) => c.read(askFlowProvider.notifier).ask('Who wins the lottery?'),
      after: (tester) async {
        await tester.tap(keyed('ask-expert'));
        await _settle(tester);
      },
    ),
  ];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  for (final language in const ['en', 'hi']) {
    testWidgets('ask screens in $language', (tester) async {
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

      var n = 0;
      for (final shot in shots) {
        router.go(Routes.home);
        await _settle(tester);
        container.read(askFlowProvider.notifier).reset();
        api
          ..hangAsk = false
          ..longAnswer = false;
        tester.takeException();
        await shot.prepare?.call(container, api);
        router.go(shot.route);
        await _settle(tester);
        await shot.after?.call(tester);
        await _settle(tester);
        n++;
        await _save(tester, '$_shotDir/$language/${n.toString().padLeft(2, '0')}-${shot.name}.png');
        final error = tester.takeException();
        if (error != null) debugPrint('NOTE ${shot.name}: ${error.toString().split('\n').first}');
      }
    });
  }
}
