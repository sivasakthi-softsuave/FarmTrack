import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/voice/voice_service.dart';
import '../../core/voice/voice_widgets.dart';
import '../../core/widgets/big_buttons.dart';
import '../../core/widgets/design.dart';

/// The dark camera of the mockup (`.phone.dark` and the inline colours of its "Take photos" screen), shared by the two
/// looks of the camera screen ([CaptureDesign]).
class CaptureColors {
  const CaptureColors._();

  static const ground = Color(0xFF0E1510);
  static const panel = Color(0xFF0B110D);
  static const frame = Color(0xFF16261A);
  static const thumb = Color(0xFF2C6B37);
  static const thumbIcon = Color(0xFFBFE5C8);
  static const sun = Color(0xFFF2C94C);

  /// The light green of the voice wave and of a tip that is being spoken.
  static const mint = Color(0xFF7BE08F);

  /// Glass chips over the picture. A plain translucent fill, not a blur: a blur costs a lot on a small phone.
  static const chip = Color(0x85000000);
}

final _underTest = Platform.environment.containsKey('FLUTTER_TEST');

/// True when nothing on the camera screen should move: the phone asks for no animations, or this is `flutter test` (a loop
/// would keep `pumpAndSettle` from ever settling, as it does for [VoiceWave]).
bool captureStill(BuildContext context) => MediaQuery.disableAnimationsOf(context) || _underTest;

/// How many times a decoration loop runs before it rests. The camera screen is looked at for a few seconds, so it moves
/// for about half a minute and then stands still: easier on the battery of a small phone.
const captureLoops = 9;

// ---------------------------------------------------------------------------- the leaf picture

/// The leaf of the mockup's SVG (viewBox 300 x 340) as a path: the outline both designs trace.
Path leafPath() => Path()
  ..moveTo(150, 40)
  ..cubicTo(230, 80, 250, 190, 160, 300)
  ..cubicTo(70, 250, 50, 120, 150, 40)
  ..close();

/// The big leaf with its veins and five brown spots, in the SVG's own 300 x 340 units.
void paintLeafArt(Canvas canvas) {
  canvas.drawPath(leafPath(), Paint()..color = const Color(0xFF3E8E4A));
  final vein = Paint()
    ..color = const Color(0xFF2C6B37)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4;
  canvas.drawLine(const Offset(150, 52), const Offset(158, 296), vein);
  vein.strokeWidth = 2.5;
  for (final (a, b) in const [
    (Offset(152, 120), Offset(205, 95)),
    (Offset(154, 170), Offset(218, 150)),
    (Offset(156, 220), Offset(205, 215)),
    (Offset(151, 140), Offset(100, 115)),
    (Offset(153, 195), Offset(90, 175)),
    (Offset(155, 245), Offset(110, 240)),
  ]) {
    canvas.drawLine(a, b, vein);
  }
  final spot = Paint()..color = const Color(0xE65B4630); // #5B4630 at 90 %
  for (final (x, y, r) in spotMarks) {
    canvas.drawCircle(Offset(x, y), r, spot);
  }
}

/// The five spots of the leaf (x, y, radius): where the rings of design A point.
const spotMarks = [
  (190.0, 130.0, 9.0),
  (120.0, 160.0, 7.0),
  (175.0, 200.0, 11.0),
  (125.0, 225.0, 6.0),
  (200.0, 175.0, 5.0),
];

/// A path drawn as dashes: [on] long, [off] apart, shifted along the line by [phase] (a changing phase makes it march).
void paintDashed(Canvas canvas, Path path, Paint paint, {double on = 10, double off = 8, double phase = 0}) {
  final period = on + off;
  for (final PathMetric metric in path.computeMetrics()) {
    for (var d = phase % period - period; d < metric.length; d += period) {
      final start = math.max(d, 0.0);
      final end = math.min(d + on, metric.length);
      if (end > start) canvas.drawPath(metric.extractPath(start, end), paint);
    }
  }
}

/// The four white corner marks: a [stroke] px line, outer radius 14, [arm] long. With [t] and [breathing] the corners move
/// slowly in and out, as if the camera were focusing.
class CornerPainter extends CustomPainter {
  CornerPainter({this.arm = 44, this.stroke = 5, this.t, this.breathing = false}) : super(repaint: t);

