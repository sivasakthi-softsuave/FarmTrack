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

/// The bar at the bottom of Home, My field, Diary and Ask: four pictures with a word, and the photo in the middle as a
/// raised green circle. From Home a page opens on top of it (the back arrow returns to Home); between pages one
/// replaces the other, so the back arrow always leads home.
class AppBottomNav extends ConsumerWidget {
  const AppBottomNav({super.key, required this.current});

  final AppTab current;

  /// The bar's own height (the camera circle rises above it).
  static const height = 72.0;

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
    final items = [
      (AppTab.home, AppIcons.house, t('nav_home')),
      (AppTab.field, AppIcons.field, t('home_field_label')),
      (AppTab.scan, AppIcons.camera, t('home_scan_label')),
      (AppTab.diary, AppIcons.notebook, t('home_diary_label')),
      (AppTab.ask, AppIcons.question, t('home_ask_label')),
    ];
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        top: false,
        // The words stay small enough to fit under the pictures at any text size.
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: SizedBox(
            height: height,
            child: Row(
              children: [
                for (final (tab, icon, label) in items)
                  Expanded(
                    child: _NavItem(
                      key: ValueKey(_key(tab)),
                      icon: icon,
                      label: label,
                      selected: tab == current,
                      raised: tab == AppTab.scan,
                      onTap: () => _open(context, ref, tab),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.raised,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;

  /// The photo: a green circle that rises above the bar.
  final bool raised;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.green : AppColors.inkSoft;
    final word = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: selected || raised ? FontWeight.w800 : FontWeight.w600,
          color: raised ? AppColors.ink : color,
        ),
      ),
    );
    final Widget picture;
    if (raised) {
      picture = Transform.translate(
        offset: const Offset(0, -16),
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: AppColors.green,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.card, width: 4),
            boxShadow: [
              BoxShadow(color: AppColors.green.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 5)),
            ],
          ),
          child: Icon(icon, size: 28, color: Colors.white),
        ),
      );
    } else {
      picture = Container(
        width: 56,
        height: 30,
        decoration: BoxDecoration(
          color: selected ? AppColors.greenSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Icon(icon, size: 24, color: color),
      );
    }
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: raised ? MainAxisAlignment.end : MainAxisAlignment.center,
          children: [
            if (raised) Flexible(child: OverflowBox(maxHeight: 60, child: picture)) else picture,
            const SizedBox(height: 3),
            word,
            if (raised) const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
