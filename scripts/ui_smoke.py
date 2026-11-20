#!/usr/bin/env python3
"""UI smoke test: findings only, no fixes.

One command:   python3 scripts/ui_smoke.py            (system python3 is fine; it bootstraps its own venv)

What it does
  1. Starts a THROWAWAY Postgres (initdb in a temp dir, 127.0.0.1, random port). Never touches your dev/prod DB.
  2. Migrates it, runs `seed_dev_users` (Demo School) and adds finance@/hr@ logins (STAFF + one group each).
  3. Starts Django (DEBUG, console mail, eager Celery) and the Vite dev server on private ports.
  4. Logs in as admin, teacher, finance and HR; discovers every sidebar link from the DOM; visits each at
     phone / tablet / desktop and records page errors, console errors, failed API calls (4xx/5xx),
     horizontal scroll, overlapping/clipped elements, and a screenshot.
  5. Writes docs/specs/reports/ui-smoke-<date>.md (+ ui-smoke-<date>/ screenshots) and tears everything down.

Options: --roles admin,hr  --viewports phone,desktop  --keep-going (default)  --headed  --date YYYY-MM-DD
First run creates scripts/.venv-smoke (gitignored) with `playwright` only; backend/venv_new is not touched.
"""
import argparse
import datetime as dt
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BACKEND = ROOT / 'backend'
FRONTEND = ROOT / 'frontend' / 'codingclubskenya'
PY = ROOT / 'backend' / 'venv_new' / 'bin' / 'python'  # always the project venv, even for a baseline checkout
VENV = ROOT / 'scripts' / '.venv-smoke'
PASSWORD = 'DevPass#2026'  # seed_dev_users password (dev seed accounts only)

# role label -> (login email, groups to ensure, base seed user it clones or None)
PERSONAS = {
    'admin': ('admin@demo.com', None),
    'teacher': ('teacher@demo.com', None),
    'finance': ('finance@demo.com', 'Finance'),
    'hr': ('hr@demo.com', 'HR'),
}
VIEWPORTS = {
    'phone': {'width': 390, 'height': 844},
    'tablet': {'width': 820, 'height': 1180},
    'desktop': {'width': 1440, 'height': 900},
}


# ----------------------------------------------------------------------------- bootstrap
def ensure_venv():
    """Re-exec inside scripts/.venv-smoke (playwright only). No-op if already there."""
    vpy = VENV / 'bin' / 'python'
    if Path(sys.prefix).resolve() == VENV.resolve():
        return
    if not vpy.exists():
        print('[smoke] creating scripts/.venv-smoke with playwright (first run only)...')
        subprocess.run([sys.executable, '-m', 'venv', str(VENV)], check=True)
        subprocess.run([str(vpy), '-m', 'pip', 'install', '-q', 'playwright'], check=True)
    # no-op when the matching Chromium is already cached in ~/.cache/ms-playwright
    subprocess.run([str(vpy), '-m', 'playwright', 'install', 'chromium'], check=True)
    os.execv(str(vpy), [str(vpy), *sys.argv])


def free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


def wait_http(url, timeout=90, name=''):
    end = time.time() + timeout
    while time.time() < end:
        try:
            urllib.request.urlopen(url, timeout=2)
            return
        except urllib.error.HTTPError:
            return  # server is up, any status is fine
        except Exception:
            time.sleep(0.5)
    raise RuntimeError(f'{name or url} did not come up within {timeout}s')


def pg_bin():
    for v in ('18', '17', '16', '15'):
        p = Path(f'/usr/lib/postgresql/{v}/bin')
        if (p / 'initdb').exists():
            return p
    found = shutil.which('initdb')
    if found:
        return Path(found).parent
    raise SystemExit('initdb not found: install postgresql server binaries')


