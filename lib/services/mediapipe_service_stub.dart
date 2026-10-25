import 'dart:async';

import 'hand_detection_result.dart';
import 'hand_window.dart';

/// Non-web stub (Android / iOS): no hand detection yet, every call is
/// a harmless no-op so the rest of the app compiles and runs.
class MediaPipeService {
  final _controller = StreamController<HandDetectionResult>.broadcast();

  Stream<HandDetectionResult> get results => _controller.stream;

  Future<bool> init() async => false;

  Future<bool> startDetection() async => false;

  Future<HandWindow> recordWindow({
    Duration duration = const Duration(milliseconds: 2500),
  }) async {
    await Future.delayed(duration);
    return HandWindow.empty;
  }

  Future<bool> startLightMeter() async => false;

  void stopLightMeter() {}

  double? get brightness => null;

  void startContinuous() {}

  void stopContinuous() {}

  SegmentStatus getSegmentStatus() => SegmentStatus.idle;

  HandWindow? popSegment() => null;

  void stopDetection() {}

  void dispose() {
    _controller.close();
  }
}
