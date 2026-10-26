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
import 'ask_flow.dart';

/// Route `/ask/type`: the farmer types a question with the phone's own keyboard (at most 500 characters), then taps
/// the green send button. The question goes to the server in the app language, with the farmer's main crop.
class AskTypeScreen extends ConsumerStatefulWidget {
  const AskTypeScreen({super.key});

  @override
  ConsumerState<AskTypeScreen> createState() => _AskTypeScreenState();
}

class _AskTypeScreenState extends ConsumerState<AskTypeScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  bool get _canSend => _controller.text.trim().length >= AskFlowNotifier.minLength;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    if (!_canSend || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
    unawaited(ref.read(askFlowProvider.notifier).ask(_controller.text));
    // The answer replaces this screen, so "back" from the answer returns to the cards.
    context.pushReplacement(Routes.askAnswer);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    return VoiceScaffold(
      title: t('home_ask_label'),
      alignTop: true,
      wideAction: true,
      // 12 + 4 instead of 16: the field's focus glow reaches 4 dp outside it and the scroll view would cut it off.
      bodyPadding: const EdgeInsets.fromLTRB(12, Dimens.gutter, 12, 0),
      script: promptList(const ['ask_type_question', 'ask_tap_send']),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FieldLabel(icon: AppIcons.pen, text: t('ask_own')),
            DecoratedBox(
              // `.input.focus`: a green border and a soft green glow around it.
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: _focus.hasFocus
                    ? [BoxShadow(color: AppColors.green.withValues(alpha: 0.14), spreadRadius: 4)]
                    : null,
              ),
              child: TextField(
                key: const ValueKey('ask-field'),
                controller: _controller,
                focusNode: _focus,
                autofocus: true,
                maxLength: AskFlowNotifier.maxLength,
                minLines: 3,
                maxLines: 8,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                style: _inputText,
                decoration: InputDecoration(
                  hintText: t('ask_type_hint'),
                  hintStyle: _inputText.copyWith(color: AppColors.inkSoft),
                  counterText: '', // drawn below the glowing box instead (it would sit inside the glow)
                  filled: true,
                  fillColor: AppColors.card,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  border: _border(AppColors.line),
                  enabledBorder: _border(AppColors.line),
                  focusedBorder: _border(AppColors.green),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  '${_controller.text.characters.length}/${AskFlowNotifier.maxLength}',
                  style: AppText.hMeta.copyWith(fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomRight: AppButton(
        key: const ValueKey('ask-send'),
        icon: AppIcons.send,
        label: t('ask_send'),
        semanticLabel: t('ask_send'),
        onPressed: _canSend ? _send : null,
      ),
    );
  }

  /// `.input`: 18 / 600 text.
  static const _inputText = TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.4, color: AppColors.ink);

  /// `.input`: radius 16, a 2 px border.
  static OutlineInputBorder _border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: color, width: 2),
  );
}

/// `.field-l`: a green picture and a word above a field.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.green),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: AppText.hName.copyWith(fontSize: 15))),
        ],
      ),
    ),
  );
}
