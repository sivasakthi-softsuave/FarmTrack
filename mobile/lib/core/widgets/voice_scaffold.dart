import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../utils/haptics.dart';
import '../theme/app_theme.dart';
import '../voice/speak_on_enter.dart';
import '../voice/utterance.dart';
import '../voice/voice_widgets.dart';
import 'big_buttons.dart';
import 'demo_clock_banner.dart';

/// The frame of every screen, as in the approved mockup: one slim white bar on top (back arrow, the screen's name, its
/// own buttons and the voice button), the content, and at the bottom only the screen's one main action on a white strip
/// (or the navigation bar of the four main pages). The spoken sentence floats over the content as a dark caption (tap
/// for all of it) instead of taking a footer. It speaks [script] when the screen appears.
///
/// With [brandHeader] the top bar is the deep-green Home header: [title] and [subtitle] in white, no back arrow, the
/// voice button on the greeting's line, after [topRight]. With [bottomNav] (the four main pages) the navigation bar sits at the bottom and
/// [bottomRight] floats above it.
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
    this.titleWidget,
    this.subtitle,
    this.onSubtitleTap,
    this.subtitleLabel,
    this.avatar,
    this.brandHeader = false,
    this.flatTopBar = false,
    this.wideAction = false,
    this.bottomNav,
    this.alignTop = false,
    this.bodyPadding,
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

  /// The screen's one main action (or, with [wideAction], a row of them). Its strip is the only thing under the content.
  final Widget? bottomRight;

  /// Small buttons at the top, next to the voice button (settings, alerts).
  final List<Widget> topRight;
  final bool showBack;
  final VoidCallback? onBack;

  /// Wrap [body] in a scroll view (needed at large text sizes). Set false for bodies that fill the space.
  final bool scrollable;

  /// Show the spoken sentence as a caption. Turn it off when the screen already shows that text itself (an answer).
  final bool showCaption;

  /// A short name in the top bar (one line; it shrinks before it wraps).
  final String? title;

  /// Shown in the top bar instead of [title] (the login screen's logo).
  final Widget? titleWidget;

  /// A second, smaller line under [title] (only in the [brandHeader]).
  final String? subtitle;

  /// Makes the [subtitle] (the farmer's location on Home) a button: a pill with a pin and an arrow, a 56 dp touch target.
  final VoidCallback? onSubtitleTap;

  /// What a screen reader says for that button (default: the [subtitle]).
  final String? subtitleLabel;

  /// Initials in a round badge before the [brandHeader] title.
  final String? avatar;
  final bool brandHeader;

  /// The top bar without its white strip: it sits on the screen's own background.
  final bool flatTopBar;

  /// The main action takes the whole width of its strip (wide green button with a word, or a row of buttons).
  final bool wideAction;

  /// The navigation bar of the four main pages (see `AppBottomNav`).
  final Widget? bottomNav;

  /// Start the content at the top instead of centring it in the free space.
  final bool alignTop;

  /// Padding around the body (default: the mockup's 16 dp gutter at the sides and 8 dp on top).
  final EdgeInsets? bodyPadding;

  /// Tallest the main action gets (the mockup's 60 px button); a bigger button, or one with a word under it, shrinks to fit.
  static const actionHeight = Dimens.actionButton;

  /// Space between the bottom edge of the content and the floating caption (the mockup's 12 px above the bars).
  static const captionGap = 12.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final canGoBack = !brandHeader && showBack && (onBack != null || Navigator.of(context).canPop());
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final action = bottomRight;
    final nav = keyboardOpen ? null : bottomNav;
    // With the navigation bar the main action floats over the content instead of taking a strip.
    final floating = bottomNav != null;
    // A little smaller while the keyboard is up (the fields need the room), never below the 56 dp tap size.
    final maxAction = keyboardOpen ? Dimens.minTouch : actionHeight;
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
          child: Stack(
            children: [
              Column(
                children: [
                  if (brandHeader)
                    _BrandHeader(
                      title: title,
                      subtitle: subtitle,
                      onSubtitleTap: onSubtitleTap,
                      subtitleLabel: subtitleLabel,
                      avatar: avatar,
                      actions: topRight,
                    )
                  else
                    _TopBar(
                      title: title,
                      titleWidget: titleWidget,
                      flat: flatTopBar,
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
                      bottom: action == null && nav == null,
                      child: Stack(
                        children: [
                          // The green header reaches a little under the first card (Home).
                          if (brandHeader)
                            const Positioned(
                              left: 0,
                              right: 0,
                              top: 0,
                              height: _bandOverlap,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: AppColors.brand,
                                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
                                ),
                              ),
                            ),
                          Padding(
                            padding:
                                bodyPadding ??
                                EdgeInsets.fromLTRB(Dimens.gutter, brandHeader ? 0 : 8, Dimens.gutter, 0),
                            child: Column(
                              children: [
                                if (!keyboardOpen) const VoiceMissingBanner(),
                                Expanded(
                                  child: scrollable
                                      ? _ScrollingBody(
                                          captionRoom: !keyboardOpen,
                                          extraRoom: floating && action != null ? actionHeight + Dimens.navRise : 0,
                                          alignTop: alignTop || brandHeader,
                                          child: body,
                                        )
                                      : body,
                                ),
                              ],
                            ),
                          ),
                          // At the bottom of the content: the spoken sentence, with the screen's floating action just above
                          // it (the mockup's order). Both make room for the fields while the keyboard is up.
                          if (!keyboardOpen)
                            Positioned(
                              left: Dimens.gutter,
                              right: Dimens.gutter,
                              // A floating action sits above the camera circle of the bar, never under it.
                              bottom: captionGap + (floating && action != null ? Dimens.navRise : 0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (floating && action != null)
                                    Align(
                                      alignment: AlignmentDirectional.centerEnd,
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(maxHeight: maxAction),
                                        child: FittedBox(fit: BoxFit.scaleDown, child: action),
                                      ),
                                    ),
                                  if (showCaption) VoiceCaption(topGap: floating && action != null ? 8 : 0),
                                ],
                              ),
                            )
                          else if (floating && action != null)
                            Positioned(
                              right: Dimens.gutter,
                              bottom: 10 + Dimens.navRise,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(maxHeight: maxAction),
                                child: FittedBox(fit: BoxFit.scaleDown, child: action),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (action != null && !floating) _ActionStrip(wide: wideAction, maxHeight: maxAction, child: action),
                  // Room for the navigation bar, which is drawn over it (its camera circle rises above the bar).
                  if (nav != null) SizedBox(height: Dimens.nav + MediaQuery.paddingOf(context).bottom),
                ],
              ),
              if (nav != null) Positioned(left: 0, right: 0, bottom: 0, child: nav),
            ],
          ),
        ),
      ),
    );
  }

  /// How far the green of the Home header reaches under the first card (the mockup's -60 px margin).
  static const _bandOverlap = 60.0;
}

