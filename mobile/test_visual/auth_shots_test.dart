import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmtrack/core/config/app_config.dart';
import 'package:farmtrack/core/providers.dart';
import 'package:farmtrack/core/storage/token_store.dart';

import '../test/support/finders.dart';
import '../test/support/harness.dart';

/// Renders the screens before the farmer is logged in (splash, language, welcome, login, server dialog) to PNG files, to
/// compare them with the approved mockup (`docs/design/ui-redesign-mockup.html`, 390 x 844 phones).
///
///     flutter test test_visual/auth_shots_test.dart --dart-define=SHOT_DIR=C:\some\folder
///
/// One folder per language (`en`, `hi`), one `NN-name.png` per screen, 780 x 1688 pixels (2x). Not part of `flutter test`.
const _shotDir = String.fromEnvironment('SHOT_DIR');

/// A real server (not the demo mock), so the login screen shows its "Server: ... Change" line.
const _realServer = AppConfig(apiBaseUrl: 'http://192.168.1.5:8000', useMockApi: false, mockLatency: Duration.zero);

/// A phone key store that never answers: the splash screen stays on the logo.
class _HangingStore implements TokenStore {
  @override
  Future<StoredTokens?> read() => Completer<StoredTokens?>().future;

  @override
  Future<void> write(StoredTokens tokens) => Completer<void>().future;

  @override
  Future<void> clear() => Completer<void>().future;
}

/// A start that fails outright, to see the splash screen's error card.
class _BrokenSession extends SessionNotifier {
  @override
  Future<void> restore() async => throw StateError('keystore is broken');

  @override
  void assumeLoggedOut() => throw StateError('cannot continue as logged out');
}

class _Shot {
  const _Shot(this.name, this.create, {this.after, this.settle = true});

  final String name;
  final Future<TestEnv> Function(String language) create;
  final Future<void> Function(WidgetTester tester, TestEnv env)? after;

  /// Let the screen's animations and speech run to their end (not for the splash, which must not move on).
  final bool settle;
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

Future<TestEnv> _loginEnv(String language, {bool prefill = true, AppConfig? config}) async {
  final env = await TestEnv.create(language: language, onboardingDone: true, config: config ?? const AppConfig.test());
  if (prefill) await env.prefs.setString('last_username', 'f001');
  return env;
}

void main() {
  final shots = <_Shot>[
    _Shot('splash', (l) => TestEnv.create(language: l, tokenStore: _HangingStore()), settle: false),
    _Shot(
      'splash-slow',
      (l) => TestEnv.create(language: l, tokenStore: _HangingStore()),
      after: (tester, env) => tester.pump(const Duration(seconds: 6, milliseconds: 500)),
      settle: false,
    ),
    _Shot(
      'splash-error',
      (l) => TestEnv.create(language: l, extraOverrides: [sessionProvider.overrideWith(_BrokenSession.new)]),
      settle: false,
    ),
    _Shot('language', (l) => TestEnv.create(language: null)),
    _Shot('welcome', (l) => TestEnv.create(language: l)),
    // The mockup's login: user name filled in, password typed and focused, a real server.
    _Shot(
      'login',
      (l) => _loginEnv(l, config: _realServer),
      after: (tester, env) async {
        await enterLogin(tester, password: 'farm1234');
      },
    ),
    _Shot('login-empty', (l) => _loginEnv(l, prefill: false, config: _realServer)),
    _Shot(
      'login-password-shown',
      (l) => _loginEnv(l, config: _realServer),
      after: (tester, env) async {
        await enterLogin(tester, password: 'farm1234');
        await tapKey(tester, 'login-eye');
      },
    ),
    _Shot(
      'login-wrong',
      (l) => _loginEnv(l, config: _realServer),
      after: (tester, env) async {
        await enterLogin(tester, password: 'abc');
        await tapKey(tester, 'login-submit');
      },
    ),
    _Shot(
      'server-dialog',
      (l) => _loginEnv(l, config: _realServer),
      after: (tester, env) async {
        await tapKey(tester, 'server-link');
      },
    ),
    _Shot(
      'server-dialog-error',
      (l) => _loginEnv(l, config: _realServer),
      after: (tester, env) async {
        await tapKey(tester, 'server-link');
        await tester.enterText(keyed('server-field'), '192.168.1.5');
        await tapKey(tester, 'server-save');
      },
    ),
    _Shot(
      'login-keyboard',
      (l) => _loginEnv(l, config: _realServer),
      after: (tester, env) async {
        tester.view.viewInsets = const FakeViewPadding(bottom: 600);
        await tester.pump();
      },
    ),
  ];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  for (final language in const ['en', 'hi']) {
    testWidgets('screens before login in $language', (tester) async {
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
        final env = await shot.create(language);
        await tester.pumpWidget(RepaintBoundary(key: _boundary, child: env.app()));
        // The splash screen moves on by itself; take it before that.
        if (shot.settle) {
          await _settle(tester);
        } else {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await shot.after?.call(tester, env);
        if (shot.settle) await _settle(tester);
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
