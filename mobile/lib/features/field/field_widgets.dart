import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/design.dart';
import '../diary/date_words.dart';
import 'field_words.dart';
import 'weather_glyph.dart';

/// "This information is old": shown when the server says the sensor is quiet or the answer comes from the phone's memory.
/// An amber warning card as the mockup draws warnings: flat, a thin amber line, the round amber dot with a dark picture.
class OldInfoBanner extends ConsumerWidget {
  const OldInfoBanner({super.key, this.since});

  /// When the information is from.
  final DateTime? since;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final words = ref.watch(dateWordsProvider);
    return AppCard(
      key: const ValueKey('field-old'),
      color: AppColors.amberSoft,
      flat: true,
      line: AppColors.amberLine,
      child: Row(
        children: [
          const IconDot(AppIcons.clock, background: AppColors.amber, foreground: AppColors.ink, round: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('field_old_title'), style: AppText.hName),
                if (since != null) Text(words.written(since!), style: AppText.hMeta),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Nothing is known about this farmer's field yet: a neutral card (grey is "waiting"), the picture and the words.
class NoFieldData extends ConsumerWidget {
  const NoFieldData({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    return AppCard(
      key: const ValueKey('field-no-data'),
      color: AppColors.neutralSoft,
      flat: true,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: IconDot(
              AppIcons.offline,
              background: AppColors.card,
              foreground: AppColors.inkSoft,
              size: 72,
              round: true,
              iconSize: 38,
            ),
          ),
          const SizedBox(height: 12),
          Text(t('field_no_data_title'), textAlign: TextAlign.center, style: AppText.big),
        ],
      ),
    );
  }
}

/// The readings as tiles, two in a row (the mockup's grid, 10 apart): a blue round picture, the title, one word, the
/// number small. Tapping a tile says its title and word.
class ReadingTiles extends ConsumerWidget {
  const ReadingTiles({super.key, required this.tiles, required this.onSpeak});

  final List<ReadingTile> tiles;

  /// Called with the sentence to say (title and word, no number).
  final void Function(String sentence) onSpeak;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    Widget tileCard(ReadingTile tile) => AppCard(
      key: ValueKey('reading-${tile.id}'),
      onTap: () => onSpeak('${t(tile.labelKey)}, ${t(tile.wordKey)}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconDot(tile.icon, background: AppColors.blueSoft, foreground: tile.color, size: 40, round: true),
          const SizedBox(height: 10),
          Text(t(tile.labelKey), style: AppText.hMeta),
          Text(
            t(tile.wordKey),
            key: ValueKey('reading-word-${tile.id}'),
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.35),
          ),
          Text(
            tile.unitKey == null ? tile.digits : '${tile.digits} ${t(tile.unitKey!)}',
            key: ValueKey('reading-digits-${tile.id}'),
            style: AppText.hMeta,
          ),
        ],
      ),
    );

    // Both cards of a row are as tall as the taller one; a lone last tile keeps half the width.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < tiles.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tileCard(tiles[i])),
                const SizedBox(width: 10),
                Expanded(child: i + 1 < tiles.length ? tileCard(tiles[i + 1]) : const SizedBox.shrink()),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Seven days in one white card, seven equal columns, in the style of a weather app's strip: the day's name on top (grey, today in
/// bold ink on a soft panel), a coloured weather picture (sun, cloud with a little rain, cloud with a lot), the high in bold and the
/// low in grey. The word for the rain is in the day's semantics label.
class ForecastStrip extends ConsumerWidget {
  const ForecastStrip({super.key, required this.days});

  final List<ForecastDayOut> days;

  static const _columns = 7;
  static const glyphSize = 32.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final words = ref.watch(dateWordsProvider);
    final now = ref.watch(clockProvider)();
    const small = TextStyle(fontSize: 13, height: 1.35);
    Widget fit(Widget child) => FittedBox(fit: BoxFit.scaleDown, child: child);

    Widget column(ForecastDayOut day) {
      final date = DateTime.tryParse(day.day);
      final today = date != null && daysAgo(date, now) == 0;
      final name = date == null ? '' : (today ? words.today : words.shortWeekday(date));
      final rainWord = t(forecastWordKey(day.rainMm));
      return Semantics(
        container: true,
        label: '$name, $rainWord',
        excludeSemantics: true,
        child: DecoratedBox(
          // Today stands on a soft panel, like the "Now" of a weather strip.
          decoration: BoxDecoration(
            color: today ? AppColors.paper : null,
            borderRadius: BorderRadius.circular(Dimens.radiusSmall),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              key: ValueKey('forecast-${day.day}'),
              mainAxisSize: MainAxisSize.min,
              children: [
                fit(
                  Text(
                    name,
                    style: small.copyWith(
                      fontWeight: today ? FontWeight.w800 : FontWeight.w600,
                      color: today ? AppColors.ink : AppColors.inkSoft,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                WeatherGlyph(
                  key: ValueKey('forecast-glyph-${day.day}'),
                  kind: weatherKindOfRain(day.rainMm),
                  size: glyphSize,
                ),
                const SizedBox(height: 8),
                fit(
                  Text(
                    '${day.tmaxC.round()}°',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                fit(Text('${day.tminC.round()}°', style: small.copyWith(color: AppColors.inkSoft))),
              ],
            ),
          ),
        ),
      );
    }

    return AppCard(
      key: const ValueKey('forecast-strip'),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _columns; i++)
            Expanded(child: i < days.length ? column(days[i]) : const SizedBox.shrink()),
        ],
      ),
    );
  }
}