/// The white strip at the bottom that holds the screen's main action: padding 12 / 16 / 22, a hairline above it.
class _ActionStrip extends StatelessWidget {
  const _ActionStrip({required this.wide, required this.maxHeight, required this.child});

  final bool wide;
  final double maxHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Widget inner;
    if (wide) {
      inner = SizedBox(width: double.infinity, height: Dimens.actionButton, child: child);
    } else {
      // A little smaller while the keyboard is up: the fields need the room.
      inner = Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: FittedBox(fit: BoxFit.scaleDown, child: child),
        ),
      );
    }
    final inset = MediaQuery.paddingOf(context).bottom;
    return DecoratedBox(
      decoration: _stripDecoration,
      child: Padding(
        padding: EdgeInsets.fromLTRB(Dimens.gutter, 12, Dimens.gutter, math.max(22, inset + 10)),
        child: inner,
      ),
    );
  }
}

const _stripDecoration = BoxDecoration(
  color: AppColors.card,
  border: Border(top: BorderSide(color: AppColors.line)),
);
const _barDecoration = BoxDecoration(
  color: AppColors.card,
  border: Border(bottom: BorderSide(color: AppColors.line)),
);
const _flatDecoration = BoxDecoration(color: AppColors.paper);

/// The bar on top of an ordinary screen (`.topbar`): back arrow, the name in 20 / 700, the screen's own buttons and the
/// voice button. White with a hairline below it, or [flat] on the screen's own background.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.titleWidget,
    required this.flat,
    required this.actions,
    required this.back,
  });

  final String? title;
  final Widget? titleWidget;
  final bool flat;
  final List<Widget> actions;
  final Widget? back;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.dark,
    child: DecoratedBox(
      decoration: flat ? _flatDecoration : _barDecoration,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Thin strip while the server runs on a demo clock. Never spoken.
            const DemoClockBanner(),
            // The buttons are 48 wide inside 56 wide tap areas, so the row starts 4 dp inside the 16 dp gutter.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                height: Dimens.topBar,
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
    final custom = titleWidget;
    final hasTitle = custom != null || name.isNotEmpty;
    // The screen's own buttons shrink together if the phone is narrow; never an overflow.
    final buttons = Align(
      alignment: Alignment.centerRight,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(mainAxisSize: MainAxisSize.min, children: actions),
      ),
    );
    return [
      ?back,
      if (hasTitle)
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: 8, right: back == null && custom == null ? 8 : 4),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: custom ?? Text(name, maxLines: 1, style: AppText.title.copyWith(color: AppColors.ink)),
            ),
          ),
        ),
      if (actions.isEmpty && !hasTitle) const Spacer(),
      if (actions.isNotEmpty) hasTitle ? Flexible(child: buttons) : Expanded(child: buttons),
      const VoiceButton(),
    ];
  }
}

