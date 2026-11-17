# Release 1 rehearsal, 2026-11-15

Server: only read-only counts over ssh. Nothing on contabo was changed. The rehearsal ran on a private local PG 16.15 (initdb in scratchpad, port 5440, stopped afterwards). Worktree of `backend` `fix/private-media` @ 2b6a476.

## 1. Private media (STOPPED, awaiting your approval)

**Counts in prod `epk/media`:** all nine private prefixes (recruitment, assessment_evidence, reference_documents, scheme_uploads, course_attachments, course_materials, submissions, form_submissions, disputes) are **absent: 0 files**. The only top-level dir is `shop/`. So nothing private has been uploaded yet, and nothing breaks when we block these paths now. The exposure is only that anything uploaded later would be public.

**Where the change goes (differs from your instruction):** neither `/etc/nginx/nginx.conf` nor `personalweb/nginx.conf` contains the api/erp/learningpack servers. They only `include /etc/nginx/sites-enabled/*`. The live vhosts are symlinks to `/etc/nginx/sites-available/codingclubskenya-{api,main,learningpack}.conf`. Only **api** has a `/media/` alias on disk. erp and learningpack have no `/media/`, so the 404 block there is defence in depth and a no-op today. Editing the two `nginx.conf` files would not implement the fix, so I propose leaving them alone.

`personalweb/nginx.conf` (the file `deploy-auto.sh` copies over `/etc/nginx/nginx.conf`) lacks `limit_req_zone … zone=login` that the live file has, and carries a legacy server block. The timer is disabled, but I recommend deleting the `cp … /etc/nginx/nginx.conf` line from `deploy-auto.sh` before it is ever re-enabled.

Proposed diffs (made from the captured live files): `docs/prod-capture/nginx-proposal/codingclubskenya-{api,main,learningpack}.diff`.

api vhost, inserted before `# Django Media Files`:
```nginx
    location ~* ^/media/(recruitment|assessment_evidence|reference_documents|scheme_uploads|course_attachments|course_materials|submissions|form_submissions|disputes)/ {
        return 404;
    }

    location /protected-media/ {
        internal;
        alias /home/devops/home/personal/personalweb/epk/media/;
        add_header X-Content-Type-Options nosniff always;
    }
```
erp and learningpack vhosts, before `location / {`: only the `return 404` regex block.
The regex location takes precedence over the plain `/media/` prefix, so private paths get 404 while `/media/shop/...` keeps working.

Commands (run on contabo; sudo needs your password):
```bash
cd /etc/nginx/sites-available && TS=$(date +%Y%m%d-%H%M%S)
for f in api main learningpack; do sudo cp -a codingclubskenya-$f.conf codingclubskenya-$f.conf.bak-$TS; done
# copy the three .diff files to the server first (scp docs/prod-capture/nginx-proposal/*.diff contabo:/tmp/)
for f in api main learningpack; do sudo patch --dry-run codingclubskenya-$f.conf < /tmp/codingclubskenya-$f.diff; done
for f in api main learningpack; do sudo patch codingclubskenya-$f.conf < /tmp/codingclubskenya-$f.diff; done
sudo nginx -t && sudo systemctl reload nginx
# verify
curl -s -o /dev/null -w '%{http_code}\n' https://api.codingclubskenya.com/media/recruitment/x     # expect 404
curl -s -o /dev/null -w '%{http_code}\n' https://api.codingclubskenya.com/protected-media/x       # expect 404 (internal only)
# rollback: sudo cp -a codingclubskenya-<f>.conf.bak-$TS codingclubskenya-<f>.conf && sudo nginx -t && sudo systemctl reload nginx
```
Later, with the backend release: set `PRIVATE_MEDIA_ACCEL_PREFIX=/protected-media` in the prod `.env` (matches the internal location). `FRONTEND_URL` is also still unset.

## 2. Distributor, done

