import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/design.dart';
import 'capture_widgets.dart';

/// Camera screen, design A ("alive frame with tip chips"): the mockup's dark frame, but it moves a little (a scan line, a
/// leaf that floats) and the tips the voice gives are three picture chips under it. The chip of the sentence being spoken
/// lights up, and the frame shows what it means: rings on the spots, corners moving in, a warm light.
class CaptureViewA extends ConsumerWidget {
  const CaptureViewA({super.key, required this.owner, required this.denied});

  /// The screen that speaks (so another screen's speech lights no chip).
  final Object owner;
  final bool denied;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    return TipSync(
      owner: owner,
      builder: (context, tip) => LayoutBuilder(
        builder: (context, constraints) {
          // A tall phone has room above the frame for the sentence that floats there while it is spoken.
          final top = constraints.maxHeight >= 520 ? 72.0 : 10.0;
          return Padding(
            padding: EdgeInsets.fromLTRB(0, top, 0, 8),
            child: Center(
              // On a small phone the frame and the chips shrink together instead of overflowing.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: 328,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AliveFrame(denied: denied, tip: tip),
                      const SizedBox(height: 16),
                      TipChips(
                        active: tip,
                        leaf: t('scan_chip_leaf'),
                        close: t('scan_chip_close'),
                        light: t('scan_chip_light'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The frame: 300 x 340, dark green with a faint dot grid, the leaf of the mockup, four white corner marks. Moves for about
/// half a minute after it opens and again while a tip is spoken, then rests; never moves when the phone asks for no
/// animations. While the camera is not allowed the leaf is replaced by the red crossed-out camera.
class AliveFrame extends StatefulWidget {
  const AliveFrame({super.key, required this.denied, required this.tip});

  final bool denied;

  /// The tip being spoken now (`null` = none).
  final CaptureTip? tip;

  @override
  State<AliveFrame> createState() => _AliveFrameState();
}

class _AliveFrameState extends State<AliveFrame> with TickerProviderStateMixin {
  /// One loop: the scan line goes down once, the leaf floats up and down once.
  late final AnimationController _t = AnimationController(vsync: this, duration: const Duration(milliseconds: 3400));

  /// 0 to 1 each time the tip changes, so a ring or a light fades in.
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (captureStill(context)) {
      _t.stop();
    } else if (!_started) {
      _started = true;
      _t.repeat(count: captureLoops);
    }
  }

  @override
  void didUpdateWidget(AliveFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tip == widget.tip) return;
    if (!captureStill(context)) {
      _fade.forward(from: 0);
      if (widget.tip != null && !_t.isAnimating) {
        _t
          ..value = 0
          ..repeat(count: 5);
      }
    }
  }

  @override
  void dispose() {
    _t.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 300,
    height: 340,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: ExcludeSemantics(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _AlivePainter(t: _t, fade: _fade, tip: widget.tip, leaf: !widget.denied),
              ),
            ),
          ),
        ),
        if (widget.denied) const Center(child: CameraDeniedMark()),
        Positioned(
          left: -6,
          top: -6,
          right: -6,
          bottom: -6,
          child: ExcludeSemantics(
            child: CustomPaint(
              painter: CornerPainter(arm: 40, t: _t, breathing: widget.tip == CaptureTip.close),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Everything inside the frame, drawn in the SVG's own 300 x 340 units and scaled to the box.
class _AlivePainter extends CustomPainter {
  _AlivePainter({required this.t, required this.fade, required this.tip, required this.leaf})
    : super(repaint: Listenable.merge([t, fade]));

  final Animation<double> t;
  final Animation<double> fade;
  final CaptureTip? tip;
  final bool leaf;

  static final _backdrop = ui.Gradient.radial(
    const Offset(150, 129),
    230,
    const [Color(0xFF25422F), Color(0xFF16261A), Color(0xFF101B13)],
    const [0, 0.62, 1],
  );
  static final _dots = [
    for (var y = 9.0; y < 340; y += 18)
      for (var x = 9.0; x < 300; x += 18) Offset(x, y),
  ];
  static final _dotPaint = Paint()
    ..color = const Color(0x14FFFFFF)
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round;
  static const _rings = [Offset(175, 200), Offset(190, 130)];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 300, size.height / 340);
    final frame = RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 300, 340), const Radius.circular(24));
    canvas
      ..save()
      ..clipRRect(frame)
      ..drawRRect(frame, Paint()..shader = _backdrop)
      ..drawPoints(ui.PointMode.points, _dots, _dotPaint);
    if (leaf) {
      // 0 .. 1 .. 0 once per loop: the leaf rises 5 px and turns 2 degrees, and settles again.
      final s = (1 - math.cos(2 * math.pi * t.value)) / 2;
      canvas
        ..save()
        ..translate(150, 170 - 5 * s)
        ..rotate((-1 + 2.2 * s) * math.pi / 180)
        ..translate(-150, -170);
      paintLeafArt(canvas);
      canvas.restore();
      _scanLine(canvas);
      switch (tip) {
        case CaptureTip.leaf:
          _spotRings(canvas);
        case CaptureTip.light:
          _warmLight(canvas);
        case CaptureTip.close || null:
          break;
      }
    }
    canvas.restore();
  }

  /// A thin light that goes down the frame once per loop and fades at both ends.
  void _scanLine(Canvas canvas) {
    final p = t.value;
    if (p <= 0 || p >= 1) return;
    final a = math.min((p / 0.12).clamp(0.0, 1.0), ((1 - p) / 0.12).clamp(0.0, 1.0));
    final y = 20 + 300 * Curves.easeInOut.transform(p);
    const mint = CaptureColors.mint;
    for (final (half, alpha) in const [(8.5, 0.07), (4.5, 0.18), (1.5, 0.95)]) {
      final paint = Paint()
        ..shader = ui.Gradient.linear(
          const Offset(12, 0),
          const Offset(288, 0),
          [mint.withValues(alpha: 0), mint.withValues(alpha: alpha * a), mint.withValues(alpha: 0)],
          const [0, 0.5, 1],
        );
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(12, y - half, 288, y + half), Radius.circular(half)),
        paint,
      );
    }
  }

  /// "Choose a leaf with spots": a ring that grows and fades on two of the spots.
  void _spotRings(Canvas canvas) {
    for (final (i, centre) in _rings.indexed) {
      final p = (t.value * 3400 / 1800 + i * 0.33) % 1.0;
      final radius = 13 * (0.55 + 1.35 * Curves.easeOut.transform(p));
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = CaptureColors.sun.withValues(alpha: (1 - p) * 0.95 * fade.value),
      );
    }
  }

  /// "Take it in daylight": a warm light from the top right corner.
  void _warmLight(Canvas canvas) {
    final paint = Paint()
      ..shader = ui.Gradient.radial(const Offset(264, 20), 190, [
        CaptureColors.sun.withValues(alpha: 0.6 * fade.value),
        CaptureColors.sun.withValues(alpha: 0),
      ]);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 300, 340), paint);
  }

  @override
  bool shouldRepaint(_AlivePainter oldDelegate) => oldDelegate.tip != tip || oldDelegate.leaf != leaf;
}

