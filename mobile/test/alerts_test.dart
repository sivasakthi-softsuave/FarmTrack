import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmtrack/core/errors/api_exception.dart';
import 'package:farmtrack/core/models/models.dart';
import 'package:farmtrack/core/network/mock_api_client.dart';
import 'package:farmtrack/core/network/mock_data.dart';
import 'package:farmtrack/core/providers.dart';
import 'package:farmtrack/core/router/app_router.dart';
import 'package:farmtrack/core/router/routes.dart';
import 'package:farmtrack/features/alerts/alert_widgets.dart';
import 'package:farmtrack/features/alerts/alerts_providers.dart';
import 'package:farmtrack/features/diary/date_words.dart';
import 'package:farmtrack/core/theme/app_theme.dart';
import 'package:farmtrack/core/widgets/design.dart';

import 'support/feature_fakes.dart';
import 'support/finders.dart';
import 'support/harness.dart';

Future<TestEnv> alertsEnv({MockApiClient? api, String language = 'hi'}) => TestEnv.create(
  loggedIn: true,
  language: language,
  api: api ?? MockApiClient(latency: Duration.zero),
  extraOverrides: [clockProvider.overrideWithValue(() => fixedNow)],
);

/// Home, then the bell. Afterwards the voice log holds what the alert list said.
Future<void> openAlerts(WidgetTester tester, TestEnv env, {double textScale = 1.0, Size? size}) async {
  useSmallPhone(tester, textScale: textScale, size: size ?? const Size(360, 640));
  await pumpApp(tester, env, location: '/home');
  env.voice.clear();
  await tapKey(tester, 'home-alerts');
}

AlertOut alert(
  String id, {
  Severity level = Severity.yellow,
  DateTime? at,
  bool read = false,
  String? scanId,
  String? spokenHi,
}) => AlertOut(
  id: id,
  kind: 'scab_infection_risk',
  level: level,
  title: LocalizedText.pair(en: 'Title $id', hi: 'शीर्षक $id'),
  body: LocalizedText.pair(en: 'Body of $id.', hi: 'पूरा लिखा $id।'),
  spoken: SpokenOut(
    text: LocalizedText.pair(en: 'Say $id.', hi: spokenHi ?? 'बोला $id।'),
  ),
  createdAt: at ?? DateTime.utc(2026, 5, 11, 12),
  readAt: read ? DateTime.utc(2026, 5, 11, 13) : null,
  scanId: scanId,
);

