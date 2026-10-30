import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmtrack/core/models/models.dart';
import 'package:farmtrack/core/network/mock_api_client.dart';
import 'package:farmtrack/core/theme/app_theme.dart';
import 'package:farmtrack/features/diary/date_words.dart';
import 'package:farmtrack/features/diary/diary_providers.dart';
import 'package:farmtrack/features/diary/diary_timeline.dart';

import 'support/feature_fakes.dart';
import 'support/finders.dart';
import 'support/harness.dart';

/// The diary page of the owner's choice (design 2 of `docs/design/diary-combined-proposals.html`): the crop circles, this week with
/// the month on a sheet, and the timeline with a thread. The phone's day is 12 May 2026 (a Tuesday).

DateTime may(int day) => DateTime.utc(2026, 5, day, 12);

typedef LogSpec = ({String name, String crop, DateTime at});

LogSpec log(String name, String crop, DateTime at) => (name: name, crop: crop, at: at);

/// log-1 .. log-5 in this order (the mock server numbers them so).
final _logs = [
  log('Score', 'apple', may(12)),
  log('Mancozeb', 'tomato', may(12)),
  log('Score', 'apple', may(11)),
  log('Miravis Duo', 'apple', may(8)),
  log('Score', 'tomato', DateTime.utc(2026, 4, 20, 12)),
];

Future<TestEnv> _env({String language = 'en', List<LogSpec>? logs}) async {
  final mock = MockApiClient(latency: Duration.zero);
  for (final l in logs ?? _logs) {
    await mock.createSprayLog(SprayLogIn(cropId: l.crop, freeText: l.name, sprayedAt: l.at));
  }
  return TestEnv.create(
    loggedIn: true,
    language: language,
    api: mock,
    extraOverrides: [clockProvider.overrideWithValue(() => fixedNow)],
  );
}

Future<void> _open(WidgetTester tester, TestEnv env, {Size size = const Size(360, 640), double textScale = 1.0}) async {
  useSmallPhone(tester, textScale: textScale, size: size);
  await pumpApp(tester, env, location: '/home');
  env.voice.clear();
  await tapKey(tester, 'home-diary');
}

String _text(String key) => (find.byKey(ValueKey(key)).evaluate().single.widget as Text).data!;

/// How many dots a day of the strip (or of the month) shows.
int _dots(WidgetTester tester, String key) =>
    find.descendant(of: keyed(key), matching: find.byType(DecoratedBox)).evaluate().length;

