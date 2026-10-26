import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/utils/haptics.dart';
import '../../core/voice/utterance.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/status_views.dart';
import '../../core/widgets/voice_scaffold.dart';
import '../../core/theme/app_theme.dart';
import 'scan_flow.dart';

/// Sends the photos (or the confirmed crop) and waits for the server's answer, then routes by its status.
///
/// With [confirmCropId] null it uploads the photos; otherwise it posts the crop the farmer ticked or chose.
class ProcessingScreen extends ConsumerStatefulWidget {
  const ProcessingScreen({super.key, this.confirmCropId});

  final String? confirmCropId;

  @override
  ConsumerState<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends ConsumerState<ProcessingScreen> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (!mounted) return;
    _started = true;
    final flow = ref.read(scanFlowProvider.notifier);
    final cropId = widget.confirmCropId;
    final current = ref.read(scanFlowProvider);
    if (cropId == null ? current.photos.isEmpty : current.scan == null) {
      // Opened without anything to send (for example after the app restarted): start from the beginning.
      context.go(cropId == null ? Routes.scan : Routes.home);
      return;
    }
    final scan = cropId == null ? await flow.submit() : await flow.confirmCrop(cropId);
    if (!mounted) return;
    if (scan == null) {
      if (ref.read(scanFlowProvider).phase == ScanPhase.queued) {
        // No internet: the photos are saved in the offline queue and will be sent later.
        Haptics.success();
        context.go(Routes.scanSaved);
        return;
      }
      // Failed or cancelled: the build method shows the error screen or the cancel already navigated.
      Haptics.error();
      return;
    }
    Haptics.success();
    context.go(routeForScan(scan));
  }

  void _cancel() {
    ref.read(scanFlowProvider.notifier).cancel();
    context.go(widget.confirmCropId == null ? Routes.scanReview : Routes.scanConfirm);
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(scanFlowProvider);
    final t = ref.watch(stringsProvider);
    final lang = ref.watch(languageProvider);
    final resources = ref.watch(resourcesProvider);
    final uploading = widget.confirmCropId == null;

    if (_started && flow.phase == ScanPhase.failed && flow.error != null) {
      return ErrorRetryScreen(error: flow.error!, onRetry: _run, onBack: _cancel);
    }

    // The four steps of the mockup, from what the app really knows: the photos are going up (step 1), the server is
    // looking at them (2: finding the crop), the crop is settled and the server looks for the disease (3). Choosing the
    // medicine (4) is part of the answer that ends this screen, so it never starts here.
    final looking = uploading && flow.phase == ScanPhase.analysing;
    final done = uploading ? (looking ? 1 : 0) : 2;
    final upload = uploading && flow.phase == ScanPhase.uploading && flow.progress > 0 ? flow.progress : null;
    final cropId = widget.confirmCropId;
    final steps = [
      _Step(t(done >= 1 ? 'step_photos_sent' : 'uploading')),
      _Step(
        t(done >= 2 ? 'step_crop_found' : 'step_finding_crop'),
        pill: done >= 2 && cropId != null ? resources.cropName(cropId, lang) : null,
      ),
      _Step(t('step_finding_disease')),
      _Step(t('step_choosing_medicine')),
    ];

    return VoiceScaffold(
      showBack: false,
      onBack: _cancel,
      flatTopBar: true,
      alignTop: true,
      // The mockup's row is 56 high and its content starts 10 below it; the bar is 64 high.
      bodyPadding: const EdgeInsets.fromLTRB(Dimens.gutter, 2, Dimens.gutter, 0),
      script: promptList(uploading ? const ['scan_uploading', 'scan_wait'] : const ['scan_wait']),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: _ProgressRing(value: (done + (upload ?? 1 / 6)) / steps.length)),
          const SizedBox(height: 18),
          // The big words stay the same all the way (the mockup's title); the first step says "Sending photos" meanwhile.
          // The mockup sets no line height here, so the font's own (1.36) applies, not the 1.2 of the result titles.
          Text(t('analysing'), textAlign: TextAlign.center, style: AppText.big.copyWith(height: 1.36)),
          const SizedBox(height: 6),
          Text(
            t('scan_wait_subtitle'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: AppColors.inkSoft, height: 1.35),
          ),
          const SizedBox(height: 18),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(
              children: [
                for (var i = 0; i < steps.length; i++)
                  _StepRow(
                    step: steps[i],
                    state: i < done
                        ? _StepState.done
                        : i == done
                        ? _StepState.current
                        : _StepState.pending,
                    first: i == 0,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          // Not in the mockup, but the farmer must always be able to stop a slow upload.
          AppButton(
            key: const ValueKey('cancel-button'),
            style: AppButtonStyle.outline,
            icon: AppIcons.cross,
            label: t('a11y_cancel'),
            semanticLabel: t('a11y_cancel'),
            onPressed: _cancel,
          ),
        ],
      ),
    );
  }
}

