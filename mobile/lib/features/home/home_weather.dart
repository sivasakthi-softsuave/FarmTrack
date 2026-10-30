import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/voice/speak_on_enter.dart';
import '../../core/voice/utterance.dart';
import '../../core/widgets/design.dart';
import '../diary/date_words.dart';
import '../field/current_weather.dart';
import '../field/field_providers.dart';
import '../field/field_words.dart';
import '../field/weather_glyph.dart';
import '../field/weather_words.dart';

/// The mockup's 12 px gap between the blocks of a page, and the 10 px (12 minus the label's -2) under a section label.
const _blockGap = 12.0;
const _labelGap = 10.0;

/// Whether Home can show the weather blocks for this answer: some temperature or condition to draw the big card from.
bool homeWeatherHasData(FieldOut field) => CurrentWeatherCard.hasData(field);

/// The weather part of Home (the owner's choice "option B", 29 Oct 2026): one big card whose colour follows the sky, the next hours, the
/// "can I spray today?" check, the rain of the week as a chart, and the details of the air and the sun. Every block is optional: the
/// server may have no hours, no spray check or no sun times, and then the block is simply not there. The numbers are for the eyes; the
/// voice says the server's own words (and, on a touch, the words of the spray check and the rain), never digits.
class HomeWeather extends ConsumerWidget {
  const HomeWeather({super.key, required this.view, required this.placeName, required this.picked});

  final FieldView view;

  /// The place of the header line ("Navalur", or "Kotgarh, Shimla" for the farmer's own field): the big card names it.
  final String placeName;

  /// The farmer chose another place: the heading says "this place" instead of "your field".
  final bool picked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final now = ref.watch(clockProvider)();
    final field = view.field;
    final heading = t(picked ? 'field_place_now' : 'field_readings_title');
    // Hours that are over are not shown (an answer kept on the phone for a day has none left). A spray verdict of an old answer is
    // never shown: it would say "good time" about weather that has gone.
    final hours = [
      for (final h in field.hours)
        if (h.time.add(const Duration(hours: 1)).isAfter(now)) h,
    ];
    final spray = view.fromCache ? null : field.spray;
    final week = field.forecast.take(7).toList();
    final tiles = _airTiles(t, field);

    Widget block(String label, Widget child) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: _blockGap),
        SectionLabel(label, hindi: isDevanagari(label)),
        const SizedBox(height: _labelGap),
        child,
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeadingRow(heading: heading, place: shortPlaceName(placeName)),
        _Hero(field: field, placeName: placeName, at: field.asOf ?? now),
        if (hours.isNotEmpty) block(t('home_hours_title'), _HoursCard(hours: hours)),
        if (spray != null) block(t('home_spray_title'), _SprayCard(spray: spray, hoursKnown: hours.length)),
        if (week.isNotEmpty) block(t('home_rain_title'), _RainWeekCard(days: week)),
        if (tiles.isNotEmpty) block(t('home_air_title'), _AirGrid(tiles: tiles)),
      ],
    );
  }
}

/// The name of a place for the heading row: only the first part ("Navalur" of "Navalur, Thiruporur"). A name that is still wider than the
/// room it has is cut with "…" by the row itself.
String shortPlaceName(String place) => place.split(',').first.trim();

/// "NOW AT THIS PLACE" and, at the right, the name of the place in green (the first part of it, and "…" where it does not fit). The heading
/// keeps its words (up to about two thirds of the row); the place gets the rest. The card below opens My field.
class _HeadingRow extends StatelessWidget {
  const _HeadingRow({required this.heading, required this.place});

  final String heading;

  /// The short name of the place; empty when the farmer has no place yet (then only the heading shows).
  final String place;

  @override
  Widget build(BuildContext context) => MediaQuery.withClampedTextScaling(
    maxScaleFactor: 1.3,
    child: SizedBox(
      height: Dimens.minTouch,
      child: LayoutBuilder(
        builder: (context, box) => Row(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: box.maxWidth * 0.64),
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  isDevanagari(heading) ? heading : heading.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: isDevanagari(heading) ? AppText.labelHindi : AppText.label,
                ),
              ),
            ),
            if (place.isNotEmpty)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, top: 6),
                  child: Semantics(
                    label: place,
                    excludeSemantics: true,
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.location_on_outlined, size: 16, color: AppColors.green),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              place,
                              key: const ValueKey('home-weather-place'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.green),
                            ),
                          ),
                        ],
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

