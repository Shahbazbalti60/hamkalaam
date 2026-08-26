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

  let latestResult = { handDetected: false, handCount: 0, landmarks: [] };

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
    latestResult = { handDetected: false, handCount: 0, landmarks: [] };
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

        // Flatten landmarks into a flat [x,y,z, x,y,z, ...] array,
        // padded/truncated to a fixed shape of 2 hands x 21 points x
        // 3 coords = 126 values, so the backend always receives a
        // consistent-length input regardless of how many hands (0,
        // 1, or 2) are actually visible.
        const flat = [];
        for (let h = 0; h < 2; h++) {
          const hand = result.landmarks && result.landmarks[h];
          for (let p = 0; p < 21; p++) {
            const point = hand && hand[p];
            flat.push(point ? point.x : 0);
            flat.push(point ? point.y : 0);
            flat.push(point ? point.z : 0);
          }
        }

        latestResult = {
          handDetected: count > 0,
          handCount: count,
          landmarks: flat,
        };
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