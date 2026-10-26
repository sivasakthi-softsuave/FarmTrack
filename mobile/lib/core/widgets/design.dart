import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/haptics.dart';

/// The building blocks of the approved UI mockup (`docs/design/ui-redesign-mockup.html`), named after its CSS classes so a
/// screen can be written straight from the mockup: `.card`, `.label`, `.pill`, `.dot`, `.btn`, the toggle.
///
/// Sizes are the mockup's, in dp (the mockup's px at 390 x 844).

/// `.card`: a white card, radius 20, padding 16, soft shadow. [flat] drops the shadow (the mockup's tinted cards), [color]
/// sets the fill, [line] adds a one pixel border (amber warnings use [AppColors.amberLine]).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.color = AppColors.card,
    this.flat = false,
    this.line,
    this.padding = const EdgeInsets.all(16),
    this.radius = Dimens.radius,
    this.onTap,
    this.semanticLabel,
  });

  final Widget child;
  final Color color;
  final bool flat;
  final Color? line;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Makes the whole card a button.
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: line == null ? null : Border.all(color: line!),
      boxShadow: flat ? null : AppDecor.shadows,
    );
    final content = Padding(padding: padding, child: child);
    if (onTap == null) return DecoratedBox(decoration: decoration, child: content);
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: DecoratedBox(
        decoration: decoration,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: () {
              Haptics.tap();
              onTap!();
            },
            child: content,
          ),
        ),
      ),
    );
  }
}

/// `.label`: the small heading above a group of cards. Capitals and letter spacing in Latin scripts; in Devanagari
/// (`hindi`) neither (letter spacing breaks the conjuncts) and one point bigger, as the mockup's Hindi screens do.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.hindi = false});

  final String text;
  final bool hindi;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
    child: Text(hindi ? text : text.toUpperCase(), style: hindi ? AppText.labelHindi : AppText.label),
  );
}

/// Whether [text] is written in Devanagari (the mockup treats its labels differently).
bool isDevanagari(String text) => RegExp('[ऀ-ॿ]').hasMatch(text);

/// `.pill`: a small rounded tag (a state, a count, a name). Height 30 unless [height] says otherwise.
class AppPill extends StatelessWidget {
  const AppPill(
    this.text, {
    super.key,
    required this.background,
    required this.foreground,
    this.icon,
    this.height = 30,
    this.fontSize = 13,
    this.horizontal = 12,
  });

  final String text;
  final Color background;
  final Color foreground;
  final IconData? icon;
  final double height;
  final double fontSize;
  final double horizontal;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    padding: EdgeInsets.symmetric(horizontal: horizontal),
    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 20, color: foreground), const SizedBox(width: 6)],
        Text(
          text,
          maxLines: 1,
          style: AppText.pill.copyWith(fontSize: fontSize, color: foreground),
        ),
      ],
    ),
  );
}

/// `.dot`: a tinted square (radius 14) or circle that holds a picture: the leading picture of a card.
class IconDot extends StatelessWidget {
  const IconDot(
    this.icon, {
    super.key,
    required this.background,
    required this.foreground,
    this.size = 44,
    this.round = false,
    this.iconSize = 24,
    this.shadow = false,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final double size;
  final bool round;
  final double iconSize;

  /// The green glow under the big round green buttons.
  final bool shadow;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: background,
      shape: round ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: round ? null : BorderRadius.circular(Dimens.radiusSmall),
      boxShadow: shadow
          ? [BoxShadow(color: AppColors.green.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))]
          : null,
    ),
    child: Icon(icon, size: iconSize, color: foreground),
  );
}