class Stack:
    """Throwaway Postgres + Django + Vite. Everything is torn down in close()."""

    def __init__(self):
        self.tmp = Path(tempfile.mkdtemp(prefix='ui-smoke-'))
        self.procs = []
        self.pg_dir = None
        self.api_port = free_port()
        self.web_port = free_port()
        self.pg_port = free_port()

    @property
    def api(self):
        return f'http://127.0.0.1:{self.api_port}'

    @property
    def web(self):
        return f'http://localhost:{self.web_port}'

    def env(self):
        e = dict(os.environ)
        e.update({
            'DEBUG': 'True',
            'DATABASE_URL': f'postgres://smoke@127.0.0.1:{self.pg_port}/smoke',
            'EMAIL_BACKEND': 'django.core.mail.backends.console.EmailBackend',
            'CELERY_TASK_ALWAYS_EAGER': '1',
            'CELERY_BROKER_URL': 'memory://',
            'CELERY_RESULT_BACKEND': 'cache+memory://',
            'CORS_ALLOWED_ORIGINS': self.web,
            'ALLOWED_HOSTS': '*',
            'API_LOGIN_RATE': '1000/min',
            'API_LOGIN_IP_RATE': '10000/hour',
        })
        return e

    def start_postgres(self):
        b = pg_bin()
        self.pg_dir = self.tmp / 'pg'
        subprocess.run([str(b / 'initdb'), '-D', str(self.pg_dir), '-U', 'smoke', '--auth=trust', '-E', 'UTF8'],
                       check=True, stdout=subprocess.DEVNULL)
        opts = f'-p {self.pg_port} -c listen_addresses=127.0.0.1 -c unix_socket_directories={self.tmp}'
        subprocess.run([str(b / 'pg_ctl'), '-D', str(self.pg_dir), '-o', opts, '-l', str(self.tmp / 'pg.log'),
                        '-w', 'start'], check=True, stdout=subprocess.DEVNULL)
        subprocess.run([str(b / 'createdb'), '-h', '127.0.0.1', '-p', str(self.pg_port), '-U', 'smoke', 'smoke'],
                       check=True)
        self._pg_ctl = b / 'pg_ctl'

    def manage(self, *args, stdin=None):
        return subprocess.run([str(PY), 'manage.py', *args], cwd=BACKEND, env=self.env(), input=stdin,
                              text=True, check=True, capture_output=True)

    def prepare_data(self):
        self.manage('migrate', '--noinput')
        self.manage('seed_dev_users')
        code = (
            "from django.contrib.auth.models import Group\n"
            "from accounts.models import User\n"
            "base = User.objects.get(email='staff@demo.com')\n"
            "for email, group in (('finance@demo.com','Finance'),('hr@demo.com','HR')):\n"
            "    u, _ = User.objects.get_or_create(email=email, defaults={'role':'STAFF','school':base.school})\n"
            "    u.role='STAFF'; u.school=base.school; u.first_name='Demo'; u.last_name=group\n"
            "    u.is_active=True; u.must_change_password=False; u.set_password(%r); u.save()\n"
            "    u.groups.set([Group.objects.get_or_create(name=group)[0]])\n"
        ) % PASSWORD
        self.manage('shell', stdin=code)

    def spawn(self, name, cmd, cwd, env, ready_url):
        log = open(self.tmp / f'{name}.log', 'w')
        p = subprocess.Popen(cmd, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        self.procs.append(p)
        wait_http(ready_url, name=name)

    def start_servers(self):
        self.spawn('django', [str(PY), 'manage.py', 'runserver', f'127.0.0.1:{self.api_port}', '--noreload'],
                   BACKEND, self.env(), f'{self.api}/api/')
        fe = dict(os.environ, VITE_API_URL=self.api)
        self.spawn('vite', ['npm', 'run', 'dev', '--', '--port', str(self.web_port), '--strictPort',
                            '--host', 'localhost'], FRONTEND, fe, self.web)

    def close(self):
        for p in reversed(self.procs):
            try:
                os.killpg(p.pid, signal.SIGTERM)
            except Exception:
                pass
        if self.pg_dir:
            subprocess.run([str(self._pg_ctl), '-D', str(self.pg_dir), '-m', 'immediate', 'stop'],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        shutil.rmtree(self.tmp, ignore_errors=True)


# ----------------------------------------------------------------------------- in-page probes
LAYOUT_JS = r"""
() => {
  const vw = document.documentElement.clientWidth, vh = window.innerHeight;
  const out = {hscroll: null, clipped: [], overlaps: [], truncated: []};
  const de = document.documentElement;
  if (de.scrollWidth > vw + 1) out.hscroll = {scrollWidth: de.scrollWidth, viewport: vw};
  const sel = (el) => {
    let s = el.tagName.toLowerCase();
    if (el.id) s += '#' + el.id;
    const c = (el.getAttribute('class') || '').trim().split(/\s+/).filter(Boolean).slice(0, 3).join('.');
    if (c) s += '.' + c;
    const t = (el.innerText || el.getAttribute('aria-label') || el.getAttribute('placeholder') || '').trim().replace(/\s+/g, ' ').slice(0, 30);
    return t ? `${s} "${t}"` : s;
  };
  const visible = (el) => {
    const r = el.getBoundingClientRect();
    if (r.width < 2 || r.height < 2) return false;
    const cs = getComputedStyle(el);
    return cs.visibility !== 'hidden' && cs.display !== 'none' && cs.opacity !== '0';
  };
  const inScrollX = (el) => {  // inside an intentional horizontal scroller (tables, tab strips)
    for (let p = el.parentElement; p && p !== document.body; p = p.parentElement) {
      const ox = getComputedStyle(p).overflowX;
      if ((ox === 'auto' || ox === 'scroll') && p.scrollWidth > p.clientWidth) return true;
    }
    return false;
  };
  const inFixedOffscreen = (el) => {  // closed drawers are parked off-canvas on purpose
    for (let p = el; p && p !== document.body; p = p.parentElement) {
      const cs = getComputedStyle(p);
      if (cs.position === 'fixed' && (p.getBoundingClientRect().right <= 0 || p.getBoundingClientRect().left >= vw)) return true;
      if (p.getAttribute('aria-hidden') === 'true' || p.hasAttribute('inert')) return true;
    }
    return false;
  };
  const all = [...document.body.querySelectorAll('*')].filter(visible);
  for (const el of all) {
    if (['SCRIPT', 'STYLE', 'SVG', 'PATH', 'HTML', 'BODY'].includes(el.tagName.toUpperCase())) continue;
    const r = el.getBoundingClientRect();
    if (inFixedOffscreen(el)) continue;
    if ((r.right > vw + 2 || r.left < -2) && !inScrollX(el) && out.clipped.length < 15)
      out.clipped.push({el: sel(el), left: Math.round(r.left), right: Math.round(r.right), viewport: vw});
    // text that is cut off by its own box (overflow hidden, no ellipsis wrap)
    const cs = getComputedStyle(el);
    if (el.children.length === 0 && el.innerText && el.innerText.trim() && cs.overflowX === 'hidden'
        && el.scrollWidth > el.clientWidth + 2 && cs.textOverflow !== 'ellipsis' && out.truncated.length < 10)
      out.truncated.push({el: sel(el), scrollWidth: el.scrollWidth, clientWidth: el.clientWidth});
  }
  // overlap: interactive controls whose boxes intersect (and are not nested in each other)
  const ctl = [...document.querySelectorAll('a[href],button,input:not([type=hidden]),select,textarea,[role=button]')]
    .filter(visible).filter((e) => !inFixedOffscreen(e));
  const seen = new Set();
  for (let i = 0; i < ctl.length && out.overlaps.length < 15; i++) {
    const a = ctl[i], ra = a.getBoundingClientRect();
    for (let j = i + 1; j < ctl.length; j++) {
      const b = ctl[j];
      if (a.contains(b) || b.contains(a)) continue;
      const rb = b.getBoundingClientRect();
      const w = Math.min(ra.right, rb.right) - Math.max(ra.left, rb.left);
      const h = Math.min(ra.bottom, rb.bottom) - Math.max(ra.top, rb.top);
      if (w > 4 && h > 4 && (w * h) > 0.25 * Math.min(ra.width * ra.height, rb.width * rb.height)) {
        // an element drawn on top (modal/header) is not a bug if the lower one is covered by design: report anyway, reviewer decides
        const key = sel(a) + '|' + sel(b);
        if (!seen.has(key)) { seen.add(key); out.overlaps.push({a: sel(a), b: sel(b), w: Math.round(w), h: Math.round(h)}); }
      }
    }
  }
  return out;
}
"""

NAV_JS = r"""
async () => {
  // Group toggles close over stale state (several clicks in one tick keep only the last), so open ONE group at a
  // time, harvest its links, and move on. Links of already-open groups are harvested too.
  const sel = 'button[aria-controls^="nav-"]';
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const visibleBtn = (b) => b.getBoundingClientRect().width > 0;
  const first = [...document.querySelectorAll(sel)].find(visibleBtn) || document.querySelector(sel);
  const root = (first && (first.closest('aside') || first.closest('nav') || first.parentElement.parentElement)) || document.body;
  const out = new Map();
  const harvest = () => {
    for (const a of root.querySelectorAll('a[href]')) {
      const href = a.getAttribute('href');
      if (href && href.startsWith('/') && !out.has(href))
        out.set(href, (a.innerText || a.getAttribute('title') || '').trim().replace(/\s+/g, ' '));
    }
  };
  harvest();
  const titles = [...root.querySelectorAll(sel)].map((b) => b.getAttribute('aria-controls'));
  for (const id of titles) {
    const b = root.querySelector(`button[aria-controls="${id}"]`);
    if (!b) continue;
    if (b.getAttribute('aria-expanded') === 'false') { b.click(); await sleep(200); }
    harvest();
    const b2 = root.querySelector(`button[aria-controls="${id}"]`);
    if (b2 && b2.getAttribute('aria-expanded') === 'true') { b2.click(); await sleep(150); }  // close again
  }
  return [...out].map(([href, label]) => ({href, label}));
}
"""


# ----------------------------------------------------------------------------- browser run
def slug(s):
    return ''.join(c if c.isalnum() else '-' for c in s).strip('-') or 'root'


def login_state(browser, stack, email):
    """Fresh login -> storage_state. Done per viewport: a state captured once goes stale when the access token
    expires mid-run and the rotated/blacklisted refresh token redirects every later page to /login."""
    ctx = browser.new_context(viewport=VIEWPORTS['desktop'])
    ctx.add_init_script("localStorage.setItem('terms_accepted','true')")
    page = ctx.new_page()
    try:
        page.goto(f'{stack.web}/login', wait_until='networkidle')
        page.locator('input[type=text]').first.fill(email)
        page.locator('input[type=password]').first.fill(PASSWORD)
        page.locator('button[type=submit]').click()
        page.wait_for_url(lambda u: '/login' not in u, timeout=20000)
        page.wait_for_load_state('networkidle')
        return ctx.storage_state()
    except Exception:
        return None
    finally:
        ctx.close()


def run_browser(stack, roles, viewports, shots_dir, headed, only=()):
    from playwright.sync_api import sync_playwright

    results, notes = [], []
    api_origin = stack.api
    with sync_playwright() as pw:
        browser = pw.chromium.launch(headless=not headed)
        for role in roles:
            email, _ = PERSONAS[role]
            # ---- login once (desktop) and keep storage state for the other viewports
            ctx = browser.new_context(viewport=VIEWPORTS['desktop'])
            # terms & privacy consent gates the login form (the checkbox unmounts once ticked)
            ctx.add_init_script("localStorage.setItem('terms_accepted','true')")
            page = ctx.new_page()
            page.goto(f'{stack.web}/login', wait_until='networkidle')
            page.locator('input[type=text]').first.fill(email)
            page.locator('input[type=password]').first.fill(PASSWORD)
            page.locator('button[type=submit]').click()
            try:
                page.wait_for_url(lambda u: '/login' not in u, timeout=20000)
                page.wait_for_load_state('networkidle')
            except Exception:
                notes.append(f'**{role}**: login did not leave /login (url={page.url}); role skipped.')
                shot = shots_dir / f'{role}-login-failed.png'
                page.screenshot(path=str(shot))
                ctx.close()
                continue
            home = page.url.replace(stack.web, '') or '/'
            try:  # the sidebar mounts after the profile loads
                page.wait_for_selector('nav button[aria-controls^="nav-"]', timeout=15000)
            except Exception:
                notes.append(f'**{role}**: no collapsible sidebar groups appeared within 15s.')
            links = page.evaluate(NAV_JS)
            seen, pages = set(), []
            links = [l for l in links if not only or l['href'] in only]
            for l in ([{'href': home, 'label': 'Home'}] if not only else []) + links:
                if l['href'] not in seen:
                    seen.add(l['href'])
                    pages.append(l)
            ctx.close()
            notes.append(f'**{role}** ({email}): landed on `{home}`, {len(pages)} sidebar pages discovered.')

            for vp_name in viewports:
                state = login_state(browser, stack, email)
                if state is None:
                    notes.append(f'**{role}** / {vp_name}: re-login failed; viewport skipped.')
                    continue
                ctx = browser.new_context(viewport=VIEWPORTS[vp_name], storage_state=state)
                # some pages call fetch('/api/...') on their own origin; production nginx forwards that to Django,
                # Vite dev does not (empty 500). Mirror nginx here so those pages are not reported as broken.
                ctx.route(f'{stack.web}/api/**',
                          lambda route: route.continue_(url=route.request.url.replace(stack.web, stack.api, 1)))
                for pg in pages:
                    page = ctx.new_page()
                    rec = {'role': role, 'viewport': vp_name, 'page': pg['href'], 'label': pg['label'],
                           'page_errors': [], 'console_errors': [], 'failed_api': [], 'hscroll': None,
                           'clipped': [], 'overlaps': [], 'truncated': [], 'shot': '', 'nav_error': ''}
                    page.on('pageerror', lambda e, r=rec: r['page_errors'].append(str(e)[:300]))
                    page.on('console', lambda m, r=rec: r['console_errors'].append(m.text[:300])
                            if m.type == 'error' else None)
                    page.on('response', lambda resp, r=rec: r['failed_api'].append(
                        f'{resp.status} {resp.request.method} {resp.url.replace(api_origin, "")[:120]}')
                        if resp.status >= 400 and resp.url.startswith(api_origin) else None)
                    try:
                        page.goto(f'{stack.web}{pg["href"]}', wait_until='networkidle', timeout=30000)
                        page.wait_for_timeout(600)
                        if '/login' in page.url and '/login' not in pg['href']:
                            rec['nav_error'] = f'redirected to {page.url.replace(stack.web, "")}'
                        lay = page.evaluate(LAYOUT_JS)
                        rec.update(hscroll=lay['hscroll'], clipped=lay['clipped'], overlaps=lay['overlaps'],
                                   truncated=lay['truncated'])
                    except Exception as e:  # navigation/timeouts are findings too
                        rec['nav_error'] = f'{type(e).__name__}: {str(e)[:200]}'
                    fname = f'{role}-{vp_name}-{slug(pg["href"])}.png'
                    try:
                        page.screenshot(path=str(shots_dir / fname), full_page=True)
                        rec['shot'] = fname
                    except Exception as e:
                        rec['nav_error'] += f' (screenshot failed: {e})'
                    results.append(rec)
                    print(f'[smoke] {role:8} {vp_name:8} {pg["href"]:40} '
                          f'pe={len(rec["page_errors"])} ce={len(rec["console_errors"])} '
                          f'api={len(rec["failed_api"])} h={"Y" if rec["hscroll"] else "-"} '
                          f'clip={len(rec["clipped"])} ovl={len(rec["overlaps"])}')
                    page.close()
                ctx.close()
        browser.close()
    return results, notes


# ----------------------------------------------------------------------------- report
def md(s):
    return str(s).replace('|', '\\|').replace('\n', ' ')


def write_report(results, notes, date, out_md, shots_rel, args):
    def bad(r):
        return bool(r['page_errors'] or r['console_errors'] or r['failed_api'] or r['hscroll']
                    or r['clipped'] or r['overlaps'] or r['nav_error'])

    flagged = [r for r in results if bad(r)]
    L = [f'# UI smoke report {date}', '',
         f'Generated by `scripts/ui_smoke.py` against a throwaway Postgres, seeded Demo School, console mail. '
         f'Findings only, nothing was fixed. Screenshots: `{shots_rel}/`.', '',
         f'- Roles: {", ".join(args.roles)}; viewports: ' +
         ', '.join(f'{v} {VIEWPORTS[v]["width"]}x{VIEWPORTS[v]["height"]}' for v in args.viewports),
         f'- Page visits: {len(results)}; with at least one finding: {len(flagged)}', '']
    L += [f'- {n}' for n in notes] + ['']

    L += ['## Totals by role and viewport', '',
          '| Role | Viewport | Pages | Page errors | Console errors | Failed API | H-scroll | Overlap/clipped | Nav errors |',
          '|---|---|---|---|---|---|---|---|---|']
    for role in args.roles:
        for vp in args.viewports:
            rs = [r for r in results if r['role'] == role and r['viewport'] == vp]
            if not rs:
                continue
            L.append(f'| {role} | {vp} | {len(rs)} | {sum(bool(r["page_errors"]) for r in rs)} | '
                     f'{sum(bool(r["console_errors"]) for r in rs)} | {sum(bool(r["failed_api"]) for r in rs)} | '
                     f'{sum(bool(r["hscroll"]) for r in rs)} | '
                     f'{sum(bool(r["clipped"] or r["overlaps"]) for r in rs)} | {sum(bool(r["nav_error"]) for r in rs)} |')

    L += ['', '## Every page visit', '',
          '| Role | Viewport | Page | PgErr | Console | API 4xx/5xx | H-scroll | Clipped | Overlap | Shot |',
          '|---|---|---|---|---|---|---|---|---|---|']
    for r in results:
        shot = f'[png]({shots_rel}/{r["shot"]})' if r['shot'] else ''
        L.append(f'| {r["role"]} | {r["viewport"]} | `{md(r["page"])}` | {len(r["page_errors"])} | '
                 f'{len(r["console_errors"])} | {len(r["failed_api"])} | {"YES" if r["hscroll"] else "-"} | '
                 f'{len(r["clipped"])} | {len(r["overlaps"])} | {shot} |')

    L += ['', '## Findings detail (pages with at least one finding)', '']
    if not flagged:
        L.append('None.')
    for r in flagged:
        L.append(f'### {r["role"]} / {r["viewport"]} / `{r["page"]}` ({md(r["label"])})')
        if r['nav_error']:
            L.append(f'- Navigation: {md(r["nav_error"])}')
        for k, title in (('page_errors', 'Page error'), ('console_errors', 'Console error'),
                         ('failed_api', 'Failed API call')):
            for x in dict.fromkeys(r[k]):
                L.append(f'- {title}: `{md(x)}`')
        if r['hscroll']:
            L.append(f'- Horizontal scroll: document {r["hscroll"]["scrollWidth"]}px wide in {r["hscroll"]["viewport"]}px viewport')
        for c in r['clipped']:
            L.append(f'- Clipped: `{md(c["el"])}` spans {c["left"]}..{c["right"]} (viewport {c["viewport"]})')
        for o in r['overlaps']:
            L.append(f'- Overlap: `{md(o["a"])}` over `{md(o["b"])}` ({o["w"]}x{o["h"]}px)')
        for t in r['truncated']:
            L.append(f'- Text cut off: `{md(t["el"])}` content {t["scrollWidth"]}px in {t["clientWidth"]}px box')
        if r['shot']:
            L.append(f'- Screenshot: [{r["shot"]}]({shots_rel}/{r["shot"]})')
        L.append('')

    # same console/API message repeating across pages is usually one root cause
    from collections import Counter
    cnt = Counter()
    for r in results:
        for x in set(r['console_errors'] + r['failed_api'] + r['page_errors']):
            cnt[x[:140]] += 1
    L += ['## Most repeated messages (likely shared root causes)', '']
    L += [f'- {n}x `{md(m)}`' for m, n in cnt.most_common(10)] or ['None.']
    out_md.write_text('\n'.join(L) + '\n')


# ----------------------------------------------------------------------------- main
def main():
    ensure_venv()
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--roles', default=','.join(PERSONAS))
    ap.add_argument('--viewports', default=','.join(VIEWPORTS))
    ap.add_argument('--date', default=dt.date.today().isoformat())
    ap.add_argument('--headed', action='store_true')
    ap.add_argument('--backend-dir', help='baseline: exported backend tree to run instead of ./backend')
    ap.add_argument('--frontend-dir', help='baseline: exported frontend/codingclubskenya tree (needs node_modules)')
    ap.add_argument('--only', default='', help='comma-separated page paths to visit (e.g. /schemes-of-work)')
    ap.add_argument('--tag', default='', help='suffix for report/screenshot names, e.g. baseline')
    args = ap.parse_args()
    args.roles = [r for r in args.roles.split(',') if r]
    args.viewports = [v for v in args.viewports.split(',') if v]
    for r in args.roles:
        if r not in PERSONAS:
            sys.exit(f'unknown role {r}; choose from {list(PERSONAS)}')
    for v in args.viewports:
        if v not in VIEWPORTS:
            sys.exit(f'unknown viewport {v}; choose from {list(VIEWPORTS)}')

    global BACKEND, FRONTEND
    if args.backend_dir:
        BACKEND = Path(args.backend_dir).resolve()
    if args.frontend_dir:
        FRONTEND = Path(args.frontend_dir).resolve()
    name = f'ui-smoke-{args.date}' + (f'-{args.tag}' if args.tag else '')
    reports = ROOT / 'docs' / 'specs' / 'reports'
    shots_dir = reports / name
    out_md = reports / f'{name}.md'
    if shots_dir.exists():
        shutil.rmtree(shots_dir)  # only our own dated output dir, re-runs replace it
    shots_dir.mkdir(parents=True)

    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))  # let `finally` tear the stack down
    stack = Stack()
    try:
        print(f'[smoke] postgres :{stack.pg_port}  api :{stack.api_port}  web :{stack.web_port}')
        stack.start_postgres()
        stack.prepare_data()
        stack.start_servers()
        results, notes = run_browser(stack, args.roles, args.viewports, shots_dir, args.headed, tuple(x for x in args.only.split(',') if x))
        write_report(results, notes, args.date, out_md, name, args)
        print(f'[smoke] report: {out_md.relative_to(ROOT)}')
    finally:
        stack.close()


if __name__ == '__main__':
    main()
