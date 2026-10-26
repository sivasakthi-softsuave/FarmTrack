import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../theme/app_theme.dart';
import '../voice/speak_on_enter.dart';
import '../voice/utterance.dart';
import '../voice/voice_widgets.dart';
import 'big_buttons.dart';
import 'demo_clock_banner.dart';

/// The frame of every screen, kept as thin as possible so the content is the main thing: one slim bar on top (back
/// arrow, an optional title, the screen's small buttons, the speaker), the content, and at the bottom only the screen's
/// one main action on a white strip. The spoken sentence floats over the content as a dark caption (tap for all of it)
/// instead of taking a footer. It speaks [script] when the screen appears.
///
/// With [brandHeader] the top bar is the deep-green Home header: [title] and [subtitle] in white, no back arrow.
class VoiceScaffold extends ConsumerWidget {
  const VoiceScaffold({
    super.key,
    required this.script,
    required this.body,
    this.replayScript,
    this.owner,
    this.restartKey,
    this.speakEnabled = true,
    this.bottomRight,
    this.topRight = const [],
    this.showBack = true,
    this.onBack,
    this.scrollable = true,
    this.showCaption = true,
    this.title,
    this.subtitle,
    this.brandHeader = false,
  });

  /// What to say when the screen opens (and when the speaker button is tapped).
  final List<Utterance> script;
  final Widget body;

  /// What the speaker button plays, when it differs from [script].
  final List<Utterance>? replayScript;

  /// The screen's speech identity (see [SpeakOnEnter.owner]).
  final Object? owner;

  /// Change it to speak the script again while the screen stays open.
  final Object? restartKey;
  final bool speakEnabled;

  /// The screen's one main action, bottom-right. Its strip is the only thing under the content.
  final Widget? bottomRight;

  /// Small buttons at the top, next to the speaker (settings, alerts).
  final List<Widget> topRight;
  final bool showBack;
  final VoidCallback? onBack;

  /// Wrap [body] in a scroll view (needed at large text sizes). Set false for bodies that fill the space.
  final bool scrollable;

  /// Show the spoken sentence as a caption. Turn it off when the screen already shows that text itself (an answer).
  final bool showCaption;

  /// A short name in the top bar (one line; it shrinks before it wraps).
  final String? title;

  /// A second, smaller line under [title] (only in the [brandHeader]).
  final String? subtitle;
  final bool brandHeader;

  /// Tallest the main action gets; a bigger button, or one with a word under it, shrinks to fit.
  static const actionHeight = 76.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final canGoBack = !brandHeader && showBack && (onBack != null || Navigator.of(context).canPop());
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final action = bottomRight;
    return PopScope(
      // With an explicit [onBack] the phone's own back button does the same as the arrow on screen.
      canPop: onBack == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onBack?.call();
      },
      child: Scaffold(
        body: SpeakOnEnter(
          script: script,
          replayScript: replayScript,
          owner: owner,
          restartKey: restartKey,
          enabled: speakEnabled,
          child: Column(
            children: [
              if (brandHeader)
                _BrandHeader(title: title, subtitle: subtitle, actions: topRight)
              else
                _TopBar(
                  title: title,
                  actions: topRight,
                  back: canGoBack
                      ? BigIconButton(
                          icon: AppIcons.back,
                          semanticLabel: t('a11y_back'),
                          color: AppColors.neutralSoft,
                          foreground: AppColors.ink,
                          size: Dimens.minTouch,
                          onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                        )
                      : null,
                ),
              Expanded(
                child: SafeArea(
                  top: false,
                  bottom: action == null,
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(Dimens.gutter, 8, Dimens.gutter, 0),
                        child: Column(
                          children: [
                            if (!keyboardOpen) const VoiceMissingBanner(),
                            Expanded(
                              child: scrollable ? _ScrollingBody(captionRoom: !keyboardOpen, child: body) : body,
                            ),
                          ],
                        ),
                      ),
                      // Floats over the lowest part of the content, just above the action strip; it makes room for
                      // the fields while the keyboard is up.
                      if (showCaption && !keyboardOpen)
                        const Positioned(left: Dimens.gutter, right: Dimens.gutter, bottom: 10, child: VoiceCaption()),
                    ],
                  ),
                ),
              ),
              if (action != null)
                DecoratedBox(
                  decoration: const BoxDecoration(
                    color: AppColors.card,
                    border: Border(top: BorderSide(color: AppColors.line)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(Dimens.gutter, 6, Dimens.gutter, 8),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: ConstrainedBox(
                          // A little smaller while the keyboard is up: the fields need the room.
                          constraints: BoxConstraints(maxHeight: keyboardOpen ? actionHeight - 12 : actionHeight),
                          child: FittedBox(fit: BoxFit.scaleDown, child: action),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The white bar on top of an ordinary screen: back arrow, title, the screen's own buttons, the speaker.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.actions, required this.back});

  final String? title;
  final List<Widget> actions;
  final Widget? back;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.dark,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Thin strip while the server runs on a demo clock. Never spoken.
            const DemoClockBanner(),
            // As tall as the speaker with its "speaking" ring (56 + 8), so no button is squeezed.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                height: Dimens.minTouch + 8,
                child: Row(children: _items(context)),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  List<Widget> _items(BuildContext context) {
    final name = title ?? '';
    // The screen's own buttons shrink together if the phone is narrow; never an overflow.
    final buttons = Align(
      alignment: Alignment.centerRight,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final w in actions) ...[w, const SizedBox(width: 8)],
          ],
        ),
      ),
    );
    return [
      ?back,
      if (name.isNotEmpty)
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: back == null ? 4 : 12, right: 8),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(name, maxLines: 1, style: Theme.of(context).textTheme.titleLarge),
            ),
          ),
        ),
      if (actions.isEmpty && name.isEmpty) const Spacer(),
      if (actions.isNotEmpty) name.isEmpty ? Expanded(child: buttons) : Flexible(child: buttons),
      const SpeakerButton(),
    ];
  }
}

/// The deep-green Home header: a greeting and the village in white, the screen's buttons and the speaker on the right.
class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.title, required this.subtitle, required this.actions});

  final String? title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final name = title ?? '';
    final place = subtitle ?? '';
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: _decorated(theme, name, place),
    );
  }

  Widget _decorated(TextTheme theme, String name, String place) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.brand,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const DemoClockBanner(),
            Padding(
              padding: const EdgeInsets.fromLTRB(Dimens.gutter, 8, 12, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (name.isNotEmpty)
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              name,
                              key: const ValueKey('home-greeting'),
                              maxLines: 1,
                              style: theme.titleLarge?.copyWith(color: Colors.white),
                            ),
                          ),
                        if (place.isNotEmpty)
                          Text(
                            place,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.bodyMedium?.copyWith(fontSize: 14, color: const Color(0xFFD7E8DC)),
                          ),
                      ],
                    ),
                  ),
                  if (actions.isNotEmpty)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final w in actions) ...[w, const SizedBox(width: 8)],
                        ],
                      ),
                    ),
                  const SpeakerButton(onDark: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScrollingBody extends StatelessWidget {
  const _ScrollingBody({required this.child, required this.captionRoom});

  final Widget child;

  /// Leave room under the last item for the floating caption (not while the keyboard is up: there is no caption then).
  final bool captionRoom;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final room = captionRoom ? 64.0 : 8.0;
      return SingleChildScrollView(
        padding: EdgeInsets.only(bottom: room),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: (constraints.maxHeight - room).clamp(0.0, double.infinity)),
          child: Align(alignment: Alignment.center, child: child),
        ),
      );
    },
  );
}
