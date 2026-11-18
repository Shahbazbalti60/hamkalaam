import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/camera_helper.dart';
import '../../services/expression_service.dart';
import '../../services/mediapipe_service.dart';

/// Admin: records the team's own face expressions to train the
/// expression CNN (SRDS FR-20 / FR-21). Each recording is 3 seconds;
/// about 15 face vectors (68 landmarks each) are sent to the server.
class ExpressionCaptureScreen extends StatefulWidget {
  const ExpressionCaptureScreen({super.key});

  @override
  State<ExpressionCaptureScreen> createState() => _ExpressionCaptureScreenState();
}

class _ExpressionCaptureScreenState extends State<ExpressionCaptureScreen> {
  static const Color _navy = Color(0xFF1F3864);
  static const int _recordMs = 3000;
  static const int _everyMs = 200;
  static const int _minVectors = 8;

  static const List<String> _classes = [
    'Question', 'Negation', 'Affirmation', 'Neutral', 'Happy', 'Sad'
  ];
  static const Map<String, String> _howTo = {
    'Question': 'Raise your eyebrows and lean slightly forward, as when asking a question in sign. You may tilt your head a little.',
    'Negation': 'Pull your eyebrows together and down, press your lips, and slowly shake your head side to side.',
    'Affirmation': 'Relaxed eyebrows, mouth slightly open, and nod slowly up and down.',
    'Neutral': 'Relaxed resting face, looking at the camera.',
    'Happy': 'A natural smile with the corners of the mouth up.',
    'Sad': 'Mouth corners down, eyebrows slightly raised in the middle.',
  };

  final ExpressionService _service = ExpressionService();
  final MediaPipeService _mediaPipe = MediaPipeService();

  CameraController? _camera;
  String? _cameraError;
  bool _starting = true;
  String _cameraStatus = 'Starting camera...';
  bool _detectionOn = false;

  String _selected = 'Question';
  bool _countingDown = false;
  int _countdown = 2;
  bool _recording = false;
  bool _uploading = false;
  double _progress = 0;
  bool _faceNow = false;
  Timer? _faceTimer;

