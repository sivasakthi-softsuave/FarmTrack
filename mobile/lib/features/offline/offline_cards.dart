import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/api_exception.dart';
import '../../core/models/models.dart';
import '../../core/offline/offline_queue.dart';
import '../../core/offline/offline_status.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/voice/speak_on_enter.dart';
import '../../core/voice/voice_service.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/status_views.dart';
import '../diary/date_words.dart';
import '../diary/diary_providers.dart';
import '../scan/scan_flow.dart';
import 'last_result.dart';

/// The cards of the offline queue on Home, in the mockup's order: a green "Result ready: tap to see" card for a saved
/// photo that was sent, then the "Last advice" card that opens the last answer again from the phone's memory (it works
/// without internet and says its date). Nothing shows when there is neither. Every block brings its own 12 dp gap above
/// it (the mockup's `.pad` gap), so an empty block takes no room.
class OfflineResultCards extends ConsumerStatefulWidget {
  const OfflineResultCards({super.key, this.part = OfflineResultPart.both});

  /// Home shows the green "Result ready" card right under the camera card and the "Last advice" card below the weather: the same
  /// widget, once for each part.
  final OfflineResultPart part;

  @override
  ConsumerState<OfflineResultCards> createState() => _OfflineResultCardsState();
}

/// Which cards of [OfflineResultCards] a block shows.
enum OfflineResultPart { both, ready, last }

class _OfflineResultCardsState extends ConsumerState<OfflineResultCards> {
  bool _opening = false;

  Future<void> _openResult(ReadyResult result) async {
    if (_opening) return;
    final notifier = ref.read(offlineStatusProvider.notifier);
    final voice = ref.read(voiceServiceProvider);
    final owner = VoiceSession.maybeOf(context)?.owner;
    setState(() => _opening = true);
    try {
      final scan = await notifier.open(result);
      if (!mounted) return;
      ref.read(scanFlowProvider.notifier).showResult(scan);
      notifier.dismiss(result.scanId);
      Haptics.success();
      context.go(routeForScan(scan));
    } on ApiException catch (e) {
      Haptics.error();
      // A result the server does not know any more can never be opened: take the card away.
      if (e.kind == ApiErrorKind.client) notifier.dismiss(result.scanId);
      await voice.speakPrompts([errorPromptFor(e)], owner: owner);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  /// The last advice again, from the phone's memory (works with no internet).
  void _openLast(LastResult last) {
    ref.read(scanFlowProvider.notifier).showResult(last.scan, remember: false);
    Haptics.tap();
    context.go(routeForScan(last.scan));
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(offlineStatusProvider.select((s) => s.ready));
    final t = ref.watch(stringsProvider);
    var last = ref.watch(lastResultProvider);
    // A result that is ready to open is the same answer: one card is enough.
    if (last != null && status.any((r) => r.scanId == last!.scan.id)) last = null;
    final showReady = widget.part != OfflineResultPart.last && status.isNotEmpty;
    final showLast = widget.part != OfflineResultPart.ready && last != null;
    if (!showReady && !showLast) return const SizedBox.shrink();
    // The last advice that was already written into the diary shows the green tick.
    final lastAdviceId = last?.scan.advice?.id ?? '';
    final lastSprayed = lastAdviceId.isNotEmpty && ref.watch(sprayStateProvider(lastAdviceId)) == SprayState.done;
    final heading = t('home_last_advice');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showReady) ...[
          const SizedBox(height: _blockGap),
          _ReadyCard(
            key: const ValueKey('offline-result-card'),
            label: t('offline_result_card'),
            count: status.length > 1 ? status.length : 0,
            onTap: _opening ? null : () => _openResult(status.first),
          ),
        ],
        if (showLast) ...[
          const SizedBox(height: _blockGap),
          SectionLabel(heading, hindi: isDevanagari(heading)),
          const SizedBox(height: _labelGap),
          _LastAdviceCard(
            key: const ValueKey('last-result-card'),
            last: last,
            sprayed: lastSprayed,
            onTap: () => _openLast(last!),
          ),
        ],
      ],
    );
  }
}

/// "Waiting to send: N" while items still wait for the internet: the mockup's flat neutral card with the clock. A tap
/// says what is waiting and tries to send it right now (the automatic retries wait for the timer, the network coming
/// back or the app being opened).
class OfflineWaitingCard extends ConsumerWidget {
  const OfflineWaitingCard({super.key});

