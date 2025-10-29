import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mlkit_facemesh_example/mediapipe_face/painters/face_mesh_detector_painter.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';
import 'package:image/image.dart' as img;

import 'package:flutter_mlkit_facemesh_example/common/colors.dart';
import 'package:flutter_mlkit_facemesh_example/mediapipe_face/services/camera_manager.dart';
import 'package:flutter_mlkit_facemesh_example/mediapipe_face/services/face_mesh_service.dart';
import 'package:flutter_mlkit_facemesh_example/mediapipe_face/services/input_image_converter.dart';
import 'package:flutter_mlkit_facemesh_example/util/device_info.dart';
import 'package:flutter_mlkit_facemesh_example/util/permission_util.dart';

class MediaPipeFace extends StatefulWidget {
  const MediaPipeFace({super.key});

  @override
  State<MediaPipeFace> createState() => _MediaPipeFaceState();
}

class _MediaPipeFaceState extends State<MediaPipeFace> with SingleTickerProviderStateMixin {
  final CameraManager _cameraManager = CameraManager();
  final FaceMeshService _faceMeshService = FaceMeshService();
  final InputImageConverter _inputImageConverter = InputImageConverter();

  late Directory _directory;
  int _androidSdkVersion = 0;

  bool _isCameraReady = false;
  bool _isDetecting = false;
  bool _imageLoaded = false;
  bool _isCapturing = false;

  static const List<int> _defaultMeshIndices = [412, 355, 278, 326, 97, 102, 126, 188, 6];

  late final TextEditingController _meshIndicesController;
  List<int> _customMeshIndices = List<int>.from(_defaultMeshIndices);

  OverlayEntry? _loadingOverlay;

  late final AnimationController _hintController;
  late final Animation<double> _hintScale;

  CameraImage? _latestCameraImage;
  Uint8List? _originBytes;
  InputImageMetadata? _inputImageMetadata;
  List<FaceMesh> _meshes = [];

  @override
  void initState() {
    super.initState();
    _hintController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _hintScale = Tween<double>(begin: 0.85, end: 1.05).animate(CurvedAnimation(parent: _hintController, curve: Curves.easeInOut));
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncHintAnimation());
    _meshIndicesController = TextEditingController(text: _defaultMeshIndices.join(', '));
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    _directory = Directory.systemTemp;

