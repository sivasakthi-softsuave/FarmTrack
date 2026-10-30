import 'json_utils.dart';

/// One result of the place search (`GET /v1/places/search`): what the farmer reads ([label]) and the point the map shows.
class PlaceOut {
  const PlaceOut({required this.name, required this.label, required this.lat, required this.lon, this.kind = 'place'});

  factory PlaceOut.fromJson(Json json) => PlaceOut(
    name: json.str('name'),
    label: json.str('label'),
    kind: json.str('kind', 'place'),
    lat: json.doubleOr('lat'),
    lon: json.doubleOr('lon'),
  );

  final String name;

  /// `Theog, Shimla, Himachal Pradesh` (in the language that was asked for).
  final String label;

  /// `state`, `district`, `tehsil`, `town`, `village` or `place`: how far the map zooms in.
  final String kind;
  final double lat;
  final double lon;

  Json toJson() => {'name': name, 'label': label, 'kind': kind, 'lat': lat, 'lon': lon};
}

class PlaceSearchOut {
  const PlaceSearchOut({this.items = const []});

  factory PlaceSearchOut.fromJson(Json json) => PlaceSearchOut(items: json.list('items', PlaceOut.fromJson));

  final List<PlaceOut> items;

  Json toJson() => {
    'items': [for (final p in items) p.toJson()],
  };
}