class _Step {
  const _Step(this.label, {this.pill});

  final String label;

  /// The crop's name, shown at the right of the "Crop found" row.
  final String? pill;
}

enum _StepState { done, current, pending }

/// One of the four rows of the card: a 34 px marker (tick, spinner or dashed ring) and the step's name, 58 high.
class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.state, required this.first});

  final _Step step;
  final _StepState state;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final pending = state == _StepState.pending;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: first ? null : const Border(top: BorderSide(color: AppColors.line)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 58),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              switch (state) {
                _StepState.done => const IconDot(
                  AppIcons.tickBold,
                  background: AppColors.green,
                  foreground: Colors.white,
                  size: 34,
                  round: true,
                  iconSize: 20,
                ),
                _StepState.current => const _StepSpinner(),
                _StepState.pending => const ExcludeSemantics(
                  child: SizedBox(width: 34, height: 34, child: CustomPaint(painter: _DashedRingPainter())),
                ),
              },
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  step.label,
                  style: pending
                      ? const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.inkSoft)
                      : AppText.hName.copyWith(fontSize: 16),
                ),
              ),
              if (step.pill != null) ...[
                const SizedBox(width: 12),
                AppPill(step.pill!, background: AppColors.greenSoft, foreground: AppColors.green),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The 180 px progress ring of the mockup: a 12 px track, a green arc from the top with round ends, and a white disc with
/// the thin leaf in the middle. The arc grows as steps finish (and with the upload, while photos go up).
class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.value});

  /// 0 to 1.
  final double value;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return ExcludeSemantics(
      child: SizedBox(
        key: const ValueKey('progress'),
        width: 180,
        height: 180,
        child: Stack(
          alignment: Alignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(end: value.clamp(0.0, 1.0)),
              duration: still ? Duration.zero : const Duration(milliseconds: 500),
              curve: Curves.easeOut,
              builder: (context, v, _) => CustomPaint(size: const Size(180, 180), painter: _RingPainter(v)),
            ),
            Container(
              width: 128,
              height: 128,
              decoration: const BoxDecoration(
                color: AppColors.card,
                shape: BoxShape.circle,
                boxShadow: AppDecor.shadows,
              ),
              child: const Icon(AppIcons.leafThin, size: 60, color: AppColors.green),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.value);

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    // The mockup's circle: r 80 and a 12 px line in a 180 box.
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: 80);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, line..color = AppColors.track);
    if (value > 0) canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * value, false, line..color = AppColors.green);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => oldDelegate.value != value;
}

/// The marker of the step that is going on: a 34 px circle with a 3 px green line and a light-grey right side. It turns
/// slowly, and stands still when the phone asks for no animations.
class _StepSpinner extends StatefulWidget {
  const _StepSpinner();

  @override
  State<_StepSpinner> createState() => _StepSpinnerState();
}

class _StepSpinnerState extends State<_StepSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _turn.stop();
    } else if (!_turn.isAnimating) {
      _turn.repeat();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RotationTransition(
      key: const ValueKey('step-spinner'),
      turns: _turn,
      child: const SizedBox(width: 34, height: 34, child: CustomPaint(painter: _SpinnerPainter())),
    ),
  );
}

class _SpinnerPainter extends CustomPainter {
  const _SpinnerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // `border: 3px solid green; border-right-color: #DCE7DD`: the right quarter (between the diagonals) is grey.
    final rect = (Offset.zero & size).deflate(1.5);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas
      ..drawArc(rect, 0, math.pi * 2, false, line..color = AppColors.green)
      ..drawArc(rect, -math.pi / 4, math.pi / 2, false, line..color = AppColors.track);
  }

  @override
  bool shouldRepaint(_SpinnerPainter oldDelegate) => false;
}

/// The marker of a step that has not started: a 2 px dashed ring (#B9C4BB).
class _DashedRingPainter extends CustomPainter {
  const _DashedRingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1);
    final line = Paint()
      ..color = AppColors.dashed
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    const dashes = 12;
    const step = math.pi * 2 / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect, i * step, step * 0.58, false, line);
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter oldDelegate) => false;
}
