import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/design.dart';
import 'auth_widgets.dart';

/// The dialog in which the server address is typed (`http://<PC address>:8000`) and kept on the phone. Used by the login
/// screen and by Settings, so the address can be fixed whenever the PC's address changes.
Future<void> showServerDialog(BuildContext context, WidgetRef ref) =>
    showDialog<void>(context: context, builder: (_) => const _ServerDialog());

/// A white card on the dimmed screen, in the look of the login: a picture and the title, the address in a login-style
/// field, then "Reset" and "Save" as the app's two buttons.
class _ServerDialog extends ConsumerStatefulWidget {
  const _ServerDialog();

  @override
  ConsumerState<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends ConsumerState<_ServerDialog> {
  late final TextEditingController _controller = TextEditingController(text: ref.read(apiBaseUrlProvider));
  final FocusNode _focus = FocusNode();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    await ref.read(sharedPreferencesProvider).remove(serverOverrideKey);
    ref
      ..invalidate(apiBaseUrlProvider)
      ..invalidate(apiClientProvider);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _save() async {
    final t = ref.read(stringsProvider);
    final text = _controller.text.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(text);
    final ok = uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
    if (!ok) {
      setState(() => _error = t('server_invalid'));
      return;
    }
    await ref.read(sharedPreferencesProvider).setString(serverOverrideKey, text);
    ref
      ..invalidate(apiBaseUrlProvider)
      ..invalidate(apiClientProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    return Dialog(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        namesRoute: true,
        label: t('server_title'),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExcludeSemantics(
                child: Row(
                  children: [
                    const IconDot(AppIcons.server, background: AppColors.neutralSoft, foreground: AppColors.ink),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(t('server_title'), style: AppText.title.copyWith(color: AppColors.ink)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Semantics(
                label: t('server_title'),
                child: FieldGlow(
                  focusNode: _focus,
                  color: _error == null ? AppColors.green : AppColors.red,
                  child: TextField(
                    key: const ValueKey('server-field'),
                    controller: _controller,
                    focusNode: _focus,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: authInputStyle.copyWith(fontSize: 16),
                    decoration: authInputDecoration(hint: 'http://192.168.1.5:8000', error: _error != null),
                  ),
                ),
              ),
              if (_error != null)
                Semantics(
                  liveRegion: true,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(AppIcons.warning, size: 20, color: AppColors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                              color: AppColors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      key: const ValueKey('server-reset'),
                      style: AppButtonStyle.outline,
                      label: t('server_reset'),
                      semanticLabel: t('server_reset'),
                      onPressed: _reset,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppButton(
                      key: const ValueKey('server-save'),
                      label: t('server_save'),
                      semanticLabel: t('server_save'),
                      onPressed: _save,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
