// web/mediapipe_bridge.js
//
// Bridges MediaPipe's HandLandmarker (loaded from CDN) into a set of
// plain functions on `window.hamkalaamMediaPipe` that Dart can call via
// dart:js_interop. Runs its own independent hidden camera stream for
// detection, completely separate from the visible Flutter `camera`
// package preview.
//
// startWindow()/stopWindow(): fixed-window recording (60 x 126).
// startContinuous()/popSegment()/getSegmentStatus(): automatic mode.
// A small state machine cuts the live frame stream into one segment per
// signed word (hand appears -> hand gone for END_GAP_MS), resamples each
// segment to 60 frames and queues it for the classifier.

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

  // ---- continuous segmenter -----------------------------------------
  const SEG = {
    startHandMs: 120,   // hand must be present this long to start a word
    endGapMs: 700,      // no hand this long = the word is finished
    maxMs: 3500,        // force-cut a very long segment
    minMs: 400,         // ignore shorter segments (hand just passing by)
    minHandFrames: 8,   // ignore segments with fewer hand frames
    preRollMs: 300,     // keep a little time before the first hand frame
    postRollMs: 300,    // ... and after the last one
  };
  let contActive = false;
  let ring = [];            // recent frames (for pre-roll)
  let segState = "idle";    // "idle" | "signing"
  let handRunStart = null;
  let segFrames = [];
  let lastHandT = 0;        // last frame time that had a hand (in segment)
  let lastHandSeenT = 0;    // last frame time that had a hand (anywhere)
  let lastFrameT = 0;
  let segQueue = [];
  let discarded = 0;

  function resetSegmenter(t0) {
    ring = [];
    segState = "idle";
    handRunStart = null;
    segFrames = [];
    segQueue = [];
    discarded = 0;
    lastHandT = t0;
    lastHandSeenT = t0;
    lastFrameT = t0;
  }

  function startContinuous() {
    resetSegmenter(performance.now());
    contActive = true;
  }

  function stopContinuous() {
    contActive = false;
    resetSegmenter(0);
  }

  function finishSegment() {
    const keepUntil = lastHandT + SEG.postRollMs;
    const trimmed = segFrames.filter((f) => f.t <= keepUntil);
    segFrames = [];
    segState = "idle";
    handRunStart = null;
    const handFrames = trimmed.filter((f) => f.hand).length;
    const dur = trimmed.length ? trimmed[trimmed.length - 1].t - trimmed[0].t : 0;
    if (handFrames < SEG.minHandFrames || dur < SEG.minMs) {
      discarded++;
      return;
    }
    const picked = resample(trimmed, WINDOW_FRAMES);
    segQueue.push({
      frames: picked.map((f) => f.flat.map(round5)),
      handFrames: picked.filter((f) => f.hand).length,
      rawCount: trimmed.length,
      durationMs: Math.round(dur),
    });
  }

  function processFrame(t, flat, hasHand) {
    lastFrameT = t;
    const frame = { t: t, flat: flat, hand: hasHand };
    if (hasHand) lastHandSeenT = t;

    if (segState === "idle") {
      ring.push(frame);
      while (ring.length && t - ring[0].t > SEG.preRollMs + SEG.startHandMs + 200) {
        ring.shift();
      }
      if (hasHand) {
        if (handRunStart === null) handRunStart = t;
        if (t - handRunStart >= SEG.startHandMs) {
          segState = "signing";
          segFrames = ring.filter((f) => f.t >= handRunStart - SEG.preRollMs);
          lastHandT = t;
          ring = [];
        }
      } else {
        handRunStart = null;
      }
    } else {
      segFrames.push(frame);
      if (hasHand) lastHandT = t;
      if (t - lastHandT >= SEG.endGapMs) {
        finishSegment();
      } else if (t - segFrames[0].t >= SEG.maxMs) {
        finishSegment();
      }
    }
  }

  // Returns JSON of the oldest finished segment, or "" if none.
  function popSegment() {
    if (segQueue.length === 0) return "";
    return JSON.stringify(segQueue.shift());
  }

  function getSegmentStatus() {
    return JSON.stringify({
      state: segState,
      queued: segQueue.length,
      msSinceHand: Math.round(lastFrameT - lastHandSeenT),
      discarded: discarded,
    });
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

        if (contActive) processFrame(nowMs, flat, count > 0);
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

  // ---- light meter (admin dataset capture) --------------------------
  // Average brightness (0-255) of the camera picture, using the same
  // formula as the SRDS: 0.299 R + 0.587 G + 0.114 B.
  let lightStream = null;
  let lightVideo = null;
  let lightTimer = null;
  let lightValue = -1;

  async function startLightMeter() {
    if (lightTimer) return true;
    lightStream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: "user" },
    });
    lightVideo = document.createElement("video");
    lightVideo.style.display = "none";
    lightVideo.autoplay = true;
    lightVideo.playsInline = true;
    lightVideo.muted = true;
    lightVideo.srcObject = lightStream;
    document.body.appendChild(lightVideo);
    await lightVideo.play();

    const canvas = document.createElement("canvas");
    canvas.width = 32;
    canvas.height = 24;
    const ctx = canvas.getContext("2d", { willReadFrequently: true });
    lightTimer = setInterval(() => {
      if (!lightVideo || lightVideo.readyState < 2) return;
      try {
        ctx.drawImage(lightVideo, 0, 0, 32, 24);
        const d = ctx.getImageData(0, 0, 32, 24).data;
        let sum = 0;
        for (let i = 0; i < d.length; i += 4) {
          sum += 0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2];
        }
        lightValue = sum / (d.length / 4);
      } catch (e) {
        /* ignore a bad frame */
      }
    }, 300);
    return true;
  }

  function stopLightMeter() {
    if (lightTimer) {
      clearInterval(lightTimer);
      lightTimer = null;
    }
    if (lightStream) {
      lightStream.getTracks().forEach((t) => t.stop());
      lightStream = null;
    }
    if (lightVideo) {
      lightVideo.remove();
      lightVideo = null;
    }
    lightValue = -1;
  }

  function getBrightness() {
    return lightValue;
  }

  return {
    init, startDetection, stopDetection, getLatestResult,
    startWindow, stopWindow,
    startContinuous, stopContinuous, popSegment, getSegmentStatus,
    startLightMeter, stopLightMeter, getBrightness,
    _resampleForTest: resample,
    _processFrameForTest: processFrame,
  };
})();
