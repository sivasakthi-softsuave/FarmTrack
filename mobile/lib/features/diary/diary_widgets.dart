import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/big_buttons.dart';
import '../../core/widgets/design.dart';
import '../result/advice_widgets.dart';
import '../scan/crop_picture.dart';
import 'date_words.dart';
import 'diary_providers.dart';

/// A small label with a picture and words: never colour alone. (Still used by the alerts list.)
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.icon, required this.label, required this.color, required this.background});

  final IconData icon;
  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}

/// The pill of a warning level: picture and word ("Be careful" / "Serious").
class SeverityPill extends ConsumerWidget {
  const SeverityPill({super.key, required this.severity});

  final Severity severity;

  @override
  Widget build(BuildContext context, WidgetRef ref) => StatusPill(
    icon: severityIcon(severity),
    label: ref.watch(stringsProvider)('severity_${severity.wire}'),
    color: severity == Severity.red ? AppColors.red : AppColors.amberDark,
    background: AppColors.severitySoft(severity),
  );
}

// ----------------------------------------------------------------------------------------------------- list entries

/// A medicine as the server writes it, "Name (Brand)", split into the name and the brand; no brackets, no brand.
({String name, String brand}) splitMedicineName(String text) {
  final match = RegExp(r'^(.+?)\s*\(([^()]+)\)$').firstMatch(text.trim());
  if (match == null) return (name: text.trim(), brand: '');
  return (name: match.group(1)!.trim(), brand: match.group(2)!.trim());
}

/// `.dot` with a crop's picture: the crop's own picture when the app has one, else the picture of its group (tree for
/// fruit, leaf for vegetables, grass for cereals). Always blue (information).
class CropDot extends ConsumerWidget {
  const CropDot({super.key, required this.cropId, this.size = 44});

  /// The crop id in lower case (the app's names and pictures are keyed so).
  final String cropId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(resourcesProvider).cropGroup(cropId);
    final assets = ref.watch(cropImageAssetsProvider).value ?? const <String>{};
    final path = 'assets/crops/${cropId.toLowerCase()}.png';
    if (assets.contains(path)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(Dimens.radiusSmall),
        child: Image.asset(path, width: size, height: size, fit: BoxFit.cover),
      );
    }
    final icon = switch (group) {
      'vegetable' => AppIcons.leaf,
      'cereal' => AppIcons.grass,
      _ => AppIcons.tree,
    };
    return IconDot(
      icon,
      background: AppColors.blueSoft,
      foreground: AppColors.blue,
      size: size,
      iconSize: (size * 0.55).roundToDouble(),
    );
  }
}

/// A card with the chosen crop: its picture and its name (`.h-name`). [nameKey] marks the name for tests.
class CropCard extends ConsumerWidget {
  const CropCard({super.key, required this.cropId, this.nameKey});

  final String cropId;
  final Key? nameKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    final id = cropId.toLowerCase();
    return AppCard(
      child: Row(
        children: [
          CropDot(cropId: id),
          const SizedBox(width: 12),
          Expanded(
            child: Text(ref.watch(resourcesProvider).cropName(id, lang), key: nameKey, style: AppText.hName),
          ),
        ],
      ),
    );
  }
}

/// The warning of an entry inside its card: a soft amber row (a soft red one when it is serious) with its picture and
/// its words, 14 / 600 (the mockup's diary).
class DiaryWarningRow extends ConsumerWidget {
  const DiaryWarningRow({super.key, required this.warning});

  final WarningOut warning;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serious = warning.level == Severity.red;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: serious ? AppColors.redSoft : AppColors.amberSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            serious ? AppIcons.danger : AppIcons.warning,
            size: 20,
            color: serious ? AppColors.red : AppColors.amberDark,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              warning.text.forLang(ref.watch(languageProvider)),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.35, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// One entry of the diary list: the flask, the medicine and the brand and crop under it, then a grey "Waiting" pill or
/// the green tick of a saved entry, and the entry's warnings as rows inside the card.
class DiaryEntryCard extends ConsumerWidget {
  const DiaryEntryCard({super.key, required this.entry, required this.onTap});

