import 'package:flutter/material.dart';

import 'field_words.dart';

/// What a weather picture shows.
enum WeatherKind { sun, moon, partlySunny, cloud, lightRain, heavyRain, snow }

/// The picture of a day of the week card, chosen by its rain: the sun (dry), a cloud with a little rain, a cloud with a lot.
WeatherKind weatherKindOfRain(double rainMm) => switch (rainBand(rainMm)) {
  RainBand.none => WeatherKind.sun,
  RainBand.light => WeatherKind.lightRain,
  RainBand.heavy => WeatherKind.heavyRain,
};

/// The picture of the sky now, from the server's `sky` word (see `ConditionsOut.sky`); by night the sun becomes the moon. A word the
/// app does not know shows a plain cloud.
WeatherKind weatherKindOfSky(String? sky, {bool isDay = true}) => switch (sky) {
  'clear' || 'mostly_clear' => isDay ? (sky == 'clear' ? WeatherKind.sun : WeatherKind.partlySunny) : WeatherKind.moon,
  'partly_cloudy' => isDay ? WeatherKind.partlySunny : WeatherKind.cloud,
  'drizzle' || 'showers' => WeatherKind.lightRain,
  'rain' || 'heavy_rain' || 'thunderstorm' => WeatherKind.heavyRain,
  'snow' => WeatherKind.snow,
  _ => WeatherKind.cloud,
};

/// A weather picture, drawn (not a picture of the icon font) so that it can be coloured like the weather itself: a warm sun, a pale
/// moon, a grey-blue cloud, blue drops. The shapes differ too, so the colours alone carry nothing. Decorative: the word for the
/// weather is written next to it and in the semantics label of its card.
class WeatherGlyph extends StatelessWidget {
  const WeatherGlyph({super.key, required this.kind, this.size = 32});

  final WeatherKind kind;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(size: Size.square(size), painter: _GlyphPainter(kind)),
  );
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.kind);

  final WeatherKind kind;

  static const _sunLight = Color(0xFFFFD54F);
  static const _sunDeep = Color(0xFFFF9800);
  static const _moonLight = Color(0xFFFFF3C4);
  static const _moonDeep = Color(0xFFF2C14E);
  static const _cloudLight = Color(0xFFD3DEEB);
  static const _cloudDeep = Color(0xFF93A7BE);
  static const _cloudEdge = Color(0xFF7F93AB);
  static const _drop = Color(0xFF2F7BD9);
  static const _flake = Color(0xFF5B9BE6);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    switch (kind) {
      case WeatherKind.sun:
        _sun(canvas, s, center: Offset(s / 2, s / 2), radius: 0.33 * s);
      case WeatherKind.moon:
        _moon(canvas, s);
      case WeatherKind.partlySunny:
        _sun(canvas, s, center: Offset(0.36 * s, 0.34 * s), radius: 0.23 * s);
        _cloud(canvas, s, lift: -0.06);
      case WeatherKind.cloud:
        _cloud(canvas, s, lift: 0);
      case WeatherKind.lightRain:
        _cloud(canvas, s, lift: 0.08);
        _drops(canvas, s, xs: const [0.38, 0.62], top: 0.66, length: 0.14);
      case WeatherKind.heavyRain:
        _cloud(canvas, s, lift: 0.12);
        _drops(canvas, s, xs: const [0.30, 0.50, 0.70], top: 0.64, length: 0.24);
      case WeatherKind.snow:
        _cloud(canvas, s, lift: 0.10);
        final flake = Paint()..color = _flake;
        for (final (x, y) in const [(0.32, 0.72), (0.50, 0.84), (0.68, 0.72)]) {
          canvas.drawCircle(Offset(x * s, y * s), 0.055 * s, flake);
        }
    }
  }

  void _sun(Canvas canvas, double s, {required Offset center, required double radius}) {
    canvas.drawCircle(center, radius * 1.4, Paint()..color = _sunDeep.withValues(alpha: 0.18));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.35, -0.35),
          colors: [_sunLight, _sunDeep],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  /// A crescent: a disc with a bite out of its upper right.
  void _moon(Canvas canvas, double s) {
    final disc = Path()..addOval(Rect.fromCircle(center: Offset(0.48 * s, 0.52 * s), radius: 0.33 * s));
    final bite = Path()..addOval(Rect.fromCircle(center: Offset(0.64 * s, 0.40 * s), radius: 0.28 * s));
    canvas.drawPath(
      Path.combine(PathOperation.difference, disc, bite),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_moonLight, _moonDeep],
        ).createShader(Rect.fromLTWH(0, 0, s, s)),
    );
  }

  /// A cloud of three bumps on a flat base, [lift] (of the picture's height) higher than the middle to leave room for rain.
  void _cloud(Canvas canvas, double s, {required double lift}) {
    Path bump(double x, double y, double r) =>
        Path()..addOval(Rect.fromCircle(center: Offset(x * s, (y - lift) * s), radius: r * s));
    final base = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(0.10 * s, (0.46 - lift) * s, 0.90 * s, (0.72 - lift) * s),
          Radius.circular(0.13 * s),
        ),
      );
    final cloud = [
      bump(0.32, 0.50, 0.16),
      bump(0.52, 0.38, 0.22),
      bump(0.71, 0.50, 0.15),
    ].fold(base, (shape, bump) => Path.combine(PathOperation.union, shape, bump));
    canvas.drawPath(
      cloud,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_cloudLight, _cloudDeep],
        ).createShader(Rect.fromLTWH(0, 0, s, s)),
    );
    canvas.drawPath(
      cloud,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.03 * s
        ..color = _cloudEdge,
    );
  }

  void _drops(Canvas canvas, double s, {required List<double> xs, required double top, required double length}) {
    final paint = Paint()
      ..color = _drop
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 0.07 * s;
    for (final x in xs) {
      canvas.drawLine(Offset((x + 0.03) * s, top * s), Offset((x - 0.03) * s, (top + length) * s), paint);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.kind != kind;
}
