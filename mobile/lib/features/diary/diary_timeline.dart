import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/voice/utterance.dart';
import '../../core/widgets/big_buttons.dart';
import '../../core/widgets/design.dart';
import 'date_words.dart';
import 'diary_providers.dart';
import 'diary_widgets.dart';

/// The parts of the diary page of the owner's choice (30 Oct 2026, design 2 of `docs/design/diary-combined-proposals.html`): the crop
/// circles (All, Apple, Tomato), a strip of this week with a button for the month, and the timeline with a thread, a big circle for
/// each day and a card for each spray.

/// The thread of the timeline.
const _thread = Color(0xFFD5DDD3);

/// The crops of the entries as lower case ids, the one sprayed last first (the entries are newest first).
List<String> diaryCrops(List<DiaryEntry> entries) {
  final seen = <String>{};
  return [
    for (final e in entries)
      if (e.cropId.isNotEmpty && seen.add(e.cropId.toLowerCase())) e.cropId.toLowerCase(),
  ];
}

/// How many entries each day has (the keys are days without a time).
Map<DateTime, int> diarySprayCounts(List<DiaryEntry> entries) {
  final counts = <DateTime, int>{};
  for (final e in entries) {
    counts.update(dayOnly(e.date), (n) => n + 1, ifAbsent: () => 1);
  }
  return counts;
}

String _dayKey(DateTime day) => '${day.year}-${day.month}-${day.day}';

/// One to three small dots for the sprays of a day (more than three still show three).
class _Dots extends StatelessWidget {
  const _Dots(this.count, {super.key, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 5,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < math.min(count, 3); i++) ...[
          if (i > 0) const SizedBox(width: 3),
          DecoratedBox(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: const SizedBox(width: 5, height: 5),
          ),
        ],
      ],
    ),
  );
}

// ------------------------------------------------------------------------------------------------------ crop circles

/// "All" and a round picture for every crop in the diary; the chosen one has a green ring. A touch chooses it (the diary then shows
/// only that crop). [selected] is a lower case crop id, or null for all.
class DiaryCropRow extends ConsumerWidget {
  const DiaryCropRow({super.key, required this.crops, required this.selected, required this.onSelect});

  final List<String> crops;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final lang = ref.watch(languageProvider);
    final resources = ref.watch(resourcesProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CropChoice(
            key: const ValueKey('diary-crop-all'),
            label: t('diary_all_crops'),
            selected: selected == null,
            onTap: () => onSelect(null),
            picture: const IconDot(
              Icons.grid_view_rounded,
              background: AppColors.greenSoft,
              foreground: AppColors.green,
              size: 56,
              round: true,
              iconSize: 28,
            ),
          ),
          for (final id in crops)
            _CropChoice(
              key: ValueKey('diary-crop-$id'),
              label: resources.cropName(id, lang),
              selected: selected == id,
              onTap: () => onSelect(id),
              picture: CropDot(cropId: id, size: 56, round: true),
            ),
        ],
      ),
    );
  }
}

