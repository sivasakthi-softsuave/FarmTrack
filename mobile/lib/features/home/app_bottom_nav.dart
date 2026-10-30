import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/haptics.dart';
import '../scan/scan_flow.dart';

/// The pages of the bottom bar. [scan] is the big green camera in the middle.
enum AppTab { home, field, scan, diary, ask }

/// The bar at the bottom of Home, My field, Diary and Ask (the mockup's `.nav`): four pictures with a word, and the
/// photo in the middle as a raised green circle. From Home a page opens on top of it (the back arrow returns to Home);
/// between pages one replaces the other, so the back arrow always leads home.
///
/// The widget is [Dimens.nav] + [rise] + the phone's bottom inset tall: the bar itself and, above it, a transparent strip
/// the camera circle rises into (so the whole circle can be tapped). `VoiceScaffold` places it over the bottom of the
/// screen and keeps [Dimens.nav] free for it.
class AppBottomNav extends ConsumerWidget {
  const AppBottomNav({super.key, required this.current});

  final AppTab current;

  /// How far the camera circle rises above the bar (the mockup's -34 px margin, minus the 8 px of padding).
  static const rise = Dimens.navRise;

  /// The bar's own height without the phone's bottom inset.
  static const height = Dimens.nav;

  void _open(BuildContext context, WidgetRef ref, AppTab tab) {
    if (tab == current) return;
    Haptics.tap();
    switch (tab) {
      case AppTab.home:
        context.go(Routes.home);
      case AppTab.scan:
        ref.read(scanFlowProvider.notifier).reset();
        context.go(Routes.scan);
      case AppTab.field:
        _page(context, Routes.field);
      case AppTab.diary:
        _page(context, Routes.diary);
      case AppTab.ask:
        _page(context, Routes.ask);
    }
  }

  void _page(BuildContext context, String route) {
    if (current == AppTab.home) {
      context.push(route);
    } else {
      context.pushReplacement(route);
    }
  }

  /// On Home the three pages keep the keys the voice tour and the tests know (`home-field` ...).
  String _key(AppTab tab) {
    final homeKey = current == AppTab.home && (tab == AppTab.field || tab == AppTab.diary || tab == AppTab.ask);
    return homeKey ? 'home-${tab.name}' : 'nav-${tab.name}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final inset = MediaQuery.paddingOf(context).bottom;
    final items = [
      (AppTab.home, AppIcons.house, t('nav_home')),
      (AppTab.field, AppIcons.field, t('home_field_label')),
      (AppTab.scan, AppIcons.camera, t('home_scan_label')),
      (AppTab.diary, AppIcons.notebook, t('home_diary_label')),
      (AppTab.ask, AppIcons.question, t('home_ask_label')),
    ];
    // The words stay small enough to fit under the pictures at any text size.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: SizedBox(
        height: height + rise + inset,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: height + inset,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: AppColors.card,
                  border: Border(top: BorderSide(color: AppColors.line)),
                ),
                child: Padding(
                  padding: EdgeInsets.only(bottom: inset),
                  child: Row(
                    children: [
                      for (final (tab, icon, label) in items)
                        Expanded(
                          child: tab == AppTab.scan
                              ? const SizedBox.shrink()
                              : _NavItem(
                                  key: ValueKey(_key(tab)),
                                  icon: icon,
                                  label: label,
                                  selected: tab == current,
                                  onTap: () => _open(context, ref, tab),
                                ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Center(
                child: _ScanItem(
                  key: ValueKey(_key(AppTab.scan)),
                  label: items[2].$3,
                  selected: current == AppTab.scan,
                  onTap: () => _open(context, ref, AppTab.scan),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _wordStyle = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.inkSoft);

/// One of the four ordinary pages: a 56 x 32 pill with the picture (green on a soft green when it is the page you are
/// on) and the word below it.
class _NavItem extends StatelessWidget {
  const _NavItem({super.key, required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.green : AppColors.inkSoft;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.greenSoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 24, color: color),
              ),
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: _wordStyle.copyWith(fontWeight: selected ? FontWeight.w700 : FontWeight.w600, color: color),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The photo in the middle: a 68 px green circle with a 5 px white ring and a green glow, the word under it.
class _ScanItem extends StatelessWidget {
  const _ScanItem({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    excludeSemantics: true,
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: SizedBox(
        width: 84,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: AppColors.green,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.card, width: 5),
                boxShadow: [
                  BoxShadow(color: AppColors.green.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6)),
                ],
              ),
              child: const Icon(AppIcons.camera, size: 30, color: Colors.white),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: _wordStyle.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
