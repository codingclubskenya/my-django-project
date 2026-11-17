# Release 1 deploy prep, 2026-11-15

Nothing was run on the server except the checks below. The nginx edit is pending your sudo (see section 1).

## 1. nginx (checks done, apply pending)

- Live api vhost line 14 is `location /media/ {`: a plain prefix, **not `^~`**. So the regex `~* ^/media/(private prefixes)/ { return 404; }` takes precedence, and no proposal change was needed.
- **X-Accel prefix:** `core/private_files.py` builds `X-Accel-Redirect` as `<PRIVATE_MEDIA_ACCEL_PREFIX without trailing slash>/<file name>`. Use `PRIVATE_MEDIA_ACCEL_PREFIX=/protected-media` (a trailing slash also works). It matches `location /protected-media/ { internal; alias …/epk/media/; }`.
- The three diffs are already copied to `contabo:/tmp/codingclubskenya-*.diff`. The backup, `--dry-run`, `patch` + `nginx -t`, and reload commands were handed to you as four separate `! ssh -t contabo …` steps. **Not run yet.** The verification curls (private path 404, `/protected-media/` 404, one real `/media/shop/<file>` 200) still need to be done after reload. I can run them once you confirm the reload (they need a real shop file name, which I'll pick from a count-only listing).
- Learningpack `/shop/<id>/` rewrite (**not applied**), file `docs/prod-capture/nginx-proposal/learningpack-shop-rewrite.snippet`, goes before `location / {` in `codingclubskenya-learningpack.conf`:
  ```nginx
  location ~ ^/shop/[^/]+/?$ {
      try_files $uri $uri/index.html /shop/placeholder/index.html;
  }
  ```
  `try_files` serves a pre-rendered product page first and falls back to the placeholder, so `/shop/` itself (no id) is untouched. Caveat: Next's client-side navigation also fetches `.txt` payloads under `/shop/<id>/…`. Those deeper paths don't match and 404, and Next then falls back to a full page load. Functionally fine, slightly slower.

## 2. Backend: `repair_sites_history` (done)

- `accounts/management/commands/repair_sites_history.py` (placed in `accounts` because `core` is not an installed app, so commands there are not discovered). Tests: `accounts/test_repair_sites_history.py`, 5 cases, all passing (consistent no-op; prod state repaired and idempotent; `--dry-run` changes nothing; table present but unrecorded only records; recorded-but-missing-table refuses with an error).
- Behaviour: table missing and no sites migrations recorded → creates `django_site` via the real sites migrations (not hand-written SQL) and records 0001/0002 in one transaction; table present but unrecorded → records only; both in place → no-op; inconsistent other states → `CommandError`, no changes.
- Commit `889b022` on `fix/private-media`, merged into `feat/school-data-management` (merge commit `209e535`).
- **Fresh rehearsal** (new restore of `school_mgmt-20261115-131813.dump` into local PG 16.15):
  1. plain `migrate`: fails with `InconsistentMigrationHistory`, as expected.
  2. `repair_sites_history --dry-run`: reports the plan, changes nothing.
  3. `repair_sites_history`: repaired. Second run: "nothing to do".
  4. `migrate --noinput`: 28 migrations applied, 0 tracebacks, 36 s. 0 pending after.
  5. `check --deploy`: exit 0; the only non-spectacular warning is `security.W009`, which comes from the throwaway rehearsal `SECRET_KEY`.

## 3. Distributor `/shop/[id]` (done, rewrite proposed above)

- Commit `7f13fc5` on `fix/verified-payments`; `release-1` moved to the same commit. `ProductDetailClient.tsx` now takes the id from `usePathname()` (the second URL segment). The build-time `params` id is only the fallback when the URL segment is `placeholder`, so the placeholder page serves any id once the nginx rewrite is in.
- `next build` under Node 20 passes. `/shop/[id]` pre-renders its (API-listed, up to 100) products or just `/shop/placeholder` if the API is unreachable at build time. The deploy script requires the placeholder page to exist.
- Not verified in a browser: the id-from-URL path needs a real run through nginx with the rewrite. Test it after you apply the snippet, with one product URL.

## 4. Deploy scripts (written, not run)

Committed in the backend repo as `ec2f9d9` on `feat/school-data-management`:

**`deploy/deploy-release.sh <ref>`** (run on the server as the app user):
1. Preflight: aborts if tracked files are modified in `epk` (prod currently has 35, so discard or save them first), `.env` is missing, or any of `SECRET_KEY, DB_*, PRIVATE_MEDIA_ACCEL_PREFIX, FRONTEND_URL` are absent (override with `ALLOW_MISSING_ENV=1`). `git fetch`, then resolves the ref (no pull).
2. Backup: `pg_dump -Fc` and a media tarball under `~/backups`. **Aborts if the dump is empty** or has ≤ 100 TOC entries, or the media archive is empty or unreadable. Credentials are read from `.env` without printing.
3. `git checkout --detach <ref>`, `pip install -r requirements.txt`, `mkdir -p logs`, `check --deploy --fail-level ERROR`.
4. `repair_sites_history`, `migrate --noinput`, `collectstatic --noinput`.
5. `sudo systemctl restart gunicorn`; then health check over the unix socket (`/api/health/`, 15 tries) with the proper `Host` and `X-Forwarded-Proto` headers, so the SSL redirect doesn't give a 301.
6. On any failure it prints the previous commit, the checkout command to return to, and the backup path. There is no automatic rollback, and migrations are not reversed.

**`deploy/deploy-static.sh distributor|frontend <ref>`:**
- Builds the ref in a fresh git worktree under `personalweb/releases/<site>-<ts>`, copying untracked `.env*` build config from the live checkout.
- Runs `npm ci` and `npm run build`, with a Node 20+ check (`NODE_BIN` override) and sanity checks (`/shop`, `/bookshop`, `/cart`, `/shop/placeholder` exist for the distributor).
- Swaps the live path with a symlink rename (`mv -T`), so it is atomic after the first run. The first run turns the real `out/` or `dist/` directory into `<live>.prev` with two renames in quick succession. Keeps 3 releases. A failed build leaves the live site untouched.
- The swap logic was exercised in a temp dir (real dir to symlink, then symlink to symlink). `bash -n` passes; **shellcheck is not installed**, so the scripts are unlinted. A full dry run needs a staging checkout, which I did not do.

**`deploy-auto.sh`:** no copy exists in our repos (it lives only in `personalweb/` on the server). I saved the server's version as `docs/prod-capture/deploy-auto.sh.orig` and the edited version, with the `sudo cp … /etc/nginx/nginx.conf` line removed, as `docs/prod-capture/deploy-auto.sh`. To apply on the server, copy it over the live file (your call, because the timer is disabled and it is outside the repos).

## Things to know
- `backend/deploy/deploy.sh` (older, in the repo) runs `DROP DATABASE IF EXISTS school_mgmt` and drops the DB user. It must never be run on prod. Consider deleting or guarding it. I did not touch it.
- Unrelated to our commits: the distributor, frontend and backend submodule pointers in the root repo are not bumped (you asked for that only on request).
- Still unset on prod: `PRIVATE_MEDIA_ACCEL_PREFIX` and `FRONTEND_URL`. `deploy-release.sh` will refuse to run until they are set.

## Remaining decisions / actions for you
1. Run the four nginx steps (backup, dry-run, patch + `nginx -t`, reload); tell me when done and I'll verify with curl.
2. Apply the learningpack rewrite snippet (after the above), then smoke-test one `/shop/<id>/` URL in a browser.
3. Set `PRIVATE_MEDIA_ACCEL_PREFIX=/protected-media` and `FRONTEND_URL` in the prod `.env`.
4. Decide whether to install the edited `deploy-auto.sh` on the server, and whether to remove `deploy.sh`.
