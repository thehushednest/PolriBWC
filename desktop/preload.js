const { contextBridge } = require('electron');

contextBridge.exposeInMainWorld('polriDesktop', {
  platform: process.platform,
  mode: 'command-center',
});
