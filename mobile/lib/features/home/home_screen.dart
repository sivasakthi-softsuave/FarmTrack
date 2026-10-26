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
import '../offline/offline_cards.dart';
import '../scan/scan_flow.dart';

/// The four big picture buttons. Speaks `home_intro`; on the very first visit it also says what each button does.
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
    final heroHeight = (height * 0.22).clamp(124.0, 190.0);
    final smallHeight = (height * 0.19).clamp(104.0, 160.0);
    final farmer = ref.watch(sessionProvider).farmer;
    final firstName = (farmer?.name ?? '').trim().split(' ').first;
    final place = [farmer?.village, farmer?.district].whereType<String>().where((s) => s.isNotEmpty).join(', ');

    Widget tile(String key, Widget picture, String label, VoidCallback onTap, double h) => SizedBox(
      height: h,
      child: PictureTile(
        key: ValueKey(key),
        semanticLabel: label,
        label: label,
        borderColor: AppColors.line,
        onPressed: onTap,
        child: _Bubble(child: picture),
      ),
    );

    return VoiceScaffold(
      showBack: false,
      brandHeader: true,
      title: firstName.isEmpty ? t('app_name') : t('home_greeting', args: {'name': firstName}),
      subtitle: place,
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
      // One big card for the photo and three smaller ones; the bell and the gear are in the green header.
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OfflineCards(),
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: tile(
                  'home-field',
                  const _FieldPicture(size: 44),
                  t('home_field_label'),
                  () => context.push(Routes.field),
                  smallHeight,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: tile(
                  'home-diary',
                  const Icon(AppIcons.notebook, size: 40, color: AppColors.blue),
                  t('home_diary_label'),
                  () => context.push(Routes.diary),
                  smallHeight,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: tile(
                  'home-ask',
                  const Icon(AppIcons.question, size: 40, color: AppColors.blue),
                  t('home_ask_label'),
                  () => context.push(Routes.ask),
                  smallHeight,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
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

/// The soft blue circle behind the picture of a small Home card.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: 64,
    height: 64,
    alignment: Alignment.center,
    decoration: const BoxDecoration(color: AppColors.blueSoft, shape: BoxShape.circle),
    child: child,
  );
}

/// The "My field" picture: a cloud over a patch of grass, so both "the field picture" and "the cloud picture"
/// of the voice prompts match what is on screen.
class _FieldPicture extends StatelessWidget {
  const _FieldPicture({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      children: [
        Positioned(
          left: 0,
          bottom: 0,
          child: Icon(AppIcons.field, size: size * 0.7, color: AppColors.green),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: Icon(AppIcons.cloud, size: size * 0.75, color: AppColors.blue),
        ),
      ],
    ),
  );
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
