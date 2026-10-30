import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/design.dart';
import 'place_map.dart';
import 'place_providers.dart';
import 'weather_map_data.dart';

/// The picture of a layer on its chip, and the words under it.
IconData mapLayerIcon(MapLayer layer) => switch (layer) {
  MapLayer.radar => AppIcons.rain,
  MapLayer.clouds => AppIcons.cloud,
  MapLayer.rain => AppIcons.drop,
};

String mapLayerNameKey(MapLayer layer) => switch (layer) {
  MapLayer.radar => 'weather_map_radar',
  MapLayer.clouds => 'weather_map_clouds',
  MapLayer.rain => 'weather_map_rain',
};

/// What the voice says about a layer (and the caption shows).
String mapLayerSayKey(MapLayer layer) => switch (layer) {
  MapLayer.radar => 'weather_map_say_radar',
  MapLayer.clouds => 'weather_map_say_clouds',
  MapLayer.rain => 'weather_map_say_rain',
};

String mapLayerCreditKey(MapLayer layer) => switch (layer) {
  MapLayer.radar => 'weather_map_credit_radar',
  MapLayer.clouds => 'weather_map_credit_clouds',
  MapLayer.rain => 'weather_map_credit_rain',
};

/// The card on My field that opens the weather map.
class WeatherMapEntry extends ConsumerWidget {
  const WeatherMapEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    return AppCard(
      key: const ValueKey('field-map-open'),
      onTap: () => context.push(Routes.weatherMap),
      semanticLabel: '${t('weather_map_title')}. ${t('weather_map_entry_hint')}',
      child: Row(
        children: [
          const IconDot(AppIcons.cloud, background: AppColors.blueSoft, foreground: AppColors.blue, round: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('weather_map_title'), style: AppText.hName),
                Text(t('weather_map_entry_hint'), style: AppText.hMeta),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(AppIcons.chevron, size: 22, color: AppColors.chevron),
        ],
      ),
    );
  }
}

/// The three layers as big buttons side by side; the chosen one is green.
class MapLayerChips extends ConsumerWidget {
  const MapLayerChips({super.key, required this.selected, required this.onSelect});

