import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';

/// Turns the numbers of a reading into the plain words a farmer uses. The limits only choose the word (they match the
/// words the server speaks); the weather rules that decide risks live on the server.
enum TempBand { cold, cool, pleasant, warm, hot }

TempBand tempBand(double celsius) {
  if (celsius < 5) return TempBand.cold;
  if (celsius < 15) return TempBand.cool;
  if (celsius < 25) return TempBand.pleasant;
  if (celsius < 32) return TempBand.warm;
  return TempBand.hot;
}

enum RainBand { none, light, heavy }

RainBand rainBand(double mm) {
  if (mm < 1) return RainBand.none;
  return mm < 10 ? RainBand.light : RainBand.heavy;
}

enum HumidityBand { dry, ok, damp }

HumidityBand humidityBand(double percent) {
  if (percent < 50) return HumidityBand.dry;
  return percent < 80 ? HumidityBand.ok : HumidityBand.damp;
}

enum LeafBand { dry, damp, wet }

/// [minutes] of leaf wetness.
LeafBand leafBand(int minutes) {
  if (minutes < 60) return LeafBand.dry;
  return minutes < 240 ? LeafBand.damp : LeafBand.wet;
}

enum SoilBand { dry, ok, wet }

SoilBand soilBand(double percent) {
  if (percent < 15) return SoilBand.dry;
  return percent < 40 ? SoilBand.ok : SoilBand.wet;
}

/// The picture of a warning level (risk cards, alerts): tick, warning triangle, danger sign.
IconData severityPicture(Severity level) => switch (level) {
  Severity.green => AppIcons.tick,
  Severity.yellow => AppIcons.warning,
  Severity.red => AppIcons.danger,
};

/// The thin line round a tinted card of a level (danger card, alert): the mockup's amber and red lines, a soft green for
/// "fine".
Color severityLine(Severity level) => switch (level) {
  Severity.green => AppColors.green.withValues(alpha: 0.35),
  Severity.yellow => AppColors.amberLine,
  Severity.red => AppColors.redLine,
};

/// One big tile of "My field": a picture, one word, and the number small.
class ReadingTile {
  const ReadingTile({
    required this.id,
    required this.icon,
    required this.color,
    required this.labelKey,
    required this.wordKey,
    required this.digits,
    this.unitKey,
  });

  final String id;
  final IconData icon;
  final Color color;

  /// Interface string keys (strings.json) of the tile's title and of the word for its state.
  final String labelKey;
  final String wordKey;

  /// The measured value, written small ("17 °C"). Never spoken.
  final String digits;

  /// Interface string key of a unit that is a word and so must be translated ("hours"); null when [digits] is complete.
  final String? unitKey;
}

/// Leaf wetness written like the mockup, "6 hours": whole hours from an hour on, else minutes.
({String number, String unitKey}) leafDuration(int minutes) {
  if (minutes < 60) return (number: '$minutes', unitKey: 'field_unit_min');
  final hours = (minutes / 60).round();
  return (number: '$hours', unitKey: hours == 1 ? 'field_unit_hour' : 'field_unit_hours');
}

String _number(double value) {
  final rounded = value.roundToDouble() == value ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return rounded;
}

/// Tiles that come from the weather (not from the soil sensor): hidden when the server has weather switched off.
const weatherTileIds = {'temp', 'humidity', 'rain', 'leaf'};

/// The tiles for the readings the server sent (a missing reading has no tile). With [weather] false only the sensor
/// tiles (soil) are kept.
List<ReadingTile> readingTiles(ReadingsOut? readings, {bool weather = true}) {
  final all = _allReadingTiles(readings);
  return weather
      ? all
      : [
          for (final tile in all)
            if (!weatherTileIds.contains(tile.id)) tile,
        ];
}

List<ReadingTile> _allReadingTiles(ReadingsOut? readings) {
  if (readings == null) return const [];
  final temp = readings.tempC;
  final humidity = readings.rhPct;
  final rain = readings.rain24hMm;
  final leaf = readings.leafWetnessMin;
  final soil = readings.soilMoisturePct;
  return [
    if (temp != null)
      ReadingTile(
        id: 'temp',
        icon: AppIcons.sun,
        color: AppColors.blue,
        labelKey: 'field_label_temp',
        wordKey: 'field_temp_${tempBand(temp).name}',
        digits: '${temp.round()} °C',
      ),
    if (humidity != null)
      ReadingTile(
        id: 'humidity',
        icon: AppIcons.drop,
        color: AppColors.blue,
        labelKey: 'field_label_humidity',
        wordKey: 'field_humid_${humidityBand(humidity).name}',
        digits: '${humidity.round()} %',
      ),
    if (rain != null)
      ReadingTile(
        id: 'rain',
        icon: AppIcons.rain,
        color: AppColors.blue,
        labelKey: 'field_label_rain',
        wordKey: 'field_rain_${rainBand(rain).name}',
        digits: '${_number(rain)} mm',
      ),
    if (leaf != null)
      ReadingTile(
        id: 'leaf',
        icon: AppIcons.leaf,
        color: AppColors.blue,
        labelKey: 'field_label_leaf',
        wordKey: 'field_leaf_${leafBand(leaf).name}',
        digits: leafDuration(leaf).number,
        unitKey: leafDuration(leaf).unitKey,
      ),
    if (soil != null)
      ReadingTile(
        id: 'soil',
        icon: AppIcons.soil,
        color: AppColors.blue,
        labelKey: 'field_label_soil',
        wordKey: 'field_soil_${soilBand(soil).name}',
        digits: '${soil.round()} %',
      ),
  ];
}

/// The words of a forecast day's rain (a string key).
String forecastWordKey(double rainMm) => 'field_rain_${rainBand(rainMm).name}';
