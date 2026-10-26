import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/design.dart';
import '../diary/date_words.dart';
import '../field/field_words.dart';

/// The picture of an alert: the rain cloud for the rain alerts (`rain_washoff`), else the picture of its level (tick,
/// warning triangle, danger sign).
IconData alertPicture(AlertOut alert) => alert.kind.contains('rain') ? AppIcons.rain : severityPicture(alert.level);

/// The mockup's alert time: "Today, 07:30", "Yesterday", or the date ("12 May").
String alertWhen(DateWords words, DateTime created, DateTime now) {
  final local = created.toLocal();
  return switch (daysAgo(created, now)) {
    0 => '${words.today}, ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}',
    1 => words.yesterday,
    _ => words.written(created),
  };
}

/// An unread red alert is the urgent one: it also has a "Listen" button on the list (the mockup's first card).
bool alertIsUrgent(AlertOut alert) => !alert.isRead && alert.level == Severity.red;

/// One alert in the list, as the mockup draws it: a white card, a round dot (red with a white picture when it is urgent,
/// amber with a dark one for "be careful", soft green with a green one for "done"), the title with a blue "New" tag when
/// it is unread, the message, and the time in grey. A done alert ("Result ready") ends in an arrow; a read alert is a
/// little paler. The level's word is in the semantics, the picture and colour carry it on screen.
class AlertCard extends ConsumerWidget {
  const AlertCard({super.key, required this.alert, required this.onTap, this.onListen});

  final AlertOut alert;
  final VoidCallback onTap;

  /// Says the alert aloud. The "Listen" button shows only on an urgent alert ([alertIsUrgent]).
  final VoidCallback? onListen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    final t = ref.watch(stringsProvider);
    final words = ref.watch(dateWordsProvider);
    final now = ref.watch(clockProvider)();
    final unread = !alert.isRead;
    final level = alert.level;
    final body = alert.body.forLang(lang);
    final created = alert.createdAt;
    final when = created == null ? '' : alertWhen(words, created, now);
    final listen = onListen != null && alertIsUrgent(alert);
    final (fill, picture) = switch (level) {
      Severity.red => (AppColors.red, Colors.white),
      Severity.yellow => (AppColors.amber, AppColors.ink),
      Severity.green => (AppColors.greenSoft, AppColors.green),
    };

    final card = AppCard(
      key: ValueKey('alert-${alert.id}'),
      onTap: onTap,
      // The Listen button's tap area is 56 high round a 50 high button: 3 dp less below it keeps the mockup's 16.
      padding: EdgeInsets.fromLTRB(16, 16, 16, listen ? 13 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                label: t('severity_${level.wire}'),
                child: IconDot(alertPicture(alert), background: fill, foreground: picture, round: true),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(alert.title.forLang(lang), style: AppText.hName)),
                        if (unread) ...[
                          const SizedBox(width: 8),
                          // The tag keeps its 24 dp height at big text sizes.
                          MediaQuery.withClampedTextScaling(
                            maxScaleFactor: 1.3,
                            child: AppPill(
                              t('alerts_new'),
                              key: ValueKey('alert-new-${alert.id}'),
                              background: AppColors.blue,
                              foreground: Colors.white,
                              height: 24,
                              fontSize: 12,
                              horizontal: 9,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (body.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(body, style: AppText.body),
                      ),
                    if (when.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(when, style: AppText.hMeta.copyWith(fontSize: 13)),
                      ),
                  ],
                ),
              ),
              if (level == Severity.green) ...[
                const SizedBox(width: 12),
                const Icon(AppIcons.chevron, size: 24, color: AppColors.chevron),
              ],
            ],
          ),
          if (listen) ...[
            const SizedBox(height: 9),
            AlertListenButton(
              key: ValueKey('alert-listen-${alert.id}'),
              label: t('field_listen_card'),
              onPressed: onListen!,
            ),
          ],
        ],
      ),
    );
    return unread ? card : Opacity(opacity: 0.85, child: card);
  }
}

/// The mockup's outline "Listen" button of an alert (`.btn.outline`, 50 high, 15 / 700, a 20 px speaker). Its tap area is
/// 56 dp high, the white button sits in the middle of it.
class AlertListenButton extends StatelessWidget {
  const AlertListenButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: label,
    excludeSemantics: true,
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        Haptics.tap();
        onPressed();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Container(
          height: 50,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line, width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(AppIcons.speaker, size: 20, color: AppColors.ink),
              const SizedBox(width: 10),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label, maxLines: 1, style: AppText.button.copyWith(fontSize: 15, color: AppColors.ink)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The top of an opened alert, drawn like the mockup's advice card: a flat card tinted with the level's colour and a thin
/// line, the round dot with the picture, the level's word in a white tag, the title big, then the full text and the time.
class AlertSummaryCard extends ConsumerWidget {
  const AlertSummaryCard({super.key, required this.alert, required this.when});

  final AlertOut alert;

  /// The time in words ([alertWhen]); empty for an alert without a date.
  final String when;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    final t = ref.watch(stringsProvider);
    final level = alert.level;
    final body = alert.body.forLang(lang);
    return AppCard(
      key: ValueKey('severity-${level.wire}'),
      color: AppColors.severitySoft(level),
      flat: true,
      line: severityLine(level),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconDot(
                alertPicture(alert),
                background: AppColors.severity(level),
                foreground: AppColors.onSeverity(level),
                size: 60,
                round: true,
                iconSize: 30,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: MediaQuery.withClampedTextScaling(
                        maxScaleFactor: 1.3,
                        child: AppPill(
                          t('severity_${level.wire}'),
                          background: AppColors.card,
                          foreground: AppColors.severityAccent(level),
                          height: 26,
                          horizontal: 10,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(alert.title.forLang(lang), style: AppText.big),
                  ],
                ),
              ),
            ],
          ),
          if (body.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(body, key: const ValueKey('alert-body'), style: AppText.body),
            ),
          if (when.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(when, style: AppText.hMeta.copyWith(fontSize: 13)),
            ),
        ],
      ),
    );
  }
}

/// No alerts yet: the bell in a neutral circle and the words (grey is "nothing happening").
class AlertsEmpty extends ConsumerWidget {
  const AlertsEmpty({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: Dimens.hero,
          height: Dimens.hero,
          decoration: const BoxDecoration(color: AppColors.neutralSoft, shape: BoxShape.circle),
          child: const Icon(AppIcons.bell, size: 72, color: AppColors.inkSoft),
        ),
        const SizedBox(height: 16),
        Text(
          t('alerts_empty_title'),
          key: const ValueKey('alerts-empty'),
          textAlign: TextAlign.center,
          style: AppText.big,
        ),
      ],
    );
  }
}
