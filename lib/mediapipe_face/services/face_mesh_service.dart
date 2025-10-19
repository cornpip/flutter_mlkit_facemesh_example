import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';
import 'package:image/image.dart' as img;

import 'package:flutter_mlkit_facemesh_example/mediapipe_face/utils/coordinates_translator.dart';

class FaceMeshService {
  FaceMeshService({
    FaceMeshDetector? detector,
  }) : _meshDetector =
            detector ?? FaceMeshDetector(option: FaceMeshDetectorOptions.faceMesh);

  final FaceMeshDetector _meshDetector;

  Future<FaceMesh?> detectLargestFace(InputImage inputImage) async {
    final meshes = await _meshDetector.processImage(inputImage);
    if (meshes.isEmpty) return null;
    return findLargestFace(meshes);
  }

  FaceMesh findLargestFace(List<FaceMesh> meshes) {
    if (meshes.isEmpty) {
      throw StateError('findLargestFace requires at least one mesh');
    }

    FaceMesh? largestFace;
    double maxArea = 0;

    for (final mesh in meshes) {
      final box = mesh.boundingBox;
      final area = box.width * box.height;
      if (area > maxArea || largestFace == null) {
        maxArea = area;
        largestFace = mesh;
      }
    }

    return largestFace!;
  }

  FaceMesh scaleMesh({
    required FaceMesh mesh,
    required Size originalSize,
    required Size targetSize,
    required InputImageMetadata metadata,
  }) {
    final lensDirection = CameraLensDirection.back;
    final rotation = metadata.rotation;

    final scaledPointsList = mesh.points.map((point) {
      final x = translateX(
        point.x.toDouble(),
        targetSize,
        originalSize,
        rotation,
        lensDirection,
      );
      final y = translateY(
        point.y.toDouble(),
        targetSize,
        originalSize,
        rotation,
        lensDirection,
      );

      return FaceMeshPoint(x: x, y: y, z: point.z * 0, index: point.index);
    }).toList();

    final leftRaw = translateX(
      mesh.boundingBox.left,
      targetSize,
      originalSize,
      rotation,
      lensDirection,
    );
    final rightRaw = translateX(
      mesh.boundingBox.right,
      targetSize,
      originalSize,
      rotation,
      lensDirection,
    );
    final topRaw = translateY(
      mesh.boundingBox.top,
      targetSize,
      originalSize,
      rotation,
      lensDirection,
    );
    final bottomRaw = translateY(
      mesh.boundingBox.bottom,
      targetSize,
      originalSize,
      rotation,
      lensDirection,
    );

    final left = math.min(leftRaw, rightRaw);
    final right = math.max(leftRaw, rightRaw);
    final top = math.min(topRaw, bottomRaw);
    final bottom = math.max(topRaw, bottomRaw);

    final scaledBoundingBox = Rect.fromLTRB(left, top, right, bottom);

    final scaledTriangles = mesh.triangles
        .map(
          (triangle) => FaceMeshTriangle(
            points: triangle.points.map((p) => scaledPointsList[p.index]).toList(),
          ),
        )
        .toList();

    final scaledContours = mesh.contours.map((type, contourPoints) {
      final scaledContourPoints =
          contourPoints?.map((p) => scaledPointsList[p.index]).toList();
      return MapEntry(type, scaledContourPoints);
    });

    return FaceMesh(
      points: scaledPointsList,
      boundingBox: scaledBoundingBox,
      triangles: scaledTriangles,
      contours: scaledContours,
    );
  }

  Future<List<FaceMesh>> detectResizedMeshes({
    required File originalFile,
    required Uint8List bytes,
    required Size targetSize,
    required bool isAndroid12OrAbove,
    required bool isBackCamera,
  }) async {
    final original = img.decodeImage(bytes);
    if (original == null) {
      throw StateError('Failed to decode image bytes');
    }

    img.Image processed;
    if (isAndroid12OrAbove) {
      processed = img.copyResize(
        original,
        width: targetSize.width.toInt(),
        height: targetSize.height.toInt(),
      );
    } else {
      final rotated = img.copyRotate(
        original,
        angle: isBackCamera ? -90 : 90,
      );
      processed = img.copyResize(
        rotated,
        width: targetSize.height.toInt(),
        height: targetSize.width.toInt(),
      );
    }

    final resizedBytes = img.encodeJpg(processed);
    final tempFile = File('${originalFile.parent.path}/resized.jpg');
    await tempFile.writeAsBytes(resizedBytes, mode: FileMode.write);

    final inputImage = InputImage.fromFilePath(tempFile.path);
    return _meshDetector.processImage(inputImage);
  }

  Future<void> dispose() async {
    await _meshDetector.close();
  }
}
