import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'hand_detection_result.dart';

@JS('hamkalaamMediaPipe.init')
external JSPromise<JSBoolean> _jsInit();

@JS('hamkalaamMediaPipe.startDetection')
external JSPromise<JSBoolean> _jsStartDetection();

@JS('hamkalaamMediaPipe.stopDetection')
external void _jsStopDetection();

@JS('hamkalaamMediaPipe.getLatestResult')
external JSString _jsGetLatestResult();

/// Web implementation — talks to web/mediapipe_bridge.js.
///
/// The JS side runs its own independent hidden camera stream and
/// polls MediaPipe's HandLandmarker on every animation frame. This
/// class polls the JS side's latest cached result at a fixed interval
/// and exposes it as a Dart stream.
class MediaPipeService {
  Timer? _pollTimer;
  final _controller = StreamController<HandDetectionResult>.broadcast();

  Stream<HandDetectionResult> get results => _controller.stream;

  bool _initialized = false;

  /// Loads the MediaPipe model. Safe to call multiple times — the JS
  /// side no-ops if already initialized. Can take a few seconds on
  /// first call since it downloads the model from Google's CDN.
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

  /// Starts an independent hidden camera stream and begins polling
  /// detection results roughly 6-7 times per second.
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

  /// Stops the hidden camera stream and detection loop. Always call
  /// this when leaving the recognition screen so the camera light
  /// actually turns off.
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