import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmtrack/core/providers.dart';
import 'package:farmtrack/core/router/routes.dart';
import 'package:farmtrack/core/settings/app_settings.dart';
import 'package:farmtrack/core/theme/app_theme.dart';

import 'support/finders.dart';
import 'support/harness.dart';

void main() {
  group('home', () {
    testWidgets(
      'a big photo card, the bottom bar, a gear and a bell; every target is at least 56 dp, the photo card much larger',
      (tester) async {
        useSmallPhone(tester);
        final env = await TestEnv.create(loggedIn: true);
        await pumpApp(tester, env);
        final scan = tester.getSize(keyed('home-scan'));
        expect(scan.width, greaterThanOrEqualTo(96));
        expect(scan.height, greaterThanOrEqualTo(96));
        // Field, Diary and Ask are in the bottom bar.
        for (final key in ['home-field', 'home-diary', 'home-ask', 'nav-scan']) {
          final size = tester.getSize(keyed(key));
          expect(size.width, greaterThanOrEqualTo(56), reason: key);
          expect(size.height, greaterThanOrEqualTo(56), reason: key);
        }
        // The camera is the photo card and the middle of the bar.
        expect(find.byIcon(AppIcons.camera), findsNWidgets(2));
        expect(find.byIcon(AppIcons.field), findsOneWidget);
        expect(find.byIcon(AppIcons.notebook), findsOneWidget);
        expect(find.byIcon(AppIcons.question), findsOneWidget);
        expect(find.byIcon(AppIcons.gear), findsOneWidget);
        expect(find.byIcon(AppIcons.bell), findsOneWidget);
        expectBigTouchTargets(tester);
      },
    );

    testWidgets(
      'first visit: speaks the intro and then each button; later visits only the intro; the speaker replays everything',
      (tester) async {
        final env = await TestEnv.create(loggedIn: true, homeTourDone: false);
        final container = await pumpApp(tester, env);
        expect(env.voice.spokenIds, [
          'home_intro',
          'home_scan',
          'home_field',
          'home_diary',
          'home_ask',
          'home_settings',
        ]);
        expect(container.read(settingsProvider).homeTourDone, isTrue);

        env.voice.clear();
        await replayVoice(tester);
        expect(env.voice.spokenIds, hasLength(6), reason: 'turning the voice back on replays the whole tour');

        // A second visit (new Home screen): only the short intro.
        env.voice.clear();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(env.app(location: '/home'));
        await tester.pumpAndSettle();
        expect(env.voice.spokenIds, ['home_intro']);
      },
    );

    testWidgets('the photo card is one button: there is no gallery row under it (the camera page has the gallery)', (
      tester,
    ) async {
      useSmallPhone(tester);
      final env = await TestEnv.create(loggedIn: true, language: 'en');
      await pumpApp(tester, env, location: '/home');
      expect(keyed('home-scan'), findsOneWidget);
      expect(find.text('Or choose a photo from the gallery'), findsNothing);
      expect(find.byIcon(AppIcons.gallery), findsNothing);
      expect(find.byKey(const ValueKey('home-gallery')), findsNothing);
      expect(env.picker.galleryOpened, 0);
      await tapKey(tester, 'home-scan');
      expect(find.byKey(const ValueKey('gallery-button')), findsOneWidget, reason: 'the gallery is on the camera page');
    });

    testWidgets(
      'alerts, settings and the voice button share one line at the right, drawn smaller, with 56 dp tap areas',
      (tester) async {
        useSmallPhone(tester, size: const Size(390, 844));
        final env = await TestEnv.create(loggedIn: true, language: 'en');
        await pumpApp(tester, env, location: '/home');
        final bell = tester.getRect(keyed('home-alerts'));
        final gear = tester.getRect(keyed('home-settings'));
        final voice = tester.getRect(keyed('voice-button'));
        final greeting = tester.getRect(keyed('home-greeting'));

        // One line at the right, in this order: bell, gear, voice; the names (greeting, place) are left of them.
        expect(gear.center.dy, closeTo(bell.center.dy, 0.5));
        expect(voice.center.dy, closeTo(bell.center.dy, 0.5));
        expect(greeting.right, lessThanOrEqualTo(bell.left + 0.5));
        expect(bell.right, lessThanOrEqualTo(gear.left + 0.5));
        expect(gear.right, lessThanOrEqualTo(voice.left + 0.5));
        expect(voice.right, lessThanOrEqualTo(390));

        // One voice button, not a speaker and a mute button.
        expect(find.byIcon(AppIcons.speaker), findsOneWidget);
        expect(
          find.byIcon(AppIcons.noVoice),
          findsNothing,
          reason: 'the crossed-out speaker shows only while the voice is off',
        );

        // The circles are drawn 40 dp (a little smaller than the 48 dp of the other screens); the tap areas stay 56 dp.
        for (final key in ['home-alerts', 'home-settings', 'voice-button']) {
          final area = tester.getSize(keyed(key));
          expect(area.width, greaterThanOrEqualTo(56), reason: key);
          expect(area.height, greaterThanOrEqualTo(56), reason: key);
          final circle = find.descendant(
            of: keyed(key),
            matching: find.byWidgetPredicate(
              (w) => w is Container && w.constraints == BoxConstraints.tightFor(width: 40, height: 40),
            ),
          );
          expect(circle, findsOneWidget, reason: '$key is drawn 40 dp wide');
        }
        expectBigTouchTargets(tester);
      },
    );

    testWidgets('one voice button turns the voice off and on: the speaker, then the crossed-out speaker in red', (
      tester,
    ) async {
      useSmallPhone(tester);
      final env = await TestEnv.create(loggedIn: true, language: 'en');
      final container = await pumpApp(tester, env, location: '/home');
      expect(container.read(settingsProvider).muted, isFalse);
      await tester.tap(keyed('voice-button'));
      await tester.pump();
      expect(container.read(settingsProvider).muted, isTrue);
      expect(find.byIcon(AppIcons.noVoice), findsOneWidget);
      expect(find.byIcon(AppIcons.speaker), findsNothing);
      expect(env.voice.stopCalls, greaterThan(0), reason: 'what is being said stops at once');
      env.voice.clear();
      await tester.tap(keyed('voice-button'));
      await tester.pump();
      expect(container.read(settingsProvider).muted, isFalse);
      expect(find.byIcon(AppIcons.speaker), findsOneWidget);
      expect(env.voice.spokenIds.first, 'home_intro', reason: 'the voice is back and says the page again');
      expect(env.voice.spokenIds, hasLength(6), reason: 'the whole tour, as the speaker button used to');
    });

    testWidgets('each button opens its screen, which speaks its own introduction', (tester) async {
      useSmallPhone(tester);
      final env = await TestEnv.create(loggedIn: true);
      await pumpApp(tester, env);
      final expected = {
        'home-field': 'field_intro',
        'home-diary': 'diary_intro',
        'home-ask': 'ask_intro',
        'home-alerts': 'alert_open',
        'home-settings': 'settings_speed',
      };
      for (final entry in expected.entries) {
        env.voice.clear();
        await tapKey(tester, entry.key);
        expect(env.voice.spokenIds.first, entry.value, reason: entry.key);
        await goBack(tester);
        expect(keyed('home-scan'), findsOneWidget);
      }
    });

    testWidgets('the bell shows how many alerts are unread; the offline sign shows with no network', (tester) async {
      useSmallPhone(tester);
      final env = await TestEnv.create(loggedIn: true);
      await pumpApp(tester, env);
      expect(find.descendant(of: keyed('alert-badge'), matching: find.text('1')), findsOneWidget);
      expect(find.byIcon(AppIcons.offline), findsNothing);
      env.connectivity.online = false;
      await tester.pumpAndSettle();
      expect(find.byIcon(AppIcons.offline), findsOneWidget);
    });
  });

  group('settings', () {
    Future<TestEnv> openSettings(WidgetTester tester) async {
      useSmallPhone(tester);
      final env = await TestEnv.create(loggedIn: true);
      await pumpApp(tester, env, location: Routes.home);
      await tapKey(tester, 'home-settings');
      env.voice.clear();
      return env;
    }

    testWidgets('speaks about speed and volume; every control is a big picture', (tester) async {
      useSmallPhone(tester);
      final env = await TestEnv.create(loggedIn: true);
      await pumpApp(tester, env, location: Routes.home);
      env.voice.clear();
      await tapKey(tester, 'home-settings');
      expect(env.voice.spokenIds, ['settings_speed', 'settings_volume']);
      expectBigTouchTargets(tester);
    });

    testWidgets('speed: the choice is applied, saved and demonstrated by speaking', (tester) async {
      final env = await openSettings(tester);
      await tapKey(tester, 'speed-slow');
      expect(containerOf(tester).read(settingsProvider).speed, SpeechSpeed.slow);
      expect(env.prefs.getString('speech_speed'), 'slow');
      expect(env.voice.spokenIds, ['settings_speed']);
      await tapKey(tester, 'speed-fast');
      expect(containerOf(tester).read(settingsProvider).speed, SpeechSpeed.fast);
    });

    testWidgets('volume: the choice is applied, saved and demonstrated by speaking', (tester) async {
      final env = await openSettings(tester);
      await tapKey(tester, 'volume-low');
      expect(containerOf(tester).read(settingsProvider).volume, VolumeLevel.low);
      expect(env.prefs.getString('volume'), 'low');
      expect(env.voice.spokenIds, ['settings_volume']);
    });

    testWidgets('language: switching to English changes the words, tells the server and confirms in English', (
      tester,
    ) async {
      final env = await openSettings(tester);
      expect(find.text('भाषा'), findsOneWidget);
      await tapKey(tester, 'language-en');
      expect(containerOf(tester).read(languageProvider), 'en');
      expect(env.prefs.getString('language'), 'en');
      expect(env.voice.log.last, 'settings_language_changed@en');
      expect(find.text('LANGUAGE'), findsOneWidget);
      expect(env.api.calls, contains('patchMe'));
      expect((await env.api.me()).language, 'en');
    });

    testWidgets('captions can be switched off and on; the choice is saved', (tester) async {
      final env = await openSettings(tester);
      expect(keyed('voice-caption'), findsOneWidget);
      await tapKey(tester, 'settings-captions');
      expect(containerOf(tester).read(settingsProvider).captions, isFalse);
      expect(env.prefs.getBool('captions'), isFalse);
      expect(keyed('voice-caption'), findsNothing);
      await tapKey(tester, 'settings-captions');
      expect(env.prefs.getBool('captions'), isTrue);
    });

    testWidgets('log out asks for a tick or a cross; the tick clears the login and returns to the login screen', (
      tester,
    ) async {
      final env = await openSettings(tester);
      await tapKey(tester, 'log-out');
      expect(env.voice.spokenIds, ['settings_logout_confirm']);
      expect(await env.tokens.read(), isNotNull, reason: 'nothing happens before the farmer confirms');
      await tapKey(tester, 'logout-yes');
      expect(keyed('login-username'), findsOneWidget);
      expect(await env.tokens.read(), isNull);
      expect(containerOf(tester).read(sessionProvider).isLoggedIn, isFalse);
      expect(env.api.calls, contains('logout'), reason: 'the server is told so it can revoke the refresh token');
    });

    testWidgets('settings survive a restart', (tester) async {
      final env = await openSettings(tester);
      await tapKey(tester, 'speed-slow');
      await tapKey(tester, 'volume-medium');
      await tapKey(tester, 'settings-captions');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(env.app(location: Routes.settings));
      await tester.pumpAndSettle();
      final settings = containerOf(tester).read(settingsProvider);
      expect(settings.speed, SpeechSpeed.slow);
      expect(settings.volume, VolumeLevel.medium);
      expect(settings.captions, isFalse);
      expect(settings.language, 'hi');
    });
  });

  group('session', () {
    testWidgets('when the server rejects the refresh token the farmer is sent to the login screen', (tester) async {
      useSmallPhone(tester);
      final env = await TestEnv.create(loggedIn: true);
      final container = await pumpApp(tester, env);
      expect(keyed('home-scan'), findsOneWidget);
      container.read(sessionProvider.notifier).expire();
      await tester.pumpAndSettle();
      expect(keyed('login-username'), findsOneWidget);
    });

    testWidgets('logged-out farmers cannot open private screens by route', (tester) async {
      final env = await TestEnv.create(onboardingDone: true);
      await pumpApp(tester, env, location: Routes.scan);
      expect(keyed('login-username'), findsOneWidget);
      expect(keyed('camera-button'), findsNothing);
    });
  });
}
