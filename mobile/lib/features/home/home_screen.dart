import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/offline/offline_status.dart';
import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/voice/speak_on_enter.dart';
import '../../core/voice/utterance.dart';
import '../../core/voice/voice_service.dart';
import '../../core/voice/voice_widgets.dart';
import '../../core/widgets/big_buttons.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/voice_scaffold.dart';
import '../field/field_providers.dart';
import '../field/field_words.dart';
import '../offline/offline_cards.dart';
import '../scan/photo_picker.dart';
import '../scan/scan_flow.dart';
import 'app_bottom_nav.dart';

/// The first page: the green header, the big photo card, the last advice and the field, and the bottom bar. Speaks
/// `home_intro`; on the very first visit it also says what each button does.
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
    final place = [farmer?.village, farmer?.district].whereType<String>().where((s) => s.isNotEmpty).join(', ');

    return VoiceScaffold(
      showBack: false,
      brandHeader: true,
      avatar: _initials(farmer?.name ?? ''),
      title: firstName.isEmpty ? t('app_name') : t('home_greeting', args: {'name': firstName}),
      subtitle: place,
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
      // The big photo card first (it reaches into the green header), then what happened lately, the field, and what
      // waits to be sent. Every block brings its own 12 dp gap above it, so a block that is not shown takes no room.
      body: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_ScanCard(), OfflineResultCards(), _FieldSummary(), OfflineWaitingCard()],
      ),
    );
  }

  /// "DS" for "Dinesh Sharma": the first letter of up to two words.
  static String _initials(String name) =>
      name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
}

/// The mockup's 12 px gap between the blocks of a page, and the 10 px (12 minus the label's -2) under a section label.
const _blockGap = 12.0;
const _labelGap = 10.0;

/// The big photo card (`.card` with radius 24 and padding 18): the green camera circle, the words, the arrow, and under
/// a hairline the way to take a photo that is already in the phone. The upper part opens the camera page; the row under
/// it opens the phone's gallery and goes on to the review of the chosen photos, as the gallery button of the camera
/// page does.
class _ScanCard extends ConsumerStatefulWidget {
  const _ScanCard();

  @override
  ConsumerState<_ScanCard> createState() => _ScanCardState();
}

class _ScanCardState extends ConsumerState<_ScanCard> {
  bool _busy = false;

  void _openScan() {
    ref.read(scanFlowProvider.notifier).reset();
    context.go(Routes.scan);
  }

  /// Photos that are already in the phone: the system picker, as many as one scan takes, then the review.
  Future<void> _openGallery() async {
    if (_busy) return;
    final flow = ref.read(scanFlowProvider.notifier);
    flow.reset(); // a new scan, as with the camera
    final picker = ref.read(photoPickerProvider);
    final voice = ref.read(voiceServiceProvider);
    final owner = VoiceSession.maybeOf(context)?.owner;
    setState(() => _busy = true);
    try {
      final paths = await picker.pickFromGallery(limit: flow.maxPhotos);
      if (!mounted || paths.isEmpty) return;
      var added = false;
      for (final path in paths) {
        added = flow.addPhoto(path) || added;
      }
      if (added) Haptics.success();
      context.go(Routes.scanReview);
    } catch (_) {
      Haptics.error();
      await voice.speakPrompts(const ['error_try_again'], owner: owner);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final title = t('home_scan_card_title');
    // A narrow phone or large text leaves the words too little room next to the 76 px circle and the arrow: the circle
    // gets smaller and the (decorative) arrow goes, so the title keeps to one or two lines and the card stays short enough
    // for the photo button to be in view without scrolling.
    final compact = MediaQuery.sizeOf(context).width < 360 || MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    final circle = compact ? 56.0 : 76.0;
    return AppCard(
      padding: EdgeInsets.zero,
      radius: 24,
      // The ripple of the two buttons must show over the white card, so they sit on a transparent Material above it.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              label: t('a11y_camera'),
              excludeSemantics: true,
              child: InkWell(
                key: const ValueKey('home-scan'),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                onTap: () {
                  Haptics.tap();
                  _openScan();
                },
                // 10 at the bottom, then the gallery button starts with its own 4 above the hairline: 14 in all.
                child: Padding(
                  padding: EdgeInsets.fromLTRB(compact ? 14 : 18, compact ? 14 : 18, compact ? 14 : 18, 10),
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
                            Text(
                              t('home_scan_card_hint'),
                              style: const TextStyle(fontSize: 15, color: AppColors.inkSoft),
                            ),
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
            Semantics(
              button: true,
              label: t('a11y_gallery'),
              excludeSemantics: true,
              child: InkWell(
                key: const ValueKey('home-gallery'),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                onTap: _busy
                    ? null
                    : () {
                        Haptics.tap();
                        _openGallery();
                      },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Divider(height: 1, thickness: 1, color: AppColors.line),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 14, 0, 18),
                        child: Row(
                          children: [
                            const Icon(AppIcons.gallery, size: 20, color: AppColors.inkSoft),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                t('home_gallery_row'),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.inkSoft,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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

/// `.ibtn.glass`: a white circle at 14 % on the green header, white picture; with [badge] unread the red count of the
/// mockup's `.badge` (22 high, 12 / 800, a 2 px ring in the header's green) on its upper right corner.
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
      onPressed: onPressed,
    );
    if (badge <= 0) return button;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        // The circle is 48 inside its 56 tap area, so -2 / -2 of the circle is 2 / 2 of the area. The number never takes
        // taps from the bell under it, and stays small however large the text is set.
        Positioned(
          right: 2,
          top: 2,
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
          size: Dimens.ibtn,
          round: true,
        ),
      ),
    ),
  );
}

/// Whether Home asks the server for the field (`GET /v1/field`) to show "Now in your field". Off under `flutter test`,
/// so the extra request cannot take a failure that a test queued for another call; the field tests cover the data.
final homeFieldSummaryProvider = Provider<bool>((ref) => !Platform.environment.containsKey('FLUTTER_TEST'));

/// "Now in your field": up to three readings of the field page in one white card, three equal columns with a hairline
/// between them (a blue picture, the grey name, the word). The card opens the field page. Shown only when the field
/// answer is there; while it loads, or without internet and without a kept answer, nothing shows.
class _FieldSummary extends ConsumerWidget {
  const _FieldSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(homeFieldSummaryProvider)) return const SizedBox.shrink();
    final view = ref.watch(fieldProvider).value;
    if (view == null || view.hasNoData) return const SizedBox.shrink();
    final all = readingTiles(view.field.readings, weather: ref.watch(weatherOnProvider));
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
                        child: _Reading(tile: tiles[i], label: t(tiles[i].labelKey), word: t(tiles[i].wordKey)),
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

/// One reading of the field card: a 24 px blue picture (all three are blue, as in the mockup), the name in 13 grey and
/// the word in 16 / 700. A long word shrinks instead of wrapping, so the three columns stay level.
class _Reading extends StatelessWidget {
  const _Reading({required this.tile, required this.label, required this.word});

  final ReadingTile tile;
  final String label;
  final String word;

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
    ],
  );
}
