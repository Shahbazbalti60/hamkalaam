import 'package:camera/camera.dart';

/// Thrown when the device really has no camera.
class NoCameraException implements Exception {
  @override
  String toString() => 'No camera found on this device.';
}

/// Opens the front camera reliably.
///
/// Why this exists: in the browser, the camera sometimes fails to start
/// with a transient "cameraAbort" error, mostly right after the
/// permission prompt or when the device has not been fully released yet.
/// The fixes here:
///   * list the cameras ONCE (listing itself briefly opens the camera);
///   * ALWAYS close a half-opened controller before the next attempt
///     (a leaked one keeps the device locked and makes every retry fail);
///   * wait longer between attempts (700ms, 1.4s, 2.1s ...);
///   * report progress so the screen can say "waking up... try 3 of 6"
///     instead of looking frozen or showing an error straight away.
class CameraHelper {
  static bool _isTransient(Object e) =>
      (e is CameraException && e.code == 'cameraAbort') ||
      e.toString().contains('cameraAbort');

  /// Returns the ready controller, or null if [isCancelled] became true
  /// (e.g. the person left the screen while it was still retrying).
  static Future<CameraController?> openFrontCamera({
    ResolutionPreset preset = ResolutionPreset.medium,
    int maxAttempts = 6,
    void Function(int attempt, int maxAttempts)? onAttempt,
    bool Function()? isCancelled,
  }) async {
    bool cancelled() => isCancelled?.call() ?? false;

    // 1) Find the cameras (once).
    List<CameraDescription> cameras = [];
    for (var i = 1; i <= 3; i++) {
      try {
        cameras = await availableCameras();
        break;
      } catch (e) {
        if (!_isTransient(e) || i == 3) rethrow;
        await Future.delayed(const Duration(milliseconds: 700));
      }
    }
    if (cameras.isEmpty) throw NoCameraException();
    if (cancelled()) return null;

    // Prefer the front camera (the person signs facing the device).
    final selected = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    // Give the device a moment to be released after the permission probe.
    await Future.delayed(const Duration(milliseconds: 500));

    // 2) Open it, patiently.
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (cancelled()) return null;
      onAttempt?.call(attempt, maxAttempts);

      final controller = CameraController(
        selected,
        preset,
        enableAudio: false,
      );

      try {
        await controller.initialize();
        if (cancelled()) {
          await controller.dispose();
          return null;
        }
        return controller;
      } catch (e) {
        // Always release the half-opened camera before trying again.
        try {
          await controller.dispose();
        } catch (_) {}

        if (!_isTransient(e) || attempt == maxAttempts) rethrow;
        await Future.delayed(Duration(milliseconds: 700 * attempt));
      }
    }
    return null;
  }
}
