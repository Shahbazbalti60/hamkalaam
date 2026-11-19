import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'hand_detection_result.dart';
import 'face_reading.dart';
import 'hand_window.dart';
import 'webview_page.dart';

/// Android / iOS implementation.
///
/// The hand and face detector (MediaPipe) is JavaScript, so on the phone it
/// runs inside a WebView that is shown as the camera picture. This class
/// has the same public methods as the web version, so the recognition
/// screen does not care which one it is talking to.
class MediaPipeService {
  WebViewController? _controller;
  final _results = StreamController<HandDetectionResult>.broadcast();

  Completer<bool>? _readyC;
  Completer<bool>? _startedC;
  Completer<HandWindow>? _windowC;
  bool _ready = false;
  bool _started = false;
  String? _lastError;
  String _facing = 'user'; // 'user' = front camera, 'environment' = back

  FaceReading _face = FaceReading.none;
  SegmentStatus _status = SegmentStatus.idle;
  final List<HandWindow> _segments = [];

  Stream<HandDetectionResult> get results => _results.stream;

  /// True while the back camera is in use.
  bool get usingBackCamera => _facing == 'environment';

  /// The last problem text (for the screen to show), or null.
  String? get lastError => _lastError;

  /// The camera picture. Null until [init] has been called.
  Widget? get previewWidget {
    final c = _controller;
    return c == null ? null : WebViewWidget(controller: c);
  }

  // ---- loading ---------------------------------------------------------

  /// Creates the WebView (immediately, before the first await, so the
  /// screen can show it) and loads the detector. Safe to call twice.
  Future<bool> init() {
    if (_ready) return Future.value(true);
    if (_readyC != null) return _readyC!.future;
    _readyC = Completer<bool>();
    _lastError = null;

    final c = WebViewController(
      onPermissionRequest: (request) => request.grant(),
    )
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('Hamkalaam', onMessageReceived: _onMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (e) {
          if (e.isForMainFrame == true) _fail('Page error: ${e.description}');
        },
      ));
    _controller = c;

    () async {
      // The Android camera permission has to be asked for by the app itself.
      try {
        final cams = await availableCameras();
        final front = cams.firstWhere(
            (x) => x.lensDirection == CameraLensDirection.front,
            orElse: () => cams.first);
        final cc =
            CameraController(front, ResolutionPreset.low, enableAudio: false);
        await cc.initialize();
        await cc.dispose();
      } catch (_) {
        _fail('Camera permission was refused. Allow the camera for this app '
            'in the phone settings and try again.');
        return;
      }
      await c.loadHtmlString(kWebViewPageHtml, baseUrl: 'https://hamkalaam.app/');
    }();

