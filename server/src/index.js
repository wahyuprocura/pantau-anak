// Pantau Anak — server utama (REST + WebSocket), self-hosted.
import express from 'express';
import { WebSocketServer } from 'ws';
import multer from 'multer';
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import { nanoid } from 'nanoid';
import { customAlphabet } from 'nanoid';
import 'dotenv/config';

import db from './db.js';
import {
  hashPassword, checkPassword, signParentToken,
  newDeviceToken, hashToken, requireParent, verifyParentToken,
} from './auth.js';

const PORT = parseInt(process.env.PORT || '8787', 10);
const MEDIA_DIR = process.env.MEDIA_DIR || './data/media';
const PAIRING_TTL = parseInt(process.env.PAIRING_CODE_TTL || '300', 10);
fs.mkdirSync(MEDIA_DIR, { recursive: true });

const now = () => Date.now();
const code6 = customAlphabet('0123456789', 6);

const app = express();
app.use(express.json({ limit: '1mb' }));

// ---------- Autentikasi device (header x-device-token) ----------
function requireDevice(req, res, next) {
  const token = req.headers['x-device-token'];
  if (!token) return res.status(401).json({ error: 'no device token' });
  const row = db.prepare('SELECT * FROM devices WHERE token_hash = ?').get(hashToken(String(token)));
  if (!row) return res.status(401).json({ error: 'invalid device token' });
  db.prepare('UPDATE devices SET last_seen = ? WHERE id = ?').run(now(), row.id);
  req.device = row;
  next();
}

function ownDevice(parentId, deviceId) {
  return db.prepare('SELECT * FROM devices WHERE id = ? AND parent_id = ?').get(deviceId, parentId);
}

// ======================= ORTU =======================
app.post('/api/parent/register', (req, res) => {
  const { email, password, name } = req.body || {};
  if (!email || !password) return res.status(400).json({ error: 'email & password wajib' });
  const exists = db.prepare('SELECT id FROM parents WHERE email = ?').get(email);
  if (exists) return res.status(409).json({ error: 'email sudah terdaftar' });
  const info = db.prepare('INSERT INTO parents (email, pass_hash, name, created_at) VALUES (?,?,?,?)')
    .run(email, hashPassword(password), name || null, now());
  const parent = { id: info.lastInsertRowid, email };
  res.json({ token: signParentToken(parent) });
});

app.post('/api/parent/login', (req, res) => {
  const { email, password } = req.body || {};
  const p = db.prepare('SELECT * FROM parents WHERE email = ?').get(email || '');
  if (!p || !checkPassword(password || '', p.pass_hash))
    return res.status(401).json({ error: 'email atau password salah' });
  res.json({ token: signParentToken(p), name: p.name });
});

// Buat kode pairing untuk mendaftarkan HP anak baru.
app.post('/api/parent/pairing-code', requireParent, (req, res) => {
  const code = code6();
  const expiresAt = now() + PAIRING_TTL * 1000;
  db.prepare('INSERT OR REPLACE INTO pairing_codes (code, parent_id, expires_at, used) VALUES (?,?,?,0)')
    .run(code, req.parentId, expiresAt);
  res.json({ code, expiresAt, ttl: PAIRING_TTL });
});

// Daftar device + ringkasan terakhir.
app.get('/api/parent/devices', requireParent, (req, res) => {
  const devices = db.prepare('SELECT id, name, platform, created_at, last_seen FROM devices WHERE parent_id = ?')
    .all(req.parentId);
  const out = devices.map((d) => {
    const loc = db.prepare('SELECT lat,lng,accuracy,battery,charging,recorded_at FROM locations WHERE device_id = ? ORDER BY recorded_at DESC LIMIT 1').get(d.id);
    const fg = db.prepare('SELECT package,label,since,updated_at FROM foreground WHERE device_id = ?').get(d.id);
    return { ...d, online: deviceSockets.has(d.id), lastLocation: loc || null, foreground: fg || null };
  });
  res.json({ devices: out });
});