/// `.btn`: a main button, 60 high, radius 18, 18 / 700 text, a 30 px picture. [AppButtonStyle.primary] is the green one
/// with its glow, [outline] the white one with a 2 px line, [danger] the red outline ("Log out"). [square] is the 60 x 60
/// picture-only button (`.btn.sq`). In a row, wrap it in `Expanded`.
enum AppButtonStyle { primary, outline, danger }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.onPressed,
    required this.semanticLabel,
    this.label,
    this.icon,
    this.style = AppButtonStyle.primary,
    this.square = false,
    this.height = Dimens.actionButton,
    this.fontSize = 18,
    this.bold = true,
    this.foreground,
    this.minWidth,
    this.horizontalPadding = 16,
  });

  final VoidCallback? onPressed;
  final String semanticLabel;
  final String? label;
  final IconData? icon;
  final AppButtonStyle style;
  final bool square;
  final double height;
  final double fontSize;

  /// Use the 2.6 wide tick / cross of the green buttons.
  final bool bold;

  /// Overrides the text and picture colour (the blue "More" button).
  final Color? foreground;
  final double? minWidth;

  /// Space at the left and right of the picture and word (22 on the floating "Write a spray" button).
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final primary = style == AppButtonStyle.primary;
    final fg =
        foreground ??
        switch (style) {
          AppButtonStyle.primary => Colors.white,
          AppButtonStyle.outline => AppColors.ink,
          AppButtonStyle.danger => AppColors.red,
        };
    final fill = !enabled ? AppColors.line : (primary ? AppColors.green : AppColors.card);
    final border = switch (style) {
      AppButtonStyle.primary => null,
      AppButtonStyle.outline => Border.all(color: AppColors.line, width: 2),
      AppButtonStyle.danger => Border.all(color: AppColors.redLine, width: 2),
    };
    final shown = enabled ? fg : AppColors.inkSoft;
    final picture = icon == null
        ? null
        : Icon(icon, size: square || label == null ? 24 : (primary ? 30 : 24), color: shown);
    final inner = square || label == null
        ? Center(child: picture)
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (picture != null) ...[picture, const SizedBox(width: 10)],
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label!,
                    maxLines: 1,
                    style: AppText.button.copyWith(fontSize: fontSize, color: shown),
                  ),
                ),
              ),
            ],
          );
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        width: square ? height : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(18),
            border: enabled ? border : null,
            boxShadow: primary && enabled
                ? [
                    BoxShadow(
                      color: AppColors.green.withValues(alpha: 0.28),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: enabled
                  ? () {
                      Haptics.tap();
                      onPressed!();
                    }
                  : null,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: square ? 0 : horizontalPadding),
                child: inner,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The toggle of the mockup's settings: a 52 x 32 track (green when on) with a 24 px white knob.
class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, required this.onChanged, required this.semanticLabel});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      enabled: onChanged != null,
      label: semanticLabel,
      excludeSemantics: true,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onChanged == null
            ? null
            : () {
                Haptics.tap();
                onChanged!(!value);
              },
        child: SizedBox(
          width: 72,
          height: Dimens.minTouch,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 52,
              height: 32,
              decoration: BoxDecoration(
                color: value ? AppColors.green : AppColors.dashed,
                borderRadius: BorderRadius.circular(16),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 150),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.all(4),
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.wave`: four green bars that breathe while the app speaks (still when the phone asks for no animations). It breathes
/// for [seconds] and then rests at full height, so a screen that shows it can always settle (`pumpAndSettle` in tests).
class VoiceWave extends StatefulWidget {
  const VoiceWave({super.key, this.color = const Color(0xFF7CD992), this.animate = true, this.seconds = 12});

  final Color color;
  final bool animate;
  final int seconds;

  @override
  State<VoiceWave> createState() => _VoiceWaveState();
}

class _VoiceWaveState extends State<VoiceWave> with SingleTickerProviderStateMixin {
  static final _underTest = Platform.environment.containsKey('FLUTTER_TEST');

  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 1));
  bool _started = false;

  static const _heights = [8.0, 16.0, 11.0, 18.0];
  static const _delays = [0.0, 0.15, 0.3, 0.45];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Still under `flutter test` too (as the Home field summary is): a moving wave would advance the test clock inside
    // `pumpAndSettle` and fire the offline retry timers early.
    final still = !widget.animate || MediaQuery.disableAnimationsOf(context) || _underTest;
    if (still) {
      _c.stop();
    } else if (!_c.isAnimating && !_started) {
      _started = true;
      _c.repeat(count: widget.seconds);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: 20,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Container(
                width: 3,
                height: _heights[i] * _scale(i),
                decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(2)),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  // The mockup's keyframe: full size, down to 45 % in the middle of each second, back again; the bars start 0.15 s apart.
  double _scale(int i) {
    if (!_c.isAnimating) return 1;
    final t = (_c.value - _delays[i]) % 1.0;
    final tri = t < 0.5 ? t * 2 : (1 - t) * 2; // 0 .. 1 .. 0
    return 1 - 0.55 * tri;
  }
}
