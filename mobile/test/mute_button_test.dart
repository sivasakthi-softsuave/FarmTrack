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

/// The mute button: next to the speaker in the top bar of every screen. One tap silences the voice at once and keeps the
/// app quiet (the choice is saved); a second tap turns the voice on and plays the screen's speech again.
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

  testWidgets('the mute button sits next to the speaker and starts with the voice on', (tester) async {
    await open(tester);
    expect(keyed('mute-button'), findsOneWidget);
    expect(keyed('speaker-button'), findsOneWidget);
    expect(muted(tester), isFalse);
    final mute = tester.getRect(keyed('mute-button'));
    final speaker = tester.getRect(keyed('speaker-button'));
    expect(mute.right, lessThanOrEqualTo(speaker.left + 0.5), reason: 'mute is left of the speaker');
    expect(mute.size, speaker.size, reason: 'the same round button size');
    expect(find.bySemanticsLabel('Mute the voice'), findsNothing, reason: 'labels are in Hindi by default');
  });

  testWidgets('a tap mutes: the voice is cut at once, the choice is saved and the button says so', (tester) async {
    final env = await open(tester);
    expect(env.voice.stopCalls, 0);
    await tester.tap(keyed('mute-button'));
    await tester.pump();
    expect(muted(tester), isTrue);
    expect(env.voice.stopCalls, 1, reason: 'what is being spoken stops immediately');
    expect((await SharedPreferences.getInstance()).getBool('voice_muted'), isTrue, reason: 'it survives a restart');
    expect(
      find.descendant(
        of: keyed('mute-button'),
        matching: find.byWidgetPredicate((w) => w is Icon && w.icon == AppIcons.noVoice && w.color == AppColors.red),
      ),
      findsOneWidget,
      reason: 'the crossed-out speaker turns red while the voice is off',
    );
  });

  testWidgets('a second tap turns the voice on and plays the screen speech again', (tester) async {
    final env = await open(tester);
    await tester.tap(keyed('mute-button'));
    await tester.pump();
    final callsWhileMuted = env.voice.calls.length;
    await tester.tap(keyed('mute-button'));
    await tester.pump();
    expect(muted(tester), isFalse);
    expect((await SharedPreferences.getInstance()).getBool('voice_muted'), isFalse);
    expect(env.voice.calls.length, callsWhileMuted + 1, reason: 'the farmer hears that the voice is back');
    expect(env.voice.spokenIds.last, 'welcome');
  });

  testWidgets('the speaker while muted turns the voice on and plays: whoever asks to listen wants to hear', (
    tester,
  ) async {
    final env = await open(tester);
    await tester.tap(keyed('mute-button'));
    await tester.pump();
    final before = env.voice.calls.length;
    await tester.tap(keyed('speaker-button'));
    await tester.pump();
    expect(muted(tester), isFalse);
    expect(env.voice.calls.length, before + 1);
  });

  testWidgets('the muted state is read from the saved settings at start', (tester) async {
    SharedPreferences.setMockInitialValues({'voice_muted': true, 'language': 'hi'});
    final prefs = await SharedPreferences.getInstance();
    expect(SettingsStore(prefs).load().muted, isTrue);
    expect(const AppSettings().muted, isFalse, reason: 'the voice is on by default');
  });
}
