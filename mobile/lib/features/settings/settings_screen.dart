import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_version.dart';
import '../../core/l10n/app_resources.dart';
import '../../core/models/models.dart';
import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/voice/speak_on_enter.dart';
import '../../core/voice/utterance.dart';
import '../../core/voice/voice_service.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/voice_scaffold.dart';
import '../auth/server_dialog.dart';

/// Whether the settings screen shows the server address (debug builds only). Tests override it.
final showServerUrlProvider = Provider<bool>((ref) => kDebugMode);

/// Who is logged in, language, voice speed, volume, "let the app speak", written words, the server and the app version,
/// and log out. Each change is applied at once and spoken as a sample; log out asks for a tick or a cross first. Drawn
/// as the mockup's settings page: white cards on the light ground, big text-only segmented buttons, switches in rows.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final Object _owner = Object();

  Future<void> _say(List<String> ids, {String? lang}) =>
      ref.read(voiceServiceProvider).speakPrompts(ids, lang: lang, owner: _owner);

  /// "Let the app speak": off silences the app on every screen (the words still show) and stops what is being said at
  /// once, like the mute button of the top bar; on says a sample, so the farmer hears that the voice is back.
  Future<void> _setVoice({required bool on}) async {
    await ref.read(settingsProvider.notifier).setMuted(on: !on);
    if (on) {
      await _say(const ['settings_volume']);
    } else {
      await ref.read(voiceServiceProvider).stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final lang = ref.watch(languageProvider);
    final session = ref.watch(sessionProvider);
    final farmer = session.farmer;
    final languages = ref.watch(resourcesProvider).languages;
    // Only against a real server (or in a debug build): where the app looks for it. The address of a test PC changes
    // with the network, so a release build with the demo mock shows no server at all.
    final realServer = !ref.watch(appConfigProvider).useMockApi;
    final showServer = realServer || ref.watch(showServerUrlProvider);
    final serverText = t('settings_server', args: {'url': ref.watch(apiBaseUrlProvider)});

    return VoiceScaffold(
      owner: _owner,
      title: t('a11y_settings'),
      script: promptList(const ['settings_speed', 'settings_volume']),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (farmer != null) _ProfileCard(farmer: farmer),
          _Group(
            title: t('settings_language'),
            child: _LanguageChoices(
              languages: languages,
              selected: lang,
              onChosen: (code) async {
                await ref.read(sessionProvider.notifier).syncLanguage(code);
                await _say(const ['settings_language_changed'], lang: code);
              },
            ),
          ),
          _Group(
            title: t('settings_speed'),
            child: _Choices<SpeechSpeed>(
              keyPrefix: 'speed',
              ids: const ['slow', 'normal', 'fast'],
              values: SpeechSpeed.values,
              selected: settings.speed,
              labels: [t('speed_slow'), t('speed_normal'), t('speed_fast')],
              onChosen: (v) async {
                await notifier.setSpeed(v);
                await _say(const ['settings_speed']);
              },
            ),
          ),
          _Group(
            title: t('settings_volume'),
            child: _Choices<VolumeLevel>(
              keyPrefix: 'volume',
              ids: const ['low', 'medium', 'high'],
              values: VolumeLevel.values,
              selected: settings.volume,
              labels: [t('volume_low'), t('volume_medium'), t('volume_high')],
              onChosen: (v) async {
                await notifier.setVolume(v);
                await _say(const ['settings_volume']);
              },
            ),
          ),
          const SizedBox(height: _gap),
          _SwitchRow(
            icon: AppIcons.speaker,
            label: t('settings_voice'),
            switchKey: const ValueKey('settings-voice'),
            value: !settings.muted,
            onChanged: (on) => _setVoice(on: on),
          ),
          const SizedBox(height: _gap),
          _SwitchRow(
            icon: AppIcons.captions,
            label: t('settings_captions'),
            switchKey: const ValueKey('settings-captions'),
            value: settings.captions,
            onChanged: (on) => notifier.setCaptions(on: on),
          ),
          const SizedBox(height: _gap),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showServer) ...[
                    _ServerRow(text: serverText, tappable: realServer, showKey: ref.watch(showServerUrlProvider)),
                    const _Hairline(),
                  ],
                  _AboutRow(text: t('settings_about', args: {'v': kAppVersion})),
                ],
              ),
            ),
          ),
          if (session.isLoggedIn) ...[
            const SizedBox(height: _gap),
            AppButton(
              key: const ValueKey('log-out'),
              style: AppButtonStyle.danger,
              icon: AppIcons.logout,
              label: t('log_out'),
              semanticLabel: t('log_out'),
              onPressed: () => context.push(Routes.settingsLogout),
            ),
          ],
        ],
      ),
    );
  }
}

