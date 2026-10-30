import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/design.dart';
import 'weather_glyph.dart';
import 'weather_words.dart';

/// "Weather now", in the style of a weather app: the picture of the sky, the temperature big, the word for the sky and how it
/// feels, and under a hairline the details: air quality, wind, humidity, visibility, pressure and dew point (each only when
/// the server knows it). The numbers are for the eyes; the voice says the server's own summary, never digits.
class CurrentWeatherCard extends ConsumerWidget {
  const CurrentWeatherCard({super.key, required this.field});

  final FieldOut field;

  /// Whether there is anything for the card to show: the temperature, or any of the conditions.
  static bool hasData(FieldOut field) => field.readings?.tempC != null || !(field.conditions?.isEmpty ?? true);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final temp = field.readings?.tempC;
    final humidity = field.readings?.rhPct;
    final c = field.conditions ?? const ConditionsOut();
    final isDay = c.isDay ?? true;
    final skyKey = skyWordKey(c.sky, isDay: isDay);
    final feels = c.feelsLikeC;

    final details = <_DetailData>[
      if (c.aqi != null) _aqi(t, c.aqi!),
      if (c.windKmh != null) _DetailData('wind', t('weather_wind'), '${c.windKmh!.round()} ${t('weather_unit_kmh')}'),
      if (humidity != null) _DetailData('humidity', t('weather_humidity'), '${humidity.round()} %'),
      if (c.visibilityKm != null)
        _DetailData('visibility', t('weather_visibility'), '${plainNumber(c.visibilityKm!)} ${t('weather_unit_km')}'),
      if (c.pressureHpa != null)
        _DetailData('pressure', t('weather_pressure'), '${c.pressureHpa!.round()} ${t('weather_unit_mb')}'),
      if (c.dewPointC != null) _DetailData('dew', t('weather_dew'), '${c.dewPointC!.round()}°'),
    ];

    return AppCard(
      key: const ValueKey('weather-card'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (c.sky != null) ...[
                WeatherGlyph(
                  key: const ValueKey('weather-glyph'),
                  kind: weatherKindOfSky(c.sky, isDay: isDay),
                  size: 56,
                ),
                const SizedBox(width: 12),
              ],
              if (temp != null)
                // A big decorative number: it stays the same size whatever the text size, so that it never pushes the words out.
                MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.15,
                  child: Text.rich(
                    key: const ValueKey('weather-temp'),
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${temp.round()}',
                          style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w500, height: 1.1),
                        ),
                        const TextSpan(
                          text: '°C',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: AppColors.inkSoft),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (skyKey != null)
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          t(skyKey),
                          key: const ValueKey('weather-sky'),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.3),
                        ),
                      ),
                    if (feels != null)
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          t('weather_feels_like', args: {'temp': '${feels.round()}'}),
                          key: const ValueKey('weather-feels'),
                          style: const TextStyle(fontSize: 14, color: AppColors.inkSoft, height: 1.35),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(height: 1, thickness: 1, color: AppColors.line),
            const SizedBox(height: 14),
            for (var i = 0; i < details.length; i += _perRow) ...[
              if (i > 0) const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var j = i; j < i + _perRow; j++)
                    Expanded(child: j < details.length ? _Detail(data: details[j]) : const SizedBox.shrink()),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  static const _perRow = 3;

  /// The air quality: a dot in the colour of its band, the index, and the band in words under it.
  static _DetailData _aqi(String Function(String key, {Map<String, Object> args}) t, int aqi) {
    final band = aqiBand(aqi);
    return _DetailData(
      'aqi',
      t('weather_aqi'),
      '$aqi',
      note: t(aqiWordKey(band)),
      dot: AppColors.severity(aqiSeverity(band)),
    );
  }
}

class _DetailData {
  const _DetailData(this.id, this.label, this.value, {this.note, this.dot});

  final String id;
  final String label;
  final String value;

  /// A word under the value (the band of the air quality).
  final String? note;

  /// A dot before the value.
  final Color? dot;
}

/// One detail: the name in grey, the value in bold (and, for the air quality, a dot before it and its word under it). Long words
/// shrink instead of wrapping, so the three columns stay level.
class _Detail extends StatelessWidget {
  const _Detail({required this.data});

  final _DetailData data;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: Column(
      key: ValueKey('weather-detail-${data.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(data.label, style: AppText.hMeta.copyWith(fontSize: 13)),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (data.dot != null) ...[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: data.dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                data.value,
                key: ValueKey('weather-value-${data.id}'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.35),
              ),
            ],
          ),
        ),
        if (data.note != null)
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(data.note!, style: AppText.hMeta.copyWith(fontSize: 13)),
          ),
      ],
    ),
  );
}
