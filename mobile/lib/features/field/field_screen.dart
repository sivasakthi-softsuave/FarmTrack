import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/voice/utterance.dart';
import '../../core/widgets/big_buttons.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/status_views.dart';
import '../../core/widgets/voice_scaffold.dart';
import '../home/app_bottom_nav.dart';
import 'current_weather.dart';
import 'field_providers.dart';
import 'field_widgets.dart';
import 'field_words.dart';
import 'place_providers.dart';
import 'place_widgets.dart';
import 'weather_map_widgets.dart';

/// Route `/field`: "My field". The week in one card first, then picture tiles with a word for the weather now, and a
/// round arrow to look again (the owner's order, 27 Oct 2026: no village line, no danger cards, the week on top; the
/// dangers are in Alerts and in the spoken summary). It says the server's spoken summary when it opens.
///
/// When the server can give the weather of a chosen place, a card at the top says whose weather this is ("My field" or the
/// place the farmer picked) and opens the place picker; the same tiles and week then show that place's weather.
///
/// Old information (a quiet sensor, or the last answer kept on the phone because there is no internet) is marked on
/// the screen and announced with `field_stale`; an answer with nothing in it says `field_no_data`.
class FieldScreen extends ConsumerStatefulWidget {
  const FieldScreen({super.key});

  @override
  ConsumerState<FieldScreen> createState() => _FieldScreenState();
}

