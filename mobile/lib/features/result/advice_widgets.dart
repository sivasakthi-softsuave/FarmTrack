import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/design.dart';

IconData severityIcon(Severity s) => switch (s) {
  Severity.green => AppIcons.tick,
  Severity.yellow => AppIcons.warning,
  Severity.red => AppIcons.danger,
};

/// The amber card of the mockup (`Advice`) writes its text in this warm dark brown (inline style, not a token).
const adviceAmberText = Color(0xFF3B3320);

/// `.pill` of the result screens: a rounded tag that grows with the text size (the shared [AppPill] has a fixed height,
/// which a big text setting would overflow).
class ResultPill extends StatelessWidget {
  const ResultPill(
    this.text, {
    super.key,
    required this.background,
    required this.foreground,
    this.icon,
    this.height = 30,
    this.horizontal = 12,
  });

  final String text;
  final Color background;
  final Color foreground;
  final IconData? icon;
  final double height;
  final double horizontal;

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(minHeight: height),
    padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: 2),
    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 20, color: foreground), const SizedBox(width: 6)],
        Flexible(
          child: Text(text, style: AppText.pill.copyWith(color: foreground)),
        ),
      ],
    ),
  );
}

/// The card at the top of an advice: colour and picture carry the urgency before any word is read. A flat card of the
/// severity's soft colour with a thin line, the picture in a full-colour 60 px circle, the severity word as a white
/// tag above the disease name, and the description under both.
class SeverityBand extends ConsumerWidget {
  const SeverityBand({
    super.key,
    required this.severity,
    required this.headline,
    this.description = '',
    this.cropName = '',
  });

  final Severity severity;
  final String headline;

  /// The advice's own short explanation (the mockup's 15 px text in the card).
  final String description;

  /// The crop the advice is for, as a second tag, so a wrong crop is noticed.
  final String cropName;

  /// The thin line of the card: amber and red have tokens, green is its own colour made light.
  static Color _line(Severity s) => switch (s) {
    Severity.green => AppColors.green.withValues(alpha: 0.3),
    Severity.yellow => AppColors.amberLine,
    Severity.red => AppColors.redLine,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final accent = AppColors.severityAccent(severity);
    return AppCard(
      key: ValueKey('severity-${severity.wire}'),
      color: AppColors.severitySoft(severity),
      flat: true,
      line: _line(severity),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconDot(
                severityIcon(severity),
                background: AppColors.severity(severity),
                foreground: AppColors.onSeverity(severity),
                size: 60,
                round: true,
                iconSize: 30,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        ResultPill(
                          t('severity_${severity.wire}'),
                          background: AppColors.card,
                          foreground: accent,
                          height: 26,
                          horizontal: 10,
                        ),
                        if (cropName.isNotEmpty)
                          ResultPill(
                            cropName,
                            key: const ValueKey('advice-crop'),
                            background: AppColors.card,
                            foreground: AppColors.inkSoft,
                            height: 26,
                            horizontal: 10,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(headline, key: const ValueKey('advice-headline'), style: AppText.big),
                  ],
                ),
              ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              description,
              key: const ValueKey('advice-summary'),
              style: AppText.body.copyWith(color: severity == Severity.yellow ? adviceAmberText : AppColors.ink),
            ),
          ],
        ],
      ),
    );
  }
}

/// One warning: amber-dark picture on a white card, or (serious) a red picture on a flat red-soft card. [nested] is for a
/// warning inside another card (a medicine): a flat tinted card, because a white card with a shadow would sit on white.
class WarningTile extends StatelessWidget {
  const WarningTile({super.key, required this.level, required this.text, this.nested = false});

  final Severity level;
  final String text;
  final bool nested;

  @override
  Widget build(BuildContext context) {
    final serious = level == Severity.red;
    final color = serious ? AppColors.red : AppColors.amberDark;
    return AppCard(
      color: serious ? AppColors.redSoft : (nested ? AppColors.amberSoft : AppColors.card),
      flat: serious || nested,
      line: nested ? (serious ? AppColors.redLine : AppColors.amberLine) : null,
      radius: nested ? Dimens.radiusSmall : Dimens.radius,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(serious ? AppIcons.danger : AppIcons.warning, size: 24, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: AppText.body.copyWith(fontSize: 15.5))),
        ],
      ),
    );
  }
}

