'use strict';
// Fullscreen is a device capability, not a consequence of a narrow window.
(() => {
  const isMobile = () => navigator.userAgentData?.mobile === true ||
    /Android|iPhone|iPad|iPod/i.test(navigator.userAgent || '') ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const fullscreenElement = () => document.fullscreenElement || document.webkitFullscreenElement;
  let suspended = false;
  const videoFullscreen = () => {
    const element = fullscreenElement();
    return isMobile() && !suspended && !document.hidden && Boolean(element?.matches?.('.video-stage') || element?.closest?.('.video-stage'));
  };
  let pending = false, owned = false, generation = 0, attemptedGeneration = -1;
  function release() {
    generation++;
    if (owned || pending) {
      try { screen.orientation?.unlock?.(); } catch { /* Browser already released it. */ }
    }
    owned = false;
  }
  async function syncOrientation() {
    if (!videoFullscreen()) { release(); return; }
    if (pending || owned || attemptedGeneration === generation || typeof screen.orientation?.lock !== 'function') return;
    const attempt = generation;
    attemptedGeneration = attempt;
    pending = true;
    try {
      await screen.orientation.lock('landscape');
      owned = true;
    } catch { /* Native fullscreen remains usable when orientation lock is unsupported. */ }
    finally {
      pending = false;
      if (attempt !== generation || !videoFullscreen()) {
        release();
        // A new fullscreen session may have started while the old request settled.
        if (videoFullscreen()) syncOrientation();
      }
    }
  }
  async function enterFullscreen(stage) {
    if (!isMobile() || !stage) return false;
    if (fullscreenElement()) {
      const exit = document.exitFullscreen || document.webkitExitFullscreen;
      if (exit) { await exit.call(document); return true; }
    }
    const request = stage.requestFullscreen || stage.webkitRequestFullscreen;
    if (!request) return false;
    try {
      await request.call(stage);
      await syncOrientation();
      return true;
    } catch { return false; }
  }
  document.addEventListener('fullscreenchange', syncOrientation);
  document.addEventListener('webkitfullscreenchange', syncOrientation);
  document.addEventListener('visibilitychange', syncOrientation);
  window.addEventListener('pagehide', () => { suspended = true; release(); });
  window.addEventListener('pageshow', () => { suspended = false; syncOrientation(); });
  globalThis.SeasonMobilePlayback = { isMobile, enterFullscreen };
})();
