import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmtrack/core/models/models.dart';
import 'package:farmtrack/core/network/api_client.dart';
import 'package:farmtrack/core/errors/api_exception.dart';
import 'package:farmtrack/core/network/mock_api_client.dart';
import 'package:farmtrack/core/network/mock_data.dart';
import 'package:farmtrack/core/voice/utterance.dart';
import 'package:farmtrack/features/diary/diary_screen.dart';
import 'package:farmtrack/core/theme/app_theme.dart';
import 'package:farmtrack/core/widgets/design.dart';

import 'support/finders.dart';
import 'support/harness.dart';

/// A mock server whose next scan answer is whatever the test builds.
class _ScriptedApi extends MockApiClient {
  _ScriptedApi(this.build) : super(latency: Duration.zero);

  final ScanOut Function(String id) build;

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
    calls.add('createScan');
    final scan = build('scan-1');
    scans[scan.id] = scan;
    return scan;
  }
}

/// Opens the camera screen, takes one photo and sends it. Afterwards the voice log holds only the result screen's speech.
Future<void> runScan(WidgetTester tester, TestEnv env) async {
  useSmallPhone(tester);
  env.picker.queuePhotos(1);
  await pumpApp(tester, env, location: '/home');
  await tapKey(tester, 'home-scan');
  await tapKey(tester, 'camera-button');
  await tapKey(tester, 'send-photos');
  env.voice.keepLastCall(); // what the result screen said when it opened
}

Future<TestEnv> envFor(MockScanScenario scenario, {String language = 'hi'}) =>
    TestEnv.create(loggedIn: true, language: language, scanScript: [scenario]);

