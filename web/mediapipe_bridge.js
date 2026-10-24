// web/mediapipe_bridge.js
//
// Bridges MediaPipe's HandLandmarker (loaded from CDN) into a set of
// plain functions on `window.hamkalaamMediaPipe` that Dart can call via
// dart:js_interop. Runs its own independent hidden camera stream for
// detection, completely separate from the visible Flutter `camera`
// package preview.
//
// DAY 1 ADDITION: startWindow() / stopWindow() record every detected
// frame (with a timestamp) and return exactly 60 evenly spaced frames,
// the same shape as the training dataset (60 x 126).

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

  const WINDOW_FRAMES = 60;      // frames the model expects
  const MAX_BUFFER = 600;        // safety cap (about 20 s at 30 fps)
  let recording = false;
  let windowBuffer = [];         // [{t: ms, flat: [126 numbers], hand: bool}]

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
    recording = false;
    windowBuffer = [];
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

  function round5(v) {
    return Math.round(v * 100000) / 100000;
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

        // 2 hands x 21 points x 3 coords = 126 values, zeros when absent.
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

        // Window recording: keep EVERY processed frame, including
        // frames with no hand (all zeros) - the dataset has those too.
        if (recording && windowBuffer.length < MAX_BUFFER) {
          windowBuffer.push({ t: nowMs, flat: flat, hand: count > 0 });
        }
      } catch (e) {
        console.error("MediaPipe detectForVideo error:", e);
      }
    }

    requestAnimationFrame(detectLoop);
  }

  function getLatestResult() {
    return JSON.stringify(latestResult);
  }

  // ---- window recording -------------------------------------------

  function startWindow() {
    windowBuffer = [];
    recording = true;
  }

  // Pick `target` frames evenly spaced in TIME (nearest real frame, no
  // blending, so "no hand" zeros are never mixed into real landmarks).
  function resample(buf, target) {
    const n = buf.length;
    if (n === 0) return [];
    const t0 = buf[0].t;
    const t1 = buf[n - 1].t;
    const out = [];
    let j = 0;
    for (let i = 0; i < target; i++) {
      const want = target === 1 ? t0 : t0 + ((t1 - t0) * i) / (target - 1);
      while (j < n - 1 && Math.abs(buf[j + 1].t - want) <= Math.abs(buf[j].t - want)) {
        j++;
      }
      out.push(buf[j]);
    }
    return out;
  }

  // Stops recording and returns JSON:
  // {frames: [[126],...60], handFrames: n, rawCount: n, durationMs: n}
  function stopWindow() {
    recording = false;
    const buf = windowBuffer;
    windowBuffer = [];
    if (buf.length < 5) {
      return JSON.stringify({ frames: [], handFrames: 0, rawCount: buf.length, durationMs: 0 });
    }
    const picked = resample(buf, WINDOW_FRAMES);
    let handFrames = 0;
    const frames = picked.map((f) => {
      if (f.hand) handFrames++;
      return f.flat.map(round5);
    });
    return JSON.stringify({
      frames: frames,
      handFrames: handFrames,
      rawCount: buf.length,
      durationMs: Math.round(buf[buf.length - 1].t - buf[0].t),
    });
  }

  return {
    init, startDetection, stopDetection, getLatestResult,
    startWindow, stopWindow,
    _resampleForTest: resample,
  };
})();