  final double arm;
  final double stroke;
  final Animation<double>? t;
  final bool breathing;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final half = stroke / 2;
    // The line runs in the middle of its width, so the 14 px outer radius is 14 - half on the line.
    final corner = Path()
      ..moveTo(half, arm)
      ..lineTo(half, 14)
      ..arcTo(Rect.fromLTWH(half, half, 28 - stroke, 28 - stroke), math.pi, math.pi / 2, false)
      ..lineTo(arm, half);
    final value = t?.value ?? 0;
    final k = breathing ? 1 - 0.06 * (1 - math.cos(2 * math.pi * value)) / 2 : 1.0;
    canvas
      ..translate(size.width / 2, size.height / 2)
      ..scale(k)
      ..translate(-size.width / 2, -size.height / 2);
    for (final (dx, dy, sx, sy) in [
      (0.0, 0.0, 1.0, 1.0),
      (size.width, 0.0, -1.0, 1.0),
      (0.0, size.height, 1.0, -1.0),
      (size.width, size.height, -1.0, -1.0),
    ]) {
      canvas
        ..save()
        ..translate(dx, dy)
        ..scale(sx, sy)
        ..drawPath(corner, line)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(CornerPainter oldDelegate) =>
      oldDelegate.arm != arm || oldDelegate.stroke != stroke || oldDelegate.breathing != breathing;
}

/// The red crossed-out camera that replaces the leaf while the camera is not allowed.
class CameraDeniedMark extends StatelessWidget {
  const CameraDeniedMark({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 120,
    height: 120,
    decoration: const BoxDecoration(color: AppColors.redSoft, shape: BoxShape.circle),
    child: const Icon(AppIcons.cameraOff, size: 72, color: AppColors.red, key: ValueKey('camera-denied')),
  );
}

// ---------------------------------------------------------------------------- the spoken tips

/// The three tips the voice gives, as the pictures the screens show them with.
enum CaptureTip {
  leaf('scan_one_leaf'),
  close('scan_hold_close'),
  light('scan_daylight');

  const CaptureTip(this.promptId);

  final String promptId;
}

/// Tells its [builder] which of the [CaptureTip]s the voice is saying right now (`null` while it says something else or
/// nothing), by comparing the caption with the sentence of each tip. When the words do not match (the server's text
/// differs from the bundled one) nothing lights up and the screen is just as usable.
class TipSync extends ConsumerWidget {
  const TipSync({super.key, required this.owner, required this.builder});

  /// The screen that started the speech: another screen's speech lights nothing.
  final Object owner;
  final Widget Function(BuildContext context, CaptureTip? tip) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voice = ref.watch(voiceServiceProvider);
    final catalogue = ref.watch(promptCatalogueProvider);
    final lang = ref.watch(languageProvider);
    return ValueListenableBuilder<VoiceState>(
      valueListenable: voice.state,
      builder: (context, state, _) {
        CaptureTip? now;
        final caption = state.caption?.trim();
        if (state.speaking && state.owner == owner && caption != null && caption.isNotEmpty) {
          final spokenIn = state.captionLang ?? lang;
          for (final tip in CaptureTip.values) {
            if (catalogue.text(tip.promptId, spokenIn).trim() == caption) now = tip;
          }
        }
        return builder(context, now);
      },
    );
  }
}

/// A small picture-and-words badge over the camera: a dark glass pill with a [icon].
class CaptureChip extends StatelessWidget {
  const CaptureChip({super.key, required this.icon, required this.text, this.iconColor = Colors.white});

  final IconData? icon;
  final String text;
  final Color iconColor;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(color: CaptureColors.chip, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 20, color: iconColor), const SizedBox(width: 6)],
          Flexible(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppText.pill.copyWith(fontSize: 14, color: Colors.white),
            ),
          ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------- top row

/// `row` of the mockup's camera: a glass back button, the centred "Photo 2 of 4" pill, the voice button on glass.
class CaptureTopRow extends StatelessWidget {
  const CaptureTopRow({super.key, required this.backLabel, required this.title, required this.onBack});

  final String backLabel;
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 60,
    child: Padding(
      // The round buttons are 48 wide inside 56 wide tap areas, so the row starts 4 dp inside the 16 dp gutter.
      padding: const EdgeInsets.symmetric(horizontal: 12),
      // The back button and the voice button are the same size, so the pill is in the middle of the screen.
      child: Row(
        children: [
          BigIconButton(
            icon: AppIcons.back,
            semanticLabel: backLabel,
            color: glassButtonColor,
            foreground: Colors.white,
            size: Dimens.minTouch,
            onPressed: onBack,
          ),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: AppPill(title, background: glassButtonColor, foreground: Colors.white),
              ),
            ),
          ),
          const VoiceButton(onDark: true),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------- photo strip

/// The photos of this scan as [max] slots: a 56 px tile for each photo taken (a red cross at its corner removes it), the
/// dashed plus tile that takes the next one, and numbered empty slots for the rest, so "up to 4 photos" needs no words.
/// When there is room the count ("1/4") stands at the right (design A) or right after the slots (design B, [centered]).
class PhotoStrip extends StatelessWidget {
  const PhotoStrip({
    super.key,
    required this.photos,
    required this.max,
    required this.hint,
    required this.countWord,
    required this.removeLabel,
    required this.addLabel,
    required this.onRemove,
    required this.onAdd,
    this.centered = false,
  });

