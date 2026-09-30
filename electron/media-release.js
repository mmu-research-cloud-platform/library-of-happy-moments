const { createHash } = require('node:crypto');
const { spawn, execFileSync } = require('node:child_process');
const fs = require('node:fs');
const https = require('node:https');
const os = require('node:os');
const path = require('node:path');
const { pipeline } = require('node:stream/promises');

const root = path.resolve(__dirname, '..');
const assetName = 'ffmpeg-n9.0-latest-win64-gpl-9.0.zip';
const releaseApi = 'https://api.github.com/repos/BtbN/FFmpeg-Builds/releases/tags/latest';
const files = ['ffmpeg.exe', 'ffprobe.exe', 'LICENSE.txt'];
const manifestFile = path.join(root, 'bin', '.downloads', 'windows-release.json');
const toolsDir = path.join(root, 'bin', 'windows-x64');

function sha256(file) {
  return createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function verifyArchive(archive, expectedDigest) {
  if (!/^sha256:[a-f0-9]{64}$/.test(expectedDigest || '') ||
      expectedDigest !== `sha256:${sha256(archive)}`) {
    throw new Error('Upstream archive digest mismatch; no binaries installed');
  }
}

function get(url, redirects = 5) {
  return new Promise((resolve, reject) => {
    if (!url.startsWith('https://')) return reject(new Error('Only HTTPS downloads are supported'));
    https.get(url, { headers: { 'User-Agent': 'library-of-happy-moments-release' } }, (response) => {
      if ([301, 302, 303, 307, 308].includes(response.statusCode)) {
        const next = response.headers.location;
        response.resume();
        if (!next || redirects === 0) return reject(new Error('Too many download redirects'));
        const redirect = new URL(next, url);
        if (redirect.protocol !== 'https:') return reject(new Error('Insecure download redirect'));
        return resolve(get(redirect.href, redirects - 1));
      }
      if (response.statusCode !== 200) {
        response.resume();
        return reject(new Error(`Download returned HTTP ${response.statusCode}: ${url}`));
      }
      resolve(response);
    }).on('error', reject);
  });
}

async function fetchRelease() {
  const response = await get(releaseApi);
  const chunks = [];
  for await (const chunk of response) chunks.push(chunk);
  const release = JSON.parse(Buffer.concat(chunks).toString('utf8'));
  const asset = release.assets?.find((entry) => entry.name === assetName);
  if (!asset || !/^sha256:[a-f0-9]{64}$/.test(asset.digest || '')) {
    throw new Error(`Missing ${assetName} or its SHA-256 digest in the upstream release`);
  }
  return { release, asset };
}

function extractMember(archive, member, destination) {
  return new Promise((resolve, reject) => {
    const child = spawn('tar.exe', ['-xOf', archive, member], { windowsHide: true });
    const output = fs.createWriteStream(destination);
    let error = '';
    child.stderr.on('data', (chunk) => { error += chunk.toString(); });
    const copied = pipeline(child.stdout, output);
    child.on('error', reject);
    child.on('close', (code) => {
      if (code !== 0) return reject(new Error(`Archive extraction failed: ${error}`));
      copied.then(resolve, reject);
    });
  });
}

function validateManifest(manifest, dir = toolsDir) {
  if (!manifest || !/^sha256:[a-f0-9]{64}$/.test(manifest.assetDigest || '') ||
      !/^https:\/\/github\.com\/BtbN\/FFmpeg-Builds\/releases\/download\//.test(manifest.assetUrl || '') ||
      !Number.isSafeInteger(manifest.assetId) || manifest.assetId <= 0) {
    throw new Error('Missing verified upstream asset identity');
  }
  for (const name of files) {
    const expected = manifest.files?.[name];
    if (!/^[a-f0-9]{64}$/.test(expected || '') || !fs.existsSync(path.join(dir, name)) ||
        sha256(path.join(dir, name)) !== expected) {
      throw new Error(`Missing or changed Windows media tool: ${name}`);
    }
  }
}

async function downloadWindowsTools() {
  if (process.platform !== 'win32') throw new Error('Download Windows media tools on Windows.');
  const { release, asset } = await fetchRelease();
  if (process.env.MEDIA_ASSET_SHA256 && asset.digest !== process.env.MEDIA_ASSET_SHA256) {
    throw new Error('Selected upstream media asset differs from pinned MEDIA_ASSET_SHA256');
  }
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'happy-moments-media-'));
  try {
    const archive = path.join(temporary, assetName);
    await pipeline(await get(asset.browser_download_url), fs.createWriteStream(archive));
    verifyArchive(archive, asset.digest);
    const prefix = `${assetName.slice(0, -4)}/`;
    const listing = execFileSync('tar.exe', ['-tf', archive], { encoding: 'utf8' }).split(/\r?\n/);
    for (const name of files) {
      const member = `${prefix}${name === 'LICENSE.txt' ? name : `bin/${name}`}`;
      if (!listing.includes(member)) throw new Error(`Archive lacks ${member}`);
      await extractMember(archive, member, path.join(temporary, name));
    }
    const version = execFileSync(path.join(temporary, 'ffmpeg.exe'), ['-version'], { encoding: 'utf8', windowsHide: true });
    if (!version.includes('--enable-gpl') || !version.includes('--enable-libx264')) {
      throw new Error('Downloaded FFmpeg lacks the required GPL/libx264 build options');
    }
    const manifest = {
      ffmpegVersion: version.split(/\r?\n/)[0],
      ffmpegConfiguration: version.split(/\r?\n/).find((line) => line.startsWith('configuration:')),
      releaseUrl: release.html_url,
      releasePublishedAt: release.published_at,
      assetUrl: asset.browser_download_url,
      assetId: asset.id,
      assetDigest: asset.digest,
      downloadedAt: new Date().toISOString(),
      files: Object.fromEntries(files.map((name) => [name, sha256(path.join(temporary, name))]))
    };
    validateManifest(manifest, temporary);
    fs.mkdirSync(toolsDir, { recursive: true });
    for (const name of files) fs.copyFileSync(path.join(temporary, name), path.join(toolsDir, name));
    fs.mkdirSync(path.dirname(manifestFile), { recursive: true });
    fs.writeFileSync(manifestFile, `${JSON.stringify(manifest, null, 2)}\n`);
    console.log(`Verified Windows media tools: ${asset.digest}`);
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true });
  }
}

