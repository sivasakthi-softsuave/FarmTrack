import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/errors/api_exception.dart';
import '../../core/location/device_location.dart';
import '../../core/models/models.dart';
import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/voice/utterance.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/voice_scaffold.dart';
import '../auth/auth_widgets.dart';
import 'place_map.dart';
import 'place_providers.dart';

/// Route `/field/place`: "Choose a place" for the weather on My field. Three ways, the easiest first:
///  1. "My location": one touch, the phone's position is used at once (the phone asks for permission the first time).
///  2. Search a name (a state, district, tehsil, town or village): the results are a list; touching one is the choice.
///  3. Touch the free map: a red pin marks the point, then "Show weather here" confirms it (a touch is easy to do by
///     accident while moving the map, so this one asks).
/// The search starts when the farmer SUBMITS (the keyboard's search key or the glass button), never on every key press: the
/// public OpenStreetMap search forbids that and it would send a request per letter.
class PlacePickerScreen extends ConsumerStatefulWidget {
  const PlacePickerScreen({super.key});

  @override
  ConsumerState<PlacePickerScreen> createState() => _PlacePickerScreenState();
}

class _PlacePickerScreenState extends ConsumerState<PlacePickerScreen> {
  final Object _owner = Object();
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode();
  final MapController _map = MapController();

  /// Null: the map is shown. A list (also an empty one): the search results are shown instead of the map.
  List<PlaceOut>? _results;
  bool _searching = false;
  bool _locating = false;

  /// The name of a chosen point is being looked up.
  bool _naming = false;

  /// The interface string key of the message under the buttons (a search or location problem), if any.
  String? _messageKey;

  /// A point touched on the map, waiting for "Show weather here".
  LatLng? _draft;

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
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

  Future<void> _say(String sentence) {
    final lang = ref.read(languageProvider);
    return ref.read(voiceServiceProvider).speak([TextUtterance(sentence, lang: lang)], owner: _owner);
  }

  /// The choice is made: it becomes the farmer's current location (kept on the phone), and My field shows the weather of it. The
  /// picker is opened from Home (the location line) and from My field (the place bar): either way the next thing to see is the weather.
  void _finish(PickedPlace place) {
    ref.read(pickedPlaceProvider.notifier).pick(place);
    context.go(Routes.field);
  }

  /// The real name of a point: the nearest village, its tehsil, district and state. If the server cannot say (no internet, the
  /// search switched off, nothing known there, too slow) the generic words are used, so a choice always works.
  Future<({String label, String kind})> _nameOf(double lat, double lon, String fallback) async {
    if (!ref.read(placesSearchOnProvider)) return (label: fallback, kind: 'place');
    try {
      final place = await ref
          .read(apiClientProvider)
          .reversePlace(lat, lon, lang: ref.read(languageProvider))
          .timeout(const Duration(seconds: 8));
      final label = place.label.trim();
      return label.isEmpty ? (label: fallback, kind: 'place') : (label: label, kind: place.kind);
    } on Object {
      return (label: fallback, kind: 'place');
    }
  }

