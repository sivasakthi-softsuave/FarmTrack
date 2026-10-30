import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmtrack/core/providers.dart';
import 'package:farmtrack/core/settings/app_settings.dart';
import 'package:farmtrack/core/theme/app_theme.dart';
import 'package:farmtrack/core/voice/utterance.dart';
import 'package:farmtrack/core/widgets/voice_scaffold.dart';

import 'support/finders.dart';
import 'support/harness.dart';

/// The voice button: the one speaker in the top bar of every screen, for the voice off and on. One tap silences the voice at
/// once and keeps the app quiet (the choice is saved); a second tap turns the voice on and plays the screen's speech again.
void main() {
  Future<TestEnv> open(WidgetTester tester) async {
    useSmallPhone(tester, size: const Size(390, 844));
    final env = await TestEnv.create();
    await tester.pumpWidget(
      env.wrap(VoiceScaffold(script: promptList(const ['welcome']), body: const SizedBox(height: 40))),
    );
    await tester.pump();
    return env;
  }

  bool muted(WidgetTester tester) => containerOf(tester).read(settingsProvider).muted;

  Finder pictureIn(IconData icon, {Color? colored}) => find.descendant(
    of: keyed('voice-button'),
    matching: find.byWidgetPredicate((w) => w is Icon && w.icon == icon && (colored == null || w.color == colored)),
  );

  testWidgets('there is one voice button, a speaker, and the voice starts on', (tester) async {
    await open(tester);
    expect(keyed('voice-button'), findsOneWidget);
    expect(find.byKey(const ValueKey('speaker-button')), findsNothing, reason: 'no separate listen button');
    expect(find.byKey(const ValueKey('mute-button')), findsNothing, reason: 'no separate mute button');
    expect(muted(tester), isFalse);
    expect(pictureIn(AppIcons.speaker), findsOneWidget);
    expect(pictureIn(AppIcons.noVoice), findsNothing);
    final box = tester.getRect(keyed('voice-button'));
    expect(box.size, const Size(56, 56), reason: 'the 56 dp tap area');
    expect(box.right, 390 - 12, reason: 'the right-most button of the bar');
    expect(find.bySemanticsLabel('Mute the voice'), findsNothing, reason: 'labels are in Hindi by default');
  });

  testWidgets('a tap mutes: the voice is cut at once, the choice is saved and the button says so', (tester) async {
    final env = await open(tester);
    expect(env.voice.stopCalls, 0);
    await tester.tap(keyed('voice-button'));
    await tester.pump();
    expect(muted(tester), isTrue);
    expect(env.voice.stopCalls, 1, reason: 'what is being spoken stops immediately');
    expect((await SharedPreferences.getInstance()).getBool('voice_muted'), isTrue, reason: 'it survives a restart');
    expect(pictureIn(AppIcons.noVoice, colored: AppColors.red), findsOneWidget, reason: 'the crossed-out speaker, red');
    expect(pictureIn(AppIcons.speaker), findsNothing);
  });

  testWidgets('a second tap turns the voice on and plays the screen speech again', (tester) async {
    final env = await open(tester);
    await tester.tap(keyed('voice-button'));
    await tester.pump();
    final callsWhileMuted = env.voice.calls.length;
    await tester.tap(keyed('voice-button'));
    await tester.pump();
    expect(muted(tester), isFalse);
    expect((await SharedPreferences.getInstance()).getBool('voice_muted'), isFalse);
    expect(env.voice.calls.length, callsWhileMuted + 1, reason: 'the farmer hears that the voice is back');
    expect(env.voice.spokenIds.last, 'welcome');
    expect(pictureIn(AppIcons.speaker), findsOneWidget, reason: 'the speaker is back');
  });

  testWidgets('the label says what a tap does: mute while the voice is on, turn on while it is off', (tester) async {
    await open(tester);
    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel('आवाज़ बंद करें'), findsOneWidget);
    await tester.tap(keyed('voice-button'));
    await tester.pump();
    expect(find.bySemanticsLabel('आवाज़ बंद है। चालू करें'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the muted state is read from the saved settings at start', (tester) async {
    SharedPreferences.setMockInitialValues({'voice_muted': true, 'language': 'hi'});
    final prefs = await SharedPreferences.getInstance();
    expect(SettingsStore(prefs).load().muted, isTrue);
    expect(const AppSettings().muted, isFalse, reason: 'the voice is on by default');
  });
}