void main() {
  group('the alert list', () {
    testWidgets(
      'newest first; each alert is a white card: a round dot (colour and picture show how urgent), the title, the '
      'message and the time; an unread one has a blue "New" tag, a read one is paler',
      (tester) async {
        final env = await alertsEnv();
        await openAlerts(tester, env);
        final semantics = tester.ensureSemantics();

        final first = MockData.alerts().items.first;
        final unread = keyed('alert-alert-1');
        final read = keyed('alert-alert-2');
        expect(unread, findsOneWidget);
        expect(tester.getTopLeft(unread).dy, lessThan(tester.getTopLeft(read).dy));

        // Level: colour and picture on a 44 dp round dot (the word is in the semantics, as the mockup shows none).
        IconDot dotOf(Finder card) => tester.widget<IconDot>(find.descendant(of: card, matching: find.byType(IconDot)));
        expect(find.descendant(of: unread, matching: find.byIcon(AppIcons.rain)), findsOneWidget);
        expect(find.descendant(of: unread, matching: find.bySemanticsLabel(RegExp('गंभीर'))), findsOneWidget);
        expect(dotOf(unread).background, AppColors.red, reason: 'urgent: red with a white picture');
        expect(dotOf(unread).foreground, Colors.white);
        expect(find.descendant(of: read, matching: find.byIcon(AppIcons.warning)), findsOneWidget);
        expect(find.descendant(of: read, matching: find.bySemanticsLabel(RegExp('सावधान'))), findsOneWidget);
        expect(dotOf(read).background, AppColors.amber, reason: 'be careful: amber with a dark picture');
        expect(dotOf(read).foreground, AppColors.ink);
        expect(dotOf(unread).size, 44);
        expect(dotOf(unread).round, isTrue);

        // Unread: a blue "New" tag, 24 high, 12 px white words; read: none.
        expect(keyed('alert-new-alert-1'), findsOneWidget);
        expect(find.descendant(of: unread, matching: find.text('नई')), findsOneWidget);
        expect(keyed('alert-new-alert-2'), findsNothing);
        final tag = tester.widget<AppPill>(keyed('alert-new-alert-1'));
        expect((tag.background, tag.foreground, tag.height, tag.fontSize), (AppColors.blue, Colors.white, 24, 12));

        // Title (17 / 700), the message (15) and the time in grey (13).
        final title = tester.widget<Text>(find.descendant(of: unread, matching: find.text('बारिश ने छिड़काव धो दिया')));
        expect((title.style!.fontSize, title.style!.fontWeight), (17, FontWeight.w700));
        final message = tester.widget<Text>(find.descendant(of: unread, matching: find.text(first.body.hi)));
        expect(message.style!.fontSize, 15);
        final local = first.createdAt!.toLocal();
        final hhmm = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
        final time = tester.widget<Text>(find.descendant(of: unread, matching: find.text('आज, $hhmm')));
        expect((time.style!.fontSize, time.style!.color), (13, AppColors.inkSoft));

        // A read alert is 85 % opaque; an unread one is not faded.
        int fades(Finder card) => find.ancestor(of: card, matching: find.byType(Opacity)).evaluate().length;
        expect(fades(read), fades(unread) + 1);
        expect(tester.widget<Opacity>(find.ancestor(of: read, matching: find.byType(Opacity)).first).opacity, 0.85);

        expect(env.voice.spokenIds, ['alert_open']);
        expect(env.voice.unknownIds, isEmpty);
        expectBigTouchTargets(tester);
        semantics.dispose();
      },
    );

    testWidgets('an urgent unread alert has the outline "Listen" button; it speaks that alert and opens nothing', (
      tester,
    ) async {
      final api = MockApiClient(latency: Duration.zero);
      final env = await alertsEnv(api: api);
      await openAlerts(tester, env);
      expect(keyed('alert-listen-alert-1'), findsOneWidget);
      expect(keyed('alert-listen-alert-2'), findsNothing, reason: 'not urgent (and already read)');
      expect(find.descendant(of: keyed('alert-listen-alert-1'), matching: find.text('सुनें')), findsOneWidget);
      expect(
        find.descendant(of: keyed('alert-listen-alert-1'), matching: find.byIcon(AppIcons.speaker)),
        findsOneWidget,
      );
      // 50 high white button with a 2 px line inside a 56 dp tap area, as wide as the card's content.
      expect(tester.getSize(keyed('alert-listen-alert-1')).height, 56);
      final button = tester.widget<Container>(
        find.descendant(of: keyed('alert-listen-alert-1'), matching: find.byType(Container)),
      );
      expect(button.constraints!.maxHeight, 50);
      expect((button.decoration! as BoxDecoration).border!.top.width, 2);
      expectBigTouchTargets(tester);

      env.voice.clear();
      await tapKey(tester, 'alert-listen-alert-1');
      expect(env.voice.spokenTexts, [MockData.alerts().items.first.spoken.text.hi]);
      expect(keyed('alert-alert-1'), findsOneWidget, reason: 'still the list');
      expect(find.byKey(const ValueKey('alert-body')), findsNothing);
      expect(api.calls, isNot(contains('markAlertRead')));
    });

    testWidgets('"Listen" while the voice is muted turns it on again, like the speaker in the bar', (tester) async {
      final env = await alertsEnv();
      await openAlerts(tester, env);
      await containerOf(tester).read(settingsProvider.notifier).setMuted(on: true);
      await tester.pump();
      env.voice.clear();
      await tapKey(tester, 'alert-listen-alert-1');
      expect(containerOf(tester).read(settingsProvider).muted, isFalse);
      expect(env.voice.spokenTexts, [MockData.alerts().items.first.spoken.text.hi]);
    });

    testWidgets('a "result ready" (green) alert has a green-soft dot with a tick and ends in an arrow', (tester) async {
      final api = MockApiClient(latency: Duration.zero)
        ..alertItems = [
          AlertOut(
            id: 'g',
            level: Severity.green,
            title: LocalizedText.pair(en: 'Result ready: tap to see', hi: 'नतीजा आ गया'),
            body: LocalizedText.pair(en: 'Apple scab', hi: 'सेब का स्कैब'),
            createdAt: DateTime.utc(2026, 5, 1, 12),
            readAt: DateTime.utc(2026, 5, 1, 13),
            scanId: 'x',
          ),
          alert('plain', level: Severity.red, at: DateTime.utc(2026, 4, 1)),
        ];
      final env = await alertsEnv(api: api);
      await openAlerts(tester, env);
      final done = keyed('alert-g');
      final dot = tester.widget<IconDot>(find.descendant(of: done, matching: find.byType(IconDot)));
      expect((dot.background, dot.foreground), (AppColors.greenSoft, AppColors.green));
      expect(find.descendant(of: done, matching: find.byIcon(AppIcons.tick)), findsOneWidget);
      final arrow = find.descendant(of: done, matching: find.byIcon(AppIcons.chevron));
      expect(arrow, findsOneWidget);
      expect(tester.widget<Icon>(arrow).color, AppColors.chevron);
      expect(find.descendant(of: keyed('alert-plain'), matching: find.byIcon(AppIcons.chevron)), findsNothing);
      expect(keyed('alert-listen-g'), findsNothing);
      expect(
        find.descendant(of: done, matching: find.text('1 मई')),
        findsOneWidget,
        reason: 'older: the date',
      );
    });

    test('the time: today with the hour, yesterday as a word, older as the date', () {
      final resources = loadResources();
      final words = DateWords((key) => resources.t(key, 'en'));
      final now = fixedNow;
      expect(alertWhen(words, DateTime(2026, 5, 12, 7, 30), now), 'Today, 07:30');
      expect(alertWhen(words, DateTime(2026, 5, 11, 20), now), 'Yesterday');
      expect(alertWhen(words, DateTime(2026, 5, 1, 9), now), '1 May');
    });

    testWidgets('the server order does not matter: they are shown newest first', (tester) async {
      final api = MockApiClient(latency: Duration.zero)
        ..alertItems = [
          alert('old', at: DateTime.utc(2026, 5, 1, 12)),
          alert('new', at: DateTime.utc(2026, 5, 11, 12)),
          alert('undated').copyWithDate(null),
        ];
      final env = await alertsEnv(api: api);
      await openAlerts(tester, env);
      final tops = [
        for (final id in ['new', 'old', 'undated']) tester.getTopLeft(keyed('alert-$id')).dy,
      ];
      expect(tops, [...tops]..sort());
    });

    testWidgets('empty: a picture, words and alert_none', (tester) async {
      final api = MockApiClient(latency: Duration.zero)..alertItems = [];
      final env = await alertsEnv(api: api);
      await openAlerts(tester, env);
      expect(keyed('alerts-empty'), findsOneWidget);
      expect(find.text('कोई सूचना नहीं'), findsOneWidget);
      expect(find.byIcon(AppIcons.bell), findsOneWidget);
      expect(env.voice.spokenIds, ['alert_none']);
    });

    testWidgets('the top bar: back arrow, "Alerts", the mute button and the speaker', (tester) async {
      final env = await alertsEnv(language: 'en');
      await openAlerts(tester, env);
      expect(find.text('Alerts'), findsOneWidget);
      expect(find.byIcon(AppIcons.back), findsOneWidget);
      expect(keyed('mute-button'), findsOneWidget);
      expect(keyed('speaker-button'), findsOneWidget);
      // The cards start 16 dp under the bar, 16 dp from the sides, 12 dp apart.
      final bar = tester.getBottomLeft(find.byIcon(AppIcons.back)).dy;
      final card = tester.getRect(keyed('alert-alert-1'));
      expect(card.left, 16);
      expect(card.width, 360 - 32);
      expect(card.top - bar, lessThan(40));
      final second = tester.getRect(keyed('alert-alert-2'));
      expect(second.top - card.bottom, closeTo(12, 0.5));
    });

    testWidgets('a failed load shows the error screen; the retry shows the list', (tester) async {
      final api = MockApiClient(latency: Duration.zero);
      final env = await alertsEnv(api: api);
      useSmallPhone(tester);
      await pumpApp(tester, env, location: '/home');
      api.failWith(const ApiException.network(), ops: {'listAlerts'});
      env.voice.clear();
      await tapKey(tester, 'home-alerts');
      expect(keyed('retry-button'), findsOneWidget);
      expect(env.voice.spokenIds, ['error_no_internet']);
      api.clearFailure();
      await tapKey(tester, 'retry-button');
      expect(keyed('alert-alert-1'), findsOneWidget);
    });

    testWidgets('english', (tester) async {
      final env = await alertsEnv(language: 'en');
      await openAlerts(tester, env);
      expect(find.text('Rain washed your spray'), findsOneWidget);
      expect(find.text('New'), findsOneWidget);
      expect(find.text('Listen'), findsOneWidget);
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel(RegExp('Serious')), findsOneWidget);
      semantics.dispose();
    });
  });

  group('opening an alert', () {
    testWidgets('speaks its text, shows level, title and body, marks it read and the bell badge goes', (tester) async {
      final api = MockApiClient(latency: Duration.zero);
      final env = await alertsEnv(api: api);
      useSmallPhone(tester);
      await pumpApp(tester, env, location: '/home');
      expect(find.descendant(of: keyed('alert-badge'), matching: find.text('1')), findsOneWidget);
      await tapKey(tester, 'home-alerts');
      env.voice.clear();
      await tapKey(tester, 'alert-alert-1');

      expect(env.voice.spokenTexts, [MockData.alerts().items.first.spoken.text.hi]);
      // The card is tinted with the level's colour: red-soft with a thin red line, the round dot with the rain cloud, the
      // word in a white tag, the title big (26 / 800), then the whole text.
      expect(keyed('severity-red'), findsOneWidget);
      final card = tester.widget<DecoratedBox>(
        find.descendant(of: keyed('severity-red'), matching: find.byType(DecoratedBox)).first,
      );
      expect((card.decoration as BoxDecoration).color, AppColors.redSoft);
      expect((card.decoration as BoxDecoration).border!.top.color, AppColors.redLine);
      expect(find.descendant(of: keyed('severity-red'), matching: find.byIcon(AppIcons.rain)), findsOneWidget);
      expect(find.text('गंभीर'), findsOneWidget);
      expect(find.text('बारिश ने छिड़काव धो दिया'), findsOneWidget);
      final title = tester.widget<Text>(find.text('बारिश ने छिड़काव धो दिया'));
      expect((title.style!.fontSize, title.style!.fontWeight), (26, FontWeight.w800));
      expect(find.text('सूचनाएँ'), findsOneWidget, reason: 'the bar names the screen');
      expect(keyed('alert-body'), findsOneWidget);
      expect(api.calls, contains('markAlertRead'));
      expectBigTouchTargets(tester);

      // Back to the list: no longer highlighted. Back to Home: no badge.
      await tester.tap(find.byIcon(AppIcons.back));
      await tester.pumpAndSettle();
      expect(keyed('alert-new-alert-1'), findsNothing);
      await tester.tap(find.byIcon(AppIcons.back));
      await tester.pumpAndSettle();
      expect(keyed('alert-badge'), findsNothing);
    });

    testWidgets('an alert that is already read is not marked again', (tester) async {
      final api = MockApiClient(latency: Duration.zero);
      final env = await alertsEnv(api: api);
      await openAlerts(tester, env);
      await tapKey(tester, 'alert-alert-2');
      expect(api.calls, isNot(contains('markAlertRead')));
    });

    testWidgets('reading is silent when there is no internet: the alert stays unread', (tester) async {
      final api = MockApiClient(latency: Duration.zero);
      final env = await alertsEnv(api: api);
      await openAlerts(tester, env);
      api.failWith(const ApiException.network(), ops: {'markAlertRead'});
      env.voice.clear();
      await tapKey(tester, 'alert-alert-1');
      expect(env.voice.spokenTexts, hasLength(1));
      await tester.tap(find.byIcon(AppIcons.back));
      await tester.pumpAndSettle();
      expect(keyed('alert-new-alert-1'), findsOneWidget);
    });

    testWidgets('without a spoken text the body is read; a green alert has a tick and the word "fine"', (tester) async {
      final api = MockApiClient(latency: Duration.zero)
        ..alertItems = [
          AlertOut(
            id: 'g',
            level: Severity.green,
            title: LocalizedText.pair(en: 'All well', hi: 'सब ठीक'),
            body: LocalizedText.pair(en: 'Nothing to do.', hi: 'कुछ करना नहीं।'),
            createdAt: DateTime.utc(2026, 5, 11, 12),
          ),
        ];
      final env = await alertsEnv(api: api);
      await openAlerts(tester, env);
      expect(find.descendant(of: keyed('alert-g'), matching: find.byIcon(AppIcons.tick)), findsOneWidget);
      env.voice.clear();
      await tapKey(tester, 'alert-g');
      expect(env.voice.spokenTexts, ['कुछ करना नहीं।']);
      expect(keyed('severity-green'), findsOneWidget);
      expect(find.text('ठीक'), findsOneWidget);
      expect(keyed('alert-open-scan'), findsNothing);
    });

    testWidgets('the speaker button says the alert again', (tester) async {
      final env = await alertsEnv();
      await openAlerts(tester, env);
      env.voice.clear();
      await tapKey(tester, 'alert-alert-2');
      final first = List.of(env.voice.log);
      expect(first, hasLength(1));
      env.voice.clear();
      await tapKey(tester, 'speaker-button');
      expect(env.voice.log, first);
    });

    testWidgets('an alert that is not in the list leads back to the list', (tester) async {
      final env = await alertsEnv();
      useSmallPhone(tester);
      final container = await pumpApp(tester, env, location: '/home');
      unawaited(container.read(routerProvider).push<void>(Routes.alertDetailFor('no-such-alert')));
      await tester.pumpAndSettle();
      expect(keyed('alert-alert-1'), findsOneWidget);
    });

    testWidgets('a detail link without an id leads back to the list', (tester) async {
      final env = await alertsEnv();
      useSmallPhone(tester);
      final container = await pumpApp(tester, env, location: '/home');
      unawaited(container.read(routerProvider).push<void>(Routes.alertDetail));
      await tester.pumpAndSettle();
      expect(keyed('alert-alert-1'), findsOneWidget);
    });
  });

  group('an alert about a photo', () {
    testWidgets('has a big green arrow; it opens that scan\'s advice on the normal result screen', (tester) async {
      final api = MockApiClient(latency: Duration.zero);
      final env = await alertsEnv(api: api);
      await openAlerts(tester, env);
      env.voice.clear();
      await tapKey(tester, 'alert-alert-1');
      expect(keyed('alert-open-scan'), findsOneWidget);
      expect(env.voice.spokenIds, ['alert_see_scan']);
      expect(env.voice.spokenTexts, hasLength(1), reason: 'the alert text comes first, then the hint');
      expect(env.voice.log.last, 'alert_see_scan@hi');
      // The green action of the bar under the content: the green arrow and the words, 60 high, full width.
      expect(find.descendant(of: keyed('alert-open-scan'), matching: find.byIcon(AppIcons.greenArrow)), findsOneWidget);
      expect(find.descendant(of: keyed('alert-open-scan'), matching: find.text('फोटो का नतीजा')), findsOneWidget);
      expect(tester.getSize(keyed('alert-open-scan')), const Size(360 - 32, 60));
      expectBigTouchTargets(tester);

      env.voice.clear();
      await tapKey(tester, 'alert-open-scan');
      expect(api.calls, contains('getScan'));
      // The advice screen: severity band, the medicine and the "I sprayed" button.
      expect(keyed('severity-yellow'), findsOneWidget);
      expect(keyed('product-P007'), findsOneWidget);
      expect(keyed('i-sprayed'), findsOneWidget);
      expect(env.voice.spokenIds.first, 'result_intro');

      // "I sprayed" works from here: the diary knows the medicine.
      env.voice.clear();
      await tapKey(tester, 'i-sprayed');
      expect(env.voice.spokenTexts, ['डिफेनोकोनाज़ोल, Score']);
      await tapKey(tester, 'diary-save');
      expect(api.sprayLogsIn.single.adviceId, 'adv-${MockData.alertScanId}');
    });

    testWidgets('an expert case opens the expert screen', (tester) async {
      final api = MockApiClient(latency: Duration.zero)
        ..scans['x'] = MockData.needsExpertScan('x')
        ..alertItems = [alert('a', scanId: 'x')];
      final env = await alertsEnv(api: api);
      await openAlerts(tester, env);
      await tapKey(tester, 'alert-a');
      await tapKey(tester, 'alert-open-scan');
      expect(find.byIcon(AppIcons.expert), findsWidgets);
      expect(env.voice.spokenIds, contains('result_expert'));
    });

    testWidgets('a scan that has no result yet says error_try_again and stays', (tester) async {
      final api = MockApiClient(latency: Duration.zero)
        ..scans['x'] = MockData.confirmCropScan('x')
        ..alertItems = [alert('a', scanId: 'x')];
      final env = await alertsEnv(api: api);
      await openAlerts(tester, env);
      await tapKey(tester, 'alert-a');
      env.voice.clear();
      await tapKey(tester, 'alert-open-scan');
      expect(env.voice.spokenIds, ['error_try_again']);
      expect(keyed('alert-open-scan'), findsOneWidget);
    });

    testWidgets('no internet: speaks error_no_internet, keeps the alert and the button; a second try works', (
      tester,
    ) async {
      final api = MockApiClient(latency: Duration.zero);
      final env = await alertsEnv(api: api);
      await openAlerts(tester, env);
      await tapKey(tester, 'alert-alert-1');
      api.failWith(const ApiException.network(), ops: {'getScan'});
      env.voice.clear();
      await tapKey(tester, 'alert-open-scan');
      expect(env.voice.spokenIds, ['error_no_internet']);
      expect(keyed('alert-open-scan'), findsOneWidget);
      api.clearFailure();
      await tapKey(tester, 'alert-open-scan');
      expect(keyed('i-sprayed'), findsOneWidget);
    });

    testWidgets('a scan that is gone (404) says error_try_again', (tester) async {
      final api = MockApiClient(latency: Duration.zero)..alertItems = [alert('a', scanId: 'gone')];
      final env = await alertsEnv(api: api);
      await openAlerts(tester, env);
      await tapKey(tester, 'alert-a');
      env.voice.clear();
      await tapKey(tester, 'alert-open-scan');
      expect(env.voice.spokenIds, ['error_try_again']);
    });
  });

  group('refreshing', () {
    testWidgets('when the app comes back, the list and the badge load again', (tester) async {
      final api = MockApiClient(latency: Duration.zero);
      final env = await alertsEnv(api: api);
      await openAlerts(tester, env);
      expect(keyed('alert-fresh'), findsNothing);
      final before = api.calls.where((c) => c == 'listAlerts').length;
      api.alertItems = [
        alert('fresh', level: Severity.red, at: DateTime.utc(2026, 5, 12, 5)),
        ...MockData.alerts().items,
      ];
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(api.calls.where((c) => c == 'listAlerts').length, greaterThan(before));
      expect(keyed('alert-fresh'), findsOneWidget);
      await tester.tap(find.byIcon(AppIcons.back));
      await tester.pumpAndSettle();
      expect(find.descendant(of: keyed('alert-badge'), matching: find.text('2')), findsOneWidget);
    });

    testWidgets('every five minutes while Home or the list is open, and not before', (tester) async {
      final api = MockApiClient(latency: Duration.zero);
      final env = await alertsEnv(api: api);
      useSmallPhone(tester);
      await pumpApp(tester, env, location: '/home');
      int listed() => api.calls.where((c) => c == 'listAlerts').length;
      final start = listed();
      await tester.pump(const Duration(minutes: 4));
      expect(listed(), start, reason: 'not yet');
      api.alertItems = [alert('fresh'), ...MockData.alerts().items];
      await tester.pump(const Duration(minutes: 1, seconds: 1));
      await tester.pumpAndSettle();
      expect(listed(), greaterThan(start));
      expect(
        find.descendant(of: keyed('alert-badge'), matching: find.text('2')),
        findsOneWidget,
        reason: 'Home is refreshed',
      );

      // On the alert list it refreshes the list too.
      await tapKey(tester, 'home-alerts');
      expect(keyed('alert-fresh'), findsOneWidget);
      api.alertItems = [alert('fresher', at: DateTime.utc(2026, 5, 12, 9)), alert('fresh'), ...MockData.alerts().items];
      await tester.pump(const Duration(minutes: 5, seconds: 1));
      await tester.pumpAndSettle();
      expect(keyed('alert-fresher'), findsOneWidget);
    });

    testWidgets('a refresh does not speak again and does not flicker to a spinner', (tester) async {
      final env = await alertsEnv();
      await openAlerts(tester, env);
      final spoken = List.of(env.voice.log);
      await tester.pump(const Duration(minutes: 5, seconds: 1));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpAndSettle();
      expect(env.voice.log, spoken);
    });
  });

  group('layout', () {
    for (final (name, size, scale) in [
      ('320x568', const Size(320, 568), 1.0),
      ('360x640 at 1.6x text', const Size(360, 640), 1.6),
      ('320x568 at 1.6x text', const Size(320, 568), 1.6),
    ]) {
      testWidgets('list and detail fit on $name', (tester) async {
        final api = MockApiClient(latency: Duration.zero)
          ..alertItems = [
            alert('long', level: Severity.red, scanId: MockData.alertScanId).copyWithTitle(
              LocalizedText.pair(
                en: 'A title that is quite long and has to wrap over several lines',
                hi: 'एक बहुत लंबा शीर्षक जिसे कई पंक्तियों में लिखना पड़ता है ताकि पूरा दिखे',
              ),
            ),
            alert('b'),
          ];
        final env = await alertsEnv(api: api);
        await openAlerts(tester, env, textScale: scale, size: size);
        expect(tester.takeException(), isNull);
        expectBigTouchTargets(tester);
        // The card (with its Listen button) can be taller than the screen: tap its top, clear of the floating caption.
        await tester.ensureVisible(keyed('alert-long'));
        await tester.pump();
        await tester.tapAt(tester.getTopLeft(keyed('alert-long')) + const Offset(24, 8));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expectBigTouchTargets(tester);
        final arrow = tester.getRect(keyed('alert-open-scan'));
        expect(arrow.bottom, lessThanOrEqualTo(size.height));
      });
    }
  });

  group('helpers', () {
    test('newestFirst keeps the order of equal times and puts undated alerts last', () {
      final t = DateTime.utc(2026, 5, 1);
      final sorted = newestFirst([
        alert('a', at: t),
        alert('b', at: t),
        alert('c', at: t.add(const Duration(hours: 1))),
        alert('d').copyWithDate(null),
      ]);
      expect([for (final a in sorted) a.id], ['c', 'a', 'b', 'd']);
    });

    testWidgets('alerts of one farmer are not shown to the next one who logs in', (tester) async {
      final api = MockApiClient(latency: Duration.zero);
      final env = await alertsEnv(api: api);
      final container = await pumpApp(tester, env, location: '/home');
      expect((await container.read(alertsProvider.future)).items, hasLength(2));
      await container.read(sessionProvider.notifier).logout();
      await tester.pumpAndSettle();
      await container.read(sessionProvider.notifier).login(MockData.tokens(2));
      api.alertItems = [alert('mine')];
      container.read(alertsProvider);
      expect((await container.read(alertsProvider.future)).items.single.id, 'mine');
    });
  });
}

extension on AlertOut {
  AlertOut copyWithDate(DateTime? at) => AlertOut(
    id: id,
    kind: kind,
    level: level,
    title: title,
    body: body,
    spoken: spoken,
    createdAt: at,
    readAt: readAt,
    scanId: scanId,
  );

  AlertOut copyWithTitle(LocalizedText newTitle) => AlertOut(
    id: id,
    kind: kind,
    level: level,
    title: newTitle,
    body: body,
    spoken: spoken,
    createdAt: createdAt,
    readAt: readAt,
    scanId: scanId,
  );
}
