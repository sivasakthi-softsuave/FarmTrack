import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmtrack/core/errors/api_exception.dart';
import 'package:farmtrack/core/models/models.dart';
import 'package:farmtrack/core/network/mock_api_client.dart';
import 'package:farmtrack/core/offline/offline_queue.dart';
import 'package:farmtrack/features/diary/date_words.dart';
import 'package:farmtrack/features/diary/diary_providers.dart';
import 'package:farmtrack/features/diary/diary_widgets.dart' show CropDot, splitMedicineName;
import 'package:farmtrack/core/theme/app_theme.dart';

import 'support/feature_fakes.dart';
import 'support/finders.dart';
import 'support/harness.dart';

/// Noon UTC on a day of May 2026: the same calendar day in every time zone from -11 to +11.
DateTime may(int day) => DateTime.utc(2026, 5, day, 12);

Future<TestEnv> listEnv({
  MockApiClient? api,
  FakeOfflineQueue? queue,
  String language = 'hi',
  List<({String name, int day})> logs = const [],
}) async {
  final mock = api ?? MockApiClient(latency: Duration.zero);
  for (final log in logs) {
    await mock.createSprayLog(SprayLogIn(cropId: 'apple', freeText: log.name, sprayedAt: may(log.day)));
  }
  return TestEnv.create(
    loggedIn: true,
    language: language,
    api: mock,
    extraOverrides: [
      clockProvider.overrideWithValue(() => fixedNow),
      if (queue != null) offlineQueueProvider.overrideWithValue(queue),
    ],
  );
}

Future<void> openList(WidgetTester tester, TestEnv env, {double textScale = 1.0, Size? size}) async {
  useSmallPhone(tester, textScale: textScale, size: size ?? const Size(360, 640));
  await pumpApp(tester, env, location: '/home');
  env.voice.clear();
  await tapKey(tester, 'home-diary');
}