app.get('/api/parent/devices/:id/locations', requireParent, (req, res) => {
  if (!ownDevice(req.parentId, req.params.id)) return res.status(404).json({ error: 'device tidak ditemukan' });
  const limit = Math.min(parseInt(req.query.limit || '200', 10), 1000);
  const rows = db.prepare('SELECT lat,lng,accuracy,battery,charging,recorded_at FROM locations WHERE device_id = ? ORDER BY recorded_at DESC LIMIT ?')
    .all(req.params.id, limit);
  res.json({ locations: rows });
});

app.get('/api/parent/devices/:id/usage', requireParent, (req, res) => {
  if (!ownDevice(req.parentId, req.params.id)) return res.status(404).json({ error: 'device tidak ditemukan' });
  const day = req.query.day || new Date().toISOString().slice(0, 10);
  const rows = db.prepare('SELECT package,label,seconds FROM app_usage WHERE device_id = ? AND day = ? ORDER BY seconds DESC')
    .all(req.params.id, day);
  res.json({ day, apps: rows });
});

app.get('/api/parent/devices/:id/media', requireParent, (req, res) => {
  if (!ownDevice(req.parentId, req.params.id)) return res.status(404).json({ error: 'device tidak ditemukan' });
  const rows = db.prepare('SELECT id,kind,mime,created_at,command_id FROM media WHERE device_id = ? ORDER BY created_at DESC LIMIT 100')
    .all(req.params.id);
  res.json({ media: rows });
});

// Sajikan file media (hanya milik device si ortu).
app.get('/api/parent/media/:mediaId', requireParent, (req, res) => {
  const m = db.prepare('SELECT * FROM media WHERE id = ?').get(req.params.mediaId);
  if (!m || !ownDevice(req.parentId, m.device_id)) return res.status(404).end();
  const fp = path.join(MEDIA_DIR, m.filename);
  if (!fs.existsSync(fp)) return res.status(404).end();
  if (m.mime) res.type(m.mime);
  fs.createReadStream(fp).pipe(res);
});

// Kejadian yang belum dilihat (SOS, baterai lemah, check-in selesai).
app.get('/api/parent/events', requireParent, (req, res) => {
  const rows = db.prepare(`
    SELECT e.id, e.device_id, e.type, e.payload, e.created_at, e.seen, d.name AS device_name
    FROM events e JOIN devices d ON d.id = e.device_id
    WHERE d.parent_id = ? ORDER BY e.created_at DESC LIMIT 100`).all(req.parentId);
  res.json({ events: rows.map((r) => ({ ...r, payload: r.payload ? JSON.parse(r.payload) : null })) });
});

app.post('/api/parent/events/:id/seen', requireParent, (req, res) => {
  db.prepare(`UPDATE events SET seen = 1 WHERE id = ? AND device_id IN (SELECT id FROM devices WHERE parent_id = ?)`)
    .run(req.params.id, req.parentId);
  res.json({ ok: true });
});

// Kirim perintah ke HP anak (lock / unlock / checkin kamera+mic).
app.post('/api/parent/devices/:id/command', requireParent, (req, res) => {
  const d = ownDevice(req.parentId, req.params.id);
  if (!d) return res.status(404).json({ error: 'device tidak ditemukan' });
  const { type, params } = req.body || {};
  if (!['lock', 'unlock', 'checkin', 'live', 'live_stop'].includes(type))
    return res.status(400).json({ error: 'type tidak dikenal' });
  const id = nanoid();
  const t = now();
  db.prepare('INSERT INTO commands (id, device_id, type, params, status, created_at, updated_at) VALUES (?,?,?,?,?,?,?)')
    .run(id, d.id, type, params ? JSON.stringify(params) : null, 'pending', t, t);
  const delivered = pushToDevice(d.id, { kind: 'command', id, type, params: params || {} });
  if (delivered) db.prepare('UPDATE commands SET status = ?, updated_at = ? WHERE id = ?').run('sent', now(), id);
  res.json({ commandId: id, delivered });
});

