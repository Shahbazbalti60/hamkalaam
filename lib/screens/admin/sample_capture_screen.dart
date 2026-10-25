import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_service.dart';
import '../../services/camera_helper.dart';
import '../../services/dataset_service.dart';
import '../../services/mediapipe_service.dart';

/// Records short sign videos for ONE dataset word and uploads each one
/// to the server (saved under that word, and counted in its progress).
///
/// Workflow: tap the red button to start, sign the word, tap again to
/// stop. The clip uploads automatically and the screen is immediately
/// ready for the next take — so 50 samples can be filmed in a row.
class SampleCaptureScreen extends StatefulWidget {
  final int wordId;
  final String urduWord;
  final String gloss;
  final int initialSampleCount;

  const SampleCaptureScreen({
    super.key,
    required this.wordId,
    required this.urduWord,
    required this.gloss,
    required this.initialSampleCount,
  });

  @override
  State<SampleCaptureScreen> createState() => _SampleCaptureScreenState();
}

class _SampleCaptureScreenState extends State<SampleCaptureScreen> {
  static const int _targetSamples = 50;
  static const int _maxSeconds = 10;
  static const double _minSeconds = 0.8;

  final DatasetService _datasetService = DatasetService();

  CameraController? _controller;
  String? _cameraError;
  bool _initializing = true;
  String _cameraStatus = 'Starting camera...';

  bool _isRecording = false;
  bool _isUploading = false;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  Timer? _tick;

  late int _sampleCount = widget.initialSampleCount;
  int _savedThisSession = 0;

  // --- lighting check (SRDS FR-15) ---
  // Brightness is 0-255 (0.299R + 0.587G + 0.114B). The minimum is
  // adjustable because lighting and cameras differ between rooms/devices.
  static const double _defaultMinLight = 80;
  static const String _prefKey = 'light_threshold';
  final MediaPipeService _lightMeter = MediaPipeService();
  Timer? _lightTimer;
  double? _brightness; // null = meter not available (no check done)
  double _minLight = _defaultMinLight;
  double _lightSum = 0; // average over the current recording
  int _lightCount = 0;

  bool get _tooDark => _brightness != null && _brightness! < _minLight;

