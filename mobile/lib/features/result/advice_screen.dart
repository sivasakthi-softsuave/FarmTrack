import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/voice/utterance.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/redirect.dart';
import '../../core/widgets/voice_scaffold.dart';
import '../diary/diary_providers.dart';
import '../scan/scan_scope.dart';
import 'advice_widgets.dart';

/// The result for an `ok` scan: severity card, medicines with dose sentences, timing, warnings and steps.
/// It says `result_intro`, then the advice's spoken version and "if you have sprayed, tap the green tick". The green
/// tick opens the spray diary's confirm screen for this advice; once the spray is written the tick is replaced by a
/// green "sprayed" mark (grey "waiting" while the entry still waits for the internet).
class AdviceScreen extends StatelessWidget {
  const AdviceScreen({super.key});

  @override
  Widget build(BuildContext context) => ScanScope(builder: _content);

  Widget _content(BuildContext context, WidgetRef ref, ScanOut scan) {
    final advice = scan.advice;
    if (advice == null) return const Redirect(to: Routes.home);

    final lang = ref.watch(languageProvider);
    final resources = ref.watch(resourcesProvider);
    final t = ref.watch(stringsProvider);
    final cropId = advice.cropId.isNotEmpty ? advice.cropId : (scan.crop?.cropId ?? '');
    final cropName = resources.cropName(cropId, lang, serverName: scan.crop?.name);

    final spoken = (advice.spoken.isEmpty ? scan.spoken : advice.spoken).toUtterance(lang);
    final sprayed = ref.watch(sprayStateProvider(advice.id));
    // The sentence names the green tick, so the button that opens the diary is the green tick. The app picks the
    // sentence itself (whatever prompt the server names for this step, the picture on the button is the app's).
    final script = <Utterance>[
      const PromptUtterance('result_intro'),
      ?spoken,
      if (sprayed == SprayState.none) const PromptUtterance('diary_tick_sprayed'),
    ];

    return VoiceScaffold(
      script: script,
      title: t('advice_title'),
      onBack: () => context.go(Routes.home),
      alignTop: true,
      // The mockup's `.pad`: 16 all round (the scaffold's default is 8 on top).
      bodyPadding: const EdgeInsets.fromLTRB(Dimens.gutter, Dimens.gutter, Dimens.gutter, 0),
      // The crop the advice is for stays visible as a tag on the severity card, so a wrong crop is noticed.
      body: AdviceCards(advice: advice, cropName: cropId.isNotEmpty ? cropName : ''),
      // A house to go home, and the wide green "I sprayed" (or the sprayed mark once it is written).
      wideAction: true,
      bottomRight: Row(
        children: [
          AppButton(
            key: const ValueKey('advice-home'),
            style: AppButtonStyle.outline,
            square: true,
            icon: AppIcons.house,
            semanticLabel: t('a11y_home'),
            onPressed: () => context.go(Routes.home),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: switch (sprayed) {
              SprayState.none => AppButton(
                key: const ValueKey('i-sprayed'),
                icon: AppIcons.tickBold,
                label: t('a11y_sprayed'),
                semanticLabel: t('a11y_sprayed'),
                onPressed: () => context.push(
                  Routes.diaryFor(
                    adviceId: advice.id,
                    cropId: cropId.isEmpty ? null : cropId,
                    productId: advice.products.isEmpty ? null : advice.products.first.productId,
                  ),
                ),
              ),
              SprayState.waiting => SprayStatusChip(waiting: true, label: t('diary_waiting_label')),
              SprayState.done => SprayStatusChip(waiting: false, label: t('advice_sprayed_done')),
            },
          ),
        ],
      ),
    );
  }
}