  final DiaryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final lang = ref.watch(languageProvider);
    final words = ref.watch(dateWordsProvider);
    final now = ref.watch(clockProvider)();
    final medicine = splitMedicineName(entry.name.isEmpty ? t('diary_no_name') : entry.name);
    final crop = entry.cropId.isEmpty ? '' : ref.watch(resourcesProvider).cropName(entry.cropId.toLowerCase(), lang);
    final meta = [medicine.brand, crop].where((s) => s.isNotEmpty).join(' · ');
    final warnings = [
      for (final w in entry.warnings)
        if (!w.text.isEmpty) w,
    ];
    final relative = words.relative(entry.date, now);
    final date = relative == null ? words.written(entry.date) : '$relative, ${words.written(entry.date)}';
    // The card is one button: it reads the whole entry (the rows inside it are not buttons of their own), with the
    // word of each warning's level, as the picture and the colour of the row carry it for the eye.
    final spoken = [
      entry.name.isEmpty ? t('diary_no_name') : entry.name,
      if (crop.isNotEmpty) crop,
      date,
      if (entry.pending) t('diary_waiting_label'),
      for (final w in warnings)
        '${t(w.level == Severity.red ? 'severity_red' : 'severity_yellow')}: ${w.text.forLang(lang)}',
    ].join('. ');

    return AppCard(
      key: ValueKey('diary-entry-${entry.id}'),
      onTap: onTap,
      semanticLabel: spoken,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                const IconDot(AppIcons.medicine, background: AppColors.blueSoft, foreground: AppColors.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(medicine.name, style: AppText.hName),
                      if (meta.isNotEmpty) Text(meta, style: AppText.hMeta),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (entry.pending)
                  // Never wider than half the card: at the biggest text size the pill shrinks instead of squeezing the name.
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: constraints.maxWidth / 2),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: AppPill(
                        t('diary_waiting_short'),
                        background: AppColors.neutralSoft,
                        foreground: AppColors.inkSoft,
                        icon: AppIcons.clock,
                      ),
                    ),
                  )
                else
                  const IconDot(
                    AppIcons.tickBold,
                    background: AppColors.greenSoft,
                    foreground: AppColors.green,
                    size: 30,
                    round: true,
                    iconSize: 20,
                  ),
              ],
            ),
          ),
          for (final w in warnings) DiaryWarningRow(warning: w),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------------------------------------- saved entry

/// A warning of a saved entry: colour, picture and words together, with its own speaker button. A soft panel of its
/// colour with a thin line, like the advice's warnings.
class DiaryWarningCard extends ConsumerWidget {
  const DiaryWarningCard({super.key, required this.warning, required this.onSpeak});

  final WarningOut warning;
  final VoidCallback onSpeak;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final lang = ref.watch(languageProvider);
    final level = warning.level == Severity.red ? Severity.red : Severity.yellow;
    final accent = AppColors.severityAccent(level);
    final serious = level == Severity.red;
    return Container(
      key: ValueKey('warning-${warning.code}'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
      decoration: BoxDecoration(
        color: AppColors.severitySoft(level),
        borderRadius: BorderRadius.circular(Dimens.radius),
        border: Border.all(color: serious ? AppColors.redLine : AppColors.amberLine),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(severityIcon(level), size: 24, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('severity_${level.wire}'),
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.3, color: accent),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    warning.text.forLang(lang),
                    style: const TextStyle(fontSize: 15.5, height: 1.45, color: AppColors.ink),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          BigIconButton(
            key: ValueKey('warning-speak-${warning.code}'),
            icon: AppIcons.speaker,
            semanticLabel: t('diary_listen_warning'),
            color: AppColors.greenSoft,
            foreground: AppColors.green,
            size: Dimens.minTouch,
            onPressed: onSpeak,
          ),
        ],
      ),
    );
  }
}

/// A medicine of an advice: name, brand and dose, big enough to tap. Tapping says its name and dose. The chosen one is
/// soft green with a green line and a tick.
class MedicineCard extends ConsumerWidget {
  const MedicineCard({super.key, required this.product, required this.onTap, this.selected = false});

