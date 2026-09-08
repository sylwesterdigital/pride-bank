import crypto from 'node:crypto';
import { promisify } from 'node:util';
import { pool, tx } from './db.js';
import { config } from './config.js';

const scrypt = promisify(crypto.scrypt);
const normalizeEmail = (v) => String(v || '').trim().toLowerCase();
const normalizeUsername = (v) => String(v || '').trim().replace(/^@/, '').toLowerCase();

async function passwordHash(password, salt = crypto.randomBytes(16).toString('hex')) {
  const key = await scrypt(password, `${salt}:${config.sessionPepper}`, 64);
  return `scrypt$${salt}$${Buffer.from(key).toString('hex')}`;
}

async function verifyPassword(password, encoded) {
  const [kind, salt, expected] = String(encoded).split('$');
  if (kind !== 'scrypt' || !salt || !expected) return false;
  const candidate = await passwordHash(password, salt);
  const a = Buffer.from(candidate);
  const b = Buffer.from(encoded);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function sessionDigest(token) {
  return crypto.createHash('sha256').update(`${token}:${config.sessionPepper}`).digest('hex');
}

async function issueSession(client, userId) {
  const token = crypto.randomBytes(32).toString('base64url');
  const digest = sessionDigest(token);
  await client.query(
    `INSERT INTO auth_sessions (user_id, token_hash, expires_at) VALUES ($1,$2,now() + interval '30 days')`,
    [userId, digest]
  );
  return token;
}

export async function register({ email, username, displayName, password }) {
  email = normalizeEmail(email);
  username = normalizeUsername(username);
  displayName = String(displayName || '').trim();
  if (!/^\S+@\S+\.\S+$/.test(email)) throw Object.assign(new Error('Enter a valid email address'), { status: 400 });
  if (!/^[a-z0-9_]{3,24}$/.test(username)) throw Object.assign(new Error('Username must be 3–24 letters, numbers or underscores'), { status: 400 });
  if (displayName.length < 2 || displayName.length > 80) throw Object.assign(new Error('Display name must be 2–80 characters'), { status: 400 });
  if (String(password || '').length < 12) throw Object.assign(new Error('Password must be at least 12 characters'), { status: 400 });
  const hash = await passwordHash(password);
  try {
    return await tx(async (client) => {
      const inserted = await client.query(
        `INSERT INTO users (email, username, display_name, password_hash) VALUES ($1,$2,$3,$4) RETURNING id,email,username,display_name,created_at`,
        [email, username, displayName, hash]
      );
      const user = inserted.rows[0];
      await client.query(`SELECT create_member_blocks_account($1)`, [user.id]);
      const token = await issueSession(client, user.id);
      return { user, token };
    });
  } catch (error) {
    if (error.code === '23505') throw Object.assign(new Error('Email or username is already in use'), { status: 409 });
    throw error;
  }
}

export async function login({ email, password }) {
  const result = await pool.query(`SELECT id,email,username,display_name,password_hash,status FROM users WHERE email=$1`, [normalizeEmail(email)]);
  const user = result.rows[0];
  if (!user || !(await verifyPassword(String(password || ''), user.password_hash))) {
    await new Promise(r => setTimeout(r, 250));
    throw Object.assign(new Error('Email or password is incorrect'), { status: 401 });
  }
  if (user.status !== 'active') throw Object.assign(new Error('Account is not available'), { status: 403 });
  const token = await tx(client => issueSession(client, user.id));
  delete user.password_hash;
  return { user, token };
}

export async function requireAuth(req, res, next) {
  try {
    const header = req.get('authorization') || '';
    const token = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
    if (!token) return res.status(401).json({ error: 'authentication_required' });
    const digest = sessionDigest(token);
    const result = await pool.query(
      `SELECT u.id,u.email,u.username,u.display_name,u.status
       FROM auth_sessions s JOIN users u ON u.id=s.user_id
       WHERE s.token_hash=$1 AND s.revoked_at IS NULL AND s.expires_at>now()`, [digest]
    );
    if (!result.rowCount || result.rows[0].status !== 'active') return res.status(401).json({ error: 'authentication_required' });
    req.user = result.rows[0];
    req.sessionTokenHash = digest;
    next();
  } catch (error) { next(error); }
}

export async function logout(tokenHash) {
  await pool.query(`UPDATE auth_sessions SET revoked_at=now() WHERE token_hash=$1 AND revoked_at IS NULL`, [tokenHash]);
}
