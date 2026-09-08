import { pool } from './db.js';

export async function getBlocksAccount(userId) {
  const r = await pool.query(`SELECT id,balance,status FROM blocks_accounts WHERE user_id=$1 AND account_type='member'`, [userId]);
  if (!r.rowCount) throw Object.assign(new Error('Blocks account missing'), { status: 500 });
  return r.rows[0];
}

export async function balanceFor(userId) {
  const account = await getBlocksAccount(userId);
  return Number(account.balance);
}

export async function activityFor(userId, limit = 50) {
  const account = await getBlocksAccount(userId);
  const r = await pool.query(
    `SELECT lt.id,lt.kind,lt.description,lt.created_at,le.amount,lt.external_reference,lt.metadata
     FROM ledger_entries le JOIN ledger_transactions lt ON lt.id=le.transaction_id
     WHERE le.account_id=$1 ORDER BY lt.created_at DESC LIMIT $2`, [account.id, Math.min(Number(limit)||50,100)]
  );
  return r.rows.map(row => ({ ...row, amount: Number(row.amount) }));
}

export async function transferBlocks({ fromUserId, toUsername, amount, note, idempotencyKey }) {
  const n = Number(amount);
  if (!Number.isSafeInteger(n) || n <= 0 || n > 10_000_000) throw Object.assign(new Error('Invalid Blocks amount'), { status: 400 });
  if (!idempotencyKey || idempotencyKey.length < 12) throw Object.assign(new Error('Idempotency-Key is required'), { status: 400 });
  const target = await pool.query(`SELECT id FROM users WHERE username=$1 AND status='active'`, [String(toUsername||'').replace(/^@/,'').toLowerCase()]);
  if (!target.rowCount) throw Object.assign(new Error('Member not found'), { status: 404 });
  if (target.rows[0].id === fromUserId) throw Object.assign(new Error('Cannot send Blocks to yourself'), { status: 400 });
  const r = await pool.query(`SELECT * FROM post_member_transfer($1,$2,$3,$4,$5)`, [fromUserId, target.rows[0].id, n, String(note||'').slice(0,180), idempotencyKey]);
  return r.rows[0];
}
