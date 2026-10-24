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

/// Live state of the automatic word cutter (continuous mode).
class SegmentStatus {
  final String state; // 'idle' (waiting) or 'signing' (a word is being cut)
  final int queued; // finished words waiting to be classified
  final int msSinceHand; // how long since a hand was last seen
  final int discarded; // too-short segments that were ignored

  const SegmentStatus({
    required this.state,
    required this.queued,
    required this.msSinceHand,
    required this.discarded,
  });

  static const idle =
      SegmentStatus(state: 'idle', queued: 0, msSinceHand: 0, discarded: 0);

  bool get isSigning => state == 'signing';
}
