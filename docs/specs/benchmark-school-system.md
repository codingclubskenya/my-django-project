Sidebar: Dashboard, Calendar, Classes, Subjects, Students, Teachers, BOM/PA, Staff, Exams, Attendance, Messages, Printouts, Billing, Finance, Timetable, Opportunities.

---

## Classes (`/classes`)
Three tabs: **My Classes**, **Manage Classes**, **Add New Class**. A "class" has two levels: the *form/grade* (e.g. Grade 10, Form 4) split into streams (Zion, Everest), and the *subject class*, which is a stream plus a subject taught by a teacher.

### My Classes (`/classes/myclass`)
- Table of subject classes the logged-in teacher teaches, e.g. "Grade 10 Zion - English", "Form 4 Everest - Chemistry".
- **Class list** opens a panel with the class register header (school, phone, email, "GRADE 10 ZION - 2026 - CLASS LIST", teacher) and columns IMAGE, ADMNO, NAME, PL, GENDER. Options: list type *Basic* or *Custom*, plus Print and Download.
- **Manage** opens per-subject-class settings (not opened in this pass).

### Manage Classes (`/classes/manage`)
- One row per form/grade with boys, girls and total counts (Grade 10: 2+1=3, Form 4: 6+7=13, total 16).
- Per row: a **Class Supervisor** dropdown, **Manage**, **Class list**.
- A *Graduated Classes* link lists past classes.

### Add New Class (`/classes/add`)
- Fields: **Form / Grade** (required), **Stream(s)** (required), and a grouped multi-select of **subjects done by this class**.
- Subject groups: Mathematics, Languages, Literature, Sciences, Humanities, Technicals, Optionals, Support Subjects. The list covers both 8-4-4 and CBC/CBE subjects (Community Service Learning, Core/Essential Mathematics, Aviation, Marine and Fisheries, and others).

---

## Exams (`/exams`)
Top tabs: **Assessments**, **Manage Exams**, **Create Exam**, **Grading Systems**, **Subject Paper Ratios**, **More** (includes **Deleted Exams**).

Flow: define grading system and paper ratios → create exam for a form/term → enable subject papers → upload results → analyse → publish/release → send to parents.

### Assessments (`/exams/my-classes`)
- For a teacher's own classes. Tabs: *My Classes* and *Continuous Assessment Tests*.
- Radio toggle: **Continuous Assessment Tests** or **School Based Assessment** (the CBC formative side).
- Each subject class has **View Assessments**, which opens `/exams/my-classes/assessments/v2/<id>`. That page has filters **Year**, **Term** and **Strand** (all required) and a **Create Assessment** button. It shows "No Assessments Found" until one is created.

### Manage Exams (`/exams/manage`)
- Filter by **Academic Year**. Exams are grouped by term, one row per exam and class.
- Columns: Exam, Class, Status, Updated By, Updated On, Action.
- **Status lifecycle** (seen on this site):
  1. *Results Not Uploaded* (actions: Edit Exam, Subject Papers, Upload Results, Delete). Example: END YEAR, Term 3.
  2. *Pending Publishing* (actions: Publish Results, Delete). Example: MID TERM, Term 2.
  3. *Released* (actions: Analyze Results, Send Results, Withdraw Results). Example: SAMPLE, Term 2.
- **Subject Papers** opens `/exams/manage/config/<id>/<id>` ("Form 4 - END YEAR - 2026 Term 3"). It lists every subject with Paper/Ratio, Status (*unset* until configured) and **Add**, plus an **Enable all** button. This decides which subjects and papers make up the exam.

### Create Exam (`/exams/create-exam`)
- **Exam Type**: Written test, Consolidated Exam, KCSE, Supplementary Exam, Year Average.
- Fields: Exam Name, Term (1–3), Year (2022–2026), and the Form/Grade that sat (Grade 10 or Form 4). The **Create** button creates it with status "Results Not Uploaded".

### Grading Systems (`/exams/grading-systems`)
- Lists grading schemes with **View**, **Delete** and **Create Grading System**. Existing: **CBE** and **EAST** (the old 8-4-4 scale).

### Subject Paper Ratios (`/exams/subject-papers`)
- Per subject, each paper has an "Out Of" mark and a **Ratio** weight, used to combine papers into one subject score. Examples:
  - Kiswahili: Kar 1 (40, ratio 1), Kar 2 (80, ratio 2), Kar 3 (80, ratio 2).
  - Biology, Chemistry and Physics: P1 80/3, P2 80/3, P3 40/4.
  - English: P1 60/3, P2 80/4, P3 80/4.
  - Maths, History, Geography, CRE, Agriculture, Business: papers out of 100, ratio 1.
- Each paper has **Edit**/**Delete**, and each subject has **Add Subject Paper**. Some subjects (Essential/Core Maths, Kenyan Sign Language, Music & Dance, CSL) have no papers yet.

### Deleted Exams (`/exams/deleted-exams`)
- Soft-delete bin, currently empty.

---

## Other pages
| Page | Path | What it does |
|---|---|---|
| Dashboard | `/dashboard/welcome/admin` | Counts of students/teachers/staff, SMS credit balance with Buy SMS credits, Assessment Outcomes chart (grade, stream, summative/formative, exam), Student Flow chart (enrollment vs transfers), switches to Teacher or 8-4-4 dashboards. |
| Subjects | `/subjects` | "Compulsory Subjects" per form (Form 1–4, Grade 10–12) with Add/Edit/Delete. None are set yet. |
| Students | `/students` → `/students/search` | Search by Admission Number, Name, Phone, UPI or Index Number. |
| Attendance | `/attendance` | Lists the teacher's subject classes, each with an **Attendance** button for marking. |
| Messages | `/messages/inbox` | School inbox, currently empty, with an **Opt Out** control. |
| Printouts | `/printouts` | Documents to print: Class List, Score Sheet, Analysis Report, Report Forms, Merit List, Assessments, Transcripts, Attendance Reports, Leaving Certificates, House List. |
| Timetable | `/timetable/dashboard` | Today's lessons, ongoing classes, average attendance, students marked absent or unmarked, teacher workload (lessons per week/today), teacher compliance (unmarked lessons, marking rate). |
| Calendar | `/events` | School events calendar. Not inspected. |
| Teachers / BOM-PA / Staff | `/staff/teacher`, `/staff/official`, `/staff/worker` | Staff directories: teachers, board/PA officials, support workers. Not inspected. |
| Billing, Finance, Opportunities | `/billing/invoices`, `/finance`, `/opportunities` | Invoices and subscription, fee finance module, and opportunities. Not inspected. |
| Settings / Profile | `/settings/...` | Profile, linked accounts (multi-school login switching), change password. Not inspected. |
| Customer Support | `/customer-support` | Help page. Not inspected. |
