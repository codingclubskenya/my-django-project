# CI/CD plan (2026-11-20)

## Decisions and status (2026-11-20, later)
- Approved: code-only backend rollback under the rule **"migrations additive only; removals ship in a later release"**; the narrow NOPASSWD sudoers line for restarting gunicorn only; CI first, CD after CI is green and approved.
- **CI built** (workflow files committed and pushed): backend `e4ec5a1` (replaces the stale `backend-ci.yml`), frontend `b121f35`, distributor `67e7c2b` (on `feat/bookshop-rework`). Blocking: backend tests on `postgres:16` plus `check` and `makemigrations --check`, frontend `vite build`, distributor `next build`, ruff for syntax errors and undefined names only. Everything else (oxlint, eslint, wider ruff) is report-only.
- **Blocker: the first runs on all three repos failed in 2 s with "The job was not started because your account is locked due to a billing issue."** That is the `fattym` GitHub account (billing/spending limit); nothing in the workflows is at fault. Fix it in GitHub (Settings, Billing and plans), then re-run. Until then the same steps were run locally: fresh venv from `requirements.txt` (`check` and `makemigrations --check` clean), full suite 868 tests OK on Postgres 16, `vite build` OK.
- **All four repos are PUBLIC** (`gh repo view`: `fattym/epk`, `fattym/frontend-apk-web`, `fattym/disributor`, `codingclubskenya/my-django-project`), not private as assumed. Consequences: Actions minutes are free for public repos once billing is sorted; the deploy scripts, nginx configs and deploy logs in the root repo are world-readable; the Deploy workflow's `CI_READ_TOKEN` is not needed (public check runs are readable without a token). Please confirm the lock icon in GitHub; if you want them private, decide before CD is built.
- Still open: CD build and the one-off server steps (section 4) wait for CI to be green and your go.


Status: **discovery only.** Nothing has been built, nothing on the server was changed (read-only `ssh contabo` checks, listed in section 1). Build order: CI first; CD only after CI is green on all three repos.

## 1. Discovery

### Repos and existing workflows
| Repo | GitHub remote | `.github/workflows` | Notes |
|---|---|---|---|
| root `my-django-project` | `codingclubskenya/my-django-project` | none | superproject; holds docs, `scripts/ui_smoke.py`, pointers |
| `backend` | `fattym/epk` | `backend-ci.yml` (stale, see below) | Django 6; the repo root *is* the backend (no `backend/` subfolder) |
| `frontend` | `fattym/frontend-apk-web` | none | app is in `codingclubskenya/` (Vite, Node 20, `package-lock.json`, `oxlint`) |
| `distributor` | `fattym/disributor` (sic) | none | Next.js 16, `output: "export"` in production, Node >= 20.11, `package-lock.json` |

Three different owners/accounts and four repos: environment secrets do not cross repos, so the Deploy workflow lives in **one** repo (root) and the CI workflows live in their own repos.

### The existing `backend-ci.yml` would fail today (so it is replaced, not extended)
- Runs `python -m pytest`; the project's suite is `manage.py test` with `core.settings_test` (CLAUDE.md: never plain settings).
- `working-directory: backend` and `paths: backend/**` are wrong inside the backend repo (the root is already backend).
- Triggers on `main/master/develop` only; our branches are `feat/*`, `release/*`.
- Installs `requirements.txt` only but calls `ruff` (pinned in `requirements-dev.txt`).
- `ruff check .` reports **472 errors** and `ruff format --check .` says **464 files would be reformatted**. Both can never be a blocking gate today. `ruff check --select E9,F63,F7,F82` (syntax errors, undefined names) passes today and is the first blocking gate; plain `--select F` has 149 findings (125 auto-fixable) and becomes the second step after one cleanup commit.
- Starts a Redis service the tests do not use (`settings_test` uses locmem cache and eager Celery).

### Other facts that shape the plan
- Full backend suite on Postgres 16 (parallel 4): 860 tests, about 220 s on this laptop.
- `oxlint` (frontend) prints warnings only; `vite build` is the real check (about 20 s). Distributor: `next build` needs `NEXT_PUBLIC_API_URL`; `generateStaticParams` calls the API at build time but falls back to `placeholder` if it fails, so CI sets a dummy URL and does no real network. `npm run lint` (eslint) hung for 100 s locally, so it is report-only until fixed.
- Server (`ssh contabo`, read-only): user `devops`; key-only SSH on port 22, `PermitRootLogin no`; **3** keys in `authorized_keys`; sudo for `devops` is `(ALL) ALL` with a password, plus `NOPASSWD` only for `systemctl restart|status epk-celery`. **`sudo systemctl restart gunicorn` (which `deploy-release.sh` runs) still needs a password**, so a non-interactive deploy cannot work until that one sudoers line exists. `gunicorn` and `epk-celery` are active.
- `deploy-release.sh <ref>`: backs up the DB + media, checks out the ref, installs deps, `migrate`, restarts gunicorn then Celery, checks health. It restores the previous checkout automatically only **before** the database is touched; after `migrate` it only prints a rollback hint (migrations are never reversed).
- `deploy-static.sh frontend|distributor <ref>`: builds in a fresh release dir, swaps a symlink atomically, keeps 3 releases, prints a rollback command.

