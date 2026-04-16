const path = require('path');
const { app, BrowserWindow, Menu, shell, session } = require('electron');

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

  mainWindow.loadURL(DASHBOARD_URL);
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

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
