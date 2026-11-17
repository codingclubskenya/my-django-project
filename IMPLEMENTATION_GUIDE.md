# Implementation Guide — CBC School ERP

> Concrete, file-by-file implementation steps for closing every gap identified in IMPROVEMENT_PLAN.md. Organized by module. Each section includes: model definitions, file paths, management commands, and verification steps.

---

## Phase 0 — Production Critical Fixes (do first, ~3 hours)

### 0.1 Fix world-writable gunicorn socket
**File:** systemd unit on the Contabo VPS (`/etc/systemd/system/gunicorn.service`)
```ini
# Change: --umask 000 → --umask 007
ExecStart=/home/devops/home/personal/personalweb/epk/venv/bin/gunicorn --access-logfile ... --umask 007 core.wsgi:application
```
```bash
sudo systemctl daemon-reload
sudo systemctl restart gunicorn
ls -la /home/devops/home/personal/personalweb/epk/epk.sock  # should be srw-rw----
```

### 0.2 Start Celery workers
**Files to create:**
- `/etc/systemd/system/celery.service` — worker
- `/etc/systemd/system/celerybeat.service` — scheduler (periodic tasks)

```ini
# /etc/systemd/system/celery.service
[Unit]
Description=Celery Service
After=network.target redis-server.service

[Service]
User=devops
Group=www-data
EnvironmentFile=/home/devops/home/personal/personalweb/epk/.env
WorkingDirectory=/home/devops/home/personal/personalweb/epk
ExecStart=/home/devops/home/personal/personalweb/epk/venv/bin/celery -A core worker -l info
Restart=always

[Install]
WantedBy=multi-user.target
```
```bash
systemctl enable --now celery.service celerybeat.service
ssh contabo "sudo systemctl status celery.service"  # verify active
```

### 0.3 Fix missing `django-redis` (or remove from settings)
**Option A (recommended):** Install the package
```bash
ssh contabo "cd ~/home/personal/personalweb/epk && venv/bin/pip install django-redis"
```
**Option B:** Edit `core/settings_production.py` — remove `django_redis`-specific keys from `CACHES`:
```python
CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.redis.RedisCache',
        'LOCATION': f'{_redis_url}/{_REDIS_DB_CACHE}',
        # keep OPTIONS minimal — remove COMPRESSOR and CLIENT_CLASS
        'KEY_PREFIX': 'school_mgmt',
        'TIMEOUT': 300,
    },
    'sessions': {
        'BACKEND': 'django.core.cache.backends.redis.RedisCache',
        'LOCATION': f'{_redis_url}/{_REDIS_DB_SESSIONS}',
        'KEY_PREFIX': 'school_mgmt_sessions',
        'TIMEOUT': 86400,
    },
}
```
After either fix: `sudo systemctl restart gunicorn` and test: `python manage.py shell -c "from django.core.cache import cache; cache.set('test', 'ok', 30); print(cache.get('test'))"`

### 0.4 Add nginx rate limiting
**File:** `/etc/nginx/nginx.conf` (in `http {}` block)
```nginx
limit_req_zone $binary_remote_addr zone=login:10m rate=5r/m;
limit_req_zone $binary_remote_addr zone=api:10m rate=60r/s;
limit_req_zone $binary_remote_addr zone=mpesa:10m rate=10r/m;
```
Then add inside the relevant `location` blocks:
```nginx
# /api/auth/login/
limit_req zone=login burst=10 nodelay;
# /pma/ — restrict to office IP
allow YOUR_OFFICE_IP;
deny all;
limit_req zone=login burst=5 nodelay;
# /api/mpesa/callback/
limit_req zone=mpesa burst=10 nodelay;
```
Reload: `sudo nginx -t && sudo systemctl reload nginx`

---

## Phase 1 — Missing Modules (models + serializers + views + URLs + admin)

### 1.1 Health Records Module
**New app:** `backend/health/`

