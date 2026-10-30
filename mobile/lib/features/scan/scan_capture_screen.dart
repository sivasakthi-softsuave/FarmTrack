import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/voice/speak_on_enter.dart';
import '../../core/voice/utterance.dart';
import '../../core/voice/voice_service.dart';
import '../../core/voice/voice_widgets.dart';
import '../../core/widgets/demo_clock_banner.dart';
import 'capture_design_a.dart';
import 'capture_design_b.dart';
import 'capture_widgets.dart';
import 'photo_picker.dart';
import 'scan_flow.dart';

/// One huge camera button. Speaks how to hold the phone, then opens the system camera.
///
/// The mockup's "Take photos": a dark full-screen camera with a leaf frame and the tips, the photos taken so far in a strip
/// (red cross removes, plus adds), the gallery, the round shutter and the green tick that sends. It has two looks that the
/// owner compares on a phone ([CaptureDesign], chosen in Settings): A keeps the frame and puts the three tips under it as
/// chips; B makes the whole screen the viewfinder. Both do exactly the same things; only [build] differs.
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
    final design = ref.watch(settingsProvider.select((s) => s.captureDesign));
    final b = design == CaptureDesign.b;
    final inset = MediaQuery.paddingOf(context).bottom;

    final strip = PhotoStrip(
      photos: photos,
      max: max,
      centered: b,
      hint: t('scan_up_to', args: {'max': max}),
      countWord: t('scan_photos_word'),
      removeLabel: t('a11y_remove_photo'),
      addLabel: t('a11y_plus'),
      onRemove: (i) => ref.read(scanFlowProvider.notifier).removePhotoAt(i),
      onAdd: _busy ? null : _openCamera,
    );
    final controls = CaptureControls(
      galleryLabel: t('a11y_gallery'),
      galleryWord: t('scan_gallery_word'),
      cameraLabel: t('a11y_camera'),
      sendLabel: t('a11y_send'),
      sendWord: t('scan_send_word'),
      onGallery: _busy ? null : _openGallery,
      onCamera: _busy ? null : _openCamera,
      onSend: photos.isEmpty ? null : () => context.go(Routes.scanUploading),
    );

    final content = Column(
      children: [
        SafeArea(
          bottom: false,
          child: Column(
            children: [
              const DemoClockBanner(),
              // The camera is a fixed picture, not running text: the words on it keep to 1.3 times so the layout never breaks.
              MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: CaptureTopRow(
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
                      child: b ? CaptureViewB(denied: _denied) : CaptureViewA(owner: _owner, denied: _denied),
                    ),
                  ),
                ],
              ),
              // The spoken sentence floats at the top: the bottom of the picture belongs to the tips.
              const Positioned(left: Dimens.gutter, right: Dimens.gutter, top: 8, child: VoiceCaption()),
            ],
          ),
        ),
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: b
              ? DecoratedBox(
                  // No solid panel: the controls sit on a fade from the picture to the dark.
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x000B110D), Color(0xEE0B110D), Color(0xEE0B110D)],
                      stops: [0, 0.34, 1],
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(Dimens.gutter, 16, Dimens.gutter, math.max(22, inset + 10)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [strip, const SizedBox(height: 8), controls],
                    ),
                  ),
                )
              : DecoratedBox(
                  decoration: const BoxDecoration(
                    color: CaptureColors.panel,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(Dimens.gutter, 0, Dimens.gutter, math.max(26, inset + 10)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [strip, const SizedBox(height: 16), controls],
                    ),
                  ),
                ),
        ),
      ],
    );

    return PopScope(
      // The phone's own back button does the same as the arrow on screen.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: CaptureColors.ground,
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
            child: b
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      const Positioned.fill(child: CaptureBackdropB()),
                      content,
                    ],
                  )
                : content,
          ),
        ),
      ),
    );
  }
}
