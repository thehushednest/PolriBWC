# Polri BWC Flutter

Prototype aplikasi `Flutter` untuk body worn camera personel Polri dengan satu codebase untuk `Android` dan `iOS`.

## Fitur Saat Ini

- layar login `Polri BWC`
- beranda operasional dengan shift aktif, statistik, backend status, dan aktivitas terakhir
- layar rekam aktif dengan timer, GPS, ukuran file, enkripsi, tombol darurat, dan preview kamera
- peta patroli mock dengan daftar personel aktif, chat, dan SOS
- tab `PTT / HT` digital dengan pilihan kanal, feed siaran, dan tombol tahan-bicara
- galeri rekaman dengan pencarian, filter, progress sinkronisasi, dan detail rekaman
- pemutar video lokal di detail rekaman untuk file yang benar-benar tersimpan di perangkat
- form laporan insiden yang mengaitkan rekaman dengan jenis kejadian
- backend gateway yang bisa berjalan di mode `mock` atau `API`

## Struktur Penting

- `lib/main.dart`
- `lib/src/body_worn_app.dart`
- `lib/src/app_config.dart`
- `lib/src/backend_gateway.dart`
- `lib/src/api_client.dart`
- `lib/src/polri_backend_api.dart`
- `lib/src/models.dart`
- `lib/src/recording_detail_sheet.dart`
- `lib/src/tabs_primary.dart`
- `lib/src/tabs_secondary.dart`
- `lib/src/ui_components.dart`
- `lib/src/navigation.dart`
- `docs/backend_api_contract.md`
- `pubspec.yaml`
- `legacy-android/`

## Catatan

- Folder `legacy-android/` menyimpan draft Android native sebelumnya agar tidak hilang.
- Versi sekarang sudah punya fondasi pemisahan antara UI, gateway backend, dan API client.
- Secara default aplikasi berjalan di mode `mock` agar tetap bisa didemokan tanpa server.
- Rekaman seed/dummy akan menampilkan placeholder preview, sedangkan rekaman lokal hasil tangkapan perangkat bisa diputar di detail rekaman.
- Flow laporan tetap ada, tetapi sekarang lebih cocok diakses dari galeri/detail rekaman agar navigasi bawah fokus ke operasi lapangan.

## Mode Backend

Default:

```bash
flutter run
```

Saat ini default repo diarahkan ke server Wi-Fi laptop:

- base URL default: `http://192.168.1.26:8787`
- mode backend default: `API`

Mode API sungguhan:

```bash
flutter run --dart-define=POLRI_BWC_USE_MOCK=false --dart-define=POLRI_BWC_API_BASE_URL=http://10.0.2.2:8080
```

Environment yang didukung:

- `POLRI_BWC_USE_MOCK=true|false`
- `POLRI_BWC_API_BASE_URL=http://host:port`
- `POLRI_BWC_API_VERSION=v1`
- `POLRI_BWC_TIMEOUT_SECONDS=10`

Kontrak endpoint awal ada di `docs/backend_api_contract.md`.

## Kesiapan Deploy

Fondasi yang sudah disiapkan:

- package Android bukan lagi `com.example.*`
- konfigurasi backend sudah bisa dipindah dari mock ke API dengan `dart-define`
- struktur app sudah dipisah antara UI, gateway backend, dan API client

Sebelum rilis produksi, yang masih perlu dilanjutkan:

- release signing key Android
- environment `dev`, `staging`, dan `prod`
- backend upload, autentikasi, dan PTT transport sungguhan
- hardening perangkat dan kebijakan MDM
- uji di perangkat fisik untuk kamera, audio, GPS, dan background behavior

## Menjalankan

```bash
flutter pub get
flutter run
```

## Uji Dengan HP Dan Server Laptop

Alamat Wi-Fi laptop saat ini:

- `192.168.1.26`

Port server lokal yang dipakai:

- `8787`

Jalankan server lokal di laptop:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start_local_server.ps1 -HostAddress 0.0.0.0 -Port 8787
```

Health check server:

- `http://192.168.1.26:8787/api/v1/health`

Build APK yang diarahkan ke server laptop:

```powershell
flutter build apk --debug --dart-define=POLRI_BWC_USE_MOCK=false --dart-define=POLRI_BWC_API_BASE_URL=http://192.168.1.26:8787 --dart-define=POLRI_BWC_API_VERSION=v1
```

Catatan:

- HP dan laptop harus berada di Wi-Fi yang sama.
- Kalau Windows Defender meminta izin jaringan saat server dijalankan, izinkan untuk jaringan `Private`.
