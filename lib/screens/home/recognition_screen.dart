import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../services/auth_service.dart';
import '../../services/mediapipe_service.dart';
import '../../services/camera_helper.dart';
import '../../services/recognition_service.dart';
import '../../services/audio_service.dart';

class RecognitionScreen extends StatefulWidget {
  const RecognitionScreen({super.key});

  @override
  State<RecognitionScreen> createState() => _RecognitionScreenState();
}

class _RecognitionScreenState extends State<RecognitionScreen> {
  bool _isSigning = false;
  String _expressionLabel = 'Neutral';
  final List<String> _wordStream = [];
  String? _generatedSentence;

  // --- Camera state (Step 3a: real live preview) ---
  CameraController? _cameraController;
  Future<void>? _initializeCameraFuture;
  String? _cameraError;
  String _cameraStatus = 'Starting camera...';

  // --- MediaPipe hand detection state (Step 3b) ---
  final MediaPipeService _mediaPipeService = MediaPipeService();
  bool _isMediaPipeStarting = false;
  bool _handDetected = false;
  int _handCount = 0;
  // Hand-tracking model warm-up status (shown in the bottom-left badge).
  bool _aiChecked = false;
  bool _aiReady = false;
  // Last recognition error shown, so the same error isn't spammed.
  String? _lastShownError;
  List<double> _latestLandmarks = [];
  DateTime? _lastHandSeenAt;

  // --- Recognition pipeline state (Phase 4) ---
  // NOTE: hits DUMMY rule-based classifiers on the backend for now,
  // not real trained models — see app/ai/*.py comments.
  final RecognitionService _recognitionService = RecognitionService();
  Timer? _classifyTimer;
  String? _lastAddedWord;
  bool _isGenerating = false;