/// The deep-green Home header (`.home` header of the mockup): the initials in a glass circle, the greeting (20 / 700) with the
/// farmer's place under it (14, a little transparent), and at the right, in ONE line, the bell, the gear and the voice button as
/// small glass buttons. The buttons are drawn [Dimens.compactIbtn] wide (their tap areas stay 56 dp) so that three of them fit
/// beside the names; on a narrow phone the initials, which only decorate, give their room to the names.
class _BrandHeader extends StatelessWidget {
  const _BrandHeader({
    required this.title,
    required this.subtitle,
    required this.avatar,
    required this.actions,
    this.onSubtitleTap,
    this.subtitleLabel,
  });

  final String? title;
  final String? subtitle;
  final VoidCallback? onSubtitleTap;
  final String? subtitleLabel;
  final String? avatar;
  final List<Widget> actions;

  /// Narrower than this, the initials are left out.
  static const _avatarMinWidth = 380.0;

  @override
  Widget build(BuildContext context) {
    final name = title ?? '';
    final place = subtitle ?? '';
    final initials = avatar ?? '';
    final showAvatar = initials.isNotEmpty && MediaQuery.sizeOf(context).width >= _avatarMinWidth;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: ColoredBox(
        color: AppColors.brand,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const DemoClockBanner(),
              Padding(
                padding: const EdgeInsets.fromLTRB(Dimens.gutter, 10, 12, 8),
                child: Row(
                  children: [
                    if (showAvatar) ...[
                      ExcludeSemantics(
                        child: Container(
                          width: Dimens.ibtn,
                          height: Dimens.ibtn,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(color: Color(0x29FFFFFF), shape: BoxShape.circle),
                          child: Text(
                            initials,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(child: _names(name, place)),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ...actions,
                          const VoiceButton(onDark: true, diameter: Dimens.compactIbtn),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _names(String name, String place) => Column(
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
            style: AppText.title.copyWith(color: Colors.white, height: 1.3),
          ),
        ),
      if (place.isNotEmpty)
        onSubtitleTap == null
            ? Text(place, maxLines: 1, overflow: TextOverflow.ellipsis, style: _placeStyle)
            : _placeButton(place),
    ],
  );

  static const _placeStyle = TextStyle(fontSize: 14, color: Color(0xD9FFFFFF), height: 1.35);

  /// The location as a button: a glass pill (pin, the place, a small arrow) inside a 56 dp touch target. Touching it opens the
  /// place picker, where the farmer searches a name, uses the phone's position or touches the map.
  Widget _placeButton(String place) => LayoutBuilder(
    builder: (context, constraints) =>
        _placePill(context, place, _fitting(context, place, constraints.maxWidth - _pillChrome)),
  );

  /// What the pill takes besides its words: the padding (8 + 8), the pin (18 + 4) and the arrow (2 + 20).
  static const _pillChrome = 60.0;

  /// The most parts of [place] ("Kotgarh, Kumharsain, Shimla") that fit on one line in [maxWidth]: all of them if they fit, else
  /// fewer, but never fewer than the first (the village), which is cut with dots only if even that does not fit.
  static String _fitting(BuildContext context, String place, double maxWidth) {
    final parts = place.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    if (parts.length < 2) return place;
    final style = DefaultTextStyle.of(context).style.merge(_placeStyle);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    for (var count = parts.length; count > 1; count--) {
      final text = parts.take(count).join(', ');
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final fits = painter.width <= maxWidth;
      painter.dispose();
      if (fits) return text;
    }
    return parts.first;
  }

  Widget _placePill(BuildContext context, String place, String shown) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: Semantics(
      button: true,
      label: subtitleLabel ?? place,
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('home-place'),
        borderRadius: BorderRadius.circular(Dimens.minTouch / 2),
        onTap: () {
          Haptics.tap();
          onSubtitleTap!();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Dimens.minTouch, minWidth: Dimens.minTouch),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(color: const Color(0x29FFFFFF), borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.place_outlined, size: 18, color: Colors.white),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        shown,
                        key: const ValueKey('home-place-text'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _placeStyle,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.keyboard_arrow_down, size: 20, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ScrollingBody extends StatelessWidget {
  const _ScrollingBody({required this.child, required this.captionRoom, this.extraRoom = 0, this.alignTop = false});

  final Widget child;

  /// Leave room under the last item for the floating caption (not while the keyboard is up: there is no caption then).
  final bool captionRoom;

  /// More room under the last item for a floating action.
  final double extraRoom;
  final bool alignTop;

  /// What the caption bubble takes at the bottom: two lines of 15 / 1.35 at the farmer's text size, its padding and the
  /// gap under it.
  static double captionHeight(BuildContext context) {
    final lines = 2 * 15 * 1.35 * MediaQuery.textScalerOf(context).scale(1);
    return math.max(Dimens.ibtn, lines + 22) + VoiceScaffold.captionGap;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final room = (captionRoom ? captionHeight(context) : 8.0) + extraRoom;
      return SingleChildScrollView(
        padding: EdgeInsets.only(bottom: room),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: (constraints.maxHeight - room).clamp(0.0, double.infinity)),
          child: Align(alignment: alignTop ? Alignment.topCenter : Alignment.center, child: child),
        ),
      );
    },
  );
}