// ------------------------------------------------------------------------------------------------ the big card

/// The colours of the big card for a sky: the top of the gradient, the bottom, and the glow of the sun or moon in its corner. The
/// bottoms are dark enough for white text (4.5 to 1 or better, `test/home_weather_test.dart` checks).
({Color top, Color bottom, Color glow}) heroColors(HeroSky sky) => switch (sky) {
  HeroSky.sunny => (top: const Color(0xFF165DA9), bottom: const Color(0xFF2874C0), glow: const Color(0x99FFCF6E)),
  HeroSky.hot => (top: const Color(0xFF9E3F0E), bottom: const Color(0xFFB85516), glow: const Color(0x99FFE08C)),
  HeroSky.cloud => (top: const Color(0xFF33506F), bottom: const Color(0xFF52729A), glow: const Color(0x47FFFFFF)),
  HeroSky.rain => (top: const Color(0xFF26356F), bottom: const Color(0xFF3F559A), glow: const Color(0x52A0BEFF)),
  HeroSky.night => (top: const Color(0xFF0C1D3F), bottom: const Color(0xFF1D3768), glow: const Color(0x4DBED2FF)),
};

/// A text on one line that shrinks instead of wrapping.
Widget _fit(String text, TextStyle style, {AlignmentGeometry alignment = AlignmentDirectional.centerStart, Key? key}) =>
    FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignment,
      child: Text(text, key: key, maxLines: 1, style: style),
    );

class _Hero extends ConsumerWidget {
  const _Hero({required this.field, required this.placeName, required this.at});

  final FieldOut field;
  final String placeName;

  /// When the weather is from (shown beside the place).
  final DateTime at;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final now = ref.watch(clockProvider)();
    final c = field.conditions ?? const ConditionsOut();
    final r = field.readings;
    final temp = r?.tempC;
    final sky = heroSkyOf(sky: c.sky, isDay: c.isDay, tempC: temp);
    final colors = heroColors(sky);
    final skyKey = skyWordKey(c.sky, isDay: c.isDay ?? true);
    final feels = c.feelsLikeC;
    final range = _todayRange(field.forecast, now);

    final airWord = r?.rhPct == null ? null : t('field_humid_${humidityBand(r!.rhPct!).name}');
    final rainWord = r?.rain24hMm == null ? null : t(forecastWordKey(r!.rain24hMm!));
    final windWord = c.windKmh == null ? null : t(windWordKey(c.windKmh!));
    final chips = <Widget>[
      if (r?.rhPct != null)
        _GlassChip(
          id: 'air',
          icon: AppIcons.drop,
          label: t('field_label_humidity'),
          value: '${r!.rhPct!.round()} %',
          word: airWord!,
        ),
      if (r?.rain24hMm != null)
        _GlassChip(
          id: 'rain',
          icon: AppIcons.rain,
          label: t('field_label_rain'),
          value: '${plainNumber(r!.rain24hMm!)} mm',
          word: rainWord!,
        ),
      if (c.windKmh != null)
        _GlassChip(
          id: 'wind',
          icon: Icons.air,
          label: t('weather_wind'),
          value: '${c.windKmh!.round()} ${t('weather_unit_kmh')}',
          word: windWord!,
        ),
    ];

    final place = [if (placeName.isNotEmpty) placeName, clockText(t, at)].join(' · ');
    final rangeText = range == null
        ? null
        : t('home_hero_day', args: {'low': '${range.tminC.round()}', 'high': '${range.tmaxC.round()}'});
    final label = [
      placeName,
      if (temp != null) '${temp.round()} °C',
      if (skyKey != null) t(skyKey),
      if (feels != null) t('weather_feels_like', args: {'temp': '${feels.round()}'}),
      ?rangeText,
      if (airWord != null) '${t('field_label_humidity')} $airWord',
      if (rainWord != null) '${t('field_label_rain')} $rainWord',
      if (windWord != null) '${t('weather_wind')} $windWord',
    ].where((p) => p.isNotEmpty).join('. ');

