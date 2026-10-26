import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/api_exception.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../voice/utterance.dart';
import 'big_buttons.dart';
import 'voice_scaffold.dart';

/// Prompt id to speak for a failed API call: "no internet" for connection problems, "try again" otherwise.
String errorPromptFor(Object error) =>
    error is ApiException && error.isConnectionProblem ? 'error_no_internet' : 'error_try_again';

/// A full error screen that is never a dead end: it speaks, and offers one big retry button.
class ErrorRetryScreen extends ConsumerWidget {
  const ErrorRetryScreen({super.key, required this.error, required this.onRetry, this.onBack});

  final Object error;
  final VoidCallback onRetry;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final connection = error is ApiException && (error as ApiException).isConnectionProblem;
    return VoiceScaffold(
      script: promptList([errorPromptFor(error)]),
      onBack: onBack,
      showBack: onBack != null,
      body: Container(
        width: 168,
        height: 168,
        decoration: BoxDecoration(
          color: connection ? AppColors.neutralSoft : AppColors.amberSoft,
          shape: BoxShape.circle,
        ),
        child: Icon(
          connection ? AppIcons.offline : AppIcons.warning,
          size: 96,
          color: connection ? AppColors.inkSoft : AppColors.amberDark,
        ),
      ),
      bottomRight: BigIconButton(
        key: const ValueKey('retry-button'),
        icon: AppIcons.roundArrow,
        semanticLabel: t('a11y_retry'),
        size: 112,
        onPressed: onRetry,
      ),
    );
  }
}

/// A picture, a progress bar and a cancel cross: used while photos upload and while the server thinks.
class ProcessingBody extends StatelessWidget {
  const ProcessingBody({
    super.key,
    required this.icon,
    required this.label,
    this.progress,
    this.onCancel,
    this.cancelLabel = '',
  });

  final IconData icon;
  final String label;

  /// 0 to 1 while uploading; null for an endless bar.
  final double? progress;
  final VoidCallback? onCancel;
  final String cancelLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The picture in a white circle inside a turning green ring.
        SizedBox(
          width: 168,
          height: 168,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const SizedBox.expand(
                child: CircularProgressIndicator(strokeWidth: 10, backgroundColor: Color(0xFFDCE7DD)),
              ),
              Container(
                width: 132,
                height: 132,
                decoration: _ringCentre,
                child: Icon(icon, size: 64, color: AppColors.green),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 20),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(key: const ValueKey('progress'), value: progress, minHeight: 12),
        ),
        if (onCancel != null) ...[
          const SizedBox(height: 20),
          CrossButton(key: const ValueKey('cancel-button'), onPressed: onCancel, semanticLabel: cancelLabel, size: 72),
        ],
      ],
    );
  }
}

const _ringCentre = BoxDecoration(color: AppColors.card, shape: BoxShape.circle, boxShadow: AppDecor.shadows);
