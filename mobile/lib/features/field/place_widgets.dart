import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/design.dart';
import 'place_providers.dart';

/// The first card of "My field" when the server can give the weather of a chosen place: which place the weather below is
/// of ("My field" or the place the farmer picked) and one tap to choose another. With a picked place a second button goes
/// back to the farmer's own field.
class PlaceBar extends ConsumerWidget {
  const PlaceBar({super.key, this.place});

  /// The picked place, or null for the farmer's own field.
  final PickedPlace? place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final name = place?.label ?? t('field_place_mine');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          key: const ValueKey('place-bar'),
          onTap: () => context.push(Routes.fieldPlace),
          semanticLabel: '${t('field_place_title')} $name. ${t('field_place_change')}',
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('field_place_title'), style: AppText.hMeta),
                    Text(
                      name,
                      key: const ValueKey('place-name'),
                      style: AppText.hName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      t('field_place_change'),
                      key: const ValueKey('place-change'),
                      style: AppText.hMeta.copyWith(color: AppColors.green, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(AppIcons.chevron, size: 22, color: AppColors.chevron),
            ],
          ),
        ),
        if (place != null) ...[
          const SizedBox(height: 10),
          AppButton(
            key: const ValueKey('place-clear'),
            style: AppButtonStyle.outline,
            icon: AppIcons.field,
            label: t('field_place_back'),
            semanticLabel: t('field_place_back'),
            onPressed: () => ref.read(pickedPlaceProvider.notifier).clear(),
          ),
        ],
      ],
    );
  }
}

/// The weather of a picked place could not be read (no internet, or the server's weather service is down): a calm card in
/// the screen itself, not a whole error screen, so the farmer can try again, choose another place or go back to the field.
class PlaceWeatherError extends ConsumerWidget {
  const PlaceWeatherError({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    return AppCard(
      key: const ValueKey('place-weather-error'),
      color: AppColors.amberSoft,
      flat: true,
      line: AppColors.amberLine,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconDot(AppIcons.warning, background: AppColors.amber, foreground: AppColors.ink, round: true),
              const SizedBox(width: 12),
              Expanded(child: Text(t('field_place_failed'), style: AppText.hName)),
            ],
          ),
          const SizedBox(height: 12),
          AppButton(
            key: const ValueKey('place-retry'),
            style: AppButtonStyle.outline,
            icon: AppIcons.roundArrow,
            label: t('field_place_retry'),
            semanticLabel: t('field_place_retry'),
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
