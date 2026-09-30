const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const { verifyArchive, validateManifest, noticeSection, writeReleaseNotice } = require('./media-release');

const names = ['ffmpeg.exe', 'ffprobe.exe', 'LICENSE.txt'];
const digest = (contents) => createHash('sha256').update(contents).digest('hex');

function fixture(dir) {
  const files = {};
  for (const name of names) {
    fs.writeFileSync(path.join(dir, name), name);
    files[name] = digest(name);
  }
  return {
    releaseUrl: 'https://github.com/BtbN/FFmpeg-Builds/releases/tag/latest',
    releasePublishedAt: '2026-09-29T00:00:00Z',
    assetUrl: 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/sample.zip',
    assetId: 123,
    assetDigest: `sha256:${'a'.repeat(64)}`,
    downloadedAt: '2026-09-29T00:00:00Z',
    files
  };
}

test('archive digest must match the release metadata', (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'media-test-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const archive = path.join(dir, 'archive.zip');
  fs.writeFileSync(archive, 'archive');
  assert.doesNotThrow(() => verifyArchive(archive, `sha256:${digest('archive')}`));
  assert.throws(() => verifyArchive(archive, `sha256:${'0'.repeat(64)}`), /digest mismatch/);
});

test('notice lists verified bundled file hashes without claiming source compliance', (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'media-test-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const manifest = fixture(dir);
  validateManifest(manifest, dir);
  const notice = noticeSection(manifest);
  for (const name of names) assert.ok(notice.includes(manifest.files[name]));
  assert.match(notice, /not that complete corresponding source is available/);
});

test('changed or missing files fail verification', (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'media-test-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const manifest = fixture(dir);
  fs.writeFileSync(path.join(dir, 'ffprobe.exe'), 'changed');
  assert.throws(() => validateManifest(manifest, dir), /ffprobe.exe/);
  fs.writeFileSync(path.join(dir, 'ffprobe.exe'), 'ffprobe.exe');
  fs.rmSync(path.join(dir, 'LICENSE.txt'));
  assert.throws(() => validateManifest(manifest, dir), /LICENSE.txt/);
});

test('release notice uses staged binaries and rejects a mismatch', (t) => {
  const folder = fs.mkdtempSync(path.join(os.tmpdir(), 'media-test-'));
  t.after(() => fs.rmSync(folder, { recursive: true, force: true }));
  const dir = path.join(folder, 'resources', 'bundle', 'app', 'bin', 'windows-x64');
  fs.mkdirSync(dir, { recursive: true });
  const manifest = fixture(dir);
  const manifestPath = path.join(folder, 'manifest.json');
  fs.writeFileSync(manifestPath, JSON.stringify(manifest));
  writeReleaseNotice(folder, manifestPath);
  assert.match(fs.readFileSync(path.join(folder, 'SOURCE-NOTICE.md'), 'utf8'), /do not redistribute this ZIP/);
  assert.equal(JSON.parse(fs.readFileSync(path.join(folder, 'MEDIA-PROVENANCE.json'))).files['ffmpeg.exe'], manifest.files['ffmpeg.exe']);
  fs.writeFileSync(path.join(dir, 'ffmpeg.exe'), 'changed');
  assert.throws(() => writeReleaseNotice(folder, manifestPath), /ffmpeg.exe/);
});
