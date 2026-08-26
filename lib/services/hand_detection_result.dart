/// Result of the latest hand-detection frame.
class HandDetectionResult {
  final bool handDetected;
  final int handCount;

  /// Flattened [x,y,z, x,y,z, ...] hand landmark coordinates.
  /// Fixed length of 126 (2 hands x 21 points x 3 coords), padded
  /// with zeros for hands not currently visible. Empty when
  /// detection hasn't started or MediaPipe isn't available
  /// (non-web platforms).
  final List<double> landmarks;

  const HandDetectionResult({
    required this.handDetected,
    required this.handCount,
    this.landmarks = const [],
  });

  static const none = HandDetectionResult(
    handDetected: false,
    handCount: 0,
    landmarks: [],
  );
}