**`health/models.py`**
```python
from django.db import models
from tenants.models import School
from accounts.models import User

class HealthRecord(models.Model):
    school = models.ForeignKey(School, on_delete=models.CASCADE, related_name='health_records')
    student = models.ForeignKey(User, on_delete=models.CASCADE, related_name='health_records')
    allergies = models.TextField(blank=True, help_text="Comma-separated or structured JSON")
    medications = models.TextField(blank=True)
    medical_conditions = models.TextField(blank=True)
    emergency_contact_name = models.CharField(max_length=100)
    emergency_contact_phone = models.CharField(max_length=20)
    last_updated = models.DateTimeField(auto_now=True)
    created_at = models.DateTimeField(auto_now_add=True)

class NurseVisit(models.Model):
    school = models.ForeignKey(School, on_delete=models.CASCADE, related_name='nurse_visits')
    student = models.ForeignKey(User, on_delete=models.CASCADE, related_name='nurse_visits')
    reason = models.TextField()
    treatment = models.TextField(blank=True)
    medication_given = models.TextField(blank=True)
    severity = models.CharField(max_length=20, choices=(('MINOR','Minor'),('MODERATE','Moderate'),('SERIOUS','Serious')), default='MINOR')
    recorded_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, related_name='recorded_visits')
    created_at = models.DateTimeField(auto_now_add=True)
```

**`health/admin.py`** — register both with school scoping
**`health/serializers.py`** — `HealthRecordSerializer` + `NurseVisitSerializer`
**`health/views.py`** — `SchoolScopedViewSet`
**`health/urls.py`** — `path('api/health/', include(router.urls))`
Add `'health'` to `INSTALLED_APPS` + `core/urls.py` include.

### 1.2 Disciplinary Records Module
**New app:** `backend/discipline/`

**`discipline/models.py`**
```python
from django.db import models
from tenants.models import School
from accounts.models import User

class DisciplinaryRecord(models.Model):
    school = models.ForeignKey(School, on_delete=models.CASCADE, related_name='disciplinary_records')
    student = models.ForeignKey(User, on_delete=models.CASCADE, related_name='disciplinary_records')
    incident_type = models.CharField(max_length=50, choices=(('LATE','Late'),('ABSENT','Absent'),('DISRUPTION','Disruption'),('BULLYING','Bullying'),('DAMAGE','Damage'),('OTHER','Other')))
    description = models.TextField()
    action_taken = models.TextField()
    severity = models.CharField(max_length=20, choices=(('LOW','Low'),('MEDIUM','Medium'),('HIGH','High')), default='LOW')
    recorded_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, related_name='recorded_discipline')
    parent_notified = models.BooleanField(default=False)
    resolved = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
```

### 1.3 Alumni Tracking Module
**New app:** `backend/alumni/`

**`alumni/models.py`**
```python
class Alumni(models.Model):
    school = models.ForeignKey(School, on_delete=models.CASCADE, related_name='alumni')
    user = models.OneToOneField(User, on_delete=models.SET_NULL, null=True, blank=True, related_name='alumni_profile')
    graduation_year = models.PositiveSmallIntegerField()
    current_status = models.CharField(max_length=100, blank=True)
    current_institution = models.CharField(max_length=255, blank=True)
    current_employer = models.CharField(max_length=255, blank=True)
    linkedin = models.URLField(blank=True)
    email = models.EmailField(blank=True)
    phone = models.CharField(max_length=20, blank=True)
```

### 1.4 Parent-Teacher Meeting Scheduling
**Reuse the Interview pattern from `recruitment`.** Add to `backend/parents/` (or reuse `recruitment` with a `meeting_type` field).

**`parent_meetings/models.py`**
```python
class ParentTeacherMeeting(models.Model):
    school = models.ForeignKey(School, on_delete=models.CASCADE, related_name='ptmeetings')
    teacher = models.ForeignKey(User, on_delete=models.CASCADE, related_name='scheduled_meetings')
    parent = models.ForeignKey(User, on_delete=models.CASCADE, related_name='meetings_as_parent')
    student = models.ForeignKey(User, on_delete=models.CASCADE, related_name='meetings_as_student')
    scheduled_at = models.DateTimeField()
    duration_minutes = models.PositiveSmallIntegerField(default=30)
    location = models.CharField(max_length=255, blank=True)
    agenda = models.TextField(blank=True)
    status = models.CharField(max_length=20, choices=(('PENDING','Pending'),('CONFIRMED','Confirmed'),('COMPLETED','Completed'),('CANCELLED','Cancelled')), default='PENDING')
    notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
```