double _top(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

void main() {
  group('the helpers', () {
    test('the crops of the entries: lower case, the one sprayed last first, no repeats, no empty one', () {
      final entries = [
        DiaryEntry(id: '1', cropId: 'Tomato', name: 'a', date: may(12)),
        DiaryEntry(id: '2', cropId: 'Apple', name: 'b', date: may(11)),
        DiaryEntry(id: '3', cropId: 'tomato', name: 'c', date: may(10)),
        DiaryEntry(id: '4', cropId: '', name: 'd', date: may(9)),
      ];
      expect(diaryCrops(entries), ['tomato', 'apple']);
      expect(diaryCrops(const []), isEmpty);
    });

    test('sprays per day, whatever the time of day', () {
      final entries = [
        DiaryEntry(id: '1', cropId: 'apple', name: 'a', date: DateTime.utc(2026, 5, 12, 6)),
        DiaryEntry(id: '2', cropId: 'apple', name: 'b', date: DateTime.utc(2026, 5, 12, 9)),
        DiaryEntry(id: '3', cropId: 'apple', name: 'c', date: may(11)),
      ];
      final counts = diarySprayCounts(entries);
      expect(counts[dayOnly(may(12))], 2);
      expect(counts[dayOnly(may(11))], 1);
      expect(counts[dayOnly(may(10))], isNull);
    });
  });

  group('the crop circles', () {
    testWidgets('one crop only: no circles to choose from', (tester) async {
      final env = await _env(logs: [log('Score', 'apple', may(12)), log('Mancozeb', 'apple', may(11))]);
      await _open(tester, env);
      expect(keyed('diary-crop-all'), findsNothing);
      expect(keyed('diary-week'), findsOneWidget);
    });

    testWidgets('two crops: All and a circle for each; a touch shows only that crop and says its name', (tester) async {
      final env = await _env();
      await _open(tester, env);
      expect(keyed('diary-crop-all'), findsOneWidget);
      expect(keyed('diary-crop-apple'), findsOneWidget);
      expect(keyed('diary-crop-tomato'), findsOneWidget);
      expect(find.descendant(of: keyed('diary-crop-apple'), matching: find.text('Apple')), findsOneWidget);
      expect(find.descendant(of: keyed('diary-crop-tomato'), matching: find.text('Tomato')), findsOneWidget);
      expect(find.descendant(of: keyed('diary-crop-all'), matching: find.text('All')), findsOneWidget);
      // The circles are in the order the crops were sprayed last: both on 12 May, the server's order decides.
      expect(_dots(tester, 'diary-week-dots-12'), 2, reason: 'an apple and a tomato spray today');

      env.voice.clear();
      await tapKey(tester, 'diary-crop-tomato');
      expect(env.voice.spokenTexts, ['Tomato']);
      expect(keyed('diary-entry-log-2'), findsOneWidget, reason: 'the tomato spray of today');
      expect(keyed('diary-entry-log-1'), findsNothing, reason: 'the apple sprays are not shown');
      expect(keyed('diary-entry-log-3'), findsNothing);
      expect(_dots(tester, 'diary-week-dots-12'), 1, reason: 'the week shows the chosen crop only');
      expect(_dots(tester, 'diary-week-dots-11'), 0);

      env.voice.clear();
      await tapKey(tester, 'diary-crop-all');
      expect(env.voice.spokenTexts, ['All crops']);
      expect(keyed('diary-entry-log-1'), findsOneWidget);
      expect(_dots(tester, 'diary-week-dots-11'), 1);
      expectBigTouchTargets(tester);
    });

    testWidgets('the crop circles are in Hindi too', (tester) async {
      final env = await _env(language: 'hi');
      await _open(tester, env);
      expect(find.descendant(of: keyed('diary-crop-all'), matching: find.text('सब')), findsOneWidget);
      expect(find.descendant(of: keyed('diary-crop-apple'), matching: find.text('सेब')), findsOneWidget);
      env.voice.clear();
      await tapKey(tester, 'diary-crop-apple');
      expect(env.voice.spokenTexts, ['सेब']);
      expect(env.voice.spokenTexts.single, isNot(matches(RegExp(r'\d'))));
    });
  });

  group('this week', () {
    testWidgets('the last seven days, today last, a dot for each spray', (tester) async {
      final env = await _env();
      await _open(tester, env);
      expect(find.text('This week'), findsOneWidget);
      expect(find.text('Month'), findsOneWidget);
      final days = [for (var d = 6; d <= 12; d++) d];
      for (final d in days) {
        expect(keyed('diary-week-day-$d'), findsOneWidget, reason: 'day $d');
      }
      final lefts = [for (final d in days) tester.getTopLeft(keyed('diary-week-day-$d')).dx];
      expect(lefts, [...lefts]..sort(), reason: 'the oldest day first, today at the right');
      expect(find.descendant(of: keyed('diary-week-day-12'), matching: find.text('Tue')), findsOneWidget);
      expect(find.descendant(of: keyed('diary-week-day-8'), matching: find.text('Fri')), findsOneWidget);
      expect(_dots(tester, 'diary-week-dots-12'), 2, reason: 'two sprays today');
      expect(_dots(tester, 'diary-week-dots-11'), 1);
      expect(_dots(tester, 'diary-week-dots-8'), 1);
      expect(_dots(tester, 'diary-week-dots-9'), 0, reason: 'nothing on the 9th');
    });

    testWidgets('the whole card is a button that opens the month', (tester) async {
      final env = await _env();
      await _open(tester, env);
      expect(keyed('diary-month-sheet'), findsNothing);
      await tapKey(tester, 'diary-week');
      expect(keyed('diary-month-sheet'), findsOneWidget);
      expect(_text('diary-month-title'), 'May 2026');
      expectBigTouchTargets(tester);
    });
  });

  group('the month', () {
    testWidgets('the counters of the month and a dot on every day sprayed', (tester) async {
      final env = await _env();
      await _open(tester, env);
      await tapKey(tester, 'diary-week');
      expect(find.text('Sprays: 4'), findsOneWidget, reason: 'four sprays in May');
      expect(find.text('Crops: 2'), findsOneWidget);
      expect(find.text('Last: Today'), findsOneWidget);
      for (var d = 1; d <= 31; d++) {
        expect(keyed('diary-month-day-2026-5-$d'), findsOneWidget, reason: 'May $d');
      }
      expect(_dots(tester, 'diary-month-dots-12'), 2);
      expect(_dots(tester, 'diary-month-dots-11'), 1);
      expect(_dots(tester, 'diary-month-dots-8'), 1);
      expect(_dots(tester, 'diary-month-dots-13'), 0);
      // 1 May 2026 is a Friday: four blank cells before it (Monday first), so the 1st sits in the fifth column.
      final first = tester.getTopLeft(keyed('diary-month-day-2026-5-1')).dx;
      final monday4 = tester.getTopLeft(keyed('diary-month-day-2026-5-4')).dx;
      expect(first, greaterThan(monday4), reason: 'Friday is right of Monday');
    });

    testWidgets('earlier months with the arrows, as far back as the first spray; never past this month', (
      tester,
    ) async {
      final env = await _env();
      await _open(tester, env);
      await tapKey(tester, 'diary-week');
      // May is the newest month: no way on; April has the oldest spray: one way back.
      await tapKey(tester, 'diary-month-next');
      expect(_text('diary-month-title'), 'May 2026');
      await tapKey(tester, 'diary-month-prev');
      expect(_text('diary-month-title'), 'April 2026');
      expect(find.text('Sprays: 1'), findsOneWidget);
      expect(find.text('Crops: 1'), findsOneWidget);
      expect(find.text('Last: Today'), findsOneWidget, reason: 'the last spray of all, not of the month');
      expect(keyed('diary-month-dots-20'), findsOneWidget);
      await tapKey(tester, 'diary-month-prev');
      expect(_text('diary-month-title'), 'April 2026', reason: 'nothing is written before April');
      await tapKey(tester, 'diary-month-next');
      expect(_text('diary-month-title'), 'May 2026');
      expectBigTouchTargets(tester);
    });

    testWidgets('a month without sprays says so', (tester) async {
      final env = await _env(
        logs: [log('Score', 'apple', may(12)), log('Score', 'apple', DateTime.utc(2026, 3, 3, 12))],
      );
      await _open(tester, env);
      await tapKey(tester, 'diary-week');
      await tapKey(tester, 'diary-month-prev');
      expect(_text('diary-month-title'), 'April 2026');
      expect(find.text('No sprays this month'), findsOneWidget);
      expect(find.text('Sprays: 0'), findsNothing);
    });

    testWidgets('the speaker says the count in words, never digits; "Done" closes the sheet', (tester) async {
      final env = await _env();
      await _open(tester, env);
      await tapKey(tester, 'diary-week');
      env.voice.clear();
      await tapKey(tester, 'diary-month-speak');
      expect(env.voice.spokenTexts, ['You sprayed four times in May.']);
      await tapKey(tester, 'diary-month-prev');
      env.voice.clear();
      await tapKey(tester, 'diary-month-speak');
      expect(env.voice.spokenTexts, ['You sprayed one time in April.']);
      expect(env.voice.spokenTexts.single, isNot(matches(RegExp(r'\d'))));
      await tapKey(tester, 'diary-month-done');
      expect(keyed('diary-month-sheet'), findsNothing);
    });

    testWidgets('in Hindi: the month, the counters and the voice', (tester) async {
      final env = await _env(language: 'hi');
      await _open(tester, env);
      await tapKey(tester, 'diary-week');
      expect(_text('diary-month-title'), 'मई 2026');
      expect(find.text('छिड़काव: 4'), findsOneWidget);
      expect(find.text('फसलें: 2'), findsOneWidget);
      env.voice.clear();
      await tapKey(tester, 'diary-month-speak');
      expect(env.voice.spokenTexts, ['मई में आपने चार बार छिड़काव किया।']);
      expect(env.voice.spokenTexts.single, isNot(matches(RegExp(r'\d'))));
    });
  });

  group('the timeline', () {
    testWidgets('a big circle and a heading for each day, newest first, with the cards under them', (tester) async {
      final env = await _env();
      await _open(tester, env);
      // Today and yesterday are called so, with their weekday beside; an older day has its weekday and its date.
      Finder inDay(String day, String text) =>
          find.descendant(of: keyed('diary-day-2026-5-$day'), matching: find.text(text));
      final heads = [
        (inDay('12', 'Today'), inDay('12', 'Tuesday')),
        (inDay('11', 'Yesterday'), inDay('11', 'Monday')),
        (inDay('8', 'Friday'), inDay('8', '8 May')),
      ];
      for (final (headline, rest) in heads) {
        expect(headline, findsOneWidget);
        expect(rest, findsOneWidget);
      }
      final tops = [for (final (headline, _) in heads) _top(tester, headline)];
      expect(tops, [...tops]..sort(), reason: 'newest day first');
      for (final (id, day) in [('log-1', 12), ('log-2', 12), ('log-3', 11), ('log-4', 8)]) {
        final card = _top(tester, keyed('diary-entry-$id'));
        final node = _top(tester, keyed('diary-node-2026-5-$day'));
        expect(card, greaterThan(node), reason: '$id is under the circle of the $day');
      }
      expect(_top(tester, keyed('diary-entry-log-3')), greaterThan(_top(tester, keyed('diary-entry-log-1'))));
      // The circles carry the day number; today's is solid green, the others are white with a green line.
      for (final (day, number) in [(12, '12'), (11, '11'), (8, '8')]) {
        expect(find.descendant(of: keyed('diary-node-2026-5-$day'), matching: find.text(number)), findsOneWidget);
      }
      Color fill(int day) =>
          ((tester.widget<Container>(keyed('diary-node-2026-5-$day'))).decoration! as BoxDecoration).color!;
      expect(fill(12), AppColors.green);
      expect(fill(11), Colors.white);
      expect(fill(8), Colors.white);
      // Both sprays of the 12th are under one circle.
      expect(find.byKey(const ValueKey('diary-node-2026-5-12')), findsOneWidget);
    });

    testWidgets('in Hindi the headings are words', (tester) async {
      final env = await _env(language: 'hi');
      await _open(tester, env);
      Finder inDay(String day, String text) =>
          find.descendant(of: keyed('diary-day-2026-5-$day'), matching: find.text(text));
      expect(inDay('12', 'आज'), findsOneWidget);
      expect(inDay('12', 'मंगलवार'), findsOneWidget);
      expect(inDay('11', 'बीता कल'), findsOneWidget);
      expect(inDay('11', 'सोमवार'), findsOneWidget);
      expect(inDay('8', 'शुक्रवार'), findsOneWidget);
      expect(inDay('8', '8 मई'), findsOneWidget);
    });

    testWidgets('a waiting entry has the grey tag and no "saved"', (tester) async {
      final env = await _env(logs: [log('Score', 'apple', may(11))]);
      await _open(tester, env);
      expect(find.text('saved'), findsOneWidget);
      final container = ProviderScope.containerOf(tester.element(keyed('diary-week')));
      container
          .read(pendingSpraysProvider.notifier)
          .add(
            PendingSpray(
              key: 'k1',
              log: SprayLogIn(cropId: 'apple', sprayedAt: may(12)),
              name: 'Mancozeb',
            ),
          );
      await tester.pumpAndSettle();
      final entry = keyed('diary-entry-k1');
      expect(find.descendant(of: entry, matching: find.text('Waiting')), findsOneWidget);
      expect(find.descendant(of: entry, matching: find.text('saved')), findsNothing);
      expect(find.descendant(of: entry, matching: find.byIcon(AppIcons.tickBold)), findsNothing);
    });
  });

  group('layout', () {
    for (final (name, size, scale) in [
      ('320x568 at 2.0x text', const Size(320, 568), 2.0),
      ('320x568', const Size(320, 568), 1.0),
      ('360x640 at 1.6x text', const Size(360, 640), 1.6),
      ('411x900', const Size(411, 900), 1.0),
    ]) {
      for (final language in ['en', 'hi']) {
        testWidgets('the page and the month sheet fit on $name in $language', (tester) async {
          final env = await _env(language: language);
          await _open(tester, env, size: size, textScale: scale);
          expect(tester.takeException(), isNull);
          expect(keyed('diary-add'), findsOneWidget);
          expectBigTouchTargets(tester);
          await tapKey(tester, 'diary-week');
          expect(tester.takeException(), isNull);
          expect(keyed('diary-month-sheet'), findsOneWidget);
          expectBigTouchTargets(tester);
          await tapKey(tester, 'diary-month-prev');
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
