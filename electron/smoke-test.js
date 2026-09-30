const assert = require('node:assert/strict');
const { spawn, execFileSync } = require('node:child_process');
const fs = require('node:fs');
const net = require('node:net');
const path = require('node:path');

const bundle = path.resolve(process.env.BUNDLE_DIR || path.join(__dirname, '..', 'dist', 'win-unpacked'), 'resources', 'bundle');
const appRoot = path.join(bundle, 'app');
const rscript = path.join(bundle, 'runtime', 'bin', 'Rscript.exe');
assert.ok(fs.existsSync(rscript), 'Bundled Rscript is missing');
assert.ok(fs.existsSync(path.join(bundle, 'library', 'facereaderconverter')));

const socket = net.createServer();
socket.listen(0, '127.0.0.1', async () => {
  const port = socket.address().port;
  socket.close(async () => {
    const env = {
      SystemRoot: process.env.SystemRoot,
      WINDIR: process.env.WINDIR,
      TEMP: process.env.TEMP,
      TMP: process.env.TMP,
      PATH: `${path.join(bundle, 'runtime', 'bin', 'x64')}${path.delimiter}${process.env.SystemRoot}\\System32`,
      R_HOME: path.join(bundle, 'runtime'),
      R_LIBS: path.join(bundle, 'library'),
      R_LIBS_USER: path.join(bundle, 'library'),
      R_LIBS_SITE: path.join(bundle, 'library'),
      R_ENVIRON_USER: 'NUL',
      R_PROFILE_USER: 'NUL',
      SHINY_PORT: String(port),
      STARTUP_TOKEN: 'bundle-smoke-test'
    };
    const child = spawn(rscript, [
      '-e', 'shiny::runApp(".", host="127.0.0.1", port=as.integer(Sys.getenv("SHINY_PORT")), launch.browser=FALSE)'
    ], { cwd: appRoot, env, windowsHide: true });
    let errors = '';
    child.stderr.on('data', (data) => { errors += data.toString(); });
    try {
      let ready = false;
      for (let attempt = 0; attempt < 100; attempt++) {
        if (child.exitCode !== null) break;
        try {
          const response = await fetch(`http://127.0.0.1:${port}/?startup=bundle-smoke-test`);
          if (response.ok && (await response.text()).includes('startup-bundle-smoke-test')) {
            ready = true;
            break;
          }
        } catch (_) { /* Wait for startup. */ }
        await new Promise((resolve) => setTimeout(resolve, 200));
      }
      assert.ok(ready, `Bundled Shiny did not start: ${errors}`);
      console.log('Bundled R and Shiny startup smoke test passed.');
    } finally {
      if (child.exitCode === null) {
        // Rscript on Windows can leave its R child running after the wrapper exits.
        execFileSync('taskkill.exe', ['/PID', String(child.pid), '/T', '/F'], { stdio: 'ignore' });
      }
    }
  });
});
