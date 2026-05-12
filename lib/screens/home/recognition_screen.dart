import 'package:flutter/material.dart';

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

  // Dummy demo flow
  void _toggleSigning() {
    setState(() {
      _isSigning = !_isSigning;
      if (!_isSigning) {
        _wordStream.clear();
        _generatedSentence = null;
        _expressionLabel = 'Neutral';
      }
    });

    if (_isSigning) {
      _runDemoFlow();
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
                // Camera placeholder
                Container(
                  width: double.infinity,
                  color: Colors.grey[900],
                  child: _isSigning
                      ? Stack(
                          children: [
                            // Simulated camera feed
                            Container(
                              width: double.infinity,
                              height: double.infinity,
                              color: Colors.grey[850],
                              child: const Center(
                                child: Icon(
                                  Icons.videocam,
                                  size: 80,
                                  color: Colors.white12,
                                ),
                              ),
                            ),
                            // Landmark overlay simulation
                            Positioned(
                              top: 20,
                              left: 20,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.8),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.fiber_manual_record,
                                        color: Colors.white, size: 10),
                                    SizedBox(width: 4),
                                    Text('Hand Detected',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.videocam_off,
                                  size: 60, color: Colors.white24),
                              const SizedBox(height: 12),
                              const Text(
                                'Camera inactive',
                                style: TextStyle(
                                    color: Colors.white38, fontSize: 14),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Tap "Start Signing" to begin',
                                style: TextStyle(
                                    color: Colors.white24, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
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
                        onPressed: _toggleSigning,
                        icon: Icon(
                          _isSigning ? Icons.stop : Icons.sign_language,
                        ),
                        label: Text(
                          _isSigning ? 'Stop Signing' : 'Start Signing',
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
}

