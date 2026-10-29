// Inisialisasi database memakai SQLite bawaan Node (node:sqlite, tanpa native build).
import { DatabaseSync } from 'node:sqlite';
import fs from 'node:fs';
import path from 'node:path';
import 'dotenv/config';

const DB_PATH = process.env.DB_PATH || './data/pantau.db';

// Pastikan folder data ada
fs.mkdirSync(path.dirname(DB_PATH), { recursive: true });

export const db = new DatabaseSync(DB_PATH);
db.exec('PRAGMA journal_mode = WAL;');
db.exec('PRAGMA foreign_keys = ON;');

db.exec(`
CREATE TABLE IF NOT EXISTS parents (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  email       TEXT UNIQUE NOT NULL,
  pass_hash   TEXT NOT NULL,
  name        TEXT,
  created_at  INTEGER NOT NULL
);

-- Tiap HP anak = 1 baris. Nempel ke satu akun ortu.
CREATE TABLE IF NOT EXISTS devices (
  id            TEXT PRIMARY KEY,          -- uuid device
  parent_id     INTEGER NOT NULL REFERENCES parents(id) ON DELETE CASCADE,
  name          TEXT NOT NULL,             -- mis. "HP Budi"
  token_hash    TEXT NOT NULL,             -- hash token device (dipakai app anak)
  platform      TEXT,
  created_at    INTEGER NOT NULL,
  last_seen     INTEGER
);

-- Kode pairing sekali pakai: ortu generate, anak masukkan.
CREATE TABLE IF NOT EXISTS pairing_codes (
  code        TEXT PRIMARY KEY,            -- 6 digit
  parent_id   INTEGER NOT NULL REFERENCES parents(id) ON DELETE CASCADE,
  expires_at  INTEGER NOT NULL,
  used        INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS locations (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  device_id   TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  lat         REAL NOT NULL,
  lng         REAL NOT NULL,
  accuracy    REAL,
  battery     INTEGER,                     -- 0-100
  charging    INTEGER,                     -- 0/1
  recorded_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_loc_device_time ON locations(device_id, recorded_at DESC);

-- Ringkasan pemakaian app per hari (dari Usage Access).
CREATE TABLE IF NOT EXISTS app_usage (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  device_id   TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  day         TEXT NOT NULL,               -- YYYY-MM-DD (zona HP anak)
  package     TEXT NOT NULL,
  label       TEXT,
  seconds     INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL,
  UNIQUE(device_id, day, package)
);
CREATE INDEX IF NOT EXISTS idx_usage_device_day ON app_usage(device_id, day);

-- App yang SEDANG dibuka (foreground), diperbarui berkala.
CREATE TABLE IF NOT EXISTS foreground (
  device_id   TEXT PRIMARY KEY REFERENCES devices(id) ON DELETE CASCADE,
  package     TEXT,
  label       TEXT,
  since       INTEGER,
  updated_at  INTEGER
);

-- Kejadian dari HP anak ke ortu: sos, low_battery, checkin_media, dll.
CREATE TABLE IF NOT EXISTS events (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  device_id   TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  type        TEXT NOT NULL,
  payload     TEXT,                        -- JSON
  created_at  INTEGER NOT NULL,
  seen        INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_events_device_time ON events(device_id, created_at DESC);

-- Perintah dari ortu ke HP anak: lock, checkin (kamera+mic), unlock.
CREATE TABLE IF NOT EXISTS commands (
  id          TEXT PRIMARY KEY,
  device_id   TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  type        TEXT NOT NULL,               -- lock | checkin | unlock
  params      TEXT,                        -- JSON
  status      TEXT NOT NULL DEFAULT 'pending', -- pending|sent|done|failed
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
);

-- Media hasil check-in (foto depan/belakang, klip audio). Transparan: app anak
-- menampilkan notif saat menangkap.
CREATE TABLE IF NOT EXISTS media (
  id          TEXT PRIMARY KEY,
  device_id   TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  command_id  TEXT REFERENCES commands(id) ON DELETE SET NULL,
  kind        TEXT NOT NULL,               -- photo_front | photo_back | audio
  filename    TEXT NOT NULL,
  mime        TEXT,
  created_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_media_device_time ON media(device_id, created_at DESC);
`);

console.log(`DB siap di ${DB_PATH}`);

export default db;
