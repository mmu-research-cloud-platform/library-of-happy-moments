const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

if (process.platform !== 'win32' || process.arch !== 'x64') {
  throw new Error('The bundled desktop build requires Windows x64.');
}

const root = path.resolve(__dirname, '..');
const stage = path.join(root, 'build', 'bundle');
const rscript = process.env.BUNDLE_RSCRIPT || 'Rscript.exe';
const listFile = path.join(os.tmpdir(), `happy-moments-packages-${process.pid}.txt`);

try {
  execFileSync(rscript, [path.join(__dirname, 'package-list.R'), listFile], {
    cwd: root, stdio: 'inherit'
  });
  const [rHome, ...packages] = fs.readFileSync(listFile, 'utf8').trim().split(/\r?\n/);
  if (!rHome || packages.length === 0) throw new Error('R package inventory is empty.');
  for (const binary of ['ffmpeg.exe', 'ffprobe.exe']) {
    if (!fs.existsSync(path.join(root, 'bin', 'windows-x64', binary))) {
      throw new Error(`Missing bundled ${binary}`);
    }
  }
  fs.rmSync(stage, { recursive: true, force: true });
  fs.mkdirSync(stage, { recursive: true });
  fs.cpSync(rHome, path.join(stage, 'runtime'), { recursive: true });
  fs.mkdirSync(path.join(stage, 'library'));
  for (const entry of packages) {
    const [name, source] = entry.split('\t');
    if (!name || !source || !fs.existsSync(source)) throw new Error(`Missing R package: ${entry}`);
    fs.cpSync(source, path.join(stage, 'library', name), { recursive: true });
  }
  const appDir = path.join(stage, 'app');
  fs.mkdirSync(appDir);
  fs.copyFileSync(path.join(root, 'app.R'), path.join(appDir, 'app.R'));
  fs.cpSync(path.join(root, 'R'), path.join(appDir, 'R'), { recursive: true });
  fs.mkdirSync(path.join(appDir, 'bin'));
  fs.cpSync(path.join(root, 'bin', 'windows-x64'), path.join(appDir, 'bin', 'windows-x64'), { recursive: true });
  fs.copyFileSync(path.join(root, 'LICENSE'), path.join(appDir, 'LICENSE'));
  console.log(`Staged R and ${packages.length} packages in ${stage}`);
} finally {
  fs.rmSync(listFile, { force: true });
}
