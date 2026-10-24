import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../data/psl_words_ur.dart';
import '../../services/auth_service.dart';
import '../../services/mediapipe_service.dart';
import '../../services/hand_window.dart';
import '../../services/camera_helper.dart';
import '../../services/recognition_service.dart';
import '../../services/audio_service.dart';
import '../../services/session_service.dart';

class _Guess {
  final String word; // model label (English key)
  final double confidence;
  const _Guess(this.word, this.confidence);
}

class RecognitionScreen extends StatefulWidget {
  const RecognitionScreen({super.key});

  @override
  State<RecognitionScreen> createState() => _RecognitionScreenState();
}

class _RecognitionScreenState extends State<RecognitionScreen> {
  static const Color _navy = Color(0xFF1F3864);

  /// No hand for this long after at least one word = the sentence is over.
  static const int _sentencePauseMs = 2000;

  /// Nobody signed anything for this long = stop listening.
  static const int _idleTimeoutMs = 20000;

  // --- session state ---
  bool _listening = false;
  bool _isStarting = false;
  bool _signingNow = false; // a word is being captured right now
  bool _classifying = false;
  bool _finishing = false; // building / speaking the sentence
  bool _ticking = false;
  Timer? _tickTimer;
  String _expressionLabel = 'Neutral';

  /// Model labels (English keys). Shown to the user as Urdu via [_urdu].
  final List<String> _wordStream = [];
  String? _generatedSentence;

  // --- last result message ---
  String? _resultMessage;
  bool _resultIsGood = false;
  List<_Guess> _suggestions = [];

  // --- Camera ---
  CameraController? _cameraController;
  Future<void>? _initializeCameraFuture;
  String? _cameraError;
  String _cameraStatus = 'Starting camera...';

  // --- MediaPipe ---
  final MediaPipeService _mediaPipeService = MediaPipeService();
  StreamSubscription? _handSub;
  bool _handDetected = false;
  int _handCount = 0;
  bool _aiChecked = false;
  bool _aiReady = false;
  bool _modelChecked = false;
  bool _modelReady = false;

  // --- Services ---
  final RecognitionService _recognitionService = RecognitionService();
  final AudioService _audioService = AudioService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isSpeaking = false;
  bool _audioFailed = false; // last audio request failed -> show Retry
  Uint8List? _audioCache; // last spoken audio, so replay needs no network
  String? _audioCacheFor;

  // --- History logging ---
  final SessionService _sessionService = SessionService();
  int? _sessionId; // created lazily on the first sentence

  @override
  void initState() {
    super.initState();
    _initializeCameraFuture = _initCamera();
    _handSub = _mediaPipeService.results.listen((result) {
      if (!mounted) return;
      if (result.handDetected != _handDetected ||
          result.handCount != _handCount) {
        setState(() {
          _handDetected = result.handDetected;
          _handCount = result.handCount;
        });
      }
    });
  }

  String _urdu(String label) => pslUrdu[label] ?? label;

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

