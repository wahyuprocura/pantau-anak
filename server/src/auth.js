// Helper autentikasi: JWT untuk ortu, token acak untuk device anak.
import jwt from 'jsonwebtoken';
import bcrypt from 'bcryptjs';
import crypto from 'node:crypto';
import 'dotenv/config';

const JWT_SECRET = process.env.JWT_SECRET || 'dev-insecure-secret';
const PARENT_TTL = parseInt(process.env.PARENT_TOKEN_TTL || '2592000', 10);

export function hashPassword(pw) {
  return bcrypt.hashSync(pw, 10);
}
export function checkPassword(pw, hash) {
  return bcrypt.compareSync(pw, hash);
}

export function signParentToken(parent) {
  return jwt.sign({ sub: parent.id, role: 'parent', email: parent.email }, JWT_SECRET, {
    expiresIn: PARENT_TTL,
  });
}

export function verifyParentToken(token) {
  try {
    const p = jwt.verify(token, JWT_SECRET);
    return p.role === 'parent' ? p : null;
  } catch {
    return null;
  }
}

// Token device: string acak panjang. Yang disimpan di DB hanya hash-nya.
export function newDeviceToken() {
  return crypto.randomBytes(32).toString('hex');
}
export function hashToken(t) {
  return crypto.createHash('sha256').update(t).digest('hex');
}

// Middleware Express untuk endpoint ortu.
export function requireParent(req, res, next) {
  const h = req.headers.authorization || '';
  const token = h.startsWith('Bearer ') ? h.slice(7) : null;
  const payload = token && verifyParentToken(token);
  if (!payload) return res.status(401).json({ error: 'unauthorized' });
  req.parentId = payload.sub;
  next();
}
