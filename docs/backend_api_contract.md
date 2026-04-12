# Backend API Contract

Dokumen ini mendeskripsikan kontrak awal untuk menghubungkan aplikasi `Polri BWC` ke backend sungguhan.

Base URL dibentuk dari:

- `POLRI_BWC_API_BASE_URL`
- `POLRI_BWC_API_VERSION`

Contoh:

`http://10.0.2.2:8080/api/v1`

## 1. Health Check

`GET /health`

Response:

```json
{
  "status": "ok",
  "service": "polri-bwc-api",
  "time": "2026-04-07T10:00:00.000Z"
}
```

## 1. Presence / User Online

`GET /presence`

Response:

```json
[
  {
    "username": "test1",
    "deviceId": "android-test1",
    "status": "online",
    "activeChannelId": "ch3",
    "clientTimeIso": "2026-04-07T05:20:00.000Z",
    "lastSeenIso": "2026-04-07T05:20:03.000Z",
    "resolvedStatus": "online"
  }
]
```

`POST /presence/heartbeat`

Body:

```json
{
  "username": "test1",
  "deviceId": "android-test1",
  "status": "online",
  "activeChannelId": "ch3",
  "clientTimeIso": "2026-04-07T05:20:00.000Z"
}
```

## 2. Chat Threads

`GET /chats`

Response:

```json
{
  "Bripda A. Susilo": [
    {
      "fromMe": false,
      "text": "Santoso, posisi sekarang di mana?",
      "timeLabel": "08:42"
    }
  ]
}
```

`POST /chats`

Body:

```json
{
  "threads": {
    "Bripda A. Susilo": [
      {
        "fromMe": true,
        "text": "Siap, posisi aman.",
        "timeLabel": "08:45"
      }
    ]
  }
}
```

`POST /chats/message`

Body:

```json
{
  "threadName": "Bripda A. Susilo",
  "message": {
    "fromMe": true,
    "text": "Siap, posisi aman.",
    "timeLabel": "08:45"
  }
}
```

`POST /chats/auto-reply`

Body:

```json
{
  "threadName": "Bripda A. Susilo"
}
```

Response:

```json
{
  "messages": [
    {
      "fromMe": false,
      "text": "Command center menerima update Anda.",
      "timeLabel": "08:46"
    }
  ]
}
```

## 3. Incident Reports

`GET /reports`

Response:

```json
[
  {
    "id": "IR_20260407_084512",
    "type": "Penangkapan",
    "description": "Tersangka diamankan tanpa perlawanan.",
    "witness": "Budi",
    "recordingId": "REC_20260407_084031",
    "recordedAtIso": "2026-04-07T08:45:12.000Z",
    "locationLabel": "Jl. Jend. Sudirman, Jakpus",
    "deliveryStatus": "Diteruskan ke command center"
  }
]
```

`POST /reports`

Body:

```json
{
  "id": "IR_20260407_084512",
  "type": "Penangkapan",
  "description": "Tersangka diamankan tanpa perlawanan.",
  "witness": "Budi",
  "recordingId": "REC_20260407_084031",
  "recordedAtIso": "2026-04-07T08:45:12.000Z",
  "locationLabel": "Jl. Jend. Sudirman, Jakpus",
  "deliveryStatus": "Dikirim ke endpoint"
}
```

## 4. Recordings

`GET /recordings`

Response:

```json
[
  {
    "id": "REC_20260407_084031",
    "officerName": "Bripda R. Santoso",
    "unitName": "Polda Metro Jaya",
    "recordedAtIso": "2026-04-07T08:40:31.000Z",
    "filePath": "/storage/emulated/0/Android/data/.../recordings/bwc_123.mp4",
    "latitude": -6.2088,
    "longitude": 106.8456,
    "source": "LIVE_RECORD_CAPTURE",
    "notes": "Penangkapan - 4m 21dt",
    "status": "syncing",
    "durationSeconds": 261,
    "sizeBytes": 84541440,
    "locationLabel": "Jl. Jend. Sudirman, Jakpus",
    "tagLabel": "Penangkapan",
    "relatedToCase": true,
    "syncProgress": 64,
    "backendStatusLabel": "Upload chunk 64%"
  }
]
```

`POST /recordings`

Body mengikuti skema `RecordingEntry` di atas.

`POST /recordings/upload`

Body minimal:

```json
{
  "recordingId": "REC_20260407_084031",
  "chunkIndex": 1,
  "chunkCount": 4,
  "bytesBase64": "..."
}
```

Response:

```json
{
  "recordingId": "REC_20260407_084031",
  "status": "syncing",
  "syncProgress": 25,
  "backendStatusLabel": "Upload chunk 25%"
}
```

## 5. Catatan Integrasi

- Semua field tanggal gunakan `ISO 8601 UTC`.
- `status` rekaman saat ini mendukung:
  - `pending`
  - `syncing`
  - `uploaded`
  - `failed`
- Jika endpoint belum siap, aplikasi akan fallback ke penyimpanan lokal.
- Untuk emulator Android, host lokal backend biasanya dipanggil via `http://10.0.2.2:<port>`.

## 5. PTT / HT Digital

`GET /ptt/channels`

Response:

```json
[
  { "id": "ch1", "label": "Ch 1", "subtitle": "" },
  { "id": "ch2", "label": "Ch 2", "subtitle": "" },
  { "id": "ch3", "label": "Ch 3", "subtitle": "" },
  { "id": "ch4", "label": "Ch 4", "subtitle": "" }
]
```

`GET /ptt/feed?channelId=ch3`

Response:

```json
[
  {
    "initials": "AS",
    "speakerName": "Bripda A. Susilo",
    "statusLabel": "2.1d",
    "timeLabel": "08:42",
    "waveLevel": 0.82,
    "accentColorHex": "#33E3B1",
    "isSystem": false
  }
]
```

`POST /ptt/transmit/start`

Body:

```json
{
  "channelId": "ch3",
  "officerId": "88122344",
  "deviceId": "BWC-ANDROID-001"
}
```

Response:

```json
{
  "sessionId": "PTT_20260407_101201",
  "status": "talking"
}
```

`POST /ptt/transmit/stop`

Body:

```json
{
  "sessionId": "PTT_20260407_101201",
  "durationSeconds": 12
}
```

Response:

```json
{
  "status": "completed"
}
```
