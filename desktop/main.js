const path = require('path');
const { app, BrowserWindow, Menu, shell, session, ipcMain } = require('electron');

const DASHBOARD_URL =
  process.env.POLRI_BWC_DASHBOARD_URL ||
  'https://polribwc.asksenopati.com/dashboard/login';
const ALLOWED_ORIGIN = new URL(DASHBOARD_URL).origin;

let splashWindow = null;
let mainWindow = null;

function createSplashWindow() {
  splashWindow = new BrowserWindow({
    width: 480,
    height: 320,
    frame: false,
    transparent: false,
    alwaysOnTop: true,
    resizable: false,
    maximizable: false,
    minimizable: false,
    show: false,
    center: true,
    backgroundColor: '#0c1b2d',
    webPreferences: {
      contextIsolation: true,
      sandbox: true,
    },
  });

  splashWindow.loadFile(path.join(__dirname, 'splash.html'));
  splashWindow.once('ready-to-show', () => splashWindow.show());
}

function createMainWindow() {
  mainWindow = new BrowserWindow({
    width: 1440,
    height: 900,
    minWidth: 1280,
    minHeight: 760,
    show: false,
    autoHideMenuBar: true,
    title: 'Polri BWC Command Center',
    backgroundColor: '#edf4ff',
    titleBarStyle: 'hidden',
    titleBarOverlay: {
      color: '#081523',
      symbolColor: '#f4f8ff',
      height: 40,
    },
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
      devTools: false,
    },
  });

  Menu.setApplicationMenu(null);

  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    const targetOrigin = new URL(url).origin;
    if (targetOrigin === ALLOWED_ORIGIN) {
      mainWindow.loadURL(url);
      return { action: 'deny' };
    }
    shell.openExternal(url);
    return { action: 'deny' };
  });

  mainWindow.webContents.on('will-navigate', (event, url) => {
    const targetOrigin = new URL(url).origin;
    if (targetOrigin !== ALLOWED_ORIGIN) {
      event.preventDefault();
      shell.openExternal(url);
    }
  });

  mainWindow.webContents.on('before-input-event', (event, input) => {
    if (input.key === 'F12') event.preventDefault();
    if ((input.control || input.meta) && ['r', 'R', 'u', 'U', 'i', 'I'].includes(input.key)) {
      event.preventDefault();
    }
  });

  mainWindow.once('ready-to-show', () => {
    if (splashWindow && !splashWindow.isDestroyed()) splashWindow.close();
    mainWindow.maximize();
    mainWindow.show();
  });

  mainWindow.on('closed', () => {
    mainWindow = null;
  });

  mainWindow.webContents.on('did-finish-load', async () => {
    await injectCommandCenterChrome();
  });

  mainWindow.loadURL(DASHBOARD_URL);
}