/// A picture, then a sentence that wraps beside it (the dose and the waiting period of a medicine).
class _IconLine extends StatelessWidget {
  const _IconLine({required this.icon, required this.text, required this.color, required this.style, this.top = 0});

  final IconData icon;
  final String text;
  final Color color;
  final TextStyle style;

  /// Nudges the picture down so it sits on the first line of text (the mockup's `margin-top`).
  final double top;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: EdgeInsets.only(top: top),
        child: Icon(icon, size: 24, color: color),
      ),
      const SizedBox(width: 12),
      Expanded(child: Text(text, style: style)),
    ],
  );
}

/// One approved medicine: the active ingredient, a brand example, the dose as a sentence and the waiting period.
class ProductCard extends ConsumerWidget {
  const ProductCard({super.key, required this.product});

  final ProductOut product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final lang = ref.watch(languageProvider);
    final brand = [
      product.brandExamples.take(2).join(' / '),
      ?product.formulation,
    ].where((s) => s.isNotEmpty).join(' · ');
    final dose = product.doseText.forLang(lang);
    final waiting = product.waitingPeriodDays;
    return AppCard(
      key: ValueKey('product-${product.productId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconDot(
                AppIcons.medicine,
                background: AppColors.blueSoft,
                foreground: AppColors.blue,
                size: 52,
                round: true,
                iconSize: 30,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.activeIngredient.forLang(lang),
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.3),
                    ),
                    if (brand.isNotEmpty) Text(brand, style: AppText.hMeta),
                  ],
                ),
              ),
            ],
          ),
          Container(height: 1, color: AppColors.line, margin: const EdgeInsets.symmetric(vertical: 14)),
          _IconLine(
            icon: AppIcons.drop,
            text: dose.isNotEmpty
                ? dose
                : [if (product.doseMin != null) '${product.doseMin}', ?product.doseUnit].join(' '),
            color: AppColors.blue,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.4),
            top: 2,
          ),
          if (waiting != null) ...[
            const SizedBox(height: 10),
            _IconLine(
              icon: AppIcons.clock,
              text: t('advice_wait_days', args: {'n': waiting}),
              color: AppColors.inkSoft,
              style: const TextStyle(fontSize: 16, height: 1.4),
              top: 1,
            ),
          ],
          for (final w in product.warnings) ...[
            const SizedBox(height: 10),
            WarningTile(level: w.level, text: w.text.forLang(lang), nested: true),
          ],
        ],
      ),
    );
  }
}

/// "When": one tinted card whose colour says what to do. Green = spray now, grey = wait, blue = information (spray
/// again later, no spray needed).
class TimingCard extends StatelessWidget {
  const TimingCard({super.key, required this.action, required this.text});

  final TimingAction action;
  final String text;

  @override
  Widget build(BuildContext context) {
    final (fill, dot, icon) = switch (action) {
      TimingAction.sprayNow => (AppColors.greenSoft, AppColors.green, AppIcons.tickBold),
      TimingAction.wait => (AppColors.neutralSoft, AppColors.inkSoft, AppIcons.hourglass),
      TimingAction.repeatWithinDays => (AppColors.blueSoft, AppColors.blue, AppIcons.roundArrow),
      TimingAction.notNeeded => (AppColors.blueSoft, AppColors.blue, AppIcons.info),
      TimingAction.unknown => (AppColors.neutralSoft, AppColors.inkSoft, AppIcons.clock),
    };
    return AppCard(
      color: fill,
      flat: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconDot(icon, background: dot, foreground: Colors.white, size: 36, round: true, iconSize: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.45)),
          ),
        ],
      ),
    );
  }
}

/// Everything of an advice except the actions. First view: severity card, medicines, timing and warnings (what to buy
/// and do). The safety notes and steps are behind one "More" button, so the first view stays short.
class AdviceCards extends ConsumerStatefulWidget {
  const AdviceCards({super.key, required this.advice, this.cropName = ''});

  final AdviceOut advice;

  /// Shown as a tag on the severity card (empty: no tag).
  final String cropName;

