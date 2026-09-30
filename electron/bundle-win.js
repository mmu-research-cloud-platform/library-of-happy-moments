const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

if (process.platform !== 'win32' || process.arch !== 'x64') {
  throw new Error('Run this bundler on Windows x64.');
}

const root = path.resolve(__dirname, '..');
const dist = path.join(root, 'dist');
const folder = path.join(dist, 'win-unpacked');
const archive = path.join(dist, 'library-of-happy-moments-win-x64.zip');

function run(program, args) {
  execFileSync(program, args, { cwd: root, stdio: 'inherit' });
}

// The R installation and packages are local inputs; record their versions for repeatable builds.
fs.rmSync(archive, { force: true });
run(process.execPath, [path.join(__dirname, 'media-release.js'), 'download']);
run(process.execPath, [path.join(__dirname, 'stage.js')]);
run(process.execPath, [require.resolve('electron-builder/cli.js'), '--win', 'dir']);
run(process.execPath, [path.join(__dirname, 'smoke-test.js')]);

for (const name of ['Library of Happy Moments.exe', 'resources/bundle/runtime/bin/Rscript.exe',
  'resources/bundle/app/bin/windows-x64/LICENSE.txt']) {
  if (!fs.existsSync(path.join(folder, name))) throw new Error(`Incomplete build: ${name}`);
}
fs.copyFileSync(path.join(__dirname, 'RUN-BUNDLE.md'), path.join(folder, 'RUN-BUNDLE.md'));
run(process.execPath, [path.join(__dirname, 'media-release.js'), 'notice', folder]);
run(process.execPath, [path.join(__dirname, 'release-audit.js'), 'audit', folder]);

if (process.env.RELEASE_REVIEW_FILE && process.env.MEDIA_ASSET_SHA256) {
  run(process.execPath, [path.join(__dirname, 'release-win.js')]);
} else {
  console.log('Development folder ready. ZIP withheld: run npm run release:win after review.');
}
