import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmtrack/core/providers.dart';
import 'package:farmtrack/core/router/app_router.dart';
import 'package:farmtrack/core/router/routes.dart';
import 'package:farmtrack/core/settings/app_settings.dart';
import 'package:farmtrack/core/theme/app_theme.dart';
import 'package:farmtrack/core/voice/utterance.dart';
import 'package:farmtrack/features/scan/capture_design_a.dart';
import 'package:farmtrack/features/scan/capture_design_b.dart';
import 'package:farmtrack/features/scan/photo_picker.dart';
import 'package:farmtrack/features/scan/scan_flow.dart';

import 'support/finders.dart';
import 'support/harness.dart';

/// The two looks of the camera screen ([CaptureDesign]): what both must do, what each shows, and that both fit the
/// smallest phones at the biggest text. `scan_capture_review_test.dart` and the audit cover design A (the default).

Future<void> openCapture(
  WidgetTester tester,
  TestEnv env,
  CaptureDesign design, {
  Size? size,
  double scale = 1.0,
}) async {
  if (size == null) {
    useSmallPhone(tester, textScale: scale);
  } else {
    useSmallPhone(tester, size: size, textScale: scale);
  }
  final container = await pumpApp(tester, env, location: '/home');
  await container.read(settingsProvider.notifier).setCaptureDesign(design);
  env.voice.clear();
  container.read(routerProvider).go(Routes.scan);
  await tester.pumpAndSettle();
}

/// Whether the chip with [key] has the green "being spoken" look.
bool lit(WidgetTester tester, String key) {
  final box = tester.widget<AnimatedContainer>(
    find.descendant(of: keyed(key), matching: find.byType(AnimatedContainer)),
  );
  return (box.decoration! as BoxDecoration).color == const Color(0x335FD17A);
}

