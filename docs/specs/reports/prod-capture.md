# Production capture (read-only on server), 2026-11-15

Server: only new files were written under `~/backups` on `contabo`. Nothing was changed, restarted or pulled.

## 1. Backups (verified)

| Artifact | Server | Laptop | Check |
|---|---|---|---|
| DB dump (custom format, pg_dump 16.15) | `~/backups/school_mgmt-20261115-131813.dump` | `~/prod-backups/` | 757,219 bytes, **1735 TOC entries** (`pg_restore --list`), sha256 matches both ends (`16bd0362…cad39`) |
| media tarball | `~/backups/media-20261115-131813.tgz` | `~/prod-backups/` | 26,093,075 bytes, 488 entries, sha256 matches (`bf4ab11f…87d6`) |

The dump was taken with credentials read from `.env` inside the ssh session, never printed. The dump and media stay outside the repo.
Restore has not been test-run (no scratch DB was used). Do that before relying on it.

## 2. Prod uncommitted code

Saved in `docs/prod-capture/`. Patches use `git diff HEAD`, so staged changes are included. No `.env` files were included, and the untracked tarballs exclude venv, node_modules, .next, out, dist, media and staticfiles.

| Repo (prod branch @ base) | Patch | Untracked |
|---|---|---|
| epk (qa/hardening-fixes @ 7f2d760) | `epk-uncommitted.patch` (1129 lines, 33 files) | `epk-untracked.tgz`: `core/schema_generator.py`, `deploy/redis/redis.conf` |
| distributor (main @ cd52e8e) | `distributor-uncommitted.patch` (2 files; `next.config.ts` is staged) | `distributor-untracked.tgz`: `logs/next.log`, `next.pid`, `start_next.sh` |
| frontend (development @ 19e3cd3) | empty (no tracked changes) | `frontend-untracked.tgz`: 103 files, all build output and old backup dirs (`dist-backup-20260922-…`, `learningpack-backup-20260922-…`, built `index.html`/`assets`/`favicon.svg`) |

## 3. Comparison with our branches

Method: throwaway worktrees of `backend` `fix/private-media` and `feat/school-data-management`, `git apply --check` (forward and reverse) per file. Prod's base 7f2d760 is an ancestor of `fix/private-media`, but our branch has drifted by 215 files, so most hunks cannot be applied textually.

### epk (backend): all **prod-only**, none already in ours
The patch is a **drf-spectacular workaround**, not feature work:
- 125 added `schema = None` lines across 33 `views.py`/`urls.py` files (Spectacular crash/warning suppression). Zero `schema = None` exist on either of our branches.
- `core/settings.py`: adds `DISABLE_ERRORS_AND_WARNINGS` and `DEFAULT_GENERATOR_CLASS = core.schema_generator.TolerantSchemaGenerator` (prod-only untracked file).
- `core/settings_production.py`: a full prod-local `REST_FRAMEWORK` block (JWT auth, IsAuthenticated, throttle `anon 100/day`, `user 1000/hour`) and `SPECTACULAR_SETTINGS`. Ours instead does `from .settings import *` and extends `REST_FRAMEWORK` (`NUM_PROXIES`), with `user` rate `3000/hour` (env `API_USER_RATE`), so **prod's effective throttles differ from ours** (1000/hour vs 3000/hour).
- Classification (identical for both branches):
  - **Prod-only, applies cleanly (4 files):** `audit/urls.py`, `complaints/views.py`, `events/views.py`, `shop/views.py`.
  - **Prod-only, textual conflict from drift (29 files):** all other files. They conflict only because the surrounding code changed. In intent they are the same `schema = None` insertions.
  - **Already in ours:** none.
- Impact: dropping this patch means Spectacular schema generation runs against real views on prod. `check --deploy` showed only warnings, so it was fine, but `/api/schema` and docs may emit errors. `SERVE_INCLUDE_SCHEMA` is False in prod's block anyway. Safe to discard once we confirm no prod route depends on it.
- `deploy/redis/redis.conf` is prod-only. Not in our repo, so review before discarding.

### distributor: **prod-only**, applies cleanly to both `HEAD` and `fix/verified-payments`
- `next.config.ts`: adds `output: "export"` and `trailingSlash: true`. **Ours has no static export**, and nginx serves `disributor/out`. A plain `next build` from our branch would not produce `out/`, so the learningpack site would break (or serve stale `out/`).
- `app/discovery/page.tsx`: swaps Next 15 `use(searchParams)` for `useSearchParams()` (required for static export). Ours still has the `use(...)` form.
- `start_next.sh`/`next.pid`/`logs/`: runtime junk. It explains the crash-looping `disributor-next` (`next start` is incompatible with `output: "export"`).
- Recommendation: land both changes in the distributor repo, and remove or fix `disributor-next.service`.

### frontend: nothing to merge
No tracked changes. The untracked content is build output and stale backups, **prod-only and not source**.

## 4. nginx

Copied to `docs/prod-capture/nginx.conf` (prod's `personalweb/nginx.conf`), plus the live vhosts in `docs/prod-capture/sites-enabled/` (api, erp/main, learningpack).

- **No private-media blocks anywhere on prod.** None of the files contains `internal`, `protected-media`, or a `404` for the private prefixes (recruitment, assessment_evidence, reference_documents, scheme_uploads, course_attachments, course_materials, submissions, form_submissions, disputes).
  - api vhost (`api.codingclubskenya.com`): `location /media/` is a plain `alias …/epk/media/`, so **private uploads are publicly fetchable by URL today**.
  - erp vhost (`codingclubskenya-main.conf`): no `/media/` and no private blocks.
  - learningpack vhost: static `root …/disributor/out`, no private blocks.
  - prod's `nginx.conf`: only a legacy `codingclubskenya.com` server with a plain `/media/` alias.
- Ours: root `deploy/nginx/school_management` has the 404 + `/protected-media/` internal location. `backend`'s `fix/private-media` adds `deploy/nginx/learningpack` (commit 2b6a476). The paths differ (`/home/personal/...backend/media` vs prod `/home/devops/.../epk/media`).
- `/etc/nginx/nginx.conf` **differs** from `personalweb/nginx.conf`. `deploy-auto.sh` overwrites the live file with the repo copy on every run, so prod's live config can be silently replaced.
- Security note: the media exposure exists now, independent of our release. Treat it as a priority, since it needs the nginx change plus `PRIVATE_MEDIA_ACCEL_PREFIX` (still unset on prod).

## Open decisions for you
1. Discard prod's `schema = None` patch, or keep it as a stash for rollback? (Saved locally either way.)
2. Land `output: "export"` + discovery page change in the distributor repo before anyone triggers a build.
3. Next step needs approval: nginx edits for private media (confirm, then `nginx -t`), and stopping `auto-deploy.timer`.
4. Test-restore `school_mgmt-20261115-131813.dump` into a scratch DB locally to confirm it is usable.