  Map<String, int> _counts = {};
  Map<String, int> _recs = {};

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _faceTimer?.cancel();
    _mediaPipe.stopDetection();
    _mediaPipe.dispose();
    _camera?.dispose();
    super.dispose();
  }

  String? get _token =>
      Provider.of<AuthService>(context, listen: false).accessToken;

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.red : Colors.green[700],
      ));
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _cameraError = null;
    });
    try {
      final controller = await CameraHelper.openFrontCamera(
        onAttempt: (attempt, max) {
          if (!mounted) return;
          setState(() => _cameraStatus = attempt == 1
              ? 'Starting camera...'
              : 'Camera is waking up... (try $attempt of $max)');
        },
        isCancelled: () => !mounted,
      );
      if (controller == null) return;
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _camera = controller);

      setState(() => _cameraStatus = 'Loading face model...');
      await _mediaPipe.init();
      _detectionOn = await _mediaPipe.startDetection();
      if (!mounted) return;
      setState(() => _starting = false);
      if (!_detectionOn) {
        _snack('Face detection could not start. Use Chrome on a computer.', error: true);
      }
      _faceTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
        final seen = _mediaPipe.latestFace.detected;
        if (mounted && seen != _faceNow) setState(() => _faceNow = seen);
      });
      _loadSummary();
    } on NoCameraException {
      if (!mounted) return;
      setState(() {
        _cameraError = 'No camera found on this device.';
        _starting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cameraError = 'Could not start the camera. Please try again.';
        _starting = false;
      });
    }
  }

  Future<void> _loadSummary() async {
    final token = _token;
    if (token == null) return;
    final r = await _service.getSummary(token);
    if (!mounted || r['success'] != true) return;
    setState(() {
      _counts = Map<String, int>.from(r['counts']);
      _recs = Map<String, int>.from(r['recordings']);
    });
  }

  Future<void> _record() async {
    if (_countingDown || _recording || _uploading || !_detectionOn) return;
    final token = _token;
    if (token == null) return;

    // 2-second get-ready countdown
    for (var i = 2; i > 0; i--) {
      setState(() {
        _countingDown = true;
        _countdown = i;
      });
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
    }

    setState(() {
      _countingDown = false;
      _recording = true;
      _progress = 0;
    });
    final vectors = <List<double>>[];
    final steps = _recordMs ~/ _everyMs;
    for (var i = 0; i < steps; i++) {
      await Future.delayed(const Duration(milliseconds: _everyMs));
      if (!mounted) return;
      final face = _mediaPipe.latestFace;
      if (face.detected) vectors.add(face.points);
      setState(() => _progress = (i + 1) / steps);
    }

    setState(() {
      _recording = false;
      _uploading = true;
    });
    if (vectors.length < _minVectors) {
      setState(() => _uploading = false);
      _snack('Your face was seen only ${vectors.length} times. Face the camera in good light and try again.',
          error: true);
      return;
    }

    final recId = '${_selected}-${DateTime.now().millisecondsSinceEpoch}';
    final r = await _service.upload(
        token: token, label: _selected, recId: recId, vectors: vectors);
    if (!mounted) return;
    setState(() => _uploading = false);
    if (r['success'] == true) {
      setState(() {
        _counts = Map<String, int>.from(r['counts']);
        _recs = Map<String, int>.from(r['recordings']);
      });
      _snack('Saved ${vectors.length} frames of "$_selected".');
    } else {
      _snack(r['message'] as String? ?? 'Upload failed', error: true);
    }
  }

  Future<void> _deleteClass() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete all "$_selected" samples?'),
        content: const Text('Use this if a class was recorded wrongly. It cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    final token = _token;
    if (ok != true || token == null) return;
    final r = await _service.deleteClass(token, _selected);
    if (!mounted) return;
    if (r['success'] == true) {
      setState(() {
        _counts = Map<String, int>.from(r['counts']);
        _recs = Map<String, int>.from(r['recordings']);
      });
      _snack('Samples of "$_selected" deleted.');
    } else {
      _snack(r['message'] as String? ?? 'Could not delete', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _countingDown || _recording || _uploading;
    final total = _counts.values.fold<int>(0, (a, b) => a + b);

    return PopScope(
      canPop: !busy,
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          title: const Text('Expression Samples',
              style: TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              tooltip: 'Delete this class',
              icon: const Icon(Icons.delete_outline),
              onPressed: busy ? null : _deleteClass,
            ),
          ],
        ),
        body: Center(
         child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Camera: a small preview that shows the WHOLE camera picture
              AspectRatio(
                aspectRatio: 4 / 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    color: Colors.black,
                    child: _buildCamera(),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Class chooser
              const Text('Expression to record',
                  style: TextStyle(fontWeight: FontWeight.w600, color: _navy)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in _classes)
                    ChoiceChip(
                      label: Text('$c  ${_counts[c] ?? 0}'),
                      selected: _selected == c,
                      onSelected: busy ? null : (_) => setState(() => _selected = c),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Text(_howTo[_selected] ?? '', style: const TextStyle(height: 1.4)),
              ),
              const SizedBox(height: 12),

              // Record button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (busy || _starting || !_detectionOn || !_faceNow) ? null : _record,
                  icon: const Icon(Icons.fiber_manual_record),
                  label: Text(
                    _starting
                        ? 'Starting...'
                        : _countingDown
                            ? 'Get ready... $_countdown'
                            : _recording
                                ? 'Recording ${(_progress * 100).round()} %'
                                : _uploading
                                    ? 'Saving...'
                                    : !_faceNow
                                        ? 'Show your face to the camera'
                                        : 'Record 3 seconds of "$_selected"',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[600],
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              if (_recording)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(value: _progress, minHeight: 6),
                ),
              const SizedBox(height: 16),

              // Counts
              Text('Collected so far: $total frames',
                  style: const TextStyle(fontWeight: FontWeight.w600, color: _navy)),
              const SizedBox(height: 6),
              for (final c in _classes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(width: 110, child: Text(c)),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: ((_counts[c] ?? 0) / 300).clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: Colors.grey[200],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${_counts[c] ?? 0} (${_recs[c] ?? 0} rec.)',
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              const Text(
                'Aim for about 300 frames (20 recordings) per expression, from each team member, '
                'in different lighting and with small head movements. Affirmation, Question and '
                'Negation matter most: there is no public dataset for them.',
                style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
              ),
            ],
          ),
         ),
        ),
        ),
      ),
    );
  }

  Widget _buildCamera() {
    if (_cameraError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_cameraError!, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: _start, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_camera == null || !_camera!.value.isInitialized) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white38),
            const SizedBox(height: 12),
            Text(_cameraStatus, style: const TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(child: CameraPreview(_camera!)),
        Positioned(
          top: 10,
          left: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: (_faceNow ? Colors.green : Colors.grey).withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_faceNow ? 'Face seen' : 'No face seen',
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ),
        if (_countingDown)
          Center(
            child: Container(
              width: 90,
              height: 90,
              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text('$_countdown',
                  style: const TextStyle(color: Colors.white, fontSize: 52, fontWeight: FontWeight.bold)),
            ),
          ),
        if (_recording)
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('REC',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  }
}
