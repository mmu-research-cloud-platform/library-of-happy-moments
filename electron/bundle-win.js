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
run(process.execPath, [path.join(__dirname, 'stage.js')]);
run(process.execPath, [require.resolve('electron-builder/cli.js'), '--win', 'dir']);
run(process.execPath, [path.join(__dirname, 'smoke-test.js')]);

for (const name of ['Library of Happy Moments.exe', 'resources/bundle/runtime/bin/Rscript.exe',
  'resources/bundle/app/bin/windows-x64/LICENSE.txt']) {
  if (!fs.existsSync(path.join(folder, name))) throw new Error(`Incomplete build: ${name}`);
}
for (const [source, target] of [
  ['RUN-BUNDLE.md', 'RUN-BUNDLE.md'],
  ['SOURCE-NOTICE.md', 'SOURCE-NOTICE.md']
]) {
  fs.copyFileSync(path.join(__dirname, source), path.join(folder, target));
}

// Windows tar uses ZIP when the output name ends in .zip.
run('tar.exe', ['-a', '-cf', archive, '-C', dist, 'win-unpacked']);
if (!fs.statSync(archive).size) throw new Error('The generated ZIP is empty.');
console.log(`Bundle ready: ${archive}`);