## 2. CI plan (GitHub Actions, per repo)

Common: trigger on `push` (all branches) and `pull_request`; `concurrency: group: ci-${{ github.ref }}, cancel-in-progress: true`; `permissions: contents: read`; fail-fast job order (cheap lint first); dependency caches; pin actions by major version.

### 2.1 backend repo: replace `.github/workflows/backend-ci.yml` with `ci.yml`
```yaml
name: CI
on:
  push:
  pull_request:
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
permissions:
  contents: read
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.12', cache: pip, cache-dependency-path: requirements-dev.txt }
      - run: pip install ruff==0.17.5
      - name: Blocking (syntax errors, undefined names)
        run: ruff check . --select E9,F63,F7,F82
      - name: Report only (ratchet later)
        run: ruff check . --select F --statistics
        continue-on-error: true
  test:
    needs: lint
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env: { POSTGRES_USER: test, POSTGRES_PASSWORD: test, POSTGRES_DB: test }
        ports: ['5432:5432']
        options: >-
          --health-cmd "pg_isready -U test" --health-interval 5s --health-timeout 5s --health-retries 10
    env:
      DATABASE_URL: postgres://test:test@localhost:5432/test
      DJANGO_SETTINGS_MODULE: core.settings_test
      SECRET_KEY: ci-only-not-a-secret
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.12', cache: pip, cache-dependency-path: requirements.txt }
      - run: pip install -r requirements.txt
      - run: python manage.py check
      - name: No model change without a migration
        run: python manage.py makemigrations --check --dry-run
      - run: python manage.py test --noinput --parallel 4
```
Notes: `check --deploy` is not run in CI (it needs production env); the deploy script already runs it. Open point: confirm `requirements.txt` installs on a clean Ubuntu runner (system libs for any compiled package); first run will tell.

### 2.2 frontend repo: `.github/workflows/ci.yml`
```yaml
name: CI
on: { push: , pull_request: }
concurrency: { group: ci-${{ github.ref }}, cancel-in-progress: true }
permissions: { contents: read }
jobs:
  build:
    runs-on: ubuntu-latest
    defaults: { run: { working-directory: codingclubskenya } }
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20, cache: npm, cache-dependency-path: codingclubskenya/package-lock.json }
      - run: npm ci
      - run: npx oxlint
        continue-on-error: true      # warnings today; make blocking after a cleanup
      - run: npm run build
```

### 2.3 distributor repo: `.github/workflows/ci.yml`
Same shape: Node 20, `npm ci`, `npm run build` with `env: { NEXT_PUBLIC_API_URL: https://example.invalid/api, NODE_ENV: production }`; `npm run lint` as `continue-on-error` with `timeout-minutes: 3`.

### 2.4 root repo
No CI needed beyond a docs/markdown sanity check; the Deploy workflow (section 3) is the only workflow there.

### Required status checks
After the first green run: branch protection on `feat/school-data-management` and `master` requiring `lint`, `test` (backend), `build` (frontend, distributor).

## 3. CD plan: manual "Deploy" workflow (root repo)

Never on `push`. `on: workflow_dispatch` with inputs `target` (choice: backend | frontend | distributor), `ref` (string, default the branch name), `confirm` (boolean "I have read the migration list").

### 3.1 Guard rails
1. GitHub **environment `production`** with **required reviewer = you**; the SSH secrets exist only in that environment, so no other workflow or fork can read them.
2. The workflow first checks that the target repo's CI is green for the exact sha of `ref` (`gh api repos/<owner>/<repo>/commits/<sha>/check-runs`). It needs a read-only fine-grained token (`CI_READ_TOKEN`, only if those repos are private; open question 1).
3. `ref` must match `^[A-Za-z0-9._/-]{1,100}$` and may not start with `-` (checked twice: in the workflow and in the server script).
4. For `backend`, a read-only step prints the unapplied migration list before the approval prompt, so the reviewer sees what will run.

### 3.2 Restricted SSH key
New key pair, used by nothing else. `authorized_keys` line on the server (one line):
```
restrict,command="/home/devops/deploy-scripts/ci-dispatch.sh" ssh-ed25519 AAAA...deploy-key... github-deploy
```
`restrict` turns off pty, port/agent/X11 forwarding and `~/.ssh/rc`. The forced command ignores what the client asked for and runs only the dispatcher, which reads `SSH_ORIGINAL_COMMAND` and accepts exactly three shapes. (A `from=` limit is not usable: GitHub-hosted runner addresses change constantly.)

