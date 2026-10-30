import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmtrack/core/models/models.dart';
import 'package:farmtrack/core/network/api_client.dart';
import 'package:farmtrack/core/errors/api_exception.dart';
import 'package:farmtrack/core/network/mock_api_client.dart';
import 'package:farmtrack/core/network/mock_data.dart';
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
    testWidgets('shows the crop, the disease, the medicine with its two steps and last one card of advice', (
      tester,
    ) async {
      final env = await envFor(MockScanScenario.ok);
      await runScan(tester, env);

      // The crop's round picture and name, then the disease with the severity's picture.
      expect(keyed('advice-crop-card'), findsOneWidget);
      expect(tester.widget<Text>(keyed('advice-crop')).data, 'सेब');
      expect(tester.widget<Text>(keyed('advice-headline')).data, 'सेब का स्कैब (पपड़ी रोग)');
      expect(keyed('severity-yellow'), findsOneWidget);
      // The medicine: its name, the brand, the two steps and the waiting period; not the server's dose sentence.
      expect(keyed('product-P007'), findsOneWidget);
      expect(find.text('डिफेनोकोनाज़ोल'), findsOneWidget, reason: 'the card title; the step is a whole sentence');
      expect(find.textContaining('Score'), findsOneWidget);
      expect(find.text('डिफेनोकोनाज़ोल 30 मिली लें।'), findsOneWidget);
      expect(find.text('इसे 200 लीटर पानी में मिलाएँ।'), findsOneWidget);
      expect(find.text('दो सौ लीटर पानी में तीस मिलीलीटर।'), findsNothing);
      expect(find.text('तुड़ाई से 14 दिन पहले तक रुकें'), findsOneWidget);
      // Last, one card: when to spray, the warnings and the general measures. The long safety notes wait behind "More".
      expect(keyed('advice-notes'), findsOneWidget);
      expect(
        find.descendant(of: keyed('advice-notes'), matching: find.textContaining('आज छिड़काव कीजिए')),
        findsOneWidget,
      );
      expect(find.textContaining('कोई और दवा, खाद या हार्मोन मत मिलाइए'), findsOneWidget);
      expect(find.textContaining('सात दिन के अंदर दोबारा'), findsOneWidget);
      expect(find.textContaining('पूरे पेड़ पर'), findsOneWidget, reason: 'a general measure of the advice');
      expect(find.text('सलाह'), findsOneWidget, reason: 'the name of the screen in the top bar');
      expect(keyed('advice-summary'), findsNothing, reason: 'no explanation text any more');
      expect(find.textContaining('मुँह पर कपड़ा'), findsNothing);
      await tapKey(tester, 'advice-more');
      expect(find.textContaining('मुँह पर कपड़ा'), findsOneWidget);
      expect(find.byIcon(AppIcons.warning), findsWidgets);
      expect(find.byIcon(AppIcons.danger), findsWidgets, reason: 'the red warning has its own picture');
      expectBigTouchTargets(tester);

      // Only the crop, the disease and the names of the medicines are said by themselves.
      expect(env.voice.log, ['crop_is_apple@hi', 'सेब का स्कैब (पपड़ी रोग)@hi', 'दवा: डिफेनोकोनाज़ोल।@hi']);
      expect(env.voice.unknownIds, isEmpty);
    });

    testWidgets('in English everything reads and speaks in English', (tester) async {
      final env = await envFor(MockScanScenario.ok, language: 'en');
      await runScan(tester, env);
      expect(find.text('Advice'), findsOneWidget);
      expect(tester.widget<Text>(keyed('advice-crop')).data, 'Apple');
      expect(tester.widget<Text>(keyed('advice-headline')).data, 'Apple scab');
      expect(find.text('Take 30 ml of Difenoconazole.'), findsOneWidget);
      expect(find.text('Mix it in 200 litres of water.'), findsOneWidget);
      expect(find.text('Wait 14 days before harvest'), findsOneWidget);
      expect(find.text('Advice and warnings'), findsOneWidget);
      expect(env.voice.log, ['crop_is_apple@en', 'Apple scab@en', 'Medicine: Difenoconazole.@en']);
    });

    testWidgets('the speaker button plays the three again', (tester) async {
      final env = await envFor(MockScanScenario.ok);
      await runScan(tester, env);
      final first = List.of(env.voice.log);
      await replayVoice(tester);
      expect(env.voice.log, [...first, ...first]);
    });

    testWidgets('a medicine card and the last card have a speaker; only a tap says them', (tester) async {
      final env = await envFor(MockScanScenario.ok, language: 'en');
      await runScan(tester, env);
      env.voice.clear();
      expect(env.voice.log, isEmpty, reason: 'nothing of the cards is said by itself');

      await tapKey(tester, 'product-speak-P007');
      expect(env.voice.spokenTexts, [
        'Difenoconazole. Take 30 millilitres of Difenoconazole. Mix it in 200 litres of water. '
            'Wait 14 days before harvest.',
      ]);

      env.voice.clear();
      await tapKey(tester, 'advice-notes-speak');
      final said = env.voice.spokenTexts.single;
      expect(said, startsWith('Spray today. No rain is expected in the next twelve hours.'));
      expect(said, contains('Do not mix any other chemical, nutrient or hormone with this spray.'));
      expect(said, contains('Spray the whole tree, on the top and the bottom of the leaves.'));
      expect(said, isNot(contains('Wear a mask')), reason: 'the safety notes are said only once they are opened');

      await tapKey(tester, 'advice-more');
      env.voice.clear();
      await tapKey(tester, 'advice-notes-speak');
      expect(env.voice.spokenTexts.single, contains('Wear a mask and gloves.'));
      expectBigTouchTargets(tester);
    });

    testWidgets('a dose that is not "X in N litres of water" is not cut into steps: the server sentence shows', (
      tester,
    ) async {
      final base = MockData.scabAdvice('scan-1');
      final scan = ScanOut.fromJson({
        ...MockData.okScan('scan-1').toJson(),
        'advice': {
          ...base.toJson(),
          'products': [
            {...base.products.single.toJson(), 'dose_unit': 'ml/L'},
          ],
        },
      });
      final env = await TestEnv.create(loggedIn: true, language: 'en', api: _ScriptedApi((_) => scan));
      await runScan(tester, env);
      expect(find.text('Thirty millilitres in two hundred litres of water.'), findsOneWidget);
      expect(find.textContaining('Take 30'), findsNothing);
      expect(find.textContaining('Mix it in'), findsNothing);
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
      expect(keyed('advice-choose-one'), findsOneWidget, reason: 'with several medicines: choose one');
      // A medicine's own warning is in the last card, once.
      expect(find.text('रोक लग सकती है'), findsOneWidget);
      expect(find.descendant(of: keyed('advice-notes'), matching: find.text('रोक लग सकती है')), findsOneWidget);
      expect(find.textContaining('अगले बारह घंटे'), findsNothing, reason: 'no timing');
      expect(env.voice.log.last, 'दवा: डिफेनोकोनाज़ोल, प्रोपीनेब।@hi');
    });

    testWidgets('the first line of the last card says what to do by its picture', (tester) async {
      final base = MockData.scabAdvice('scan-1');
      final cases = {
        TimingAction.sprayNow: AppIcons.tickBold,
        TimingAction.wait: AppIcons.hourglass,
        TimingAction.repeatWithinDays: AppIcons.roundArrow,
        TimingAction.notNeeded: AppIcons.info,
        TimingAction.unknown: AppIcons.info,
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
        expect(find.descendant(of: keyed('advice-note-0'), matching: find.text('समय')), findsOneWidget);
        expect(
          find.descendant(of: keyed('advice-note-0'), matching: find.byIcon(entry.value)),
          findsOneWidget,
          reason: entry.key.wire,
        );
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('the disease is only its name: no warning picture, the severity is for a screen reader', (
      tester,
    ) async {
      final base = MockData.scabAdvice('scan-1');
      const words = {'yellow': 'सावधान', 'red': 'गंभीर', 'green': 'ठीक'};
      for (final entry in words.entries) {
        final scan = ScanOut.fromJson({
          ...MockData.okScan('scan-1').toJson(),
          'advice': {...base.toJson(), 'severity': entry.key},
        });
        final env = await TestEnv.create(loggedIn: true, api: _ScriptedApi((_) => scan));
        await runScan(tester, env);
        final card = keyed('advice-crop-card');
        for (final icon in [AppIcons.warning, AppIcons.danger, AppIcons.tick]) {
          expect(
            find.descendant(of: card, matching: find.byIcon(icon)),
            findsNothing,
            reason: '${entry.key} $icon',
          );
        }
        final semantics = tester.ensureSemantics();
        expect(tester.getSemantics(keyed('severity-${entry.key}')).label, startsWith('${entry.value}.'));
        semantics.dispose();
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  group('the leaf is not identified', () {
    testWidgets('confirm_crop: no question, no crop grid: "I cannot identify this leaf", another photo', (
      tester,
    ) async {
      final env = await envFor(MockScanScenario.confirmCrop, language: 'en');
      await runScan(tester, env);
      expect(find.text('I cannot identify this leaf'), findsOneWidget);
      expect(keyed('retake-camera'), findsOneWidget);
      expect(find.descendant(of: keyed('retake-issue'), matching: find.byIcon(AppIcons.leaf)), findsOneWidget);
      expect(keyed('crop-yes'), findsNothing);
      expect(keyed('crop-no'), findsNothing);
      expect(keyed('crop-apple'), findsNothing);
      expect(env.voice.spokenTexts, [
        'I cannot identify this leaf. Please give me another photo. Show one leaf, close up, in daylight.',
      ]);
      expect(env.voice.spokenIds, ['scan_retake_tap']);
      expectBigTouchTargets(tester);

      env.voice.clear();
      await tapKey(tester, 'retake-camera');
      expect(keyed('camera-button'), findsOneWidget);
      expect(env.voice.spokenIds.first, 'scan_open_camera');
    });

    testWidgets('a crop the server could not name at all says the same, in Hindi too', (tester) async {
      final unknown = ScanOut.fromJson({
        ...MockData.needsExpertScan('scan-1').toJson(),
        'crop': const CropOut(unknown: true, confidence: 0.1).toJson(),
      });
      final env = await TestEnv.create(loggedIn: true, api: _ScriptedApi((_) => unknown));
      await runScan(tester, env);
      expect(find.text('इस पत्ती की पहचान नहीं हो पाई'), findsOneWidget);
      expect(keyed('retake-camera'), findsOneWidget);
      expect(keyed('ask-expert'), findsNothing);
    });

    testWidgets('a leaf of a known crop that the server is unsure about still goes to the expert', (tester) async {
      final env = await envFor(MockScanScenario.needsExpert);
      await runScan(tester, env);
      expect(keyed('expert-icon-needs_expert'), findsOneWidget);
      expect(keyed('retake-camera'), findsNothing);
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

  testWidgets('the whole mock script, in order: not identified, advice, blurry, expert, no data, no disease', (
    tester,
  ) async {
    final env = await TestEnv.create(loggedIn: true);
    useSmallPhone(tester);
    await pumpApp(tester, env, location: '/home');
    const expected = [
      'retake-camera',
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
      await tester.tap(find.byIcon(AppIcons.back));
      await tester.pumpAndSettle();
      expect(keyed('home-scan'), findsOneWidget, reason: 'back arrow returns to the home screen');
    }
    expect(env.voice.unknownIds, isEmpty);
  });
}
