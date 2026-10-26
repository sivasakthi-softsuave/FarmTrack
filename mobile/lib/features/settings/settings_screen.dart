import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_version.dart';
import '../../core/providers.dart';
import '../auth/server_dialog.dart';
import '../../core/router/routes.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/voice/utterance.dart';
import '../../core/voice/voice_service.dart';
import '../../core/widgets/voice_scaffold.dart';
import '../onboarding/language_screen.dart';

/// Whether the settings screen shows the server address (debug builds only). Tests override it.
final showServerUrlProvider = Provider<bool>((ref) => kDebugMode);

/// Language, voice speed, volume, written words and log out, with the app version at the bottom. Each change is
/// applied at once and spoken as a sample; log out asks for a tick or a cross first.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final Object _owner = Object();

  Future<void> _say(List<String> ids, {String? lang}) =>
      ref.read(voiceServiceProvider).speakPrompts(ids, lang: lang, owner: _owner);

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final lang = ref.watch(languageProvider);
    final session = ref.watch(sessionProvider);
    final aboutStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15, color: AppColors.inkSoft);

    return VoiceScaffold(
      owner: _owner,
      title: t('a11y_settings'),
      script: promptList(const ['settings_speed', 'settings_volume']),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Section(
            title: t('settings_language'),
            child: LanguageButtons(
              selected: lang,
              compact: true,
              onChosen: (code) async {
                await ref.read(sessionProvider.notifier).syncLanguage(code);
                await _say(const ['settings_language_changed'], lang: code);
              },
            ),
          ),
          _Section(
            title: t('settings_speed'),
            child: _Choices<SpeechSpeed>(
              keyPrefix: 'speed',
              ids: const ['slow', 'normal', 'fast'],
              values: SpeechSpeed.values,
              selected: settings.speed,
              icons: const [AppIcons.slow, AppIcons.normalSpeed, AppIcons.fast],
              labels: [t('speed_slow'), t('speed_normal'), t('speed_fast')],
              onChosen: (v) async {
                await notifier.setSpeed(v);
                await _say(const ['settings_speed']);
              },
            ),
          ),
          _Section(
            title: t('settings_volume'),
            child: _Choices<VolumeLevel>(
              keyPrefix: 'volume',
              ids: const ['low', 'medium', 'high'],
              values: VolumeLevel.values,
              selected: settings.volume,
              icons: const [AppIcons.volumeLow, AppIcons.volumeMedium, AppIcons.volumeHigh],
              labels: [t('volume_low'), t('volume_medium'), t('volume_high')],
              onChosen: (v) async {
                await notifier.setVolume(v);
                await _say(const ['settings_volume']);
              },
            ),
          ),
          _Section(
            title: t('settings_captions'),
            child: _Choices<bool>(
              keyPrefix: 'captions',
              ids: const ['off', 'on'],
              values: const [false, true],
              selected: settings.captions,
              icons: const [AppIcons.cross, AppIcons.tick],
              labels: [t('a11y_no'), t('a11y_yes')],
              onChosen: (on) => notifier.setCaptions(on: on),
            ),
          ),
          if (session.isLoggedIn)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                key: const ValueKey('log-out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.red,
                  side: const BorderSide(color: Color(0xFFF2C2BE), width: 2),
                ),
                icon: const Icon(AppIcons.logout),
                label: Text(t('log_out')),
                onPressed: () => context.push(Routes.settingsLogout),
              ),
            ),
          // Only against a real server: where the app looks for it. The address of a test PC changes with the network.
          if (!ref.watch(appConfigProvider).useMockApi)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                key: const ValueKey('settings-server-link'),
                icon: const Icon(Icons.dns_rounded),
                label: Text(
                  '${t('login_server')}: ${ref.watch(apiBaseUrlProvider)}',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                onPressed: () => showServerDialog(context, ref),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              children: [
                Text(
                  t('settings_about', args: {'v': kAppVersion}),
                  key: const ValueKey('settings-about'),
                  textAlign: TextAlign.center,
                  style: aboutStyle,
                ),
                if (ref.watch(showServerUrlProvider))
                  Text(
                    t('settings_server', args: {'url': ref.watch(apiBaseUrlProvider)}),
                    key: const ValueKey('settings-server'),
                    textAlign: TextAlign.center,
                    style: aboutStyle,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
    decoration: AppDecor.card(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );
}

/// A segmented choice (two or three parts side by side), the chosen one in green.
class _Choices<T> extends StatelessWidget {
  const _Choices({
    required this.keyPrefix,
    required this.ids,
    required this.values,
    required this.selected,
    required this.icons,
    required this.labels,
    required this.onChosen,
  });

  final String keyPrefix;
  final List<String> ids;
  final List<T> values;
  final T selected;
  final List<IconData> icons;
  final List<String> labels;
  final Future<void> Function(T value) onChosen;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < values.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(
          child: _Choice(
            key: ValueKey('$keyPrefix-${ids[i]}'),
            icon: icons[i],
            label: labels[i],
            selected: values[i] == selected,
            onTap: () => onChosen(values[i]),
          ),
        ),
      ],
    ],
  );
}

/// One part of a segmented choice: a picture and a word; the chosen one is green with a green border.
class _Choice extends StatelessWidget {
  const _Choice({super.key, required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.green : AppColors.ink;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? AppColors.greenSoft : AppColors.card,
        shape: AppDecor.shape(selected ? _chosenSide : _plainSide, radius: 16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: SizedBox(
            height: 68,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 24, color: color),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 14, color: color),
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
}

const _chosenSide = BorderSide(color: AppColors.green, width: 2.5);
const _plainSide = BorderSide(color: AppColors.line, width: 2);
