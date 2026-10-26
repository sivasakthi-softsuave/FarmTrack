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
import '../../core/widgets/status_views.dart';
import '../../core/widgets/voice_scaffold.dart';
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
    final theme = Theme.of(context).textTheme;
    // The picture gives way to the fields while the keyboard is up.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return VoiceScaffold(
      owner: _owner,
      script: promptList(const ['login_intro', 'login_ask_username', 'login_ask_password', 'login_tap_tick']),
      onBack: () => context.go(Routes.welcome),
      flatTopBar: true,
      titleWidget: _Logo(name: t('app_name')),
      alignTop: true,
      wideAction: true,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!keyboardOpen) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(Dimens.radius),
              child: const SizedBox(height: 140, child: CustomPaint(painter: _HillsPainter())),
            ),
            const SizedBox(height: 18),
          ],
          Text(t('a11y_login'), style: theme.headlineMedium),
          const SizedBox(height: 2),
          Text(t('login_welcome'), style: theme.bodyLarge?.copyWith(color: AppColors.inkSoft)),
          const SizedBox(height: 18),
          _FieldLabel(icon: AppIcons.person, text: t('login_username_label')),
          const SizedBox(height: 8),
          Semantics(
            label: t('login_username_label'),
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
              style: Theme.of(context).textTheme.titleMedium,
              decoration: _decoration(),
              onSubmitted: (_) => _passwordFocus.requestFocus(),
            ),
          ),
          const SizedBox(height: 16),
          _FieldLabel(icon: AppIcons.lock, text: t('login_password_label')),
          const SizedBox(height: 8),
          Semantics(
            label: t('login_password_label'),
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
              style: Theme.of(context).textTheme.titleMedium,
              // The eye sits inside the box, at its right end.
              decoration: _decoration().copyWith(
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 4),
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
                suffixIconConstraints: const BoxConstraints(minWidth: 60, minHeight: Dimens.minTouch),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
          // Only against a real server: which PC or server the test phone talks to (never shown with the demo mock).
          if (!ref.watch(appConfigProvider).useMockApi) _ServerLink(enabled: !_busy),
        ],
      ),
      bottomRight: TickButton(
        key: const ValueKey('login-submit'),
        size: 64,
        showLabel: true,
        semanticLabel: t('a11y_login'),
        onPressed: _busy ? null : _submit,
      ),
    );
  }

  InputDecoration _decoration() => InputDecoration(
    counterText: '',
    filled: true,
    fillColor: AppColors.card,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.line, width: 2),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFC9D3C6), width: 2),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.green, width: 3),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.line, width: 2),
    ),
  );
}

/// A picture and a word above a field.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Row(
      children: [
        Icon(icon, size: 26, color: AppColors.green),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
      ],
    ),
  );
}

/// A small link under the login fields: opens a dialog to type the server address (`http://<PC address>:8000`).
class _ServerLink extends ConsumerWidget {
  const _ServerLink({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final url = ref.watch(apiBaseUrlProvider);
    final small = Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextButton(
        key: const ValueKey('server-link'),
        style: TextButton.styleFrom(
          minimumSize: const Size(64, 56),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          foregroundColor: AppColors.inkSoft,
        ),
        onPressed: enabled ? () => showServerDialog(context, ref) : null,
        child: Row(
          children: [
            const Icon(Icons.dns_rounded, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${t('login_server')}: $url', overflow: TextOverflow.ellipsis, maxLines: 1, style: small),
            ),
            const SizedBox(width: 8),
            Text(
              t('login_server_change'),
              style: small?.copyWith(color: AppColors.blue, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// The FarmTrack mark in the top bar: a leaf on a deep-green tile and the name.
class _Logo extends StatelessWidget {
  const _Logo({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(14)),
          child: const Icon(AppIcons.leaf, size: 26, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Text(name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      ],
    ),
  );
}

/// Green hills with a few apple trees and a sun: the login picture (drawn, so it costs no download).
class _HillsPainter extends CustomPainter {
  const _HillsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.greenSoft);
    canvas.drawCircle(Offset(w * 0.77, h * 0.32), h * 0.15, Paint()..color = const Color(0xFFF2C94C));
    final far = Path()
      ..moveTo(0, h * 0.73)
      ..cubicTo(w * 0.17, h * 0.47, w * 0.31, h * 0.47, w * 0.49, h * 0.67)
      ..cubicTo(w * 0.66, h * 0.82, w * 0.83, h * 0.55, w, h * 0.63)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(far, Paint()..color = const Color(0xFF9CCFA8));
    final near = Path()
      ..moveTo(0, h * 0.87)
      ..cubicTo(w * 0.2, h * 0.67, w * 0.4, h * 0.73, w * 0.57, h * 0.83)
      ..cubicTo(w * 0.74, h * 0.92, w * 0.86, h * 0.75, w, h * 0.8)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(near, Paint()..color = const Color(0xFF4E9F62));
    final trunk = Paint()..color = const Color(0xFF6B4E2E);
    final crown = Paint()..color = AppColors.green;
    final apple = Paint()..color = AppColors.red;
    for (final (x, y, r) in const [(0.2, 0.64, 0.08), (0.3, 0.61, 0.067), (0.69, 0.65, 0.08)]) {
      final c = Offset(w * x, h * y);
      canvas.drawRect(Rect.fromLTWH(c.dx - 2, c.dy + h * r * 0.6, 4, h * r * 1.1), trunk);
      canvas.drawCircle(c, h * r, crown);
      canvas.drawCircle(c + Offset(-h * r * 0.35, -h * r * 0.2), h * 0.014, apple);
      canvas.drawCircle(c + Offset(h * r * 0.4, h * r * 0.25), h * 0.014, apple);
    }
  }

  @override
  bool shouldRepaint(_HillsPainter oldDelegate) => false;
}
