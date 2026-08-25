import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../services/mediapipe_service.dart';

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

  // --- MediaPipe hand detection state (Step 3b) ---
  final MediaPipeService _mediaPipeService = MediaPipeService();
  bool _isMediaPipeStarting = false;
  bool _handDetected = false;
  int _handCount = 0;

  @override
  void initState() {
    super.initState();
    _initializeCameraFuture = _initCamera();
    _mediaPipeService.results.listen((result) {
      if (!mounted) return;
      setState(() {
        _handDetected = result.handDetected;
        _handCount = result.handCount;
      });
    });
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _cameraError = 'No camera found on this device.');
        return;
      }

      // Prefer the front camera (selfie-style) since the person signs
      // facing their own device, same as a video call.
      final selectedCamera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller.initialize();

      if (!mounted) return;

      setState(() {
        _cameraController = controller;
        _cameraError = null;
      });
    } catch (e) {
      if (!mounted) return;
      // TEMP DEBUG: print raw exception to terminal to diagnose.
      // ignore: avoid_print
      print('CAMERA INIT ERROR (raw): $e');
      setState(() {
        _cameraError = _friendlyCameraError(e);
      });
    }
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
    super.dispose();
  }

  // Dummy demo flow — word stream / sentence generation is still
  // simulated for now. Real word/sentence output needs the trained
  // gesture classifier (Phase 4/6). Hand *detection* (this toggle)
  // is real, powered by MediaPipe.
  void _toggleSigning() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera is not ready yet.')),
      );
      return;
    }

    if (!_isSigning) {
      // Starting: fire up MediaPipe hand detection before flipping
      // _isSigning, so the button shows a loading state during the
      // (first-time) model download.
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

      setState(() => _isSigning = true);
      _runDemoFlow();
    } else {
      _mediaPipeService.stopDetection();
      setState(() {
        _isSigning = false;
        _wordStream.clear();
        _generatedSentence = null;
        _expressionLabel = 'Neutral';
        _handDetected = false;
        _handCount = 0;
      });
    }
  }

  Future<void> _runDemoFlow() async {
    // Simulate word recognition
    await Future.delayed(const Duration(seconds: 2));
    if (!_isSigning || !mounted) return;
    setState(() {
      _wordStream.add('پانی');
      _expressionLabel = 'Question';
    });

    await Future.delayed(const Duration(seconds: 2));
    if (!_isSigning || !mounted) return;
    setState(() => _wordStream.add('دینا'));

    await Future.delayed(const Duration(seconds: 2));
    if (!_isSigning || !mounted) return;
    setState(() => _wordStream.add('مجھے'));

    await Future.delayed(const Duration(seconds: 2));
    if (!_isSigning || !mounted) return;
    // Simulate pause → sentence generation
    setState(() {
      _generatedSentence = 'کیا آپ مجھے پانی دے سکتے ہیں؟';
      _isSigning = false;
    });
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
                            color: _isSigning ? Colors.green : Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isSigning ? 'AI Active' : 'AI Standby',
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
                                        onPressed: () {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                  'Audio — ElevenLabs TTS coming soon!'),
                                            ),
                                          );
                                        },
                                        icon: const Icon(
                                            Icons.volume_up_outlined),
                                        label: const Text('Play Audio'),
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
                        onPressed: _isMediaPipeStarting ? null : _toggleSigning,
                        icon: _isMediaPipeStarting
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
                              : (_isSigning ? 'Stop Signing' : 'Start Signing'),
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
          return const Center(
            child: CircularProgressIndicator(color: Colors.white38),
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