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
import '../scan/result_prompts.dart';
import '../scan/scan_scope.dart';
import 'advice_result.dart';
import 'advice_widgets.dart';

/// The result for an `ok` scan: the crop's picture and name, the disease, the medicines one by one with the two steps
/// to use each, and last one card with the advice and the warnings (see [AdviceResult]).
///
/// It says only the crop, the disease and the names of the medicines when it opens. The steps and the advice are said
/// when the farmer taps the speaker of their card. The green tick opens the spray diary's confirm screen for this
/// advice; once the spray is written the tick is replaced by a green "sprayed" mark (grey "waiting" while the entry
/// still waits for the internet).
class AdviceScreen extends ConsumerStatefulWidget {
  const AdviceScreen({super.key});

  @override
  ConsumerState<AdviceScreen> createState() => _AdviceScreenState();
}

class _AdviceScreenState extends ConsumerState<AdviceScreen> {
  final Object _owner = Object();

  @override
  Widget build(BuildContext context) => ScanScope(builder: _content);

  /// A card's speaker: says [sentence] now.
  void _say(String sentence) {
    final lang = ref.read(languageProvider);
    ref.read(voiceServiceProvider).speak([TextUtterance(sentence, lang: lang)], owner: _owner);
  }

  Widget _content(BuildContext context, WidgetRef ref, ScanOut scan) {
    final advice = scan.advice;
    if (advice == null) return const Redirect(to: Routes.home);

    final lang = ref.watch(languageProvider);
    final resources = ref.watch(resourcesProvider);
    final catalogue = ref.watch(promptCatalogueProvider);
    final t = ref.watch(stringsProvider);
    final cropId = advice.cropId.isNotEmpty ? advice.cropId : (scan.crop?.cropId ?? '');
    final cropName = cropId.isEmpty ? '' : resources.cropName(cropId, lang, serverName: scan.crop?.name);
    final diseaseName = scan.disease?.name?.forLang(lang).trim() ?? '';
    final sprayed = ref.watch(sprayStateProvider(advice.id));

    // Only these three are said by themselves: the crop, the disease, the medicines (by name).
    final medicines = [for (final p in advice.products) medicineName(p, lang)].where((n) => n.isNotEmpty).toList();
    final named = cropPrompt(cropId, catalogue);
    final script = <Utterance>[
      if (cropId.isNotEmpty) named != null ? PromptUtterance(named) : TextUtterance(cropName, lang: lang),
      if (diseaseName.isNotEmpty) TextUtterance(diseaseName, lang: lang),
      if (medicines.isNotEmpty)
        TextUtterance(t('advice_say_medicine', args: {'names': medicines.join(', ')}), lang: lang),
    ];

    return VoiceScaffold(
      owner: _owner,
      script: script,
      title: t('advice_title'),
      onBack: () => context.go(Routes.home),
      alignTop: true,
      // The mockup's `.pad`: 16 all round (the scaffold's default is 8 on top).
      bodyPadding: const EdgeInsets.fromLTRB(Dimens.gutter, Dimens.gutter, Dimens.gutter, 0),
      body: AdviceResult(advice: advice, cropId: cropId, cropName: cropName, diseaseName: diseaseName, onSpeak: _say),
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