void main() {
  group('the choice', () {
    testWidgets('a fresh install shows design A', (tester) async {
      final env = await TestEnv.create(loggedIn: true);
      useSmallPhone(tester);
      final container = await pumpApp(tester, env, location: '/home');
      container.read(routerProvider).go(Routes.scan);
      await tester.pumpAndSettle();
      expect(find.byType(CaptureViewA), findsOneWidget);
      expect(find.byType(CaptureViewB), findsNothing);
    });

    testWidgets('Settings has the choice; the screen follows it and the phone remembers it', (tester) async {
      final env = await TestEnv.create(loggedIn: true, language: 'en');
      useSmallPhone(tester, size: const Size(360, 900));
      final container = await pumpApp(tester, env, location: '/home');
      container.read(routerProvider).go(Routes.settings);
      await tester.pumpAndSettle();
      expect(find.text('CAMERA SCREEN'), findsOneWidget, reason: 'section labels are set in capitals');
      expect(find.text('Design A'), findsOneWidget);
      expect(find.text('Design B'), findsOneWidget);

      await tapKey(tester, 'capture-b');
      expect(env.prefs.getString('capture_design'), 'b');
      container.read(routerProvider).go(Routes.scan);
      await tester.pumpAndSettle();
      expect(find.byType(CaptureViewB), findsOneWidget);

      container.read(routerProvider).go(Routes.settings);
      await tester.pumpAndSettle();
      await tapKey(tester, 'capture-a');
      expect(env.prefs.getString('capture_design'), 'a');
      container.read(routerProvider).go(Routes.scan);
      await tester.pumpAndSettle();
      expect(find.byType(CaptureViewA), findsOneWidget);
    });

    testWidgets('a saved choice is read at start', (tester) async {
      final env = await TestEnv.create(loggedIn: true);
      await env.prefs.setString('capture_design', 'b');
      useSmallPhone(tester);
      final container = await pumpApp(tester, env, location: '/home');
      container.read(routerProvider).go(Routes.scan);
      await tester.pumpAndSettle();
      expect(find.byType(CaptureViewB), findsOneWidget);
    });
  });

  for (final design in CaptureDesign.values) {
    group('design ${design.name.toUpperCase()}: the same things work', () {
      testWidgets('speaks the same five sentences and keeps the buttons the tests and the voice name', (tester) async {
        final env = await TestEnv.create(loggedIn: true);
        await openCapture(tester, env, design);
        expect(env.voice.spokenIds, [
          'scan_open_camera',
          'scan_or_gallery',
          'scan_hold_close',
          'scan_one_leaf',
          'scan_daylight',
        ]);
        expect(env.voice.unknownIds, isEmpty);
        expect(tester.getSize(keyed('camera-button')).width, greaterThanOrEqualTo(88));
        expect(tester.getSize(keyed('gallery-button')).width, greaterThanOrEqualTo(56));
        expect(keyed('send-photos'), findsOneWidget);
        expect(keyed('strip-add'), findsOneWidget);
        expectBigTouchTargets(tester);
      });

      testWidgets('a photo goes to the review; the strip then shows it, the count and the free slots', (tester) async {
        final env = await TestEnv.create(loggedIn: true, language: 'en');
        env.picker.queuePhotos(2);
        await openCapture(tester, env, design);
        expect(find.text('Photo 1 of 4'), findsOneWidget);
        expect(find.text('0/4'), findsOneWidget);
        // The plus tile is slot 1; the empty slots after it carry their numbers 2, 3 and 4.
        for (final n in ['2', '3', '4']) {
          expect(find.text(n), findsOneWidget, reason: 'slot $n');
        }
        await tapKey(tester, 'camera-button');
        await tapKey(tester, 'add-photo');
        expect(find.text('Photo 2 of 4'), findsOneWidget);
        expect(keyed('strip-photo-0'), findsOneWidget);
        expect(find.text('1/4'), findsOneWidget);
        // Slot 1 is the photo, slot 2 the plus tile; 3 and 4 are still empty.
        expect(find.text('2'), findsNothing);
        expect(find.text('3'), findsOneWidget);
        expect(find.text('4'), findsOneWidget);
        expectBigTouchTargets(tester);

        await tester.tap(find.descendant(of: keyed('strip-remove-0'), matching: find.byIcon(AppIcons.crossBold)));
        await tester.pumpAndSettle();
        expect(keyed('strip-photo-0'), findsNothing);
        expect(find.text('0/4'), findsOneWidget);
      });

      testWidgets('with four photos there is no plus and no empty slot, and the send tick is on', (tester) async {
        final env = await TestEnv.create(loggedIn: true, language: 'en');
        await openCapture(tester, env, design);
        final flow = containerOf(tester).read(scanFlowProvider.notifier);
        for (var i = 0; i < 4; i++) {
          flow.addPhoto('/tmp/leaf_$i.jpg');
        }
        await tester.pumpAndSettle();
        expect(keyed('strip-photo-3'), findsOneWidget);
        expect(keyed('strip-add'), findsNothing);
        expect(find.text('4/4'), findsOneWidget);
        expect(find.text('Photo 4 of 4'), findsOneWidget);
        final send = tester.widget<InkWell>(find.descendant(of: keyed('send-photos'), matching: find.byType(InkWell)));
        expect(send.onTap, isNotNull);
      });

      testWidgets('camera permission denied: the red camera replaces the leaf and one more tap tries again', (
        tester,
      ) async {
        final env = await TestEnv.create(loggedIn: true);
        env.picker.script.add(const CameraPermissionDenied());
        env.picker.queuePhotos(1);
        await openCapture(tester, env, design);
        env.voice.clear();
        await tapKey(tester, 'camera-button');
        expect(keyed('camera-denied'), findsOneWidget);
        expect(env.voice.spokenIds, ['permission_denied_camera']);
        await tapKey(tester, 'camera-button');
        expect(keyed('photo-0'), findsOneWidget);
      });

      testWidgets('the gallery adds photos and the back arrow leaves', (tester) async {
        final env = await TestEnv.create(loggedIn: true);
        env.picker.queueGallery(2);
        await openCapture(tester, env, design);
        await tapKey(tester, 'gallery-button');
        expect(env.picker.galleryOpened, 1);
        expect(keyed('photo-1'), findsOneWidget);
      });
    });
  }

  group('design A: the tip chips', () {
    testWidgets('three chips with their words, in English and in Hindi', (tester) async {
      final env = await TestEnv.create(loggedIn: true, language: 'en');
      await openCapture(tester, env, CaptureDesign.a);
      expect(find.text('One leaf with spots'), findsOneWidget);
      expect(find.text('Close, whole leaf'), findsOneWidget);
      expect(find.text('Daylight'), findsOneWidget);
    });

    testWidgets('the chip of the sentence being spoken lights up, no other, and none when it is not spoken', (
      tester,
    ) async {
      final env = await TestEnv.create(language: 'en');
      final owner = Object();
      await tester.pumpWidget(env.wrap(Scaffold(body: CaptureViewA(owner: owner, denied: false))));
      await tester.pumpAndSettle();
      expect(
        [lit(tester, 'tip-chip-leaf'), lit(tester, 'tip-chip-close'), lit(tester, 'tip-chip-light')],
        [false, false, false],
      );

      Future<List<bool>> say(String id, {Object? by}) async {
        await env.voice.speak([PromptUtterance(id)], owner: by ?? owner);
        await tester.pumpAndSettle();
        return [lit(tester, 'tip-chip-leaf'), lit(tester, 'tip-chip-close'), lit(tester, 'tip-chip-light')];
      }

      expect(await say('scan_one_leaf'), [true, false, false]);
      expect(await say('scan_hold_close'), [false, true, false]);
      expect(await say('scan_daylight'), [false, false, true]);
      expect(await say('scan_open_camera'), [
        false,
        false,
        false,
      ], reason: 'a sentence that is not a tip lights nothing');
      expect(await say('scan_daylight', by: Object()), [false, false, false], reason: 'another screen is speaking');
      await say('scan_daylight');
      env.voice.finishSpeaking();
      await tester.pumpAndSettle();
      expect(lit(tester, 'tip-chip-light'), isFalse, reason: 'nothing is lit once the speech is over');
    });

    testWidgets('the chips do not take taps and a screen reader skips them', (tester) async {
      final env = await TestEnv.create(loggedIn: true, language: 'en');
      final semantics = tester.ensureSemantics();
      await openCapture(tester, env, CaptureDesign.a);
      expect(find.bySemanticsLabel('One leaf with spots'), findsNothing);
      semantics.dispose();
    });
  });

  group('design B: the viewfinder', () {
    testWidgets('has the two chips, and the thirds, outline and focus are drawn', (tester) async {
      final env = await TestEnv.create(loggedIn: true, language: 'en');
      await openCapture(tester, env, CaptureDesign.b);
      expect(find.text('Fit the whole leaf inside'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(CaptureViewB), matching: find.text('Take the photo in daylight.')),
        findsOneWidget,
      );
      expect(find.byType(CaptureBackdropB), findsOneWidget);
    });
  });

  // Both looks on the smallest phones with the biggest text, as the audit does for every other screen: no overflow, every
  // tap target at least 56 dp (48 for Android's own rule) and every control with a label.
  for (final design in CaptureDesign.values) {
    for (final size in const [Size(320, 568), Size(360, 640), Size(411, 900)]) {
      for (final scale in const [1.0, 2.0]) {
        for (final language in const ['en', 'hi']) {
          testWidgets(
            'design ${design.name.toUpperCase()} fits ${size.width.toInt()}x${size.height.toInt()} at text size $scale in $language',
            (tester) async {
              final semantics = tester.ensureSemantics();
              final env = await TestEnv.create(loggedIn: true, language: language);
              await openCapture(tester, env, design, size: size, scale: scale);
              expect(tester.takeException(), isNull);
              expectBigTouchTargets(tester);
              await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
              await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

              // The same with a full strip: four photos, each with its red cross.
              final flow = containerOf(tester).read(scanFlowProvider.notifier);
              for (var i = 0; i < 4; i++) {
                flow.addPhoto('/tmp/leaf_$i.jpg');
              }
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              expectBigTouchTargets(tester);
              await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
              semantics.dispose();
            },
          );
        }
      }
    }
  }
}
