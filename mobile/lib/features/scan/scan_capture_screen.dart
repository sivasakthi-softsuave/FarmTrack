import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/voice/speak_on_enter.dart';
import '../../core/voice/utterance.dart';
import '../../core/voice/voice_service.dart';
import '../../core/voice/voice_widgets.dart';
import '../../core/widgets/big_buttons.dart';
import '../../core/widgets/demo_clock_banner.dart';
import '../../core/widgets/design.dart';
import 'photo_picker.dart';
import 'scan_flow.dart';

// The dark camera of the mockup (`.phone.dark` and the inline colours of its "Take photos" screen).
const _ground = Color(0xFF0E1510);
const _panel = Color(0xFF0B110D);
const _thumb = Color(0xFF2C6B37);
const _thumbIcon = Color(0xFFBFE5C8);
const _sun = Color(0xFFF2C94C);

/// One huge camera button. Speaks how to hold the phone, then opens the system camera.
///
/// The mockup's "Take photos": a dark full-screen camera with a leaf frame and one tip, the photos taken so far in a strip
/// (red cross removes, plus adds), the gallery, the round shutter and the green tick that sends.
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

  void _back() => context.go(ref.read(scanFlowProvider).photos.isEmpty ? Routes.home : Routes.scanReview);

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final photos = ref.watch(scanFlowProvider.select((s) => s.photos));
    final max = ref.watch(appConfigProvider).maxPhotos;
    final inset = MediaQuery.paddingOf(context).bottom;
    // The camera is a fixed picture, not running text: the words on it keep to 1.3 times so the layout never breaks.
    return PopScope(
      // The phone's own back button does the same as the arrow on screen.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: _ground,
        // The scaffold's own top bar is white; this screen is dark, so it has its own top row (mute and speaker as on the
        // other screens, on glass).
        body: SpeakOnEnter(
          script: promptList(
            _denied
                ? const ['permission_denied_camera']
                : const ['scan_open_camera', 'scan_or_gallery', 'scan_hold_close', 'scan_one_leaf', 'scan_daylight'],
          ),
          owner: _owner,
          restartKey: _denied,
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light,
            child: Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      const DemoClockBanner(),
                      MediaQuery.withClampedTextScaling(
                        maxScaleFactor: 1.3,
                        child: _TopRow(
                          backLabel: t('a11y_back'),
                          title: t('scan_photo_n_of', args: {'n': math.min(photos.length + 1, max), 'max': max}),
                          onBack: _back,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Column(
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: Dimens.gutter),
                            child: VoiceMissingBanner(),
                          ),
                          Expanded(
                            child: MediaQuery.withClampedTextScaling(
                              maxScaleFactor: 1.3,
                              child: _ViewfinderZone(denied: _denied, tip: t('scan_tip_daylight')),
                            ),
                          ),
                        ],
                      ),
                      // The spoken sentence floats at the top: the bottom of the picture belongs to the tip.
                      const Positioned(left: Dimens.gutter, right: Dimens.gutter, top: 8, child: VoiceCaption()),
                    ],
                  ),
                ),
                MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: _panel,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(Dimens.gutter, 0, Dimens.gutter, math.max(26, inset + 10)),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _PhotoStrip(
                            photos: photos,
                            max: max,
                            hint: t('scan_up_to', args: {'max': max}),
                            removeLabel: t('a11y_remove_photo'),
                            addLabel: t('a11y_plus'),
                            onRemove: (i) => ref.read(scanFlowProvider.notifier).removePhotoAt(i),
                            onAdd: _busy ? null : _openCamera,
                          ),
                          const SizedBox(height: 16),
                          _Controls(
                            galleryLabel: t('a11y_gallery'),
                            galleryWord: t('scan_gallery_word'),
                            cameraLabel: t('a11y_camera'),
                            sendLabel: t('a11y_send'),
                            sendWord: t('scan_send_word'),
                            onGallery: _busy ? null : _openGallery,
                            onCamera: _busy ? null : _openCamera,
                            onSend: photos.isEmpty ? null : () => context.go(Routes.scanUploading),
                          ),
                        ],
                      ),
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

/// `row` of the mockup's camera: a glass back button, the centred "Photo 2 of 4" pill, mute and the speaker on glass.
class _TopRow extends StatelessWidget {
  const _TopRow({required this.backLabel, required this.title, required this.onBack});

