const { createHash } = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

function sha256(file) {
  return createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function nativeFiles(directory, folder = directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) return nativeFiles(file, folder);
    return entry.isFile() && /\.(exe|dll|node)$/i.test(entry.name)
      ? [path.relative(folder, file).replaceAll(path.sep, '/')]
      : [];
  });
}

function packageRecord(directory, name, category) {
  const description = path.join(directory, 'DESCRIPTION');
  if (!fs.existsSync(description)) throw new Error(`Missing R package DESCRIPTION: ${name}`);
  const text = fs.readFileSync(description, 'utf8');
  const field = (key) => text.match(new RegExp(`^${key}:\\s*(.*)$`, 'm'))?.[1]?.trim();
  const version = field('Version');
  const license = field('License');
  if (!version || !license) throw new Error(`Missing version or license for R package: ${name}`);
  const notices = fs.readdirSync(directory).filter((file) => /^(LICENSE|LICENCE|COPYING|NOTICE)(\.|$)/i.test(file));
  if (/\bfile\s+LICEN[SC]E\b/i.test(license) && !notices.some((file) => /^LICEN[SC]E(\.|$)/i.test(file))) {
    throw new Error(`Missing license file for R package: ${name}`);
  }
  return { name, version, license, notices: notices.map((file) => `resources/bundle/${category}/${name}/${file}`) };
}

function auditBundle(folder) {
  const bundle = path.join(folder, 'resources', 'bundle');
  const runtime = path.join(bundle, 'runtime');
  const library = path.join(bundle, 'library');
  if (!fs.existsSync(path.join(runtime, 'COPYING'))) {
    throw new Error('Missing R runtime license');
  }
  const packageDirs = [
    [path.join(runtime, 'library'), 'runtime/library'],
    [library, 'library']
  ];
  const packages = packageDirs.flatMap(([dir, category]) => {
    if (!fs.existsSync(dir)) throw new Error(`Missing R package directory: ${category}`);
    return fs.readdirSync(dir, { withFileTypes: true })
      .filter((entry) => entry.isDirectory())
      .map((entry) => packageRecord(path.join(dir, entry.name), entry.name, category));
  });
  if (!packages.some((item) => item.name === 'facereaderconverter')) {
    throw new Error('Bundled facereaderconverter is missing');
  }
  const electronLicenses = ['LICENSE.electron.txt', 'LICENSES.chromium.html'];
  for (const name of electronLicenses) {
    if (!fs.existsSync(path.join(folder, name))) throw new Error(`Missing ${name}`);
  }
  for (const name of ['SOURCE-NOTICE.md', 'RUN-BUNDLE.md']) {
    if (!fs.existsSync(path.join(folder, name))) throw new Error(`Missing ${name}`);
  }
  const media = JSON.parse(fs.readFileSync(path.join(folder, 'MEDIA-PROVENANCE.json'), 'utf8'));
  const mediaDir = path.join(bundle, 'app', 'bin', 'windows-x64');
  for (const [name, digest] of Object.entries(media.files)) {
    if (!/^[a-f0-9]{64}$/.test(digest) || sha256(path.join(mediaDir, name)) !== digest) {
      throw new Error(`Media hash mismatch: ${name}`);
    }
  }
  const inventory = {
    appLicense: 'resources/bundle/app/LICENSE',
    appLicenseSha256: sha256(path.join(bundle, 'app', 'LICENSE')),
    runtimeLicense: 'resources/bundle/runtime/COPYING',
    runtimeLicenseSha256: sha256(path.join(runtime, 'COPYING')),
    rVersion: packages.find((item) => item.name === 'base')?.version,
    electronLicenses,
    electronVersion: require('electron/package.json').version,
    electronLicenseHashes: Object.fromEntries(electronLicenses.map((name) => [name, sha256(path.join(folder, name))])),
    bundleNoticeHashes: Object.fromEntries(['SOURCE-NOTICE.md', 'RUN-BUNDLE.md']
      .map((name) => [name, sha256(path.join(folder, name))])),
    media,
    packages,
    packageDescriptionHashes: Object.fromEntries(packageDirs.flatMap(([dir, category]) =>
      fs.readdirSync(dir, { withFileTypes: true }).filter((entry) => entry.isDirectory())
        .map((entry) => [`${category}/${entry.name}`, sha256(path.join(dir, entry.name, 'DESCRIPTION'))]))),
    nativeFileHashes: Object.fromEntries(nativeFiles(folder).sort()
      .map((name) => [name, sha256(path.join(folder, name))])),
    appSourceHashes: Object.fromEntries(['app.R', 'instructions.qmd', ...fs.readdirSync(path.join(bundle, 'app', 'R')).map((name) => `R/${name}`)]
      .map((name) => [name, sha256(path.join(bundle, 'app', name))]))
  };
  if (!inventory.rVersion) throw new Error('Missing R base version');
  fs.writeFileSync(path.join(folder, 'COMPONENT-INVENTORY.json'), `${JSON.stringify(inventory, null, 2)}\n`);
  return inventory;
}

function verifyReleaseEvidence(folder, evidenceFile) {
  const inventory = JSON.parse(fs.readFileSync(path.join(folder, 'COMPONENT-INVENTORY.json'), 'utf8'));
  const evidence = JSON.parse(fs.readFileSync(evidenceFile, 'utf8'));
  const required = ['mediaCorrespondingSource', 'rAndPackageSources', 'electronChromiumSources',
    'licenseNoticeReview', 'codecPatentReview'];
  for (const key of required) {
    if (typeof evidence[key] !== 'string' || !evidence[key].trim()) {
      throw new Error(`Missing release review evidence: ${key}`);
    }
  }
  if (evidence.inventorySha256 !== sha256(path.join(folder, 'COMPONENT-INVENTORY.json')) ||
      evidence.mediaAssetDigest !== inventory.media.assetDigest ||
      evidence.mediaFileHashes?.['ffmpeg.exe'] !== inventory.media.files['ffmpeg.exe'] ||
      evidence.mediaFileHashes?.['ffprobe.exe'] !== inventory.media.files['ffprobe.exe']) {
    throw new Error('Release evidence does not match the packaged media binaries');
  }
  // Evidence is a review record, not an automatic determination of license or patent compliance.
  if (path.resolve(evidenceFile) === path.resolve(folder, 'RELEASE-REVIEW.json')) {
    throw new Error('Supply the review record outside the output folder');
  }
  fs.copyFileSync(evidenceFile, path.join(folder, 'RELEASE-REVIEW.json'));
}

if (require.main === module) {
  const [action, folder, evidence] = process.argv.slice(2);
  if (action === 'audit') auditBundle(folder);
  else if (action === 'verify' && evidence) verifyReleaseEvidence(folder, evidence);
  else throw new Error('Usage: node electron/release-audit.js audit <folder> | verify <folder> <review.json>');
}

module.exports = { auditBundle, packageRecord, verifyReleaseEvidence };