/// The three spoken tips as chips under the frame: a picture and two words each. The one being spoken has a green outline.
/// They are not buttons (the voice says the same words), so a screen reader skips them.
class TipChips extends StatelessWidget {
  const TipChips({super.key, required this.active, required this.leaf, required this.close, required this.light});

  final CaptureTip? active;
  final String leaf;
  final String close;
  final String light;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _TipChip(
              key: const ValueKey('tip-chip-leaf'),
              icon: AppIcons.leaf,
              label: leaf,
              active: active == CaptureTip.leaf,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _TipChip(
              key: const ValueKey('tip-chip-close'),
              icon: AppIcons.zoom,
              label: close,
              active: active == CaptureTip.close,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _TipChip(
              key: const ValueKey('tip-chip-light'),
              icon: AppIcons.sun,
              label: light,
              active: active == CaptureTip.light,
              iconColor: CaptureColors.sun,
            ),
          ),
        ],
      ),
    ),
  );
}

class _TipChip extends StatelessWidget {
  const _TipChip({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    this.iconColor = Colors.white,
  });

  final IconData icon;
  final String label;
  final bool active;
  final Color iconColor;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 250),
    padding: const EdgeInsets.fromLTRB(6, 9, 6, 9),
    decoration: BoxDecoration(
      color: active ? const Color(0x335FD17A) : const Color(0x12FFFFFF),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: active ? const Color(0xE67BE08F) : Colors.transparent, width: 1.5),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(color: Color(0x1AFFFFFF), shape: BoxShape.circle),
          child: Icon(icon, size: 22, color: iconColor),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: isDevanagari(label) ? 13.5 : 12.5,
            fontWeight: FontWeight.w600,
            height: 1.25,
            color: Colors.white,
          ),
        ),
      ],
    ),
  );
}
