import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/api_exception.dart';
import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/voice/utterance.dart';
import '../../core/voice/voice_service.dart';
import '../../core/widgets/big_buttons.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/status_views.dart';
import '../../core/widgets/voice_scaffold.dart';
import 'auth_widgets.dart';
import 'server_dialog.dart';

/// The one login screen (route `/login`): a user name and a password typed with the phone's own keyboard, then the big
/// green tick. The app always asks for it; the session itself stays in the secure token store. Only the last user name
/// is remembered (in SharedPreferences) and prefilled, never the password.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  /// Same rules as the server: 3 to 40 characters of a to z, 0 to 9, dot, underscore and minus; password 6 or more.
  static final _usernameShape = RegExp(r'^[a-z0-9._-]{3,40}$');
  static const _minPassword = 6;

  final Object _owner = Object();
  late final TextEditingController _username;
  final TextEditingController _password = TextEditingController();
  final FocusNode _usernameFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  bool _hidden = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _username = TextEditingController(text: ref.read(settingsStoreProvider).loadLastUsername() ?? '');
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _say(List<String> ids) => ref.read(voiceServiceProvider).speakPrompts(ids, owner: _owner);

  void _toggleHidden() {
    setState(() => _hidden = !_hidden);
    _say([_hidden ? 'login_hide_password' : 'login_show_password']);
  }

  Future<void> _fail(String promptId) async {
    Haptics.error();
    await _say([promptId]);
  }

  Future<void> _submit() async {
    if (_busy) return;
    final username = _username.text.trim().toLowerCase();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) {
      (username.isEmpty ? _usernameFocus : _passwordFocus).requestFocus();
      await _fail('login_fields_needed');
      return;
    }
    // Such a pair can never exist: say "not right" without asking the server.
    if (!_usernameShape.hasMatch(username) || password.length < _minPassword) {
      await _fail('login_wrong');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _busy = true);
    try {
      final token = await ref
          .read(apiClientProvider)
          .login(username: username, password: password, deviceId: ref.read(deviceIdProvider));
      if (!mounted) return;
      await ref.read(settingsStoreProvider).saveLastUsername(username);
      await ref.read(sessionProvider.notifier).login(token);
      await ref.read(sessionProvider.notifier).syncLanguage(ref.read(languageProvider));
      Haptics.success();
      if (mounted) context.go(Routes.homeFresh);
    } on ApiException catch (e) {
      if (!mounted) return;
      final wrong = e.code == 'invalid_credentials' || e.kind == ApiErrorKind.validation;
      await _fail(wrong ? 'login_wrong' : errorPromptFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    // The picture gives way to the fields while the keyboard is up.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return VoiceScaffold(
      owner: _owner,
      script: promptList(const ['login_intro', 'login_ask_username', 'login_ask_password', 'login_tap_tick']),
      // The mockup's login has no back arrow (logo, then the voice buttons); the phone's own back button still goes back.
      onBack: () => context.go(Routes.welcome),
      showBack: false,
      flatTopBar: true,
      titleWidget: AuthLogo(name: t('app_name')),
      alignTop: true,
      wideAction: true,
      // The mockup's login has a 20 gutter (the other screens 16).
      bodyPadding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!keyboardOpen) ...[const HillsPicture(), const SizedBox(height: 14)],
          AuthHeading(title: t('a11y_login'), subtitle: t('login_welcome')),
          const SizedBox(height: 14),
          _FieldLabel(icon: AppIcons.person, text: t('login_username_label')),
          Semantics(
            label: t('login_username_label'),
            child: FieldGlow(
              focusNode: _usernameFocus,
              child: TextField(
                key: const ValueKey('login-username'),
                controller: _username,
                focusNode: _usernameFocus,
                autofocus: _username.text.isEmpty,
                enabled: !_busy,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 40,
                style: authInputStyle,
                decoration: authInputDecoration(),
                onSubmitted: (_) => _passwordFocus.requestFocus(),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _FieldLabel(icon: AppIcons.lock, text: t('login_password_label')),
          Semantics(
            label: t('login_password_label'),
            child: FieldGlow(
              focusNode: _passwordFocus,
              child: TextField(
                key: const ValueKey('login-password'),
                controller: _password,
                focusNode: _passwordFocus,
                autofocus: _username.text.isNotEmpty,
                enabled: !_busy,
                obscureText: _hidden,
                // Plain letters and numbers, no suggestions or learned words.
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 128,
                // The dots are spaced out (`letter-spacing: 4px`); the shown password is plain text.
                style: authInputStyle.copyWith(letterSpacing: _hidden ? 4 : null),
                // The eye sits inside the box, at its right end.
                decoration: authInputDecoration(
                  // Flutter adds half of the letter spacing before each dot (CSS only after it): 2 less keeps the mockup's start.
                  start: _hidden ? 12 : 14,
                  suffixIcon: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: BigIconButton(
                      key: const ValueKey('login-eye'),
                      icon: _hidden ? AppIcons.eye : AppIcons.eyeOff,
                      semanticLabel: t(_hidden ? 'login_show_password' : 'login_hide_password'),
                      color: AppColors.neutralSoft,
                      foreground: AppColors.ink,
                      size: Dimens.minTouch,
                      onPressed: _toggleHidden,
                    ),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
          ),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
          // Only against a real server: which PC or server the test phone talks to (never shown with the demo mock).
          if (!ref.watch(appConfigProvider).useMockApi) _ServerLink(enabled: !_busy),
        ],
      ),
      bottomRight: AppButton(
        key: const ValueKey('login-submit'),
        icon: AppIcons.tickBold,
        label: t('a11y_login'),
        semanticLabel: t('a11y_login'),
        onPressed: _busy ? null : _submit,
      ),
    );
  }
}

/// A picture and a word above a field (`.field-l`: a 20 green picture, 15 / 700, 4 above and 8 below).
class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.36, color: AppColors.ink),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The line under the login fields: opens a dialog to type the server address (`http://<PC address>:8000`). The picture,
/// the address and a blue "Change" (13 px); the tap area is the full 56 dp high.
class _ServerLink extends ConsumerWidget {
  const _ServerLink({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final url = ref.watch(apiBaseUrlProvider);
    const small = TextStyle(fontSize: 13, height: 1.36, color: AppColors.inkSoft);
    final change = t('login_server_change');
    return Semantics(
      button: true,
      enabled: enabled,
      label: '${t('login_server')}: $url. $change',
      excludeSemantics: true,
      child: SizedBox(
        height: Dimens.minTouch,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: const ValueKey('server-link'),
            borderRadius: BorderRadius.circular(12),
            onTap: enabled ? () => showServerDialog(context, ref) : null,
            child: Row(
              children: [
                const SizedBox(width: 2),
                const Icon(AppIcons.server, size: 20, color: AppColors.inkSoft),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${t('login_server')}: $url', overflow: TextOverflow.ellipsis, maxLines: 1, style: small),
                ),
                const SizedBox(width: 8),
                Text(
                  change,
                  style: small.copyWith(color: AppColors.blue, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
