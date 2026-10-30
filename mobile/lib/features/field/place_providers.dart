import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/widgets/demo_clock_banner.dart';
import 'field_providers.dart';

/// A place the farmer chose to see the weather of: a search result, the phone's position, or a point tapped on the map.
class PickedPlace {
  const PickedPlace({required this.label, required this.lat, required this.lon, this.kind = 'place'});

  /// What the screen shows and says: `Theog, Shimla, Himachal Pradesh`, or "My location" / "A point on the map".
  final String label;
  final double lat;
  final double lon;

  /// `state`, `district`, `tehsil`, `town`, `village` or `place` (see [zoomForKind]).
  final String kind;

  /// About 1 km: the server rounds the point the same way, so two nearly equal points are one weather question.
  String get key => '${lat.toStringAsFixed(2)},${lon.toStringAsFixed(2)}';

  /// The first two parts of the label, `Kotgarh, Kumharsain`: what fits on the Home location pill (the whole label is on My field).
  String get shortLabel {
    final parts = label.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    return parts.length <= 2 ? label : parts.take(2).join(', ');
  }

  Map<String, Object> toJson() => {'label': label, 'lat': lat, 'lon': lon, 'kind': kind};

  /// A place read back from the phone's memory; null for anything damaged or out of range (a damaged entry is the same as none).
  static PickedPlace? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final label = json['label'];
      final lat = json['lat'];
      final lon = json['lon'];
      if (label is! String || label.trim().isEmpty || lat is! num || lon is! num) return null;
      if (!lat.isFinite || !lon.isFinite || lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
      final kind = json['kind'];
      return PickedPlace(label: label, lat: lat.toDouble(), lon: lon.toDouble(), kind: kind is String ? kind : 'place');
    } on Object {
      return null;
    }
  }

  @override
  bool operator ==(Object other) => other is PickedPlace && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// The farmer's CURRENT LOCATION for the weather, chosen on the place picker (the location line of Home, or the place bar of
/// My field). Null is the farmer's own registered place ("my field": the village and district of the profile, and the server's
/// `/v1/field`). It is kept on the phone, one entry per farmer id (so another farmer who logs in on the same phone never sees
/// it, and the same farmer finds it again after the app was closed) until the farmer goes "back to my field".
class PickedPlaceNotifier extends Notifier<PickedPlace?> {
  String? _key;

  @override
  PickedPlace? build() {
    final farmerId = ref.watch(sessionProvider.select((s) => s.farmer?.id));
    _key = farmerId == null || farmerId.isEmpty ? null : 'picked_place_$farmerId';
    final key = _key;
    return key == null ? null : PickedPlace.tryParse(ref.watch(sharedPreferencesProvider).getString(key));
  }

  /// Two places within about 1 km are the same weather question (see [PickedPlace.==]), but a new NAME for the same spot must still reach
  /// the screens (the generic "My location" becomes the real name of the area).
  @override
  bool updateShouldNotify(PickedPlace? previous, PickedPlace? next) =>
      previous != next || previous?.label != next?.label || previous?.kind != next?.kind;

  void pick(PickedPlace place) {
    state = place;
    final key = _key;
    if (key != null) unawaited(ref.read(sharedPreferencesProvider).setString(key, jsonEncode(place.toJson())));
  }

  void clear() {
    state = null;
    final key = _key;
    if (key != null) unawaited(ref.read(sharedPreferencesProvider).remove(key));
  }
}

final pickedPlaceProvider = NotifierProvider<PickedPlaceNotifier, PickedPlace?>(PickedPlaceNotifier.new);

/// `GET /v1/weather` for [place]: live, so it is not kept on the phone (no internet = an error the screen can show).
final placeWeatherProvider = FutureProvider.autoDispose.family<FieldView, PickedPlace>((ref, place) async {
  return FieldView(await ref.watch(apiClientProvider).weatherAt(place.lat, place.lon));
});

/// Whether the server can give the weather of a chosen place (`/v1/meta` `place_weather_enabled`). The last answer is kept on the phone,
/// so offline the app does what it did the last time it heard (like [weatherEnabledProvider]).
const _placeWeatherKey = 'place_weather_enabled';

final placeWeatherEnabledProvider = FutureProvider<bool>((ref) async {
  final prefs = ref.watch(sharedPreferencesProvider);
  final meta = await ref.watch(serverMetaProvider.future);
  if (meta == null) return prefs.getBool(_placeWeatherKey) ?? false;
  await prefs.setBool(_placeWeatherKey, meta.placeWeatherEnabled);
  return meta.placeWeatherEnabled;
});

/// [placeWeatherEnabledProvider] without the waiting: the saved answer (or false) until the server has answered. The field screen offers
/// "choose a place" when it is true.
final placeWeatherOnProvider = Provider<bool>((ref) {
  final fetched = ref.watch(placeWeatherEnabledProvider).value;
  return fetched ?? ref.watch(sharedPreferencesProvider).getBool(_placeWeatherKey) ?? false;
});

/// The same for the location line of HOME. Home must not ask the server by itself under `flutter test` (an extra `GET /v1/meta` could
/// take a failure that a test queued for another call: see [demoBannerFetchProvider]), so there it only reads the saved answer. In the
/// real app the demo banner's own fetch of `/v1/meta` keeps that saved answer fresh.
final homePlacePickerProvider = Provider<bool>((ref) {
  if (!ref.watch(demoBannerFetchProvider)) {
    return ref.watch(sharedPreferencesProvider).getBool(_placeWeatherKey) ?? false;
  }
  return ref.watch(placeWeatherOnProvider);
});

/// The server can search places by name: the place picker then shows its search box.
final placesSearchOnProvider = Provider<bool>(
  (ref) => ref.watch(serverMetaProvider).value?.placesSearchEnabled ?? false,
);

// ---------------------------------------------------------------------------- the map

/// Where the map's pictures come from. The default is OpenStreetMap's own server: fine for development and demos, but NOT a
/// production tile server (its policy: best effort, no guarantee, heavy use is blocked). For real use build with
/// `--dart-define=MAP_TILE_URL=https://your-tile-provider/{z}/{x}/{y}.png` and the credit that provider asks for in
/// `MAP_ATTRIBUTION`. An empty `MAP_TILE_URL` draws no tiles at all (tests).
const defaultTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const defaultAttribution = '© OpenStreetMap contributors';

final mapTileUrlProvider = Provider<String?>((ref) {
  const url = String.fromEnvironment('MAP_TILE_URL', defaultValue: defaultTileUrl);
  return url.isEmpty ? null : url;
});

/// The map's credit line. It is always shown on the map (OpenStreetMap's licence and every tile provider require it).
final mapAttributionProvider = Provider<String>((ref) {
  const text = String.fromEnvironment('MAP_ATTRIBUTION', defaultValue: defaultAttribution);
  return text;
});

/// How far the map zooms in on a place of this [kind] (Himachal Pradesh is about 5 degrees wide).
double zoomForKind(String kind) => switch (kind) {
  'state' => 7,
  'district' => 9,
  'tehsil' => 10.5,
  'town' => 12,
  'village' => 13,
  _ => 12,
};

/// The map opens on Himachal Pradesh as a whole when nothing is chosen yet.
const himachalCenter = (lat: 31.9, lon: 77.2);
const himachalZoom = 7.0;
