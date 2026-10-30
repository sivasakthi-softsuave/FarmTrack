import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/voice/utterance.dart';
import '../../core/widgets/big_buttons.dart';
import '../../core/widgets/voice_scaffold.dart';
import '../diary/date_words.dart';
import 'place_providers.dart';
import 'weather_map_data.dart';
import 'weather_map_widgets.dart';
import 'weather_words.dart';

/// Route `/field/map`: the weather map of Zoom Earth's kind, from free sources. Three buttons choose what is laid over the map (rain
/// radar, clouds, rain amount), a play button runs the last hours as a film, and the line under the button says how old the picture
/// on the map is. It opens on the place chosen on My field (with a red pin), else on Himachal Pradesh as a whole.
///
/// It says what the chosen layer shows when it opens and when another one is chosen. If a layer cannot be fetched it says so and a
/// button tries again (the map under it stays).
class WeatherMapScreen extends ConsumerStatefulWidget {
  const WeatherMapScreen({super.key});

  @override
  ConsumerState<WeatherMapScreen> createState() => _WeatherMapScreenState();
}

class _WeatherMapScreenState extends ConsumerState<WeatherMapScreen> {
  /// How long a picture stays while the map plays.
  static const _step = Duration(milliseconds: 900);

  final Object _owner = Object();
  final MapController _map = MapController();
  MapLayer _layer = MapLayer.radar;

  /// The picture shown; null is the newest.
  int? _index;
  Timer? _timer;

  bool get _playing => _timer != null;

  @override
  void dispose() {
    _timer?.cancel();
    _map.dispose();
    super.dispose();
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.field);
    }
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _choose(MapLayer layer) {
    if (layer == _layer) return;
    _stop();
    setState(() {
      _layer = layer;
      _index = null;
    });
  }

  void _togglePlay(int count) {
    if (_playing) {
      setState(_stop);
      return;
    }
    if (count < 2) return;
    setState(() {
      // From the newest picture it starts again from the oldest.
      if (_index == null || _index! >= count - 1) _index = 0;
      _timer = Timer.periodic(_step, (_) => _tick());
    });
  }

  void _tick() {
    final frames = ref.read(mapFramesProvider(_layer)).value;
    if (!mounted || frames == null || frames.length < 2) {
      setState(_stop);
      return;
    }
    setState(() => _index = ((_index ?? frames.length - 1) + 1) % frames.length);
  }

  void _retry() => ref.invalidate(mapFramesProvider(_layer));

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final lang = ref.watch(languageProvider);
    final now = ref.watch(clockProvider)();
    final picked = ref.watch(placeWeatherOnProvider) ? ref.watch(pickedPlaceProvider) : null;
    final async = ref.watch(mapFramesProvider(_layer));
    final frames = async.value ?? const <MapFrame>[];
    final failed = !async.isLoading && async.hasError;
    final none = !async.isLoading && !failed && frames.isEmpty;
    final index = frames.isEmpty ? 0 : (_index ?? frames.length - 1).clamp(0, frames.length - 1);
    final frame = frames.isEmpty ? null : frames[index];
    final preload = _playing && frames.length > 1 ? frames[(index + 1) % frames.length] : null;

    final center = picked == null ? LatLng(himachalCenter.lat, himachalCenter.lon) : LatLng(picked.lat, picked.lon);

    return VoiceScaffold(
      owner: _owner,
      title: t('weather_map_title'),
      onBack: _back,
      script: [TextUtterance(t(failed ? 'weather_map_failed' : mapLayerSayKey(_layer)), lang: lang)],
      restartKey: '${_layer.name}-$failed',
      scrollable: false,
      alignTop: true,
      bodyPadding: const EdgeInsets.fromLTRB(Dimens.gutter, Dimens.gutter, Dimens.gutter, 8),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MapLayerChips(selected: _layer, onSelect: _choose),
          const SizedBox(height: 8),
          if (async.isLoading)
            const SizedBox(
              height: 64,
              child: Center(child: LinearProgressIndicator(key: ValueKey('wmap-busy'))),
            )
          else if (failed || none)
            _Problem(failed: failed, onRetry: _retry)
          else
            _Controls(
              playing: _playing,
              count: frames.length,
              index: index,
              label: frame == null ? '' : mapFrameLabel(t, frame.time, now),
              onPlay: () => _togglePlay(frames.length),
              onScrub: (i) {
                _stop();
                setState(() => _index = i);
              },
            ),
          const SizedBox(height: 8),
          Expanded(
            child: WeatherMapView(
              controller: _map,
              center: center,
              zoom: picked == null ? himachalZoom : 8,
              layer: _layer,
              frame: frame,
              preload: preload,
              marker: picked == null ? null : center,
            ),
          ),
        ],
      ),
    );
  }
}