### 1.5 Staff Payroll / HR / Leave
**New app:** `backend/payroll/`

**`payroll/models.py`**
```python
class StaffProfile(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='staff_profile')
    school = models.ForeignKey(School, on_delete=models.CASCADE, related_name='staff_profiles')
    employee_id = models.CharField(max_length=20, unique=True)
    designation = models.CharField(max_length=100)
    department = models.CharField(max_length=100, blank=True)
    hire_date = models.DateField()
    salary = models.DecimalField(max_digits=10, decimal_places=2)
    bank_account = models.CharField(max_length=50, blank=True)
    bank_name = models.CharField(max_length=50, blank=True)
    is_active = models.BooleanField(default=True)

class LeaveRequest(models.Model):
    staff = models.ForeignKey(StaffProfile, on_delete=models.CASCADE, related_name='leave_requests')
    leave_type = models.CharField(max_length=20, choices=(('ANNUAL','Annual'),('SICK','Sick'),('CASUAL','Casual'),('MATERNITY','Maternity')))
    start_date = models.DateField()
    end_date = models.DateField()
    days = models.PositiveSmallIntegerField()
    reason = models.TextField()
    status = models.CharField(max_length=20, choices=(('PENDING','Pending'),('APPROVED','Approved'),('REJECTED','Rejected')), default='PENDING')
    approved_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True, related_name='approved_leaves')
    created_at = models.DateTimeField(auto_now_add=True)

class PaySlip(models.Model):
    staff = models.ForeignKey(StaffProfile, on_delete=models.CASCADE, related_name='payslips')
    month = models.PositiveSmallField()
    year = models.PositiveSmallField()
    gross_salary = models.DecimalField(max_digits=10, decimal_places=2)
    deductions = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    net_salary = models.DecimalField(max_digits=10, decimal_places=2)
    generated_at = models.DateTimeField(auto_now_add=True)
```

**Wire into recruitment:** Add a post-save signal on `Offer.accepted → create StaffProfile + inactive User`.

---

## Phase 2 — AI / Agentic Features

> Each AI feature follows the human-in-the-loop rule: AI output is a **draft/suggestion**, never auto-committed. Log suggestions separately.

### 2.1 AI-assisted Scheme of Work Drafting
**Files:** `backend/curriculum/views.py`, `backend/curriculum/models.py` (add fields to `SchemeWeek`)

Add to `SchemeWeek` model:
```python
learning_experience = models.TextField(blank=True, help_text="AI-drafted — review before finalizing")
key_inquiry_question = models.TextField(blank=True)
ai_suggested_resources = models.JSONField(blank=True, null=True, help_text="List of suggested resources")
ai_draft_timestamp = models.DateTimeField(null=True, blank=True)
```

New view `backend/curriculum/views.py`:
```python
class AIAssistSchemeView(APIView):
    permission_classes = [IsAuthenticated]
    def post(self, request):
        # 1. Fetch learning outcome text + sub-strand
        # 2. Call LLM (via AI_ASSIST_API_URL) to draft learning_experience, key_inquiry, resources
        # 3. Return as JSON {learning_experience, key_inquiry_question, learning_resources}
        # 4. DO NOT save to DB — user must review in UI
```

### 2.2 Report Card Narrative Generation
**Files:** `backend/reports/views.py`, `backend/exams/models.py`

New endpoint `/api/reports/cbc-narrative/<learner_id>/`:
```python
def generate_narrative(learner, term):
    assessments = CompetencyAssessment.objects.filter(learner=learner, term=term)
    # Compile competency levels + attendance + homework
    # Call LLM to produce coherent narrative
    # Return draft for teacher review
```

