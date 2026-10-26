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
import '../../core/widgets/big_buttons.dart';
import '../../core/widgets/voice_scaffold.dart';
import '../field/field_providers.dart';
import '../field/field_words.dart';
import '../offline/offline_cards.dart';
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

  void _openScan() {
    ref.read(scanFlowProvider.notifier).reset();
    context.go(Routes.scan);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final online = ref.watch(onlineProvider).value ?? true;
    final unread = ref.watch(unreadAlertsProvider).value ?? 0;
    final resultReady = ref.watch(offlineStatusProvider.select((s) => s.ready.isNotEmpty));
    final height = MediaQuery.sizeOf(context).height;
    final heroHeight = (height * 0.2).clamp(124.0, 170.0);
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
        if (!online)
          Semantics(
            label: t('a11y_offline'),
            child: const Icon(AppIcons.offline, size: 32, color: Colors.white),
          ),
        _TopIcon(
          key: const ValueKey('home-alerts'),
          icon: AppIcons.bell,
          semanticLabel: t('a11y_alerts'),
          badge: unread,
          onPressed: () => context.push(Routes.alerts),
        ),
        _TopIcon(
          key: const ValueKey('home-settings'),
          icon: AppIcons.gear,
          semanticLabel: t('a11y_settings'),
          onPressed: () => context.push(Routes.settings),
        ),
      ],
      // The big photo card first (it reaches into the green header), then what happened lately and the field.
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: heroHeight,
            child: _ScanCard(
              key: const ValueKey('home-scan'),
              label: t('home_scan_label'),
              hint: t('home_scan_hint'),
              semanticLabel: t('a11y_camera'),
              onPressed: _openScan,
            ),
          ),
          const SizedBox(height: 14),
          const OfflineCards(),
          const _FieldSummary(),
        ],
      ),
    );
  }

  /// "DS" for "Dinesh Sharma": the first letter of up to two words.
  static String _initials(String name) =>
      name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
}

/// The big photo card: a green camera circle, the word and a short hint, and an arrow. The whole card is the button.
class _ScanCard extends StatelessWidget {
  const _ScanCard({
    super.key,
    required this.label,
    required this.hint,
    required this.semanticLabel,
    required this.onPressed,
  });

  final String label;
  final String hint;
  final String semanticLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        color: AppColors.card,
        elevation: 2,
        shadowColor: AppColors.shadow,
        shape: AppDecor.shape(AppDecor.side(AppColors.green), radius: 24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            Haptics.tap();
            onPressed();
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final circle = constraints.maxHeight.clamp(56.0, 88.0);
                return Row(
                  children: [
                    Container(
                      width: circle,
                      height: circle,
                      decoration: BoxDecoration(
                        color: AppColors.green,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.green.withValues(alpha: 0.3),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Icon(AppIcons.camera, size: circle * 0.5, color: Colors.white),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(label, maxLines: 1, style: theme.headlineMedium),
                          ),
                          Flexible(
                            child: Text(
                              hint,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.bodyMedium?.copyWith(color: AppColors.inkSoft),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(color: AppColors.greenSoft, shape: BoxShape.circle),
                      child: const Icon(AppIcons.greenArrow, size: 24, color: AppColors.green),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _TopIcon extends StatelessWidget {
  const _TopIcon({super.key, required this.icon, required this.semanticLabel, required this.onPressed, this.badge = 0});

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onPressed;
  final int badge;

  @override
  Widget build(BuildContext context) {
    // White circles on the green header.
    final button = BigIconButton(
      icon: icon,
      semanticLabel: semanticLabel,
      color: AppColors.card,
      foreground: AppColors.brand,
      size: Dimens.minTouch,
      onPressed: onPressed,
    );
    if (badge <= 0) return button;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        // The number never takes taps from the bell under it, and stays small however large the text is set.
        Positioned(
          right: -2,
          top: -2,
          child: IgnorePointer(
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.2,
              child: Container(
                key: const ValueKey('alert-badge'),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.brand, width: 2),
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Whether Home asks the server for the field (`GET /v1/field`) to show "Now in your field". Off under `flutter test`,
/// so the extra request cannot take a failure that a test queued for another call; the field tests cover the data.
final homeFieldSummaryProvider = Provider<bool>((ref) => !Platform.environment.containsKey('FLUTTER_TEST'));

/// "Now in your field": up to three readings of the field page (picture, title, word) in one card that opens it. Shown
/// only when the field answer is there; while it loads, or without internet and without a kept answer, nothing shows.
class _FieldSummary extends ConsumerWidget {
  const _FieldSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(homeFieldSummaryProvider)) return const SizedBox.shrink();
    final view = ref.watch(fieldProvider).value;
    if (view == null || view.hasNoData) return const SizedBox.shrink();
    final tiles = readingTiles(view.field.readings, weather: ref.watch(weatherOnProvider)).take(3).toList();
    if (tiles.isEmpty) return const SizedBox.shrink();
    final t = ref.watch(stringsProvider);
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(t('field_readings_title'), style: theme.titleMedium?.copyWith(color: AppColors.inkSoft)),
          ),
          Semantics(
            button: true,
            label: t('home_field_label'),
            child: Material(
              key: const ValueKey('home-field-card'),
              color: AppColors.card,
              elevation: 2,
              shadowColor: AppColors.shadow,
              shape: AppDecor.shape(BorderSide.none),
              child: InkWell(
                borderRadius: BorderRadius.circular(Dimens.radius),
                onTap: () {
                  Haptics.tap();
                  context.push(Routes.field);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                  child: Row(
                    children: [
                      for (final tile in tiles)
                        Expanded(
                          child: Column(
                            children: [
                              Icon(tile.icon, size: 26, color: tile.color),
                              const SizedBox(height: 4),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  t(tile.labelKey),
                                  style: theme.bodyMedium?.copyWith(color: AppColors.inkSoft),
                                ),
                              ),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(t(tile.wordKey), style: theme.titleMedium),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
