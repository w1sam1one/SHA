// 0012 (C1): the scanner's camera runs only while the screen is open and the
// app is in the foreground, and never keeps a second camera open.
import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sha/features/qr/qr_camera.dart';

/// A camera that counts what the app does with it. [gate] holds the start
/// open, as Android's permission dialog does.
class _FakeCamera extends CameraPlatform {
  int created = 0;
  int disposed = 0;
  int streams = 0;
  final flash = <FlashMode>[];
  Completer<void>? gate;
  CameraException? createError;
  final _initialized = StreamController<CameraInitializedEvent>.broadcast();

  int get open => created - disposed;

  @override
  Future<List<CameraDescription>> availableCameras() async => const [
    CameraDescription(
      name: '0',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
  ];

  @override
  Future<int> createCameraWithSettings(
    CameraDescription description,
    MediaSettings? settings,
  ) async {
    final error = createError;
    if (error != null) throw error;
    created++;
    final id = created;
    final gate = this.gate;
    if (gate != null) await gate.future;
    return id;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    scheduleMicrotask(
      () => _initialized.add(
        CameraInitializedEvent(
          cameraId,
          720,
          480,
          ExposureMode.auto,
          true,
          FocusMode.auto,
          true,
        ),
      ),
    );
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      _initialized.stream.where((e) => e.cameraId == cameraId);

  /// Never closes: CameraController waits for its first event.
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      StreamController<CameraErrorEvent>().stream;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  bool supportsImageStreaming() => true;

  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int cameraId, {
    CameraImageStreamOptions? options,
  }) {
    streams++;
    return StreamController<CameraImageData>().stream;
  }

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async =>
      flash.add(mode);

  @override
  Widget buildPreview(int cameraId) => const SizedBox.expand();

  /// Counts only cameras that were created: a controller whose start
  /// failed has no camera to close.
  @override
  Future<void> dispose(int cameraId) async {
    if (cameraId >= 1 && cameraId <= created) disposed++;
  }
}

const _toBackground = [
  AppLifecycleState.inactive,
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
];
const _toForeground = [
  AppLifecycleState.hidden,
  AppLifecycleState.inactive,
  AppLifecycleState.resumed,
];

Future<void> _lifecycle(
  WidgetTester tester,
  List<AppLifecycleState> states,
) async {
  for (final state in states) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }
}

void main() {
  late _FakeCamera camera;
  late ValueNotifier<bool> running;
  late ValueNotifier<bool> torch;

  setUp(() {
    camera = _FakeCamera();
    CameraPlatform.instance = camera;
    running = ValueNotifier(false);
    torch = ValueNotifier(false);
  });

  Widget app({bool scanner = true}) => MaterialApp(
    home: scanner
        ? QrCamera(onCode: (_) {}, torch: torch, running: running)
        : const SizedBox(),
  );

  testWidgets('starts, stops in the background, starts again, stops on '
      'leaving', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect((camera.open, camera.streams, running.value), (1, 1, true));

    await _lifecycle(tester, _toBackground);
    await tester.pumpAndSettle();
    expect((camera.open, running.value), (0, false));

    await _lifecycle(tester, _toForeground);
    await tester.pumpAndSettle();
    expect((camera.open, camera.streams, running.value), (1, 2, true));

    await tester.pumpWidget(app(scanner: false));
    await tester.pumpAndSettle();
    expect(camera.open, 0);
  });

  testWidgets('background and back while the camera is starting: it runs '
      'afterwards, with one camera open', (tester) async {
    camera.gate = Completer<void>();
    await tester.pumpWidget(app());
    await tester.pump();
    await _lifecycle(tester, _toBackground);
    await _lifecycle(tester, _toForeground);
    camera.gate!.complete();
    camera.gate = null;
    await tester.pumpAndSettle();
    expect((camera.open, running.value), (1, true));
    expect(camera.streams, greaterThanOrEqualTo(1));
  });

  testWidgets('leaving the screen while the camera is starting closes it', (
    tester,
  ) async {
    camera.gate = Completer<void>();
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pumpWidget(app(scanner: false));
    camera.gate!.complete();
    await tester.pumpAndSettle();
    expect((camera.open, camera.streams), (0, 0));
  });

  testWidgets('a denied camera says so, and is tried again on return', (
    tester,
  ) async {
    camera.createError = CameraException('CameraAccessDenied', 'denied');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(
      find.textContaining('SHA behöver tillgång till kameran'),
      findsOneWidget,
    );
    expect(running.value, isFalse);

    // The user gives permission in the phone's settings and comes back.
    camera.createError = null;
    await _lifecycle(tester, _toBackground);
    await _lifecycle(tester, _toForeground);
    await tester.pumpAndSettle();
    expect((camera.open, running.value), (1, true));
    expect(find.textContaining('SHA behöver tillgång'), findsNothing);
  });

  testWidgets('the torch follows its switch while the camera runs', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    torch.value = true;
    await tester.pumpAndSettle();
    torch.value = false;
    await tester.pumpAndSettle();
    expect(camera.flash, containsAllInOrder([FlashMode.torch, FlashMode.off]));
  });
}
