import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/offline/offline_status.dart';
import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/voice/utterance.dart';
import '../../core/voice/voice_widgets.dart';
import '../../core/widgets/big_buttons.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/voice_scaffold.dart';
import '../field/field_providers.dart';
import '../field/field_words.dart';
import '../field/place_providers.dart';
import '../offline/offline_cards.dart';
import '../scan/scan_flow.dart';
import 'app_bottom_nav.dart';
import 'home_weather.dart';

/// The first page: the green header, the big photo card, the weather of the farmer's place (the big weather card, the next hours,
/// the spray check, the rain of the week and the details of the air), the last advice, and the bottom bar. Speaks `home_intro`; on
/// the very first visit it also says what each button does.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.fresh = false});

  /// Arrived straight from login: greet first.
  final bool fresh;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const _tour = ['home_intro', 'home_scan', 'home_field', 'home_diary', 'home_ask', 'home_settings'];

  /// Decided once, so the speaker button keeps replaying the whole tour after it was marked as heard.
  late final bool _firstVisit = !ref.read(settingsProvider).homeTourDone;

  @override
  void initState() {
    super.initState();
    if (_firstVisit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(settingsProvider.notifier).markHomeTourDone();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final online = ref.watch(onlineProvider).value ?? true;
    final unread = ref.watch(unreadAlertsProvider).value ?? 0;
    final resultReady = ref.watch(offlineStatusProvider.select((s) => s.ready.isNotEmpty));
    final farmer = ref.watch(sessionProvider).farmer;
    final firstName = (farmer?.name ?? '').trim().split(' ').first;
    // The farmer's CURRENT location: the place chosen on the place picker, else the village and district of the profile. Touching it
    // opens the picker (when the server can give the weather of a chosen place).
    final placeOn = ref.watch(homePlacePickerProvider);
    final picked = placeOn ? ref.watch(pickedPlaceProvider) : null;
    final profilePlace = [farmer?.village, farmer?.district].whereType<String>().where((s) => s.isNotEmpty).join(', ');
    final place = picked?.shortLabel ?? (profilePlace.isEmpty && placeOn ? t('field_place_change') : profilePlace);
    // The weather below names the place only when there is one ("Choose place" is the header's prompt, not a place).
    final placeKnown = picked != null || profilePlace.isNotEmpty;

    return VoiceScaffold(
      showBack: false,
      brandHeader: true,
      avatar: _initials(farmer?.name ?? ''),
      title: firstName.isEmpty ? t('app_name') : t('home_greeting', args: {'name': firstName}),
      subtitle: place,
      onSubtitleTap: placeOn ? () => context.push(Routes.fieldPlace) : null,
      subtitleLabel: '$place. ${t('field_place_change')}',
      bottomNav: const AppBottomNav(current: AppTab.home),
      script: promptList([
        if (widget.fresh) 'login_ok',
        ..._firstVisit ? _tour : const ['home_intro'],
        if (resultReady) 'offline_result_ready',
      ]),
      replayScript: promptList([..._tour, if (resultReady) 'offline_result_ready']),
      topRight: [
        if (!online) _OfflineSign(label: t('a11y_offline')),
        _HeaderButton(
          key: const ValueKey('home-alerts'),
          icon: AppIcons.bell,
          semanticLabel: t('a11y_alerts'),
          badge: unread,
          onPressed: () => context.push(Routes.alerts),
        ),
        _HeaderButton(
          key: const ValueKey('home-settings'),
          icon: AppIcons.gear,
          semanticLabel: t('a11y_settings'),
          onPressed: () => context.push(Routes.settings),
        ),
      ],
      // The big photo card first (it reaches into the green header), a result that is ready, the weather, the last advice, and what
      // waits to be sent. Every block brings its own 12 dp gap above it, so a block that is not shown takes no room.
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _ScanCard(),
          const OfflineResultCards(part: OfflineResultPart.ready),
          _FieldSummary(placeName: placeKnown ? place : ''),
          const OfflineResultCards(part: OfflineResultPart.last),
          const OfflineWaitingCard(),
        ],
      ),
    );
  }

  /// "SS" for "Shahzad Sharma": the first letter of up to two words.
  static String _initials(String name) =>
      name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
}

