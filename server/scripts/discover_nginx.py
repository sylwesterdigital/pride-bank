#!/usr/bin/env python3
from __future__ import annotations
import argparse
import os
import pathlib
import re
import secrets
import subprocess
import sys
from dataclasses import dataclass
from urllib.parse import quote, urlsplit, urlunsplit

@dataclass(frozen=True)
class Candidate:
    site: str
    host: str
    base_path: str

FILE_MARKER = re.compile(r'^# configuration file (.+?):\s*$', re.M)


def split_effective(text: str):
    matches = list(FILE_MARKER.finditer(text))
    for i, m in enumerate(matches):
        start = m.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        yield m.group(1), text[start:end]


def block_ranges(text: str, keyword: str):
    out=[]
    i=0
    n=len(text)
    state='normal'; quote_char=''; stack=[]
    while i<n:
        c=text[i]
        if state=='comment':
            if c=='\n': state='normal'
            i+=1; continue
        if state=='quote':
            if c=='\\': i+=2; continue
            if c==quote_char: state='normal'
            i+=1; continue
        if c=='#': state='comment'; i+=1; continue
        if c in "'\"": state='quote'; quote_char=c; i+=1; continue
        if c=='{':
            j=i-1
            while j>=0 and text[j].isspace(): j-=1
            k=j
            while k>=0 and (text[k].isalnum() or text[k] in '_-'): k-=1
            word=text[k+1:j+1]
            stack.append((word,i))
        elif c=='}' and stack:
            word,start=stack.pop()
            if word==keyword: out.append((start,i))
        i+=1
    return out


def directive_values(body: str, name: str):
    return [m.group(1).strip() for m in re.finditer(rf'(?:^|[;\n])\s*{re.escape(name)}\s+([^;{{}}]+);', body)]


def plain_path(value: str):
    value=value.strip().strip('"\'')
    if '$' in value:
        return None
    return value


def norm_uri(path: str):
    if not path.startswith('/'):
        path='/' + path
    path=re.sub(r'/+', '/', path)
    if path != '/' and path.endswith('/'):
        path=path[:-1]
    return path


def rel_uri(root: str, public_root: str):
    try:
        rel=os.path.relpath(public_root, root)
    except ValueError:
        return None
    if rel == '.': return '/'
    if rel.startswith('../') or rel == '..': return None
    return norm_uri('/' + rel)


def https_block(body: str):
    return any(re.search(r'\b443\b', v) for v in directive_values(body,'listen')) or bool(directive_values(body,'ssl_certificate'))


def server_names(body: str):
    names=[]
    for value in directive_values(body,'server_name'):
        for item in value.split():
            if item in ('_','localhost') or '*' in item or '$' in item:
                continue
            if re.fullmatch(r'[A-Za-z0-9.-]+', item):
                names.append(item.rstrip('.'))
    return list(dict.fromkeys(names))


def top_level_text(body: str):
    # Blank nested blocks so server-level root directives are not confused with location roots.
    chars=list(body)
    for keyword in ('location','if'):
        for start,end in block_ranges(body, keyword):
            for i in range(start, end+1):
                chars[i]=' '
    return ''.join(chars)


def location_candidates(body: str, public_root: str):
    paths=set()
    for start,end in block_ranges(body,'location'):
        # recover location header immediately before the opening brace
        j=start-1
        while j>=0 and body[j].isspace(): j-=1
        line_start=body.rfind('\n',0,j+1)+1
        header=body[line_start:start].strip()
        m=re.match(r'location\s+(?:=\s+|\^~\s+)?([^\s{]+)', header)
        if not m: continue
        uri=m.group(1)
        if not uri.startswith('/') or uri.startswith('/~') or '$' in uri: continue
        loc_body=body[start+1:end]
        aliases=directive_values(loc_body,'alias')
        roots=directive_values(loc_body,'root')
        for alias in aliases:
            ap=plain_path(alias)
            if not ap: continue
            ap=os.path.normpath(ap)
            pr=os.path.normpath(public_root)
            if pr==ap:
                paths.add(norm_uri(uri))
            elif pr.startswith(ap.rstrip('/') + '/'):
                rel=os.path.relpath(pr,ap)
                paths.add(norm_uri(uri.rstrip('/') + '/' + rel))
        for root in roots:
            rp=plain_path(root)
            if not rp: continue
            rel=rel_uri(os.path.normpath(rp), os.path.normpath(public_root))
            if rel and (rel==norm_uri(uri) or rel.startswith(norm_uri(uri).rstrip('/') + '/')):
                paths.add(rel)
    return paths


def candidates_from_block(site: str, body: str, public_root: str):
    if not https_block(body): return []
    names=server_names(body)
    if not names: return []
    # In addition to parsed root/alias mappings, probe conservative suffixes of
    # the public filesystem path. This handles nginx layouts where root/alias is
    # inherited through an included snippet and therefore lives in another
    # source file in `nginx -T` output. The random live probe determines truth.
    parts=[x for x in pathlib.Path(public_root).parts if x not in ('/','var','www')]
    paths={'/'}
    for count in range(1, min(4,len(parts))+1):
        paths.add(norm_uri('/' + '/'.join(parts[-count:])))
    for root in directive_values(top_level_text(body),'root'):
        rp=plain_path(root)
        if rp:
            rel=rel_uri(os.path.normpath(rp), os.path.normpath(public_root))
            if rel: paths.add(rel)
    paths |= location_candidates(body, public_root)
    return [Candidate(site, host, p) for host in names for p in sorted(paths)]


