import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/voice/utterance.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/status_views.dart';
import '../../core/widgets/voice_scaffold.dart';
import '../home/app_bottom_nav.dart';
import 'date_words.dart';
import 'diary_providers.dart';
import 'diary_timeline.dart';
import 'saved_speech.dart';

/// "My spray diary" (the owner's design 2 of `docs/design/diary-combined-proposals.html`): the crop circles on top (when there is
/// more than one crop), a strip of this week with a button for the month, then the timeline: newest first along a thread, a big
/// circle for each day and a card for each spray (its crop, the kind of medicine, the dose, the days to wait, its warnings, a
/// speaker, and a grey "Waiting" tag while it has not reached the server). Tapping an entry opens it (how to use the
/// medicine) and says it aloud. The floating green button writes a spray that was not advised.
class DiaryListScreen extends ConsumerStatefulWidget {
  const DiaryListScreen({super.key});

  @override
  ConsumerState<DiaryListScreen> createState() => _DiaryListScreenState();
}

class _DiaryListScreenState extends ConsumerState<DiaryListScreen> {
  final Object _owner = Object();

  /// The lower case id of the crop chosen on the crop circles; null shows every crop.
  String? _crop;

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.home);
    }
  }

  Future<void> _speakEntry(DiaryEntry entry) {
    final lang = ref.read(languageProvider);
    final t = ref.read(stringsProvider);
    final words = ref.read(dateWordsProvider);
    final name = entry.name.isEmpty ? t('diary_no_name') : entry.name;
    final items = <Utterance>[
      TextUtterance('$name, ${words.spoken(entry.date)}', lang: lang),
      if (entry.pending) const PromptUtterance('diary_waiting'),
      if (entry.warnings.isNotEmpty) const PromptUtterance('diary_warning'),
      for (final w in entry.warnings) ?warningUtterance(w, lang),
    ];
    return ref.read(voiceServiceProvider).speak(items, owner: _owner);
  }

  /// Chooses the crop whose sprays the page shows (null: all of them) and says its name.
  void _chooseCrop(String? cropId) {
    setState(() => _crop = cropId);
    final lang = ref.read(languageProvider);
    final t = ref.read(stringsProvider);
    final name = cropId == null ? t('diary_all_crops_say') : ref.read(resourcesProvider).cropName(cropId, lang);
    ref.read(voiceServiceProvider).speak([TextUtterance(name, lang: lang)], owner: _owner);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final now = ref.watch(clockProvider)();
    final logs = ref.watch(sprayLogsProvider);
    final pending = ref.watch(pendingSpraysProvider).items;

    // A waiting entry reached the server while the diary is open.
    ref.listen(pendingSpraysProvider.select((p) => p.sent), (previous, next) {
      if (next > (previous ?? 0)) {
        ref.read(voiceServiceProvider).speak(promptList(const ['diary_sent']), owner: _owner, interrupt: false);
      }
    });

    final failed = logs.hasError && !logs.hasValue;
    // No internet: the list the phone kept the last time.
    final remembered = failed ? ref.watch(cachedSprayLogsProvider) : null;
    if (failed && pending.isEmpty && remembered == null) {
      return ErrorRetryScreen(error: logs.error!, onRetry: () => ref.invalidate(sprayLogsProvider), onBack: _back);
    }
    final loading = !logs.hasValue && !failed;
    final entries = mergeDiaryEntries(logs.value ?? remembered ?? const [], pending, now);
    // Crop circles (only when there is more than one crop to choose from); a crop that has no entry any more is not chosen.
    final crops = diaryCrops(entries);
    final crop = _crop != null && crops.contains(_crop) ? _crop : null;
    final shown = crop == null
        ? entries
        : [
            for (final e in entries)
              if (e.cropId.toLowerCase() == crop) e,
          ];
    final script = promptList([
      'diary_intro',
      if (failed) errorPromptFor(logs.error!) else if (entries.isEmpty) 'diary_empty' else 'diary_add_hint',
    ]);

    return VoiceScaffold(
      owner: _owner,
      title: t('home_diary_label'),
      script: script,
      speakEnabled: !loading,
      // A main page: no back arrow (the bottom bar goes elsewhere); the phone's own back still leaves it.
      showBack: false,
      onBack: _back,
      alignTop: true,
      bodyPadding: const EdgeInsets.fromLTRB(Dimens.gutter, Dimens.gutter, Dimens.gutter, 0),
      bottomNav: const AppBottomNav(current: AppTab.diary),
      // Floats over the list, above the caption: a green "+ Write a spray".
      bottomRight: AppButton(
        key: const ValueKey('diary-add'),
        icon: AppIcons.plus,
        label: t('diary_add_label'),
        semanticLabel: t('diary_add_label'),
        horizontalPadding: 22,
        onPressed: () => context.push(Routes.diaryAdd),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : entries.isEmpty
          ? AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const IconDot(
                    AppIcons.notebook,
                    background: AppColors.blueSoft,
                    foreground: AppColors.blue,
                    size: 72,
                    round: true,
                    iconSize: 38,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    t('diary_empty_title'),
                    key: const ValueKey('diary-empty'),
                    textAlign: TextAlign.center,
                    style: AppText.big,
                  ),
                ],
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (failed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: AppCard(
                      key: const ValueKey('diary-offline'),
                      color: AppColors.neutralSoft,
                      flat: true,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          const Icon(AppIcons.offline, size: 24, color: AppColors.inkSoft),
                          const SizedBox(width: 12),
                          Expanded(child: Text(t('a11y_offline'), style: AppText.hName.copyWith(fontSize: 16))),
                        ],
                      ),
                    ),
                  ),
                if (crops.length > 1) ...[
                  DiaryCropRow(crops: crops, selected: crop, onSelect: _chooseCrop),
                  const SizedBox(height: 12),
                ],
                DiaryWeekCard(
                  counts: diarySprayCounts(shown),
                  onOpen: () => showDiaryMonthSheet(context, entries: shown, owner: _owner),
                ),
                const SizedBox(height: 12),
                DiaryTimeline(entries: shown, onSpeak: _speakEntry),
              ],
            ),
    );
  }
}
