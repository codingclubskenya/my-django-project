# my-django-project (school management platform)
Superproject with 3 git submodules, each its own repo. Commit inside the submodule, then bump the pointer in root only when asked.
- backend/: Django 6 + DRF, simplejwt/allauth, Celery + Redis, Postgres. ~40 apps (academics, fees, exams, tenants, ...). Core models: User, School, Term, Grade.
- frontend/: web + mobile clients (codingclubskenya = React web).
- distributor/: Next.js app; see distributor/AGENTS.md.
- deploy/nginx, backend/deploy: infra. Treat as production config; confirm before edits.

## Commands
- Python: `backend/venv_new/bin/python` (never system python or pip).
- Tests: `cd backend && DJANGO_SETTINGS_MODULE=core.settings_test venv_new/bin/python manage.py test <app> --noinput` (all apps: omit <app>). Never plain settings: too slow.
- Migrations: generate with `makemigrations <app>`, never hand-write. Read migrations/ only for migration tasks.

## Rules
- Multi-tenant: every query/view must stay scoped to the tenant/school. Flag any change that could leak across schools.
- Security-sensitive areas (accounts, fees/payments, permissions, nginx): smallest change, explain risk in one line.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- When graphify-out/graph.json exists, run `graphify query "<question>"` before your first grep, search or source-file read for a codebase question, and put this rule in every subagent prompt that explores code. Read raw files only for lines the graph or an earlier read already located. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` from the repo root (~/Documents/Code/my-django-project, never a submodule) to keep the graph current (AST-only, no API cost).
- A committed graphify-out/graph.json is rewritten whole on every build, so a large diff to it in a pull request is expected. Do not flag it as churn or suggest skipping the graph rebuild or its hooks.

## Browser testing (claude --chrome)
- Only drive the browser against local dev servers (localhost:5173 frontend, localhost:8000 API). Never production or staging URLs.
- Use only the dev seed accounts (`manage.py seed_dev_users`). Never real user credentials.
- Read the console for errors only; don't dump full logs. Close tabs when done.
- Before relying on the graph, check `jq '.nodes|length' graphify-out/graph.json`; if under 3000, run `graphify update . --force` from the repo root first (branch switches can leave a partial graph).

## Production server (ssh contabo)
- Every ssh/scp/rsync command needs my approval. Read-only by default: inspect, count, dump. Anything that changes the server (migrate, restart, file edits, pip/npm installs, nginx reload) only when I say so for that step.
- Never print secrets: no cat of .env or settings with passwords; use `grep -c` or key names only.
- Before any change: confirm a fresh database backup exists and say where it is.
- nginx: always `nginx -t` before reload. Django: always run migrations with production settings and after `check_duplicates`/`check_stream_years` where the deploy notes require them.
