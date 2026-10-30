import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diary/date_words.dart';

/// The pictures the weather map can lay over the map, each from a free source that needs no key:
///  * [radar]: where it rained in the last two hours (RainViewer's radar, every 10 minutes);
///  * [clouds]: the clouds seen from the Himawari weather satellite (NASA GIBS, every 10 minutes, about an hour old);
///  * [rain]: how hard it rained, measured from space (NASA GPM IMERG, every 30 minutes, about six hours old).
enum MapLayer { radar, clouds, rain }

/// One picture of a layer: the map tiles of one moment. [urlTemplate] has the `{z}`, `{x}` and `{y}` of a tile server.
class MapFrame {
  const MapFrame({required this.time, required this.urlTemplate});

  /// When the picture was taken (UTC).
  final DateTime time;
  final String urlTemplate;
}

/// How a layer is drawn on the map.
class MapLayerSpec {
  const MapLayerSpec({required this.maxNativeZoom, required this.opacity});

  /// The deepest zoom the source has pictures for (the map scales them up beyond it).
  final int maxNativeZoom;

  /// How much of the map under the picture shows through (0 = all, 1 = none).
  final double opacity;
}

/// RainViewer's free radar stops at zoom 7; NASA's tiles at zoom 6. The cloud picture is a full grey picture (not transparent), so it
/// is drawn thinner than the two that only paint the wet places.
const mapLayerSpecs = {
  MapLayer.radar: MapLayerSpec(maxNativeZoom: 7, opacity: 0.85),
  MapLayer.clouds: MapLayerSpec(maxNativeZoom: 6, opacity: 0.7),
  MapLayer.rain: MapLayerSpec(maxNativeZoom: 6, opacity: 0.85),
};

/// Where the pictures of each layer come from.
abstract class WeatherMapFeed {
  /// The pictures of [layer], the oldest first and the newest last; empty when the source has none. [now] is the phone's clock.
  /// Throws a [DioException] when the source cannot be reached (the screen then offers "try again").
  Future<List<MapFrame>> frames(MapLayer layer, DateTime now);
}

/// The real sources. It uses its own Dio (never the one of the server API: the farmer's login must not go to other servers).
class HttpWeatherMapFeed implements WeatherMapFeed {
  HttpWeatherMapFeed(this._dio);

  final Dio _dio;

  static const rainViewerIndex = 'https://api.rainviewer.com/public/weather-maps.json';
  static const gibsBase = 'https://gibs.earthdata.nasa.gov/wmts/epsg3857/best';
  static const cloudsGibsLayer = 'Himawari_AHI_Band13_Clean_Infrared';
  static const rainGibsLayer = 'IMERG_Precipitation_Rate_30min';

  /// A small tile over India: asked (HEAD, no picture is sent) to learn whether NASA already has a moment.
  static const _probeTile = '3/3/5';

  @override
  Future<List<MapFrame>> frames(MapLayer layer, DateTime now) => switch (layer) {
    MapLayer.radar => _radar(),
    // The newest Himawari picture is about 40 minutes old, the newest IMERG one about six hours. Ask for the moments around that.
    MapLayer.clouds => _gibs(
      cloudsGibsLayer,
      now,
      step: const Duration(minutes: 10),
      earliestAge: const Duration(minutes: 20),
      tries: 10,
      count: 12,
    ),
    MapLayer.rain => _gibs(
      rainGibsLayer,
      now,
      step: const Duration(minutes: 30),
      earliestAge: const Duration(hours: 2),
      tries: 14,
      count: 6,
    ),
  };

  Future<List<MapFrame>> _radar() async {
    final response = await _dio.get<Object?>(rainViewerIndex);
    return response.statusCode == 200 ? parseRainViewerFrames(response.data) : const [];
  }

