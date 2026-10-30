import 'json_utils.dart';
import 'localized.dart';

class ReadingsOut {
  const ReadingsOut({this.tempC, this.rhPct, this.rain24hMm, this.leafWetnessMin, this.soilMoisturePct});

  factory ReadingsOut.fromJson(Json json) => ReadingsOut(
    tempC: json.doubleOrNull('temp_c'),
    rhPct: json.doubleOrNull('rh_pct'),
    rain24hMm: json.doubleOrNull('rain_24h_mm'),
    leafWetnessMin: json.intOrNull('leaf_wetness_min'),
    soilMoisturePct: json.doubleOrNull('soil_moisture_pct'),
  );

  final double? tempC;
  final double? rhPct;
  final double? rain24hMm;
  final int? leafWetnessMin;
  final double? soilMoisturePct;

  Json toJson() => {
    'temp_c': tempC,
    'rh_pct': rhPct,
    'rain_24h_mm': rain24hMm,
    'leaf_wetness_min': leafWetnessMin,
    'soil_moisture_pct': soilMoisturePct,
  };
}

/// What the sky and the air are like now, the details of a weather app (`conditions` of `GET /v1/field` and `GET /v1/weather`).
/// Every part may be missing: the weather source did not have it, or the server has weather switched off.
class ConditionsOut {
  const ConditionsOut({
    this.sky,
    this.isDay,
    this.feelsLikeC,
    this.windKmh,
    this.visibilityKm,
    this.pressureHpa,
    this.dewPointC,
    this.aqi,
    this.uvIndex,
    this.sunrise,
    this.sunset,
  });

  factory ConditionsOut.fromJson(Json json) {
    final day = json['is_day'];
    return ConditionsOut(
      sky: json.strOrNull('sky'),
      isDay: day is bool ? day : null,
      feelsLikeC: json.doubleOrNull('feels_like_c'),
      windKmh: json.doubleOrNull('wind_kmh'),
      visibilityKm: json.doubleOrNull('visibility_km'),
      pressureHpa: json.doubleOrNull('pressure_hpa'),
      dewPointC: json.doubleOrNull('dew_point_c'),
      aqi: json.intOrNull('aqi'),
      uvIndex: json.doubleOrNull('uv_index'),
      sunrise: json.dateOrNull('sunrise'),
      sunset: json.dateOrNull('sunset'),
    );
  }

  /// One of `clear`, `mostly_clear`, `partly_cloudy`, `cloudy`, `fog`, `drizzle`, `rain`, `heavy_rain`, `showers`, `snow`,
  /// `thunderstorm` (the server turns the weather code into these).
  final String? sky;
  final bool? isDay;
  final double? feelsLikeC;
  final double? windKmh;
  final double? visibilityKm;

  /// Sea-level pressure, in hectopascals (the same number as millibars).
  final double? pressureHpa;
  final double? dewPointC;

  /// US air quality index, 0 to 500.
  final int? aqi;

  /// How strong the sun is now (the UV index: 0 to 11 or more).
  final double? uvIndex;

  /// The sunrise and sunset of today (UTC; shown on the phone's clock).
  final DateTime? sunrise;
  final DateTime? sunset;

  /// Nothing is known of what the "Weather now" card shows (the sun and the UV belong to the details of Home, not to that card).
  bool get isEmpty =>
      sky == null &&
      feelsLikeC == null &&
      windKmh == null &&
      visibilityKm == null &&
      pressureHpa == null &&
      dewPointC == null &&
      aqi == null;

  Json toJson() => {
    'sky': sky,
    'is_day': isDay,
    'feels_like_c': feelsLikeC,
    'wind_kmh': windKmh,
    'visibility_km': visibilityKm,
    'pressure_hpa': pressureHpa,
    'dew_point_c': dewPointC,
    'aqi': aqi,
    'uv_index': uvIndex,
    'sunrise': sunrise?.toUtc().toIso8601String(),
    'sunset': sunset?.toUtc().toIso8601String(),
  };
}