New file `~/deploy-scripts/ci-dispatch.sh` (owned by `devops`, mode 755; versioned in `backend/deploy/ci-dispatch.sh`):
```bash
#!/usr/bin/env bash
# Forced command for the GitHub deploy key. Only: backend|frontend|distributor <ref>
set -euo pipefail
read -r target ref extra <<<"${SSH_ORIGINAL_COMMAND:-}"
[ -z "${extra:-}" ] || { echo "bad command" >&2; exit 2; }
[[ "$ref" =~ ^[A-Za-z0-9._/-]{1,100}$ && "$ref" != -* ]] || { echo "bad ref" >&2; exit 2; }
ROOT=/home/devops/home/personal/personalweb
S=$HOME/deploy-scripts
case "$target" in
  backend)
    prev=$(git -C "$ROOT/epk" rev-parse HEAD)
    "$S/deploy-release.sh" "$ref" && curl -fsS --max-time 10 https://api.codingclubskenya.com/api/healthz/ >/dev/null && exit 0
    echo "DEPLOY OR HEALTH CHECK FAILED: rolling code back to $prev (database left as is)" >&2
    git -C "$ROOT/epk" checkout --detach "$prev"
    sudo systemctl restart gunicorn
    exit 1 ;;
  frontend|distributor)
    live=$([ "$target" = frontend ] && echo "$ROOT/frontend-apk-web/codingclubskenya/dist" || echo "$ROOT/disributor/out")
    health=$([ "$target" = frontend ] && echo https://erp.codingclubskenya.com/healthz || echo https://learningpack.codingclubskenya.com/)
    prev=$(readlink "$live")
    "$S/deploy-static.sh" "$target" "$ref" && curl -fsS --max-time 10 "$health" >/dev/null && exit 0
    echo "HEALTH CHECK FAILED: swapping back to $prev" >&2
    ln -sfn "$prev" "$live.new" && mv -T "$live.new" "$live"
    exit 1 ;;
  *) echo "unknown target" >&2; exit 2 ;;
esac
```
Details to confirm while building: the real distributor health URL and `out` path (taken from `deploy-static.sh` and the release-1 deploy log), and whether the backend health URL should go through nginx (public) or the unix socket as the script does.

### 3.3 Sudoers (backend only needs this)
One new line, validated with `visudo -cf` before it is installed:
```
devops ALL=(root) NOPASSWD: /usr/bin/systemctl restart gunicorn, /usr/bin/systemctl status gunicorn
```
Nothing else: no wildcard, no `ALL`. `epk-celery` already has its line.

### 3.4 Automatic rollback: what it can and cannot do
- **frontend / distributor:** full rollback (symlink back to the previous release), health re-checked.
- **backend:** code-only rollback (checkout the previous commit, restart gunicorn). The database is **not** reversed. That is safe only while migrations stay additive (the standing rule in `DEPLOYMENT-GUIDE.md`); a destructive migration needs a manual restore from the dump the script prints. The migration list in 3.1(4) is what protects against this. Rollback is only attempted when the failure is after the code moved; failures before the DB is touched are already restored by `deploy-release.sh`.