      _warmUpAi();
    } on NoCameraException {
      if (!mounted) return;
      setState(() => _cameraError = 'No camera found on this device.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _cameraError = _friendlyCameraError(e));
    }
  }

  /// Loads the browser hand model AND the server LSTM before first use.
  Future<void> _warmUpAi() async {
    if (_aiChecked && _modelChecked) return;
    final token = _token;

    final hand = _mediaPipeService.init().then((ok) {
      if (!mounted) return;
      setState(() {
        _aiChecked = true;
        _aiReady = ok;
      });
    });

    final server = () async {
      if (token == null) return;
      final status = await _recognitionService.modelStatus(token: token);
      if (!mounted) return;
      setState(() {
        _modelChecked = true;
        _modelReady = status['success'] == true && status['ready'] == true;
      });
    }();

    await Future.wait([hand, server]);
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
    _tickTimer?.cancel();
    _handSub?.cancel();
    _cameraController?.dispose();
    _mediaPipeService.stopContinuous();
    _mediaPipeService.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  String? get _token =>
      Provider.of<AuthService>(context, listen: false).accessToken;

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : null,
      ),
    );
  }

  // ------------------------------------------------------------------
  // Listening (automatic mode)
  // ------------------------------------------------------------------

  Future<void> _startListening() async {
    if (_listening || _isStarting || _finishing) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      _toast('Camera is not ready yet.');
      return;
    }
    if (_token == null) {
      _toast('Please log in again.', error: true);
      return;
    }

    setState(() => _isStarting = true);
    final started = await _mediaPipeService.startDetection();
    if (!mounted) return;
    setState(() => _isStarting = false);

    if (!started) {
      _toast(
          'Hand detection could not start. It works in Chrome on a computer.',
          error: true);
      return;
    }

    _mediaPipeService.startContinuous();
    setState(() {
      _listening = true;
      _signingNow = false;
      _classifying = false;
      _wordStream.clear();
      _generatedSentence = null;
      _expressionLabel = 'Neutral';
      _resultMessage = null;
      _suggestions = [];
    });

    _tickTimer?.cancel();
    _tickTimer =
        Timer.periodic(const Duration(milliseconds: 150), (_) => _tick());
  }

  void _stopListening({required bool keepResult}) {
    _tickTimer?.cancel();
    _tickTimer = null;
    _mediaPipeService.stopContinuous();
    _mediaPipeService.stopDetection();
    if (!mounted) return;
    setState(() {
      _listening = false;
      _signingNow = false;
      _classifying = false;
      _handDetected = false;
      _handCount = 0;
      if (!keepResult) {
        _wordStream.clear();
        _generatedSentence = null;
        _expressionLabel = 'Neutral';
        _resultMessage = null;
        _suggestions = [];
      }
    });
  }

  /// Runs every 150 ms while listening:
  /// 1) classify any finished word, 2) decide whether the sentence is over.
  Future<void> _tick() async {
    if (!_listening || _ticking || _finishing) return;
    _ticking = true;
    try {
      final status = _mediaPipeService.getSegmentStatus();
      if (mounted && status.isSigning != _signingNow) {
        setState(() => _signingNow = status.isSigning);
      }

      // 1) A finished word is waiting -> classify it.
      if (status.queued > 0) {
        final seg = _mediaPipeService.popSegment();
        if (seg != null) await _classifySegment(seg);
        return;
      }

      if (status.isSigning || _classifying) return;

      // 2) Pause after at least one word -> sentence is over.
      if (_wordStream.isNotEmpty && status.msSinceHand >= _sentencePauseMs) {
        await _finishSentence();
        return;
      }

      // 3) Nobody is signing at all -> stop after a while.
      if (_wordStream.isEmpty && status.msSinceHand >= _idleTimeoutMs) {
        _stopListening(keepResult: false);
        _toast('No signing seen for a while. Tap Start Signing to try again.');
      }
    } finally {
      _ticking = false;
    }
  }

  Future<void> _classifySegment(HandWindow seg) async {
    final token = _token;
    if (token == null || !_listening) return;

    setState(() => _classifying = true);
    final result = await _recognitionService.classifySequence(
      token: token,
      frames: seg.frames,
    );
    if (!mounted) return;
    if (!_listening) {
      setState(() => _classifying = false);
      return;
    }

    if (result['success'] != true) {
      setState(() {
        _classifying = false;
        _resultIsGood = false;
        _resultMessage =
            (result['message'] as String?) ?? 'Recognition request failed';
      });
      return;
    }

    final word = result['word'] as String?;
    final confidence = (result['confidence'] as num?)?.toDouble() ?? 0.0;
    final uncertain = result['uncertain'] == true;
    final top3 = _parseTop3(result['top3']);
    final pct = (confidence * 100).round();

    setState(() {
      _classifying = false;
      if (word != null && !uncertain) {
        _wordStream.add(word);
        _resultIsGood = true;
        _resultMessage = '${_urdu(word)}  ($pct%)';
        _suggestions = [];
      } else {
        _resultIsGood = false;
        _suggestions = top3;
        _resultMessage = top3.isEmpty
            ? 'I could not recognise that sign. Please repeat it.'
            : 'Not sure about that sign. Tap the right word, or repeat it.';
      }
    });
  }

  List<_Guess> _parseTop3(dynamic raw) {
    final out = <_Guess>[];
    if (raw is! List) return out;
    for (final e in raw) {
      if (e is Map) {
        final w = (e['word'] ?? e['label'] ?? e['name'])?.toString();
        final c = e['confidence'] ?? e['prob'] ?? e['probability'] ?? e['score'];
        if (w != null) out.add(_Guess(w, c is num ? c.toDouble() : 0.0));
      } else if (e is List && e.isNotEmpty) {
        final c = e.length > 1 ? e[1] : 0;
        out.add(_Guess(e[0].toString(), c is num ? c.toDouble() : 0.0));
      } else if (e is String) {
        out.add(_Guess(e, 0.0));
      }
    }
    return out;
  }

  void _acceptSuggestion(_Guess g) {
    setState(() {
      _wordStream.add(g.word);
      _resultIsGood = true;
      _resultMessage = _urdu(g.word);
      _suggestions = [];
    });
  }

  // ------------------------------------------------------------------
  // Sentence + audio
  // ------------------------------------------------------------------

  /// FALLBACK only (used if the server cannot be reached): joins the
  /// Urdu words. The real sentence comes from the backend /generate.
  String _buildSentence(List<String> labels) {
    return '${labels.map(_urdu).join(' ')}۔';
  }

  Future<void> _finishSentence() async {
    if (_finishing || _wordStream.isEmpty) return;
    _finishing = true;
    final words = List<String>.from(_wordStream);
    final token = _token;
    _stopListening(keepResult: true);
    if (!mounted) {
      _finishing = false;
      return;
    }
    setState(() {}); // shows "Making sentence..."

    // Real Urdu sentence from the backend rule engine; if the server
    // is unreachable, fall back to simply joining the Urdu words.
    var sentence = _buildSentence(words);
    if (token != null) {
      final result = await _recognitionService.generate(
        token: token,
        wordSequence: words,
        expressionContext: _expressionLabel,
      );
      final text = result['urdu_sentence'];
      if (result['success'] == true && text is String && text.isNotEmpty) {
        sentence = text;
      }
    }
    if (!mounted) {
      _finishing = false;
      return;
    }
    setState(() {
      _generatedSentence = sentence;
      _audioFailed = false;
    });
    if (token != null) {
      // Background: never blocks the speech or the screen.
      unawaited(_saveToHistory(token, sentence, words, _expressionLabel));
    }
    await _playAudio(); // speaks automatically
    _finishing = false;
    if (mounted) setState(() {});
  }

  Future<void> _playAudio() async {
    final sentence = _generatedSentence;
    if (sentence == null || _isSpeaking) return;
    final token = _token;
    if (token == null) return;

    // Replay from memory if we already have this sentence's audio.
    if (_audioCache != null && _audioCacheFor == sentence) {
      await _playBytes(_audioCache!);
      return;
    }

    setState(() {
      _isSpeaking = true;
      _audioFailed = false;
    });
    final result = await _audioService
        .speak(token: token, text: sentence)
        .timeout(
          const Duration(seconds: 8),
          onTimeout: () => <String, dynamic>{'success': false},
        );
    if (!mounted) return;

    if (result['success'] == true) {
      final bytes = result['bytes'] as Uint8List;
      setState(() {
        _isSpeaking = false;
        _audioCache = bytes;
        _audioCacheFor = sentence;
      });
      await _playBytes(bytes);
    } else {
      // Offline fallback: the Urdu text stays on screen, audio can be retried.
      setState(() {
        _isSpeaking = false;
        _audioFailed = true;
      });
      _toast('Audio unavailable - check your connection.', error: true);
    }
  }

  Future<void> _playBytes(Uint8List bytes) async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(BytesSource(bytes));
    } catch (_) {
      _toast('Tap "Play Again" to hear the sentence.');
    }
  }

  /// Saves the sentence to the user's history. Retries up to 3 times
  /// (waiting 1 s, 2 s, 4 s) and only shows a quiet message if all fail.
  Future<void> _saveToHistory(
    String token,
    String sentence,
    List<String> words,
    String expression,
  ) async {
    const waits = [1, 2, 4];
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        if (_sessionId == null) {
          final started = await _sessionService.startSession(token);
          if (started['success'] == true) {
            final session = started['session'];
            final id = session is Map ? (session['id'] ?? session['session_id']) : null;
            if (id is num) _sessionId = id.toInt();
          }
        }
        final id = _sessionId;
        if (id != null) {
          final saved = await _sessionService.saveSentence(
            token: token,
            sessionId: id,
            urduSentence: sentence,
            wordSequence: words,
            expressionContext: expression,
          );
          if (saved['success'] == true) return;
        }
      } catch (_) {
        // fall through to retry
      }
      if (attempt < 2) {
        await Future.delayed(Duration(seconds: waits[attempt]));
      }
    }
    _toast('Could not save this sentence to your history.');
  }

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------

  String get _aiBadgeText {
    if (_listening) return 'AI Active';
    if (!_aiChecked || !_modelChecked) return 'AI Loading...';
    if (_aiReady && _modelReady) return 'AI Ready';
    if (_aiReady && !_modelReady) return 'Server model offline';
    return 'AI Standby';
  }

  bool get _aiBadgeGreen => _listening || (_aiReady && _modelReady);

  String get _liveStatus {
    if (_classifying) return 'Recognising...';
    if (_signingNow) return 'Signing detected...';
    if (_wordStream.isEmpty) return 'Listening. Raise your hand and sign.';
    return 'Listening. Stop signing to finish the sentence.';
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
                    '1. Tap "Start Signing"\n'
                    '2. Sign your words. Put your hands down for a moment between words\n'
                    '3. Each word appears in Urdu as you sign\n'
                    '4. When you stop signing for about 2 seconds, the sentence is made and spoken automatically',
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
          Expanded(flex: 5, child: _buildCameraStack()),
          Expanded(flex: 4, child: _buildBottomPanel()),
        ],
      ),
    );
  }

  Widget _buildCameraStack() {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.grey[900],
          child: _buildCameraArea(),
        ),

        if (_listening)
          Positioned(
            top: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _expressionLabel,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ),

        if (_listening)
          Positioned(
            top: 20,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: (_handDetected ? Colors.green : Colors.grey)
                    .withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    _handDetected ? Icons.fiber_manual_record : Icons.search,
                    color: Colors.white,
                    size: 10,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _handDetected
                        ? 'Hand Detected${_handCount > 1 ? " ($_handCount)" : ""}'
                        : 'Searching for hand...',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),

        // Live status line
        if (_listening)
          Positioned(
            left: 16,
            right: 16,
            bottom: 48,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: (_signingNow ? Colors.red : Colors.black)
                      .withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _liveStatus,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),

        // AI badge
        Positioned(
          bottom: 16,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                    color: _aiBadgeGreen ? Colors.green : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(_aiBadgeText,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomPanel() {
    return Container(
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
            _sectionLabel('Word Stream'),
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
                  ? Text('Recognised words will appear here...',
                      style: TextStyle(color: Colors.grey[400], fontSize: 13))
                  : Directionality(
                      textDirection: TextDirection.rtl,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (var i = 0; i < _wordStream.length; i++)
                            InputChip(
                              label: Text(_urdu(_wordStream[i])),
                              labelStyle: const TextStyle(
                                  color: _navy,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 20),
                              backgroundColor: _navy.withValues(alpha: 0.1),
                              onDeleted: _finishing
                                  ? null
                                  : () =>
                                      setState(() => _wordStream.removeAt(i)),
                            ),
                        ],
                      ),
                    ),
            ),

            if (_resultMessage != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    _resultIsGood
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                    size: 18,
                    color: _resultIsGood ? Colors.green : Colors.orange[800],
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _resultMessage!,
                      style: TextStyle(
                        fontSize: 15,
                        color: _resultIsGood
                            ? Colors.green[800]
                            : Colors.orange[900],
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (_suggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final g in _suggestions)
                    ActionChip(
                      label: Text(
                        '${_urdu(g.word)}${g.confidence > 0 ? "  ${(g.confidence * 100).round()}%" : ""}',
                        style: const TextStyle(fontSize: 16),
                      ),
                      onPressed: () => _acceptSuggestion(g),
                    ),
                ],
              ),
            ],

            const SizedBox(height: 16),
            _sectionLabel('Generated Sentence'),
            const SizedBox(height: 8),
            _buildSentenceBox(),
            const SizedBox(height: 20),
            _buildButtons(),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.grey,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildSentenceBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _generatedSentence != null
            ? _navy.withValues(alpha: 0.05)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _generatedSentence != null
              ? _navy.withValues(alpha: 0.2)
              : Colors.grey[200]!,
        ),
      ),
      child: _generatedSentence != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    _generatedSentence!,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: _navy,
                      height: 1.6,
                    ),
                    textDirection: TextDirection.rtl,
                  ),
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
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(_audioFailed
                                ? Icons.refresh
                                : Icons.volume_up_outlined),
                        label: Text(_isSpeaking
                            ? 'Speaking...'
                            : (_audioFailed ? 'Retry audio' : 'Play Again')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _navy,
                          side: const BorderSide(color: _navy),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _generatedSentence = null;
                          _audioFailed = false;
                          _wordStream.clear();
                          _resultMessage = null;
                          _suggestions = [];
                        });
                      },
                      icon: const Icon(Icons.refresh, color: Colors.grey),
                      tooltip: 'Clear',
                    ),
                  ],
                ),
              ],
            )
          : Text('Your Urdu sentence will appear here...',
              style: TextStyle(color: Colors.grey[400], fontSize: 13)),
    );
  }

  Widget _buildButtons() {
    if (!_listening) {
      final busy = _isStarting || _isSpeaking || _finishing;
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: busy ? null : _startListening,
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.sign_language),
          label: Text(
            _isStarting
                ? 'Starting camera...'
                : (_finishing && !_isSpeaking
                    ? 'Making sentence...'
                    : _isSpeaking
                    ? 'Speaking...'
                    : (_generatedSentence != null
                        ? 'Sign again'
                        : 'Start Signing')),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _navy,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }

    // Listening: Stop + manual "make sentence now" as a backup.
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: (_wordStream.isEmpty || _classifying)
                ? null
                : _finishSentence,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Sentence now'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _navy,
              minimumSize: const Size(0, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _stopListening(keepResult: false),
            icon: const Icon(Icons.stop),
            label: const Text('Stop',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[600],
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

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
