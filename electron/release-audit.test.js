const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const { auditBundle, packageRecord, verifyReleaseEvidence } = require('./release-audit');

test('inventory captures R package version, license and included notice', (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'release-audit-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  fs.writeFileSync(path.join(dir, 'DESCRIPTION'), 'Package: sample\nVersion: 1.2.3\nLicense: MIT + file LICENSE\n');
  assert.throws(() => packageRecord(dir, 'sample', 'library'), /Missing license file/);
  fs.writeFileSync(path.join(dir, 'LICENSE'), 'copyright');
  assert.deepEqual(packageRecord(dir, 'sample', 'library'), {
    name: 'sample', version: '1.2.3', license: 'MIT + file LICENSE',
    notices: ['resources/bundle/library/sample/LICENSE']
  });
});

test('release review must match the exact inventory and media', (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'release-audit-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const inventoryPath = path.join(dir, 'COMPONENT-INVENTORY.json');
  const inventory = { media: { assetDigest: `sha256:${'a'.repeat(64)}`, files: {
    'ffmpeg.exe': 'b'.repeat(64), 'ffprobe.exe': 'c'.repeat(64)
  } } };
  fs.writeFileSync(inventoryPath, JSON.stringify(inventory));
  const evidence = {
    inventorySha256: createHash('sha256').update(fs.readFileSync(inventoryPath)).digest('hex'),
    mediaAssetDigest: inventory.media.assetDigest,
    mediaFileHashes: inventory.media.files,
    mediaCorrespondingSource: 'release-specific source archive and build instructions',
    rAndPackageSources: 'package source archive inventory',
    electronChromiumSources: 'electron source and notices archive',
    licenseNoticeReview: 'approved by release owner',
    codecPatentReview: 'approved for intended territories by counsel'
  };
  const evidencePath = path.join(dir, 'review.json');
  fs.writeFileSync(evidencePath, JSON.stringify(evidence));
  verifyReleaseEvidence(dir, evidencePath);
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(dir, 'RELEASE-REVIEW.json'))), evidence);
  evidence.inventorySha256 = '0'.repeat(64);
  fs.writeFileSync(evidencePath, JSON.stringify(evidence));
  assert.throws(() => verifyReleaseEvidence(dir, evidencePath), /does not match/);
  evidence.inventorySha256 = createHash('sha256').update(fs.readFileSync(inventoryPath)).digest('hex');
  evidence.codecPatentReview = '';
  fs.writeFileSync(evidencePath, JSON.stringify(evidence));
  assert.throws(() => verifyReleaseEvidence(dir, evidencePath), /codecPatentReview/);
});

test('release review rejects an absent or incomplete record', (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'release-audit-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  fs.writeFileSync(path.join(dir, 'COMPONENT-INVENTORY.json'), JSON.stringify({ media: { files: {} } }));
  assert.throws(() => verifyReleaseEvidence(dir, path.join(dir, 'missing.json')), /ENOENT/);
  const record = path.join(dir, 'record.json');
  fs.writeFileSync(record, '{}');
  assert.throws(() => verifyReleaseEvidence(dir, record), /mediaCorrespondingSource/);
});

test('audit inventories staged components and rejects changed media', (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'release-audit-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const bundle = path.join(dir, 'resources', 'bundle');
  const write = (name, value) => {
    const destination = path.join(dir, name);
    fs.mkdirSync(path.dirname(destination), { recursive: true });
    fs.writeFileSync(destination, value);
  };
  write('resources/bundle/runtime/COPYING', 'GPL');
  write('resources/bundle/runtime/library/base/DESCRIPTION', 'Version: 4.6.1\nLicense: Part of R\n');
  write('resources/bundle/library/facereaderconverter/DESCRIPTION', 'Version: 0.3.2.2\nLicense: MIT\n');
  write('resources/bundle/app/LICENSE', 'MIT');
  write('resources/bundle/app/app.R', 'source');
  write('resources/bundle/app/R/helper.R', 'helper');
  write('LICENSE.electron.txt', 'electron');
  write('LICENSES.chromium.html', 'chromium');
  write('SOURCE-NOTICE.md', 'notice');
  write('RUN-BUNDLE.md', 'instructions');
  const mediaPath = path.join(bundle, 'app', 'bin', 'windows-x64', 'ffmpeg.exe');
  write('resources/bundle/app/bin/windows-x64/ffmpeg.exe', 'media');
  write('MEDIA-PROVENANCE.json', JSON.stringify({ files: {
    'ffmpeg.exe': createHash('sha256').update('media').digest('hex')
  } }));
  const inventory = auditBundle(dir);
  assert.equal(inventory.rVersion, '4.6.1');
  assert.equal(inventory.packages.length, 2);
  assert.deepEqual(auditBundle(dir), inventory);
  fs.writeFileSync(mediaPath, 'tampered');
  assert.throws(() => auditBundle(dir), /Media hash mismatch/);
});
