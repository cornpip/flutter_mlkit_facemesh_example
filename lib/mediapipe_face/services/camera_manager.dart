import 'package:camera/camera.dart';

typedef CameraImageListener = void Function(CameraImage image);

class CameraManager {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;

  CameraController? get controller => _controller;
  List<CameraDescription> get cameras => List.unmodifiable(_cameras);
  CameraDescription? get selectedCamera =>
      _cameras.isEmpty ? null : _cameras[_selectedCameraIndex];
  int get selectedCameraIndex => _selectedCameraIndex;

  Future<void> initialize({
    required CameraImageListener onImage,
    int cameraIndex = 1,
    int skipFrameCount = 1,
  }) async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) {
      throw StateError('No available cameras');
    }

    if (cameraIndex >= 0 && cameraIndex < _cameras.length) {
      _selectedCameraIndex = cameraIndex;
    } else {
      _selectedCameraIndex = 0;
    }

    await _replaceController(
      onImage: onImage,
      skipFrameCount: skipFrameCount,
    );
  }

  Future<void> switchCamera({
    required CameraImageListener onImage,
    int skipFrameCount = 1,
  }) async {
    if (_cameras.isEmpty) return;

    final currentCamera = selectedCamera;
    if (currentCamera == null) return;

    int newIndex;
    if (currentCamera.lensDirection == CameraLensDirection.front) {
      newIndex =
          _cameras.indexWhere((cam) => cam.lensDirection == CameraLensDirection.back);
    } else {
      newIndex =
          _cameras.indexWhere((cam) => cam.lensDirection == CameraLensDirection.front);
    }

    if (newIndex == -1 || newIndex == _selectedCameraIndex) {
      return;
    }

    _selectedCameraIndex = newIndex;
    await _replaceController(
      onImage: onImage,
      skipFrameCount: skipFrameCount,
    );
  }

  Future<void> startImageStream({
    required CameraImageListener onImage,
    int skipFrameCount = 1,
  }) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }

    await _startImageStream(
      controller: controller,
      onImage: onImage,
      skipFrameCount: skipFrameCount,
    );
  }

  Future<void> stopImageStream() async {
    final controller = _controller;
    if (controller == null) return;

    if (controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
  }

  Future<void> dispose() async {
    await stopImageStream();
    await _disposeController();
  }

  Future<void> _replaceController({
    required CameraImageListener onImage,
    int skipFrameCount = 1,
  }) async {
    await _disposeController();

    final selectedCamera = this.selectedCamera;
    if (selectedCamera == null) return;

    final controller = CameraController(
      selectedCamera,
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );

    _controller = controller;

    await controller.initialize();
    await _startImageStream(
      controller: controller,
      onImage: onImage,
      skipFrameCount: skipFrameCount,
    );
  }

  Future<void> _disposeController() async {
    final controller = _controller;
    if (controller == null) return;

    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      await controller.dispose();
    } finally {
      _controller = null;
    }
  }

  Future<void> _startImageStream({
    required CameraController controller,
    required CameraImageListener onImage,
    int skipFrameCount = 1,
  }) async {
    int skipped = 0;

    await controller.startImageStream((image) {
      if (skipped < skipFrameCount) {
        skipped++;
        return;
      }
      onImage(image);
    });
  }
}