    const white = Colors.white;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: DecoratedBox(
          key: const ValueKey('home-hero'),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colors.top, colors.bottom],
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x1F102818), blurRadius: 4, offset: Offset(0, 2)),
              BoxShadow(color: Color(0x29102818), blurRadius: 22, offset: Offset(0, 10)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Stack(
              children: [
                // The glow of the sun (or moon) in the upper right corner.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0.76, -1.15),
                        radius: 0.9,
                        colors: [colors.glow, colors.glow.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ),
                Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: () {
                      Haptics.tap();
                      context.push(Routes.field);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.location_on_outlined, size: 16, color: white),
                                    const SizedBox(width: 5),
                                    Flexible(
                                      child: _fit(
                                        place,
                                        const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: white),
                                        key: const ValueKey('home-hero-place'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              if (c.sky != null) ...[
                                WeatherGlyph(
                                  key: const ValueKey('home-hero-glyph'),
                                  kind: weatherKindOfSky(c.sky, isDay: c.isDay ?? true),
                                  size: MediaQuery.sizeOf(context).width < 340 ? 52 : 64,
                                ),
                                const SizedBox(width: 10),
                              ],
                              if (temp != null)
                                Flexible(
                                  flex: 3,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: AlignmentDirectional.centerStart,
                                    child: Text.rich(
                                      key: const ValueKey('home-hero-temp'),
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text: '${temp.round()}',
                                            style: const TextStyle(
                                              fontSize: 56,
                                              fontWeight: FontWeight.w800,
                                              height: 1,
                                              letterSpacing: -1,
                                              color: white,
                                            ),
                                          ),
                                          const TextSpan(
                                            text: '°C',
                                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: white),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (skyKey != null)
                                      _fit(
                                        t(skyKey),
                                        const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          height: 1.25,
                                          color: white,
                                        ),
                                        alignment: AlignmentDirectional.centerEnd,
                                        key: const ValueKey('home-hero-sky'),
                                      ),
                                    if (feels != null)
                                      // May wrap to a second line: a long Hindi sentence stays readable instead of shrinking.
                                      Text(
                                        t('weather_feels_like', args: {'temp': '${feels.round()}'}),
                                        key: const ValueKey('home-hero-feels'),
                                        maxLines: 2,
                                        textAlign: TextAlign.end,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w500,
                                          height: 1.4,
                                          color: white,
                                        ),
                                      ),
                                    if (rangeText != null)
                                      // One line (a break inside "26° – 34°" reads badly): it shrinks a little instead.
                                      _fit(
                                        rangeText,
                                        const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w500,
                                          height: 1.4,
                                          color: white,
                                        ),
                                        alignment: AlignmentDirectional.centerEnd,
                                        key: const ValueKey('home-hero-range'),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (chips.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (var i = 0; i < chips.length; i++) ...[
                                    if (i > 0) const SizedBox(width: 8),
                                    Expanded(child: chips[i]),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Today's low and high from the week (null when the week does not have today).
  static ForecastDayOut? _todayRange(List<ForecastDayOut> week, DateTime now) {
    for (final day in week) {
      final date = DateTime.tryParse(day.day);
      if (date != null && daysAgo(date, now) == 0) return day;
    }
    return null;
  }
}

/// One of the three small glass boxes in the big card (air, rain, wind): a name, the number and a word.
class _GlassChip extends StatelessWidget {
  const _GlassChip({
    required this.id,
    required this.icon,
    required this.label,
    required this.value,
    required this.word,
  });

  final String id;
  final IconData icon;
  final String label;
  final String value;
  final String word;

  @override
  Widget build(BuildContext context) {
    const white = Colors.white;
    return DecoratedBox(
      key: ValueKey('home-chip-$id'),
      decoration: BoxDecoration(
        // A dark glass (not a white one) keeps the white words readable on the lightest sky.
        color: Colors.black.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: white),
                const SizedBox(width: 5),
                Expanded(
                  child: _fit(label, const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: white)),
                ),
              ],
            ),
            _fit(
              value,
              const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, height: 1.25, color: white),
              key: ValueKey('home-chip-value-$id'),
            ),
            _fit(word, const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: white)),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------------------------------------ next hours

class _HoursCard extends ConsumerWidget {
  const _HoursCard({required this.hours});

  final List<HourOut> hours;

  static const _columnWidth = 56.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: AppCard(
        key: const ValueKey('home-hours'),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        // The picture is 32 high and the three lines of words grow with the text size: so does the strip.
        child: Builder(
          builder: (context) => SizedBox(
            height: (40 + 56 * MediaQuery.textScalerOf(context).scale(1)).ceilToDouble(),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: hours.length,
              itemExtent: _columnWidth,
              itemBuilder: (context, i) {
                final h = hours[i];
                final first = i == 0;
                final time = first ? t('home_hour_now') : clockText(t, h.time, minutes: false);
                final skyKey = skyWordKey(h.sky, isDay: h.isDay ?? true);
                final temp = h.tempC == null ? null : '${h.tempC!.round()}°';
                final chance = h.rainChancePct;
                final chanceText = chance == null || chance <= 0 ? '–' : '$chance %';
                return Semantics(
                  container: true,
                  excludeSemantics: true,
                  label: [
                    time,
                    ?temp,
                    if (skyKey != null) t(skyKey),
                    if (chance != null && chance > 0) '${t('field_label_rain')} $chance %',
                  ].join(', '),
                  child: Column(
                    key: ValueKey('home-hour-$i'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _fit(
                        time,
                        TextStyle(
                          fontSize: 12.5,
                          fontWeight: first ? FontWeight.w800 : FontWeight.w600,
                          color: first ? AppColors.ink : AppColors.inkSoft,
                        ),
                        alignment: Alignment.center,
                      ),
                      const SizedBox(height: 4),
                      WeatherGlyph(kind: weatherKindOfSky(h.sky, isDay: h.isDay ?? true), size: 32),
                      const SizedBox(height: 2),
                      if (temp != null)
                        _fit(
                          temp,
                          const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink),
                          alignment: Alignment.center,
                        ),
                      _fit(
                        chanceText,
                        TextStyle(
                          fontSize: 12,
                          fontWeight: chanceText == '–' ? FontWeight.w500 : FontWeight.w700,
                          color: chanceText == '–' ? AppColors.chevron : AppColors.blue,
                        ),
                        alignment: Alignment.center,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------------------------------------ can I spray today?

/// The look of the three answers: the card's gradient and line, and the colour of the round sign. Green is yes, amber is "be careful"
/// and red is "not now", the same meanings as everywhere in the app.
({Color top, Color bottom, Color line, Color sign, Color signInk}) _sprayColors(SprayStatus state) => switch (state) {
  SprayStatus.ok => (
    top: const Color(0xFFE8F6EC),
    bottom: const Color(0xFFCBEAD4),
    line: const Color(0xFFA9D3B4),
    sign: AppColors.green,
    signInk: Colors.white,
  ),
  SprayStatus.care => (
    top: const Color(0xFFFFF6DC),
    bottom: const Color(0xFFFDE5A6),
    line: AppColors.amberLine,
    sign: AppColors.amber,
    signInk: const Color(0xFF3A2A00),
  ),
  SprayStatus.stop => (
    top: const Color(0xFFFDECEA),
    bottom: const Color(0xFFF7C9C4),
    line: AppColors.redLine,
    sign: AppColors.red,
    signInk: Colors.white,
  ),
};

IconData _statusIcon(SprayStatus s) => switch (s) {
  SprayStatus.ok => AppIcons.tick,
  SprayStatus.care => AppIcons.warning,
  SprayStatus.stop => AppIcons.cross,
};

/// What the card says (on the screen) and what a touch makes the voice say (no digits), for the answer of the server.
({String title, String say, String speak}) sprayWords(Translate t, SprayOut spray, {required int hoursKnown}) {
  final title = t(switch (spray.state) {
    SprayStatus.ok => 'spray_go',
    SprayStatus.care => 'spray_care',
    SprayStatus.stop => 'spray_stop',
  });
  final rainHours = spray.rain.hours;
  switch (spray.headline) {
    case 'raining':
      return (title: title, say: t('spray_say_raining'), speak: t('spray_speak_raining'));
    case 'rain_soon':
      return (
        title: title,
        say: t('spray_say_rain_soon', args: {'h': rainHours ?? 3}),
        speak: t(spray.state == SprayStatus.stop ? 'spray_speak_rain_soon' : 'spray_speak_rain_later'),
      );
    case 'windy':
      return (title: title, say: t('spray_say_windy'), speak: t('spray_speak_wind'));
    case 'hot':
      return (title: title, say: t('spray_say_hot'), speak: t('spray_speak_hot'));
  }
  // `calm_dry`, or a reason this app does not know: the title alone says it when the state is not "good".
  if (spray.state == SprayStatus.ok) {
    return (
      title: title,
      say: t('spray_say_calm_dry', args: {'h': rainHours ?? hoursKnown}),
      speak: t('spray_speak_go'),
    );
  }
  return (title: title, say: title, speak: title);
}

class _SprayCard extends ConsumerWidget {
  const _SprayCard({required this.spray, required this.hoursKnown});

  final SprayOut spray;

  /// How many hours the server looked at (the dry time when no rain was found in them).
  final int hoursKnown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final words = sprayWords(t, spray, hoursKnown: hoursKnown);
    final colors = _sprayColors(spray.state);

    final windValue = spray.wind.value;
    final windText = windValue == null
        ? '–'
        : t(
            'spray_wind_value',
            args: {
              'kmh': windValue.round(),
              'word': t(switch (spray.wind.status) {
                SprayStatus.ok => windWordKey(windValue).replaceFirst('home_wind_', 'spray_word_'),
                SprayStatus.care => 'spray_word_windy',
                SprayStatus.stop => 'spray_word_very_windy',
              }),
            },
          );
    final rain = spray.rain;
    final rainText = rain.value == null && rain.hours == null
        ? '–'
        : switch (rain.status) {
            SprayStatus.stop when spray.headline == 'raining' => t('spray_rain_now'),
            SprayStatus.stop => t('spray_rain_stop', args: {'mm': plainNumber(rain.value ?? 0)}),
            SprayStatus.care => rain.hours == null ? '–' : t('spray_rain_care', args: {'h': rain.hours!}),
            SprayStatus.ok =>
              rain.hours == null ? t('spray_rain_ok_day') : t('spray_rain_ok', args: {'h': rain.hours!}),
          };
    final heatValue = spray.heat.value;
    final heatText = heatValue == null
        ? '–'
        : t(
            switch (spray.heat.status) {
              SprayStatus.ok => 'spray_heat_ok',
              SprayStatus.care => 'spray_heat_care',
              SprayStatus.stop => 'spray_heat_stop',
            },
            args: {'t': heatValue.round()},
          );

    final lang = ref.watch(languageProvider);
    final checks = [
      ('wind', t('weather_wind'), windText, spray.wind.status),
      ('rain', t('spray_rain'), rainText, spray.rain.status),
      ('heat', t('spray_heat'), heatText, spray.heat.status),
    ];

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Semantics(
        button: true,
        label: '${words.title}. ${words.say}',
        excludeSemantics: true,
        child: DecoratedBox(
          key: ValueKey('home-spray-${spray.state.wire}'),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: colors.line, width: 1.5),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colors.top, colors.bottom],
            ),
            boxShadow: AppDecor.shadows,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () {
                Haptics.tap();
                unawaited(
                  ref.read(voiceServiceProvider).speak([
                    TextUtterance(words.speak, lang: lang),
                  ], owner: VoiceSession.maybeOf(context)?.owner),
                );
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(color: colors.sign, shape: BoxShape.circle),
                          child: Icon(_statusIcon(spray.state), size: 28, color: colors.signInk),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                words.title,
                                key: const ValueKey('home-spray-title'),
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.25),
                              ),
                              Text(
                                words.say,
                                key: const ValueKey('home-spray-say'),
                                style: const TextStyle(fontSize: 13.5, height: 1.35, color: Color(0xFF34403A)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < checks.length; i++) ...[
                            if (i > 0) const SizedBox(width: 6),
                            Expanded(
                              child: _SprayCheck(
                                id: checks[i].$1,
                                name: checks[i].$2,
                                value: checks[i].$3,
                                status: checks[i].$4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SprayCheck extends StatelessWidget {
  const _SprayCheck({required this.id, required this.name, required this.value, required this.status});

  final String id;
  final String name;
  final String value;
  final SprayStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      SprayStatus.ok => AppColors.green,
      SprayStatus.care => AppColors.amberDark,
      SprayStatus.stop => AppColors.red,
    };
    return DecoratedBox(
      key: ValueKey('home-spray-check-$id'),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.62), borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_statusIcon(status), size: 15, color: color),
                const SizedBox(width: 4),
                Expanded(child: _fit(name, const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
              ],
            ),
            Text(
              value,
              key: ValueKey('home-spray-value-$id'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------------------------------------ rain of the week

/// What the rain card says about the week: on the screen with the number of millimetres, and for the voice without digits. Null days
/// (a week without a usable date) are skipped.
({String say, String speak}) rainWeekWords(Translate t, DateWords words, List<ForecastDayOut> days, DateTime now) {
  var total = 0.0;
  ForecastDayOut? next;
  DateTime? nextDate;
  for (final day in days) {
    final date = DateTime.tryParse(day.day);
    if (date == null) continue;
    total += day.rainMm;
    if (next == null && rainBand(day.rainMm) != RainBand.none) {
      next = day;
      nextDate = date;
    }
  }
  final mm = plainNumber(total);
  if (next == null || nextDate == null) {
    return (say: t('home_rain_none'), speak: t('home_rain_say_none'));
  }
  if (daysAgo(nextDate, now) == 0) {
    return (say: t('home_rain_today', args: {'mm': mm}), speak: t('home_rain_say_today'));
  }
  final name = words.weekday(nextDate);
  return (say: t('home_rain_next', args: {'day': name, 'mm': mm}), speak: t('home_rain_say_next', args: {'day': name}));
}

class _RainWeekCard extends ConsumerWidget {
  const _RainWeekCard({required this.days});

  final List<ForecastDayOut> days;

  static const _barsHeight = 118.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final words = ref.watch(dateWordsProvider);
    final now = ref.watch(clockProvider)();
    final lang = ref.watch(languageProvider);
    final sentence = rainWeekWords(t, words, days, now);
    // The tallest bar is the wettest day, but a light week never fills the chart: 6 mm is already a full bar.
    final top = days.fold<double>(6, (m, d) => d.rainMm > m ? d.rainMm : m);

    Widget column(ForecastDayOut day) {
      final date = DateTime.tryParse(day.day);
      final today = date != null && daysAgo(date, now) == 0;
      final name = date == null ? '' : (today ? words.today : words.shortWeekday(date));
      final wet = day.rainMm > 0;
      return Semantics(
        container: true,
        excludeSemantics: true,
        label: '$name, ${t(forecastWordKey(day.rainMm))}',
        child: Column(
          key: ValueKey('home-rain-${day.day}'),
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _fit(
              plainNumber(day.rainMm),
              TextStyle(
                fontSize: 12,
                fontWeight: wet ? FontWeight.w700 : FontWeight.w500,
                color: wet ? AppColors.blue : AppColors.chevron,
              ),
              alignment: Alignment.center,
            ),
            const SizedBox(height: 3),
            Container(
              width: 22,
              height: wet ? 12 + 56 * (day.rainMm / top).clamp(0.0, 1.0) : 4,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8), bottom: Radius.circular(3)),
                gradient: wet
                    ? const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF8FBFF2), Color(0xFF3B82D4)],
                      )
                    : null,
                color: wet ? null : const Color(0xFFD8E1D9),
              ),
            ),
            const SizedBox(height: 4),
            _fit(
              name,
              TextStyle(
                fontSize: 12.5,
                fontWeight: today ? FontWeight.w800 : FontWeight.w600,
                color: today ? AppColors.ink : AppColors.inkSoft,
              ),
              alignment: Alignment.center,
            ),
          ],
        ),
      );
    }

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: AppCard(
        key: const ValueKey('home-rain-week'),
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: _barsHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [for (final day in days) Expanded(child: column(day))],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1, thickness: 1, color: AppColors.line),
            Semantics(
              button: true,
              label: sentence.say,
              excludeSemantics: true,
              child: InkWell(
                key: const ValueKey('home-rain-say'),
                borderRadius: BorderRadius.circular(Dimens.radiusSmall),
                onTap: () {
                  Haptics.tap();
                  unawaited(
                    ref.read(voiceServiceProvider).speak([
                      TextUtterance(sentence.speak, lang: lang),
                    ], owner: VoiceSession.maybeOf(context)?.owner),
                  );
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: Dimens.minTouch),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        const IconDot(
                          AppIcons.speaker,
                          background: AppColors.blueSoft,
                          foreground: AppColors.blue,
                          size: 32,
                          iconSize: 18,
                          round: true,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            sentence.say,
                            key: const ValueKey('home-rain-sentence'),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------------------------------------ the air and the sun

class _AirTile {
  const _AirTile({
    required this.id,
    required this.icon,
    required this.label,
    required this.value,
    required this.note,
    required this.top,
    required this.bottom,
    required this.ink,
    this.dot,
  });

  final String id;
  final IconData icon;
  final String label;
  final String value;
  final String note;
  final Color top;
  final Color bottom;

  /// The colour of the small picture before the name.
  final Color ink;

  /// A dot before the value (the band of the air quality).
  final Color? dot;
}

/// The tiles of the details, in the order of the mockup; one the server has no number for is not there.
List<_AirTile> _airTiles(Translate t, FieldOut field) {
  final c = field.conditions;
  if (c == null) return const [];
  final sunrise = c.sunrise;
  final sunset = c.sunset;
  final uv = c.uvIndex;
  return [
    if (c.aqi != null)
      () {
        final band = aqiBand(c.aqi!);
        return _AirTile(
          id: 'aqi',
          icon: Icons.air,
          label: t('weather_aqi'),
          value: '${c.aqi}',
          note: t(aqiWordKey(band)),
          top: const Color(0xFFFFF3D6),
          bottom: const Color(0xFFFCDD9A),
          ink: AppColors.amberDark,
          dot: AppColors.severity(aqiSeverity(band)),
        );
      }(),
    if (c.visibilityKm != null)
      _AirTile(
        id: 'visibility',
        icon: Icons.visibility_outlined,
        label: t('weather_visibility'),
        value: '${plainNumber(c.visibilityKm!)} ${t('weather_unit_km')}',
        note: t(visibilityWordKey(c.visibilityKm!)),
        top: const Color(0xFFE5F0FB),
        bottom: const Color(0xFFBCD8F3),
        ink: AppColors.blue,
      ),
    if (c.dewPointC != null)
      _AirTile(
        id: 'dew',
        icon: AppIcons.drop,
        label: t('weather_dew'),
        value: '${c.dewPointC!.round()}°',
        note: t('home_dew_note'),
        top: const Color(0xFFE3F4F5),
        bottom: const Color(0xFFB4DEE3),
        ink: const Color(0xFF136C77),
      ),
    if (c.pressureHpa != null)
      _AirTile(
        id: 'pressure',
        icon: Icons.speed,
        label: t('weather_pressure'),
        value: '${c.pressureHpa!.round()} ${t('weather_unit_mb')}',
        note: t('home_pressure_note'),
        top: const Color(0xFFECEEF8),
        bottom: const Color(0xFFCDD3EE),
        ink: const Color(0xFF3B4A9B),
      ),
    if (sunrise != null)
      _AirTile(
        id: 'sun',
        icon: Icons.wb_twilight,
        label: t('home_sun_title'),
        value: clockText(t, sunrise),
        note: sunset == null ? '' : t('home_sun_sets', args: {'time': clockText(t, sunset)}),
        top: const Color(0xFFFFF0D2),
        bottom: const Color(0xFFFFD79A),
        ink: const Color(0xFFA24F00),
      ),
    if (uv != null)
      _AirTile(
        id: 'uv',
        icon: AppIcons.sun,
        label: t('home_uv_title'),
        value: plainNumber(uv),
        note: t(uvWordKey(uv)),
        top: const Color(0xFFFBE6DD),
        bottom: const Color(0xFFF2B9A3),
        ink: const Color(0xFFA52F12),
      ),
  ];
}

class _AirGrid extends StatelessWidget {
  const _AirGrid({required this.tiles});

  final List<_AirTile> tiles;

  @override
  Widget build(BuildContext context) => MediaQuery.withClampedTextScaling(
    maxScaleFactor: 1.2,
    child: Column(
      key: const ValueKey('home-air-grid'),
      children: [
        for (var i = 0; i < tiles.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 8),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _Tile(tile: tiles[i])),
                const SizedBox(width: 8),
                Expanded(child: i + 1 < tiles.length ? _Tile(tile: tiles[i + 1]) : const SizedBox.shrink()),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.tile});

  final _AirTile tile;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    excludeSemantics: true,
    label: '${tile.label} ${tile.value}${tile.note.isEmpty ? '' : ', ${tile.note}'}',
    child: DecoratedBox(
      key: ValueKey('home-tile-${tile.id}'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tile.top, tile.bottom]),
        boxShadow: const [
          BoxShadow(color: Color(0x0F102818), blurRadius: 2, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x0F102818), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(tile.icon, size: 18, color: tile.ink),
                const SizedBox(width: 6),
                Expanded(
                  child: _fit(
                    tile.label,
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xC717201A)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                if (tile.dot != null) ...[
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(color: tile.dot, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: _fit(
                    tile.value,
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.2, color: AppColors.ink),
                    key: ValueKey('home-tile-value-${tile.id}'),
                  ),
                ),
              ],
            ),
            if (tile.note.isNotEmpty)
              Text(
                tile.note,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, height: 1.3, color: Color(0xC717201A)),
              ),
          ],
        ),
      ),
    ),
  );
}
