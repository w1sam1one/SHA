import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'qr_decoder.dart';

/// The back camera's preview, with its frames read for a QR code
/// (decision 0012 (C1): the `camera` plugin with CameraX, and zxing2).
///
/// The camera runs only while the app is in the foreground: it stops when the
/// app is hidden and starts again when it comes back. No audio is ever
/// recorded (`enableAudio: false`, and RECORD_AUDIO is removed from the
/// manifest).
class QrCamera extends StatefulWidget {
  const QrCamera({
    super.key,
    required this.onCode,
    required this.torch,
    required this.running,
  });

  /// Called with the text of each QR code found.
  final void Function(String code) onCode;

  /// The torch follows this value while the camera runs.
  final ValueNotifier<bool> torch;

  /// Set here: true while the preview runs.
  final ValueNotifier<bool> running;

  @override
  State<QrCamera> createState() => _QrCameraState();
}

enum _Problem { noCamera, permissionDenied, failed }

class _QrCameraState extends State<QrCamera> with WidgetsBindingObserver {
  CameraController? _controller;
  QrFrameReader? _reader;
  _Problem? _problem;
  bool _starting = false;

  /// False while the app is hidden: the camera must not start then.
  bool _inForeground = true;

  /// Bumped by every stop, so that a start that was under way gives up.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.torch.addListener(_applyTorch);
    unawaited(_start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.torch.removeListener(_applyTorch);
    // The parent's notifier is left alone: it is being taken down too.
    _stop(notify: false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      // Not on "inactive": Android's permission dialog makes the app
      // inactive while the camera is being started.
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        _inForeground = false;
        _stop();
        if (mounted) setState(() {});
      case AppLifecycleState.resumed:
        _inForeground = true;
        // Also after a denied camera: the user may have allowed it in the
        // phone's settings meanwhile.
        if (_controller == null) unawaited(_start());
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _start() async {
    if (_starting || _controller != null) return;
    _starting = true;
    final generation = _generation;
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (!mounted || generation != _generation) return;
      final back = cameras
          .where((c) => c.lensDirection == CameraLensDirection.back)
          .firstOrNull;
      final camera = back ?? cameras.firstOrNull;
      if (camera == null) {
        _show(_Problem.noCamera);
        return;
      }
      controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted || generation != _generation) {
        await _close(controller);
        return;
      }
      final reader = QrFrameReader(onCode: widget.onCode);
      await controller.startImageStream((image) {
        // The Y plane: brightness only, which is all a QR code needs.
        final plane = image.planes.first;
        reader.add(
          LuminanceFrame(
            bytes: plane.bytes,
            width: image.width,
            height: image.height,
            bytesPerRow: plane.bytesPerRow,
          ),
        );
      });
      if (!mounted || generation != _generation) {
        reader.close();
        await _close(controller);
        return;
      }
      setState(() {
        _controller = controller;
        _reader = reader;
        _problem = null;
      });
      widget.running.value = true;
      _applyTorch();
    } on CameraException catch (e) {
      if (controller != null) await _close(controller);
      _show(
        const {
              'CameraAccessDenied',
              'CameraAccessDeniedWithoutPrompt',
              'CameraAccessRestricted',
            }.contains(e.code)
            ? _Problem.permissionDenied
            : _Problem.failed,
      );
    } on Object {
      // No camera plugin (tests on the computer) or another failure. The
      // error's text is not shown: it is not written for the user.
      if (controller != null) await _close(controller);
      _show(_Problem.failed);
    } finally {
      _starting = false;
      // The app went to the background and came back while this start was
      // under way: that start gave up, so start again.
      if (mounted &&
          _inForeground &&
          _controller == null &&
          generation != _generation) {
        unawaited(_start());
      }
    }
  }

  /// Closes [controller]; a camera that failed to start can fail to close
  /// too, and there is nothing more to do about it then.
  static Future<void> _close(CameraController controller) async {
    try {
      await controller.dispose();
    } on Object {
      // Nothing to close.
    }
  }

  void _show(_Problem problem) {
    if (!mounted) return;
    setState(() => _problem = problem);
  }

  void _stop({bool notify = true}) {
    _generation++;
    _reader?.close();
    _reader = null;
    final controller = _controller;
    _controller = null;
    if (notify) widget.running.value = false;
    if (controller != null) unawaited(_close(controller));
  }

  void _applyTorch() {
    final controller = _controller;
    if (controller == null) return;
    unawaited(
      controller
          .setFlashMode(widget.torch.value ? FlashMode.torch : FlashMode.off)
          .catchError((Object _) {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    if (problem != null) return _CameraError(problem: problem);
    final controller = _controller;
    final size = controller?.value.previewSize;
    if (controller == null || size == null) {
      return const ColoredBox(color: Colors.black);
    }
    // The preview size is the sensor's (landscape); the phone is upright.
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.height,
          height: size.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.problem});

  final _Problem problem;

  @override
  Widget build(BuildContext context) {
    final message = switch (problem) {
      _Problem.permissionDenied =>
        'SHA behöver tillgång till kameran för att skanna QR-koder. '
            'Du kan ge behörighet i telefonens inställningar.',
      _Problem.noCamera => 'Telefonen har ingen kamera som appen kan använda.',
      _Problem.failed => 'Kameran kunde inte startas.',
    };
    return ColoredBox(
      color: ShaColors.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: ShaColors.textSecondary),
          ),
        ),
      ),
    );
  }
}