  final String backLabel;
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 60,
    child: Padding(
      // The round buttons are 48 wide inside 56 wide tap areas, so the row starts 4 dp inside the 16 dp gutter.
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            BigIconButton(
              icon: AppIcons.back,
              semanticLabel: backLabel,
              color: glassButtonColor,
              foreground: Colors.white,
              size: Dimens.minTouch,
              onPressed: onBack,
            ),
            // The pill sits in the middle of the screen when there is room next to the two voice buttons on the right.
            if (constraints.maxWidth >= 352) const SizedBox(width: Dimens.minTouch),
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: AppPill(title, background: glassButtonColor, foreground: Colors.white),
                ),
              ),
            ),
            const MuteButton(onDark: true),
            const SpeakerButton(onDark: true),
          ],
        ),
      ),
    ),
  );
}

/// The picture area: the leaf frame (300 x 340, smaller on a small phone) with the tip pill under it.
class _ViewfinderZone extends StatelessWidget {
  const _ViewfinderZone({required this.denied, required this.tip});

  final bool denied;
  final String tip;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // The frame is centred while the area is tall enough for it plus the tip on both sides; else it sits high.
      final top = constraints.maxHeight >= 440 ? 50.0 : 14.0;
      return Stack(
        children: [
          Positioned.fill(
            child: Padding(
              // 22 on the sides keeps the corner marks, which stick out 6, on the screen.
              padding: EdgeInsets.fromLTRB(22, top, 22, 50),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: _Viewfinder(denied: denied),
                ),
              ),
            ),
          ),
          Positioned(
            left: Dimens.gutter,
            right: Dimens.gutter,
            bottom: 14,
            child: Center(child: _TipPill(tip)),
          ),
        ],
      );
    },
  );
}

/// The frame: dark green, a big leaf with veins and five brown spots (the mockup's SVG), four white corner marks. While the
/// camera is not allowed the leaf is replaced by the red crossed-out camera.
class _Viewfinder extends StatelessWidget {
  const _Viewfinder({required this.denied});

  final bool denied;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 300,
    height: 340,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: ExcludeSemantics(
            child: CustomPaint(painter: _FramePainter(leaf: !denied)),
          ),
        ),
        if (denied)
          Center(
            child: Container(
              width: 120,
              height: 120,
              decoration: const BoxDecoration(color: AppColors.redSoft, shape: BoxShape.circle),
              child: const Icon(AppIcons.cameraOff, size: 72, color: AppColors.red, key: ValueKey('camera-denied')),
            ),
          ),
        const Positioned(
          left: -6,
          top: -6,
          right: -6,
          bottom: -6,
          child: ExcludeSemantics(child: CustomPaint(painter: _CornerPainter())),
        ),
      ],
    ),
  );
}

/// The mockup's inline SVG (viewBox 300 x 340), drawn in its own units and scaled to the box.
class _FramePainter extends CustomPainter {
  const _FramePainter({required this.leaf});

  final bool leaf;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 300, size.height / 340);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 300, 340), const Radius.circular(24)),
      Paint()..color = const Color(0xFF16261A),
    );
    if (!leaf) return;
    canvas.drawPath(
      Path()
        ..moveTo(150, 40)
        ..cubicTo(230, 80, 250, 190, 160, 300)
        ..cubicTo(70, 250, 50, 120, 150, 40)
        ..close(),
      Paint()..color = const Color(0xFF3E8E4A),
    );
    final vein = Paint()
      ..color = const Color(0xFF2C6B37)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawLine(const Offset(150, 52), const Offset(158, 296), vein);
    vein.strokeWidth = 2.5;
    for (final (a, b) in const [
      (Offset(152, 120), Offset(205, 95)),
      (Offset(154, 170), Offset(218, 150)),
      (Offset(156, 220), Offset(205, 215)),
      (Offset(151, 140), Offset(100, 115)),
      (Offset(153, 195), Offset(90, 175)),
      (Offset(155, 245), Offset(110, 240)),
    ]) {
      canvas.drawLine(a, b, vein);
    }
    final spot = Paint()..color = const Color(0xE65B4630); // #5B4630 at 90 %
    for (final (x, y, r) in const [
      (190.0, 130.0, 9.0),
      (120.0, 160.0, 7.0),
      (175.0, 200.0, 11.0),
      (125.0, 225.0, 6.0),
      (200.0, 175.0, 5.0),
    ]) {
      canvas.drawCircle(Offset(x, y), r, spot);
    }
  }

  @override
  bool shouldRepaint(_FramePainter oldDelegate) => oldDelegate.leaf != leaf;
}

