/// One recorded signing window: exactly 60 frames x 126 numbers
/// (same shape as the training dataset), plus a few quality numbers.
class HandWindow {
  final List<List<double>> frames; // 60 x 126, or empty if too little data
  final int handFrames; // how many of the 60 frames had a hand
  final int rawCount; // real camera frames seen during the window
  final int durationMs;

  const HandWindow({
    required this.frames,
    required this.handFrames,
    required this.rawCount,
    required this.durationMs,
  });

  static const empty =
      HandWindow(frames: [], handFrames: 0, rawCount: 0, durationMs: 0);

  bool get isUsable => frames.length == 60;

  /// Share of frames that contained a hand (0.0 - 1.0).
  double get handRatio => frames.isEmpty ? 0 : handFrames / frames.length;
}
