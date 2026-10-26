import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/big_buttons.dart';
import 'speak_on_enter.dart';
import 'voice_service.dart';

/// The speaker picture, always the right-most button of the top bar. Plays the screen's speech again; a green ring
/// shows while this screen is speaking. [onDark] is for the deep-green Home header.
class SpeakerButton extends ConsumerWidget {
  const SpeakerButton({super.key, this.onDark = false});

  final bool onDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = VoiceSession.maybeOf(context);
    final voice = ref.watch(voiceServiceProvider);
    final t = ref.watch(stringsProvider);
    return ValueListenableBuilder<VoiceState>(
      valueListenable: voice.state,
      builder: (context, state, _) {
        final speaking = state.speaking && session != null && state.owner == session.owner;
        final ring = onDark ? Colors.white : AppColors.green;
        return Container(
          key: const ValueKey('speaker-button'),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: speaking ? ring : Colors.transparent, width: 2),
          ),
          child: BigIconButton(
            icon: AppIcons.speaker,
            semanticLabel: t('a11y_listen'),
            color: onDark ? Colors.white : AppColors.greenSoft,
            foreground: AppColors.green,
            size: Dimens.minTouch,
            onPressed: session == null ? null : () => session.replay(),
          ),
        );
      },
    );
  }
}

/// The sentence being spoken, floating over the content while it is spoken (switch off in settings). One line to start
/// with; a tap opens all of it and a second tap closes it again. Shown only on the screen that spoke it.
class VoiceCaption extends ConsumerStatefulWidget {
  const VoiceCaption({super.key});

  @override
  ConsumerState<VoiceCaption> createState() => _VoiceCaptionState();
}

class _VoiceCaptionState extends ConsumerState<VoiceCaption> {
  bool _open = false;
  String? _lastText;

  @override
  Widget build(BuildContext context) {
    final session = VoiceSession.maybeOf(context);
    final enabled = ref.watch(settingsProvider.select((s) => s.captions));
    if (!enabled || session == null) return const SizedBox.shrink();
    final voice = ref.watch(voiceServiceProvider);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.3;
    return ValueListenableBuilder<VoiceState>(
      valueListenable: voice.state,
      builder: (context, state, _) {
        final text = state.owner == session.owner ? state.caption : null;
        // Only while it is being spoken: afterwards the screen has the whole width and height again.
        if (text == null || text.isEmpty || !state.speaking) return const SizedBox.shrink();
        // A new sentence starts closed again.
        if (text != _lastText) {
          _lastText = text;
          _open = false;
        }
        return Semantics(
          container: true,
          label: text,
          excludeSemantics: true,
          // A dark bubble over the light screen: it reads as "what the phone is saying", apart from the content.
          child: Material(
            key: const ValueKey('voice-caption'),
            color: AppColors.ink,
            elevation: 6,
            shadowColor: AppColors.shadow,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            // A plain gesture, not a button: opening the caption is a convenience, the screen never depends on it.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _open = !_open),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    crossAxisAlignment: _open ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                    children: [
                      const Icon(AppIcons.captions, size: 22, color: _captionAccent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _open
                            ? SingleChildScrollView(child: Text(text, style: _captionStyle(context)))
                            : Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: _captionStyle(context)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  TextStyle? _captionStyle(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white);
}

/// Light green of the caption picture on the dark bubble (8:1 on [AppColors.ink]).
const _captionAccent = Color(0xFF7CD992);

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
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: AppColors.amberSoft, borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              const Icon(AppIcons.noVoice, size: 28),
              const SizedBox(width: 12),
              Expanded(child: Text(t('voice_missing'), style: Theme.of(context).textTheme.bodyMedium)),
            ],
          ),
        );
      },
    );
  }
}
