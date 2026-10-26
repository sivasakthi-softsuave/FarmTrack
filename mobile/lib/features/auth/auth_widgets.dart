import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Small pieces shared by the screens before the farmer is in (splash, language, welcome, login and the server dialog), so
/// they look like one start: the logo, the hills picture and the text field of the mockup's login (`.input`).

/// The FarmTrack mark in the top bar: a leaf on a deep-green tile (`.dot`, 44, radius 14) and the name in 20 / 800.
class AuthLogo extends StatelessWidget {
  const AuthLogo({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const BrandTile(),
        const SizedBox(width: 10),
        Text(
          name,
          style: AppText.title.copyWith(fontWeight: FontWeight.w800, color: AppColors.ink),
        ),
      ],
    ),
  );
}

/// The deep-green rounded square with the white leaf: 44 in the top bar, bigger on the splash screen.
class BrandTile extends StatelessWidget {
  const BrandTile({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(size * 14 / 44)),
    child: Icon(AppIcons.leaf, size: size * 24 / 44, color: Colors.white),
  );
}

/// The big word of a start screen and the grey line under it ("Log in" / "Welcome. Please log in to come in."): 28 / 800
/// on 1.2, then 16 in grey, 4 below it.
class AuthHeading extends StatelessWidget {
  const AuthHeading({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.2, color: AppColors.ink),
      ),
      if (subtitle != null) ...[
        const SizedBox(height: 4),
        Text(subtitle!, style: const TextStyle(fontSize: 16, height: 1.36, color: AppColors.inkSoft)),
      ],
    ],
  );
}

/// The picture above the login: green hills with apple trees and a sun, drawn so it costs no download (the mockup's SVG,
/// 350 x 150, radius 24). The drawing is scaled to the width and rests on the bottom edge, so a narrow phone gets more sky
/// and a wide one never gets a gap at the sides.
class HillsPicture extends StatelessWidget {
  const HillsPicture({super.key, this.height = 150});

  final double height;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: const CustomPaint(painter: _HillsPainter()),
      ),
    ),
  );
}

class _HillsPainter extends CustomPainter {
  const _HillsPainter();

  // The mockup's own colours (login `<svg viewBox="0 0 350 150">`): sun, far hill, near hill, trunk.
  static const _sun = Color(0xFFF2C94C);
  static const _farHill = Color(0xFF9CCFA8);
  static const _nearHill = Color(0xFF4E9F62);
  static const _trunk = Color(0xFF6B4E2E);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.greenSoft);
    final scale = size.width / 350;
    canvas
      ..save()
      ..translate(0, size.height - 150 * scale)
      ..scale(scale);

    canvas.drawCircle(const Offset(270, 48), 22, Paint()..color = _sun);

    // `S` in the SVG repeats the mirrored control point: (230, 130) for the far hill, (260, 140) for the near one.
    final far = Path()
      ..moveTo(0, 110)
      ..cubicTo(60, 70, 110, 70, 170, 100)
      ..cubicTo(230, 130, 280, 80, 350, 95)
      ..lineTo(350, 150)
      ..lineTo(0, 150)
      ..close();
    canvas.drawPath(far, Paint()..color = _farHill);
    final near = Path()
      ..moveTo(0, 130)
      ..cubicTo(70, 100, 140, 110, 200, 125)
      ..cubicTo(260, 140, 300, 110, 350, 120)
      ..lineTo(350, 150)
      ..lineTo(0, 150)
      ..close();
    canvas.drawPath(near, Paint()..color = _nearHill);

    final crown = Paint()..color = AppColors.green;
    final trunk = Paint()..color = _trunk;
    // Crown, then trunk (over its lower edge), tree by tree, as in the SVG.
    for (final (cx, cy, r, tx, ty) in const [
      (70.0, 96.0, 12.0, 68.0, 104.0),
      (105.0, 92.0, 10.0, 103.0, 98.0),
      (240.0, 98.0, 12.0, 238.0, 106.0),
    ]) {
      canvas
        ..drawCircle(Offset(cx, cy), r, crown)
        ..drawRect(Rect.fromLTWH(tx, ty, 4, 12), trunk);
    }
    final apple = Paint()..color = AppColors.red;
    for (final (x, y) in const [(66.0, 94.0), (75.0, 99.0), (244.0, 95.0), (108.0, 90.0)]) {
      canvas.drawCircle(Offset(x, y), 2, apple);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HillsPainter oldDelegate) => false;
}

/// The look of a text field of the mockup's login (`.input`): white, radius 16, a 2 px line that turns green when the
/// field has the cursor. 58 high (it grows with the text size). The green 4 px glow of the focused field is [FieldGlow].
InputDecoration authInputDecoration({String? hint, bool error = false, Widget? suffixIcon, double start = 14}) {
  OutlineInputBorder border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: color, width: 2),
  );
  return InputDecoration(
    counterText: '',
    filled: true,
    fillColor: AppColors.card,
    hintText: hint,
    hintStyle: authInputStyle.copyWith(color: AppColors.chevron, fontWeight: FontWeight.w400),
    // 58 high: the 18 / 1.3 line (23.4) with 17.3 above and below. The text starts 2 further in than the padding says
    // (the 2 px line), which gives the mockup's 16 + 2.
    contentPadding: EdgeInsetsDirectional.fromSTEB(start, 17.3, 16, 17.3),
    suffixIcon: suffixIcon,
    // The round button inside the field is 48 wide in a 56 tap area; the field's right padding is 8 (+ the 2 px line).
    suffixIconConstraints: const BoxConstraints(minWidth: 62, minHeight: Dimens.minTouch),
    // A field that was refused (the server address) has a red line, the words under it are the screen's own.
    border: border(error ? AppColors.red : AppColors.line),
    enabledBorder: border(error ? AppColors.red : AppColors.line),
    focusedBorder: border(error ? AppColors.red : AppColors.green),
    disabledBorder: border(AppColors.line),
  );
}

/// `.input`: 18 / 600.
const authInputStyle = TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.ink, height: 1.3);

/// `.input.focus`: the soft green ring (4 px, 14 %) around the field that has the cursor.
class FieldGlow extends StatelessWidget {
  const FieldGlow({super.key, required this.focusNode, required this.child, this.color = AppColors.green});

  final FocusNode focusNode;
  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: focusNode,
    builder: (context, child) => DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: focusNode.hasFocus ? [BoxShadow(color: color.withValues(alpha: 0.14), spreadRadius: 4)] : null,
      ),
      child: child,
    ),
    child: child,
  );
}
