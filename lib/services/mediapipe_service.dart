/// Public entry point for hand-detection via MediaPipe.
///
/// On web, this exports the real implementation that talks to the JS
/// bridge in web/mediapipe_bridge.js. On non-web platforms (e.g. the
/// Android build), it exports a no-op stub — MediaPipe-in-browser is
/// only wired up for the web target in this phase (per the FYP plan:
/// "MediaPipe.js in browser").
library;

export 'mediapipe_service_stub.dart'
    if (dart.library.js_interop) 'mediapipe_service_web.dart';