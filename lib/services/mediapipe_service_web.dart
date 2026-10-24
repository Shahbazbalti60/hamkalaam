import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'hand_detection_result.dart';
import 'hand_window.dart';

@JS('hamkalaamMediaPipe.init')
external JSPromise<JSBoolean> _jsInit();

@JS('hamkalaamMediaPipe.startDetection')
external JSPromise<JSBoolean> _jsStartDetection();

@JS('hamkalaamMediaPipe.stopDetection')
external void _jsStopDetection();

@JS('hamkalaamMediaPipe.getLatestResult')
external JSString _jsGetLatestResult();

@JS('hamkalaamMediaPipe.startWindow')
external void _jsStartWindow();

@JS('hamkalaamMediaPipe.stopWindow')
external JSString _jsStopWindow();

@JS('hamkalaamMediaPipe.startContinuous')
external void _jsStartContinuous();

@JS('hamkalaamMediaPipe.stopContinuous')
external void _jsStopContinuous();

@JS('hamkalaamMediaPipe.popSegment')
external JSString _jsPopSegment();

@JS('hamkalaamMediaPipe.getSegmentStatus')
external JSString _jsGetSegmentStatus();

/// Web implementation - talks to web/mediapipe_bridge.js.
///
/// The JS side runs its own independent hidden camera stream and
/// polls MediaPipe's HandLandmarker on every animation frame. This
/// class polls the JS side's latest cached result at a fixed interval
/// and exposes it as a Dart stream. It can also record a fixed
/// "window" of frames (see [recordWindow]) for the sequence model.
class MediaPipeService {
  Timer? _pollTimer;
  final _controller = StreamController<HandDetectionResult>.broadcast();

  Stream<HandDetectionResult> get results => _controller.stream;

  bool _initialized = false;

  /// Loads the MediaPipe model. Safe to call multiple times.
  Future<bool> init() async {
    if (_initialized) return true;
    try {
      final result = await _jsInit().toDart;
      _initialized = result.toDart;
      return _initialized;
    } catch (_) {
      return false;
    }
  }

  /// Starts the hidden camera stream and begins polling results
  /// roughly 6-7 times per second.
  Future<bool> startDetection() async {
    try {
      final result = await _jsStartDetection().toDart;
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(
        const Duration(milliseconds: 150),
        (_) => _poll(),
      );
      return result.toDart;
    } catch (_) {
      return false;
    }
  }

  void _poll() {
    try {
      final jsonStr = _jsGetLatestResult().toDart;
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final rawLandmarks = data['landmarks'] as List<dynamic>? ?? [];
      _controller.add(HandDetectionResult(
        handDetected: data['handDetected'] as bool? ?? false,
        handCount: (data['handCount'] as num?)?.toInt() ?? 0,
        landmarks: rawLandmarks.map((v) => (v as num).toDouble()).toList(),
      ));
    } catch (_) {
      // A single malformed poll shouldn't break the stream.
    }
  }

  /// Records [duration] of frames (default 2.5 s) and returns exactly
  /// 60 evenly spaced frames. Detection must already be running.
  Future<HandWindow> recordWindow({
    Duration duration = const Duration(milliseconds: 2500),
  }) async {
    try {
      _jsStartWindow();
      await Future.delayed(duration);
      final jsonStr = _jsStopWindow().toDart;
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final raw = data['frames'] as List<dynamic>? ?? [];
      final frames = raw
          .map((f) =>
              (f as List<dynamic>).map((v) => (v as num).toDouble()).toList())
          .toList();
      return HandWindow(
        frames: frames,
        handFrames: (data['handFrames'] as num?)?.toInt() ?? 0,
        rawCount: (data['rawCount'] as num?)?.toInt() ?? 0,
        durationMs: (data['durationMs'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return HandWindow.empty;
    }
  }

  // ---- automatic (continuous) mode ---------------------------------

  /// Starts cutting the live camera stream into one segment per word.
  /// Detection must already be running ([startDetection]).
  void startContinuous() {
    try {
      _jsStartContinuous();
    } catch (_) {}
  }

  void stopContinuous() {
    try {
      _jsStopContinuous();
    } catch (_) {}
  }

  SegmentStatus getSegmentStatus() {
    try {
      final data =
          jsonDecode(_jsGetSegmentStatus().toDart) as Map<String, dynamic>;
      return SegmentStatus(
        state: data['state'] as String? ?? 'idle',
        queued: (data['queued'] as num?)?.toInt() ?? 0,
        msSinceHand: (data['msSinceHand'] as num?)?.toInt() ?? 0,
        discarded: (data['discarded'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return SegmentStatus.idle;
    }
  }

  /// Oldest finished word segment (60 x 126), or null if none is waiting.
  HandWindow? popSegment() {
    try {
      final jsonStr = _jsPopSegment().toDart;
      if (jsonStr.isEmpty) return null;
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final raw = data['frames'] as List<dynamic>? ?? [];
      final frames = raw
          .map((f) =>
              (f as List<dynamic>).map((v) => (v as num).toDouble()).toList())
          .toList();
      return HandWindow(
        frames: frames,
        handFrames: (data['handFrames'] as num?)?.toInt() ?? 0,
        rawCount: (data['rawCount'] as num?)?.toInt() ?? 0,
        durationMs: (data['durationMs'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Stops the hidden camera stream and detection loop. Always call
  /// this when leaving the recognition screen.
  void stopDetection() {
    _pollTimer?.cancel();
    _pollTimer = null;
    try {
      _jsStopDetection();
    } catch (_) {}
    _controller.add(HandDetectionResult.none);
  }

  void dispose() {
    stopDetection();
    _controller.close();
  }
}
