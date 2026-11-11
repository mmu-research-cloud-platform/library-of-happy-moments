const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');

class Video extends EventTarget {
  constructor() {
    super();
    this.paused = true;
    this.currentTime = 0;
    this.duration = 2;
    this.readyState = 4;
    this.playbackRate = 1;
    this.muted = false;
  }
  play() {
    if (this.rejectPlayback) return Promise.reject(new Error('Not allowed'));
    if (this.paused) {
      this.paused = false;
      queueMicrotask(() => this.dispatchEvent(new Event('play')));
    }
    return Promise.resolve();
  }
  pause() {
    if (!this.paused) {
      this.paused = true;
      queueMicrotask(() => this.dispatchEvent(new Event('pause')));
    }
  }
}

function fixture(primary = 0) {
  const videos = [new Video(), new Video(), new Video()];
  const error = { textContent: '' };
  const styles = {};
  const grid = {
    dataset: { primary: String(primary), duration: '2' }, querySelectorAll: () => videos,
    style: { setProperty: (key, value) => { styles[key] = value; } },
    parentElement: { querySelector: () => error }
  };
  let currentGrid = grid;
  let mutation;
  let tick;
  let disposed = false;
  let ready;
  const messages = {};
  const context = {
    document: {
      addEventListener: (_, callback) => { ready = callback; },
      getElementById: () => ({ querySelector: () => currentGrid })
    },
    window: { addEventListener: () => {} },
    Shiny: { addCustomMessageHandler: (name, callback) => { messages[name] = callback; } },
    MutationObserver: class {
      constructor(callback) { mutation = callback; }
      observe() {}
      disconnect() {}
    },
    setInterval: callback => { tick = callback; return 1; },
    clearInterval: () => { disposed = true; }
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '..', 'www', 'multi-video.js'), 'utf8'), context);
  ready();
  mutation();
  return { videos, error, styles, messages, tick: () => tick(),
    remove: () => { currentGrid = null; mutation(); }, disposed: () => disposed };
}

const flush = () => new Promise(resolve => setImmediate(resolve));

test('the chosen audio video leads play, pause, seek and playback rate', async () => {
  const f = fixture(2);
  assert.deepEqual(f.videos.map(video => video.muted), [true, true, false]);
  f.messages['video-columns'](3);
  assert.equal(f.styles['--video-columns'], 3);
  await f.videos[2].play();
  await flush();
  assert.ok(f.videos.every(video => !video.paused));
  f.videos[2].currentTime = 1;
  f.videos[2].dispatchEvent(new Event('seeking'));
  assert.ok(f.videos.every(video => video.currentTime === 1));
  f.videos[2].playbackRate = 1.5;
  f.videos[2].dispatchEvent(new Event('ratechange'));
  assert.ok(f.videos.every(video => video.playbackRate === 1.5));
  f.videos[0].currentTime = 0.5;
  f.tick();
  assert.equal(f.videos[0].currentTime, 1);
  f.videos[2].pause();
  await flush();
  assert.ok(f.videos.every(video => video.paused));
  f.remove();
  assert.ok(f.disposed());
});

test('buffering pauses every view and resumes without losing play intent', async () => {
  const f = fixture();
  await f.videos[0].play();
  await flush();
  f.videos[1].readyState = 2;
  f.videos[1].dispatchEvent(new Event('waiting'));
  await flush();
  assert.ok(f.videos.every(video => video.paused));
  f.videos[1].readyState = 4;
  f.videos[1].dispatchEvent(new Event('canplay'));
  await flush();
  assert.ok(f.videos.every(video => !video.paused));
  f.videos[0].currentTime = 2;
  f.tick();
  await flush();
  assert.ok(f.videos.every(video => video.paused));
  f.remove();
});

test('browser playback and media errors are visible and stop every view', async () => {
  const f = fixture();
  f.videos[1].rejectPlayback = true;
  await f.videos[0].play();
  await flush();
  assert.match(f.error.textContent, /could not start/);
  assert.ok(f.videos.every(video => video.paused));
  f.remove();
  const second = fixture();
  second.videos[1].dispatchEvent(new Event('error'));
  assert.match(second.error.textContent, /could not be loaded/);
  second.remove();
});

test('paused seeking also clamps the leader to the shared clip duration', () => {
  const f = fixture(2);
  f.videos[2].duration = 2.5;
  f.videos[2].currentTime = 2.4;
  f.videos[2].dispatchEvent(new Event('seeking'));
  assert.ok(f.videos.every(video => video.currentTime === 2));
  f.remove();
});
