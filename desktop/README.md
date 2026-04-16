# Polri BWC Desktop

Wrapper Electron untuk menjalankan dashboard `Polri BWC Command Center` sebagai aplikasi Windows tanpa address bar browser.

## Target URL

Secara default aplikasi membuka:

```text
https://polribwc.asksenopati.com/dashboard/login
```

Jika perlu override saat build atau run:

```bash
POLRI_BWC_DASHBOARD_URL=https://host-lain/dashboard/login npm start
```

## Menjalankan lokal

```bash
cd desktop
npm install
npm start
```

## Build Windows `.exe`

Jalankan dari mesin Windows:

```bash
cd desktop
npm install
npm run dist:win
```

Output installer akan muncul di:

```text
desktop/dist/
```

## Karakteristik app

- tanpa address bar
- menu bar disembunyikan
- devtools dimatikan default
- akses mikrofon dashboard diizinkan agar PTT dua arah tetap berjalan
- hanya mengizinkan navigasi internal pada origin dashboard yang sama
- top bar command center internal dengan tombol:
  - `Refresh`
  - `Layar Penuh`
  - `Minimize`
  - `Tutup`
- branding command center langsung muncul di dalam app, bukan UI browser
