import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { pool } from '../src/db.js';

const here=path.dirname(fileURLToPath(import.meta.url));
const migrationsDir=path.resolve(here,'../migrations');
await pool.query(`CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())`);
const files=(await fs.readdir(migrationsDir)).filter(x=>x.endsWith('.sql')).sort();
for (const name of files) {
  const exists=await pool.query('SELECT 1 FROM schema_migrations WHERE name=$1',[name]);
  if (exists.rowCount) continue;
  const sql=await fs.readFile(path.join(migrationsDir,name),'utf8');
  const client=await pool.connect();
  try { await client.query('BEGIN'); await client.query(sql); await client.query('INSERT INTO schema_migrations(name) VALUES ($1)',[name]); await client.query('COMMIT'); console.log(`applied ${name}`); }
  catch(e){ await client.query('ROLLBACK'); throw e; }
  finally { client.release(); }
}
await pool.end();