  final MapLayer selected;
  final ValueChanged<MapLayer> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    return Row(
      children: [
        for (final layer in MapLayer.values) ...[
          if (layer != MapLayer.values.first) const SizedBox(width: 8),
          Expanded(
            child: _Chip(
              key: ValueKey('wmap-chip-${layer.name}'),
              icon: mapLayerIcon(layer),
              label: t(mapLayerNameKey(layer)),
              selected: layer == selected,
              onTap: () => onSelect(layer),
            ),
          ),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : AppColors.ink;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: SizedBox(
        height: 64,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? AppColors.green : AppColors.card,
            borderRadius: BorderRadius.circular(Dimens.radiusSmall),
            border: selected ? null : Border.all(color: AppColors.line, width: 2),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(Dimens.radiusSmall),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 24, color: foreground),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(label, maxLines: 1, style: AppText.pill.copyWith(fontSize: 14, color: foreground)),
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

/// What the colours of a layer mean: a colour bar with a word at each end.
class MapLegend extends ConsumerWidget {
  const MapLegend({super.key, required this.layer});

  final MapLayer layer;

  /// The colours of each source, light to heavy (the shades of RainViewer's blue scheme, of the Himawari infrared picture and of NASA's rain scale).
  static List<Color> colors(MapLayer layer) => switch (layer) {
    MapLayer.radar => const [Color(0xFF8CD0F7), Color(0xFF1F78D1), Color(0xFF0B3496), Color(0xFFFFD21F)],
    MapLayer.clouds => const [Color(0xFF8E8E8E), Color(0xFFFFFFFF), Color(0xFF58B9E8), Color(0xFF1565C0)],
    MapLayer.rain => const [Color(0xFF3CB44B), Color(0xFFFFE119), Color(0xFFF58231), Color(0xFFD7263D)],
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final (low, high) = switch (layer) {
      MapLayer.clouds => (t('weather_map_legend_clear'), t('weather_map_legend_thick')),
      _ => (t('weather_map_legend_light'), t('weather_map_legend_heavy')),
    };
    final style = AppText.hMeta.copyWith(fontSize: 12, color: AppColors.ink, height: 1.2);
    return Semantics(
      container: true,
      label: '${t(mapLayerNameKey(layer))}: $low, $high',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 170),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.card.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  key: const ValueKey('wmap-legend-bar'),
                  height: 10,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: AppColors.line),
                    gradient: LinearGradient(colors: colors(layer)),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(low, style: style),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(high, style: style),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The map with one weather picture over it. Only the picture shown now is drawn, and, while the map plays, the next one without
/// being seen: its tiles are then already there when it is its turn (otherwise every step would flash an empty map).
class WeatherMapView extends ConsumerWidget {
  const WeatherMapView({
    super.key,
    required this.controller,
    required this.center,
    required this.zoom,
    required this.layer,
    required this.frame,
    this.preload,
    this.marker,
  });

  final MapController controller;
  final LatLng center;
  final double zoom;
  final MapLayer layer;

  /// The picture to show (null while the pictures are being fetched, or when there are none).
  final MapFrame? frame;

  /// The next picture, loaded without being shown.
  final MapFrame? preload;
  final LatLng? marker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final baseTiles = ref.watch(mapTileUrlProvider);
    final spec = mapLayerSpecs[layer]!;
    final credit = '${ref.watch(mapAttributionProvider)} · ${t(mapLayerCreditKey(layer))}';
    return Semantics(
      container: true,
      label: t('weather_map_label'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Dimens.radius),
        child: Stack(
          children: [
            FlutterMap(
              key: const ValueKey('weather-map'),
              mapController: controller,
              options: MapOptions(
                initialCenter: center,
                initialZoom: zoom,
                minZoom: 4,
                maxZoom: 10, // the pictures are about 2 km per dot: closer than this shows nothing more
                backgroundColor: AppColors.neutralSoft,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              ),
              children: [
                if (baseTiles != null)
                  TileLayer(urlTemplate: baseTiles, userAgentPackageName: PlaceMap.userAgentPackageName),
                // Each picture keeps its own layer (by its key) so that the one loaded in advance is the same one that is shown next.
                for (final f in [?preload, ?frame])
                  _PictureLayer(
                    key: ValueKey('wmap-${layer.name}-${f.time.millisecondsSinceEpoch}'),
                    frame: f,
                    spec: spec,
                    visible: identical(f, frame),
                  ),
                if (marker != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        key: const ValueKey('wmap-pin'),
                        point: marker!,
                        width: 56,
                        height: 56,
                        alignment: Alignment.topCenter,
                        child: const Icon(Icons.location_on, size: 44, color: AppColors.red),
                      ),
                    ],
                  ),
              ],
            ),
            Positioned(
              left: 6,
              top: 6,
              child: MapLegend(key: const ValueKey('wmap-legend'), layer: layer),
            ),
            Positioned(
              right: 4,
              bottom: 4,
              left: 4,
              child: Align(
                alignment: Alignment.bottomRight,
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
                        key: const ValueKey('wmap-credit'),
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

/// One weather picture as a tile layer. It makes its own tile provider (a [TileLayer] closes its provider when it goes away).
class _PictureLayer extends ConsumerStatefulWidget {
  const _PictureLayer({super.key, required this.frame, required this.spec, required this.visible});

  final MapFrame frame;
  final MapLayerSpec spec;
  final bool visible;

  @override
  ConsumerState<_PictureLayer> createState() => _PictureLayerState();
}

class _PictureLayerState extends ConsumerState<_PictureLayer> {
  late final TileProvider _provider = ref.read(weatherMapTileProviderProvider)();

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: widget.visible ? widget.spec.opacity : 0,
    child: TileLayer(
      urlTemplate: widget.frame.urlTemplate,
      maxNativeZoom: widget.spec.maxNativeZoom,
      tileProvider: _provider,
      userAgentPackageName: PlaceMap.userAgentPackageName,
      tileDisplay: const TileDisplay.instantaneous(),
    ),
  );
}