// ======================= DEVICE (HP ANAK) =======================
// Pairing: tukar kode 6 digit jadi token device permanen.
app.post('/api/device/pair', (req, res) => {
  const { code, name, platform } = req.body || {};
  const pc = db.prepare('SELECT * FROM pairing_codes WHERE code = ?').get(String(code || ''));
  if (!pc || pc.used || pc.expires_at < now()) return res.status(400).json({ error: 'kode tidak valid / kedaluwarsa' });
  const token = newDeviceToken();
  const id = nanoid();
  const t = now();
  db.prepare('INSERT INTO devices (id, parent_id, name, token_hash, platform, created_at, last_seen) VALUES (?,?,?,?,?,?,?)')
    .run(id, pc.parent_id, name || 'HP Anak', hashToken(token), platform || null, t, t);
  db.prepare('UPDATE pairing_codes SET used = 1 WHERE code = ?').run(pc.code);
  res.json({ deviceId: id, token });
});

app.post('/api/device/location', requireDevice, (req, res) => {
  const { lat, lng, accuracy, battery, charging, recordedAt } = req.body || {};
  if (typeof lat !== 'number' || typeof lng !== 'number') return res.status(400).json({ error: 'lat/lng wajib' });
  db.prepare('INSERT INTO locations (device_id, lat, lng, accuracy, battery, charging, recorded_at) VALUES (?,?,?,?,?,?,?)')
    .run(req.device.id, lat, lng, accuracy ?? null, battery ?? null, charging ? 1 : 0, recordedAt || now());
  // Baterai lemah -> buat event sekali.
  if (typeof battery === 'number' && battery <= 15 && !charging) {
    addEvent(req.device.id, 'low_battery', { battery });
  }
  res.json({ ok: true });
});

app.post('/api/device/usage', requireDevice, (req, res) => {
  const { day, apps } = req.body || {};
  if (!day || !Array.isArray(apps)) return res.status(400).json({ error: 'day & apps wajib' });
  const stmt = db.prepare(`INSERT INTO app_usage (device_id, day, package, label, seconds, updated_at)
    VALUES (?,?,?,?,?,?)
    ON CONFLICT(device_id, day, package) DO UPDATE SET seconds=excluded.seconds, label=excluded.label, updated_at=excluded.updated_at`);
  const t = now();
  db.exec('BEGIN');
  try {
    for (const a of apps) stmt.run(req.device.id, day, a.package, a.label || null, a.seconds || 0, t);
    db.exec('COMMIT');
  } catch (e) {
    db.exec('ROLLBACK');
    return res.status(500).json({ error: 'gagal simpan usage' });
  }
  res.json({ ok: true, count: apps.length });
});

app.post('/api/device/foreground', requireDevice, (req, res) => {
  const { package: pkg, label, since } = req.body || {};
  db.prepare(`INSERT INTO foreground (device_id, package, label, since, updated_at) VALUES (?,?,?,?,?)
    ON CONFLICT(device_id) DO UPDATE SET package=excluded.package, label=excluded.label, since=excluded.since, updated_at=excluded.updated_at`)
    .run(req.device.id, pkg || null, label || null, since || now(), now());
  res.json({ ok: true });
});

app.post('/api/device/event', requireDevice, (req, res) => {
  const { type, payload } = req.body || {};
  if (!type) return res.status(400).json({ error: 'type wajib' });
  addEvent(req.device.id, type, payload || null);
  res.json({ ok: true });
});

app.post('/api/device/command-status', requireDevice, (req, res) => {
  const { commandId, status } = req.body || {};
  if (!['done', 'failed', 'sent'].includes(status)) return res.status(400).json({ error: 'status tidak valid' });
  db.prepare('UPDATE commands SET status = ?, updated_at = ? WHERE id = ? AND device_id = ?')
    .run(status, now(), commandId, req.device.id);
  res.json({ ok: true });
});

// Upload media hasil check-in.
const upload = multer({ dest: MEDIA_DIR, limits: { fileSize: 25 * 1024 * 1024 } });
app.post('/api/device/media', requireDevice, upload.single('file'), (req, res) => {
  const { kind, commandId } = req.body || {};
  if (!req.file || !['photo_front', 'photo_back', 'audio'].includes(kind))
    return res.status(400).json({ error: 'file & kind wajib' });
  const id = nanoid();
  db.prepare('INSERT INTO media (id, device_id, command_id, kind, filename, mime, created_at) VALUES (?,?,?,?,?,?,?)')
    .run(id, req.device.id, commandId || null, kind, path.basename(req.file.path), req.file.mimetype || null, now());
  addEvent(req.device.id, 'checkin_media', { kind, mediaId: id });
  res.json({ ok: true, mediaId: id });
});