/// One hour of the forecast (`hours` of `GET /v1/field` and `GET /v1/weather`): the first is the hour it is now.
class HourOut {
  const HourOut({required this.time, this.tempC, this.sky, this.isDay, this.rainChancePct, this.rainMm, this.windKmh});

  /// An hour from the server, or null when it has no usable time (such an hour is left out).
  static HourOut? tryParse(Json json) {
    final time = json.dateOrNull('time');
    if (time == null) return null;
    final day = json['is_day'];
    return HourOut(
      time: time,
      tempC: json.doubleOrNull('temp_c'),
      sky: json.strOrNull('sky'),
      isDay: day is bool ? day : null,
      rainChancePct: json.intOrNull('rain_chance_pct'),
      rainMm: json.doubleOrNull('rain_mm'),
      windKmh: json.doubleOrNull('wind_kmh'),
    );
  }

  /// The start of the hour (UTC).
  final DateTime time;
  final double? tempC;

  /// A sky word like [ConditionsOut.sky].
  final String? sky;
  final bool? isDay;

  /// How likely rain is in this hour, 0 to 100.
  final int? rainChancePct;
  final double? rainMm;
  final double? windKmh;

  Json toJson() => {
    'time': time.toUtc().toIso8601String(),
    'temp_c': tempC,
    'sky': sky,
    'is_day': isDay,
    'rain_chance_pct': rainChancePct,
    'rain_mm': rainMm,
    'wind_kmh': windKmh,
  };
}

/// How one part of the weather suits spraying.
enum SprayStatus implements WireEnum {
  ok('ok'),
  care('care'),
  stop('stop');

  const SprayStatus(this.wire);

  @override
  final String wire;

  /// An unknown word is read as "be careful": a server newer than the app must never make a spray look safer than it is.
  static SprayStatus parse(Object? raw) => parseWire(values, raw, SprayStatus.care);
}

/// One of the three checks of [SprayOut] (wind, rain, heat): its [status] and the numbers behind it.
class SprayCheckOut {
  const SprayCheckOut({this.status = SprayStatus.ok, this.value, this.hours});

  factory SprayCheckOut.fromJson(Json json, {required String valueKey, String? hoursKey}) => SprayCheckOut(
    status: SprayStatus.parse(json['status']),
    value: json.doubleOrNull(valueKey),
    hours: hoursKey == null ? null : json.intOrNull(hoursKey),
  );

  final SprayStatus status;

  /// Wind in km/h, the rain of the next three hours in mm, or the temperature in degrees.
  final double? value;

  /// Rain only: whole hours until it rains (null: not within the hours the server looked at).
  final int? hours;
}

/// "Can I spray today?": the weather part of the answer, decided on the server by rules (`spray` of `GET /v1/field` and
/// `GET /v1/weather`; null when the server has it switched off). [state] is the worst of the three checks, [headline] the reason.
class SprayOut {
  const SprayOut({
    required this.state,
    this.headline = 'calm_dry',
    this.wind = const SprayCheckOut(),
    this.rain = const SprayCheckOut(),
    this.heat = const SprayCheckOut(),
  });

  /// The answer of the server, or null when the state is not one the app knows (then nothing is shown rather than a guess).
  static SprayOut? tryParse(Json? json) {
    if (json == null) return null;
    // The server says `go` for a good time and `care` or `stop`; the parts of the answer say `ok` where this says `go`.
    final state = switch (json['state']) {
      'go' => SprayStatus.ok,
      'care' => SprayStatus.care,
      'stop' => SprayStatus.stop,
      _ => null,
    };
    if (state == null) return null;
    return SprayOut(
      state: state,
      headline: json.str('headline', 'calm_dry'),
      wind: SprayCheckOut.fromJson(json.objOrNull('wind') ?? {}, valueKey: 'kmh'),
      rain: SprayCheckOut.fromJson(json.objOrNull('rain') ?? {}, valueKey: 'mm_next_3h', hoursKey: 'dry_hours'),
      heat: SprayCheckOut.fromJson(json.objOrNull('heat') ?? {}, valueKey: 'temp_c'),
    );
  }

