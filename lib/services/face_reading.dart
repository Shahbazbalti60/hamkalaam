/// The latest face seen by the camera: 68 landmarks as 136 numbers
/// (x1, y1, x2, y2, ... in camera pixels), exactly the input the
/// server's expression model expects (SRDS FR-20).
class FaceReading {
  final bool detected;
  final List<double> points; // 136 numbers when detected, otherwise empty

  const FaceReading({required this.detected, required this.points});

  static const none = FaceReading(detected: false, points: []);
}
