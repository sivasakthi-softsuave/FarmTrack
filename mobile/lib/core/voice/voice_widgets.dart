import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/big_buttons.dart';
import '../widgets/design.dart';
import 'speak_on_enter.dart';
import 'voice_service.dart';

/// The mockup's `.ibtn.glass`: a white circle at 14 % on the dark green of the Home header and on the camera.
const glassButtonColor = Color(0x24FFFFFF);

/// The one voice button of every screen (the top bar, the Home header, the camera): the speaker, with a mute and an unmute in it.
///
/// While the voice is on it shows the speaker (a ring round it while this screen is speaking) and one tap silences the voice at
/// once and keeps the app quiet on every screen until it is tapped again (the words still show, see [VoiceCaption]). While the
/// voice is off it shows the crossed-out speaker in red, and a tap turns the voice on and plays the screen's speech again, so the
/// farmer hears that it is back. [onDark] is for the deep-green Home header and the camera; [diameter] draws the circle smaller
/// (the tap area stays 56 dp).
class VoiceButton extends ConsumerWidget {
  const VoiceButton({super.key, this.onDark = false, this.diameter});

  final bool onDark;
  final double? diameter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = VoiceSession.maybeOf(context);
    final voice = ref.watch(voiceServiceProvider);
    final muted = ref.watch(settingsProvider.select((s) => s.muted));
    final t = ref.watch(stringsProvider);
    final Color fill;
    final Color pict;
    if (muted) {
      fill = onDark ? Colors.white : AppColors.redSoft;
      pict = AppColors.red;
    } else {
      fill = onDark ? glassButtonColor : AppColors.greenSoft;
      pict = onDark ? Colors.white : AppColors.green;
    }
    return ValueListenableBuilder<VoiceState>(
      valueListenable: voice.state,
      builder: (context, state, _) {
        final speaking = state.speaking && !muted && session != null && state.owner == session.owner;
        return KeyedSubtree(
          key: const ValueKey('voice-button'),
          child: BigIconButton(
            icon: muted ? AppIcons.noVoice : AppIcons.speaker,
            semanticLabel: muted ? t('a11y_unmute') : t('a11y_mute'),
            color: fill,
            foreground: pict,
            size: Dimens.minTouch,
            diameter: diameter,
            ringColor: speaking ? pict : null,
            onPressed: () async {
              final notifier = ref.read(settingsProvider.notifier);
              if (muted) {
                await notifier.setMuted(on: false);
                await session?.replay();
              } else {
                await notifier.setMuted(on: true);
                await voice.stop();
              }
            },
          ),
        );
      },
    );
  }
}

/// The sentence being spoken, floating over the content while it is spoken (switch off in settings): the mockup's dark
/// `.caption` with its breathing wave. Two lines to start with; a tap on the words opens all of it and a second tap
/// closes it again; the cross hides it until the next sentence. Shown only on the screen that spoke it. While the voice is
/// muted it still shows each sentence for its reading time.
class VoiceCaption extends ConsumerStatefulWidget {
  const VoiceCaption({super.key, this.topGap = 0});

  /// Space above the bubble while it shows (the caption sits under a floating button on some screens).
  final double topGap;

  @override
  ConsumerState<VoiceCaption> createState() => _VoiceCaptionState();
}

class _VoiceCaptionState extends ConsumerState<VoiceCaption> {
  bool _open = false;
  String? _lastText;
  String? _dismissedText;

  @override
  Widget build(BuildContext context) {
    final session = VoiceSession.maybeOf(context);
    final enabled = ref.watch(settingsProvider.select((s) => s.captions));
    if (!enabled || session == null) return const SizedBox.shrink();
    final voice = ref.watch(voiceServiceProvider);
    final t = ref.watch(stringsProvider);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.3;
    return ValueListenableBuilder<VoiceState>(
      valueListenable: voice.state,
      builder: (context, state, _) {
        final text = state.owner == session.owner ? state.caption : null;
        // Only while it is being spoken: afterwards the screen has the whole width and height again.
        if (text == null || text.isEmpty || !state.speaking) return const SizedBox.shrink();
        // A new sentence starts closed and visible again.
        if (text != _lastText) {
          _lastText = text;
          _open = false;
          _dismissedText = null;
        }
        if (_dismissedText == text) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.only(top: widget.topGap),
          child: Semantics(
            container: true,
            label: text,
            excludeSemantics: true,
            // A dark bubble over the light screen: it reads as "what the phone is saying", apart from the content.
            child: DecoratedBox(
              key: const ValueKey('voice-caption'),
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(color: Color(0x38000000), blurRadius: 24, offset: Offset(0, 8))],
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: Dimens.ibtn, maxHeight: maxHeight),
                child: Row(
                  children: [
                    // A plain gesture, not a button: opening the caption is a convenience, the screen never depends on it.
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _open = !_open),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 11, 0, 11),
                          child: Row(
                            crossAxisAlignment: _open ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                            children: [
                              Padding(
                                padding: EdgeInsets.only(top: _open ? 2 : 0),
                                child: const VoiceWave(),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _open
                                    ? SingleChildScrollView(child: Text(text, style: _captionStyle))
                                    : Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: _captionStyle),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: t('a11y_dismiss'),
                      onTap: () => setState(() => _dismissedText = text),
                      excludeSemantics: true,
                      child: GestureDetector(
                        key: const ValueKey('voice-caption-close'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _dismissedText = text),
                        child: const SizedBox(
                          width: Dimens.ibtn,
                          height: Dimens.ibtn,
                          child: Icon(AppIcons.cross, size: 20, color: Color(0xB3FFFFFF)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// `.caption`: 15 px on 1.35, white on the ink bubble.
const _captionStyle = TextStyle(fontSize: 15, height: 1.35, color: Colors.white);

/// Shown when this phone has no voice for the farmer's language: the words stay readable on screen.
class VoiceMissingBanner extends ConsumerWidget {
  const VoiceMissingBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voice = ref.watch(voiceServiceProvider);
    final lang = ref.watch(languageProvider);
    final t = ref.watch(stringsProvider);
    return ValueListenableBuilder<VoiceState>(
      valueListenable: voice.state,
      builder: (context, state, _) {
        if (!state.missingVoices.contains(lang)) return const SizedBox.shrink();
        return Container(
          key: const ValueKey('voice-missing'),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: AppDecor.tinted(AppColors.amberSoft, line: AppColors.amberLine, radius: 16),
          child: Row(
            children: [
              const Icon(AppIcons.noVoice, size: 28, color: AppColors.amberDark),
              const SizedBox(width: 12),
              Expanded(child: Text(t('voice_missing'), style: Theme.of(context).textTheme.bodyMedium)),
            ],
          ),
        );
      },
    );
  }
}