  @override
  void initState() {
    super.initState();
    _loadThreshold();
    _initCamera();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _lightTimer?.cancel();
    _lightMeter.stopLightMeter();
    _lightMeter.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _loadThreshold() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(_prefKey);
      if (saved != null && mounted) setState(() => _minLight = saved);
    } catch (_) {}
  }

  Future<void> _saveThreshold(double value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefKey, value);
    } catch (_) {}
  }

  /// Starts the brightness meter once the camera is up.
  Future<void> _startLightMeter() async {
    final ok = await _lightMeter.startLightMeter();
    if (!ok || !mounted) return;
    _lightTimer?.cancel();
    _lightTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted) return;
      final b = _lightMeter.brightness;
      if (_isRecording && b != null) {
        _lightSum += b;
        _lightCount++;
      }
      if (b != _brightness) setState(() => _brightness = b);
    });
  }

  void _showLightSettings() {
    double value = _minLight;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Minimum brightness'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current picture brightness: '
                '${_brightness == null ? "not available" : _brightness!.round()}'
                ' / 255',
              ),
              const SizedBox(height: 8),
              Text('Recording is blocked below: ${value.round()}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Slider(
                value: value,
                min: 20,
                max: 180,
                divisions: 32,
                label: value.round().toString(),
                onChanged: (v) => setDialogState(() => value = v),
              ),
              const Text(
                'Default is 80. Lower it for a camera that looks dark by '
                'itself, raise it for stricter lighting.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                setDialogState(() => value = _defaultMinLight);
              },
              child: const Text('Reset'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() => _minLight = value);
                _saveThreshold(value);
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  String? get _token =>
      Provider.of<AuthService>(context, listen: false).accessToken;

  // ───────────────────────── camera ─────────────────────────

  Future<void> _initCamera() async {
    setState(() {
      _initializing = true;
      _cameraError = null;
      _cameraStatus = 'Starting camera...';
    });

    if (_controller != null) {
      await _controller!.dispose();
      _controller = null;
    }

    try {
      final controller = await CameraHelper.openFrontCamera(
        onAttempt: (attempt, max) {
          if (!mounted) return;
          setState(() {
            _cameraStatus = attempt == 1
                ? 'Starting camera...'
                : 'Camera is waking up... (try $attempt of $max)';
          });
        },
        isCancelled: () => !mounted,
      );

      if (controller == null) return;
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initializing = false;
      });
      _startLightMeter();
    } on NoCameraException {
      if (!mounted) return;
      setState(() {
        _cameraError = 'No camera found on this device.';
        _initializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      final text = e.toString();
      setState(() {
        _cameraError = text.contains('NotAllowed') || text.contains('AccessDenied')
            ? 'Camera access was denied. Allow camera permission and retry.'
            : 'Could not start the camera. Please try again.';
        _initializing = false;
      });
    }
  }

  // ───────────────────────── recording ─────────────────────────

  void _snack(String text, {Color color = const Color(0xFF1F3864)}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), backgroundColor: color));
  }

  Future<void> _toggleRecording() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _isUploading) return;

    if (_isRecording) {
      await _stopAndUpload();
      return;
    }

    if (_tooDark) {
      _snack('Too dark. Improve the lighting before recording.',
          color: Colors.orange[800]!);
      return;
    }

    _lightSum = 0;
    _lightCount = 0;
    try {
      await c.startVideoRecording();
    } catch (e) {
      _snack('Could not start recording. Please try again.', color: Colors.red);
      return;
    }

    _startedAt = DateTime.now();
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || _startedAt == null) return;
      final elapsed = DateTime.now().difference(_startedAt!);
      setState(() => _elapsed = elapsed);
      if (elapsed.inSeconds >= _maxSeconds && _isRecording) {
        _stopAndUpload(); // auto-stop at the maximum length
      }
    });
    setState(() {
      _isRecording = true;
      _elapsed = Duration.zero;
    });
  }

  Future<void> _stopAndUpload() async {
    final c = _controller;
    if (c == null || !_isRecording) return;

    _tick?.cancel();
    final seconds = _startedAt == null
        ? 0.0
        : DateTime.now().difference(_startedAt!).inMilliseconds / 1000.0;

    XFile file;
    try {
      file = await c.stopVideoRecording();
    } catch (e) {
      if (mounted) setState(() => _isRecording = false);
      _snack('Recording failed. Please try again.', color: Colors.red);
      return;
    }

    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _isUploading = true;
    });

    if (seconds < _minSeconds) {
      setState(() => _isUploading = false);
      _snack('Too short — hold the sign a little longer and try again.',
          color: Colors.orange[800]!);
      return;
    }

    final token = _token;
    if (token == null) {
      setState(() => _isUploading = false);
      _snack('Not logged in.', color: Colors.red);
      return;
    }

    final bytes = await file.readAsBytes();
    final mime = file.mimeType ?? '';
    final ext = mime.contains('mp4') ? 'mp4' : (kIsWeb ? 'webm' : 'mp4');
    final name = 'sample_${DateTime.now().millisecondsSinceEpoch}.$ext';

    final result = await _datasetService.uploadSample(
      token: token,
      wordId: widget.wordId,
      bytes: bytes,
      filename: name,
      durationSeconds: seconds,
      lightingLevel: _lightCount > 0 ? _lightSum / _lightCount : _brightness,
    );

    if (!mounted) return;
    setState(() => _isUploading = false);

    if (result['success'] == true) {
      setState(() {
        _sampleCount = result['sample_count'] as int;
        _savedThisSession++;
      });
      _snack('Sample $_sampleCount saved ✓', color: Colors.green[700]!);
    } else {
      _snack(result['message'] ?? 'Upload failed. Please record again.',
          color: Colors.red);
    }
  }

  // ───────────────────────── UI ─────────────────────────

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final busy = _isRecording || _isUploading;
    final progress = (_sampleCount / _targetSamples).clamp(0.0, 1.0);
    final done = _sampleCount >= _targetSamples;

    return PopScope(
      canPop: !busy,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Record Samples',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        body: Column(
          children: [
            // Word + progress header
            Container(
              width: double.infinity,
              color: const Color(0xFF1F3864),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        widget.urduWord,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '(${widget.gloss})',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 15),
                        ),
                      ),
                      Text(
                        '$_sampleCount / $_targetSamples',
                        style: TextStyle(
                          color: done ? Colors.greenAccent : Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: Colors.white24,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          done ? Colors.greenAccent : Colors.white),
                    ),
                  ),
                ],
              ),
            ),

            // Lighting warning (SRDS FR-15)
            if (_tooDark)
              Container(
                width: double.infinity,
                color: Colors.amber[700],
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Insufficient lighting (now ${_brightness!.round()}, '
                  'need ${_minLight.round()}). Improve lighting and retry.',
                  style: const TextStyle(
                      color: Colors.black, fontWeight: FontWeight.w600),
                ),
              ),

            // Camera area
            Expanded(child: _buildCameraArea()),

            // Controls
            Container(
              width: double.infinity,
              color: Colors.black,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isUploading
                        ? 'Saving sample...'
                        : _isRecording
                            ? 'Recording  ${_fmt(_elapsed)} / 00:$_maxSeconds'
                            : 'Tap the red button, sign the word, tap again to stop',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: (_controller == null || _isUploading)
                        ? null
                        : _toggleRecording,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: (_tooDark && !_isRecording)
                                ? Colors.white24
                                : Colors.white,
                            width: 4),
                      ),
                      child: Center(
                        child: _isUploading
                            ? const SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                    strokeWidth: 3, color: Colors.white),
                              )
                            : AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: _isRecording ? 26 : 54,
                                height: _isRecording ? 26 : 54,
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(
                                      _isRecording ? 6 : 27),
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _savedThisSession == 0
                        ? 'Tip: keep the same lighting and distance for every take.'
                        : '$_savedThisSession saved this session',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraArea() {
    if (_initializing) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white38),
            const SizedBox(height: 14),
            Text(_cameraStatus,
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
      );
    }

    if (_cameraError != null || _controller == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off, size: 56, color: Colors.white24),
              const SizedBox(height: 12),
              Text(
                _cameraError ?? 'Camera not available.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _initCamera,
                icon: const Icon(Icons.refresh, color: Colors.white70),
                label: const Text('Retry',
                    style: TextStyle(color: Colors.white70)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final c = _controller!;
    return Stack(
      alignment: Alignment.center,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: c.value.aspectRatio,
            child: CameraPreview(c),
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: GestureDetector(
            onTap: _showLightSettings,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: (_tooDark ? Colors.amber[800]! : Colors.black)
                    .withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.light_mode, color: Colors.white, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    _brightness == null
                        ? 'Light: n/a'
                        : 'Light ${_brightness!.round()} (min ${_minLight.round()})',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.tune, color: Colors.white70, size: 14),
                ],
              ),
            ),
          ),
        ),
        if (_isRecording)
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.fiber_manual_record,
                      color: Colors.white, size: 12),
                  const SizedBox(width: 6),
                  Text('REC ${_fmt(_elapsed)}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
