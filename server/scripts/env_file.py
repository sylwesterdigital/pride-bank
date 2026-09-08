#!/usr/bin/env python3
"""Safe parser/writer/exec helper for /etc/pride-bank/server.env.

This file is data, never shell code. Values are intentionally not expanded.
"""
from __future__ import annotations
import os, re, sys, tempfile
from pathlib import Path

KEY_RE = re.compile(r'^[A-Z][A-Z0-9_]*$')
ALLOWED_KEYS = {
    'NODE_ENV','PORT','DATABASE_URL','DATABASE_SSL','SESSION_PEPPER',
    'STRIPE_SECRET_KEY','STRIPE_PUBLISHABLE_KEY','STRIPE_WEBHOOK_SECRET',
    'STRIPE_WEBHOOK_ID','STRIPE_MODE','STRIPE_EXPECTED_BUSINESS_NAME',
    'PUBLIC_BASE_URL','IOS_BLOCKS_PURCHASE_RAIL'
}
REQUIRED_KEYS = {
    'NODE_ENV','PORT','DATABASE_URL','DATABASE_SSL','SESSION_PEPPER',
    'STRIPE_SECRET_KEY','STRIPE_PUBLISHABLE_KEY','STRIPE_WEBHOOK_SECRET',
    'STRIPE_MODE','STRIPE_EXPECTED_BUSINESS_NAME','PUBLIC_BASE_URL',
    'IOS_BLOCKS_PURCHASE_RAIL'
}
SAFE_RAW = re.compile(r'^[A-Za-z0-9_./:@%+,-]+$')

def fail(msg: str) -> None:
    print(f'ERROR: {msg}', file=sys.stderr)
    raise SystemExit(1)

def decode_value(raw: str, lineno: int) -> str:
    raw = raw.strip()
    if not raw:
        return ''
    if raw[0] in "'\"":
        q = raw[0]
        if len(raw) < 2 or raw[-1] != q:
            fail(f'unterminated quoted value at line {lineno}')
        body = raw[1:-1]
        if q == '"':
            # Only decode escapes emitted by this tool. Never expand $, backticks, etc.
            out=[]; i=0
            while i < len(body):
                if body[i] == '\\' and i+1 < len(body) and body[i+1] in ('\\','"'):
                    out.append(body[i+1]); i += 2
                else:
                    out.append(body[i]); i += 1
            return ''.join(out)
        return body
    return raw

def parse(path: Path) -> tuple[dict[str,str], list[str]]:
    if not path.is_file():
        fail(f'environment file does not exist: {path}')
    data: dict[str,str] = {}
    order: list[str] = []
    for lineno, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
        stripped=line.strip()
        if not stripped or stripped.startswith('#'):
            continue
        if '=' not in line:
            fail(f'malformed environment entry at line {lineno}')
        key, raw = line.split('=',1)
        key=key.strip()
        if not KEY_RE.fullmatch(key):
            fail(f'invalid environment key at line {lineno}: {key!r}')
        if key not in ALLOWED_KEYS:
            fail(f'unknown Pride environment key at line {lineno}: {key}')
        if key in data:
            fail(f'duplicate Pride environment key: {key}')
        value=decode_value(raw, lineno)
        if '\x00' in value or '\n' in value or '\r' in value:
            fail(f'unsafe control character in {key}')
        data[key]=value; order.append(key)
    return data, order

def encode(value: str) -> str:
    if value and SAFE_RAW.fullmatch(value):
        return value
    # systemd EnvironmentFile and our parser both accept this conservative form.
    return '"' + value.replace('\\','\\\\').replace('"','\\"') + '"'

def write_atomic(path: Path, data: dict[str,str], order: list[str]) -> None:
    missing=[k for k in REQUIRED_KEYS if k not in data]
    if missing:
        fail('missing required environment keys: ' + ', '.join(sorted(missing)))
    parent=path.parent
    parent.mkdir(parents=True, exist_ok=True)
    fd,tmp=tempfile.mkstemp(prefix=path.name+'.', dir=str(parent), text=True)
    try:
        with os.fdopen(fd,'w',encoding='utf-8') as f:
            for key in order:
                if key in data:
                    f.write(f'{key}={encode(data[key])}\n')
            for key in sorted(data):
                if key not in order:
                    f.write(f'{key}={encode(data[key])}\n')
            f.flush(); os.fsync(f.fileno())
        os.chmod(tmp,0o600)
        os.replace(tmp,path)
    finally:
        try: os.unlink(tmp)
        except FileNotFoundError: pass

