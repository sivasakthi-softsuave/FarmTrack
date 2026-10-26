import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/haptics.dart';

/// A round picture button. Primary actions use [Dimens.primary] (96 dp) or more; nothing is below 56 dp.
///
/// The mockup's `.ibtn`: at the smallest size ([Dimens.minTouch]) the circle is drawn [Dimens.ibtn] (48) wide, flat, in
/// the middle of its 56 dp tap area; bigger buttons fill their size and carry the green glow when they are coloured.
class BigIconButton extends StatelessWidget {
  const BigIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.color = AppColors.green,
    this.foreground = Colors.white,
    this.size = Dimens.primary,
    this.label,
    this.ringColor,
  }) : assert(size >= Dimens.minTouch, 'touch targets must be at least 56 dp'),
       assert(ringColor == null || size == Dimens.minTouch, 'only the small button has a ring');

  final IconData icon;
  final VoidCallback? onPressed;
  final String semanticLabel;
  final Color color;
  final Color foreground;
  final double size;

  /// Optional word under the picture (kept very short).
  final String? label;

  /// A 2 px ring around the circle (the speaker while it is speaking), drawn inside the 56 dp tap area.
  final Color? ringColor;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final visual = size <= Dimens.minTouch ? Dimens.ibtn : size;
    // Only the big coloured buttons glow (the mockup's camera circle); the small ones sit flat.
    final glow = enabled && size > Dimens.minTouch && color.a == 1 && color.computeLuminance() < 0.5;
    final circle = Container(
      width: visual,
      height: visual,
      decoration: BoxDecoration(
        color: enabled ? color : AppColors.line,
        shape: BoxShape.circle,
        boxShadow: glow
            ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))]
            : null,
      ),
      child: Icon(icon, size: visual * 0.5, color: enabled ? foreground : AppColors.inkSoft),
    );
    final button = Material(
      type: MaterialType.transparency,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled
            ? () {
                Haptics.tap();
                onPressed!();
              }
            : null,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: ringColor == null
                ? circle
                : Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: ringColor!, width: 2),
                    ),
                    child: circle,
                  ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      excludeSemantics: true,
      child: label == null
          ? button
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                button,
                const SizedBox(height: 6),
                // Never wider than the button (plus a little), whatever the text size: it shrinks to fit.
                SizedBox(
                  width: size + 24,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelLarge),
                  ),
                ),
              ],
            ),
    );
  }
}

/// The green tick: "yes" / "continue" / "send". With [showLabel] it is a wide green pill, the tick followed by the
/// word (its [semanticLabel]); the voice still calls it "the green tick".
class TickButton extends StatelessWidget {
  const TickButton({
    super.key,
    required this.onPressed,
    required this.semanticLabel,
    this.size = Dimens.primary,
    this.showLabel = false,
  });

  final VoidCallback? onPressed;
  final String semanticLabel;
  final double size;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    if (showLabel) {
      return PillButton(icon: AppIcons.tick, label: semanticLabel, onPressed: onPressed, height: size.clamp(64, 80));
    }
    return BigIconButton(
      icon: AppIcons.tick,
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      color: AppColors.green,
      size: size,
    );
  }
}

/// A wide rounded button: a picture and a short word, green by default. It sizes itself to its content (the screen's
/// action row scales it down on a narrow phone).
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color = AppColors.green,
    this.foreground = Colors.white,
    this.height = 64,
  }) : assert(height >= Dimens.minTouch, 'touch targets must be at least 56 dp');

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final Color foreground;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fg = enabled ? foreground : AppColors.inkSoft;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: enabled ? color : AppColors.line,
        shape: const StadiumBorder(),
        elevation: enabled ? 3 : 0,
        shadowColor: color.withValues(alpha: 0.5),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: enabled
              ? () {
                  Haptics.tap();
                  onPressed!();
                }
              : null,
          // Natural width in an action row; the whole width (the word shrinks if it must) in a wide strip.
          child: LayoutBuilder(
            builder: (context, constraints) {
              final word = Text(
                label,
                maxLines: 1,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.w800),
              );
              return ConstrainedBox(
                constraints: BoxConstraints(minHeight: height, minWidth: height * 2),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: height * 0.4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: height * 0.5, color: fg),
                      const SizedBox(width: 10),
                      if (constraints.hasBoundedWidth)
                        Flexible(
                          child: FittedBox(fit: BoxFit.scaleDown, child: word),
                        )
                      else
                        word,
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The red cross: "no" / "remove".
class CrossButton extends StatelessWidget {
  const CrossButton({super.key, required this.onPressed, required this.semanticLabel, this.size = Dimens.primary});

  final VoidCallback? onPressed;
  final String semanticLabel;
  final double size;

  @override
  Widget build(BuildContext context) => BigIconButton(
    icon: AppIcons.cross,
    onPressed: onPressed,
    semanticLabel: semanticLabel,
    color: AppColors.red,
    size: size,
  );
}

/// A large rounded picture tile (Home buttons, crop choices). [child] is the picture; [label] a short word.
/// A white tile is a card with a soft shadow and a hairline of [borderColor]; a tinted tile (a chosen language) gets
/// the full [borderColor] so the choice is plain to see.
class PictureTile extends StatelessWidget {
  const PictureTile({
    super.key,
    required this.child,
    required this.onPressed,
    required this.semanticLabel,
    this.label,
    this.color = AppColors.card,
    this.borderColor = AppColors.green,
    this.minHeight = Dimens.primary,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final String semanticLabel;
  final String? label;
  final Color color;
  final Color borderColor;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        color: color,
        elevation: color == AppColors.card ? 2 : 0,
        shadowColor: AppColors.shadow,
        shape: AppDecor.shape(AppDecor.side(borderColor, strong: color != AppColors.card)),
        child: InkWell(
          borderRadius: BorderRadius.circular(Dimens.radius),
          onTap: onPressed == null
              ? null
              : () {
                  Haptics.tap();
                  onPressed!();
                },
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight, minWidth: Dimens.minTouch),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: FittedBox(fit: BoxFit.scaleDown, child: child),
                  ),
                  if (label != null) ...[
                    const SizedBox(height: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(label!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
