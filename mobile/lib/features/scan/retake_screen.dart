import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/voice/utterance.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/voice_scaffold.dart';
import 'result_prompts.dart';
import 'scan_flow.dart';

/// The photo was not usable: speaks what was wrong (blurry, dark, far, no leaf) and offers the camera again.
///
/// An amber card (a warning, as in the mockup's advice) with the picture of the problem and the sentence the voice speaks;
/// the one action is the green camera button.
class RetakeScreen extends ConsumerWidget {
  const RetakeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scan = ref.watch(scanFlowProvider).scan;
    final catalogue = ref.watch(promptCatalogueProvider);
    final lang = ref.watch(languageProvider);
    final t = ref.watch(stringsProvider);
    final issues = scan?.quality.issues ?? const <String>[];
    final tip = qualityTipPrompt(scan?.quality, catalogue);
    final retake = pickPrompt(scan?.promptsFor(NextAction.retake) ?? const [], 'scan_retake_tap', catalogue);
    final reason = catalogue.text(tip, lang);

    return VoiceScaffold(
      script: promptList([tip, retake]),
      onBack: () => context.go(Routes.home),
      body: AppCard(
        color: AppColors.amberSoft,
        flat: true,
        line: AppColors.amberLine,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconDot(
              _issueIcon(issues),
              key: const ValueKey('retake-issue'),
              background: AppColors.amber,
              foreground: AppColors.ink,
              size: 72,
              round: true,
              iconSize: 38,
            ),
            const SizedBox(height: 12),
            Text(t('retake_title'), textAlign: TextAlign.center, style: AppText.big),
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 6),
              // The amber card's text colour of the mockup (`#3B3320`).
              Text(
                reason,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, height: 1.45, color: Color(0xFF3B3320)),
              ),
            ],
          ],
        ),
      ),
      wideAction: true,
      bottomRight: AppButton(
        key: const ValueKey('retake-camera'),
        icon: AppIcons.camera,
        label: t('a11y_camera'),
        semanticLabel: t('a11y_camera'),
        onPressed: () {
          ref.read(scanFlowProvider.notifier).reset();
          context.go(Routes.scan);
        },
      ),
    );
  }

  IconData _issueIcon(List<String> issues) {
    if (issues.contains('blurry')) return AppIcons.blur;
    if (issues.contains('too_dark')) return AppIcons.moon;
    if (issues.contains('too_bright')) return AppIcons.sun;
    if (issues.contains('too_small')) return AppIcons.zoom;
    if (issues.contains('no_leaf')) return AppIcons.leaf;
    return AppIcons.warning;
  }
}
