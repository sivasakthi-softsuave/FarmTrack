import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import 'place_providers.dart';

/// A free map (OpenStreetMap pictures through `flutter_map`) on which the farmer touches a place. One red pin shows the
/// chosen point. The map's credit line is always drawn (the licence of the map data requires it). Rotating is switched off:
/// two-finger twists are easy to do by accident and a turned map confuses.
///
/// The pictures come from [mapTileUrlProvider]; read its note before a production build.
class PlaceMap extends ConsumerWidget {
  const PlaceMap({
    super.key,
    required this.controller,
    required this.initialCenter,
    required this.initialZoom,
    required this.onTap,
    this.marker,
  });

  final MapController controller;
  final LatLng initialCenter;
  final double initialZoom;
  final LatLng? marker;
  final void Function(LatLng point) onTap;

  /// The application id, sent to the tile server so it can tell this app from others (OpenStreetMap's tile policy).
  static const userAgentPackageName = 'com.softsuave.farmtrack';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final tiles = ref.watch(mapTileUrlProvider);
    final credit = ref.watch(mapAttributionProvider);
    return Semantics(
      container: true,
      label: t('place_map_label'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Dimens.radius),
        child: FlutterMap(
          key: const ValueKey('place-map'),
          mapController: controller,
          options: MapOptions(
            initialCenter: initialCenter,
            initialZoom: initialZoom,
            minZoom: 4,
            maxZoom: 18,
            backgroundColor: AppColors.neutralSoft,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            onTap: (_, point) => onTap(point),
          ),
          children: [
            if (tiles != null) TileLayer(urlTemplate: tiles, userAgentPackageName: userAgentPackageName),
            if (marker != null)
              MarkerLayer(
                markers: [
                  Marker(
                    key: const ValueKey('place-pin'),
                    point: marker!,
                    width: 56,
                    height: 56,
                    alignment: Alignment.topCenter, // the tip of the pin is on the point
                    child: const Icon(Icons.location_on, size: 52, color: AppColors.red),
                  ),
                ],
              ),
            // The credit line the map data's licence requires. Drawn here (not with flutter_map's own attribution widget) so that it
            // can shrink to fit a narrow map or big text instead of overflowing. (A link to openstreetmap.org/copyright needs a
            // url_launcher; add it when the app has one.)
            Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.card.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        credit,
                        key: const ValueKey('place-credit'),
                        style: const TextStyle(fontSize: 12, color: AppColors.ink),
                      ),
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
