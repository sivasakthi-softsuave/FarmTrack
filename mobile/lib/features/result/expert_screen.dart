import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/errors/api_exception.dart';
import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/voice/utterance.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/redirect.dart';
import '../../core/widgets/status_views.dart';
import '../../core/widgets/voice_scaffold.dart';
import '../scan/result_prompts.dart';
import '../scan/scan_flow.dart';
import '../scan/scan_scope.dart';
import 'advice_widgets.dart';

/// `needs_expert`, `no_approved_data` and `not_a_disease`: says so plainly, adds the server's own spoken text and
/// offers one button that asks a farm expert (POST /v1/expert-requests).
class ExpertScreen extends ConsumerStatefulWidget {
  const ExpertScreen({super.key});

  @override
  ConsumerState<ExpertScreen> createState() => _ExpertScreenState();
}

typedef _Words = String Function(String key, {Map<String, Object> args});

class _ExpertScreenState extends ConsumerState<ExpertScreen> {
  final Object _owner = Object();
  bool _sending = false;
  bool _sent = false;

  static const _variantPrompt = {
    ScanStatus.needsExpert: 'result_expert',
    ScanStatus.noApprovedData: 'result_no_data',
    ScanStatus.notADisease: 'result_not_disease',
  };

  Future<void> _askExpert(ScanOut scan) async {
    if (_sending || _sent) return;
    final voice = ref.read(voiceServiceProvider);
    setState(() => _sending = true);
    try {
      await ref.read(apiClientProvider).createExpertRequest(ExpertRequestIn(scanId: scan.id));
      Haptics.success();
      if (mounted) setState(() => _sent = true);
      // "Done. Your photos are saved." (the case is kept in the database)
      await voice.speak(promptList(const ['expert_photos_saved']), owner: _owner);
    } on ApiException catch (e) {
      Haptics.error();
      await voice.speak(promptList([errorPromptFor(e)]), owner: _owner);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _retake() {
    ref.read(scanFlowProvider.notifier).reset();
    context.go(Routes.scan);
  }

  @override
  Widget build(BuildContext context) => ScanScope(builder: _content);

  Widget _content(BuildContext context, WidgetRef ref, ScanOut scan) {
    if (!_variantPrompt.containsKey(scan.status)) return const Redirect(to: Routes.home);

    final lang = ref.watch(languageProvider);
    final catalogue = ref.watch(promptCatalogueProvider);
    final t = ref.watch(stringsProvider);
    final phone = ref.watch(sessionProvider.select((s) => s.farmer?.phoneMasked ?? ''));
    final fallback = _variantPrompt[scan.status]!;
    final stepAction = scan.status == ScanStatus.notADisease ? NextAction.addPhoto : NextAction.askExpert;
    // "No disease seen" always opens with its own fixed sentence: the server's step prompt for it is the add-photo
    // question ("take one more photo?"), which would come before the finding.
    final variant = scan.status == ScanStatus.notADisease
        ? fallback
        : pickPrompt(scan.promptsFor(stepAction), fallback, catalogue);

    final look = switch (scan.status) {
      ScanStatus.needsExpert => _Look(
        icon: AppIcons.expert,
        title: t('expert_variant_expert'),
        text: t('expert_card_expert'),
        fill: AppColors.blueSoft,
        dot: AppColors.blue,
        onDot: Colors.white,
        // The mockup's inline blue-grey text colour.
        textColor: const Color(0xFF22364F),
      ),
      ScanStatus.noApprovedData => _Look(
        icon: AppIcons.info,
        title: t('expert_variant_no_data'),
        text: catalogue.text(fallback, lang),
        fill: AppColors.amberSoft,
        line: AppColors.amberLine,
        dot: AppColors.amber,
        onDot: AppColors.ink,
        textColor: adviceAmberText,
      ),
      _ => _Look(
        icon: AppIcons.noDisease,
        title: t('expert_variant_not_disease'),
        text: catalogue.text(fallback, lang),
        fill: AppColors.neutralSoft,
        dot: AppColors.inkSoft,
        onDot: Colors.white,
        textColor: AppColors.ink,
      ),
    };
    final advice = scan.advice;
    final script = <Utterance>[PromptUtterance(variant), ?scan.spoken.toUtterance(lang)];
    final photos = scan.photos < 1 ? 1 : scan.photos;

    return VoiceScaffold(
      owner: _owner,
      script: script,
      title: t('result_title'),
      onBack: () => context.go(Routes.home),
      alignTop: true,
      // The mockup's `.pad`: 16 all round (the scaffold's default is 8 on top).
      bodyPadding: const EdgeInsets.fromLTRB(Dimens.gutter, Dimens.gutter, Dimens.gutter, 0),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // What happened, in one tinted card: the picture in a full-colour circle and the words under it.
          _StatusCard(look: look, status: scan.status),
          const SizedBox(height: 12),
          _PhotosCard(
            count: photos > 3 ? 3 : photos,
            label: photos == 1 ? t('expert_photos_one') : t('expert_photos_many', args: {'n': photos}),
            savedLabel: _sent ? t('expert_sent') : null,
          ),
          if (phone.isNotEmpty) ...[
            const SizedBox(height: 12),
            AppCard(
              child: Row(
                children: [
                  const IconDot(AppIcons.phone, background: AppColors.greenSoft, foreground: AppColors.green),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('expert_call_on'), style: AppText.hMeta),
                        Text(phone, style: AppText.hName),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          AppCard(
            child: Row(
              children: [
                const IconDot(AppIcons.clock, background: AppColors.neutralSoft, foreground: AppColors.inkSoft),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t('expert_keep_phone'), style: AppText.hName.copyWith(fontSize: 16)),
                      Text(t('expert_calls_from'), style: AppText.hMeta),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (advice != null) ...[const SizedBox(height: 12), AdviceCards(advice: advice)],
        ],
      ),
      wideAction: true,
      bottomRight: _sent ? _sentStrip(t) : _askStrip(t, scan),
    );
  }

  /// Before the case is saved: a round arrow for a new photo, a house, and the wide green "save this case".
  Widget _askStrip(_Words t, ScanOut scan) => Row(
    children: [
      AppButton(
        key: const ValueKey('expert-camera'),
        style: AppButtonStyle.outline,
        square: true,
        icon: AppIcons.roundArrow,
        semanticLabel: t('retake_title'),
        onPressed: _retake,
      ),
      const SizedBox(width: 12),
      AppButton(
        key: const ValueKey('expert-home'),
        style: AppButtonStyle.outline,
        square: true,
        icon: AppIcons.house,
        semanticLabel: t('a11y_home'),
        onPressed: () => context.go(Routes.home),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: AppButton(
          key: const ValueKey('ask-expert'),
          icon: AppIcons.expert,
          label: t('a11y_expert'),
          semanticLabel: t('a11y_expert'),
          onPressed: _sending ? null : () => _askExpert(scan),
        ),
      ),
    ],
  );

  /// Once it is saved (the mockup's strip): the wide "take the photo again" and the green house.
  Widget _sentStrip(_Words t) => Row(
    children: [
      Expanded(
        child: AppButton(
          key: const ValueKey('expert-camera'),
          style: AppButtonStyle.outline,
          icon: AppIcons.roundArrow,
          label: t('retake_title'),
          semanticLabel: t('retake_title'),
          onPressed: _retake,
        ),
      ),
      const SizedBox(width: 12),
      _GreenHomeButton(
        key: const ValueKey('expert-home'),
        semanticLabel: t('a11y_home'),
        onPressed: () => context.go(Routes.home),
      ),
    ],
  );
}

/// What differs between the three variants of this screen: the picture, the colours and the words.
class _Look {
  const _Look({
    required this.icon,
    required this.title,
    required this.text,
    required this.fill,
    required this.dot,
    required this.onDot,
    required this.textColor,
    this.line,
  });

  final IconData icon;
  final String title;
  final String text;
  final Color fill;
  final Color? line;
  final Color dot;
  final Color onDot;
  final Color textColor;
}

/// The tinted card at the top: a 72 px round picture, the big word and one sentence, centred.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.look, required this.status});

  final _Look look;
  final ScanStatus status;

  @override
  Widget build(BuildContext context) => AppCard(
    color: look.fill,
    flat: true,
    line: look.line,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
    child: Column(
      children: [
        IconDot(
          look.icon,
          key: ValueKey('expert-icon-${status.wire}'),
          background: look.dot,
          foreground: look.onDot,
          size: 72,
          round: true,
          iconSize: 38,
        ),
        const SizedBox(height: 12),
        Text(look.title, textAlign: TextAlign.center, style: AppText.big),
        if (look.text.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            look.text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, height: 1.45, color: look.textColor),
          ),
        ],
      ],
    ),
  );
}

/// The photos that were sent: a small green tile for each (at most three) and how many, then (once the case is saved) the
/// green "Saved" tag. On one line when it fits, wrapped when the words are long or the text is big.
class _PhotosCard extends StatelessWidget {
  const _PhotosCard({required this.count, required this.label, required this.savedLabel});

  final int count;
  final String label;

  /// The word of the green tag, or null before the case is saved.
  final String? savedLabel;

  // The mockup's inline colours of the photo tile and its leaf.
  static const _tile = Color(0xFF2C6B37);
  static const _leaf = Color(0xFFBFE5C8);

  static double _width(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: DefaultTextStyle.of(context).style.merge(style)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    return painter.width.ceilToDouble() + 1;
  }

  @override
  Widget build(BuildContext context) {
    final tiles = [
      for (var i = 0; i < count; i++)
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: _tile, borderRadius: BorderRadius.circular(12)),
          child: const Icon(AppIcons.leaf, size: 24, color: _leaf),
        ),
    ];
    final text = Text(label, style: AppText.hMeta);
    final saved = savedLabel;
    final pill = saved == null
        ? null
        : ResultPill(
            saved,
            key: const ValueKey('expert-sent'),
            background: AppColors.green,
            foreground: Colors.white,
            icon: AppIcons.tickBold,
          );
    return AppCard(
      child: LayoutBuilder(
        builder: (context, box) {
          // 12 padding either side of the word, the 20 px tick and its 6 px gap.
          final pillWidth = saved == null ? 0.0 : 24 + 26 + _width(context, saved, AppText.pill);
          final need =
              count * 56.0 +
              (count - 1) * 12 +
              12 +
              _width(context, label, AppText.hMeta) +
              (pill == null ? 0 : 12 + pillWidth);
          if (need <= box.maxWidth) {
            return Row(
              children: [
                for (final tile in tiles) ...[tile, const SizedBox(width: 12)],
                Expanded(child: text),
                if (pill != null) ...[const SizedBox(width: 12), pill],
              ],
            );
          }
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [...tiles, text, ?pill],
          );
        },
      ),
    );
  }
}

/// `.btn.primary.sq` with the 30 px house the mockup draws on it ([AppButton]'s square button draws 24 px).
class _GreenHomeButton extends StatelessWidget {
  const _GreenHomeButton({super.key, required this.semanticLabel, required this.onPressed});

  final String semanticLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticLabel,
    excludeSemantics: true,
    child: SizedBox(
      width: Dimens.actionButton,
      height: Dimens.actionButton,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.green,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: AppColors.green.withValues(alpha: 0.28), blurRadius: 16, offset: const Offset(0, 6)),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              Haptics.tap();
              onPressed();
            },
            child: const Center(child: Icon(AppIcons.house, size: 30, color: Colors.white)),
          ),
        ),
      ),
    ),
  );
}