### 2.3 Parent-facing AI Chatbot (Flutter future)
**No backend work needed initially.** When built:
1. New endpoint `/api/chatbot/` — takes a question, context (parent's learners, fees, events)
2. Auth: JWT authenticated PARENT only
3. Tool-use: internally calls `/api/fees/balance/`, `/api/events/upcoming/`, `/api/shop/products/` etc.
4. Returns answer + sources for audit

### 2.4 At-risk Learner Flagging
**Files:** new `backend/analytics/tasks.py` + Celery beat

```python
@shared_task
def flag_at_risk_learners():
    # Query: attendance < X% + repeated BE/AE + fee arrears
    # Create AtRiskFlag model entry instead of auto-modifying assessment
    # Send notification to teacher + admin
```
Add `beat_schedule` entry in `core/celery.py`.

### 2.5 Automated Timetable Generation
**Files:** `backend/academics/ai_assist.py`

Build a constraint-satisfaction solver: fetch all `Teacher` availability, `Stream` requirements per `LearningArea`, `Room`/`Resource` constraints → generate draft → check conflicts → return to UI for review.

### 2.6 Interview Question Generation
**Files:** `backend/recruitment/views.py`

New endpoint `/api/recruitment/interview-questions/`:
```python
class InterviewQuestionGenerator(APIView):
    def post(self, request, job_posting_id):
        # Fetch JobPosting requirements
        # LLM generates role-specific questions + scoring rubric
        # Return draft — hiring team reviews, doesn't auto-advance
```

---

## Phase 3 — Security & Compliance

### 3.1 Add `django-axes` (brute-force protection)
1. Add to `backend/requirements.txt`: `django-axes==6.10.0`
2. `INSTALLED_APPS`: add `'axes'`
3. `AUTHENTICATION_BACKENDS`:
```python
AUTHENTICATION_BACKENDS = [
    'axes.backends.AxesBackend',
    'django.contrib.auth.backends.ModelBackend',
]
```
4. `MIDDLEWARE`: add `'axes.middleware.AxesMiddleware'` first
5. Configure lockout:
```python
AXES_FAILURE_LIMIT = 5
AXES_COOLOFF_TIME = 300  # 5 minutes
AXES_LOCKOUT_CALLABLE = 'accounts.helpers.is_locked'
```
6. Run `python manage.py migrate axes`

### 3.2 Add object-level permissions
1. Add to `requirements.txt`: `django-guardian==3.3.0`
2. Install: `pip install -r requirements.txt`
3. Add to `settings.py` / `settings_production.py`:
```python
INSTALLED_APPS += ['guardian']
AUTHENTICATION_BACKENDS += ['guardian.backends.ObjectPermissionBackend']
ANONYMOUS_USER_ID = -1
```
4. Run: `python manage.py migrate`

### 3.3 Audit logging
Create `backend/audit/` app with an `AuditLog` model:
```python
class AuditLog(models.Model):
    user = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, related_name='audit_logs')
    school = models.ForeignKey(School, on_delete=models.CASCADE, related_name='audit_logs')
    action = models.CharField(max_length=50)
    model_name = models.CharField(max_length=100)
    object_id = models.CharField(max_length=100)
    before = models.JSONField(null=True, blank=True)
    after = models.JSONField(null=True, blank=True)
    ip_address = models.GenericIPAddressField(null=True)
    created_at = models.DateTimeField(auto_now_add=True)
```
Add a middleware or `post_save`/`pre_save` signal to log: User CRUD, fee balance changes, `Offer` accept/reject, `CompetencyAssessment` edits.

### 3.4 KDPA compliance (data retention + consent)
1. Create `backend/compliance/` app
2. `RetentionPolicy` model + management command to purge old data
3. Add `consent_given = models.BooleanField(default=False)` + `consent_date` to `User` / `ParentLearner`
4. Add "Delete my data" API endpoint (GDPR-style right to erasure)

### 3.5 Rate limiting (DRF)
In `core/settings.py` and `core/settings_production.py`:
```python
REST_FRAMEWORK['DEFAULT_THROTTLE_CLASSES'] = [
    'rest_framework.throttling.AnonRateThrottle',
    'rest_framework.throttling.UserRateThrottle',
]
REST_FRAMEWORK['DEFAULT_THROTTLE_RATES'] = {
    'anon': '100/day',
    'user': '1000/hour',
}
```

### 3.6 Fix `corsheaders` in dev settings
In `core/settings.py` — replace `CORS_ALLOW_ALL_ORIGINS = True` with:
```python
CORS_ALLOWED_ORIGINS = [
    'http://localhost:5173',
    'http://localhost:3000',
    'http://localhost:5173/schoolsystem/',
]
```

---

## Phase 4 — Infrastructure & DevOps

### 4.1 API Versioning
Wrap existing URLs under `/api/v1/`:

In `core/urls.py`:
```python
urlpatterns = [
    path('admin/', admin.site.urls),
    path('api/v1/auth/', include('accounts.urls')),
    path('api/v1/tenants/', include('tenants.urls')),
    # ... all other apps under v1
]
```
Add `DEFAULT_VERSIONING` to `REST_FRAMEWORK` settings:
```python
'DEFAULT_VERSIONING_CLASS': 'rest_framework.versioning.URLPathVersioning',
```
Add a deprecation notice to the old `/api/` endpoints.

### 4.2 CI/CD Pipeline
**File:** `.github/workflows/backend-ci.yml`
```yaml
name: Backend CI
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env: { POSTGRES_USER: test, POSTGRES_PASSWORD: test, POSTGRES_DB: test }
        options: --health-cmd pg_isready
      redis:
        image: redis:7
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.12' }
      - run: pip install -r backend/requirements.txt
      - run: pip install pytest pytest-django pytest-cov ruff
      - run: ruff check backend/
      - run: cd backend && python manage.py check
      - run: cd backend && python manage.py migrate --run-syncdb
      - run: cd backend && python manage.py test
```

**Frontend CI:** Create `.github/workflows/frontend-ci.yml` for React + Next.js lint + typecheck + build.

### 4.3 Typed API client generation
```bash
# React frontend
cd frontend/codingclubskenya
npm install -D openapi-typescript
npx openapi-typescript http://localhost:8000/api/schema/?format=json --output src/api/types.ts

# Flutter (future)
flutter pub add chopper chopper_generator build_runner
# Generate from OpenAPI schema
```

### 4.4 Docker for dev parity
**File:** `/docker-compose.yml`
```yaml
version: '3.8'
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_DB: school_mgmt
      POSTGRES_USER: school_user
      POSTGRES_PASSWORD: dev_password
    volumes: ['pg_data:/var/lib/postgresql/data']
  redis:
    image: redis:7
  web:
    build: ./backend
    command: python manage.py runserver 0.0.0.0:8000
    volumes: ['./backend:/app', './backend/media:/app/media']
    env_file: backend/.env.example
    ports: ['8000:8000']
    depends_on: [postgres, redis]
volumes: { pg_data: }
```

### 4.5 Sentry integration
Add to `settings_production.py`:
```python
import sentry_sdk
from sentry_sdk.integrations.django import DjangoIntegration

sentry_sdk.init(
    dsn=os.environ.get('SENTRY_DSN', ''),
    integrations=[DjangoIntegration()],
    traces_sample_rate=0.1,
    send_default_pii=False,
)
```

---

## Phase 5 — Frontend Improvements

### 5.1 React staff app — missing pages
Based on the route list, the following are present. Add:
- `/analytics` — comprehensive dashboard
- `/health` — student health records
- `/discipline` — disciplinary records
- `/alumni` — alumni tracking
- `/payroll` — staff payroll + leave
- `/ptm` — parent-teacher meetings
- `/compliance` — data retention, KDPA consent

### 5.2 Flutter parent app — add features
- `/chatbot` — AI parent assistant screen
- `/health` — view child's health records
- `/disciplinary` — view behavior notes
- `/analytics` — parent-facing insights (attendance, fees, progress trends)

### 5.3 Tests for frontends
```bash
# React
cd frontend/codingclubskenya
npm install -D vitest @testing-library/react

# Flutter
cd frontend/parents
flutter test  # existing framework
```