  /// `ok` is "good time to spray" (`go` on the wire), `care` "be careful", `stop` "not now".
  final SprayStatus state;

  /// `calm_dry`, `windy`, `hot`, `rain_soon` or `raining`: which part decided the state.
  final String headline;
  final SprayCheckOut wind;
  final SprayCheckOut rain;
  final SprayCheckOut heat;

  Json toJson() => {
    'state': state == SprayStatus.ok ? 'go' : state.wire,
    'headline': headline,
    'wind': {'kmh': wind.value, 'status': wind.status.wire},
    'rain': {'dry_hours': rain.hours, 'mm_next_3h': rain.value, 'status': rain.status.wire},
    'heat': {'temp_c': heat.value, 'status': heat.status.wire},
  };
}

class ForecastDayOut {
  const ForecastDayOut({required this.day, this.tminC = 0, this.tmaxC = 0, this.rainMm = 0});

  factory ForecastDayOut.fromJson(Json json) => ForecastDayOut(
    day: json.str('day'),
    tminC: json.doubleOr('tmin_c'),
    tmaxC: json.doubleOr('tmax_c'),
    rainMm: json.doubleOr('rain_mm'),
  );

  /// ISO date, `2026-05-12`.
  final String day;
  final double tminC;
  final double tmaxC;
  final double rainMm;

  Json toJson() => {'day': day, 'tmin_c': tminC, 'tmax_c': tmaxC, 'rain_mm': rainMm};
}

class RiskOut {
  const RiskOut({
    required this.id,
    this.level = Severity.yellow,
    this.title = const LocalizedText(),
    this.text = const LocalizedText(),
  });

  factory RiskOut.fromJson(Json json) => RiskOut(
    id: json.str('id'),
    level: Severity.parse(json['level']),
    title: LocalizedText.fromJson(json['title']),
    text: LocalizedText.fromJson(json['text']),
  );

  final String id;
  final Severity level;
  final LocalizedText title;
  final LocalizedText text;

  Json toJson() => {'id': id, 'level': level.wire, 'title': title.toJson(), 'text': text.toJson()};
}

class FieldOut {
  const FieldOut({
    this.stationId,
    this.village,
    this.asOf,
    this.stale = false,
    this.readings,
    this.conditions,
    this.hours = const [],
    this.spray,
    this.forecast = const [],
    this.risks = const [],
    this.spoken = const SpokenOut(),
  });

  factory FieldOut.fromJson(Json json) => FieldOut(
    stationId: json.strOrNull('station_id'),
    village: json.strOrNull('village'),
    asOf: json.dateOrNull('as_of'),
    stale: json.boolOr('stale'),
    readings: json.obj('readings', ReadingsOut.fromJson),
    conditions: json.obj('conditions', ConditionsOut.fromJson),
    hours: [for (final h in json.list('hours', HourOut.tryParse)) ?h],
    spray: SprayOut.tryParse(json.objOrNull('spray')),
    forecast: json.list('forecast', ForecastDayOut.fromJson),
    risks: json.list('risks', RiskOut.fromJson),
    spoken: SpokenOut.fromJson(json['spoken']),
  );

  final String? stationId;
  final String? village;
  final DateTime? asOf;
  final bool stale;
  final ReadingsOut? readings;
  final ConditionsOut? conditions;

  /// The next hours (the first is the hour it is now); empty when the server has none.
  final List<HourOut> hours;

  /// "Can I spray today?"; null when the server does not say.
  final SprayOut? spray;
  final List<ForecastDayOut> forecast;
  final List<RiskOut> risks;
  final SpokenOut spoken;

  Json toJson() => {
    'station_id': stationId,
    'village': village,
    'as_of': asOf?.toIso8601String(),
    'stale': stale,
    'readings': readings?.toJson(),
    'conditions': conditions?.toJson(),
    'hours': [for (final h in hours) h.toJson()],
    'spray': spray?.toJson(),
    'forecast': [for (final f in forecast) f.toJson()],
    'risks': [for (final r in risks) r.toJson()],
    'spoken': spoken.toJson(),
  };
}