void main() {
  group('ok: the advice screen', () {
    testWidgets(
      'shows severity, medicine, dose sentence, timing, warnings and steps, and speaks intro then the advice',
      (tester) async {
        final env = await envFor(MockScanScenario.ok);
        await runScan(tester, env);

        expect(keyed('severity-yellow'), findsOneWidget);
        expect(find.text('सेब का स्कैब (पपड़ी रोग)'), findsOneWidget);
        expect(keyed('product-P007'), findsOneWidget);
        expect(find.text('डिफेनोकोनाज़ोल'), findsOneWidget);
        expect(find.textContaining('Score'), findsOneWidget);
        expect(find.text('दो सौ लीटर पानी में तीस मिलीलीटर।'), findsOneWidget);
        expect(find.text('तुड़ाई से 14 दिन पहले तक रुकें'), findsOneWidget);
        expect(find.textContaining('आज छिड़काव कीजिए'), findsOneWidget);
        expect(find.textContaining('कोई और दवा, खाद या हार्मोन मत मिलाइए'), findsOneWidget);
        expect(find.textContaining('सात दिन के अंदर दोबारा'), findsOneWidget);
        // The explanation sits in the severity card; the safety notes and steps wait behind "More".
        expect(find.text('सलाह'), findsOneWidget, reason: 'the name of the screen in the top bar');
        expect(keyed('advice-summary'), findsOneWidget);
        expect(find.textContaining('पत्तियों पर भूरे, मखमली धब्बे'), findsOneWidget);
        expect(find.textContaining('मुँह पर कपड़ा'), findsNothing);
        expect(find.textContaining('पूरे पेड़ पर'), findsNothing);
        await tapKey(tester, 'advice-more');
        expect(find.textContaining('मुँह पर कपड़ा'), findsOneWidget);
        expect(find.byIcon(AppIcons.warning), findsWidgets);
        expect(find.byIcon(AppIcons.danger), findsWidgets, reason: 'the red warning has its own picture');
        expect(find.textContaining('पूरे पेड़ पर'), findsOneWidget);

        final advice = MockData.scabAdvice('x');
        expect(env.voice.log, ['result_intro@hi', '${advice.spoken.text.hi}@hi', 'diary_tick_sprayed@hi']);
        expect(env.voice.unknownIds, isEmpty);
      },
    );

    testWidgets('in English everything reads and speaks in English', (tester) async {
      final env = await envFor(MockScanScenario.ok, language: 'en');
      await runScan(tester, env);
      expect(find.text('Apple scab'), findsWidgets);
      expect(find.text('Advice'), findsOneWidget);
      expect(find.text('Be careful'), findsOneWidget, reason: 'the severity word on the card');
      expect(find.descendant(of: keyed('advice-crop'), matching: find.text('Apple')), findsOneWidget);
      expect(find.text('Thirty millilitres in two hundred litres of water.'), findsOneWidget);
      expect(find.text('Wait 14 days before harvest'), findsOneWidget);
      expect(env.voice.log.first, 'result_intro@en');
      expect(env.voice.spokenTexts.single, startsWith('This is apple scab. Spray Difenoconazole'));
    });

    testWidgets('the speaker button plays it all again', (tester) async {
      final env = await envFor(MockScanScenario.ok);
      await runScan(tester, env);
      final first = List.of(env.voice.log);
      await tester.tap(keyed('speaker-button'));
      await tester.pump();
      expect(env.voice.log, [...first, ...first]);
    });

    testWidgets('the server\'s spoken audio reference travels with the text', (tester) async {
      final scan = MockData.okScan('scan-1');
      final withAudio = ScanOut.fromJson({
        ...scan.toJson(),
        'advice': {
          ...scan.advice!.toJson(),
          'spoken': {
            'text': scan.advice!.spoken.text.toJson(),
            'audio': {
              'hi': {'url': '/audio/abc.mp3', 'sha256': 'abc'},
            },
          },
        },
      });
      final env = await TestEnv.create(loggedIn: true, api: _ScriptedApi((_) => withAudio));
      await runScan(tester, env);
      final utterance = env.voice.spoken.whereType<TextUtterance>().single;
      expect(utterance.audio!.url, '/audio/abc.mp3');
      expect(utterance.audio!.sha256, 'abc');
    });

    testWidgets('server next_steps prompt ids win over the built-in ones', (tester) async {
      final scan = MockData.okScan('scan-1');
      final custom = ScanOut.fromJson({
        ...scan.toJson(),
        'next_steps': [
          {'action': 'mark_sprayed', 'prompt_id': 'diary_tick_sprayed'},
        ],
      });
      final env = await TestEnv.create(loggedIn: true, api: _ScriptedApi((_) => custom));
      await runScan(tester, env);
      expect(env.voice.spokenIds, ['result_intro', 'diary_tick_sprayed']);
    });

    testWidgets('the green tick opens the diary with the advice, crop and medicine preselected', (tester) async {
      final env = await envFor(MockScanScenario.ok);
      await runScan(tester, env);
      expectBigTouchTargets(tester);
      env.voice.clear();
      await tapKey(tester, 'i-sprayed');
      final diary = tester.widget<DiaryScreen>(find.byType(DiaryScreen));
      expect(diary.adviceId, 'adv-scan-1');
      expect(diary.cropId, 'apple');
      expect(diary.productId, 'P007');
      // The diary's confirm screen: the medicine's name, the question, then what the tick and the cross do.
      expect(env.voice.spokenTexts, ['डिफेनोकोनाज़ोल, Score']);
      expect(env.voice.spokenIds, ['diary_did_spray', 'diary_tick_sprayed', 'diary_cross_back']);
    });

    testWidgets('an advice with several medicines, a red severity and no timing renders every card', (tester) async {
      final base = MockData.scabAdvice('scan-1');
      final product = base.products.single;
      final advice = ScanOut.fromJson({
        ...MockData.okScan('scan-1').toJson(),
        'advice': {
          ...base.toJson(),
          'severity': 'red',
          'timing': null,
          'products': [
            product.toJson(),
            {
              ...product.toJson(),
              'product_id': 'P006',
              'active_ingredient': {'en': 'Propineb', 'hi': 'प्रोपीनेब'},
              'warnings': [
                {
                  'code': 'proposed_ban',
                  'level': 'yellow',
                  'text': {'en': 'May be banned', 'hi': 'रोक लग सकती है'},
                },
              ],
            },
          ],
        },
      });
      final env = await TestEnv.create(loggedIn: true, api: _ScriptedApi((_) => advice));
      await runScan(tester, env);
      expect(keyed('severity-red'), findsOneWidget);
      expect(keyed('product-P007'), findsOneWidget);
      expect(keyed('product-P006'), findsOneWidget);
      expect(find.text('रोक लग सकती है'), findsOneWidget);
      expect(keyed('advice-timing'), findsNothing);
    });

    testWidgets('the "When" card says what to do by its colour: green spray, grey wait, blue information', (
      tester,
    ) async {
      final base = MockData.scabAdvice('scan-1');
      final cases = {
        TimingAction.sprayNow: (AppColors.greenSoft, AppIcons.tickBold),
        TimingAction.wait: (AppColors.neutralSoft, AppIcons.hourglass),
        TimingAction.repeatWithinDays: (AppColors.blueSoft, AppIcons.roundArrow),
        TimingAction.notNeeded: (AppColors.blueSoft, AppIcons.info),
        TimingAction.unknown: (AppColors.neutralSoft, AppIcons.clock),
      };
      for (final entry in cases.entries) {
        final scan = ScanOut.fromJson({
          ...MockData.okScan('scan-1').toJson(),
          'advice': {
            ...base.toJson(),
            'timing': TimingOut(
              action: entry.key,
              text: LocalizedText.pair(en: 'Timing', hi: 'समय'),
            ).toJson(),
          },
        });
        final env = await TestEnv.create(loggedIn: true, api: _ScriptedApi((_) => scan));
        await runScan(tester, env);
        final card = tester.widget<DecoratedBox>(
          find.descendant(of: keyed('advice-timing'), matching: find.byType(DecoratedBox)).first,
        );
        expect((card.decoration as BoxDecoration).color, entry.value.$1, reason: entry.key.wire);
        expect(find.descendant(of: keyed('advice-timing'), matching: find.byIcon(entry.value.$2)), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('the severity card is amber, red or green with its own picture', (tester) async {
      final base = MockData.scabAdvice('scan-1');
      const cases = {
        'yellow': (AppColors.amberSoft, AppColors.amber, AppIcons.warning),
        'red': (AppColors.redSoft, AppColors.red, AppIcons.danger),
        'green': (AppColors.greenSoft, AppColors.green, AppIcons.tick),
      };
      for (final entry in cases.entries) {
        final scan = ScanOut.fromJson({
          ...MockData.okScan('scan-1').toJson(),
          'advice': {...base.toJson(), 'severity': entry.key},
        });
        final env = await TestEnv.create(loggedIn: true, api: _ScriptedApi((_) => scan));
        await runScan(tester, env);
        final severity = keyed('severity-${entry.key}');
        final card = tester.widget<DecoratedBox>(
          find.descendant(of: severity, matching: find.byType(DecoratedBox)).first,
        );
        expect((card.decoration as BoxDecoration).color, entry.value.$1, reason: entry.key);
        final dot = tester.widget<IconDot>(find.descendant(of: severity, matching: find.byType(IconDot)).first);
        expect(dot.background, entry.value.$2, reason: entry.key);
        expect(
          find.descendant(of: severity, matching: find.byIcon(entry.value.$3)),
          findsOneWidget,
          reason: entry.key,
        );
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  group('confirm_crop', () {
    testWidgets('speaks the crop and asks for the tick; the green tick confirms the same crop and shows the advice', (
      tester,
    ) async {
      final env = await envFor(MockScanScenario.confirmCrop);
      await runScan(tester, env);
      expect(find.text('सेब'), findsOneWidget);
      expect(env.voice.log, ['crop_is_apple@hi', 'crop_confirm_prompt@hi', 'crop_tap_yes@hi', 'crop_tap_no@hi']);
      expectBigTouchTargets(tester);

      env.voice.clear();
      await tapKey(tester, 'crop-yes');
      expect(env.api.confirmedCrops, ['apple']);
      expect(keyed('severity-yellow'), findsOneWidget);
      expect(env.voice.spokenIds, ['scan_wait', 'result_intro', 'diary_tick_sprayed']);
    });

    testWidgets('the red cross opens the grid of crops: likely ones first, six per page, arrows instead of scrolling', (
      tester,
    ) async {
      final env = await envFor(MockScanScenario.confirmCrop, language: 'en');
      await runScan(tester, env);
      env.voice.clear();
      await tapKey(tester, 'crop-no');
      expect(env.voice.spokenIds, ['crop_choose_other']);
      for (final id in ['apple', 'pear', 'plum', 'tomato', 'potato', 'maize']) {
        expect(keyed('crop-$id'), findsOneWidget, reason: id);
      }
      expect(keyed('crop-grape'), findsNothing);
      expect(keyed('crops-prev'), findsNothing);
      expectBigTouchTargets(tester);

      await tapKey(tester, 'crops-next');
      expect(keyed('crop-grape'), findsOneWidget);
      expect(keyed('crop-apple'), findsNothing);
      await tapKey(tester, 'crops-prev');
      expect(keyed('crop-apple'), findsOneWidget);
    });

    testWidgets('choosing another crop posts that crop; a crop with data but no auto-advice goes to the expert', (
      tester,
    ) async {
      final env = await envFor(MockScanScenario.confirmCrop);
      await runScan(tester, env);
      await tapKey(tester, 'crop-no');
      expect(find.text('नाशपाती'), findsOneWidget, reason: 'names follow the language');
      await tapKey(tester, 'crop-tomato');
      expect(env.api.confirmedCrops, ['tomato']);
      expect(keyed('expert-icon-needs_expert'), findsOneWidget);
    });

    testWidgets('a crop without approved data ends on the "no advice yet" screen', (tester) async {
      final env = await envFor(MockScanScenario.confirmCrop);
      await runScan(tester, env);
      await tapKey(tester, 'crop-no');
      await tapKey(tester, 'crops-next');
      await tapKey(tester, 'crops-next');
      await tapKey(tester, 'crop-cauliflower');
      expect(env.api.confirmedCrops, ['cauliflower']);
      expect(keyed('expert-icon-no_approved_data'), findsOneWidget);
      expect(env.voice.spokenIds, contains('result_no_data'));
    });

    testWidgets('a crop the server could not name goes straight to the grid', (tester) async {
      final unknown = ScanOut.fromJson({
        ...MockData.confirmCropScan('scan-1').toJson(),
        'crop': const CropOut(unknown: true, confidence: 0.1, needsConfirmation: true).toJson(),
      });
      final env = await TestEnv.create(loggedIn: true, api: _ScriptedApi((_) => unknown));
      await runScan(tester, env);
      expect(keyed('crop-apple'), findsOneWidget);
      expect(env.voice.spokenIds, ['crop_choose_other']);
    });

    testWidgets('a crop that has no spoken prompt is read from its name', (tester) async {
      final olive = ScanOut.fromJson({
        ...MockData.confirmCropScan('scan-1').toJson(),
        'crop': CropOut(
          cropId: 'olive',
          name: LocalizedText.pair(en: 'Olive', hi: 'जैतून'),
          confidence: 0.5,
          needsConfirmation: true,
        ).toJson(),
      });
      final env = await TestEnv.create(loggedIn: true, api: _ScriptedApi((_) => olive));
      await runScan(tester, env);
      expect(env.voice.spokenTexts, ['जैतून']);
      expect(env.voice.spokenIds, ['crop_confirm_prompt', 'crop_tap_yes', 'crop_tap_no']);
    });
  });

  group('photo_unusable', () {
    testWidgets('speaks what was wrong, then "tap the camera"; the camera starts a fresh scan', (tester) async {
      final env = await envFor(MockScanScenario.photoBlurry);
      await runScan(tester, env);
      expect(env.voice.spokenIds, ['scan_retake_blurry', 'scan_retake_tap']);
      expectBigTouchTargets(tester);
      env.voice.clear();
      await tapKey(tester, 'retake-camera');
      expect(keyed('camera-button'), findsOneWidget);
      expect(env.voice.spokenIds.first, 'scan_open_camera');
    });

    testWidgets('too dark or too bright has its own tip', (tester) async {
      final env = await envFor(MockScanScenario.photoTooDark);
      await runScan(tester, env);
      expect(env.voice.spokenIds, ['scan_retake_dark', 'scan_retake_tap']);
    });

    testWidgets('every quality issue maps to its tip when the server names none', (tester) async {
      const expected = {
        'blurry': 'scan_retake_blurry',
        'too_dark': 'scan_retake_dark',
        'too_bright': 'scan_retake_dark',
        'too_small': 'scan_retake_far',
        'no_leaf': 'scan_retake_no_leaf',
      };
      for (final entry in expected.entries) {
        final scan = ScanOut.fromJson({
          ...MockData.photoUnusableScan('scan-1').toJson(),
          'quality': QualityOut(usable: false, issues: [entry.key], tipPromptId: 'not_a_known_prompt').toJson(),
        });
        final env = await TestEnv.create(loggedIn: true, api: _ScriptedApi((_) => scan));
        await runScan(tester, env);
        expect(env.voice.spokenIds, [entry.value, 'scan_retake_tap'], reason: entry.key);
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  group('needs_expert, no_approved_data, not_a_disease', () {
    testWidgets('needs_expert: speaks result_expert and the server text; the button asks the expert', (tester) async {
      final env = await envFor(MockScanScenario.needsExpert);
      await runScan(tester, env);
      final scan = env.api.scans['scan-1']!;
      expect(env.voice.log, ['result_expert@hi', '${scan.spoken.text.hi}@hi']);
      expect(keyed('expert-icon-needs_expert'), findsOneWidget);
      expect(find.text('अभी पक्का नहीं'), findsOneWidget);
      expect(find.text('नतीजा'), findsOneWidget, reason: 'the name of the screen in the top bar');
      // Before it is saved: no "Saved" tag, and the strip holds a new photo, home and the wide "save this case".
      expect(keyed('expert-sent'), findsNothing);
      expect(keyed('expert-camera'), findsOneWidget);
      expect(keyed('expert-home'), findsOneWidget);
      expectBigTouchTargets(tester);

      env.voice.clear();
      await tapKey(tester, 'ask-expert');
      expect(env.api.expertRequests.single.scanId, 'scan-1');
      expect(keyed('expert-sent'), findsOneWidget);
      expect(find.text('सुरक्षित रख लिया'), findsOneWidget);
      expect(keyed('ask-expert'), findsNothing);
      // Saved: the strip is the mockup's wide "take the photo again" and the green house.
      expect(find.descendant(of: keyed('expert-camera'), matching: find.text('फोटो फिर से खींचिए')), findsOneWidget);
      expect(find.descendant(of: keyed('expert-home'), matching: find.byIcon(AppIcons.house)), findsOneWidget);
      expectBigTouchTargets(tester);
      expect(env.voice.spokenIds, ['expert_photos_saved']);
    });

    testWidgets('the expert screen tells who will call: the farmer\'s own number and what to do', (tester) async {
      final env = await envFor(MockScanScenario.needsExpert, language: 'en');
      await runScan(tester, env);
      expect(find.text('An expert will look at your photos and call you on your phone.'), findsOneWidget);
      expect(find.text('1 photo'), findsOneWidget);
      expect(find.text('We will call you on'), findsOneWidget);
      expect(find.text('+91 ••••• •0001'), findsOneWidget);
      expect(find.text('Keep your phone with you'), findsOneWidget);
      expect(find.text('The expert calls from the FarmTrack office'), findsOneWidget);
    });

    testWidgets('each variant has its own colour: blue (expert), amber (no data), grey (no disease)', (tester) async {
      const cases = {
        MockScanScenario.needsExpert: ('needs_expert', AppColors.blue, AppIcons.expert),
        MockScanScenario.noApprovedData: ('no_approved_data', AppColors.amber, AppIcons.info),
        MockScanScenario.notADisease: ('not_a_disease', AppColors.inkSoft, AppIcons.noDisease),
      };
      for (final entry in cases.entries) {
        final env = await envFor(entry.key);
        await runScan(tester, env);
        final dot = tester.widget<IconDot>(keyed('expert-icon-${entry.value.$1}'));
        expect(dot.background, entry.value.$2, reason: entry.value.$1);
        expect(dot.icon, entry.value.$3, reason: entry.value.$1);
        expect(dot.size, 72);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('no_approved_data: speaks result_no_data and shows no medicine', (tester) async {
      final env = await envFor(MockScanScenario.noApprovedData);
      await runScan(tester, env);
      expect(env.voice.spokenIds, ['result_no_data']);
      expect(env.voice.spokenTexts.single, contains('मंज़ूर की हुई सलाह'));
      expect(keyed('expert-icon-no_approved_data'), findsOneWidget);
      expect(find.byIcon(AppIcons.medicine), findsNothing);
      expect(keyed('ask-expert'), findsOneWidget);
    });

    testWidgets('not_a_disease: speaks result_not_disease and offers another photo', (tester) async {
      final env = await envFor(MockScanScenario.notADisease);
      await runScan(tester, env);
      expect(env.voice.spokenIds, ['result_not_disease']);
      expect(keyed('expert-icon-not_a_disease'), findsOneWidget);
      env.voice.clear();
      await tapKey(tester, 'expert-camera');
      expect(keyed('camera-button'), findsOneWidget);
      expect(env.voice.spokenIds.first, 'scan_open_camera');
    });

    testWidgets('a failed expert request speaks the error and keeps the button', (tester) async {
      final env = await envFor(MockScanScenario.needsExpert);
      await runScan(tester, env);
      env.api.failWith(const ApiException.network(), times: 1, ops: {'createExpertRequest'});
      await tapKey(tester, 'ask-expert');
      expect(env.voice.spokenIds.last, 'error_no_internet');
      expect(keyed('ask-expert'), findsOneWidget);
      await tapKey(tester, 'ask-expert');
      expect(keyed('expert-sent'), findsOneWidget);
    });

    testWidgets('general protective advice that comes with an expert case is shown under the explanation', (
      tester,
    ) async {
      final scan = ScanOut.fromJson({
        ...MockData.needsExpertScan('scan-1').toJson(),
        'advice': MockData.scabAdvice('scan-1').toJson(),
      });
      final env = await TestEnv.create(loggedIn: true, api: _ScriptedApi((_) => scan));
      await runScan(tester, env);
      expect(keyed('severity-yellow'), findsOneWidget);
      expect(keyed('ask-expert'), findsOneWidget);
    });

    testWidgets('a status the app does not know yet is handled like "ask an expert"', (tester) async {
      final scan = ScanOut.fromJson({...MockData.needsExpertScan('scan-1').toJson(), 'status': 'something_new'});
      final env = await TestEnv.create(loggedIn: true, api: _ScriptedApi((_) => scan));
      await runScan(tester, env);
      expect(keyed('expert-icon-needs_expert'), findsOneWidget);
    });
  });

  testWidgets('the whole mock script, in order: confirm, advice, blurry, expert, no data, no disease', (tester) async {
    final env = await TestEnv.create(loggedIn: true);
    useSmallPhone(tester);
    await pumpApp(tester, env, location: '/home');
    const expected = [
      'crop-yes',
      'severity-yellow',
      'retake-camera',
      'expert-icon-needs_expert',
      'expert-icon-no_approved_data',
      'expert-icon-not_a_disease',
    ];
    for (final key in expected) {
      env.picker.queuePhotos(1);
      await tapKey(tester, 'home-scan');
      await tapKey(tester, 'camera-button');
      await tapKey(tester, 'send-photos');
      expect(keyed(key), findsOneWidget, reason: 'expected $key');
      if (key == 'crop-yes') {
        await tapKey(tester, 'crop-yes');
        expect(keyed('severity-yellow'), findsOneWidget);
      }
      await tester.tap(find.byIcon(AppIcons.back));
      await tester.pumpAndSettle();
      expect(keyed('home-scan'), findsOneWidget, reason: 'back arrow returns to the home screen');
    }
    expect(env.voice.unknownIds, isEmpty);
  });
}
