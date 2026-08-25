import 'dart:async';

import 'hand_detection_result.dart';

/// No-op stub for non-web platforms (e.g. Android build).
///
/// MediaPipe-in-browser is only implemented for the web target in this
/// phase of the project. On other platforms, hand detection always
/// reports "not detected" rather than crashing or doing nothing
/// silently-but-confusingly.
class MediaPipeService {
  final _controller = StreamController<HandDetectionResult>.broadcast();

  Stream<HandDetectionResult> get results => _controller.stream;

  Future<bool> init() async => false;

  Future<bool> startDetection() async => false;

  void stopDetection() {
    _controller.add(HandDetectionResult.none);
  }

  void dispose() {
    _controller.close();
  }
}