class _CropChoice extends StatelessWidget {
  const _CropChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.picture,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget picture;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    excludeSemantics: true,
    child: SizedBox(
      width: 82,
      child: InkWell(
        borderRadius: BorderRadius.circular(Dimens.radiusSmall),
        onTap: () {
          Haptics.tap();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: selected ? AppColors.green : Colors.transparent, width: 3),
                  boxShadow: selected ? const [BoxShadow(color: AppColors.greenSoft, spreadRadius: 3)] : null,
                ),
                child: picture,
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected ? AppColors.ink : AppColors.inkSoft,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ------------------------------------------------------------------------------------------------------- this week

/// "This week": the last seven days, a dot for every spray, today in solid green; the whole card is a button that opens the month.
class DiaryWeekCard extends ConsumerWidget {
  const DiaryWeekCard({super.key, required this.counts, required this.onOpen});

  final Map<DateTime, int> counts;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final words = ref.watch(dateWordsProvider);
    final today = dayOnly(ref.watch(clockProvider)());
    final days = [for (var back = 6; back >= 0; back--) DateTime(today.year, today.month, today.day - back)];
    return AppCard(
      key: const ValueKey('diary-week'),
      padding: const EdgeInsets.all(12),
      onTap: onOpen,
      semanticLabel: '${t('diary_week_title')}. ${t('diary_month_open')}',
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 0, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t('diary_week_title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, height: 1.3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _MonthPill(label: t('diary_month_button')),
                ],
              ),
            ),
            Row(
              children: [
                for (final day in days)
                  Expanded(
                    child: _WeekDay(
                      key: ValueKey('diary-week-day-${day.day}'),
                      weekday: words.shortWeekday(day),
                      day: day.day,
                      count: counts[day] ?? 0,
                      today: day == today,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthPill extends StatelessWidget {
  const _MonthPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: AppColors.neutralSoft, borderRadius: BorderRadius.circular(17)),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(11, 6, 7, 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(AppIcons.calendar, size: 18, color: AppColors.ink),
          const SizedBox(width: 6),
          Text(label, maxLines: 1, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(width: 2),
          const Icon(AppIcons.down, size: 18, color: AppColors.ink),
        ],
      ),
    ),
  );
}

class _WeekDay extends StatelessWidget {
  const _WeekDay({super.key, required this.weekday, required this.day, required this.count, required this.today});

  final String weekday;
  final int day;
  final int count;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final has = count > 0;
    final fill = today ? AppColors.green : (has ? AppColors.greenSoft : Colors.transparent);
    final ink = today ? Colors.white : (has ? AppColors.green : AppColors.ink);
    return Container(
      height: 60,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        boxShadow: today
            ? [BoxShadow(color: AppColors.green.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3))]
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              weekday,
              maxLines: 1,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: today ? Colors.white70 : AppColors.inkSoft,
              ),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$day',
              maxLines: 1,
              style: TextStyle(fontSize: 16, fontWeight: has || today ? FontWeight.w800 : FontWeight.w700, color: ink),
            ),
          ),
          const SizedBox(height: 2),
          _Dots(count, key: ValueKey('diary-week-dots-$day'), color: today ? Colors.white : AppColors.green),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------------------------------------------- the month

/// Opens the month calendar on a sheet from the bottom: the month of today first, earlier months with the arrows.
Future<void> showDiaryMonthSheet(BuildContext context, {required List<DiaryEntry> entries, required Object owner}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => DiaryMonthSheet(entries: entries, owner: owner),
    );

/// The month calendar: a dot for each spray, the counters of the month, the speaker that says them (in words), and "Done".
class DiaryMonthSheet extends ConsumerStatefulWidget {
  const DiaryMonthSheet({super.key, required this.entries, required this.owner});

  final List<DiaryEntry> entries;

  /// The voice owner of the page below, so that the speech stops with it.
  final Object owner;

