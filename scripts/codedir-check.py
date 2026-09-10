#!/usr/bin/env python3
"""Every SOURCE import in a code directory must resolve inside it.

A grubbery code namespace is hermetic for source: +find-code-ns returns ~
rather than falling back to a parent, so a published app that leans on the
publisher's desk lib compiles there and nowhere else. Run this on the output
of a `sync-overlay.sh --code-dir` before publishing; the bar is 0.

MARCS ARE NOT CHECKED, deliberately. Marks and nexuses go through
+resolve-built, which DOES walk ancestor namespaces - "a mark or nexus
defined in /code is available to all namespaces, but a closer ancestor can
shadow it" - so a base marc resolving upward is correct, not a gap. Checking
them here reported 88 false positives on lattice and buried the 11 real ones.

Usage: codedir-check.py <code-dir>
"""
import os, re, sys
root = sys.argv[1].rstrip('/')
files = set()
for dp, dn, fn in os.walk(root):
    for f in fn:
        files.add(os.path.relpath(os.path.join(dp, f), root))
def norm(p):
    out = []
    for s in p.split('/'):
        if s in ('', '.'): continue
        if s == '..': out and out.pop()
        else: out.append(s)
    return '/'.join(out)
ball = re.compile(r'^\s*/[<&=]\s+\S+\s+(\S+)', re.M)
marc = re.compile(r'\[\s*/((?:[a-z0-9-]+/?)*)\s+%([a-z][a-z0-9-]*)\s*\]')
bad = []
for p in sorted(files):
    if not p.endswith('.hoon'): continue
    src = open(os.path.join(root, p), encoding='utf-8', errors='replace').read()
    for pm in ball.findall(src):
        q = norm(pm.lstrip('/')) if pm.startswith('/') else norm(os.path.dirname(p) + '/' + pm)
        if pm.endswith('/'):
            if not any(f.startswith(q + '/') for f in files): bad.append((p, pm, 'dir'))
            continue
        if q in files or q + '.hoon' in files: continue
        bad.append((p, pm, 'file'))
    if False:
     for d, n in marc.findall(src):
        d = '/'.join(s for s in d.split('/') if s)
        cand = f'mar/{d}/{n}.hoon' if d else f'mar/{n}.hoon'
        if cand not in files: bad.append((p, f'[/{d} %{n}]', 'marc'))
print(f'{root.split("/")[-1]}: {len([f for f in files if f.endswith(".hoon")])} hoon files, {len(bad)} unresolved')
for p, q, k in bad: print(f'   {k:4} {q:44} <- {p}')
