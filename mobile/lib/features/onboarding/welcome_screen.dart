import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/voice/utterance.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/voice_scaffold.dart';
import '../auth/auth_widgets.dart';

/// Speaks the welcome in the chosen language; the wide green tick button moves on to the login screen. Same look as the
/// login: the hills, the big name and a grey line, and the one green button in the strip.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    return VoiceScaffold(
      script: promptList(const ['welcome', 'tap_green_tick']),
      onBack: () => context.go(Routes.language),
      flatTopBar: true,
      alignTop: true,
      wideAction: true,
      bodyPadding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const HillsPicture(),
          const SizedBox(height: 14),
          Row(
            children: [
              const BrandTile(size: 56),
              const SizedBox(width: 14),
              Expanded(child: AuthHeading(title: t('app_name'))),
            ],
          ),
          const SizedBox(height: 10),
          Text(t('welcome_text'), style: const TextStyle(fontSize: 16, height: 1.36, color: AppColors.inkSoft)),
        ],
      ),
      bottomRight: AppButton(
        key: const ValueKey('welcome-continue'),
        icon: AppIcons.tickBold,
        label: t('welcome_start'),
        semanticLabel: t('welcome_start'),
        onPressed: () async {
          await ref.read(settingsProvider.notifier).markOnboardingDone();
          if (context.mounted) context.go(Routes.login);
        },
      ),
    );
  }
}