  Future<List<MapFrame>> _gibs(
    String layer,
    DateTime now, {
    required Duration step,
    required Duration earliestAge,
    required int tries,
    required int count,
  }) async {
    final newest = roundDown(now.toUtc().subtract(earliestAge), step);
    final candidates = [for (var i = 0; i < tries; i++) newest.subtract(step * i)];
    // All the questions at once: the newest moment NASA answers for is the one to start from.
    var failures = 0;
    Object? firstFailure;
    final answers = await Future.wait([
      for (final moment in candidates)
        _gibsHas(layer, moment).then<bool>(
          (has) => has,
          onError: (Object e) {
            failures++;
            firstFailure ??= e;
            return false;
          },
        ),
    ]);
    if (failures == candidates.length) throw firstFailure!; // not one answer: no connection, not "no picture"
    final at = answers.indexOf(true);
    if (at < 0) return const [];
    final latest = candidates[at];
    return [
      for (var i = count - 1; i >= 0; i--)
        MapFrame(time: latest.subtract(step * i), urlTemplate: gibsTemplate(layer, latest.subtract(step * i))),
    ];
  }

  Future<bool> _gibsHas(String layer, DateTime moment) async {
    final response = await _dio.head<Object?>(
      '$gibsBase/$layer/default/${gibsTime(moment)}/GoogleMapsCompatible_Level6/$_probeTile.png',
    );
    return response.statusCode == 200;
  }

  /// A moment is rounded down to a multiple of [step] (NASA names its pictures by such moments).
  static DateTime roundDown(DateTime time, Duration step) {
    final ms = time.millisecondsSinceEpoch;
    return DateTime.fromMillisecondsSinceEpoch(ms - ms % step.inMilliseconds, isUtc: true);
  }

  /// `2026-10-29T14:00:00Z`, how NASA writes a moment in a tile address.
  static String gibsTime(DateTime moment) => '${moment.toUtc().toIso8601String().substring(0, 19)}Z';

  /// The tile address of one NASA picture (the rows come before the columns: `{y}/{x}`).
  static String gibsTemplate(String layer, DateTime moment) =>
      '$gibsBase/$layer/default/${gibsTime(moment)}/GoogleMapsCompatible_Level6/{z}/{y}/{x}.png';
}

/// The pictures in RainViewer's `weather-maps.json`: the past radar frames, the oldest first. Anything that does not look right is
/// left out (a frame, or all of them when the host is not RainViewer's own). Colour scheme 2 is their blue one, with snow and smoothing.
List<MapFrame> parseRainViewerFrames(Object? json) {
  if (json is! Map) return const [];
  final host = json['host'];
  final radar = json['radar'];
  if (host is! String || radar is! Map) return const [];
  final hostUri = Uri.tryParse(host);
  if (hostUri == null || hostUri.scheme != 'https' || !hostUri.host.endsWith('rainviewer.com')) return const [];
  final past = radar['past'];
  if (past is! List) return const [];
  final frames = <MapFrame>[];
  for (final item in past) {
    if (item is! Map) continue;
    final time = item['time'];
    final path = item['path'];
    if (time is! num || path is! String || !path.startsWith('/')) continue;
    frames.add(
      MapFrame(
        time: DateTime.fromMillisecondsSinceEpoch(time.toInt() * 1000, isUtc: true),
        urlTemplate: '$host$path/256/{z}/{x}/{y}/2/1_1.png',
      ),
    );
  }
  frames.sort((a, b) => a.time.compareTo(b.time));
  return frames;
}

/// The Dio of the free map sources: short waits (a slow source must not hang the screen), every answer is read (404 is "not there").
final weatherMapDioProvider = Provider<Dio>(
  (ref) => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      sendTimeout: const Duration(seconds: 8),
      validateStatus: (_) => true,
      headers: {'User-Agent': 'com.softsuave.farmtrack'},
    ),
  ),
);

final weatherMapFeedProvider = Provider<WeatherMapFeed>((ref) => HttpWeatherMapFeed(ref.watch(weatherMapDioProvider)));

/// The pictures of one layer. Not kept: the screen asks again every time it opens (the pictures are minutes old).
final mapFramesProvider = FutureProvider.autoDispose.family<List<MapFrame>, MapLayer>(
  (ref, layer) => ref.watch(weatherMapFeedProvider).frames(layer, ref.read(clockProvider)()),
);

/// Makes the tile provider of one picture layer (how its tiles are downloaded). One each: a [TileLayer] closes its provider when it
/// goes away, and the map swaps its layers every few seconds while it plays. Tests replace it, so that nothing is downloaded.
final weatherMapTileProviderProvider = Provider<TileProvider Function()>((ref) => NetworkTileProvider.new);
