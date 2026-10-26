import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/voice/utterance.dart';
import '../../core/widgets/status_views.dart';
import '../../core/widgets/voice_scaffold.dart';
import 'alert_widgets.dart';
import 'alerts_providers.dart';

/// Route `/alerts`: newest first, unread ones with a blue "New" tag. Tapping an alert opens it (and marks it as read); an
/// urgent one can also be heard from the list. Reloads when the app comes back and every five minutes (see
/// [AlertsAutoRefresh] in the router).
class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  final Object _owner = Object();

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.home);
    }
  }

  /// The "Listen" button of an urgent alert: says what the opened alert says (its spoken text, else its words). Like the
  /// speaker in the top bar it turns the voice on again if it was muted: whoever asks to listen wants to hear.
  Future<void> _listen(AlertOut alert) async {
    final lang = ref.read(languageProvider);
    final body = alert.body.forLang(lang);
    final spoken = alert.spoken.toUtterance(lang) ?? (body.isEmpty ? null : TextUtterance(body, lang: lang));
    if (spoken == null) return;
    if (ref.read(settingsProvider).muted) await ref.read(settingsProvider.notifier).setMuted(on: false);
    await ref.read(voiceServiceProvider).speak([spoken], owner: _owner);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final alerts = ref.watch(alertsProvider);

    final failed = alerts.hasError && !alerts.hasValue;
    if (failed) {
      return ErrorRetryScreen(error: alerts.error!, onRetry: () => ref.invalidate(alertsProvider), onBack: _back);
    }
    final loading = !alerts.hasValue;
    final items = newestFirst(alerts.value?.items ?? const []);

    return VoiceScaffold(
      owner: _owner,
      title: t('a11y_alerts'),
      script: promptList([items.isEmpty ? 'alert_none' : 'alert_open']),
      speakEnabled: !loading,
      onBack: _back,
      // The cards start at the top (the mockup's 16 dp `.pad`); the spinner and the empty page sit in the middle.
      alignTop: items.isNotEmpty,
      bodyPadding: const EdgeInsets.fromLTRB(Dimens.gutter, Dimens.gutter, Dimens.gutter, 0),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? const AlertsEmpty()
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  AlertCard(
                    alert: items[i],
                    onTap: () => context.push(Routes.alertDetailFor(items[i].id)),
                    onListen: () => _listen(items[i]),
                  ),
                ],
              ],
            ),
    );
  }
}