void main() {
  group('the diary list', () {
    testWidgets('empty: says so with a picture, speaks intro then diary_empty, and has the plus button', (
      tester,
    ) async {
      final env = await listEnv();
      await openList(tester, env);
      expect(keyed('diary-empty'), findsOneWidget);
      // The notebook picture of the empty page, and the Diary picture of the bottom bar.
      expect(find.byIcon(AppIcons.notebook), findsNWidgets(2));
      expect(keyed('diary-add'), findsOneWidget);
      expect(env.voice.spokenIds, ['diary_intro', 'diary_empty']);
      expect(env.voice.unknownIds, isEmpty);
      expectBigTouchTargets(tester);
    });

    testWidgets('newest first, a heading per day, the medicine, its crop and the warnings inside the entry', (
      tester,
    ) async {
      final env = await listEnv(
        logs: [
          (name: 'Score', day: 3),
          (name: 'Mancozeb', day: 12),
          (name: 'Miravis Duo', day: 7),
          (name: 'Antracol', day: 9),
        ],
      );
      await openList(tester, env);

      expect(env.voice.spokenIds, ['diary_intro', 'diary_add_hint']);
      final order = ['log-2', 'log-4', 'log-3', 'log-1'];
      final tops = [for (final id in order) tester.getTopLeft(keyed('diary-entry-$id')).dy];
      expect(tops, [...tops]..sort(), reason: 'newest day first: 12, 9, 7, 3 May');

      // One small heading per day: "Today" for today's, the day itself for the others (always above its entry).
      final headings = ['आज', '9 मई', '7 मई', '3 मई'];
      for (final (i, heading) in headings.indexed) {
        expect(find.text(heading), findsOneWidget, reason: heading);
        expect(tester.getTopLeft(find.text(heading)).dy, lessThan(tops[i]), reason: 'heading $heading');
      }

      // The entry: the crop's round picture, the medicine, and the crop in its words under it.
      final today = keyed('diary-entry-log-2');
      expect(find.descendant(of: today, matching: find.text('Mancozeb')), findsOneWidget);
      expect(find.descendant(of: today, matching: find.text('सेब')), findsOneWidget);
      expect(find.descendant(of: today, matching: find.byType(CropDot)), findsOneWidget);
      // Saved entries carry the green tick and the word "saved".
      expect(find.descendant(of: today, matching: find.byIcon(AppIcons.tickBold)), findsOneWidget);
      expect(find.descendant(of: today, matching: find.text('लिखा गया')), findsOneWidget);
      expect(
        find.descendant(of: today, matching: find.byIcon(AppIcons.speaker)),
        findsOneWidget,
        reason: 'a speaker on every card',
      );

      // The warnings are on the card without opening it: each a picture and the warning's words, never colour only.
      expect(find.descendant(of: today, matching: find.byIcon(AppIcons.warning)), findsOneWidget);
      expect(find.descendant(of: today, matching: find.textContaining('जल्द रोक लग सकती है')), findsOneWidget);
      final red = keyed('diary-entry-log-3');
      expect(find.descendant(of: red, matching: find.byIcon(AppIcons.danger)), findsOneWidget);
      expect(find.descendant(of: red, matching: find.textContaining('मंज़ूर नहीं है')), findsOneWidget);
      // Antracol is not in the mock catalogue: "not recognised" is a warning too. Score is fine: no warning, nothing to open.
      expect(find.descendant(of: keyed('diary-entry-log-4'), matching: find.byIcon(AppIcons.warning)), findsOneWidget);
      expect(find.descendant(of: keyed('diary-entry-log-1'), matching: find.byIcon(AppIcons.warning)), findsNothing);
      expect(find.descendant(of: keyed('diary-entry-log-1'), matching: find.byIcon(AppIcons.down)), findsNothing);
      expectBigTouchTargets(tester);
    });

    testWidgets('entries of one day share one heading', (tester) async {
      final env = await listEnv(
        logs: [(name: 'Score', day: 12), (name: 'Mancozeb', day: 12), (name: 'Antracol', day: 9)],
      );
      await openList(tester, env);
      expect(find.text('आज'), findsOneWidget);
      expect(find.text('9 मई'), findsOneWidget);
      final today = tester.getTopLeft(find.text('आज')).dy;
      final older = tester.getTopLeft(find.text('9 मई')).dy;
      for (final id in ['log-1', 'log-2']) {
        final top = tester.getTopLeft(keyed('diary-entry-$id')).dy;
        expect(top, allOf(greaterThan(today), lessThan(older)), reason: '$id sits under "Today", above "9 May"');
      }
    });

    testWidgets('an entry from an advice shows only the medicine and the crop; a tap opens how to use it', (
      tester,
    ) async {
      final api = MockApiClient(latency: Duration.zero);
      await api.createSprayLog(SprayLogIn(cropId: 'apple', adviceId: 'adv-1', sprayedAt: may(11)));
      final env = await listEnv(api: api, language: 'en');
      await openList(tester, env);
      final entry = keyed('diary-entry-log-1');
      expect(find.descendant(of: entry, matching: find.text('Difenoconazole')), findsOneWidget);
      expect(find.descendant(of: entry, matching: find.text('Apple')), findsOneWidget);
      // Closed: the small tags (the kind, the dose, the days to wait), not the brand or the steps.
      expect(find.descendant(of: entry, matching: find.text('Fungicide')), findsOneWidget);
      expect(find.descendant(of: entry, matching: find.text('30 ml in 200 L')), findsOneWidget);
      expect(find.descendant(of: entry, matching: find.text('Wait 14 days')), findsOneWidget);
      expect(find.descendant(of: entry, matching: find.textContaining('Score')), findsNothing);
      expect(find.textContaining('Take 30'), findsNothing);
      expect(
        find.descendant(of: entry, matching: find.byIcon(AppIcons.down)),
        findsOneWidget,
        reason: 'it can be opened',
      );

      env.voice.clear();
      await tapKey(tester, 'diary-entry-log-1');
      expect(find.descendant(of: entry, matching: find.byIcon(AppIcons.up)), findsOneWidget);
      expect(
        find.descendant(of: entry, matching: find.text('Score · 25 EC')),
        findsOneWidget,
        reason: 'brand and kind',
      );
      expect(find.text('Take 30 ml of Difenoconazole.'), findsOneWidget);
      expect(find.text('Mix it in 200 litres of water.'), findsOneWidget);
      expect(env.voice.spokenTexts, isNotEmpty, reason: 'opening an entry says it');
      expectBigTouchTargets(tester);

      env.voice.clear();
      await tapKey(tester, 'diary-speak-log-1');
      expect(env.voice.spokenTexts, hasLength(1), reason: 'the speaker inside says it again');

      await tapKey(tester, 'diary-entry-log-1');
      expect(find.text('Take 30 ml of Difenoconazole.'), findsNothing, reason: 'a second tap closes it');
    });

    test('a medicine written "Name (Brand)" is split; anything else stays whole', () {
      expect(splitMedicineName('Difenoconazole (Score)'), (name: 'Difenoconazole', brand: 'Score'));
      expect(splitMedicineName('Mancozeb 75 WP'), (name: 'Mancozeb 75 WP', brand: ''));
      expect(splitMedicineName(' Mancozeb '), (name: 'Mancozeb', brand: ''));
    });

    testWidgets('the diary is a main page: no back arrow, the floating button above the bottom bar', (tester) async {
      final env = await listEnv(logs: [(name: 'Score', day: 12)]);
      await openList(tester, env);
      expect(find.byIcon(AppIcons.back), findsNothing);
      expect(keyed('voice-button'), findsOneWidget);
      final button = tester.getRect(keyed('diary-add'));
      expect(button.height, 60, reason: 'the mockup\'s 60 high button');
      expect(find.descendant(of: keyed('diary-add'), matching: find.byIcon(AppIcons.plus)), findsOneWidget);
      expect(button.right, 360 - 16, reason: 'bottom right, in the 16 dp gutter');
      expect(button.bottom, lessThan(640 - 80), reason: 'above the 80 high bottom bar');
      // The camera circle rises above the bar: the button must clear it (it used to sit on top of it).
      final camera = tester.getRect(keyed('nav-scan'));
      expect(button.overlaps(camera), isFalse, reason: 'the button does not cover the camera circle');
      expect(button.bottom, lessThanOrEqualTo(camera.top), reason: 'it is above the circle');
    });

    testWidgets('tapping an entry says the medicine and the day in words, then its warnings', (tester) async {
      final env = await listEnv(logs: [(name: 'Mancozeb', day: 7)]);
      await openList(tester, env);
      env.voice.clear();
      await tapKey(tester, 'diary-entry-log-1');
      expect(env.voice.spokenTexts.first, 'Mancozeb, सात मई');
      expect(env.voice.spokenTexts.first, isNot(matches(RegExp(r'\d'))));
      expect(env.voice.spokenIds, ['diary_warning']);
      expect(env.voice.spokenTexts.last, contains('जल्द रोक लग सकती है'));
    });

    testWidgets('the speaker button says the intro again', (tester) async {
      final env = await listEnv(logs: [(name: 'Score', day: 12)]);
      await openList(tester, env);
      final first = List.of(env.voice.log);
      await replayVoice(tester);
      expect(env.voice.log, [...first, ...first]);
    });

    testWidgets('english', (tester) async {
      final env = await listEnv(language: 'en', logs: [(name: 'Score', day: 11)]);
      await openList(tester, env);
      expect(find.text('Yesterday'), findsOneWidget, reason: 'the day heading, with its weekday beside it');
      expect(find.text('Monday'), findsOneWidget);
      expect(find.text('saved'), findsOneWidget);
      expect(find.descendant(of: keyed('diary-entry-log-1'), matching: find.text('Score')), findsOneWidget);
      expect(find.descendant(of: keyed('diary-entry-log-1'), matching: find.text('Apple')), findsOneWidget);
      env.voice.clear();
      await tapKey(tester, 'diary-entry-log-1');
      expect(env.voice.spokenTexts, ['Score, eleven May']);
    });

    testWidgets('the plus button opens "write a spray" and says the crop prompt', (tester) async {
      final env = await listEnv();
      await openList(tester, env);
      env.voice.clear();
      await tapKey(tester, 'diary-add');
      expect(env.voice.spokenIds, ['diary_pick_crop']);
      expect(keyed('crop-apple'), findsOneWidget);
    });

    testWidgets('a failed load shows the error screen with a retry; the retry shows the list', (tester) async {
      final api = MockApiClient(latency: Duration.zero);
      final env = await listEnv(api: api, logs: [(name: 'Score', day: 11)]);
      useSmallPhone(tester);
      await pumpApp(tester, env, location: '/home');
      api.failWith(const ApiException.network(), ops: {'listSprayLogs'});
      env.voice.clear();
      await tapKey(tester, 'home-diary');
      expect(keyed('retry-button'), findsOneWidget);
      expect(env.voice.spokenIds, ['error_no_internet']);
      api.clearFailure();
      await tapKey(tester, 'retry-button');
      expect(keyed('diary-entry-log-1'), findsOneWidget);
    });

    testWidgets('a server error says error_try_again', (tester) async {
      final api = MockApiClient(latency: Duration.zero);
      final env = await listEnv(api: api);
      useSmallPhone(tester);
      await pumpApp(tester, env, location: '/home');
      api.failWith(
        const ApiException(kind: ApiErrorKind.server, code: 'x', statusCode: 500),
        ops: {'listSprayLogs'},
      );
      env.voice.clear();
      await tapKey(tester, 'home-diary');
      expect(env.voice.spokenIds, ['error_try_again']);
    });
  });

  group('entries waiting for the internet', () {
    testWidgets('are listed with a "waiting" mark even when the list cannot be loaded', (tester) async {
      final api = MockApiClient(latency: Duration.zero);
      final queue = FakeOfflineQueue();
      final env = await listEnv(api: api, queue: queue);
      useSmallPhone(tester);
      final container = await pumpApp(tester, env, location: '/home');
      container
          .read(pendingSpraysProvider.notifier)
          .add(
            PendingSpray(
              key: 'k1',
              log: SprayLogIn(cropId: 'apple', sprayedAt: may(11)),
              name: 'Score',
            ),
          );
      api.failWith(const ApiException.network(), ops: {'listSprayLogs'});
      env.voice.clear();
      await tapKey(tester, 'home-diary');

      final entry = keyed('diary-entry-k1');
      expect(entry, findsOneWidget);
      // The grey "Waiting" pill with its clock, instead of the green tick.
      expect(find.descendant(of: entry, matching: find.text('इंतज़ार में')), findsOneWidget);
      expect(find.descendant(of: entry, matching: find.byIcon(AppIcons.clock)), findsOneWidget);
      expect(find.descendant(of: entry, matching: find.byIcon(AppIcons.tickBold)), findsNothing);
      expect(keyed('diary-offline'), findsOneWidget);
      expect(env.voice.spokenIds, ['diary_intro', 'error_no_internet']);
      env.voice.clear();
      await tapKey(tester, 'diary-entry-k1');
      expect(env.voice.spokenIds, ['diary_waiting']);
    });

    testWidgets('when the queue sends one, the mark goes, the server entry shows and diary_sent is spoken', (
      tester,
    ) async {
      final api = MockApiClient(latency: Duration.zero);
      final queue = FakeOfflineQueue();
      final env = await listEnv(api: api, queue: queue);
      useSmallPhone(tester);
      final container = await pumpApp(tester, env, location: '/home');
      final log = SprayLogIn(cropId: 'apple', freeText: 'Score', sprayedAt: may(11));
      container.read(pendingSpraysProvider.notifier).add(PendingSpray(key: 'k1', log: log, name: 'Score'));
      await tapKey(tester, 'home-diary');
      expect(keyed('diary-entry-k1'), findsOneWidget);
      env.voice.clear();

      // The queue sends it: the server now has it.
      final saved = await api.createSprayLog(log);
      queue.emitSent('k1', answer: saved);
      await tester.pumpAndSettle();

      expect(keyed('diary-entry-k1'), findsNothing);
      expect(keyed('diary-entry-${saved.id}'), findsOneWidget);
      expect(find.text('इंतज़ार में'), findsNothing);
      expect(env.voice.spokenIds, ['diary_sent']);
    });

    testWidgets('an entry the server refused leaves the list; the app tells the farmer once (offline status)', (
      tester,
    ) async {
      final queue = FakeOfflineQueue();
      final env = await listEnv(queue: queue);
      useSmallPhone(tester);
      final container = await pumpApp(tester, env, location: '/home');
      container
          .read(pendingSpraysProvider.notifier)
          .add(
            PendingSpray(
              key: 'k1',
              log: SprayLogIn(cropId: 'apple', sprayedAt: may(11)),
              name: 'Score',
            ),
          );
      await tapKey(tester, 'home-diary');
      env.voice.clear();
      queue.emitDropped('k1');
      await tester.pumpAndSettle();
      expect(keyed('diary-entry-k1'), findsNothing);
      // `error_try_again` comes from the app-wide offline handler; the diary only says `diary_sent` for sent entries.
      expect(env.voice.spokenIds, ['error_try_again']);
    });

    testWidgets('events of other queue items are ignored', (tester) async {
      final queue = FakeOfflineQueue();
      final env = await listEnv(queue: queue);
      useSmallPhone(tester);
      final container = await pumpApp(tester, env, location: '/home');
      container
          .read(pendingSpraysProvider.notifier)
          .add(
            PendingSpray(
              key: 'k1',
              log: SprayLogIn(cropId: 'apple', sprayedAt: may(11)),
              name: 'Score',
            ),
          );
      queue.emitSent('some-photo-key');
      await tester.pump();
      expect(container.read(pendingSpraysProvider).items, hasLength(1));
      expect(container.read(pendingSpraysProvider).sent, 0);
    });
  });

  group('layout', () {
    for (final (name, size, scale) in [
      ('320x568', const Size(320, 568), 1.0),
      ('360x640 at 1.6x text', const Size(360, 640), 1.6),
    ]) {
      testWidgets('the list does not overflow on $name', (tester) async {
        final env = await listEnv(
          logs: [
            (name: 'A medicine with a very long name that has to wrap onto several lines of the card', day: 12),
            (name: 'Mancozeb', day: 11),
            (name: 'Miravis Duo', day: 10),
          ],
        );
        await openList(tester, env, textScale: scale, size: size);
        expect(tester.takeException(), isNull);
        expect(keyed('diary-add'), findsOneWidget);
        expectBigTouchTargets(tester);
      });
    }

    testWidgets('the empty diary does not overflow on 320x568 at 1.6x text', (tester) async {
      final env = await listEnv();
      await openList(tester, env, textScale: 1.6, size: const Size(320, 568));
      expect(tester.takeException(), isNull);
    });
  });
}