    try {
      if (Platform.isAndroid) {
        _androidSdkVersion = await DeviceInfo.getAndroidSdkVersion();
      }
    } catch (e) {
      debugPrint('Failed to get Android SDK version: $e');
    }
  }

  void _showLoadingOverlay() {
    if (!mounted || _loadingOverlay != null) return;
    final overlayState = Overlay.of(context, rootOverlay: true);

    _loadingOverlay = OverlayEntry(
      builder: (_) => Stack(
        children: [
          ModalBarrier(color: Colors.black.withOpacity(0.6), dismissible: false),
          const Center(child: CircularProgressIndicator(color: Colors.white)),
        ],
      ),
    );

    overlayState.insert(_loadingOverlay!);
  }

  void _hideLoadingOverlay() {
    _loadingOverlay?.remove();
    _loadingOverlay = null;
  }

  void _syncHintAnimation() {
    if (!_isCameraReady) {
      if (!_hintController.isAnimating) {
        _hintController.value = _hintController.lowerBound;
        _hintController.repeat(reverse: true);
      }
    } else {
      if (_hintController.isAnimating) {
        _hintController.stop();
      }
      if (_hintController.value != _hintController.lowerBound) {
        _hintController.value = _hintController.lowerBound;
      }
    }
  }

  void _handleMeshIndicesChanged(String value) {
    final entries = value.split(',');
    final parsed = <int>[];
    for (final entry in entries) {
      final trimmed = entry.trim();
      if (trimmed.isEmpty) continue;
      final index = int.tryParse(trimmed);
      if (index != null) {
        parsed.add(index);
      }
    }

    if (!mounted) return;
    setState(() {
      _customMeshIndices = parsed;
    });
  }

  Future<void> _initCamera({int cameraIndex = 1}) async {
    final hasPermission = await PermissionUtil.requestCameraPermission();
    if (!hasPermission || !mounted) return;

    setState(() {
      _isCameraReady = false;
      _resetCapturedImage();
    });

    try {
      await _cameraManager.initialize(onImage: _processCameraImageStream, cameraIndex: cameraIndex);

      if (!mounted) return;
      setState(() {
        _meshes = [];
        _isCameraReady = true;
      });
    } catch (e, st) {
      debugPrint('Camera init error: $e');
      debugPrint(st.toString());
    }
  }

  void _resetCapturedImage() {
    _originBytes = null;
    _imageLoaded = false;
  }

  Future<void> _processCameraImageStream(CameraImage image) async {
    if (_isDetecting) return;
    _isDetecting = true;

    try {
      final controller = _cameraManager.controller;
      final selectedCamera = _cameraManager.selectedCamera;
      if (controller == null || selectedCamera == null) return;

      final inputImage = _inputImageConverter.fromCameraImage(image: image, controller: controller, camera: selectedCamera);

      if (inputImage == null) return;

      final largestFace = await _faceMeshService.detectLargestFace(inputImage);

      if (largestFace == null) {
        if (mounted) {
          setState(() {
            _meshes = [];
          });
        }
        return;
      }

      if (!mounted) return;
      setState(() {
        _latestCameraImage = image;
        _inputImageMetadata = inputImage.metadata;
        _meshes = [largestFace];
      });
    } catch (e, st) {
      debugPrint('❌ Face detection error: $e');
      debugPrint(st.toString());
    } finally {
      _isDetecting = false;
    }
  }

  Future<void> _switchCamera() async {
    if (!mounted) return;

    _showLoadingOverlay();
    setState(() {
      _isCameraReady = false;
      _resetCapturedImage();
      _meshes = [];
    });

    try {
      await _cameraManager.switchCamera(onImage: _processCameraImageStream);

      if (!mounted) return;
      setState(() {
        _isCameraReady = true;
      });
    } catch (e, st) {
      debugPrint('Camera switch error: $e');
      debugPrint(st.toString());
    } finally {
      _hideLoadingOverlay();
    }
  }

  Future<void> _takePicture() async {
    final controller = _cameraManager.controller;
    if (controller == null) {
      await _initCamera();
      return;
    }

    if (!controller.value.isInitialized) {
      debugPrint('카메라가 초기화되지 않았습니다.');
      return;
    }
    if (controller.value.isTakingPicture) {
      debugPrint('이미 촬영 중입니다.');
      return;
    }

    if (!_isCameraReady) {
      if (mounted) {
        setState(() {
          _isCameraReady = true;
          _resetCapturedImage();
          _meshes = [];
        });
      }
      await _cameraManager.startImageStream(onImage: _processCameraImageStream);
      return;
    }

    XFile? tempCapturedFile;

    try {
      _showLoadingOverlay();
      if (mounted) {
        setState(() {
          _isCapturing = true;
        });
      }
      final file = await controller.takePicture();
      final imageBytes = await file.readAsBytes();
      tempCapturedFile = file;

      await _cameraManager.stopImageStream();

      final savedFile = File('${_directory.path}/latest_face_take_picture.jpg');
      await savedFile.writeAsBytes(imageBytes, mode: FileMode.write);

      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) {
        throw StateError('decoded takePictureBytes fail');
      }

      final pictureSize = Size(decoded.width.toDouble(), decoded.height.toDouble());
      final metadata = InputImageMetadata(
        size: pictureSize,
        rotation: InputImageRotation.rotation0deg,
        format: InputImageFormat.bgra8888,
        bytesPerRow: decoded.width * 4,
      );

      if (mounted) {
        setState(() {
          _isCameraReady = false;
          _meshes = [];
          _imageLoaded = false;
          _originBytes = imageBytes;
          _inputImageMetadata = metadata;
        });
      }

      final latestCameraImage = _latestCameraImage;
      final meshOriginalSize = latestCameraImage != null
          ? Size(latestCameraImage.height.toDouble(), latestCameraImage.width.toDouble())
          : const Size(720, 1280);

      final selectedCamera = _cameraManager.selectedCamera;
      final isBackCamera = selectedCamera == null ? true : selectedCamera.lensDirection == CameraLensDirection.back;

      final meshes = await _faceMeshService.detectResizedMeshes(
        originalFile: savedFile,
        bytes: imageBytes,
        targetSize: meshOriginalSize,
        sdkInt: _androidSdkVersion,
        isBackCamera: isBackCamera,
      );

      if (meshes.isEmpty) {
        if (mounted) {
          setState(() {
            _meshes = [];
          });
        }
        return;
      }

      final largestFace = _faceMeshService.findLargestFace(meshes);
      final scaledMesh = _faceMeshService.scaleMesh(mesh: largestFace, originalSize: meshOriginalSize, targetSize: pictureSize, metadata: metadata);

      if (mounted) {
        setState(() {
          _meshes = [scaledMesh];
        });
      }
    } catch (e, st) {
      debugPrint('stack trace: $st');
      debugPrint('Capture error: $e');
    } finally {
      _hideLoadingOverlay();
      if (mounted && _isCapturing) {
        setState(() {
          _isCapturing = false;
        });
      }
      if (tempCapturedFile != null) {
        final fileOnDisk = File(tempCapturedFile.path);
        if (await fileOnDisk.exists()) {
          await fileOnDisk.delete();
        }
      }
    }
  }

  @override
  void dispose() {
    _hideLoadingOverlay();
    _meshIndicesController.dispose();
    _hintController.dispose();
    unawaited(_cameraManager.dispose());
    unawaited(_faceMeshService.dispose());
    super.dispose();
  }

  double? _previewAspectRatio(CameraController? controller) {
    final value = controller?.value;
    if (value == null || !value.isInitialized) return null;
    final previewSize = value.previewSize;
    if (previewSize == null || previewSize.width == 0 || previewSize.height == 0) {
      return null;
    }
    return previewSize.width / previewSize.height;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _cameraManager.controller;
    final selectedCamera = _cameraManager.selectedCamera;

    final isBackCamera = selectedCamera?.lensDirection == CameraLensDirection.back;
    final borderRadius = BorderRadius.circular(20.r);
    final borderRadius2 = BorderRadius.circular(18.r);

    final aspectRatio = _previewAspectRatio(controller);
    final isCameraAvailable = controller != null && controller.value.isInitialized && _isCameraReady;

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncHintAnimation();
    });

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 20.w),
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(color: DEFAULT_BG),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.only(bottom: 24.h),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          decoration: BoxDecoration(color: Colors.black, borderRadius: borderRadius),
                          child: AspectRatio(
                            aspectRatio: 3 / 4,
                            child: Padding(
                              padding: EdgeInsetsGeometry.symmetric(horizontal: 8.w, vertical: 8.h),
                              child: ClipRRect(
                                borderRadius: borderRadius2,
                                child: OverflowBox(
                                  maxWidth: double.infinity,
                                  maxHeight: double.infinity,
                                  child: FittedBox(
                                    fit: BoxFit.contain,
                                    child: SizedBox(
                                      width: 300.w,
                                      child: Stack(
                                        children: [
                                          if (isCameraAvailable)
                                            ClipRRect(borderRadius: borderRadius, child: CameraPreview(controller))
                                          else
                                            AspectRatio(
                                              aspectRatio: aspectRatio != null && aspectRatio != 0 ? 1 / aspectRatio : 1,
                                              child: Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  Transform(
                                                    alignment: Alignment.center,
                                                    transform: isBackCamera ? Matrix4.identity() : (Matrix4.identity()..rotateY(math.pi)),
                                                    child: _originBytes != null
                                                        ? Image.memory(
                                                            _originBytes!,
                                                            fit: BoxFit.cover,
                                                            frameBuilder: (BuildContext context, Widget child, int? frame, bool wasSynchronouslyLoaded) {
                                                              if (wasSynchronouslyLoaded || frame != null) {
                                                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                                                  if (mounted && !_imageLoaded) {
                                                                    setState(() {
                                                                      _imageLoaded = true;
                                                                    });
                                                                  }
                                                                });
                                                                return child;
                                                              } else {
                                                                return Container(color: Colors.transparent);
                                                              }
                                                            },
                                                          )
                                                        : Container(color: Colors.transparent),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          if (_meshes.isNotEmpty && isCameraAvailable && _inputImageMetadata != null && selectedCamera != null)
                                            Positioned.fill(
                                              child: IgnorePointer(
                                                child: CustomPaint(
                                                  painter: FaceMeshDetectorPainter(
                                                    _meshes,
                                                    _inputImageMetadata!.size,
                                                    _inputImageMetadata!.rotation,
                                                    selectedCamera.lensDirection,
                                                    highlightIndices: _customMeshIndices,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          if (_meshes.isNotEmpty && !isCameraAvailable && _imageLoaded && _inputImageMetadata != null && selectedCamera != null)
                                            Positioned.fill(
                                              child: IgnorePointer(
                                                child: CustomPaint(
                                                  painter: FaceMeshDetectorPainter(
                                                    _meshes,
                                                    _inputImageMetadata!.size,
                                                    _inputImageMetadata!.rotation,
                                                    selectedCamera.lensDirection,
                                                    highlightIndices: _customMeshIndices,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 10.h,
                          right: 10.w,
                          child: IconButton(
                            icon: const Icon(Icons.cameraswitch),
                            color: Colors.white,
                            iconSize: 30.h,
                            onPressed: controller != null ? _switchCamera : null,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 90.h,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          GestureDetector(
                            onTap: _isCapturing ? null : _takePicture,
                            child: Container(
                              width: 60.r,
                              height: 60.r,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: _isCameraReady ? Colors.transparent : Colors.red.withOpacity(0.9), width: _isCameraReady ? 0 : 4.r),
                              ),
                              child: Center(
                                child: Container(
                                  width: _isCameraReady ? 40.r : 40.r,
                                  height: _isCameraReady ? 40.r : 40.r,
                                  decoration: BoxDecoration(
                                    color: _isCameraReady ? Colors.black : Colors.red,
                                    borderRadius: BorderRadius.circular(_isCameraReady ? 8.r : 26.r),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 20.h,
                            child: IgnorePointer(
                              ignoring: true,
                              child: AnimatedOpacity(
                                opacity: _isCameraReady ? 0 : 1,
                                duration: const Duration(milliseconds: 260),
                                curve: Curves.easeOut,
                                child: ScaleTransition(
                                  scale: _hintScale,
                                  child: Icon(Icons.touch_app, size: 30.r, color: Colors.black87),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(top: 12.h, bottom: 40.h),
                      child: TextField(
                        controller: _meshIndicesController,
                        onChanged: _handleMeshIndicesChanged,
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(labelText: 'Face mesh landmark 0~467 (e.g.)', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