### 3.5 `.github/workflows/deploy.yml` (root repo)
```yaml
name: Deploy
on:
  workflow_dispatch:
    inputs:
      target: { type: choice, options: [backend, frontend, distributor], required: true }
      ref:    { type: string, required: true, description: branch, tag or sha in the target repo }
      confirm: { type: boolean, required: true, description: I read the migration list (backend) }
concurrency: { group: deploy, cancel-in-progress: false }
permissions: { contents: read }
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - name: Validate inputs
        run: |
          [[ "${{ inputs.ref }}" =~ ^[A-Za-z0-9._/-]{1,100}$ && "${{ inputs.ref }}" != -* ]] || exit 1
          [ "${{ inputs.confirm }}" = true ] || { echo "tick confirm"; exit 1; }
      - name: CI must be green for this exact sha
        env: { GH_TOKEN: "${{ secrets.CI_READ_TOKEN }}" }
        run: ./.github/scripts/require-green.sh "${{ inputs.target }}" "${{ inputs.ref }}"
  deploy:
    needs: check
    runs-on: ubuntu-latest
    environment: production            # required reviewer approves here
    steps:
      - name: Install key
        run: |
          install -m 700 -d ~/.ssh
          printf '%s\n' "${{ secrets.DEPLOY_SSH_KEY }}" > ~/.ssh/id && chmod 600 ~/.ssh/id
          printf '%s\n' "${{ secrets.DEPLOY_KNOWN_HOSTS }}" > ~/.ssh/known_hosts
      - name: Deploy
        run: ssh -i ~/.ssh/id -o StrictHostKeyChecking=yes -o ServerAliveInterval=30 "${{ secrets.DEPLOY_USER }}@${{ secrets.DEPLOY_HOST }}" "${{ inputs.target }} ${{ inputs.ref }}"
      - name: Public health check
        run: |
          case "${{ inputs.target }}" in
            backend) curl -fsS https://api.codingclubskenya.com/api/healthz/ ;;
            frontend) curl -fsS https://erp.codingclubskenya.com/healthz ;;
            distributor) curl -fsS https://learningpack.codingclubskenya.com/ >/dev/null ;;
          esac
      - name: Log the deploy
        run: echo "${{ inputs.target }} ${{ inputs.ref }} by ${{ github.actor }} run ${{ github.run_id }}" >> "$GITHUB_STEP_SUMMARY"
```
Environment secrets (`production`): `DEPLOY_SSH_KEY` (private key), `DEPLOY_KNOWN_HOSTS` (the server's host key line, so the connection is pinned, not trust-on-first-use), `DEPLOY_HOST`, `DEPLOY_USER`. Optional repo secret `CI_READ_TOKEN`. The deploy-log entry in `docs/specs/reports/` stays a manual step (the workflow summary is not a substitute for the rollback target note).

## 4. Server one-off steps (each for you to run; sudo shown first)

Run as `devops` on the server. Nothing below changes a running service.
1. **Sudoers line** (validated before install):
   ```
   echo 'devops ALL=(root) NOPASSWD: /usr/bin/systemctl restart gunicorn, /usr/bin/systemctl status gunicorn' | sudo tee /etc/sudoers.d/devops-gunicorn >/dev/null
   sudo chmod 440 /etc/sudoers.d/devops-gunicorn && sudo visudo -cf /etc/sudoers.d/devops-gunicorn
   sudo -n -l | tail -3        # must now list gunicorn restart as NOPASSWD
   ```
2. **Dispatcher script** (after it is reviewed in the repo): `install -m 755 ci-dispatch.sh ~/deploy-scripts/ci-dispatch.sh`, then `bash -n ~/deploy-scripts/ci-dispatch.sh`.
3. **Key pair** (on your laptop, not the server): `ssh-keygen -t ed25519 -f ~/.ssh/gh-deploy -C github-deploy -N ''`. Put the private key into the GitHub `production` environment secret `DEPLOY_SSH_KEY`, then delete the local private file.
4. **authorized_keys:** `cp ~/.ssh/authorized_keys ~/.ssh/authorized_keys.bak-$(date +%F)`, then append the one forced-command line from 3.2 with the new public key. Test from the laptop *before* touching GitHub: `ssh -i ~/.ssh/gh-deploy contabo 'bash'` must print "bad command" and exit 2; `ssh -i ... contabo 'frontend ../x'` must print "bad ref".
5. **known_hosts value:** `ssh-keyscan -t ed25519 <host>` from the laptop, compare the fingerprint with `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` on the server, then store the line as `DEPLOY_KNOWN_HOSTS`.
6. **Dry run:** a deploy of the *current* live ref per target (no change expected), watching the workflow; for backend the migrate step is a no-op and the backup is still taken.

Each step is reversible: delete the sudoers file, restore `authorized_keys.bak-*`, remove the dispatcher.

## 5. Estimates (working days)
| Piece | Days | Notes |
|---|---|---|
| CI backend (workflow, `makemigrations --check`, first-run fixes for the runner) | 0.5 to 1 | the suite already passes on Postgres 16 |
| CI frontend + distributor | 0.5 | dummy API URL for the Next build |
| Ruff ratchet (one cleanup commit for the 149 `F` findings, then `--select F` blocking) | 0.5 | optional, separate PR; `ruff format` of 464 files is a separate decision |
| Branch protection + required checks | 0.1 | |
| `ci-dispatch.sh` + local tests of its accepts/rejects | 0.5 | tested against a scratch copy, not the live server |
| Deploy workflow, environment, `require-green.sh` | 0.5 to 1 | token question below can add time |
| Server one-off steps and dry runs (yours + mine to watch) | 0.5 | |
| Deliberate failure drills (bad health check on a throwaway copy of the dispatcher) | 0.5 | proves the rollback branches |
| **Total** | **about 4 to 5** | CI is about 1.5 to 2 of those and ships first |

## 6. Open questions for you
1. Are `fattym/epk`, `fattym/frontend-apk-web`, `fattym/disributor` private? If yes, the green-check gate needs `CI_READ_TOKEN` (fine-grained, read-only, Checks + Contents) created by the `fattym` account.
2. Accept code-only rollback for the backend (section 3.4), or require manual approval before any backend rollback?
3. OK to make the Deploy workflow live in the root repo (`codingclubskenya` org), given the three app repos belong to `fattym`?
4. Should `learningpack` (distributor) deploys use the same `production` approval, or a lighter one?