  // --- Text-to-speech state (Phase 5) ---
  final AudioService _audioService = AudioService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
    _initializeCameraFuture = _initCamera();
    _mediaPipeService.results.listen((result) {
      if (!mounted) return;
      setState(() {
        _handDetected = result.handDetected;
        _handCount = result.handCount;
        _latestLandmarks = result.landmarks;
      });
      if (result.handDetected) {
        _lastHandSeenAt = DateTime.now();
      }
    });
  }

  Future<void> _initCamera() async {
    if (_cameraController != null) {
      await _cameraController!.dispose();
      _cameraController = null;
    }
    if (mounted) {
      setState(() {
        _cameraError = null;
        _cameraStatus = 'Starting camera...';
      });
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
        _cameraController = controller;
        _cameraError = null;
      });

      // Load the hand-tracking model only AFTER the camera is up, so the
      // two heavy start-ups don't compete with each other.
      _warmUpAi();
    } on NoCameraException {
      if (!mounted) return;
      setState(() => _cameraError = 'No camera found on this device.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _cameraError = _friendlyCameraError(e));
    }
  }

  /// Downloads/prepares the hand-tracking model so it is already warm
  /// when "Start Signing" is tapped. Runs once.
  Future<void> _warmUpAi() async {
    if (_aiChecked) return;
    final ok = await _mediaPipeService.init();
    if (!mounted) return;
    setState(() {
      _aiChecked = true;
      _aiReady = ok;
    });
  }

  String _friendlyCameraError(Object e) {
    final message = e.toString();
    if (message.contains('NotAllowedError') ||
        message.contains('CameraAccessDenied') ||
        message.contains('permission')) {
      return 'Camera access was denied. Please allow camera permission and reload.';
    }
    if (message.contains('NotFoundError')) {
      return 'No camera device was found.';
    }
    return 'Could not start the camera. Please check your device and try again.';
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _mediaPipeService.dispose();
    _classifyTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  String? get _token =>
      Provider.of<AuthService>(context, listen: false).accessToken;

  // Toggles the whole recognition flow: camera was already running
  // from Step 3a; this starts/stops MediaPipe hand detection AND the
  // periodic classify polling that drives the (still dummy-model-
  // backed) word stream.
  void _toggleSigning() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera is not ready yet.')),
      );
      return;
    }

    if (!_isSigning) {
      setState(() => _isMediaPipeStarting = true);
      final started = await _mediaPipeService.startDetection();
      if (!mounted) return;
      setState(() => _isMediaPipeStarting = false);

      if (!started) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Hand detection could not start — camera preview will still work.'),
          ),
        );
      }

      setState(() {
        _isSigning = true;
        _wordStream.clear();
        _generatedSentence = null;
        _expressionLabel = 'Neutral';
        _lastAddedWord = null;
      });

      _lastHandSeenAt = DateTime.now();
      _classifyTimer = Timer.periodic(
        const Duration(milliseconds: 1200),
        (_) => _pollClassify(),
      );
    } else {
      _stopSigning(keepResult: false);
    }
  }

  void _stopSigning({required bool keepResult}) {
    _classifyTimer?.cancel();
    _classifyTimer = null;
    _mediaPipeService.stopDetection();
    setState(() {
      _isSigning = false;
      _handDetected = false;
      _handCount = 0;
      if (!keepResult) {
        _wordStream.clear();
        _generatedSentence = null;
        _expressionLabel = 'Neutral';
      }
    });
  }

  // Called every ~1.2s while signing. Sends the latest hand landmarks
  // to the (dummy) classifier, appends a new word if one comes back
  // and it's different from the last word added (basic de-dupe so
  // holding a pose doesn't spam the same word repeatedly). Also
  // watches for a pause (no hand for 1.5s after collecting at least
  // one word) to auto-trigger sentence generation, mirroring the
  // original demo's "pause to generate" behavior.
  Future<void> _pollClassify() async {
    if (!_isSigning || _isGenerating) return;

    final token = _token;
    if (token == null) return;

    // Pause detection: hand missing for a while after some words
    // were collected → generate the sentence automatically.
    if (_wordStream.isNotEmpty &&
        !_handDetected &&
        _lastHandSeenAt != null &&
        DateTime.now().difference(_lastHandSeenAt!) >
            const Duration(milliseconds: 1500)) {
      await _generateSentence();
      return;
    }

    if (!_handDetected || _latestLandmarks.isEmpty) return;

    final result = await _recognitionService.classify(
      token: token,
      handLandmarks: _latestLandmarks,
    );

    if (!mounted || !_isSigning) return;

    if (result['success'] == true) {
      final word = result['word'] as String?;
      final expression = result['expression'] as String? ?? 'Neutral';

      setState(() => _expressionLabel = expression);

      _lastShownError = null;

      if (word != null && word != _lastAddedWord) {
        setState(() {
          _wordStream.add(word);
          _lastAddedWord = word;
        });
      }
    } else {
      // Previously a failed request was ignored silently, which looked
      // like "the app does nothing". Tell the person what went wrong.
      final message =
          result['message'] as String? ?? 'Recognition request failed';
      if (message != _lastShownError) {
        _lastShownError = message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _generateSentence() async {
    final token = _token;
    if (token == null || _wordStream.isEmpty) return;

    setState(() => _isGenerating = true);

    final result = await _recognitionService.generate(
      token: token,
      wordSequence: _wordStream,
      expressionContext: _expressionLabel,
    );

    if (!mounted) return;
    setState(() => _isGenerating = false);

    if (result['success'] == true) {
      setState(() => _generatedSentence = result['urdu_sentence'] as String?);
      _stopSigning(keepResult: true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Could not generate sentence'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _playAudio() async {
    if (_generatedSentence == null || _isSpeaking) return;

    final token = _token;
    if (token == null) return;

    setState(() => _isSpeaking = true);

    final result = await _audioService.speak(
      token: token,
      text: _generatedSentence!,
    );

    if (!mounted) return;
    setState(() => _isSpeaking = false);

    if (result['success'] == true) {
      await _audioPlayer.play(BytesSource(result['bytes'] as Uint8List));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Could not play audio'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('PSL Recognition',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white54),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('How to use HamKalaam'),
                  content: const Text(
                    '1. Tap "Start Signing" to begin\n'
                    '2. Sign PSL gestures in front of the camera\n'
                    '3. Words appear in real time as you sign\n'
                    '4. Pause for 1 second to generate the Urdu sentence\n'
                    '5. The sentence is spoken aloud automatically',
                    style: TextStyle(height: 1.6),
                  ),
                  actions: [
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Got it'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Camera Preview Area
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                Container(
                  width: double.infinity,
                  height: double.infinity,
                  color: Colors.grey[900],
                  child: _buildCameraArea(),
                ),

                // Expression badge
                if (_isSigning)
                  Positioned(
                    top: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          const Text('😐 ', style: TextStyle(fontSize: 14)),
                          Text(
                            _expressionLabel,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Real hand-detection badge (MediaPipe)
                if (_isSigning)
                  Positioned(
                    top: 20,
                    left: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: (_handDetected ? Colors.green : Colors.grey)
                            .withOpacity(0.85),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _handDetected
                                ? Icons.fiber_manual_record
                                : Icons.search,
                            color: Colors.white,
                            size: 10,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _handDetected
                                ? 'Hand Detected${_handCount > 1 ? " ($_handCount)" : ""}'
                                : 'Searching for hand...',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),

                // AI Badge
                Positioned(
                  bottom: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: (_isSigning || _aiReady) ? Colors.green : Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isSigning
                              ? 'AI Active'
                              : (!_aiChecked
                                  ? 'AI Loading...'
                                  : (_aiReady ? 'AI Ready' : 'AI Standby')),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom Panel
          Expanded(
            flex: 4,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Word Stream
                    const Text(
                      'Word Stream',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: _wordStream.isEmpty
                          ? Text(
                              'Words will appear here as you sign...',
                              style: TextStyle(
                                  color: Colors.grey[400], fontSize: 13),
                            )
                          : Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _wordStream
                                  .map((word) => Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1F3864)
                                              .withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          word,
                                          style: const TextStyle(
                                            color: Color(0xFF1F3864),
                                            fontWeight: FontWeight.w500,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ))
                                  .toList(),
                            ),
                    ),

                    const SizedBox(height: 16),

                    // Generated Sentence
                    const Text(
                      'Generated Sentence',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _generatedSentence != null
                            ? const Color(0xFF1F3864).withOpacity(0.05)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _generatedSentence != null
                              ? const Color(0xFF1F3864).withOpacity(0.2)
                              : Colors.grey[200]!,
                        ),
                      ),
                      child: _generatedSentence != null
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _generatedSentence!,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1F3864),
                                    height: 1.5,
                                  ),
                                  textDirection: TextDirection.rtl,
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: _isSpeaking ? null : _playAudio,
                                        icon: _isSpeaking
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child: CircularProgressIndicator(
                                                    strokeWidth: 2),
                                              )
                                            : const Icon(
                                                Icons.volume_up_outlined),
                                        label: Text(_isSpeaking
                                            ? 'Loading...'
                                            : 'Play Audio'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor:
                                              const Color(0xFF1F3864),
                                          side: const BorderSide(
                                              color: Color(0xFF1F3864)),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      onPressed: () {
                                        setState(() {
                                          _generatedSentence = null;
                                          _wordStream.clear();
                                          _lastAddedWord = null;
                                        });
                                      },
                                      icon: const Icon(Icons.refresh,
                                          color: Colors.grey),
                                      tooltip: 'Clear',
                                    ),
                                  ],
                                ),
                              ],
                            )
                          : Text(
                              'Your Urdu sentence will appear here after signing...',
                              style: TextStyle(
                                  color: Colors.grey[400], fontSize: 13),
                            ),
                    ),

                    const SizedBox(height: 20),

                    // Start/Stop button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: (_isMediaPipeStarting || _isGenerating)
                            ? null
                            : _toggleSigning,
                        icon: (_isMediaPipeStarting || _isGenerating)
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Icon(
                                _isSigning ? Icons.stop : Icons.sign_language,
                              ),
                        label: Text(
                          _isMediaPipeStarting
                              ? 'Starting AI model...'
                              : _isGenerating
                                  ? 'Generating sentence...'
                                  : (_isSigning
                                      ? 'Stop Signing'
                                      : 'Start Signing'),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isSigning
                              ? Colors.red[600]
                              : const Color(0xFF1F3864),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds whatever the camera area should show: loading spinner,
  /// error message, or the real live camera feed.
  Widget _buildCameraArea() {
    if (_cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.videocam_off, size: 60, color: Colors.white24),
              const SizedBox(height: 12),
              Text(
                _cameraError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _cameraError = null;
                    _initializeCameraFuture = _initCamera();
                  });
                },
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

    return FutureBuilder<void>(
      future: _initializeCameraFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            _cameraController == null ||
            !_cameraController!.value.isInitialized) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.white38),
                const SizedBox(height: 14),
                Text(
                  _cameraStatus,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          );
        }

        // Real live camera preview, filling the available area.
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _cameraController!.value.previewSize?.height ?? 1,
                height: _cameraController!.value.previewSize?.width ?? 1,
                child: CameraPreview(_cameraController!),
              ),
            ),
          ),
        );
      },
    );
  }
}
