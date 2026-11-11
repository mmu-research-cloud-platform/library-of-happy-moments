const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const { validateManifest, writeReleaseNotice } = require('./media-release');
const { auditBundle } = require('./release-audit');

test('verified media provenance accepts the successor publisher but rejects other repositories', (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'media-migration-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const directory = path.join(root, 'resources', 'bundle', 'app', 'bin', 'windows-x64');
  fs.mkdirSync(directory, { recursive: true });
  const files = {};
  for (const name of ['ffmpeg.exe', 'ffprobe.exe', 'LICENSE.txt']) {
    fs.writeFileSync(path.join(directory, name), name);
    files[name] = createHash('sha256').update(name).digest('hex');
  }
  const manifest = {
    assetDigest: `sha256:${'a'.repeat(64)}`, assetId: 123,
    assetUrl: 'https://github.com/FFmpeg-Builds/FFmpeg-Builds/releases/download/latest/sample.zip',
    releaseUrl: 'https://github.com/FFmpeg-Builds/FFmpeg-Builds/releases/tag/latest',
    releasePublishedAt: '2026-11-11T00:00:00Z', downloadedAt: '2026-11-11T00:00:00Z', files
  };
  validateManifest(manifest, directory);
  const file = path.join(root, 'manifest.json');
  fs.writeFileSync(file, JSON.stringify(manifest));
  writeReleaseNotice(root, file);
  assert.throws(() => validateManifest({
    ...manifest, assetUrl: 'https://github.com/untrusted/FFmpeg-Builds/releases/download/latest/sample.zip'
  }, directory), /asset identity/);
  manifest.releaseUrl = 'https://github.com/untrusted/FFmpeg-Builds/releases/tag/latest';
  fs.writeFileSync(file, JSON.stringify(manifest));
  assert.throws(() => writeReleaseNotice(root, file), /provenance/);
});

test('the release inventory covers the shipped browser synchronization code', (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'client-audit-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  function write(name, content) {
    const file = path.join(root, name);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, content);
  }
  write('resources/bundle/runtime/COPYING', 'R license');
  write('resources/bundle/runtime/library/base/DESCRIPTION', 'Version: 4.6.1\nLicense: GPL-2\n');
  write('resources/bundle/library/facereaderconverter/DESCRIPTION', 'Version: 0.4\nLicense: MIT\n');
  write('resources/bundle/app/LICENSE', 'MIT');
  write('resources/bundle/app/app.R', 'shinyApp(ui, server)');
  write('resources/bundle/app/R/helpers.R', 'helper <- function() TRUE');
  write('resources/bundle/app/www/multi-video.js', 'version one');
  write('LICENSE.electron.txt', 'Electron license');
  write('LICENSES.chromium.html', 'Chromium license');
  write('SOURCE-NOTICE.md', 'Source notice');
  write('RUN-BUNDLE.md', 'Run instructions');
  write('MEDIA-PROVENANCE.json', JSON.stringify({ files: {} }));
  const first = auditBundle(root).appSourceHashes['www/multi-video.js'];
  assert.equal(typeof first, 'string');
  write('resources/bundle/app/www/multi-video.js', 'version two');
  const second = auditBundle(root).appSourceHashes['www/multi-video.js'];
  assert.notEqual(first, second);
});
