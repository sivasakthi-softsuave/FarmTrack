import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';

IconData severityIcon(Severity s) => switch (s) {
  Severity.green => AppIcons.tick,
  Severity.yellow => AppIcons.warning,
  Severity.red => AppIcons.danger,
};

/// The panel at the top of an advice: colour and picture carry the urgency before any word is read. A soft panel of the
/// severity colour, the picture in a full-colour circle, the severity word as a small tag and the disease name large.
class SeverityBand extends ConsumerWidget {
  const SeverityBand({super.key, required this.severity, required this.headline});

  final Severity severity;
  final String headline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final theme = Theme.of(context).textTheme;
    final accent = AppColors.severityAccent(severity);
    return Container(
      key: ValueKey('severity-${severity.wire}'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: AppDecor.panel(AppColors.severitySoft(severity), accent),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(color: AppColors.severity(severity), shape: BoxShape.circle),
            child: Icon(severityIcon(severity), size: 34, color: AppColors.onSeverity(severity)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(999)),
                  child: Text(
                    t('severity_${severity.wire}'),
                    style: theme.labelLarge?.copyWith(fontSize: 14, color: accent),
                  ),
                ),
                const SizedBox(height: 4),
                Text(headline, key: const ValueKey('advice-headline'), style: theme.headlineMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WarningTile extends StatelessWidget {
  const WarningTile({super.key, required this.level, required this.text});

  final Severity level;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = level == Severity.red ? AppColors.red : AppColors.amberDark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: AppDecor.panel(
        AppColors.severitySoft(level == Severity.red ? Severity.red : Severity.yellow),
        color,
        radius: 16,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(level == Severity.red ? AppIcons.danger : AppIcons.warning, size: 30, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
        ],
      ),
    );
  }
}

class _IconLine extends StatelessWidget {
  const _IconLine({required this.icon, required this.text, this.bold = false, this.color = AppColors.inkSoft});

  final IconData icon;
  final String text;
  final bool bold;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 28, color: color),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: bold ? FontWeight.w700 : FontWeight.w400),
        ),
      ),
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
    return Container(
      key: ValueKey('product-${product.productId}'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppDecor.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(color: AppColors.blueSoft, shape: BoxShape.circle),
                child: const Icon(AppIcons.medicine, size: 30, color: AppColors.blue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.activeIngredient.forLang(lang), style: Theme.of(context).textTheme.titleLarge),
                    if (brand.isNotEmpty)
                      Text(brand, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft)),
                  ],
                ),
              ),
            ],
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
          _IconLine(
            icon: Icons.water_drop_rounded,
            text: dose.isNotEmpty
                ? dose
                : [if (product.doseMin != null) '${product.doseMin}', ?product.doseUnit].join(' '),
            bold: true,
            color: AppColors.blue,
          ),
          if (waiting != null) ...[
            const SizedBox(height: 10),
            _IconLine(
              icon: AppIcons.clock,
              text: t('advice_wait_days', args: {'n': waiting}),
            ),
          ],
          for (final w in product.warnings) ...[
            const SizedBox(height: 10),
            WarningTile(level: w.level, text: w.text.forLang(lang)),
          ],
        ],
      ),
    );
  }
}

IconData timingIcon(TimingAction a) => switch (a) {
  TimingAction.sprayNow => AppIcons.tick,
  TimingAction.wait => Icons.hourglass_top_rounded,
  TimingAction.repeatWithinDays => AppIcons.roundArrow,
  TimingAction.notNeeded => AppIcons.cross,
  TimingAction.unknown => AppIcons.clock,
};

/// Everything of an advice except the actions. First view: severity band, medicines, timing and warnings (what to buy
/// and do). The explanation, safety notes and steps are behind one "More" button, so the first view stays short.
class AdviceCards extends ConsumerStatefulWidget {
  const AdviceCards({super.key, required this.advice});

  final AdviceOut advice;

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
    final summary = advice.summary.forLang(lang);
    final hasMore = summary.isNotEmpty || advice.safety.isNotEmpty || advice.steps.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SeverityBand(severity: advice.severity, headline: advice.headline.forLang(lang)),
        if (advice.products.isNotEmpty) _SectionLabel(t('advice_medicine')),
        for (final p in advice.products) ...[ProductCard(product: p), const SizedBox(height: 10)],
        if (timing != null && !timing.text.isEmpty) ...[
          _SectionLabel(t('advice_when')),
          Container(
            key: const ValueKey('advice-timing'),
            padding: const EdgeInsets.all(14),
            decoration: AppDecor.panel(AppColors.greenSoft, AppColors.green, radius: 16),
            child: _IconLine(
              icon: timingIcon(timing.action),
              text: timing.text.forLang(lang),
              bold: true,
              color: AppColors.green,
            ),
          ),
        ],
        if (advice.warnings.isNotEmpty) _SectionLabel(t('advice_warning')),
        for (final w in advice.warnings) ...[
          WarningTile(level: w.level, text: w.text.forLang(lang)),
          const SizedBox(height: 10),
        ],
        if (hasMore) ...[
          const SizedBox(height: 6),
          _MoreButton(open: _more, onTap: () => setState(() => _more = !_more)),
        ],
        if (_more) ...[
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(summary, key: const ValueKey('advice-summary'), style: Theme.of(context).textTheme.bodyLarge),
          ],
          for (final s in advice.safety) ...[
            const SizedBox(height: 12),
            WarningTile(level: Severity.yellow, text: s.forLang(lang)),
          ],
          if (advice.steps.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(t('advice_steps'), style: Theme.of(context).textTheme.titleLarge),
            for (var i = 0; i < advice.steps.length; i++) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(advice.steps[i].forLang(lang), style: Theme.of(context).textTheme.bodyLarge)),
                ],
              ),
            ],
          ],
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

/// "More" / "Less": opens and closes the details of an advice. A blue button with an arrow and one word.
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
      child: Material(
        key: const ValueKey('advice-more'),
        color: AppColors.card,
        shape: AppDecor.shape(const BorderSide(color: AppColors.line, width: 2), radius: 18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Dimens.minTouch),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 36, color: AppColors.blue),
                const SizedBox(width: 8),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.blue)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The state of "I sprayed" once the farmer has answered: a green pill with a tick (written in the diary) or a grey pill
/// with a clock (saved on the phone, waiting for the internet). Not a button. Never yellow.
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
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(32)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(waiting ? AppIcons.clock : AppIcons.tick, size: 32, color: Colors.white),
            const SizedBox(width: 10),
            Text(label, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

/// A small grey heading above a group of advice cards ("Medicine", "When", "Careful").
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.inkSoft)),
  );
}
