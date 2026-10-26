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
import 'diary_widgets.dart';
import 'saved_speech.dart';

/// "My spray diary": newest first, grouped by day under a small day heading; each entry is a card with the medicine,
/// its brand and crop, a grey "Waiting" pill or a green tick, and its warnings inside it. Tapping an entry says it aloud.
/// The floating green button writes a spray that was not advised.
class DiaryListScreen extends ConsumerStatefulWidget {
  const DiaryListScreen({super.key});

  @override
  ConsumerState<DiaryListScreen> createState() => _DiaryListScreenState();
}

class _DiaryListScreenState extends ConsumerState<DiaryListScreen> {
  final Object _owner = Object();

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

  /// The entries with a small heading above each day ("Today", "2 May"): 12 between cards, a little more above a heading.
  List<Widget> _days(List<DiaryEntry> entries, DateWords words, DateTime now) {
    final children = <Widget>[];
    DateTime? day;
    for (final entry in entries) {
      final entryDay = dayOnly(entry.date);
      if (entryDay != day) {
        day = entryDay;
        final label = words.relative(entryDay, now) ?? words.written(entryDay);
        if (children.isNotEmpty) children.add(const SizedBox(height: 12));
        children
          ..add(SectionLabel(label, hindi: isDevanagari(label)))
          ..add(const SizedBox(height: 10));
      } else {
        children.add(const SizedBox(height: 12));
      }
      children.add(DiaryEntryCard(entry: entry, onTap: () => _speakEntry(entry)));
    }
    return children;
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final now = ref.watch(clockProvider)();
    final words = ref.watch(dateWordsProvider);
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
                ..._days(entries, words, now),
              ],
            ),
    );
  }
}