async function injectCommandCenterChrome() {
  if (!mainWindow || mainWindow.isDestroyed()) return;

  const css = `
    :root {
      --polri-cc-topbar-height: 62px;
      --polri-cc-topbar-bg: rgba(8, 21, 35, 0.96);
      --polri-cc-topbar-line: rgba(129, 164, 204, 0.18);
      --polri-cc-topbar-text: #f4f8ff;
      --polri-cc-topbar-muted: #8fa8c5;
      --polri-cc-topbar-accent: #d11f1f;
    }
    body.polri-cc-shell {
      padding-top: calc(var(--polri-cc-topbar-height) + 10px) !important;
      box-sizing: border-box;
    }
    #polri-cc-topbar {
      position: fixed;
      top: 0;
      left: 0;
      right: 0;
      height: var(--polri-cc-topbar-height);
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 18px;
      padding: 10px 18px 10px 16px;
      background: linear-gradient(135deg, rgba(8, 21, 35, 0.98), rgba(14, 33, 54, 0.96));
      border-bottom: 1px solid var(--polri-cc-topbar-line);
      box-shadow: 0 16px 34px rgba(5, 14, 24, 0.28);
      z-index: 2147483647;
      -webkit-app-region: drag;
      backdrop-filter: blur(16px);
    }
    #polri-cc-brand {
      display: flex;
      align-items: center;
      gap: 12px;
      min-width: 0;
    }
    #polri-cc-brand-mark {
      width: 38px;
      height: 38px;
      border-radius: 12px;
      display: flex;
      align-items: center;
      justify-content: center;
      background: linear-gradient(135deg, #d11f1f, #7f0c0c);
      color: #fff;
      font: 800 14px/1 "Segoe UI", Arial, sans-serif;
      letter-spacing: 0.08em;
      box-shadow: 0 10px 24px rgba(209, 31, 31, 0.28);
      flex-shrink: 0;
    }
    #polri-cc-brand-copy {
      min-width: 0;
      display: flex;
      flex-direction: column;
      gap: 3px;
    }
    #polri-cc-brand-title {
      color: var(--polri-cc-topbar-text);
      font: 800 14px/1.1 "Segoe UI", Arial, sans-serif;
      letter-spacing: 0.04em;
      text-transform: uppercase;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    #polri-cc-brand-sub {
      color: var(--polri-cc-topbar-muted);
      font: 600 11px/1.1 "Segoe UI", Arial, sans-serif;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    #polri-cc-actions {
      display: flex;
      align-items: center;
      gap: 8px;
      flex-shrink: 0;
      -webkit-app-region: no-drag;
    }
    .polri-cc-btn {
      border: 1px solid rgba(129, 164, 204, 0.18);
      background: rgba(255,255,255,0.06);
      color: var(--polri-cc-topbar-text);
      border-radius: 12px;
      padding: 9px 12px;
      min-width: 42px;
      min-height: 40px;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 7px;
      font: 700 11px/1 "Segoe UI", Arial, sans-serif;
      cursor: pointer;
      transition: transform .15s ease, background .15s ease, border-color .15s ease;
    }
    .polri-cc-btn:hover {
      transform: translateY(-1px);
      background: rgba(255,255,255,0.1);
      border-color: rgba(129, 164, 204, 0.32);
    }
    .polri-cc-btn.alert {
      background: linear-gradient(135deg, rgba(209,31,31,0.94), rgba(127,12,12,0.94));
      border-color: transparent;
    }
    .polri-cc-btn.alert:hover {
      background: linear-gradient(135deg, rgba(221,46,46,0.98), rgba(139,18,18,0.98));
    }
    .polri-cc-btn svg {
      width: 14px;
      height: 14px;
      stroke: currentColor;
      fill: none;
      stroke-width: 1.8;
    }
  `;

  const script = `
    (() => {
      if (document.getElementById('polri-cc-topbar')) return;
      document.body.classList.add('polri-cc-shell');

      const bar = document.createElement('div');
      bar.id = 'polri-cc-topbar';
      bar.innerHTML = \`
        <div id="polri-cc-brand">
          <div id="polri-cc-brand-mark">BWC</div>
          <div id="polri-cc-brand-copy">
            <div id="polri-cc-brand-title">Polri BWC Command Center</div>
            <div id="polri-cc-brand-sub">Dashboard operasional tanpa address bar untuk monitor, live, dan PTT dua arah.</div>
          </div>
        </div>
        <div id="polri-cc-actions">
          <button class="polri-cc-btn" id="polri-cc-refresh" type="button" title="Refresh">
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 4v6h-6"></path><path d="M20 10a8 8 0 1 0 2.34 5.66"></path></svg>
            <span>Refresh</span>
          </button>
          <button class="polri-cc-btn" id="polri-cc-fullscreen" type="button" title="Fullscreen">
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 3H3v5"></path><path d="M16 3h5v5"></path><path d="M21 16v5h-5"></path><path d="M3 16v5h5"></path></svg>
            <span>Layar Penuh</span>
          </button>
          <button class="polri-cc-btn" id="polri-cc-minimize" type="button" title="Minimize">
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12h14"></path></svg>
          </button>
          <button class="polri-cc-btn alert" id="polri-cc-close" type="button" title="Tutup aplikasi">
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M18 6 6 18"></path><path d="m6 6 12 12"></path></svg>
            <span>Tutup</span>
          </button>
        </div>
      \`;

      document.body.prepend(bar);

      const bind = (id, action) => {
        const el = document.getElementById(id);
        if (el) {
          el.addEventListener('click', () => window.polriDesktop && window.polriDesktop[action] && window.polriDesktop[action]());
        }
      };

      bind('polri-cc-refresh', 'reload');
      bind('polri-cc-fullscreen', 'toggleFullscreen');
      bind('polri-cc-minimize', 'minimize');
      bind('polri-cc-close', 'close');
    })();
  `;

  try {
    await mainWindow.webContents.insertCSS(css);
    await mainWindow.webContents.executeJavaScript(script);
  } catch (_) {}
}

app.whenReady().then(async () => {
  app.setName('Polri BWC Command Center');
  createSplashWindow();

  const defaultSession = session.defaultSession;
  defaultSession.setPermissionRequestHandler((webContents, permission, callback) => {
    if (permission === 'media') {
      callback(true);
      return;
    }
    callback(false);
  });

  defaultSession.webRequest.onHeadersReceived((details, callback) => {
    const responseHeaders = { ...details.responseHeaders };
    delete responseHeaders['X-Frame-Options'];
    delete responseHeaders['x-frame-options'];
    callback({ responseHeaders });
  });

  createMainWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createMainWindow();
  });
});

ipcMain.handle('polri-desktop:reload', () => {
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.reloadIgnoringCache();
  }
});

ipcMain.handle('polri-desktop:toggle-fullscreen', () => {
  if (!mainWindow || mainWindow.isDestroyed()) return false;
  const nextState = !mainWindow.isFullScreen();
  mainWindow.setFullScreen(nextState);
  if (!nextState) {
    mainWindow.maximize();
  }
  return nextState;
});

ipcMain.handle('polri-desktop:minimize', () => {
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.minimize();
  }
});

ipcMain.handle('polri-desktop:close', () => {
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.close();
  }
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