  final ProductOut product;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    final brand = product.brandExamples.take(2).join(' / ');
    final dose = product.doseText.forLang(lang);
    return Semantics(
      selected: selected,
      child: AppCard(
        key: ValueKey('diary-product-${product.productId}'),
        color: selected ? AppColors.greenSoft : AppColors.card,
        flat: selected,
        line: selected ? AppColors.green : null,
        onTap: onTap,
        child: Row(
          children: [
            const IconDot(AppIcons.medicine, background: AppColors.blueSoft, foreground: AppColors.blue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.activeIngredient.forLang(lang), style: AppText.hName),
                  if (brand.isNotEmpty) Text(brand, style: AppText.hMeta),
                  if (dose.isNotEmpty) Text(dose, style: AppText.hMeta.copyWith(color: AppColors.ink)),
                ],
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 12),
              const IconDot(
                AppIcons.tickBold,
                background: AppColors.green,
                foreground: Colors.white,
                size: 30,
                round: true,
                iconSize: 20,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------------------------------------------- day choice

/// Which day the farmer sprayed: today (the default), yesterday, or another day of the last two weeks.
enum DayChoice { today, yesterday, other }

/// The three day buttons as the mockup's segmented choices (`.seg`): 56 high, radius 14, a 2 px line; the chosen one has
/// a green line, a soft green fill and green words.
class DateChoiceRow extends ConsumerWidget {
  const DateChoiceRow({
    super.key,
    required this.choice,
    required this.otherDay,
    required this.onToday,
    required this.onYesterday,
    required this.onOther,
  });

  final DayChoice choice;

  /// The day picked with "other day", shown on that button once it is chosen.
  final DateTime? otherDay;
  final VoidCallback onToday;
  final VoidCallback onYesterday;
  final VoidCallback onOther;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final words = ref.watch(dateWordsProvider);
    final other = choice == DayChoice.other && otherDay != null ? words.written(otherDay!) : t('diary_other_day');
    final buttons = [
      _DayButton(
        key: const ValueKey('day-today'),
        icon: AppIcons.calendar,
        label: t('diary_today'),
        selected: choice == DayChoice.today,
        onTap: onToday,
      ),
      _DayButton(
        key: const ValueKey('day-yesterday'),
        icon: AppIcons.clock,
        label: t('diary_yesterday'),
        selected: choice == DayChoice.yesterday,
        onTap: onYesterday,
      ),
      _DayButton(
        key: const ValueKey('day-other'),
        icon: AppIcons.calendar,
        label: other,
        selected: choice == DayChoice.other,
        onTap: onOther,
      ),
    ];
    // At large text sizes three buttons side by side would squeeze the words: stack them.
    final stacked = MediaQuery.textScalerOf(context).scale(20) > 26;
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < buttons.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
              child: buttons[i],
            ),
        ],
      );
    }
    return Row(
      children: [
        for (var i = 0; i < buttons.length; i++) ...[if (i > 0) const SizedBox(width: 8), Expanded(child: buttons[i])],
      ],
    );
  }
}

class _DayButton extends StatelessWidget {
  const _DayButton({super.key, required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AppColors.green : AppColors.ink;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? AppColors.greenSoft : AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dimens.radiusSmall),
          side: BorderSide(color: selected ? AppColors.green : AppColors.line, width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Dimens.radiusSmall),
          onTap: () {
            Haptics.tap();
            onTap();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Dimens.minTouch),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 20, color: foreground),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        maxLines: 1,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: foreground),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The last fourteen days as big buttons, today first.
class DayChooser extends ConsumerWidget {
  const DayChooser({super.key, required this.onPick, this.days = 14});

  /// [daysBack] is 0 for today, 1 for yesterday, up to `days - 1`.
  final void Function(int daysBack) onPick;
  final int days;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = ref.watch(dateWordsProvider);
    final now = dayOnly(ref.watch(clockProvider)());
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (var back = 0; back < days; back++)
              SizedBox(
                width: width,
                child: Builder(
                  builder: (context) {
                    final day = DateTime(now.year, now.month, now.day - back);
                    final relative = words.relative(day, now) ?? words.weekday(day);
                    return AppCard(
                      key: ValueKey('day-option-$back'),
                      // Today is the soft green one, as a chosen segment is.
                      color: back == 0 ? AppColors.greenSoft : AppColors.card,
                      flat: back == 0,
                      line: back == 0 ? AppColors.green : null,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      onTap: () => onPick(back),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(words.written(day), style: AppText.hName),
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(relative, style: AppText.hMeta),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------------------------------------------------------- crops

/// Crop cards to tap (the screen pages them with arrows, six at a time): the crop's picture in a `.dot` and its name,
/// two cards to a row.
///
/// The server writes crop ids with a capital (`Apple`), the app's names and pictures are keyed in lower case: the
/// lookups here use the lower case id, while [onPick] gives the id as it was listed (the server accepts any case).
class CropGrid extends ConsumerWidget {
  const CropGrid({super.key, required this.cropIds, required this.onPick});

  final List<String> cropIds;
  final void Function(String cropId) onPick;

  /// Crops per page of the grid.
  static const perPage = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    final resources = ref.watch(resourcesProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final id in cropIds)
              SizedBox(
                width: width,
                child: AppCard(
                  key: ValueKey('crop-$id'),
                  semanticLabel: resources.cropName(id.toLowerCase(), lang),
                  padding: const EdgeInsets.all(14),
                  onTap: () => onPick(id),
                  child: Row(
                    children: [
                      CropDot(cropId: id.toLowerCase()),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(resources.cropName(id.toLowerCase(), lang), maxLines: 1, style: AppText.hName),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
