# Pantau Anak — Server

Backend self-hosted (Node.js + SQLite bawaan Node). Dirancang untuk jalan di
home-server UserLAnd (Ubuntu) di belakang Cloudflare Tunnel.

## Jalanin lokal
```bash
cp .env.example .env          # lalu isi JWT_SECRET (sudah diisi otomatis saat setup)
npm install
npm run init-db
npm start                     # default :8787
```
Butuh Node >= 22 (pakai modul `node:sqlite`). Teruji di Node 24.

## Model akun & device
- 1 akun **ortu** (email+password) → dapat JWT.
- Ortu bikin **kode pairing 6 digit** (hidup 5 menit).
- HP anak kirim kode → dapat **device token** permanen. Tiap HP = 1 device.
- 1 ortu bisa banyak device (banyak anak / banyak HP). Tinggal ulang pairing.

## Endpoint ringkas
Header ortu: `Authorization: Bearer <jwt>` · Header anak: `x-device-token: <token>`

### Ortu
| Method | Path | Guna |
|---|---|---|
| POST | /api/parent/register | daftar akun |
| POST | /api/parent/login | login → token |
| POST | /api/parent/pairing-code | buat kode pairing |
| GET  | /api/parent/devices | daftar device + lokasi/baterai/app terakhir |
| GET  | /api/parent/devices/:id/locations?limit= | riwayat lokasi |
| GET  | /api/parent/devices/:id/usage?day=YYYY-MM-DD | pemakaian app |
| GET  | /api/parent/devices/:id/media | daftar foto/klip |
| GET  | /api/parent/media/:mediaId | ambil file media |
| GET  | /api/parent/events | SOS / baterai lemah / check-in |
| POST | /api/parent/events/:id/seen | tandai sudah dilihat |
| POST | /api/parent/devices/:id/command | kirim perintah: lock / unlock / checkin |

### Device (HP anak)
| Method | Path | Guna |
|---|---|---|
| POST | /api/device/pair | tukar kode → device token |
| POST | /api/device/location | lat,lng,accuracy,battery,charging |
| POST | /api/device/usage | {day, apps:[{package,label,seconds}]} |
| POST | /api/device/foreground | app yang sedang dibuka |
| POST | /api/device/event | {type:"sos", payload} dll |
| POST | /api/device/media | multipart: kind, commandId, file |
| POST | /api/device/command-status | {commandId, status:done/failed} |

### WebSocket `/ws`
- `?role=device&token=<deviceToken>` — HP anak nahan koneksi, terima perintah
  realtime (lock, checkin). Perintah pending otomatis dikirim saat reconnect.
- `?role=parent&token=<jwt>` — app ortu terima push event live (SOS, online/offline).

## Prinsip privasi (penting)
- Tidak ada fitur sembunyi-sembunyi. Check-in kamera/mic selalu disertai notif di
  HP anak, dan Android 12+ menampilkan indikator hijau saat kamera/mic aktif.
- Media check-in dipicu eksplisit (SOS anak atau perintah ortu), bukan streaming diam-diam.

## Deploy ke home-server UserLAnd (ringkas)
```bash
# di Ubuntu/UserLAnd
sudo apt update && sudo apt install -y nodejs npm   # pastikan node >= 22
git clone <repo> pantau-anak && cd pantau-anak/server
cp .env.example .env && nano .env                   # set JWT_SECRET acak
npm install && npm run init-db
node src/index.js                                   # atau pakai pm2 / systemd
```
Lalu arahkan Cloudflare Tunnel ke `http://localhost:8787` (ingress hostname
mis. `pantau.wiraproject.my.id`). WebSocket jalan lewat tunnel yang sama.
