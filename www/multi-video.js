(function () {
  'use strict';
  let columns = 2;
  let cleanup = () => {};

  function attach(grid) {
    const videos = Array.from(grid.querySelectorAll('video'));
    const leader = videos[Number(grid.dataset.primary)];
    if (!leader) return () => {};
    grid.style.setProperty('--video-columns', columns);
    const listeners = [];
    let intendedPlaying = false;
    let syncing = false;
    let failed = false;
    let disposed = false;
    let expectedPause = false;
    const error = grid.parentElement.querySelector('.playback-error');
    function listen(video, event, handler) {
      video.addEventListener(event, handler);
      listeners.push(() => video.removeEventListener(event, handler));
    }
    function pauseAll() {
      syncing = true;
      if (!leader.paused) expectedPause = true;
      videos.forEach(video => video.pause());
      syncing = false;
    }
    function fail(message) {
      if (disposed) return;
      failed = true;
      intendedPlaying = false;
      pauseAll();
      if (error) error.textContent = message;
    }
    function duration() {
      const limit = Number(grid.dataset.duration);
      return Math.min(Number.isFinite(limit) && limit > 0 ? limit : Infinity,
        ...videos.map(video => Number.isFinite(video.duration) ? video.duration : Infinity));
    }
    function seekAll() {
      const time = Math.min(leader.currentTime, duration());
      if (leader.currentTime > time) leader.currentTime = time;
      videos.forEach(video => {
        if (video !== leader && Math.abs(video.currentTime - time) > 0.02) video.currentTime = time;
      });
    }
    function playAll() {
      if (failed || disposed || !intendedPlaying) return;
      if (videos.some(video => video.readyState < 3)) {
        pauseAll();
        return;
      }
      syncing = true;
      videos.forEach(video => {
        video.playbackRate = leader.playbackRate;
        video.muted = video !== leader;
        const playing = video.play();
        if (playing) playing.catch(() => fail('Synchronized playback could not start. Check browser media permissions and reload the clip.'));
      });
      syncing = false;
    }
    listen(leader, 'play', () => {
      if (syncing) return;
      intendedPlaying = true;
      seekAll();
      playAll();
    });
    listen(leader, 'pause', () => {
      if (expectedPause) { expectedPause = false; return; }
      if (syncing) return;
      intendedPlaying = false;
      pauseAll();
    });
    listen(leader, 'seeking', seekAll);
    listen(leader, 'ratechange', () => videos.forEach(video => {
      if (video !== leader) video.playbackRate = leader.playbackRate;
    }));
    videos.forEach(video => {
      video.muted = video !== leader;
      listen(video, 'error', () => fail('A camera clip could not be loaded. Regenerate the clips or check the media file.'));
      listen(video, 'waiting', () => { if (intendedPlaying) pauseAll(); });
      listen(video, 'canplay', playAll);
      listen(video, 'ended', () => {
        intendedPlaying = false;
        pauseAll();
      });
    });
    const timer = setInterval(() => {
      if (disposed || failed || leader.paused) return;
      if (leader.currentTime >= duration()) {
        intendedPlaying = false;
        pauseAll();
      } else {
        seekAll();
      }
    }, 100);
    return () => {
      disposed = true;
      clearInterval(timer);
      listeners.forEach(remove => remove());
      pauseAll();
    };
  }

  document.addEventListener('DOMContentLoaded', () => {
    const player = document.getElementById('player');
    if (!player) return;
    let active = null;
    const observer = new MutationObserver(() => {
      const grid = player.querySelector('.video-grid');
      if (grid === active) return;
      cleanup();
      active = grid;
      cleanup = grid ? attach(grid) : () => {};
    });
    observer.observe(player, { childList: true, subtree: true });
    window.addEventListener('pagehide', () => { cleanup(); observer.disconnect(); });
    Shiny.addCustomMessageHandler('video-columns', value => {
      columns = value;
      if (active) active.style.setProperty('--video-columns', columns);
    });
  });
}());
