const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const { auditBundle, verifyReleaseEvidence } = require('./release-audit');

function release(folder, archive, digest, reviewFile) {
  const mediaDigest = JSON.parse(fs.readFileSync(path.join(folder, 'MEDIA-PROVENANCE.json'), 'utf8')).assetDigest;
  if (!/^sha256:[a-f0-9]{64}$/.test(digest || '') || digest !== mediaDigest) {
    throw new Error('Pinned MEDIA_ASSET_SHA256 does not match the staged media archive');
  }
  if (!reviewFile) throw new Error('RELEASE_REVIEW_FILE is required');
  auditBundle(folder);
  verifyReleaseEvidence(folder, path.resolve(reviewFile));
  // Windows tar creates ZIP output when the filename ends in .zip.
  execFileSync('tar.exe', ['-a', '-cf', archive, '-C', path.dirname(folder), path.basename(folder)], { stdio: 'inherit' });
  if (!fs.statSync(archive).size) throw new Error('The generated ZIP is empty.');
}

if (require.main === module) {
  if (process.platform !== 'win32' || process.arch !== 'x64') throw new Error('Release requires Windows x64');
  const root = path.resolve(__dirname, '..');
  const folder = path.join(root, 'dist', 'win-unpacked');
  const archive = path.join(root, 'dist', 'library-of-happy-moments-win-x64.zip');
  fs.rmSync(archive, { force: true });
  release(folder, archive, process.env.MEDIA_ASSET_SHA256, process.env.RELEASE_REVIEW_FILE);
  console.log(`Bundle ready: ${archive}`);
}

module.exports = { release };
