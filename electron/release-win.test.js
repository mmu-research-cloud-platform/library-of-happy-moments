const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const { release } = require('./release-win');

test('release refuses missing pin or review without producing a ZIP', (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'release-win-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const folder = path.join(dir, 'win-unpacked');
  const archive = path.join(dir, 'release.zip');
  fs.mkdirSync(folder);
  fs.writeFileSync(path.join(folder, 'MEDIA-PROVENANCE.json'), JSON.stringify({ assetDigest: `sha256:${'a'.repeat(64)}` }));
  assert.throws(() => release(folder, archive), /Pinned MEDIA_ASSET_SHA256/);
  assert.throws(() => release(folder, archive, `sha256:${'a'.repeat(64)}`), /RELEASE_REVIEW_FILE/);
  assert.throws(() => release(folder, archive, `sha256:${'b'.repeat(64)}`, 'review.json'), /Pinned MEDIA_ASSET_SHA256/);
  assert.equal(fs.existsSync(archive), false);
});