def validate_semantics(data: dict[str,str]) -> None:
    missing=[k for k in REQUIRED_KEYS if k not in data]
    if missing: fail('missing required environment keys: ' + ', '.join(sorted(missing)))
    if data['NODE_ENV'] != 'production': fail('NODE_ENV must be production')
    if data['PORT'] != '4317': fail('PORT must be 4317')
    if not data['DATABASE_URL'].startswith('postgresql://pride_app:') or not data['DATABASE_URL'].endswith('@127.0.0.1:5432/pride_bank'):
        fail('DATABASE_URL must target the isolated local pride_bank database as pride_app')
    if data['DATABASE_SSL'] not in ('false','true'): fail('DATABASE_SSL must be true or false')
    if not re.fullmatch(r'[0-9a-f]{64}', data['SESSION_PEPPER']): fail('SESSION_PEPPER must be 64 lowercase hex characters')
    if data['STRIPE_MODE'] not in ('test','live'): fail('STRIPE_MODE must be test or live')
    mode=data['STRIPE_MODE']
    secret=data['STRIPE_SECRET_KEY']; pub=data['STRIPE_PUBLISHABLE_KEY']
    if secret != 'CHANGE_ME' and not re.fullmatch(rf'sk_{mode}_[A-Za-z0-9_]+', secret): fail('Stripe secret key does not match STRIPE_MODE')
    if pub != 'CHANGE_ME' and not re.fullmatch(rf'pk_{mode}_[A-Za-z0-9_]+', pub): fail('Stripe publishable key does not match STRIPE_MODE')
    whsec=data['STRIPE_WEBHOOK_SECRET']
    if whsec != 'CHANGE_ME' and not re.fullmatch(r'whsec_[A-Za-z0-9_]+', whsec): fail('invalid Stripe webhook signing secret')
    wid=data.get('STRIPE_WEBHOOK_ID','CHANGE_ME')
    if wid != 'CHANGE_ME' and not re.fullmatch(r'we_[A-Za-z0-9_]+', wid): fail('invalid Stripe webhook endpoint id')
    base=data['PUBLIC_BASE_URL']
    if base != 'CHANGE_ME' and not re.fullmatch(r'https://[^\s?#]+(?:/[^\s?#]*)?', base): fail('PUBLIC_BASE_URL must be HTTPS or CHANGE_ME')
    if data['STRIPE_EXPECTED_BUSINESS_NAME'] != 'WORKWORK.FUN LTD': fail('unexpected Stripe business name')
    if data['IOS_BLOCKS_PURCHASE_RAIL'] not in ('stripe','storekit'): fail('invalid iOS purchase rail')

def main() -> None:
    if len(sys.argv) < 3:
        fail('usage: env_file.py <validate|normalize|get|set-stdin|set-many-stdin|exec> FILE ...')
    cmd=sys.argv[1]; path=Path(sys.argv[2])
    data,order=parse(path)
    if cmd == 'validate':
        validate_semantics(data); print('ENV_FILE_VALID=1'); return
    if cmd == 'normalize':
        validate_semantics(data); write_atomic(path,data,order); print('ENV_FILE_NORMALIZED=1'); return
    if cmd == 'get':
        if len(sys.argv) != 4: fail('get requires KEY')
        key=sys.argv[3]
        if key not in data: raise SystemExit(2)
        sys.stdout.write(data[key]); return
    if cmd == 'set-many-stdin':
        if len(sys.argv) != 3: fail('set-many-stdin takes updates on stdin')
        updates=[]
        for lineno,line in enumerate(sys.stdin.read().splitlines(),1):
            if not line: continue
            if '=' not in line: fail(f'malformed stdin update at line {lineno}')
            key,value=line.split('=',1)
            if key not in ALLOWED_KEYS: fail(f'unknown Pride environment key: {key}')
            if '\n' in value or '\r' in value or '\x00' in value: fail('control characters are forbidden')
            updates.append((key,value))
        if not updates: fail('no environment updates supplied')
        for key,value in updates:
            if key not in data: order.append(key)
            data[key]=value
        validate_semantics(data); write_atomic(path,data,order); return
    if cmd == 'set-stdin':
        if len(sys.argv) != 4: fail('set-stdin requires KEY')
        key=sys.argv[3]
        if key not in ALLOWED_KEYS: fail(f'unknown Pride environment key: {key}')
        value=sys.stdin.read()
        if value.endswith('\n'): value=value[:-1]
        if '\n' in value or '\r' in value or '\x00' in value: fail('multi-line/control-character values are forbidden')
        if key not in data: order.append(key)
        data[key]=value
        validate_semantics(data)
        write_atomic(path,data,order); return
    if cmd == 'exec':
        if len(sys.argv) < 5 or sys.argv[3] != '--': fail('exec requires -- COMMAND [ARGS...]')
        validate_semantics(data)
        env=os.environ.copy(); env.update(data)
        os.execvpe(sys.argv[4], sys.argv[4:], env)
    fail(f'unknown command: {cmd}')

if __name__ == '__main__':
    main()
