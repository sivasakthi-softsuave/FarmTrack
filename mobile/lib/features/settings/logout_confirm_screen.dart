import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/voice/utterance.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/voice_scaffold.dart';

/// Route `/settings/logout`: "Log out of FarmTrack?" with the red cross (stay) and the green tick (log out) as the two
/// wide buttons of the action strip. Logging out forgets the login on this phone at once and tells the server in the
/// background. Drawn like the mockup's centred state cards (a big round picture, the question in 26 / 800).
class LogoutConfirmScreen extends ConsumerWidget {
  const LogoutConfirmScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    return VoiceScaffold(
      script: promptList(const ['settings_logout_confirm']),
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
                const IconDot(
                  AppIcons.logout,
                  background: AppColors.inkSoft,
                  foreground: Colors.white,
                  size: 72,
                  round: true,
                  iconSize: 38,
                ),
                const SizedBox(height: 12),
                Text(t('settings_logout_question'), textAlign: TextAlign.center, style: AppText.big),
              ],
            ),
          ),
        ],
      ),
      wideAction: true,
      bottomRight: Row(
        children: [
          Expanded(
            child: AppButton(
              key: const ValueKey('logout-no'),
              style: AppButtonStyle.danger,
              icon: AppIcons.cross,
              label: t('a11y_no'),
              semanticLabel: t('a11y_no'),
              onPressed: () => context.pop(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AppButton(
              key: const ValueKey('logout-yes'),
              icon: AppIcons.tickBold,
              label: t('a11y_yes'),
              semanticLabel: t('a11y_yes'),
              onPressed: () async {
                await ref.read(sessionProvider.notifier).logout();
                if (context.mounted) context.go(Routes.login);
              },
            ),
          ),
        ],
      ),
    );
  }
}