/// The mockup's 12 px between the blocks of a page.
const _gap = 12.0;

/// A section: the small label (`.label`: capitals in Latin scripts, plain in Devanagari) and its controls. The label has
/// 6 px above it and -2 px under it in the mockup, so the controls sit 10 px below it.
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: _gap),
      SectionLabel(title, hindi: isDevanagari(title)),
      const SizedBox(height: _gap - 2),
      child,
    ],
  );
}

/// Who is logged in: initials in a 52 px soft-green circle, the name, and "f001 · village, district".
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.farmer});

  final FarmerOut farmer;

  /// "DS" for "Dinesh Sharma": the first letter of up to two words.
  static String _initials(String name) =>
      name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();

  @override
  Widget build(BuildContext context) {
    final place = [farmer.village, farmer.district].whereType<String>().where((s) => s.isNotEmpty).join(', ');
    final meta = [farmer.id.toLowerCase(), place].where((s) => s.isNotEmpty).join(' · ');
    return AppCard(
      key: const ValueKey('settings-profile'),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.greenSoft, shape: BoxShape.circle),
            child: Text(
              _initials(farmer.name),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.green),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (farmer.name.isNotEmpty) Text(farmer.name, style: AppText.hName),
                if (meta.isNotEmpty) Text(meta, style: AppText.hMeta),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A card with one setting that is on or off: a grey square with its picture, the words in 16 / 700 and the switch.
/// The switch is 56 dp high (the touch size) inside a 76 dp card, so the card has 10 dp above and below it and 6 dp on
/// its right (the switch keeps 10 dp of its own around the 52 px track): the track ends 16 dp from the edge.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.label,
    required this.switchKey,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final Key switchKey;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
    child: Row(
      children: [
        IconDot(icon, background: AppColors.neutralSoft, foreground: AppColors.ink),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: AppText.hName.copyWith(fontSize: 16))),
        AppSwitch(key: switchKey, value: value, onChanged: onChanged, semanticLabel: label),
      ],
    ),
  );
}

/// The server row of the settings card: the picture, the address (one line) and, when it can be changed, the arrow.
/// [tappable] opens the dialog that changes it; [showKey] marks the text for debug builds.
class _ServerRow extends ConsumerWidget {
  const _ServerRow({required this.text, required this.tappable, required this.showKey});

  final String text;
  final bool tappable;
  final bool showKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            const Icon(AppIcons.server, size: 24, color: AppColors.inkSoft),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                key: showKey ? const ValueKey('settings-server') : null,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.hMeta,
              ),
            ),
            if (tappable) const Icon(AppIcons.chevron, size: 24, color: AppColors.chevron),
          ],
        ),
      ),
    );
    if (!tappable) return row;
    return Semantics(
      button: true,
      label: text,
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('settings-server-link'),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        onTap: () => showServerDialog(context, ref),
        child: row,
      ),
    );
  }
}

/// "FarmTrack, version 0.1.0": the 48 px last row of the settings card.
class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 48),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(text, key: const ValueKey('settings-about'), style: AppText.hMeta),
      ),
    ),
  );
}

/// The 1 px line between the rows of a card, inset by the card's 16 px.
class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 16),
    child: Divider(height: 1, thickness: 1, color: AppColors.line),
  );
}