/// "3:40 pm · 1 h ago": when the picture was taken, by the phone's clock, and how long ago that is.
String mapFrameLabel(Translate t, DateTime taken, DateTime now) =>
    '${clockText(t, taken)} · ${mapAgo(t, now.difference(taken))}';

/// "Now", "20 min ago", "2 h ago", "6 h 30 min ago".
String mapAgo(Translate t, Duration age) {
  final minutes = age.inMinutes < 0 ? 0 : age.inMinutes;
  if (minutes < 5) return t('weather_map_now');
  if (minutes < 60) return t('weather_map_ago_min', args: {'n': minutes});
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  // The last few minutes of an hour are not worth saying.
  if (rest < 5 || rest > 55) return t('weather_map_ago_h', args: {'h': rest > 55 ? hours + 1 : hours});
  return t('weather_map_ago_hm', args: {'h': hours, 'm': rest});
}

/// The play button, the age of the picture and the slider that goes through the pictures.
class _Controls extends ConsumerWidget {
  const _Controls({
    required this.playing,
    required this.count,
    required this.index,
    required this.label,
    required this.onPlay,
    required this.onScrub,
  });

  final bool playing;
  final int count;
  final int index;
  final String label;
  final VoidCallback onPlay;
  final ValueChanged<int> onScrub;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    return Row(
      children: [
        BigIconButton(
          key: const ValueKey('wmap-play'),
          icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: Dimens.minTouch,
          semanticLabel: t(playing ? 'weather_map_pause' : 'weather_map_play'),
          onPressed: count > 1 ? onPlay : null,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(label, key: const ValueKey('wmap-time'), maxLines: 1, style: AppText.hName),
              ),
              SizedBox(
                height: 48, // the least a touch target may be (the Material slider is drawn as thin as the track)
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6,
                    activeTrackColor: AppColors.green,
                    inactiveTrackColor: AppColors.track,
                    thumbColor: AppColors.green,
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                  ),
                  child: Slider(
                    key: const ValueKey('wmap-slider'),
                    value: index.toDouble(),
                    min: 0,
                    max: count > 1 ? (count - 1).toDouble() : 1,
                    divisions: count > 1 ? count - 1 : null,
                    semanticFormatterCallback: (_) => label,
                    onChanged: count > 1 ? (v) => onScrub(v.round()) : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The pictures of the layer could not be fetched (no internet, or the source is down), or the source has none.
class _Problem extends ConsumerWidget {
  const _Problem({required this.failed, required this.onRetry});

  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    return Row(
      children: [
        Expanded(
          child: Text(
            t(failed ? 'weather_map_failed' : 'weather_map_empty'),
            key: const ValueKey('wmap-message'),
            style: AppText.hMeta.copyWith(color: failed ? AppColors.red : AppColors.ink, fontWeight: FontWeight.w700),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        BigIconButton(
          key: const ValueKey('wmap-retry'),
          icon: AppIcons.roundArrow,
          size: Dimens.minTouch,
          color: AppColors.neutralSoft,
          foreground: AppColors.ink,
          semanticLabel: t('weather_map_retry'),
          onPressed: onRetry,
        ),
      ],
    );
  }
}