  void _speakWaiting(BuildContext context, WidgetRef ref) {
    final owner = VoiceSession.maybeOf(context)?.owner;
    unawaited(ref.read(voiceServiceProvider).speakPrompts(const ['offline_waiting'], owner: owner));
    unawaited(ref.read(offlineQueueProvider).flush());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(offlineStatusProvider.select((s) => s.pending));
    if (pending <= 0) return const SizedBox.shrink();
    final t = ref.watch(stringsProvider);
    final label = t('offline_waiting_card', args: {'n': pending});
    return Padding(
      padding: const EdgeInsets.only(top: _blockGap),
      child: AppCard(
        key: const ValueKey('offline-waiting-card'),
        // Waiting is grey, never yellow: yellow means a warning.
        color: AppColors.neutralSoft,
        flat: true,
        semanticLabel: label,
        onTap: () => _speakWaiting(context, ref),
        child: Row(
          children: [
            const IconDot(AppIcons.clock, background: AppColors.card, foreground: AppColors.inkSoft),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: _cardName),
                  Text(t('offline_waiting_hint'), style: AppText.hMeta),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The mockup's 12 px gap between the blocks of a page, and the 10 px (12 minus the label's -2) under a section label.
const _blockGap = 12.0;
const _labelGap = 10.0;

/// `.h-name` at the 16 px the mockup uses on its small status cards.
final _cardName = AppText.hName.copyWith(fontSize: 16);

/// A saved photo was sent and its answer is ready: a green card, the tick, the words and (with several) their number.
class _ReadyCard extends StatelessWidget {
  const _ReadyCard({super.key, required this.label, required this.count, required this.onTap});

  final String label;
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AppCard(
    color: AppColors.greenSoft,
    flat: true,
    line: AppColors.green.withValues(alpha: 0.4),
    semanticLabel: label,
    onTap: onTap,
    child: Row(
      children: [
        const IconDot(AppIcons.tickBold, background: AppColors.green, foreground: Colors.white),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: _cardName)),
        if (count > 0) ...[
          const SizedBox(width: 8),
          AppPill('$count', background: AppColors.green, foreground: Colors.white),
        ],
        const SizedBox(width: 4),
        const Icon(AppIcons.chevron, size: 24, color: AppColors.green),
      ],
    ),
  );
}

/// The last advice as a card: a picture of its severity, the disease name, the severity word and the day, and a tick
/// once it was written into the diary. A result without a medicine advice says "Last advice: `day`".
class _LastAdviceCard extends ConsumerWidget {
  const _LastAdviceCard({super.key, required this.last, required this.sprayed, required this.onTap});

  final LastResult last;
  final bool sprayed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final lang = ref.watch(languageProvider);
    final words = ref.watch(dateWordsProvider);
    final advice = last.scan.advice;
    final day = words.written(last.savedAt.toLocal());
    final severity = advice?.severity;
    final headline = advice?.headline.forLang(lang) ?? '';
    final title = headline.isEmpty ? t('last_result_card', args: {'date': day}) : headline;
    final meta = severity == null || headline.isEmpty ? '' : '${t('severity_${severity.wire}')} · $day';
    final (icon, fill, color) = switch (severity) {
      Severity.red => (AppIcons.danger, AppColors.redSoft, AppColors.red),
      Severity.yellow => (AppIcons.warning, AppColors.amberSoft, AppColors.amberDark),
      Severity.green => (AppIcons.tick, AppColors.greenSoft, AppColors.green),
      null => (AppIcons.clock, AppColors.greenSoft, AppColors.green),
    };
    return AppCard(
      semanticLabel: title,
      onTap: onTap,
      child: Row(
        children: [
          IconDot(icon, background: fill, foreground: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.hName),
                if (meta.isNotEmpty) Text(meta, style: AppText.hMeta),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            sprayed ? AppIcons.tick : AppIcons.chevron,
            key: ValueKey(sprayed ? 'last-result-sprayed' : 'last-result-open'),
            size: 24,
            color: sprayed ? AppColors.green : AppColors.chevron,
          ),
        ],
      ),
    );
  }
}
