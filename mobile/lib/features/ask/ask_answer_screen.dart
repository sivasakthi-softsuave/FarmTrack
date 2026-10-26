import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/voice/utterance.dart';
import '../../core/voice/voice_service.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/redirect.dart';
import '../../core/widgets/status_views.dart';
import '../../core/widgets/voice_scaffold.dart';
import 'ask_flow.dart';

/// Route `/ask/answer`: speaks the question (suggestion cards only), waits for the server, then speaks the answer and
/// shows it as large text with the sources small underneath. When the server refuses (no approved note supports an
/// answer) it speaks the refusal and offers one big button that asks a farm expert.
class AskAnswerScreen extends ConsumerStatefulWidget {
  const AskAnswerScreen({super.key});

  @override
  ConsumerState<AskAnswerScreen> createState() => _AskAnswerScreenState();
}

class _AskAnswerScreenState extends ConsumerState<AskAnswerScreen> {
  final Object _owner = Object();

  /// The question has been spoken: from now on the answer may be spoken (it never cuts the question off).
  bool _introDone = false;
  AskOut? _spokenAnswer;
  bool _sending = false;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_intro()));
  }

  Future<void> _intro() async {
    if (!mounted) return;
    final flow = ref.read(askFlowProvider);
    final id = flow.promptId;
    if (flow.phase != AskPhase.idle && id != null) {
      final known = ref.read(promptCatalogueProvider).contains(id);
      await ref.read(voiceServiceProvider).speak([
        if (known) PromptUtterance(id) else TextUtterance(flow.question, lang: ref.read(languageProvider)),
      ], owner: _owner);
    }
    if (!mounted) return;
    _introDone = true;
    _speakFor(ref.read(askFlowProvider));
  }

  /// What to say for the state the screen is in. Errors speak for themselves (`ErrorRetryScreen`).
  void _speakFor(AskState flow) {
    if (!mounted || !_introDone) return;
    final voice = ref.read(voiceServiceProvider);
    switch (flow.phase) {
      case AskPhase.asking:
        unawaited(voice.speakPrompts(const ['ask_wait'], owner: _owner));
      case AskPhase.answered:
        final answer = flow.answer;
        if (answer == null || identical(answer, _spokenAnswer)) return;
        _spokenAnswer = answer;
        Haptics.success();
        unawaited(voice.speak(_answerScript(answer), owner: _owner));
      case AskPhase.failed:
      case AskPhase.idle:
        break;
    }
  }

  /// The server's own spoken version (with its audio), else its text; a refusal without text says `ask_no_answer`.
  List<Utterance> _answerScript(AskOut answer) {
    final lang = answer.language.isEmpty ? ref.read(languageProvider) : answer.language;
    final spoken = answer.spoken?.toUtterance(lang);
    if (spoken != null) return [spoken];
    if (answer.answer.trim().isNotEmpty) return [TextUtterance(answer.answer, lang: lang)];
    return answer.refused ? promptList(const ['ask_no_answer']) : const [];
  }

  String _answerText(AskOut answer) {
    if (answer.answer.trim().isNotEmpty) return answer.answer;
    return answer.spoken?.text.forLang(answer.language.isEmpty ? ref.read(languageProvider) : answer.language) ?? '';
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.ask);
    }
  }

  Future<void> _askExpert(AskState flow) async {
    if (_sending || _sent) return;
    final voice = ref.read(voiceServiceProvider);
    setState(() => _sending = true);
    try {
      final message = flow.question.length > AskFlowNotifier.maxLength
          ? flow.question.substring(0, AskFlowNotifier.maxLength)
          : flow.question;
      await ref.read(apiClientProvider).createExpertRequest(ExpertRequestIn(message: message));
      Haptics.success();
      if (mounted) setState(() => _sent = true);
      await voice.speak(promptList(const ['ask_expert_sent']), owner: _owner);
    } on Object catch (e) {
      Haptics.error();
      await voice.speak(promptList([errorPromptFor(e)]), owner: _owner);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(askFlowProvider);
    ref.listen<AskState>(askFlowProvider, (previous, next) {
      if (previous?.phase != next.phase) _speakFor(next);
    });
    final t = ref.watch(stringsProvider);

    switch (flow.phase) {
      case AskPhase.idle:
        // Opened without a question (the app was restarted on this screen).
        return const Redirect(to: Routes.ask);
      case AskPhase.failed:
        return ErrorRetryScreen(
          error: flow.error ?? Exception('ask failed'),
          onRetry: () => unawaited(ref.read(askFlowProvider.notifier).retry()),
          onBack: _back,
        );
      case AskPhase.asking:
        return VoiceScaffold(
          owner: _owner,
          speakEnabled: false,
          script: const [],
          replayScript: promptList(const ['ask_wait']),
          onBack: _back,
          title: t('home_ask_label'),
          alignTop: true,
          bodyPadding: _padding,
          body: _Waiting(label: t('ask_loading'), question: flow.question),
        );
      case AskPhase.answered:
        final answer = flow.answer!;
        return answer.refused ? _refused(context, flow, answer, t) : _answered(context, flow, answer, t);
    }
  }

  /// The mockup's `.pad`: 16 all round (the scaffold's default is 8 on top).
  static const _padding = EdgeInsets.fromLTRB(Dimens.gutter, Dimens.gutter, Dimens.gutter, 0);

  /// The strip's way back to the first page: a wide green button, or (next to another button) the outlined square.
  Widget _homeButton(String Function(String, {Map<String, Object> args}) t, {bool square = false}) => AppButton(
    key: const ValueKey('ask-home'),
    style: square ? AppButtonStyle.outline : AppButtonStyle.primary,
    icon: AppIcons.house,
    label: square ? null : t('a11y_home'),
    square: square,
    semanticLabel: t('a11y_home'),
    onPressed: () => context.go(Routes.home),
  );

  Widget _answered(
    BuildContext context,
    AskState flow,
    AskOut answer,
    String Function(String, {Map<String, Object> args}) t,
  ) {
    final sources = {
      for (final c in answer.citations)
        if (c.source.trim().isNotEmpty) c.source.trim(),
    };
    return VoiceScaffold(
      owner: _owner,
      speakEnabled: false,
      showCaption: false, // the answer itself is on screen below
      script: const [],
      replayScript: _answerScript(answer),
      onBack: _back,
      title: t('home_ask_label'),
      alignTop: true,
      wideAction: true,
      bodyPadding: _padding,
      // One white card: the question as a small label, the answer, the sources as small grey lines.
      body: AppCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (flow.question.trim().isNotEmpty) ...[_QuestionLabel(flow.question), const _Divider()],
            SizedBox(
              key: const ValueKey('ask-answer'),
              child: Text(_answerText(answer), style: _answerStyle),
            ),
            if (sources.isNotEmpty) ...[
              const _Divider(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(AppIcons.info, size: 20, color: AppColors.inkSoft),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${t('ask_sources')}: ${sources.join(', ')}',
                      key: const ValueKey('ask-sources'),
                      style: AppText.hMeta,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      bottomRight: _homeButton(t),
    );
  }

  Widget _refused(
    BuildContext context,
    AskState flow,
    AskOut answer,
    String Function(String, {Map<String, Object> args}) t,
  ) {
    final text = _answerText(answer);
    return VoiceScaffold(
      owner: _owner,
      speakEnabled: false,
      showCaption: false,
      script: const [],
      replayScript: _answerScript(answer),
      onBack: _back,
      title: t('home_ask_label'),
      alignTop: true,
      wideAction: true,
      bodyPadding: _padding,
      // Blue = information (the mockup's "Not sure yet" card), then the question that was asked.
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          AppCard(
            flat: true,
            color: AppColors.blueSoft,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const IconDot(
                  AppIcons.info,
                  background: AppColors.blue,
                  foreground: Colors.white,
                  size: 72,
                  round: true,
                  iconSize: 38,
                ),
                const SizedBox(height: 12),
                Text(t('ask_refused_title'), textAlign: TextAlign.center, style: AppText.big),
                if (text.isNotEmpty)
                  Padding(
                    key: const ValueKey('ask-refusal'),
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, height: 1.45, color: _onBlueSoft),
                    ),
                  ),
              ],
            ),
          ),
          if (flow.question.trim().isNotEmpty) AppCard(child: _QuestionLabel(flow.question)),
        ],
      ),
      bottomRight: Row(
        spacing: 12,
        children: [
          _homeButton(t, square: true),
          Expanded(
            child: _sent
                ? _ExpertSent(key: const ValueKey('ask-expert-sent'), label: t('expert_sent'))
                : AppButton(
                    key: const ValueKey('ask-expert'),
                    icon: AppIcons.expert,
                    label: t('a11y_expert'),
                    semanticLabel: t('a11y_expert'),
                    onPressed: _sending ? null : () => unawaited(_askExpert(flow)),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The answer text: 16 / 1.45 on the white card.
const _answerStyle = TextStyle(fontSize: 16, height: 1.45, fontWeight: FontWeight.w500, color: AppColors.ink);

/// The text colour of the mockup's blue card (`#22364F`): dark blue-grey, well above 4.5 to 1 on [AppColors.blueSoft].
const _onBlueSoft = Color(0xFF22364F);

/// The question that was asked, as a small grey label with the question picture.
class _QuestionLabel extends StatelessWidget {
  const _QuestionLabel(this.question);

  final String question;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(top: 1),
        child: Icon(AppIcons.question, size: 20, color: AppColors.blue),
      ),
      const SizedBox(width: 8),
      // Letter spacing breaks Devanagari, so the Hindi label is the plain, slightly bigger one.
      Expanded(child: Text(question, style: isDevanagari(question) ? AppText.labelHindi : AppText.label)),
    ],
  );
}

/// A hairline between the parts of a card (the mockup's `height:1px; background:var(--line); margin:14px 0`).
class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 14),
    child: SizedBox(height: 1, child: ColoredBox(color: AppColors.line)),
  );
}

