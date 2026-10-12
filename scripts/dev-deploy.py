#!/usr/bin/env python3
"""Deploy this checkout's code/ to auspex on a FAKE grubbery ship.

usage: dev-deploy.py <base-url> <cookie-jar> [--add] [--approve] [--code DIR]

Mirrors code/ into the ball at /auspex-dev/code through the explorer
(create-folder, create-file, write-text), then stamps that tree's
version.json with a dev version, which makes the desk pull. With --add it
first makes the desk: POST /apps/grubbery/desks/add {name: auspex, code:
/auspex-dev/code}, so auspex lands at the same path as on ricsul,
/apps/shell.shell/desks/auspex.desk. Files are written only when they
differ, so a redeploy sends only what changed. --approve then grants the
instance its own weir.json (approve-weir with it as `granted`; without
`granted` this kernel grants an empty weir) and reloads its permits.

Never point this at a real ship: it is for fleet ships (TESTING.md). Get
a cookie jar with scripts/hoon-test-kit/ship-cookie.sh.
"""
import argparse, functools, json, os, re, sys, time, urllib.error, urllib.parse, urllib.request

print = functools.partial(print, flush=True)  # progress shows in a log
ROOT = '/auspex-dev/code'
APP = '/apps/shell.shell/desks/auspex.desk/desk/data/auspex.auspex_app'


class Keep3xx(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a):
        return None  # the explorer answers a form POST with 303: that is success


NOREDIRECT = urllib.request.build_opener(Keep3xx)
MITES = {'js': 'application/javascript', 'json': 'application/json', 'html': 'text/html', 'css': 'text/css',
         'svg': 'image/svg', 'txt': 'text/plain', 'md': 'text/markdown'}


def cookie(jar):
    """the urbauth cookie from a curl jar (#HttpOnly_ lines included)"""
    for line in open(jar):
        f = line.removeprefix('#HttpOnly_').rstrip('\n').split('\t')
        if len(f) == 7 and f[5].startswith('urbauth-'):
            return f'{f[5]}={f[6]}'
    sys.exit(f'dev-deploy: no urbauth cookie in {jar}')


class Ship:
    def __init__(self, base, jar):
        self.base, self.cookie = base.rstrip('/'), cookie(jar)

    def req(self, path, data=None, ctype='application/x-www-form-urlencoded'):
        url = self.base + urllib.parse.quote(path, safe='/?=&.~-_')
        body = None
        if data is not None:
            body = (urllib.parse.urlencode(data) if isinstance(data, dict) and ctype.endswith('urlencoded')
                    else data).encode()
        h = {'Cookie': self.cookie}
        if body:
            h['Content-Type'] = ctype
        r = urllib.request.Request(url, data=body, headers=h)
        try:
            with NOREDIRECT.open(r, timeout=600) as resp:
                return resp.status, resp.read()
        except urllib.error.HTTPError as e:
            return e.code, e.read()

    def ball(self, path):
        return '/grubbery/ball' + path

    def children(self, d):
        """name -> entry for a ball dir, or None if it does not exist."""
        st, body = self.req(self.ball(d) + '?list=1')
        if st == 404:
            return None
        if st != 200:
            sys.exit(f'dev-deploy: list {d}: {st} {body[:200]!r}')
        return {c['name']: c for c in json.loads(body)['children']}

    def post(self, path, data, ok=(200, 303)):
        st, body = self.req(self.ball(path), data)
        if st not in ok:
            sys.exit(f'dev-deploy: {data.get("action")} {path}: {st} {body[:400].decode(errors="replace")}')

    def text(self, f):
        st, body = self.req('/grubbery/api/file' + f)
        return body.decode(errors='replace') if st == 200 else None


def ensure_dir(ship, d):
    parent, name = d.rsplit('/', 1)
    parent = parent or '/'
    kids = ship.children(parent if parent != '/' else '')
    if kids is None:
        ensure_dir(ship, parent)
        kids = {}
    if name not in kids:
        ship.post(parent if parent != '/' else '', {'action': 'create-folder', 'foldername': name})


