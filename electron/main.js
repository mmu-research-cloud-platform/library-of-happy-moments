const { app, BrowserWindow, dialog } = require('electron');
const { spawn, execFileSync } = require('node:child_process');
const net = require('node:net');
const path = require('node:path');
const { randomBytes } = require('node:crypto');

const root = path.resolve(__dirname, '..');
const bundled = app.isPackaged;
const resources = bundled ? path.join(process.resourcesPath, 'bundle') : root;
const appRoot = bundled ? path.join(resources, 'app') : root;
let server;
let window;

function availablePort() {
  return new Promise((resolve, reject) => {
    const socket = net.createServer();
    socket.once('error', reject);
    socket.listen(0, '127.0.0.1', () => {
      const port = socket.address().port;
      socket.close(() => resolve(port));
    });
  });
}

async function waitForServer(url, child, startupToken) {
  let spawnError;
  child.once('error', (error) => { spawnError = error; });
  for (let attempt = 0; attempt < 100; attempt++) {
    if (spawnError) throw spawnError;
    if (child.exitCode !== null) throw new Error('The R process exited before Shiny started.');
    try {
      const response = await fetch(url);
      if (response.ok && (await response.text()).includes(`startup-${startupToken}`)) return;
    } catch (_) {
      // Shiny has not bound the loopback port yet.
    }
    await new Promise((resolve) => setTimeout(resolve, 200));
  }
  throw new Error('Timed out waiting for the Shiny app to start.');
}

app.whenReady().then(async () => {
  try {
    const port = await availablePort();
    const startupToken = randomBytes(24).toString('hex');
    const baseUrl = `http://127.0.0.1:${port}`;
    const readinessUrl = `${baseUrl}/?startup=${startupToken}`;
    const rscript = bundled
      ? path.join(resources, 'runtime', 'bin', 'Rscript.exe')
      : (process.env.RSCRIPT || 'Rscript');
    const env = { ...process.env, SHINY_PORT: String(port), STARTUP_TOKEN: startupToken };
    if (bundled) {
      env.R_HOME = path.join(resources, 'runtime');
      env.R_LIBS = path.join(resources, 'library');
      env.R_LIBS_USER = env.R_LIBS;
      env.R_LIBS_SITE = env.R_LIBS;
      env.PATH = `${path.join(resources, 'runtime', 'bin', 'x64')}${path.delimiter}${env.PATH || ''}`;
      // Ignore developer/user R profiles and libraries when running the packaged app.
      env.R_ENVIRON_USER = 'NUL';
      env.R_PROFILE_USER = 'NUL';
    }
    server = spawn(rscript,
      ['-e', 'shiny::runApp(".", host="127.0.0.1", port=as.integer(Sys.getenv("SHINY_PORT")), launch.browser=FALSE)'],
      { cwd: appRoot, env, stdio: 'pipe', windowsHide: true });
    server.stderr.on('data', (chunk) => process.stderr.write(chunk));
    await waitForServer(readinessUrl, server, startupToken);
    window = new BrowserWindow({ width: 1200, height: 850, webPreferences: {
      nodeIntegration: false, contextIsolation: true, sandbox: true
    } });
    window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
    await window.loadURL(baseUrl);
  } catch (error) {
    dialog.showErrorBox('Could not start Library of Happy Moments', error.message);
    app.quit();
  }
});

app.on('before-quit', () => {
  if (server && server.exitCode === null) {
    if (process.platform === 'win32') {
      try {
        execFileSync('taskkill.exe', ['/PID', String(server.pid), '/T', '/F'], { windowsHide: true, stdio: 'ignore' });
      } catch (_) { /* The server may already have exited. */ }
    } else {
      server.kill();
    }
  }
});
app.on('window-all-closed', () => app.quit());