/// What replaces the expert button once the question is saved: a calm green box, not a button.
class _ExpertSent extends StatelessWidget {
  const _ExpertSent({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    height: Dimens.actionButton,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(color: AppColors.greenSoft, borderRadius: BorderRadius.circular(18)),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(AppIcons.tick, size: 24, color: AppColors.green),
        const SizedBox(width: 10),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, maxLines: 1, style: AppText.button.copyWith(color: AppColors.green)),
          ),
        ),
      ],
    ),
  );
}

/// How much of the ring and of the bar is drawn while they stand still: the mockup's ring (`stroke-dashoffset` 230 of 502).
const _stillShare = 0.54;

/// A progress ring with the question picture, the word, and a white card with the question and a bar, while the server
/// looks for the answer (the mockup's waiting screen). The ring and the bar stand still when the phone asks for no
/// animations.
class _Waiting extends StatelessWidget {
  const _Waiting({required this.label, required this.question});

  final String label;
  final String question;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Center(child: _Ring(still: still)),
        const SizedBox(height: 18),
        Text(label, textAlign: TextAlign.center, style: AppText.big),
        const SizedBox(height: 18),
        AppCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (question.trim().isNotEmpty) ...[_QuestionLabel(question), const SizedBox(height: 14)],
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: still
                    ? const _StillBar(key: ValueKey('ask-waiting-bar'))
                    : const LinearProgressIndicator(key: ValueKey('ask-waiting-bar'), minHeight: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The bar of a phone that asks for no animations: the grey track with a green part, not moving.
class _StillBar extends StatelessWidget {
  const _StillBar({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 12,
    child: ColoredBox(
      color: AppColors.track,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: _stillShare,
          child: SizedBox.expand(child: ColoredBox(color: AppColors.green)),
        ),
      ),
    ),
  );
}

/// A 180 dp ring (12 wide, green on its grey track) round a white circle with the question picture. Turning, or still
/// with part of it drawn.
class _Ring extends StatelessWidget {
  const _Ring({required this.still});

  final bool still;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: 180,
      height: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: still
                ? const CustomPaint(painter: _StillRingPainter())
                : const CircularProgressIndicator(
                    strokeWidth: 12,
                    strokeCap: StrokeCap.round,
                    backgroundColor: AppColors.track,
                    color: AppColors.green,
                  ),
          ),
          Container(
            width: 128,
            height: 128,
            decoration: const BoxDecoration(color: AppColors.card, shape: BoxShape.circle, boxShadow: AppDecor.shadows),
            child: const Icon(AppIcons.question, size: 60, color: AppColors.blue),
          ),
        ],
      ),
    ),
  );
}

class _StillRingPainter extends CustomPainter {
  const _StillRingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    const full = 2 * math.pi;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, full, false, paint..color = AppColors.track);
    canvas.drawArc(rect, -math.pi / 2, full * _stillShare, false, paint..color = AppColors.green);
  }

  @override
  bool shouldRepaint(_StillRingPainter oldDelegate) => false;
}