  Future<void> _search() async {
    final text = _query.text.trim();
    if (_searching || text.length < 2) return;
    final t = ref.read(stringsProvider);
    _focus.unfocus();
    setState(() {
      _searching = true;
      _messageKey = null;
    });
    try {
      final found = await ref.read(apiClientProvider).searchPlaces(text, lang: ref.read(languageProvider), limit: 5);
      if (!mounted) return;
      setState(() => _results = found.items);
      if (found.items.isEmpty) await _say(t('place_no_results'));
    } on ApiException {
      if (!mounted) return;
      setState(() {
        _results = null;
        _messageKey = 'place_search_failed';
      });
      await _say(t('place_search_failed'));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _useMyLocation() async {
    if (_locating) return;
    final t = ref.read(stringsProvider);
    setState(() {
      _locating = true;
      _messageKey = null;
    });
    try {
      final fix = await ref.read(deviceLocationProvider).current();
      if (!mounted) return;
      setState(() => _naming = true);
      final named = await _nameOf(fix.lat, fix.lon, t('place_my_location'));
      if (!mounted) return;
      _finish(PickedPlace(label: named.label, lat: fix.lat, lon: fix.lon, kind: named.kind));
    } on DeviceLocationException catch (e) {
      if (!mounted) return;
      final key = switch (e.reason) {
        LocationFailure.denied || LocationFailure.deniedForever => 'place_location_denied',
        LocationFailure.serviceOff => 'place_location_off',
        _ => 'place_location_failed',
      };
      setState(() => _messageKey = key);
      await _say(t(key));
    } finally {
      if (mounted) {
        setState(() {
          _locating = false;
          _naming = false;
        });
      }
    }
  }

  Future<void> _confirmDraft() async {
    final point = _draft;
    if (point == null || _naming) return;
    setState(() => _naming = true);
    final named = await _nameOf(point.latitude, point.longitude, ref.read(stringsProvider)('place_pin_label'));
    if (!mounted) return;
    setState(() => _naming = false);
    _finish(PickedPlace(label: named.label, lat: point.latitude, lon: point.longitude, kind: named.kind));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final lang = ref.watch(languageProvider);
    final searchOn = ref.watch(placesSearchOnProvider);
    final picked = ref.watch(pickedPlaceProvider);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final results = _results;

    final start = picked == null ? himachalCenter : (lat: picked.lat, lon: picked.lon);
    final Widget area;
    if (results != null) {
      area = _Results(
        places: results,
        onChoose: (p) => _finish(PickedPlace(label: p.label, lat: p.lat, lon: p.lon, kind: p.kind)),
        onShowMap: () => setState(() => _results = null),
      );
    } else if (keyboardOpen) {
      area = const SizedBox.shrink(); // the keyboard takes the room of the map while the farmer types
    } else {
      area = PlaceMap(
        controller: _map,
        initialCenter: LatLng(start.lat, start.lon),
        initialZoom: picked == null ? himachalZoom : zoomForKind(picked.kind),
        marker: _draft,
        onTap: (point) => setState(() {
          _draft = point;
          _messageKey = null;
        }),
      );
    }

    return VoiceScaffold(
      owner: _owner,
      title: t('place_title'),
      onBack: _back,
      script: [TextUtterance(t('place_tap_map'), lang: lang)],
      scrollable: false,
      alignTop: true,
      wideAction: true,
      bodyPadding: const EdgeInsets.fromLTRB(Dimens.gutter, Dimens.gutter, Dimens.gutter, 8),
      bottomRight: results == null
          ? AppButton(
              key: const ValueKey('place-confirm'),
              icon: Icons.place_outlined,
              label: t('place_show_weather'),
              semanticLabel: t('place_show_weather'),
              onPressed: _draft == null || _naming ? null : _confirmDraft,
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (searchOn) ...[
            FieldGlow(
              focusNode: _focus,
              child: TextField(
                key: const ValueKey('place-search'),
                controller: _query,
                focusNode: _focus,
                textInputAction: TextInputAction.search,
                autocorrect: false,
                maxLength: 80,
                style: authInputStyle,
                decoration: authInputDecoration(
                  hint: t('place_search_hint'),
                  suffixIcon: IconButton(
                    key: const ValueKey('place-search-go'),
                    icon: const Icon(Icons.search, size: 28, color: AppColors.green),
                    tooltip: t('place_search_label'),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: Dimens.minTouch, minHeight: Dimens.minTouch),
                    onPressed: _search,
                  ),
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(height: 10),
          ],
          AppButton(
            key: const ValueKey('place-gps'),
            style: AppButtonStyle.outline,
            icon: Icons.my_location,
            label: t('place_use_my_location'),
            semanticLabel: t('place_use_my_location'),
            onPressed: _locating || _naming ? null : _useMyLocation,
          ),
          if (_searching || _locating || _naming) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(key: ValueKey('place-busy')),
          ],
          if (_messageKey != null) ...[
            const SizedBox(height: 8),
            Text(
              t(_messageKey!),
              key: const ValueKey('place-message'),
              style: AppText.hName.copyWith(color: AppColors.red),
            ),
          ],
          const SizedBox(height: 10),
          Expanded(child: area),
        ],
      ),
    );
  }
}

/// The search results: one card each (touching it is the choice), and a button back to the map.
class _Results extends ConsumerWidget {
  const _Results({required this.places, required this.onChoose, required this.onShowMap});

  final List<PlaceOut> places;
  final void Function(PlaceOut place) onChoose;
  final VoidCallback onShowMap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // At the top, not the bottom: the spoken sentence floats over the lower part of the screen for a few seconds.
        AppButton(
          key: const ValueKey('place-results-close'),
          style: AppButtonStyle.outline,
          icon: Icons.map_outlined,
          label: t('place_results_close'),
          semanticLabel: t('place_results_close'),
          onPressed: onShowMap,
        ),
        const SizedBox(height: 10),
        Expanded(
          child: places.isEmpty
              ? Align(
                  alignment: Alignment.topCenter,
                  child: AppCard(
                    key: const ValueKey('place-no-results'),
                    color: AppColors.neutralSoft,
                    flat: true,
                    child: Text(t('place_no_results'), style: AppText.hName),
                  ),
                )
              : ListView.separated(
                  key: const ValueKey('place-results'),
                  padding: EdgeInsets.zero, // a ListView adds the status bar's height at the top otherwise
                  itemCount: places.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final p = places[i];
                    return AppCard(
                      key: ValueKey('place-result-$i'),
                      onTap: () => onChoose(p),
                      semanticLabel: p.label,
                      child: Row(
                        children: [
                          const IconDot(
                            Icons.place_outlined,
                            background: AppColors.blueSoft,
                            foreground: AppColors.blue,
                            round: true,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(p.label, style: AppText.hName, maxLines: 3, overflow: TextOverflow.ellipsis),
                          ),
                          const Icon(AppIcons.chevron, size: 22, color: AppColors.chevron),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
