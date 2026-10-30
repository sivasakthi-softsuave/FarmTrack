import '../../core/models/models.dart';

/// The skies the server names (`ConditionsOut.sky`).
const _skies = {
  'clear',
  'mostly_clear',
  'partly_cloudy',
  'cloudy',
  'fog',
  'drizzle',
  'rain',
  'heavy_rain',
  'showers',
  'snow',
  'thunderstorm',
};

/// The interface string key of the word for the sky ("Mostly sunny"), or null for a sky the app has no word for. By night "sunny"
/// is "clear" (the words `sky_clear_night`, `sky_mostly_clear_night`).
String? skyWordKey(String? sky, {bool isDay = true}) {
  if (sky == null || !_skies.contains(sky)) return null;
  final night = !isDay && (sky == 'clear' || sky == 'mostly_clear');
  return night ? 'sky_${sky}_night' : 'sky_$sky';
}

/// How clean the air is, by the US air quality index (the bands of the index).
enum AqiBand { good, moderate, sensitive, unhealthy, veryUnhealthy, hazardous }

AqiBand aqiBand(int aqi) {
  if (aqi <= 50) return AqiBand.good;
  if (aqi <= 100) return AqiBand.moderate;
  if (aqi <= 150) return AqiBand.sensitive;
  if (aqi <= 200) return AqiBand.unhealthy;
  if (aqi <= 300) return AqiBand.veryUnhealthy;
  return AqiBand.hazardous;
}

/// The interface string key of the word for a band ("Moderate").
String aqiWordKey(AqiBand band) => switch (band) {
  AqiBand.good => 'aqi_good',
  AqiBand.moderate => 'aqi_moderate',
  AqiBand.sensitive => 'aqi_sensitive',
  AqiBand.unhealthy => 'aqi_unhealthy',
  AqiBand.veryUnhealthy => 'aqi_very_unhealthy',
  AqiBand.hazardous => 'aqi_hazardous',
};

/// The colour of a band's dot: green is fine, amber is a warning for some people, red is bad for everyone.
Severity aqiSeverity(AqiBand band) => switch (band) {
  AqiBand.good => Severity.green,
  AqiBand.moderate || AqiBand.sensitive => Severity.yellow,
  AqiBand.unhealthy || AqiBand.veryUnhealthy || AqiBand.hazardous => Severity.red,
};

/// A number the way a weather app writes it: a whole number without the decimal point, else one decimal ("4", "9.7").
String plainNumber(double value) {
  final rounded = (value * 10).round() / 10;
  return rounded == rounded.roundToDouble() ? rounded.toStringAsFixed(0) : rounded.toStringAsFixed(1);
}

typedef Translate = String Function(String key, {Map<String, Object> args});

/// "6:01 am", "12:30 pm": the clock of the phone on twelve hours, the way the weather pictures are labelled.
String clockText(Translate t, DateTime moment, {bool minutes = true}) {
  final local = moment.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final ampm = t(local.hour < 12 ? 'weather_map_am' : 'weather_map_pm');
  return minutes ? '$hour:${local.minute.toString().padLeft(2, '0')} $ampm' : '$hour $ampm';
}

/// The interface string key of the word for the wind (the bands only choose a word; they are not a rule): calm below 3 km/h, a light
/// breeze to 11, a breeze to 19, windy to 28, very windy above.
String windWordKey(double kmh) {
  if (kmh < 3) return 'home_wind_calm';
  if (kmh < 12) return 'home_wind_light';
  if (kmh < 20) return 'home_wind_breeze';
  if (kmh < 29) return 'home_wind_windy';
  return 'home_wind_very_windy';
}

/// The word for the UV index (how strong the sun is) and what to do about it, from the bands of the World Health Organization.
String uvWordKey(double uv) {
  if (uv < 3) return 'home_uv_low';
  if (uv < 6) return 'home_uv_moderate';
  if (uv < 8) return 'home_uv_high';
  if (uv < 11) return 'home_uv_very_high';
  return 'home_uv_extreme';
}

/// The word for how far one can see.
String visibilityWordKey(double km) {
  if (km >= 10) return 'home_vis_clear';
  if (km >= 4) return 'home_vis_hazy';
  return 'home_vis_poor';
}

/// What the big weather card of Home looks like: its colour follows the sky (the brightest blue for a sunny day, a burnt orange when it
/// is hot, slate for cloud, indigo for rain, navy for the night).
enum HeroSky { sunny, hot, cloud, rain, night }

/// Which [HeroSky] suits this sky: by night it is always the night; rain words give rain; cloud, fog and snow give cloud; a clear or
/// partly cloudy day is sunny, or hot from 33 degrees. A sky the app does not know is judged by the temperature alone.
HeroSky heroSkyOf({String? sky, bool? isDay, double? tempC}) {
  if (isDay == false) return HeroSky.night;
  switch (sky) {
    case 'drizzle' || 'rain' || 'heavy_rain' || 'showers' || 'thunderstorm':
      return HeroSky.rain;
    case 'cloudy' || 'fog' || 'snow':
      return HeroSky.cloud;
  }
  return tempC != null && tempC >= 33 ? HeroSky.hot : HeroSky.sunny;
}
