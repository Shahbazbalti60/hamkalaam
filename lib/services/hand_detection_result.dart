/// Result of the latest hand-detection frame.
class HandDetectionResult {
  final bool handDetected;
  final int handCount;

  const HandDetectionResult({
    required this.handDetected,
    required this.handCount,
  });

  static const none = HandDetectionResult(handDetected: false, handCount: 0);
}