/// The four white corner marks: 44 x 44 boxes, a 5 px line, outer radius 14, sticking out 6 px (the box is 312 x 352).
class _CornerPainter extends CustomPainter {
  const _CornerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    // The line runs in the middle of its 5 px, so the 14 px outer radius is 11.5 px on the line.
    final corner = Path()
      ..moveTo(2.5, 44)
      ..lineTo(2.5, 14)
      ..arcTo(const Rect.fromLTWH(2.5, 2.5, 23, 23), math.pi, math.pi / 2, false)
      ..lineTo(44, 2.5);
    for (final (dx, dy, sx, sy) in [
      (0.0, 0.0, 1.0, 1.0),
      (size.width, 0.0, -1.0, 1.0),
      (0.0, size.height, 1.0, -1.0),
      (size.width, size.height, -1.0, -1.0),
    ]) {
      canvas
        ..save()
        ..translate(dx, dy)
        ..scale(sx, sy)
        ..drawPath(corner, line)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_CornerPainter oldDelegate) => false;
}

/// "Take the photo in daylight.": a dark glass pill, 36 high, with a yellow sun.
class _TipPill extends StatelessWidget {
  const _TipPill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(color: const Color(0x80000000), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(AppIcons.sun, size: 20, color: _sun),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppText.pill.copyWith(fontSize: 14, color: Colors.white),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The thumbnail strip: the photos taken (60 px tiles, a red cross at the corner removes one), a dashed plus tile while there
/// is room, and "up to 4 photos" at the right.
class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({
    required this.photos,
    required this.max,
    required this.hint,
    required this.removeLabel,
    required this.addLabel,
    required this.onRemove,
    required this.onAdd,
  });

  final List<String> photos;
  final int max;
  final String hint;
  final String removeLabel;
  final String addLabel;
  final ValueChanged<int> onRemove;
  final VoidCallback? onAdd;

  static const _tile = 60.0;
  static const _gap = 10.0;

  /// The panel's 14 px top padding lives in the strip, so the corner crosses can be tapped where they stick out.
  static const _top = 14.0;

  @override
  Widget build(BuildContext context) {
    final slots = photos.length + (photos.length < max ? 1 : 0);
    final used = slots * (_tile + _gap);
    return SizedBox(
      height: _top + _tile,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            for (var i = 0; i < photos.length; i++)
              Positioned(
                left: i * (_tile + _gap),
                top: _top,
                child: _PhotoTile(key: ValueKey('strip-photo-$i'), path: photos[i]),
              ),
            // The red cross is drawn 26 px at the tile's top right corner; its tap area is 56 x 56 (down and to the
            // right as far as the gap allows) so a thumb finds it without a tile being a button.
            for (var i = 0; i < photos.length; i++)
              Positioned(
                left: i * (_tile + _gap) + _tile - 18,
                top: 0,
                width: Dimens.minTouch,
                height: Dimens.minTouch,
                child: _RemoveBadge(key: ValueKey('strip-remove-$i'), label: removeLabel, onPressed: () => onRemove(i)),
              ),
            if (photos.length < max)
              Positioned(
                left: photos.length * (_tile + _gap),
                top: _top,
                child: _AddTile(label: addLabel, onPressed: onAdd),
              ),
            if (constraints.maxWidth - used >= 64)
              Positioned(
                left: used,
                right: 0,
                top: _top,
                height: _tile,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(
                      hint,
                      style: TextStyle(fontSize: isDevanagari(hint) ? 14 : 13, color: const Color(0xBFFFFFFF)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A photo of the scan as a 60 px tile: the green leaf tile of the mockup until (or instead of) the picture itself.
class _PhotoTile extends StatelessWidget {
  const _PhotoTile({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: _PhotoStrip._tile,
      height: _PhotoStrip._tile,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: _thumb, borderRadius: BorderRadius.circular(Dimens.radiusSmall)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Center(child: Icon(AppIcons.leaf, size: 30, color: _thumbIcon)),
          Image.file(
            File(path),
            fit: BoxFit.cover,
            cacheWidth: 120,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    ),
  );
}

/// The red 26 px cross of a tile, with a 2 px border in the colour of the panel.
class _RemoveBadge extends StatelessWidget {
  const _RemoveBadge({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        onTap: () {
          Haptics.tap();
          onPressed();
        },
        // Badge top = tile top - 8; the tap area starts 14 above the tile.
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(top: _PhotoStrip._top - 8),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: AppColors.red,
                shape: BoxShape.circle,
                border: Border.all(color: _panel, width: 2),
              ),
              child: const Icon(AppIcons.crossBold, size: 14, color: Colors.white),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The dashed plus tile: take one more photo.
class _AddTile extends StatelessWidget {
  const _AddTile({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    key: const ValueKey('strip-add'),
    button: true,
    enabled: onPressed != null,
    label: label,
    excludeSemantics: true,
    child: Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(Dimens.radiusSmall),
          onTap: onPressed == null
              ? null
              : () {
                  Haptics.tap();
                  onPressed!();
                },
          child: CustomPaint(
            painter: const _DashedBoxPainter(),
            child: const SizedBox(
              width: _PhotoStrip._tile,
              height: _PhotoStrip._tile,
              child: Icon(AppIcons.plus, size: 30, color: Colors.white),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A 2 px dashed line (white at 35 %) round a 60 px box with radius 14, drawn inside the box as a CSS border is.
class _DashedBoxPainter extends CustomPainter {
  const _DashedBoxPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius((Offset.zero & size).deflate(1), const Radius.circular(Dimens.radiusSmall - 1)),
      );
    final paint = Paint()
      ..color = const Color(0x59FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final PathMetric metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 10) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 6, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBoxPainter oldDelegate) => false;
}

/// Gallery on the left, the round shutter in the middle, the green send tick on the right.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.galleryLabel,
    required this.galleryWord,
    required this.cameraLabel,
    required this.sendLabel,
    required this.sendWord,
    required this.onGallery,
    required this.onCamera,
    required this.onSend,
  });

  final String galleryLabel;
  final String galleryWord;
  final String cameraLabel;
  final String sendLabel;
  final String sendWord;
  final VoidCallback? onGallery;
  final VoidCallback? onCamera;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _LabelledButton(
          word: galleryWord,
          child: _RoundButton(
            key: const ValueKey('gallery-button'),
            icon: AppIcons.gallery,
            iconSize: 24,
            fill: glassButtonColor,
            semanticLabel: galleryLabel,
            onPressed: onGallery,
          ),
        ),
        _Shutter(key: const ValueKey('camera-button'), semanticLabel: cameraLabel, onPressed: onCamera),
        _LabelledButton(
          word: sendWord,
          child: _RoundButton(
            key: const ValueKey('send-photos'),
            icon: AppIcons.tickBold,
            iconSize: 30,
            fill: AppColors.green,
            semanticLabel: sendLabel,
            onPressed: onSend,
          ),
        ),
      ],
    ),
  );
}

/// A control with its small word under it (12.5 px at 85 %). The word is not a button: the circle above it is.
class _LabelledButton extends StatelessWidget {
  const _LabelledButton({required this.word, required this.child});

  final String word;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      child,
      const SizedBox(height: 4),
      SizedBox(
        width: 72,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          // Devanagari is set one point bigger, as the mockup's Hindi labels are.
          child: Text(
            word,
            style: TextStyle(fontSize: isDevanagari(word) ? 13.5 : 12.5, color: const Color(0xD9FFFFFF)),
          ),
        ),
      ),
    ],
  );
}

/// A 56 px round button (the mockup draws these at 56, not 48): glass for the gallery, green for send. It dims while off.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.icon,
    required this.iconSize,
    required this.fill,
    required this.semanticLabel,
    required this.onPressed,
  });

  final IconData icon;
  final double iconSize;
  final Color fill;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onPressed != null,
    label: semanticLabel,
    excludeSemantics: true,
    child: Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: Material(
        color: fill,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed == null
              ? null
              : () {
                  Haptics.tap();
                  onPressed!();
                },
          child: SizedBox(
            width: Dimens.minTouch,
            height: Dimens.minTouch,
            child: Icon(icon, size: iconSize, color: Colors.white),
          ),
        ),
      ),
    ),
  );
}

/// The shutter: an 88 px ring (5 px white line) round a 68 px white disc.
class _Shutter extends StatelessWidget {
  const _Shutter({super.key, required this.semanticLabel, required this.onPressed});

  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onPressed != null,
    label: semanticLabel,
    excludeSemantics: true,
    child: Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed == null
              ? null
              : () {
                  Haptics.tap();
                  onPressed!();
                },
          child: Container(
            width: 88,
            height: 88,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 5),
            ),
            child: Container(
              width: 68,
              height: 68,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    ),
  );
}