def blot_for(name, top):
    """/hoon for source; /json only for the desk-level files (bill.json,
    tile.json, version.json); anything else, json under nex/ included,
    is %mime, which the nexus's /< imports of ui-app/ expect"""
    ext = name.rsplit('.', 1)[-1]
    if ext == 'hoon':
        return '/hoon'
    return '/json' if ext == 'json' and top else '/mime'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('base'); ap.add_argument('jar')
    ap.add_argument('--add', action='store_true', help='also make the desk (first deploy)')
    ap.add_argument('--approve', action='store_true', help='grant the instance its weir.json')
    ap.add_argument('--code', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'code'))
    a = ap.parse_args()
    ship = Ship(a.base, a.jar)
    if not re.match(r'https?://(localhost|127\.0\.0\.1)(:\d+)?$', ship.base):
        sys.exit('dev-deploy: refusing a non-local ship; this is for fake fleet ships only')

    code = os.path.normpath(a.code)
    sent = 0
    for dirpath, dirs, files in os.walk(code):
        dirs.sort()
        rel = os.path.relpath(dirpath, code)
        d = ROOT if rel == '.' else ROOT + '/' + rel.replace(os.sep, '/')
        ensure_dir(ship, d)
        kids = ship.children(d) or {}
        for f in sorted(files):
            if rel == '.' and f == 'version.json':
                continue  # stamped last: changing it is what makes the desk pull
            src = open(os.path.join(dirpath, f), encoding='utf-8').read()
            blot = blot_for(f, rel == '.')
            if f in kids and kids[f].get('blot') != blot:  # made with another blot
                ship.post(d, {'action': 'delete-grub', 'filename': f})
                del kids[f]
            if f not in kids:
                ship.post(d, {'action': 'create-file', 'filename': f, 'blot': blot})
            elif blot != '/json' and ship.text(d + '/' + f) == src:
                continue
            args = {'action': 'write-text', 'content': src}
            mite = MITES.get(f.rsplit('.', 1)[-1])
            if blot == '/mime' and mite:
                args['mite'] = mite
            ship.post(d + '/' + f, args, ok=(200,))
            sent += 1
            print(f'  {d}/{f}', flush=True)

    ver = json.load(open(os.path.join(code, 'version.json')))['version']
    stamp = f'{ver}-dev-{int(time.time())}'
    if 'version.json' not in (ship.children(ROOT) or {}):
        ship.post(ROOT, {'action': 'create-file', 'filename': 'version.json', 'blot': '/json'})
    ship.post(ROOT + '/version.json', {'action': 'write-text', 'content': json.dumps({'version': stamp})}, ok=(200,))
    print(f'dev-deploy: {sent} files written, version.json = {stamp}')

    if a.add:
        st, body = ship.req('/apps/grubbery/desks/add',
                            json.dumps({'name': 'auspex', 'code': ROOT}), 'application/json')
        print(f'dev-deploy: desks/add: {st} {body.decode(errors="replace")}')
        if st not in (200, 409):
            sys.exit(1)

    if a.approve:
        weir = None
        for _ in range(180):  # the instance appears once the desk has built (minutes)
            weir = ship.text(APP + '/weir.json')
            if weir:
                break
            time.sleep(5)
        if not weir:
            sys.exit(f'dev-deploy: no {APP}/weir.json yet; run --approve again later')
        body = {'action': 'approve-weir', 'app': APP, 'picks': {}, 'granted': json.loads(weir)}
        for path, data in (('/apps/grubbery/permits', body), ('/apps/grubbery/permits/reload', {'app': APP})):
            st, out = ship.req(path, json.dumps(data), 'application/json')
            print(f'dev-deploy: {path}: {st}')
            if st not in (200, 303):
                sys.exit(out[:400].decode(errors='replace'))


if __name__ == '__main__':
    main()
