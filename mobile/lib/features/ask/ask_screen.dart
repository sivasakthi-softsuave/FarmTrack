import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/voice/utterance.dart';
import '../../core/widgets/voice_scaffold.dart';
import '../home/app_bottom_nav.dart';
import 'ask_flow.dart';
import 'ask_suggestions.dart';

/// Route `/ask`: ten big picture cards with common questions (tap one: it is spoken and sent) and one big button
/// that opens the typing screen. Speaks `ask_intro`, then says what to tap.
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
      alignTop: true,
      bottomNav: const AppBottomNav(current: AppTab.ask),
      script: promptList(const ['ask_intro', 'ask_tap_picture']),
      // The ready questions as a list (picture, short title, the question itself), then "ask my own question".
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final s in suggestions)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SuggestionCard(
                key: ValueKey('ask-card-${s.id}'),
                icon: s.icon,
                label: s.label.forLang(lang),
                question: s.question.forLang(lang),
                onTap: () => _ask(context, ref, s),
              ),
            ),
          const SizedBox(height: 4),
          _OwnQuestionButton(label: t('ask_own'), onTap: () => context.push(Routes.askType)),
        ],
      ),
    );
  }
}

/// The white button under the list that opens the typing screen.
class _OwnQuestionButton extends StatelessWidget {
  const _OwnQuestionButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: Material(
      key: const ValueKey('ask-own'),
      color: AppColors.card,
      shape: AppDecor.shape(const BorderSide(color: AppColors.line, width: 2), radius: 18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          Haptics.tap();
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.edit_rounded, size: 26, color: AppColors.ink),
                const SizedBox(width: 10),
                Flexible(child: Text(label, style: Theme.of(context).textTheme.titleMedium)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// One ready question: its picture in a soft blue circle, a short title, the question itself and an arrow.
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: AppColors.card,
        elevation: 2,
        shadowColor: AppColors.shadow,
        shape: AppDecor.shape(BorderSide.none),
        child: InkWell(
          borderRadius: BorderRadius.circular(Dimens.radius),
          onTap: () {
            Haptics.tap();
            onTap();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 76),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(color: AppColors.blueSoft, borderRadius: BorderRadius.circular(14)),
                    child: Icon(icon, size: 26, color: AppColors.blue),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: theme.titleMedium),
                        if (question.isNotEmpty)
                          Text(
                            question,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.bodyMedium?.copyWith(fontSize: 14, color: AppColors.inkSoft),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right_rounded, size: 26, color: AppColors.inkSoft),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