function noticeSection(manifest) {
  return [
    '## Media binaries in this particular build',
    '',
    `Upstream release: ${manifest.releaseUrl}`,
    `Published: ${manifest.releasePublishedAt}`,
    `Binary archive: ${manifest.assetUrl} (GitHub asset ID ${manifest.assetId})`,
    `Archive SHA-256 (verified against release metadata): ${manifest.assetDigest.slice(7)}`,
    `Downloaded: ${manifest.downloadedAt}`,
    ...(manifest.ffmpegVersion ? [`Reported version: ${manifest.ffmpegVersion}`] : []),
    '',
    '| Shipped file | SHA-256 |',
    '|---|---|',
    ...files.map((name) => `| \`resources/bundle/app/bin/windows-x64/${name}\` | \`${manifest.files[name]}\` |`),
    '',
    'These hashes establish which binary files were packaged, not that complete corresponding source is available. The release tag `latest` moves; preserve exact source/build inputs separately before redistribution.',
    ''
  ].join('\n');
}

function writeReleaseNotice(folder, sourceManifest = manifestFile) {
  const manifest = JSON.parse(fs.readFileSync(sourceManifest, 'utf8'));
  if (!Number.isFinite(Date.parse(manifest.releasePublishedAt)) ||
      !Number.isFinite(Date.parse(manifest.downloadedAt)) ||
      !/^https:\/\/github\.com\/BtbN\/FFmpeg-Builds\/releases\/tag\//.test(manifest.releaseUrl || '')) {
    throw new Error('Incomplete media release provenance');
  }
  validateManifest(manifest, path.join(folder, 'resources', 'bundle', 'app', 'bin', 'windows-x64'));
  const template = fs.readFileSync(path.join(__dirname, 'SOURCE-NOTICE.md'), 'utf8');
  fs.writeFileSync(path.join(folder, 'SOURCE-NOTICE.md'), `${template.trimEnd()}\n\n${noticeSection(manifest)}`);
  fs.writeFileSync(path.join(folder, 'MEDIA-PROVENANCE.json'), `${JSON.stringify(manifest, null, 2)}\n`);
}

if (require.main === module) {
  const action = process.argv[2];
  const operation = action === 'download' ? downloadWindowsTools() :
    action === 'notice' ? Promise.resolve().then(() => writeReleaseNotice(process.argv[3])) :
      Promise.reject(new Error('Usage: node electron/media-release.js download|notice <bundle-folder>'));
  operation.catch((error) => { console.error(error); process.exitCode = 1; });
}

module.exports = { verifyArchive, validateManifest, noticeSection, writeReleaseNotice };