// ---------- util ----------
function addEvent(deviceId, type, payload) {
  db.prepare('INSERT INTO events (device_id, type, payload, created_at) VALUES (?,?,?,?)')
    .run(deviceId, type, payload ? JSON.stringify(payload) : null, now());
  // dorong ke ortu yang online
  const dev = db.prepare('SELECT parent_id FROM devices WHERE id = ?').get(deviceId);
  if (dev) pushToParent(dev.parent_id, { kind: 'event', deviceId, type, payload });
}

app.get('/healthz', (_req, res) => res.json({ ok: true, ts: now() }));

// ======================= WebSocket =======================
// device: /ws?role=device&token=<deviceToken>
// parent: /ws?role=parent&token=<jwt>
const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: '/ws' });

const deviceSockets = new Map();           // deviceId -> ws
const parentSockets = new Map();           // parentId -> Set<ws>

function pushToDevice(deviceId, msg) {
  const ws = deviceSockets.get(deviceId);
  if (ws && ws.readyState === ws.OPEN) { ws.send(JSON.stringify(msg)); return true; }
  return false;
}
function pushToParent(parentId, msg) {
  const set = parentSockets.get(parentId);
  if (!set) return;
  for (const ws of set) if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(msg));
}

wss.on('connection', (ws, req) => {
  const url = new URL(req.url, 'http://x');
  const role = url.searchParams.get('role');
  const token = url.searchParams.get('token') || '';

  if (role === 'device') {
    const dev = db.prepare('SELECT * FROM devices WHERE token_hash = ?').get(hashToken(token));
    if (!dev) return ws.close(4001, 'invalid device token');
    deviceSockets.set(dev.id, ws);
    db.prepare('UPDATE devices SET last_seen = ? WHERE id = ?').run(now(), dev.id);
    pushToParent(dev.parent_id, { kind: 'device_online', deviceId: dev.id });
    // kirim perintah yang masih pending
    const pend = db.prepare("SELECT * FROM commands WHERE device_id = ? AND status = 'pending'").all(dev.id);
    for (const c of pend) ws.send(JSON.stringify({ kind: 'command', id: c.id, type: c.type, params: c.params ? JSON.parse(c.params) : {} }));
    ws.on('close', () => {
      if (deviceSockets.get(dev.id) === ws) deviceSockets.delete(dev.id);
      pushToParent(dev.parent_id, { kind: 'device_offline', deviceId: dev.id });
    });
    // Signaling WebRTC: HP anak -> ortu (SDP offer/answer, ICE candidate).
    ws.on('message', (buf) => {
      let msg; try { msg = JSON.parse(buf.toString()); } catch { return; }
      if (msg.kind === 'signal') {
        pushToParent(dev.parent_id, { kind: 'signal', deviceId: dev.id, data: msg.data });
      }
    });
  } else if (role === 'parent') {
    const p = verifyParentToken(token);
    if (!p) return ws.close(4001, 'invalid parent token');
    if (!parentSockets.has(p.sub)) parentSockets.set(p.sub, new Set());
    parentSockets.get(p.sub).add(ws);
    // Signaling WebRTC: ortu -> HP anak. Wajib device miliknya sendiri.
    ws.on('message', (buf) => {
      let msg; try { msg = JSON.parse(buf.toString()); } catch { return; }
      if (msg.kind === 'signal' && msg.deviceId) {
        const d = db.prepare('SELECT id FROM devices WHERE id = ? AND parent_id = ?').get(msg.deviceId, p.sub);
        if (d) pushToDevice(d.id, { kind: 'signal', data: msg.data });
      }
    });
    ws.on('close', () => parentSockets.get(p.sub)?.delete(ws));
  } else {
    ws.close(4000, 'role tidak dikenal');
  }
});

server.listen(PORT, () => console.log(`Pantau Anak server jalan di :${PORT}`));