/// `.seg`: two or three equal parts side by side with 8 px between them, text only. The chosen one has a green 2 px
/// border, the soft-green fill and green words.
class _Choices<T> extends StatelessWidget {
  const _Choices({
    required this.keyPrefix,
    required this.ids,
    required this.values,
    required this.selected,
    required this.labels,
    required this.onChosen,
  });

  final String keyPrefix;
  final List<String> ids;
  final List<T> values;
  final T selected;
  final List<String> labels;
  final Future<void> Function(T value) onChosen;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < values.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(
          child: _SegButton(
            key: ValueKey('$keyPrefix-${ids[i]}'),
            label: labels[i],
            selected: values[i] == selected,
            onTap: () => onChosen(values[i]),
          ),
        ),
      ],
    ],
  );
}

/// One button of a segmented choice (`.seg button`): 56 high, radius 14, a 2 px border, 15 / 700 words. [leading] is
/// the round letter badge of the language buttons.
class _SegButton extends StatelessWidget {
  const _SegButton({super.key, required this.label, required this.selected, required this.onTap, this.leading});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.green : AppColors.ink;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      // The border is painted on the Material, not inset: the whole 56 high button is the tap area.
      child: Material(
        color: selected ? AppColors.greenSoft : AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dimens.radiusSmall),
          side: BorderSide(color: selected ? AppColors.green : AppColors.line, width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Dimens.radiusSmall),
          // Tapping the chosen one again is allowed: it plays the sample again.
          onTap: () {
            Haptics.tap();
            onTap();
          },
          child: SizedBox(
            height: Dimens.minTouch,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 8)],
                  // A long word shrinks instead of wrapping, so the buttons stay 56 high.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One segmented button per language, each with its round letter badge (32 px: green with a white letter when chosen,
/// grey when not) and the name in its own script. Tapping plays that language's name in its own voice, applies the
/// choice and calls [onChosen]. Two languages sit side by side; more are laid out two to a row.
class _LanguageChoices extends ConsumerStatefulWidget {
  const _LanguageChoices({required this.languages, required this.selected, required this.onChosen});

  final List<LanguageInfo> languages;
  final String selected;
  final Future<void> Function(String code) onChosen;

  @override
  ConsumerState<_LanguageChoices> createState() => _LanguageChoicesState();
}

class _LanguageChoicesState extends ConsumerState<_LanguageChoices> {
  bool _busy = false;

  Future<void> _choose(LanguageInfo language) async {
    if (_busy) return;
    final owner = VoiceSession.maybeOf(context)?.owner;
    setState(() => _busy = true);
    try {
      await ref.read(settingsProvider.notifier).setLanguage(language.code);
      if (language.promptId.isNotEmpty) {
        // Plays "Hindi." / "English." in that language's own voice before the change is confirmed.
        await ref.read(voiceServiceProvider).speak([
          PromptUtterance(language.promptId, lang: language.code),
        ], owner: owner);
      }
      await widget.onChosen(language.code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final buttons = [
      for (final language in widget.languages)
        _SegButton(
          key: ValueKey('language-${language.code}'),
          label: language.nativeName,
          selected: language.code == widget.selected,
          onTap: () => _choose(language),
          leading: _Badge(language: language, selected: language.code == widget.selected),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < buttons.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: buttons[i]),
              const SizedBox(width: 8),
              Expanded(child: i + 1 < buttons.length ? buttons[i + 1] : const SizedBox.shrink()),
            ],
          ),
        ],
      ],
    );
  }
}

/// The round letter of a language button (`.dot.round` 32 px, 16 px letter).
class _Badge extends StatelessWidget {
  const _Badge({required this.language, required this.selected});

  final LanguageInfo language;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('language-badge-${language.code}'),
    width: 32,
    height: 32,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: selected ? AppColors.green : AppColors.neutralSoft, shape: BoxShape.circle),
    child: Text(
      language.badgeText,
      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: selected ? Colors.white : AppColors.ink),
    ),
  );
}
