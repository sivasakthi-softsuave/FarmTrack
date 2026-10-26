import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/voice/utterance.dart';
import '../../core/voice/voice_service.dart';
import '../../core/widgets/big_buttons.dart';
import '../../core/widgets/voice_scaffold.dart';
import 'photo_picker.dart';
import 'scan_flow.dart';

/// One huge camera button. Speaks how to hold the phone, then opens the system camera.
class ScanCaptureScreen extends ConsumerStatefulWidget {
  const ScanCaptureScreen({super.key});

  @override
  ConsumerState<ScanCaptureScreen> createState() => _ScanCaptureScreenState();
}

class _ScanCaptureScreenState extends ConsumerState<ScanCaptureScreen> {
  final Object _owner = Object();
  bool _denied = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recoverLostPhoto());
  }

  Future<void> _say(List<String> ids) => ref.read(voiceServiceProvider).speakPrompts(ids, owner: _owner);

  Future<void> _recoverLostPhoto() async {
    final path = await ref.read(photoPickerProvider).recoverLostPhoto();
    if (path == null || !mounted) return;
    ref.read(scanFlowProvider.notifier).addPhoto(path);
    context.go(Routes.scanReview);
  }

  Future<void> _openCamera() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final settings = ref.read(settingsProvider);
      if (!settings.cameraExplained) {
        // "The phone will ask to use the camera: tap the button that allows it."
        await ref.read(settingsProvider.notifier).markCameraExplained();
        await _say(const ['camera_permission']);
      }
      final path = await ref.read(photoPickerProvider).takePhoto();
      if (!mounted) return;
      if (_denied) setState(() => _denied = false);
      if (path == null) return;
      if (ref.read(scanFlowProvider.notifier).addPhoto(path)) Haptics.success();
      if (mounted) context.go(Routes.scanReview);
    } on CameraPermissionDenied {
      Haptics.error();
      if (mounted) setState(() => _denied = true);
    } catch (_) {
      Haptics.error();
      await _say(const ['error_try_again']);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Photos that are already in the phone: the system picker, as many as still fit in this scan.
  Future<void> _openGallery() async {
    if (_busy) return;
    final flow = ref.read(scanFlowProvider.notifier);
    final room = flow.maxPhotos - ref.read(scanFlowProvider).photos.length;
    if (room <= 0) {
      await _say(const ['scan_photo_limit']);
      return;
    }
    setState(() => _busy = true);
    try {
      final paths = await ref.read(photoPickerProvider).pickFromGallery(limit: room);
      if (!mounted) return;
      if (_denied) setState(() => _denied = false);
      if (paths.isEmpty) return;
      var added = false;
      for (final path in paths) {
        added = flow.addPhoto(path) || added;
      }
      if (added) Haptics.success();
      if (mounted) context.go(Routes.scanReview);
    } catch (_) {
      Haptics.error();
      await _say(const ['error_try_again']);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    return VoiceScaffold(
      owner: _owner,
      script: promptList(
        _denied
            ? const ['permission_denied_camera']
            : const ['scan_open_camera', 'scan_or_gallery', 'scan_hold_close', 'scan_one_leaf', 'scan_daylight'],
      ),
      restartKey: _denied,
      onBack: () => context.go(ref.read(scanFlowProvider).photos.isEmpty ? Routes.home : Routes.scanReview),
      alignTop: true,
      // A dark "viewfinder" with a leaf in its frame and one tip, then the gallery and the big round camera button
      // (it opens the phone's own camera).
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_denied) ...[
            const Icon(Icons.no_photography_rounded, size: 72, color: AppColors.red, key: ValueKey('camera-denied')),
            const SizedBox(height: 16),
          ],
          _Viewfinder(tip: t('scan_tip')),
          const SizedBox(height: 18),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                BigIconButton(
                  key: const ValueKey('gallery-button'),
                  icon: AppIcons.gallery,
                  semanticLabel: t('a11y_gallery'),
                  size: 64,
                  color: AppColors.card,
                  foreground: AppColors.ink,
                  onPressed: _busy ? null : _openGallery,
                ),
                const SizedBox(width: 36),
                BigIconButton(
                  key: const ValueKey('camera-button'),
                  icon: AppIcons.camera,
                  semanticLabel: t('a11y_camera'),
                  size: 104,
                  onPressed: _busy ? null : _openCamera,
                ),
                // Keeps the camera in the middle.
                const SizedBox(width: 100),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The dark picture frame of the camera page: a leaf with spots inside four white corners, and one tip under it.
class _Viewfinder extends StatelessWidget {
  const _Viewfinder({required this.tip});

  final String tip;

  @override
  Widget build(BuildContext context) {
    final height = (MediaQuery.sizeOf(context).height * 0.42).clamp(200.0, 360.0);
    // The tip keeps to two lines at any text size, so the picture keeps its room.
    return MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: _frame(context, height));
  }

  Widget _frame(BuildContext context, double height) {
    return ExcludeSemantics(
      child: Container(
        height: height,
        decoration: BoxDecoration(color: const Color(0xFF0E1510), borderRadius: BorderRadius.circular(28)),
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
                child: CustomPaint(painter: const _LeafFramePainter(), child: const SizedBox.expand()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: const Color(0x66000000), borderRadius: BorderRadius.circular(999)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wb_sunny_rounded, size: 20, color: Color(0xFFF2C94C)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        tip,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A leaf with brown spots and four white corner marks around it.
class _LeafFramePainter extends CustomPainter {
  const _LeafFramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final frame = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(20));
    canvas.drawRRect(frame, Paint()..color = const Color(0xFF16261A));
    // The leaf, centred, about two thirds of the frame.
    final cx = w / 2;
    final top = h * 0.12;
    final bottom = h * 0.88;
    final half = (h * 0.3).clamp(0.0, w * 0.32);
    final leaf = Path()
      ..moveTo(cx, top)
      ..cubicTo(cx + half * 1.5, top + h * 0.15, cx + half * 1.1, bottom - h * 0.2, cx + half * 0.1, bottom)
      ..cubicTo(cx - half * 1.2, bottom - h * 0.18, cx - half * 1.4, top + h * 0.2, cx, top)
      ..close();
    canvas.drawPath(leaf, Paint()..color = const Color(0xFF3E8E4A));
    final vein = Paint()
      ..color = const Color(0xFF2C6B37)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(cx, top + 6), Offset(cx + half * 0.08, bottom - 4), vein);
    vein.strokeWidth = 2;
    for (final f in const [0.3, 0.45, 0.6, 0.75]) {
      final y = top + (bottom - top) * f;
      canvas.drawLine(Offset(cx, y), Offset(cx + half * 0.7, y - h * 0.07), vein);
      canvas.drawLine(Offset(cx, y + h * 0.03), Offset(cx - half * 0.7, y - h * 0.04), vein);
    }
    final spot = Paint()..color = const Color(0xE65B4630);
    for (final (dx, dy, r) in const [(0.35, 0.33, 0.035), (-0.4, 0.45, 0.028), (0.2, 0.6, 0.04), (-0.3, 0.72, 0.024)]) {
      canvas.drawCircle(Offset(cx + half * dx * 1.4, top + (bottom - top) * dy), h * r, spot);
    }
    // Four white corners.
    final corner = Paint()
      ..color = Colors.white
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const len = 34.0;
    const inset = 2.5;
    final corners = [
      (inset, inset, 1.0, 1.0),
      (w - inset, inset, -1.0, 1.0),
      (inset, h - inset, 1.0, -1.0),
      (w - inset, h - inset, -1.0, -1.0),
    ];
    for (final (x, y, sx, sy) in corners) {
      canvas.drawLine(Offset(x, y), Offset(x + len * sx, y), corner);
      canvas.drawLine(Offset(x, y), Offset(x, y + len * sy), corner);
    }
  }

  @override
  bool shouldRepaint(_LeafFramePainter oldDelegate) => false;
}