- Commit `cb5de1c` on `fix/verified-payments`; `release-1` fast-forwarded to the same commit. Changes: `output: "export"` + `trailingSlash: true` in `next.config.ts`, and `useSearchParams` in `app/discovery/page.tsx` (identical to prod's working-tree patch).
- `next build` under **Node 20.20.2** passes and produces `out/`. A local static server returned 200 for `/shop/`, `/bookshop/`, `/cart/`, `/discovery/`, `/shop/placeholder/`.
- **Caveat:** `/shop/[id]` is pre-rendered only for `/shop/placeholder`. A real product URL like `/shop/123/` returns **404** from a static host (prod nginx's fallback would serve the home `index.html`). Product links (`/shop/${product.id}` in discovery and the dashboard) will not work on prod as it stands, and this was already true of prod's build. Needs a decision: an nginx rewrite of `/shop/<id>/` to the placeholder page (if the page reads the id client-side), or `generateStaticParams` from the API at build time.
- `disributor-next.service` (`next start`) cannot work with export. Disable it and let nginx serve `out/`.

## 3. Backend schema, passed

On `fix/private-media` with `core.settings_production` plus local env (throwaway secret, rehearsal DB):
- `manage.py spectacular --file schema.yml`: **exit 0**, 863 KB file (1 "Errors" summary line: 203 non-fatal schema warnings, 38 unique; 17 warning lines).
- `GET /api/schema/` over HTTPS: **200** (`application/vnd.oai.openapi`, 863 KB). `?format=json`: 200. Plain HTTP returns 301 from the SSL redirect, as expected.
- A worktree has no `logs/` dir, so the first run failed with `Unable to configure handler 'file'`. Make sure `logs/` exists on prod after any fresh checkout.

## 4. Rehearsal on a restore of prod

- Restore: `school_mgmt-20261115-131813.dump` restored cleanly into PG 16.15 (136 migration rows, 5 users, 1 school: matches prod).
- 30 pending migrations on `fix/private-media` (list: `docs/prod-capture/rehearsal-pending-migrations.txt`): accounts ×7 (incl. StaffProfile, populate StudentProfile, finance/HR/health groups), academics ×4, website ×2, sites ×2, shop ×2, and one each in tenants, storefront, recruitment, procurement, payroll, gradebook, fees, distributor, curriculum, courses, carts, booklists, assessment.
- **BLOCKER found:** a plain `migrate` fails immediately:
  `InconsistentMigrationHistory: Migration socialaccount.0001_initial is applied before its dependency sites.0001_initial`.
  Prod migrated allauth socialaccount while `django.contrib.sites` was not installed (no `django_site` table exists, and `socialaccount_socialapp_sites` is absent). Our settings install `sites`. Neither `migrate` nor `MigrationExecutor` can proceed as is.
- **Workaround that worked on the rehearsal copy:** apply the `sites` SQL (`manage.py sqlmigrate sites 0001` and `0002`, creates `django_site` + unique/index) and insert the two matching rows in `django_migrations`, **before** `migrate`. Then `migrate --noinput` applied the remaining 28 migrations with **no errors in 33 s**. It should be scripted and rehearsed again as a release step. A real production run needs the same fix, after a fresh backup.
- After migrate: 0 pending, `makemigrations --check` reports no changes, users 5, groups Finance/HR/Health, 1 Site row.
- `check --deploy`: exit 0, 422 issues, all warnings: 421 drf-spectacular (no `schema = None` hacks) and `security.W009` (only because the rehearsal `SECRET_KEY` is a throwaway; prod's is fine per the earlier check).
- Not exercised: `check_duplicates` / `check_stream_years` (Stream is empty on prod and has no `academic_year` field yet), and the test suite.

## Next steps needing you
1. Approve (or change) the nginx diffs and run the commands above (sudo).
2. Decide the `/shop/[id]` static-export approach.
3. Decide how to ship the `sites` fix (script in the deploy notes vs. a squashed/fake migration).
4. Release order: backup, `sites` fix, `migrate`, set `PRIVATE_MEDIA_ACCEL_PREFIX` and `FRONTEND_URL`, restart gunicorn, deploy `out/`.
