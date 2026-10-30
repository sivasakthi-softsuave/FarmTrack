import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:farmtrack/features/field/weather_map_data.dart';

import 'feature_fakes.dart';

/// The weather map's sources, answering from memory: [count] pictures of every layer, 10 minutes apart, the newest 7 minutes before
/// [fixedNow]. Flags make it fail, answer with nothing, or wait.
class FakeMapFeed implements WeatherMapFeed {
  FakeMapFeed({this.count = 6, DateTime? newest})
    : newest = newest ?? fixedNow.subtract(const Duration(minutes: 7)).toUtc();

  final int count;
  bool fail = false;
  bool empty = false;

  /// While set, the answer waits for it.
  Completer<void>? hold;
  final List<MapLayer> asked = [];

  /// When the newest picture was taken (UTC): 7 minutes before [fixedNow] unless said.
  final DateTime newest;

  /// The picture of [layer] taken [ago] pictures before the newest.
  MapFrame frame(MapLayer layer, int ago) {
    final time = newest.subtract(Duration(minutes: 10 * ago));
    return MapFrame(
      time: time,
      urlTemplate: 'https://maps.test/${layer.name}/${time.millisecondsSinceEpoch ~/ 60000}/{z}/{x}/{y}.png',
    );
  }

  @override
  Future<List<MapFrame>> frames(MapLayer layer, DateTime now) async {
    asked.add(layer);
    await hold?.future;
    if (fail) {
      throw DioException.connectionError(
        requestOptions: RequestOptions(path: '/'),
        reason: 'no internet',
      );
    }
    if (empty) return const [];
    return [for (var ago = count - 1; ago >= 0; ago--) frame(layer, ago)];
  }
}

final _blankPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// A tile provider that downloads nothing: every tile is one blank dot, and the address template it was asked for is written down.
class RecordingTiles extends TileProvider {
  RecordingTiles(this.templates);

  final List<String> templates;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    templates.add(options.urlTemplate!);
    return MemoryImage(_blankPng);
  }
}

/// What a test needs so that the weather map's pictures download nothing. (The map under them is switched off with
/// `mapTileUrlProvider.overrideWithValue(null)`, as in the place tests.)
List<Override> mapOverrides(FakeMapFeed feed, List<String> templates) => [
  weatherMapFeedProvider.overrideWithValue(feed),
  weatherMapTileProviderProvider.overrideWithValue(() => RecordingTiles(templates)),
];