  @override
  ConsumerState<DiaryMonthSheet> createState() => _DiaryMonthSheetState();
}

class _DiaryMonthSheetState extends ConsumerState<DiaryMonthSheet> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = ref.read(clockProvider)();
    _month = DateTime(now.year, now.month);
  }

  List<DiaryEntry> get _inMonth {
    final end = DateTime(_month.year, _month.month + 1);
    return [
      for (final e in widget.entries)
        if (!dayOnly(e.date).isBefore(_month) && dayOnly(e.date).isBefore(end)) e,
    ];
  }

  void _say() {
    final t = ref.read(stringsProvider);
    final words = ref.read(dateWordsProvider);
    final count = _inMonth.length;
    final args = <String, Object>{'month': words.month(_month.month)};
    final text = switch (count) {
      0 => t('diary_month_say_none', args: args),
      1 => t('diary_month_say_one', args: args),
      <= 31 => t('diary_month_say', args: {...args, 'n': words.number(count)}),
      _ => t('diary_month_say_many', args: args),
    };
    ref.read(voiceServiceProvider).speak([TextUtterance(text, lang: ref.read(languageProvider))], owner: widget.owner);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final words = ref.watch(dateWordsProvider);
    final now = ref.watch(clockProvider)();
    final today = dayOnly(now);
    final currentMonth = DateTime(today.year, today.month);
    final counts = diarySprayCounts(widget.entries);
    var earliest = currentMonth;
    for (final e in widget.entries) {
      final d = dayOnly(e.date);
      final m = DateTime(d.year, d.month);
      if (m.isBefore(earliest)) earliest = m;
    }
    final inMonth = _inMonth;
    final crops = {for (final e in inMonth) e.cropId.toLowerCase()}..remove('');
    final lastDay = widget.entries.isEmpty ? null : dayOnly(widget.entries.first.date);
    final lastWhen = lastDay == null ? null : (words.relative(lastDay, now) ?? words.written(lastDay));
    final canGoBack = _month.isAfter(earliest);
    final canGoOn = _month.isBefore(currentMonth);
    final lead = _month.weekday - 1;
    final length = DateTime(_month.year, _month.month + 1, 0).day;
    final rows = ((lead + length) / 7).ceil();

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Padding(
          key: const ValueKey('diary-month-sheet'),
          padding: const EdgeInsets.fromLTRB(Dimens.gutter, 0, Dimens.gutter, Dimens.gutter),
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.5,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          '${words.month(_month.month)} ${_month.year}',
                          key: const ValueKey('diary-month-title'),
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.3),
                        ),
                      ),
                    ),
                    _ArrowButton(
                      key: const ValueKey('diary-month-prev'),
                      icon: AppIcons.back,
                      label: t('diary_month_prev'),
                      onTap: canGoBack ? () => setState(() => _month = DateTime(_month.year, _month.month - 1)) : null,
                    ),
                    _ArrowButton(
                      key: const ValueKey('diary-month-next'),
                      icon: AppIcons.chevron,
                      label: t('diary_month_next'),
                      onTap: canGoOn ? () => setState(() => _month = DateTime(_month.year, _month.month + 1)) : null,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (inMonth.isEmpty)
                      DiaryChip(
                        key: const ValueKey('diary-month-stat-none'),
                        icon: AppIcons.calendar,
                        text: t('diary_month_none'),
                        background: AppColors.neutralSoft,
                        foreground: AppColors.inkSoft,
                      )
                    else ...[
                      DiaryChip(
                        key: const ValueKey('diary-month-stat-sprays'),
                        icon: AppIcons.tick,
                        text: t('diary_month_sprays', args: {'n': inMonth.length}),
                        background: AppColors.greenSoft,
                        foreground: AppColors.green,
                      ),
                      DiaryChip(
                        key: const ValueKey('diary-month-stat-crops'),
                        icon: AppIcons.field,
                        text: t('diary_month_crops', args: {'n': crops.length}),
                      ),
                    ],
                    if (lastWhen != null)
                      DiaryChip(
                        key: const ValueKey('diary-month-stat-last'),
                        icon: AppIcons.clock,
                        text: t('diary_month_last', args: {'when': lastWhen}),
                        background: AppColors.neutralSoft,
                        foreground: AppColors.inkSoft,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                DecoratedBox(
                  decoration: AppDecor.card(),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            for (var i = 0; i < 7; i++)
                              Expanded(
                                child: Center(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      words.shortWeekday(DateTime(2024, 1, 1 + i)),
                                      maxLines: 1,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.inkSoft,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        for (var r = 0; r < rows; r++)
                          Row(
                            children: [
                              for (var c = 0; c < 7; c++)
                                Expanded(
                                  child: Builder(
                                    builder: (context) {
                                      final n = r * 7 + c - lead + 1;
                                      if (n < 1 || n > length) return const SizedBox(height: 46);
                                      final day = DateTime(_month.year, _month.month, n);
                                      return _MonthDay(
                                        key: ValueKey('diary-month-day-${_dayKey(day)}'),
                                        day: n,
                                        count: counts[day] ?? 0,
                                        today: day == today,
                                        future: day.isAfter(today),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    BigIconButton(
                      key: const ValueKey('diary-month-speak'),
                      icon: AppIcons.speaker,
                      semanticLabel: t('field_listen_card'),
                      color: AppColors.greenSoft,
                      foreground: AppColors.green,
                      size: Dimens.minTouch,
                      onPressed: _say,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppButton(
                        key: const ValueKey('diary-month-done'),
                        label: t('diary_done_label'),
                        semanticLabel: t('diary_done_label'),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled
            ? () {
                Haptics.tap();
                onTap!();
              }
            : null,
        child: SizedBox(
          width: Dimens.minTouch,
          height: Dimens.minTouch,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: enabled ? AppColors.neutralSoft : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(icon, size: 22, color: enabled ? AppColors.ink : AppColors.dashed),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthDay extends StatelessWidget {
  const _MonthDay({super.key, required this.day, required this.count, required this.today, required this.future});

  final int day;
  final int count;
  final bool today;
  final bool future;

  @override
  Widget build(BuildContext context) {
    final has = count > 0;
    final fill = today ? AppColors.green : (has ? AppColors.greenSoft : Colors.transparent);
    final ink = today ? Colors.white : (has ? AppColors.green : (future ? AppColors.dashed : AppColors.ink));
    return Container(
      height: 46,
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(12),
        boxShadow: today
            ? [BoxShadow(color: AppColors.green.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3))]
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$day',
              maxLines: 1,
              style: TextStyle(fontSize: 15, fontWeight: has || today ? FontWeight.w800 : FontWeight.w600, color: ink),
            ),
          ),
          const SizedBox(height: 2),
          _Dots(count, key: ValueKey('diary-month-dots-$day'), color: today ? Colors.white : AppColors.green),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------------------------------------------- the timeline

/// The entries, newest day first, along a thread: a big circle for each day (today's is solid green) and under its words (the
/// day, "Today", "Yesterday") a card for each spray.
class DiaryTimeline extends ConsumerWidget {
  const DiaryTimeline({super.key, required this.entries, required this.onSpeak});

  /// Newest first.
  final List<DiaryEntry> entries;
  final void Function(DiaryEntry entry) onSpeak;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = <DateTime, List<DiaryEntry>>{};
    for (final e in entries) {
      days.putIfAbsent(dayOnly(e.date), () => []).add(e);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final MapEntry(key: day, value: list) in days.entries)
          _DayBlock(day: day, entries: list, onSpeak: onSpeak),
      ],
    );
  }
}

class _DayBlock extends ConsumerWidget {
  const _DayBlock({required this.day, required this.entries, required this.onSpeak});

  final DateTime day;
  final List<DiaryEntry> entries;
  final void Function(DiaryEntry entry) onSpeak;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = ref.watch(dateWordsProvider);
    final now = ref.watch(clockProvider)();
    final relative = words.relative(day, now);
    final headline = relative ?? words.weekday(day);
    final rest = relative != null ? words.weekday(day) : words.written(day);
    final isToday = daysAgo(day, now) == 0;
    return Stack(
      key: ValueKey('diary-day-${_dayKey(day)}'),
      children: [
        // The thread runs from the middle of the day's circle to the bottom of the block (and so into the next block).
        const Positioned(left: 20.5, top: 22, bottom: 0, width: 3, child: ColoredBox(color: _thread)),
        Positioned(
          left: 0,
          top: 0,
          child: ExcludeSemantics(
            child: Container(
              key: ValueKey('diary-node-${_dayKey(day)}'),
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isToday ? AppColors.green : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.green, width: 2.5),
                // A ring in the colour of the page, so that the thread does not run into the circle.
                boxShadow: const [BoxShadow(color: AppColors.paper, spreadRadius: 5)],
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${day.day}',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: isToday ? Colors.white : AppColors.green,
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 58, bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Text(headline, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, height: 1.3)),
                      Text(
                        rest,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.inkSoft,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: DiaryEntryCard(entry: entry, onSpeak: () => onSpeak(entry)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
