const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('polriDesktop', {
  platform: process.platform,
  mode: 'command-center',
  reload: () => ipcRenderer.invoke('polri-desktop:reload'),
  toggleFullscreen: () => ipcRenderer.invoke('polri-desktop:toggle-fullscreen'),
  minimize: () => ipcRenderer.invoke('polri-desktop:minimize'),
  close: () => ipcRenderer.invoke('polri-desktop:close'),
});
