#!/usr/bin/env python3
from __future__ import annotations
import argparse, pathlib, re, shutil, sys, time

def blocks(text: str):
    out=[]; i=0; n=len(text)
    state='normal'; quote=''; stack=[]
    while i<n:
        c=text[i]
        if state=='comment':
            if c=='\n': state='normal'
            i+=1; continue
        if state=='quote':
            if c=='\\': i+=2; continue
            if c==quote: state='normal'
            i+=1; continue
        if c=='#': state='comment'; i+=1; continue
        if c in "'\"": state='quote'; quote=c; i+=1; continue
        if c=='{':
            j=i-1
            while j>=0 and text[j].isspace(): j-=1
            k=j
            while k>=0 and (text[k].isalnum() or text[k] in '_-'): k-=1
            word=text[k+1:j+1]
            stack.append((word,i))
        elif c=='}' and stack:
            word,start=stack.pop()
            if word=='server': out.append((start,i))
        i+=1
    return out

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--site', required=True)
    ap.add_argument('--root', required=True)
    ap.add_argument('--snippet', default='/etc/nginx/snippets/pride-bank-api.conf')
    ap.add_argument('--backup-dir', required=True)
    args=ap.parse_args()
    path=pathlib.Path(args.site).resolve()
    text=path.read_text()
    marker='include /etc/nginx/snippets/pride-bank-api.conf;'
    matches=[]
    for start,end in blocks(text):
        body=text[start+1:end]
        if args.root in body: matches.append((start,end,body))
    if len(matches)!=1:
        print(f'ERROR: expected exactly one nginx server block containing {args.root!r} in {path}, found {len(matches)}', file=sys.stderr)
        return 2
    start,end,body=matches[0]
    names=[]
    for m in re.finditer(r'(?m)^\s*server_name\s+([^;]+);', body):
        names += [x for x in m.group(1).split() if x not in ('_','localhost') and '*' not in x and '$' not in x]
    names=list(dict.fromkeys(names))
    https=bool(re.search(r'(?m)^\s*listen\s+[^;]*\b443\b[^;]*;', body) or re.search(r'(?m)^\s*ssl_certificate\s+', body))
    if len(names)!=1 or not https:
        print('ERROR: matching nginx block does not have exactly one unambiguous HTTPS server_name', file=sys.stderr)
        return 3
    if marker not in body:
        backup_dir=pathlib.Path(args.backup_dir); backup_dir.mkdir(parents=True,exist_ok=True)
        backup=backup_dir/(path.name+'.'+time.strftime('%Y%m%d%H%M%S')+'.bak')
        shutil.copy2(path,backup)
        insert='\n    # BEGIN PRIDE BANK MANAGED API\n    '+marker+'\n    # END PRIDE BANK MANAGED API\n'
        path.write_text(text[:end]+insert+text[end:])
        print(f'BACKUP={backup}')
    print(f'PUBLIC_BASE_URL=https://{names[0]}')
    return 0
if __name__=='__main__': raise SystemExit(main())