class _FieldScreenState extends ConsumerState<FieldScreen> {
  final Object _owner = Object();
  bool _reloading = false;

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.home);
    }
  }

  /// What to say for [view]: the intro (first time only), the stale / no-data prompts when the server's own spoken
  /// text does not already say them, and the server's summary.
  List<Utterance> _script(FieldView view, {bool intro = true, PickedPlace? place}) {
    final lang = ref.read(languageProvider);
    final catalogue = ref.read(promptCatalogueProvider);
    final spoken = view.field.spoken.toUtterance(lang);
    bool says(String promptId) => spoken != null && spoken.text.contains(catalogue.text(promptId, lang));
    return [
      if (place != null) TextUtterance(place.label, lang: lang), // another place: say which one, not "your field"
      if (intro && place == null) const PromptUtterance('field_intro'),
      // The old answer's own summary is not read out: its weather is not today's.
      if (view.fromCache)
        const PromptUtterance('field_stale')
      else if (view.hasNoData) ...[
        if (!says('field_no_data')) const PromptUtterance('field_no_data'),
        ?spoken,
        const PromptUtterance('field_reload'),
      ] else ...[
        if (view.field.stale && !says('field_stale')) const PromptUtterance('field_stale'),
        ?spoken,
      ],
    ];
  }

  Future<void> _reload() async {
    if (_reloading) return;
    final voice = ref.read(voiceServiceProvider);
    final place = ref.read(placeWeatherOnProvider) ? ref.read(pickedPlaceProvider) : null;
    setState(() => _reloading = true);
    // Looking again also asks the server whether its weather is on now (the app asks only once when it starts).
    ref.invalidate(serverMetaProvider);
    if (place != null) {
      ref.invalidate(placeWeatherProvider(place));
    } else {
      ref.invalidate(fieldProvider);
    }
    try {
      final view = place != null
          ? await ref.read(placeWeatherProvider(place).future)
          : await ref.read(fieldProvider.future);
      if (!mounted) return;
      final script = _script(view, intro: false, place: place);
      // Fresh information is announced as such before it is read out.
      final fresh = !view.isOld && !view.hasNoData;
      await voice.speak([if (fresh) const PromptUtterance('field_updated_ok'), ...script], owner: _owner);
    } on Object catch (e) {
      Haptics.error();
      await voice.speak(promptList([errorPromptFor(e)]), owner: _owner);
    } finally {
      if (mounted) setState(() => _reloading = false);
    }
  }

  Future<void> _say(String sentence) {
    final lang = ref.read(languageProvider);
    return ref.read(voiceServiceProvider).speak([TextUtterance(sentence, lang: lang)], owner: _owner);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final placeOn = ref.watch(placeWeatherOnProvider);
    final picked = placeOn ? ref.watch(pickedPlaceProvider) : null;
    // A picked place is live weather from the server (there is no sensor and no old answer kept for it).
    final AsyncValue<FieldView> field = picked != null
        ? ref.watch(placeWeatherProvider(picked))
        : ref.watch(fieldProvider);
    final weatherOn = picked != null || ref.watch(weatherOnProvider);

    if (picked == null && field.hasError && !field.hasValue) {
      return ErrorRetryScreen(error: field.error!, onRetry: () => ref.invalidate(fieldProvider), onBack: _back);
    }
    // A picked place that failed keeps the screen: the farmer can try again, choose another place or go back to the field.
    final placeFailed = picked != null && field.hasError && !field.hasValue;
    final view = field.value;
    final tiles = view == null ? const <ReadingTile>[] : readingTiles(view.field.readings, weather: weatherOn);

    // The mockup's `.pad`: the blocks are 12 apart; a label and what it heads are 10 apart.
    Widget group(String label, Widget content) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(label, hindi: isDevanagari(label)),
        const SizedBox(height: 10),
        content,
      ],
    );
    // No forecast strip when the server has weather switched off.
    final days = view != null && weatherOn ? view.field.forecast.take(7).toList() : const <ForecastDayOut>[];
    // "Weather now": the sky and the details of a weather app. It is weather, so it is hidden when the server has weather switched off.
    final showWeather = view != null && weatherOn && CurrentWeatherCard.hasData(view.field);
    // Nothing to draw: the server sent nothing, or only what a switched-off weather hides.
    final empty = view != null && tiles.isEmpty && days.isEmpty && !showWeather;
    final loading = view == null && !placeFailed;
    // The weather map comes right after the week (where there is one), before the readings of the field; with nothing to show above it, at the end.
    final mapCard = weatherOn && (view != null || placeFailed);
    final mapAfterWeek = mapCard && view != null && !empty;
    final blocks = <Widget>[
      if (placeOn) PlaceBar(place: picked),
      if (placeFailed)
        PlaceWeatherError(onRetry: _reload)
      else if (loading && placeOn)
        const Center(
          child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
        )
      else if (view != null) ...[
        if (view.isOld && !empty) OldInfoBanner(since: view.fromCache ? view.savedAt : view.field.asOf?.toLocal()),
        if (empty)
          const NoFieldData()
        else ...[
          // The weather now first, then the week, then the readings of the field.
          if (showWeather) group(t('weather_now_title'), CurrentWeatherCard(field: view.field)),
          if (days.isNotEmpty) group(t('field_forecast_title'), ForecastStrip(days: days)),
          if (mapAfterWeek) const WeatherMapEntry(),
          if (tiles.isNotEmpty)
            group(
              t(picked != null ? 'field_place_now' : 'field_readings_title'),
              ReadingTiles(tiles: tiles, onSpeak: _say),
            ),
        ],
      ],
      // The weather map is about the weather everywhere, so it does not wait for this field's own answer, only for the weather to be on.
      if (mapCard && !mapAfterWeek) const WeatherMapEntry(),
    ];

    return VoiceScaffold(
      owner: _owner,
      // A main page of the bottom bar: no back arrow (the phone's back button still goes home).
      title: t('field_title'),
      showBack: false,
      // A place whose weather could not be read says so (the farmer may not be able to read the card).
      script: view != null
          ? _script(view, place: picked)
          : (placeFailed ? [TextUtterance(t('field_place_failed'), lang: ref.watch(languageProvider))] : const []),
      speakEnabled: view != null || placeFailed,
      // Choosing another place says its weather again while the screen stays open.
      restartKey: picked?.key,
      onBack: _back,
      alignTop: true,
      bodyPadding: const EdgeInsets.fromLTRB(Dimens.gutter, Dimens.gutter, Dimens.gutter, 0),
      bottomNav: const AppBottomNav(current: AppTab.field),
      topRight: [
        BigIconButton(
          key: const ValueKey('field-reload'),
          icon: AppIcons.roundArrow,
          size: Dimens.minTouch,
          color: AppColors.neutralSoft,
          foreground: AppColors.ink,
          semanticLabel: t('field_reload_label'),
          onPressed: _reloading || loading ? null : _reload,
        ),
      ],
      body: loading && !placeOn
          ? const Center(child: CircularProgressIndicator())
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_reloading) const Padding(padding: EdgeInsets.only(bottom: 8), child: LinearProgressIndicator()),
                for (var i = 0; i < blocks.length; i++) ...[if (i > 0) const SizedBox(height: 12), blocks[i]],
              ],
            ),
    );
  }
}
