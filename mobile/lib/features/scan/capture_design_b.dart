import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import 'capture_widgets.dart';

// Camera screen, design B ("camera feel"): the whole screen is the viewfinder. A soft green backdrop like an out-of-focus
// orchard, a thirds grid, a dashed leaf outline that shows where to put the leaf, a focus ring, and two floating chips.
// The controls sit on a fade at the bottom instead of a solid panel.
//
// It looks like a live camera but it is not one: the shutter still opens the phone's camera app. Nothing here uses a blur
// filter (a translucent fill and a few radial gradients look the same and cost far less on a small phone).

/// The layer under the whole screen: a dark green gradient with soft light spots. Painted once, never repainted.
class CaptureBackdropB extends StatelessWidget {
  const CaptureBackdropB({super.key});

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: RepaintBoundary(
      child: CustomPaint(painter: _BackdropPainter(), size: Size.infinite),
    ),
  );
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height), const [
          Color(0xFF101C14),
          Color(0xFF0B130D),
        ]),
    );
    // Soft light spots, placed for a 360 x 790 screen and moved with the size of this one.
    final sx = size.width / 360;
    final sy = size.height / 790;
    for (final (x, y, r, color) in const [
      (55.0, 185.0, 105.0, Color(0x8C3E8E4A)),
      (310.0, 340.0, 90.0, Color(0xA62C6B37)),
      (125.0, 505.0, 75.0, Color(0x595FAA69)),
      (270.0, 160.0, 60.0, Color(0x33F2C94C)),
    ]) {
      final centre = Offset(x * sx, y * sy);
      final radius = r * math.max(sx, sy) * 1.25;
      canvas.drawCircle(
        centre,
        radius,
        Paint()..shader = ui.Gradient.radial(centre, radius, [color, color.withValues(alpha: 0)], const [0.3, 1]),
      );
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter oldDelegate) => false;
}

/// The viewfinder area between the top row and the controls.
class CaptureViewB extends ConsumerStatefulWidget {
  const CaptureViewB({super.key, required this.denied});

  final bool denied;

  @override
  ConsumerState<CaptureViewB> createState() => _CaptureViewBState();
}

class _CaptureViewBState extends ConsumerState<CaptureViewB> with SingleTickerProviderStateMixin {
  /// One loop: the dashes of the outline move two steps, the focus ring closes in once.
  late final AnimationController _t = AnimationController(vsync: this, duration: const Duration(milliseconds: 3400));
  bool _started = false;
  bool _still = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = captureStill(context);
    if (_still) {
      _t.stop();
    } else if (!_started) {
      _started = true;
      _t.repeat(count: captureLoops);
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 6),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned.fill(
            child: ExcludeSemantics(
              child: RepaintBoundary(child: CustomPaint(painter: _ThirdsPainter())),
            ),
          ),
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, c) {
                if (widget.denied) return const Center(child: CameraDeniedMark());
                // The outline is about 60 % as high as the frame, never wider than it is, and turned a little like a leaf in
                // a hand.
                final h = math.min(c.maxHeight * 0.62, c.maxWidth * 1.5);
                // A little below the middle, clear of the chip at the top.
                return Align(
                  alignment: const Alignment(0, 0.12),
                  child: Transform.rotate(
                    angle: -6 * math.pi / 180,
                    child: SizedBox(
                      width: h * _GhostLeafPainter.aspect,
                      height: h,
                      child: ExcludeSemantics(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _GhostLeafPainter(t: _t, still: _still),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (!widget.denied)
            Align(
              alignment: const Alignment(0.2, 0.14),
              child: SizedBox(
                width: 60,
                height: 60,
                child: ExcludeSemantics(
                  child: CustomPaint(
                    painter: _FocusPainter(t: _t, still: _still),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            // Below the spoken sentence, which floats over the top of the picture while it is said.
            top: 66,
            child: Center(
              child: CaptureChip(icon: AppIcons.leafThin, text: t('scan_fit_leaf')),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 14,
            child: Center(
              child: CaptureChip(icon: AppIcons.sun, iconColor: CaptureColors.sun, text: t('scan_tip_daylight')),
            ),
          ),
          Positioned(
            left: -6,
            top: -6,
            right: -6,
            bottom: -6,
            child: ExcludeSemantics(child: CustomPaint(painter: CornerPainter())),
          ),
        ],
      ),
    );
  }
}

/// The rule-of-thirds lines: two across and two down, white at 16 %.
class _ThirdsPainter extends CustomPainter {
  const _ThirdsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0x29FFFFFF)
      ..strokeWidth = 1;
    for (final k in const [1 / 3, 2 / 3]) {
      canvas
        ..drawLine(Offset(size.width * k, 0), Offset(size.width * k, size.height), line)
        ..drawLine(Offset(0, size.height * k), Offset(size.width, size.height * k), line);
    }
  }

  @override
  bool shouldRepaint(_ThirdsPainter oldDelegate) => false;
}

/// The dashed outline of a leaf, with a dotted midrib: "put the leaf here". The dashes march slowly along it.
class _GhostLeafPainter extends CustomPainter {
  _GhostLeafPainter({required this.t, required this.still}) : super(repaint: t);

  final Animation<double> t;
  final bool still;

  static final _leaf = leafPath();
  static final _bounds = _leaf.getBounds();

  /// Width over height of the leaf itself, so the box that holds the outline has no empty margin.
  static final aspect = _bounds.width / _bounds.height;

  @override
  void paint(Canvas canvas, Size size) {
    // The leaf fills the box; one scale for both ways (the box has the leaf's own shape), lines and dashes in dp.
    final k = size.height / _bounds.height;
    canvas
      ..scale(k)
      ..translate(-_bounds.left, -_bounds.top)
      ..drawPath(_leaf, Paint()..color = const Color(0x0FFFFFFF));
    final outline = Paint()
      ..color = const Color(0xCCFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5 / k
      ..strokeCap = StrokeCap.round;
    // Two dash lengths per loop (2 x 18 dp), so the loop is seamless.
    paintDashed(canvas, _leaf, outline, on: 10 / k, off: 8 / k, phase: still ? 0 : t.value * 36 / k);
    final rib = Paint()
      ..color = const Color(0x73FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 / k
      ..strokeCap = StrokeCap.round;
    paintDashed(
      canvas,
      Path()
        ..moveTo(150, 52)
        ..lineTo(158, 296),
      rib,
      on: 3 / k,
      off: 9 / k,
    );
  }

  @override
  bool shouldRepaint(_GhostLeafPainter oldDelegate) => oldDelegate.still != still;
}

/// A yellow focus square that closes in on its spot once per loop and then stays. Still: just the square.
class _FocusPainter extends CustomPainter {
  _FocusPainter({required this.t, required this.still}) : super(repaint: t);

  final Animation<double> t;
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    final p = still ? 1.0 : t.value;
    final scale = 1.7 - 0.7 * Curves.easeOut.transform((p / 0.55).clamp(0.0, 1.0));
    final opacity = p < 0.25 ? p / 0.25 : (p > 0.55 ? 0.9 : 1.0);
    canvas
      ..translate(size.width / 2, size.height / 2)
      ..scale(scale)
      ..drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 60, height: 60), const Radius.circular(12)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = CaptureColors.sun.withValues(alpha: opacity),
      );
  }

  @override
  bool shouldRepaint(_FocusPainter oldDelegate) => oldDelegate.still != still;
}