    // Safety net: the page should be ready well within a minute.
    return _readyC!.future.timeout(const Duration(seconds: 90), onTimeout: () {
      _fail('The hand detector took too long to load. Check the internet '
          'connection and try again.');
      return false;
    });
  }

  /// Runs a JavaScript line; a failure (page already closed) is ignored.
  Future<void> _js(String code) async {
    try {
      await _controller?.runJavaScript(code);
    } catch (_) {}
  }

  void _fail(String message) {
    _lastError ??= message;
    if (_readyC != null && !_readyC!.isCompleted) _readyC!.complete(false);
    if (_startedC != null && !_startedC!.isCompleted) _startedC!.complete(false);
  }

  void _onMessage(JavaScriptMessage m) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(m.message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (msg['type']) {
      case 'ready':
        _ready = true;
        if (_readyC != null && !_readyC!.isCompleted) _readyC!.complete(true);
        break;
      case 'started':
        _started = true;
        if (_startedC != null && !_startedC!.isCompleted) {
          _startedC!.complete(true);
        }
        break;
      case 'error':
        _fail('Detector error (${msg['where']}): ${msg['message']}');
        break;
      case 'tick':
        _onTick(msg);
        break;
      case 'segment':
        final w = _toWindow(msg['data']);
        if (w != null) _segments.add(w);
        break;
      case 'window':
        final w = _toWindow(msg['data']);
        if (_windowC != null && !_windowC!.isCompleted) {
          _windowC!.complete(w ?? HandWindow.empty);
        }
        break;
    }
  }

  void _onTick(Map<String, dynamic> msg) {
    final hand = (msg['hand'] as Map?)?.cast<String, dynamic>() ?? {};
    final face = (msg['face'] as Map?)?.cast<String, dynamic>() ?? {};
    final status = (msg['status'] as Map?)?.cast<String, dynamic>() ?? {};

    final raw = hand['landmarks'] as List<dynamic>? ?? [];
    _results.add(HandDetectionResult(
      handDetected: hand['handDetected'] == true,
      handCount: (hand['handCount'] as num?)?.toInt() ?? 0,
      landmarks: raw.map((v) => (v as num).toDouble()).toList(),
    ));

    if (face['detected'] == true) {
      final pts = (face['points'] as List<dynamic>)
          .map((v) => (v as num).toDouble())
          .toList();
      _face = pts.length == 136
          ? FaceReading(detected: true, points: pts)
          : FaceReading.none;
    } else {
      _face = FaceReading.none;
    }

    _status = SegmentStatus(
      state: status['state'] as String? ?? 'idle',
      queued: _segments.length,
      msSinceHand: (status['msSinceHand'] as num?)?.toInt() ?? 0,
      discarded: (status['discarded'] as num?)?.toInt() ?? 0,
    );
  }

  HandWindow? _toWindow(dynamic data) {
    try {
      final d = (data as Map).cast<String, dynamic>();
      final raw = d['frames'] as List<dynamic>? ?? [];
      final frames = raw
          .map((f) =>
              (f as List<dynamic>).map((v) => (v as num).toDouble()).toList())
          .toList();
      return HandWindow(
        frames: frames,
        handFrames: (d['handFrames'] as num?)?.toInt() ?? 0,
        rawCount: (d['rawCount'] as num?)?.toInt() ?? 0,
        durationMs: (d['durationMs'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  // ---- camera ------------------------------------------------------------

  /// Starts the camera (the picture appears in [previewWidget]).
  Future<bool> startDetection() async {
    if (_started) return true;
    final ok = await init();
    if (!ok || _controller == null) return false;
    _startedC = Completer<bool>();
    await _js("hkStart('$_facing')");
    return _startedC!.future.timeout(const Duration(seconds: 25), onTimeout: () {
      _fail('The camera did not start.');
      return false;
    });
  }

  /// Switches between the front and the back camera. Returns true when the
  /// new camera is running. (If it fails, the old camera is started again.)
  Future<bool> switchCamera() async {
    if (_controller == null || !_ready) return false;
    final previous = _facing;
    _facing = previous == 'user' ? 'environment' : 'user';
    _started = false;
    _segments.clear();
    _face = FaceReading.none;
    _lastError = null;
    await _js('hkStop()');
    await Future.delayed(const Duration(milliseconds: 300));
    var ok = await startDetection();
    if (!ok) {
      // go back to the camera that worked
      _facing = previous;
      _started = false;
      _lastError = null;
      await _js('hkStop()');
      await Future.delayed(const Duration(milliseconds: 300));
      await startDetection();
    }
    return ok;
  }

  void stopDetection() {
    _started = false;
    _segments.clear();
    _face = FaceReading.none;
    _status = SegmentStatus.idle;
    _js('hkStop()');
    _results.add(HandDetectionResult.none);
  }

  // ---- fixed window (admin capture) ---------------------------------------

  Future<HandWindow> recordWindow({
    Duration duration = const Duration(milliseconds: 2500),
  }) async {
    final c = _controller;
    if (c == null || !_started) {
      await Future.delayed(duration);
      return HandWindow.empty;
    }
    _windowC = Completer<HandWindow>();
    await _js('hkWindow(true)');
    await Future.delayed(duration);
    await _js('hkWindow(false)');
    return _windowC!.future
        .timeout(const Duration(seconds: 5), onTimeout: () => HandWindow.empty);
  }

  // ---- face --------------------------------------------------------------

  FaceReading get latestFace => _face;

  // ---- light meter (not available on the phone yet) ----------------------

  Future<bool> startLightMeter() async => false;

  void stopLightMeter() {}

  double? get brightness => null;

  // ---- automatic word cutting --------------------------------------------

  void startContinuous() {
    _segments.clear();
    _js('hkContinuous(true)');
  }

  void stopContinuous() {
    _js('hkContinuous(false)');
    _segments.clear();
  }

  SegmentStatus getSegmentStatus() => SegmentStatus(
        state: _status.state,
        queued: _segments.length,
        msSinceHand: _status.msSinceHand,
        discarded: _status.discarded,
      );

  HandWindow? popSegment() => _segments.isEmpty ? null : _segments.removeAt(0);

  void dispose() {
    stopDetection();
    _results.close();
  }
}
