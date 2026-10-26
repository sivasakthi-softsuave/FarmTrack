import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/design.dart';
import '../auth/auth_widgets.dart';

/// Checks the saved login and the onboarding flag, then moves on. Silent: no language is known yet.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  /// What the start is doing now: shown (small) if it takes long, so a stuck start can be read off the screen.
  String _step = 'starting';
  String? _error;
  bool _slow = false;
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    _watchdog = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _slow = true);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (mounted && _error != null) setState(() => _error = null);
    try {
      _step = 'reading the saved login';
      try {
        // Never wait for ever on the phone's key store: no answer means "not logged in".
        await ref.read(sessionProvider.notifier).restore().timeout(const Duration(seconds: 8));
      } on Object {
        // Continue as logged out; the farmer simply logs in again.
        ref.read(sessionProvider.notifier).assumeLoggedOut();
      }
      if (!mounted) return;
      _step = 'choosing the first screen';
      final settings = ref.read(settingsProvider);
      final session = ref.read(sessionProvider);
      final String target;
      if (settings.language == null) {
        target = Routes.language;
      } else if (!session.isLoggedIn) {
        target = settings.onboardingDone ? Routes.login : Routes.welcome;
      } else {
        target = Routes.home;
      }
      _step = 'opening $target';
      context.go(target);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    // Paper ground, the deep-green brand tile (the login's, bigger) and the name; nothing else unless the start is stuck.
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: BrandTile(size: 112)),
                const SizedBox(height: 20),
                Text(
                  t('app_name'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, height: 1.2, color: AppColors.ink),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 24),
                  AppCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const IconDot(AppIcons.warning, background: AppColors.redSoft, foreground: AppColors.red),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SelectableText(
                                'Start problem: $_error',
                                key: const ValueKey('splash-error'),
                                style: AppText.hMeta.copyWith(color: AppColors.ink),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        AppButton(
                          key: const ValueKey('splash-retry'),
                          icon: AppIcons.roundArrow,
                          label: t('a11y_retry'),
                          semanticLabel: t('a11y_retry'),
                          onPressed: _start,
                        ),
                      ],
                    ),
                  ),
                ] else if (_slow) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Still starting… ($_step)',
                    key: const ValueKey('splash-slow'),
                    textAlign: TextAlign.center,
                    style: AppText.hMeta,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
