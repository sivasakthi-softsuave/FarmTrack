import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_resources.dart';
import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/voice/speak_on_enter.dart';
import '../../core/voice/utterance.dart';
import '../../core/widgets/voice_scaffold.dart';
import '../auth/auth_widgets.dart';

/// One big button per language, labelled in its own script with its letter in a round badge. Tapping plays that
/// language's name in its own voice, applies the choice, and calls [onChosen].
///
/// The look is the mockup's segmented choice of Settings (`.seg`): white with a 2 px line, the chosen one green on a soft
/// green with a green badge. [compact] is that exact size (56 high); the first launch gets the same buttons, bigger.
class LanguageButtons extends ConsumerStatefulWidget {
  const LanguageButtons({
    super.key,
    required this.onChosen,
    this.selected,
    this.speakChoice = true,
    this.compact = false,
  });

  final Future<void> Function(String code) onChosen;

  /// Highlights the current language (settings screen).
  final String? selected;
  final bool speakChoice;

  /// The 56 high segmented buttons side by side (settings), instead of big stacked ones (first launch).
  final bool compact;

  @override
  ConsumerState<LanguageButtons> createState() => _LanguageButtonsState();
}

class _LanguageButtonsState extends ConsumerState<LanguageButtons> {
  bool _busy = false;

  Future<void> _choose(LanguageInfo language) async {
    if (_busy) return;
    final owner = VoiceSession.maybeOf(context)?.owner;
    setState(() => _busy = true);
    try {
      await ref.read(settingsProvider.notifier).setLanguage(language.code);
      if (widget.speakChoice && language.promptId.isNotEmpty) {
        // Plays "Hindi." / "English." in that language's own voice before moving on.
        await ref.read(voiceServiceProvider).speak([
          PromptUtterance(language.promptId, lang: language.code),
        ], owner: owner);
      }
      await widget.onChosen(language.code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final resources = ref.watch(resourcesProvider);
    final tiles = [
      for (final language in resources.languages)
        _LanguageChoice(
          key: ValueKey('language-${language.code}'),
          language: language,
          selected: widget.selected == language.code,
          big: !widget.compact,
          onPressed: _busy ? null : () => _choose(language),
        ),
    ];
    final gap = widget.compact ? 8.0 : 12.0;
    // Two languages fit side by side in the compact (settings) layout; more are stacked, so the list can grow as data.
    if (widget.compact && tiles.length <= 2) {
      return Row(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[if (i > 0) SizedBox(width: gap), Expanded(child: tiles[i])],
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < tiles.length; i++) ...[if (i > 0) SizedBox(height: gap), tiles[i]],
      ],
    );
  }
}

/// One language button (`.seg button`): the letter badge, the name in its own script. The chosen one is green.
class _LanguageChoice extends StatelessWidget {
  const _LanguageChoice({
    super.key,
    required this.language,
    required this.selected,
    required this.big,
    required this.onPressed,
  });

  final LanguageInfo language;
  final bool selected;

  /// The first-launch size: 104 high with a 56 badge, instead of the segmented 56 / 32.
  final bool big;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(big ? Dimens.radius : Dimens.radiusSmall);
    final badge = big ? 56.0 : 32.0;
    final name = TextStyle(
      fontSize: big ? 28 : 15,
      fontWeight: big ? FontWeight.w800 : FontWeight.w700,
      color: selected ? AppColors.green : AppColors.ink,
    );
    return Semantics(
      button: true,
      selected: selected,
      enabled: onPressed != null,
      label: language.nativeName,
      excludeSemantics: true,
      child: SizedBox(
        height: big ? 104 : Dimens.minTouch,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? AppColors.greenSoft : AppColors.card,
            borderRadius: radius,
            border: Border.all(color: selected ? AppColors.green : AppColors.line, width: 2),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              onTap: onPressed == null
                  ? null
                  : () {
                      Haptics.tap();
                      onPressed!();
                    },
              child: Center(
                // Shrinks (never clips) at the biggest text sizes.
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // The chosen language is marked on its badge (the key is what the tests look for).
                        KeyedSubtree(
                          key: selected ? ValueKey('language-selected-${language.code}') : null,
                          child: Container(
                            key: ValueKey('language-badge-${language.code}'),
                            width: badge,
                            height: badge,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected ? AppColors.green : AppColors.neutralSoft,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              language.badgeText,
                              style: TextStyle(
                                fontSize: big ? 30 : 16,
                                fontWeight: big ? FontWeight.w800 : FontWeight.w700,
                                color: selected ? Colors.white : AppColors.ink,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: big ? 16 : 8),
                        Text(language.nativeName, style: name),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// First launch: speaks "choose your language" in Hindi, then in English.
class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resources = ref.watch(resourcesProvider);
    final t = ref.watch(stringsProvider);
    // The request in every language, the first one big and the others in grey under it (no language is chosen yet).
    final words = [for (final l in resources.languages) resources.t('language_choose', l.code)];
    return VoiceScaffold(
      showBack: false,
      flatTopBar: true,
      titleWidget: AuthLogo(name: t('app_name')),
      alignTop: true,
      bodyPadding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      // Every language says the sentence in its own voice, one after the other (hi then en).
      script: [for (final l in resources.languages) PromptUtterance('choose_language', lang: l.code)],
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const HillsPicture(),
          const SizedBox(height: 14),
          AuthHeading(title: words.first, subtitle: words.length > 1 ? words.skip(1).join('\n') : null),
          const SizedBox(height: 16),
          LanguageButtons(
            onChosen: (_) async {
              if (context.mounted) context.go(Routes.welcome);
            },
          ),
        ],
      ),
    );
  }
}
