// web/mediapipe_bridge.js
//
// Bridges MediaPipe's HandLandmarker (loaded from CDN) into a set of
// plain functions on `window.hamkalaamMediaPipe` that Dart can call via
// dart:js_interop. Runs its own independent hidden camera stream for
// detection, completely separate from the visible Flutter `camera`
// package preview — this avoids needing to reach into camera_web's
// internal (and unpredictable) <video> element.

import {
  FilesetResolver,
  HandLandmarker,
} from "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.20/vision_bundle.mjs";

window.hamkalaamMediaPipe = (function () {
  let handLandmarker = null;
  let hiddenVideo = null;
  let stream = null;
  let running = false;
  let lastVideoTime = -1;

  let latestResult = { handDetected: false, handCount: 0 };

  async function init() {
    if (handLandmarker) return true; // already initialized
    const vision = await FilesetResolver.forVisionTasks(
      "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.20/wasm"
    );
    handLandmarker = await HandLandmarker.createFromOptions(vision, {
      baseOptions: {
        modelAssetPath:
          "https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task",
        delegate: "GPU",
      },
      runningMode: "VIDEO",
      numHands: 2,
    });
    return true;
  }

  async function startDetection() {
    if (running) return true;
    if (!handLandmarker) {
      await init();
    }

    stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: "user" },
    });

    hiddenVideo = document.createElement("video");
    hiddenVideo.style.display = "none";
    hiddenVideo.autoplay = true;
    hiddenVideo.playsInline = true;
    hiddenVideo.muted = true;
    hiddenVideo.srcObject = stream;
    document.body.appendChild(hiddenVideo);
    await hiddenVideo.play();

    running = true;
    lastVideoTime = -1;
    requestAnimationFrame(detectLoop);
    return true;
  }

  function stopDetection() {
    running = false;
    if (stream) {
      stream.getTracks().forEach((t) => t.stop());
      stream = null;
    }
    if (hiddenVideo) {
      hiddenVideo.remove();
      hiddenVideo = null;
    }
    latestResult = { handDetected: false, handCount: 0 };
  }

  function detectLoop() {
    if (!running || !handLandmarker || !hiddenVideo) return;

    if (
      hiddenVideo.currentTime !== lastVideoTime &&
      hiddenVideo.readyState >= 2
    ) {
      lastVideoTime = hiddenVideo.currentTime;
      const nowMs = performance.now();
      try {
        const result = handLandmarker.detectForVideo(hiddenVideo, nowMs);
        const count = result.landmarks ? result.landmarks.length : 0;
        latestResult = { handDetected: count > 0, handCount: count };
      } catch (e) {
        // Swallow per-frame detection errors so the loop keeps running;
        // a single bad frame shouldn't kill the whole detection loop.
        console.error("MediaPipe detectForVideo error:", e);
      }
    }

    requestAnimationFrame(detectLoop);
  }

  function getLatestResult() {
    return JSON.stringify(latestResult);
  }

  return { init, startDetection, stopDetection, getLatestResult };
})();