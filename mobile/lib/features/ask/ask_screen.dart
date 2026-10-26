import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/voice/utterance.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/voice_scaffold.dart';
import '../home/app_bottom_nav.dart';
import 'ask_flow.dart';
import 'ask_suggestions.dart';

/// Route `/ask`: the app's ready questions as a list of cards (tap one: it is spoken and sent) and one button under
/// them that opens the typing screen. Speaks `ask_intro`, then says what to tap.
class AskScreen extends ConsumerWidget {
  const AskScreen({super.key});

  void _ask(BuildContext context, WidgetRef ref, AskSuggestion suggestion) {
    // A second tap while the answer screen is opening must not ask (and push) twice.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final lang = ref.read(languageProvider);
    unawaited(ref.read(askFlowProvider.notifier).ask(suggestion.question.forLang(lang), promptId: suggestion.promptId));
    context.push(Routes.askAnswer);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final lang = ref.watch(languageProvider);
    final suggestions = ref.watch(askSuggestionsProvider).value ?? const <AskSuggestion>[];

    return VoiceScaffold(
      title: t('home_ask_label'),
      showBack: false, // a main page: the bottom bar is the way around
      alignTop: true,
      // The mockup's `.pad`: 16 all round (the scaffold's default is 8 on top).
      bodyPadding: const EdgeInsets.fromLTRB(Dimens.gutter, Dimens.gutter, Dimens.gutter, 0),
      bottomNav: const AppBottomNav(current: AppTab.ask),
      script: promptList(const ['ask_intro', 'ask_tap_picture']),
      // An intro line, the ready questions as cards (picture, short title, the question itself), then "ask my own".
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(t('ask_intro_line'), style: AppText.hMeta.copyWith(fontSize: 15)),
          ),
          for (final s in suggestions)
            _SuggestionCard(
              key: ValueKey('ask-card-${s.id}'),
              icon: s.icon,
              label: s.label.forLang(lang),
              question: s.question.forLang(lang),
              onTap: () => _ask(context, ref, s),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: AppButton(
              key: const ValueKey('ask-own'),
              style: AppButtonStyle.outline,
              icon: AppIcons.pen,
              label: t('ask_own'),
              semanticLabel: t('ask_own'),
              onPressed: () => context.push(Routes.askType),
            ),
          ),
        ],
      ),
    );
  }
}

/// One ready question (`.card.row`): its picture in a soft blue square, a short title, the question itself and an arrow.
class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    super.key,
    required this.icon,
    required this.label,
    required this.question,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String question;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppCard(
    onTap: onTap,
    semanticLabel: label,
    child: Row(
      children: [
        IconDot(icon, background: AppColors.blueSoft, foreground: AppColors.blue),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppText.hName),
              if (question.isNotEmpty) Text(question, style: AppText.hMeta),
            ],
          ),
        ),
        const SizedBox(width: 12),
        const Icon(AppIcons.chevron, size: 24, color: AppColors.chevron),
      ],
    ),
  );
}