def curl_probe(host: str, url: str, expected: str):
    commands=[
        ['curl','--fail','--silent','--show-error','--max-time','6','--connect-timeout','3','--resolve',f'{host}:443:127.0.0.1',url],
        ['curl','--fail','--silent','--show-error','--max-time','6','--connect-timeout','3',url],
    ]
    for cmd in commands:
        try:
            p=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True,check=False)
        except FileNotFoundError:
            return False
        if p.returncode==0 and p.stdout.strip()==expected:
            return True
    return False


def candidate_base(c: Candidate):
    return f'https://{c.host}' + ('' if c.base_path == '/' else c.base_path)


def normalize_base_url(value: str):
    parsed=urlsplit(value.strip())
    if parsed.scheme.lower() != 'https' or not parsed.hostname or parsed.query or parsed.fragment:
        return None
    host=parsed.hostname.lower().rstrip('.')
    port='' if parsed.port in (None,443) else f':{parsed.port}'
    path=norm_uri(parsed.path or '/')
    return urlunsplit(('https', host+port, '' if path=='/' else path, '', ''))


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--root', required=True)
    ap.add_argument('--preferred-base-url')
    args=ap.parse_args()
    public_root=str(pathlib.Path(args.root).resolve())
    index=pathlib.Path(public_root)/'index.html'
    if not index.is_file():
        print(f'ERROR: public root does not contain index.html: {public_root}',file=sys.stderr); return 2
    try:
        dump=subprocess.run(['nginx','-T'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,check=False)
    except FileNotFoundError:
        print('ERROR: nginx is not installed',file=sys.stderr); return 2
    if dump.returncode!=0:
        print('ERROR: nginx -T failed; refusing discovery',file=sys.stderr); print(dump.stdout,file=sys.stderr); return 2
    candidates=set()
    for site, content in split_effective(dump.stdout):
        if not site.startswith('/etc/nginx/'):
            continue
        for start,end in block_ranges(content,'server'):
            body=content[start+1:end]
            candidates.update(candidates_from_block(site, body, public_root))
    if not candidates:
        print('ERROR: no HTTPS nginx server block produced a filesystem mapping candidate for the Pride public root',file=sys.stderr); return 3

    token='pride-nginx-probe-' + secrets.token_hex(16)
    probe_name='pride-probe-' + secrets.token_hex(8) + '.txt'
    probe_path=pathlib.Path(public_root)/probe_name
    probe_path.write_text(token+'\n')
    os.chmod(probe_path,0o644)
    matches=[]
    try:
        for c in sorted(candidates,key=lambda x:(x.host,x.base_path,x.site)):
            prefix='' if c.base_path=='/' else c.base_path
            url=f'https://{c.host}{prefix}/{quote(probe_name)}'
            if curl_probe(c.host,url,token):
                matches.append(c)
    finally:
        try: probe_path.unlink()
        except FileNotFoundError: pass
    # Dedupe exact live mappings. Multiple aliases may legitimately serve the
    # same Pride tree on a shared nginx host. When the release profile supplies
    # a preferred canonical URL, it is accepted only if the live random-file
    # probe proved exactly one matching nginx server block for that exact URL.
    # This resolves aliases without guessing and without modifying the aliases.
    unique=list(dict.fromkeys(matches))
    c=None
    preferred=normalize_base_url(args.preferred_base_url) if args.preferred_base_url else None
    if args.preferred_base_url and not preferred:
        print('ERROR: --preferred-base-url must be a clean HTTPS origin/path with no query or fragment.',file=sys.stderr)
        return 4
    if preferred:
        preferred_matches=[m for m in unique if normalize_base_url(candidate_base(m)) == preferred]
        if len(preferred_matches)==1:
            c=preferred_matches[0]
            print(f'PROVEN_ALIAS_COUNT={len(unique)}')
            print('SELECTION=preferred-canonical-url')
        else:
            print(f'ERROR: preferred canonical URL {preferred} was proven by {len(preferred_matches)} nginx mappings; expected exactly one. No nginx files were modified.',file=sys.stderr)
            for m in unique:
                print(f'CANDIDATE={candidate_base(m)} SITE={m.site}',file=sys.stderr)
            return 4
    elif len(unique)==1:
        c=unique[0]
    else:
        print(f'ERROR: HTTPS probe matched {len(unique)} nginx mappings; expected exactly one. No nginx files were modified.',file=sys.stderr)
        for m in unique:
            print(f'CANDIDATE={candidate_base(m)} SITE={m.site}',file=sys.stderr)
        return 4
    base=candidate_base(c)
    print(f'SITE_FILE={c.site}')
    print(f'SERVER_NAME={c.host}')
    print(f'BASE_PATH={c.base_path}')
    print(f'PUBLIC_BASE_URL={base}')
    return 0

if __name__=='__main__':
    raise SystemExit(main())
