import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/voice/utterance.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/voice_scaffold.dart';
import '../scan/scan_flow.dart';

/// Calm confirmation after a photo was saved because there was no internet: "Your photo is saved and will be sent
/// later." One wide green button leads back to the first page. Drawn like the mockup's centred "Not sure yet" card, but
/// grey: waiting is grey, and nothing here is an error.
class SavedOfflineScreen extends ConsumerWidget {
  const SavedOfflineScreen({super.key});

  void _home(BuildContext context, WidgetRef ref) {
    ref.read(scanFlowProvider.notifier).reset();
    context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    return VoiceScaffold(
      onBack: () => _home(context, ref),
      script: promptList(const ['offline_saved']),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            color: AppColors.neutralSoft,
            flat: true,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The grey "no internet" circle with the green "saved" tick on its corner (the mockup's small round badge).
                SizedBox(
                  width: 72,
                  height: 72,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const IconDot(
                        AppIcons.offline,
                        background: AppColors.inkSoft,
                        foreground: Colors.white,
                        size: 72,
                        round: true,
                        iconSize: 38,
                      ),
                      Positioned(
                        top: -8,
                        right: -8,
                        child: Container(
                          key: const ValueKey('saved-tick'),
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: AppColors.green,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.neutralSoft, width: 2),
                          ),
                          child: const Icon(AppIcons.tickBold, size: 14, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(t('offline_saved_title'), textAlign: TextAlign.center, style: AppText.big),
                const SizedBox(height: 6),
                Text(
                  t('offline_saved_hint'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, height: 1.45, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
        ],
      ),
      wideAction: true,
      bottomRight: AppButton(
        key: const ValueKey('saved-home'),
        icon: AppIcons.house,
        label: t('a11y_home'),
        semanticLabel: t('a11y_home'),
        onPressed: () => _home(context, ref),
      ),
    );
  }
}