  @override
  ConsumerState<AdviceCards> createState() => _AdviceCardsState();
}

class _AdviceCardsState extends ConsumerState<AdviceCards> {
  bool _more = false;

  @override
  Widget build(BuildContext context) {
    final advice = widget.advice;
    final lang = ref.watch(languageProvider);
    final t = ref.watch(stringsProvider);
    final timing = advice.timing;
    final hasMore = advice.safety.isNotEmpty || advice.steps.isNotEmpty;

    // The mockup's `.pad`: 12 between cards; a label sits 6 further from the card above and 2 closer to its own cards.
    final items = <Widget>[];
    var afterLabel = false;
    void add(Widget w) {
      if (items.isNotEmpty) items.add(SizedBox(height: afterLabel ? 10 : 12));
      items.add(w);
      afterLabel = false;
    }

    void label(String text) {
      add(SectionLabel(text, hindi: isDevanagari(text)));
      afterLabel = true;
    }

    add(
      SeverityBand(
        severity: advice.severity,
        headline: advice.headline.forLang(lang),
        description: advice.summary.forLang(lang),
        cropName: widget.cropName,
      ),
    );
    if (advice.products.isNotEmpty) label(t('advice_medicine'));
    for (final p in advice.products) {
      add(ProductCard(product: p));
    }
    if (timing != null && !timing.text.isEmpty) {
      label(t('advice_when'));
      add(TimingCard(key: const ValueKey('advice-timing'), action: timing.action, text: timing.text.forLang(lang)));
    }
    if (advice.warnings.isNotEmpty) label(t('advice_warning'));
    for (final w in advice.warnings) {
      add(WarningTile(level: w.level, text: w.text.forLang(lang)));
    }
    if (hasMore) add(_MoreButton(open: _more, onTap: () => setState(() => _more = !_more)));
    if (_more) {
      for (final s in advice.safety) {
        add(WarningTile(level: Severity.yellow, text: s.forLang(lang)));
      }
      if (advice.steps.isNotEmpty) {
        label(t('advice_steps'));
        for (var i = 0; i < advice.steps.length; i++) {
          add(_StepCard(number: i + 1, text: advice.steps[i].forLang(lang)));
        }
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: items);
  }
}

/// One step of "What to do": a green numbered circle and the sentence.
class _StepCard extends StatelessWidget {
  const _StepCard({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle),
          child: Text(
            '$number',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(text, style: AppText.body.copyWith(fontSize: 15.5)),
          ),
        ),
      ],
    ),
  );
}

/// "More" / "Less": opens and closes the details of an advice. The mockup's blue outline button (52 high, 16 / 700 word
/// then an arrow); the tap area is 56 high around it. [AppButton] puts the picture before the word, so it is drawn here.
class _MoreButton extends ConsumerWidget {
  const _MoreButton({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final label = t(open ? 'less_label' : 'more_label');
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: SizedBox(
        key: const ValueKey('advice-more'),
        height: Dimens.minTouch,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            onTap: () {
              Haptics.tap();
              onTap();
            },
            child: Center(
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.line, width: 2),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          label,
                          maxLines: 1,
                          style: AppText.button.copyWith(fontSize: 16, color: AppColors.blue),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(open ? AppIcons.up : AppIcons.down, size: 24, color: AppColors.blue),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The state of "I sprayed" once the farmer has answered, in the shape of the green button it replaces but flat (it is not
/// a button): green with a bold tick (written in the diary) or grey with a clock (saved on the phone, waiting for the
/// internet). Never yellow.
class SprayStatusChip extends StatelessWidget {
  const SprayStatusChip({super.key, required this.waiting, required this.label});

  final bool waiting;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = waiting ? AppColors.inkSoft : AppColors.green;
    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      child: Container(
        key: ValueKey(waiting ? 'sprayed-waiting' : 'sprayed-done'),
        height: Dimens.actionButton,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
        // It sits beside another button: the word shrinks rather than overflow.
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(waiting ? AppIcons.clock : AppIcons.tickBold, size: 30, color: Colors.white),
            const SizedBox(width: 10),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label, maxLines: 1, style: AppText.button.copyWith(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