  final List<String> photos;
  final int max;

  /// "up to 4 photos": what a screen reader says for the count.
  final String hint;

  /// "photos": the small word under the count.
  final String countWord;
  final String removeLabel;
  final String addLabel;
  final ValueChanged<int> onRemove;
  final VoidCallback? onAdd;
  final bool centered;

  static const _tile = 56.0;
  static const _gap = 8.0;

  /// The panel's 14 px top padding lives in the strip, so the corner crosses can be tapped where they stick out.
  static const _top = 14.0;

  @override
  Widget build(BuildContext context) {
    final row = max * (_tile + _gap) - _gap;
    return SizedBox(
      height: _top + _tile,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final room = constraints.maxWidth - row;
          // Design B centres the slots with the count just after them; design A keeps the slots at the left and the count at
          // the right edge. With no room for the count the slots stand alone.
          const countWidth = 40.0;
          final showCount = centered ? room >= 12 + countWidth : room >= 64;
          final group = row + (centered && showCount ? 12 + countWidth : 0);
          final start = centered ? math.max(0.0, (constraints.maxWidth - group) / 2) : 0.0;
          return Stack(
            children: [
              for (var i = photos.length + 1; i < max; i++)
                Positioned(
                  left: start + i * (_tile + _gap),
                  top: _top,
                  child: _EmptySlot(number: i + 1),
                ),
              for (var i = 0; i < photos.length; i++)
                Positioned(
                  left: start + i * (_tile + _gap),
                  top: _top,
                  child: PhotoTile(key: ValueKey('strip-photo-$i'), path: photos[i]),
                ),
              // The red cross is drawn 26 px at the tile's top right corner; its tap area is 56 x 56 (down and to the
              // right as far as the gap allows) so a thumb finds it without a tile being a button.
              for (var i = 0; i < photos.length; i++)
                Positioned(
                  left: start + i * (_tile + _gap) + _tile - 18,
                  top: 0,
                  width: Dimens.minTouch,
                  height: Dimens.minTouch,
                  child: _RemoveBadge(
                    key: ValueKey('strip-remove-$i'),
                    label: removeLabel,
                    onPressed: () => onRemove(i),
                  ),
                ),
              if (photos.length < max)
                Positioned(
                  left: start + photos.length * (_tile + _gap),
                  top: _top,
                  child: _AddTile(label: addLabel, onPressed: onAdd),
                ),
              if (showCount)
                Positioned(
                  left: centered ? start + row + 12 : null,
                  right: centered ? null : 0,
                  top: _top,
                  height: _tile,
                  child: Semantics(
                    label: hint,
                    excludeSemantics: true,
                    child: Align(
                      alignment: centered ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
                      child: _Count(done: photos.length, max: max, word: countWord),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// "0/4" with the small word "photos" under it.
class _Count extends StatelessWidget {
  const _Count({required this.done, required this.max, required this.word});

  final int done;
  final int max;
  final String word;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(
        '$done/$max',
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white, height: 1.1),
      ),
      Text(
        word,
        // Devanagari needs more line height than Latin or its marks touch the number above.
        style: TextStyle(
          fontSize: isDevanagari(word) ? 13 : 12,
          color: const Color(0xB3FFFFFF),
          height: isDevanagari(word) ? 1.5 : 1.1,
        ),
      ),
    ],
  );
}

/// A slot of the scan with no photo yet: a faint dashed box with its number.
class _EmptySlot extends StatelessWidget {
  const _EmptySlot({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      painter: const _DashedBoxPainter(Color(0x2BFFFFFF)),
      child: SizedBox(
        width: PhotoStrip._tile,
        height: PhotoStrip._tile,
        child: Center(
          child: Text(
            '$number',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0x4DFFFFFF)),
          ),
        ),
      ),
    ),
  );
}

/// A photo of the scan as a 56 px tile: the green leaf tile of the mockup until (or instead of) the picture itself.
class PhotoTile extends StatelessWidget {
  const PhotoTile({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: PhotoStrip._tile,
      height: PhotoStrip._tile,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: CaptureColors.thumb, borderRadius: BorderRadius.circular(Dimens.radiusSmall)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Center(child: Icon(AppIcons.leaf, size: 28, color: CaptureColors.thumbIcon)),
          Image.file(
            File(path),
            fit: BoxFit.cover,
            cacheWidth: 120,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    ),
  );
}

/// The red 26 px cross of a tile, with a 2 px border in the colour of the panel.
class _RemoveBadge extends StatelessWidget {
  const _RemoveBadge({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        onTap: () {
          Haptics.tap();
          onPressed();
        },
        // Badge top = tile top - 8; the tap area starts 14 above the tile.
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(top: PhotoStrip._top - 8),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: AppColors.red,
                shape: BoxShape.circle,
                border: Border.all(color: CaptureColors.panel, width: 2),
              ),
              child: const Icon(AppIcons.crossBold, size: 14, color: Colors.white),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The dashed plus tile: take one more photo.
class _AddTile extends StatelessWidget {
  const _AddTile({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    key: const ValueKey('strip-add'),
    button: true,
    enabled: onPressed != null,
    label: label,
    excludeSemantics: true,
    child: Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(Dimens.radiusSmall),
          onTap: onPressed == null
              ? null
              : () {
                  Haptics.tap();
                  onPressed!();
                },
          child: CustomPaint(
            painter: const _DashedBoxPainter(Color(0x8CFFFFFF)),
            child: const SizedBox(
              width: PhotoStrip._tile,
              height: PhotoStrip._tile,
              child: Icon(AppIcons.plus, size: 30, color: Colors.white),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A 2 px dashed line round a 56 px box with radius 14, drawn inside the box as a CSS border is.
class _DashedBoxPainter extends CustomPainter {
  const _DashedBoxPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius((Offset.zero & size).deflate(1), const Radius.circular(Dimens.radiusSmall - 1)),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    paintDashed(canvas, path, paint, on: 6, off: 4);
  }

  @override
  bool shouldRepaint(_DashedBoxPainter oldDelegate) => oldDelegate.color != color;
}

// ---------------------------------------------------------------------------- controls

/// Gallery on the left, the round shutter in the middle, the green send tick on the right.
class CaptureControls extends StatelessWidget {
  const CaptureControls({
    super.key,
    required this.galleryLabel,
    required this.galleryWord,
    required this.cameraLabel,
    required this.sendLabel,
    required this.sendWord,
    required this.onGallery,
    required this.onCamera,
    required this.onSend,
  });

  final String galleryLabel;
  final String galleryWord;
  final String cameraLabel;
  final String sendLabel;
  final String sendWord;
  final VoidCallback? onGallery;
  final VoidCallback? onCamera;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _LabelledButton(
          word: galleryWord,
          child: _RoundButton(
            key: const ValueKey('gallery-button'),
            icon: AppIcons.gallery,
            iconSize: 24,
            fill: glassButtonColor,
            semanticLabel: galleryLabel,
            onPressed: onGallery,
          ),
        ),
        _Shutter(key: const ValueKey('camera-button'), semanticLabel: cameraLabel, onPressed: onCamera),
        _LabelledButton(
          word: sendWord,
          child: _RoundButton(
            key: const ValueKey('send-photos'),
            icon: AppIcons.tickBold,
            iconSize: 30,
            fill: AppColors.green,
            semanticLabel: sendLabel,
            onPressed: onSend,
          ),
        ),
      ],
    ),
  );
}

/// A control with its small word under it (12.5 px at 85 %). The word is not a button: the circle above it is.
class _LabelledButton extends StatelessWidget {
  const _LabelledButton({required this.word, required this.child});

  final String word;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      child,
      const SizedBox(height: 4),
      SizedBox(
        width: 72,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          // Devanagari is set one point bigger, as the mockup's Hindi labels are.
          child: Text(
            word,
            style: TextStyle(fontSize: isDevanagari(word) ? 13.5 : 12.5, color: const Color(0xD9FFFFFF)),
          ),
        ),
      ),
    ],
  );
}

/// A 56 px round button (the mockup draws these at 56, not 48): glass for the gallery, green for send. It dims while off.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.icon,
    required this.iconSize,
    required this.fill,
    required this.semanticLabel,
    required this.onPressed,
  });

  final IconData icon;
  final double iconSize;
  final Color fill;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onPressed != null,
    label: semanticLabel,
    excludeSemantics: true,
    child: Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: Material(
        color: fill,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed == null
              ? null
              : () {
                  Haptics.tap();
                  onPressed!();
                },
          child: SizedBox(
            width: Dimens.minTouch,
            height: Dimens.minTouch,
            child: Icon(icon, size: iconSize, color: Colors.white),
          ),
        ),
      ),
    ),
  );
}

/// The shutter: an 88 px ring (5 px white line) round a 68 px white disc.
class _Shutter extends StatelessWidget {
  const _Shutter({super.key, required this.semanticLabel, required this.onPressed});

  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onPressed != null,
    label: semanticLabel,
    excludeSemantics: true,
    child: Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed == null
              ? null
              : () {
                  Haptics.tap();
                  onPressed!();
                },
          child: Container(
            width: 88,
            height: 88,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 5),
            ),
            child: Container(
              width: 68,
              height: 68,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    ),
  );
}