/// The mockup's 12 px gap between the blocks of a page, and the 10 px (12 minus the label's -2) under a section label.
const _blockGap = 12.0;
const _labelGap = 10.0;

/// The big photo card (`.card` with radius 24 and padding 18): the green camera circle, the words and the arrow. It opens the
/// camera page, which has its own way to choose photos that are already in the phone.
class _ScanCard extends ConsumerWidget {
  const _ScanCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final title = t('home_scan_card_title');
    // A narrow phone or large text leaves the words too little room next to the 76 px circle and the arrow: the circle
    // gets smaller and the (decorative) arrow goes, so the title keeps to one or two lines and the card stays short.
    final compact = MediaQuery.sizeOf(context).width < 360 || MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    final circle = compact ? 56.0 : 76.0;
    return AppCard(
      padding: EdgeInsets.zero,
      radius: 24,
      // The ripple of the button must show over the white card, so it sits on a transparent Material above it.
      child: Material(
        type: MaterialType.transparency,
        child: Semantics(
          button: true,
          label: t('a11y_camera'),
          excludeSemantics: true,
          child: InkWell(
            key: const ValueKey('home-scan'),
            borderRadius: BorderRadius.circular(24),
            onTap: () {
              Haptics.tap();
              ref.read(scanFlowProvider.notifier).reset();
              context.go(Routes.scan);
            },
            child: Padding(
              padding: EdgeInsets.all(compact ? 14 : 18),
              child: Row(
                children: [
                  IconDot(
                    AppIcons.camera,
                    background: AppColors.green,
                    foreground: Colors.white,
                    size: circle,
                    round: true,
                    iconSize: circle / 2,
                    shadow: true,
                  ),
                  SizedBox(width: compact ? 12 : 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            height: isDevanagari(title) ? 1.3 : 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(t('home_scan_card_hint'), style: const TextStyle(fontSize: 15, color: AppColors.inkSoft)),
                      ],
                    ),
                  ),
                  if (!compact) ...const [
                    SizedBox(width: 16),
                    IconDot(
                      AppIcons.greenArrow,
                      background: AppColors.greenSoft,
                      foreground: AppColors.green,
                      size: 40,
                      round: true,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.ibtn.glass`: a white circle at 14 % on the green header, white picture, drawn [Dimens.compactIbtn] wide so that this
/// button, its neighbour and the voice button share the greeting's line; with [badge] unread the red count of the mockup's
/// `.badge` (22 high, 12 / 800, a 2 px ring in the header's green) on its upper right corner.
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.badge = 0,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onPressed;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final button = BigIconButton(
      icon: icon,
      semanticLabel: semanticLabel,
      color: glassButtonColor,
      foreground: Colors.white,
      size: Dimens.minTouch,
      diameter: Dimens.compactIbtn,
      onPressed: onPressed,
    );
    if (badge <= 0) return button;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        // The circle is 40 inside its 56 tap area (8 dp round it), so -2 / -4 of the circle is 6 / 4 of the area. The number
        // never takes taps from the bell under it, and stays small however large the text is set.
        Positioned(
          right: 6,
          top: 4,
          child: IgnorePointer(
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.2,
              child: Container(
                key: const ValueKey('alert-badge'),
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.red,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: AppColors.brand, width: 2),
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12, height: 1.2),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The "no internet" sign next to the bell: the same glass circle, not a button.
class _OfflineSign extends StatelessWidget {
  const _OfflineSign({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: const SizedBox(
      width: Dimens.minTouch,
      height: Dimens.minTouch,
      child: Center(
        child: IconDot(
          AppIcons.offline,
          background: glassButtonColor,
          foreground: Colors.white,
          size: Dimens.compactIbtn,
          round: true,
        ),
      ),
    ),
  );
}

/// Whether Home asks the server for the field (`GET /v1/field`) to show "Now in your field". Off under `flutter test`,
/// so the extra request cannot take a failure that a test queued for another call; the field tests cover the data.
final homeFieldSummaryProvider = Provider<bool>((ref) => !Platform.environment.containsKey('FLUTTER_TEST'));

/// "Now in your field" (or "Now at this place"): the weather of the place of the header line. With weather on it is the weather
/// of [HomeWeather]; with weather off (or an answer without any temperature) only what a sensor measures, in the white card of
/// [_SensorSummary]. Shown only when the answer is there; while it loads, or without internet and without a kept answer, nothing shows.
class _FieldSummary extends ConsumerWidget {
  const _FieldSummary({required this.placeName});

  /// The place of the header line.
  final String placeName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(homeFieldSummaryProvider)) return const SizedBox.shrink();
    // The place of the header is the place of the weather: the one the farmer chose, else the farmer's own field.
    final placeOn = ref.watch(homePlacePickerProvider);
    final picked = placeOn ? ref.watch(pickedPlaceProvider) : null;
    final view = (picked != null ? ref.watch(placeWeatherProvider(picked)) : ref.watch(fieldProvider)).value;
    if (view == null || view.hasNoData) return const SizedBox.shrink();
    final weatherOn = picked != null || ref.watch(weatherOnProvider);
    if (weatherOn && homeWeatherHasData(view.field)) {
      return HomeWeather(view: view, placeName: placeName, picked: picked != null);
    }
    return _SensorSummary(view: view, weatherOn: weatherOn);
  }
}

/// Up to three readings of the field page in one white card, three equal columns with a hairline between them (a blue picture,
/// the grey name, the word, the measured value: 17 °C, 62 %, 0 mm). The card opens the field page.
class _SensorSummary extends ConsumerWidget {
  const _SensorSummary({required this.view, required this.weatherOn});

  final FieldView view;
  final bool weatherOn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = readingTiles(view.field.readings, weather: weatherOn);
    // The mockup shows warmth, air and leaves (how long the leaves stay wet matters most for scab); another reading
    // takes the place of one that is missing.
    const preferred = ['temp', 'humidity', 'leaf'];
    final tiles = [
      for (final id in preferred) ...all.where((tile) => tile.id == id),
      ...all.where((tile) => !preferred.contains(tile.id)),
    ].take(3).toList();
    if (tiles.isEmpty) return const SizedBox.shrink();
    final t = ref.watch(stringsProvider);
    final heading = t('field_readings_title');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: _blockGap),
        SectionLabel(heading, hindi: isDevanagari(heading)),
        const SizedBox(height: _labelGap),
        Semantics(
          label: t('home_field_label'),
          child: AppCard(
            key: const ValueKey('home-field-card'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
            onTap: () => context.push(Routes.field),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < tiles.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: DecoratedBox(
                        // The hairlines are the borders of the middle column, as in the mockup.
                        decoration: i == 1
                            ? const BoxDecoration(
                                border: Border.symmetric(vertical: BorderSide(color: AppColors.line)),
                              )
                            : const BoxDecoration(),
                        child: _Reading(
                          tile: tiles[i],
                          label: t(tiles[i].labelKey),
                          word: t(tiles[i].wordKey),
                          value: tiles[i].unitKey == null
                              ? tiles[i].digits
                              : '${tiles[i].digits} ${t(tiles[i].unitKey!)}',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One reading of the field card: a 24 px blue picture (all three are blue, as in the mockup), the name in 13 grey, the
/// word in 16 / 700 and the measured value in 13 grey (the percentage of the air, the degrees, the millimetres of rain). A
/// long word shrinks instead of wrapping, so the three columns stay level. The value is for the eyes only: it is never spoken.
class _Reading extends StatelessWidget {
  const _Reading({required this.tile, required this.label, required this.word, required this.value});

  final ReadingTile tile;
  final String label;
  final String word;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(tile.icon, size: 24, color: AppColors.blue),
      // The mockup's inline picture sits on the text baseline, which leaves about 5 px under it.
      const SizedBox(height: 5),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label, style: AppText.hMeta.copyWith(fontSize: 13)),
      ),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(word, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.35)),
      ),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(value, key: ValueKey('home-reading-value-${tile.id}'), style: AppText.hMeta.copyWith(fontSize: 13)),
      ),
    ],
  );
}
