# Implementation Prompt: School Classes, Students, Parents & Staff Management

## 1. Objective

Implement a connected school management workflow covering the following modules:

1. `/classes` – Class creation, class management, student allocation, and supervisor assignment.
2. `/students` – Student registration, bulk import, and class allocation.
3. `/parents` – Parent/guardian information management and linking parents to students.
4. `/staff` – Teacher and non-teaching staff registration, bulk import, and management.

All four modules must be interconnected. Data entered in one module should automatically reflect in the relevant modules without unnecessary duplication.

Before implementation, inspect the existing project architecture, database structure, authentication, permissions, UI components, and current functionality. Extend the existing system rather than rebuilding it.

---

## 2. Classes Management – `/classes`

The Classes page should be the central point for creating and managing school classes.

### Features

- Create a new class.
- Edit class information.
- View all existing classes.
- Delete or archive classes, subject to existing student and historical record constraints.
- Assign students to classes.
- Assign a class supervisor (teacher).
- View students belonging to each class.
- View the assigned class supervisor.
- Filter classes by academic year, grade, level, or stream.

### Class creation fields

- Class Name (e.g. Grade 1, Grade 2, Grade 7).
- Class Code.
- Grade/Level.
- Stream (e.g. East, West, North).
- Academic Year.
- Class Capacity.
- Class Supervisor.
- Status (Active/Inactive).

### Class Supervisor Assignment

The Classes page is where the class supervisor is selected.

The supervisor must be selected from the staff records already registered in `/staff`.

Requirements:
- Only eligible teaching staff should appear in the supervisor dropdown.
- A teacher can supervise a class.
- Allow changing the assigned supervisor.
- Display the supervisor's name and contact information.
- Prevent invalid or duplicate assignments where restricted by school policy.
- Maintain a record of supervisor assignment changes.

### Student Allocation

Students should be allocated to classes through the `/students` module.

The Classes page should automatically display students assigned to each class.

Include:
- Total students in a class.
- Available class capacity.
- Student list.
- Search and filtering.
- Student transfer functionality.

---

## 3. Students Management – `/students`

This module handles student registration and management.

### Individual Student Registration

Provide a form for adding students with fields such as:

- Admission Number.
- First Name.
- Middle Name.
- Last Name.
- Gender.
- Date of Birth.
- Grade/Class.
- Stream.
- Academic Year.
- Admission Date.
- Student Status.
- Parent/Guardian.

Include any additional student fields already supported by the existing system.

### Bulk Student Import

Implement an Excel/CSV bulk import feature.

The upload template should contain all required student fields, including a dedicated Parent/Guardian field.

Example template columns:

| Field | Description |
|---|---|
| ADMISSION_NUMBER | Unique student admission number |
| FIRST_NAME | Student first name |
| MIDDLE_NAME | Middle name |
| LAST_NAME | Student surname |
| GENDER | Male/Female |
| DATE_OF_BIRTH | Student date of birth |
| CLASS | Class name |
| STREAM | Class stream |
| ACADEMIC_YEAR | Academic year |
| PARENT_NAME | Parent/guardian full name |
| PARENT_PHONE | Parent/guardian phone |
| PARENT_EMAIL | Parent/guardian email |
| PARENT_ID_NUMBER | Parent identification number |
| ADMISSION_DATE | Admission date |

### Bulk Import Workflow

1. Download the official student import template.
2. Populate student and parent information.
3. Upload the completed Excel/CSV file.
4. Validate the uploaded data.
5. Identify missing or invalid fields.
6. Detect duplicate admission numbers.
7. Match students to existing classes.
8. Match parents using unique identifiers such as phone number.
9. Create new parent records where appropriate.
10. Link each student to the correct parent record.
11. Display a preview before importing.
12. Allow users to confirm the import.
13. Generate an import report showing successful, failed, and skipped records.

Important: Parent information imported through the student template must also be available in `/parents`. Do not create duplicate parent records when the same parent has multiple children.

---

## 4. Parents/Guardians Management – `/parents`

This module manages all parent and guardian information.

### Features

- Add a parent or guardian.
- Edit parent information.
- View all registered parents.
- Search by name, phone number, or email.
- View children linked to each parent.
- Link one parent to multiple students.
- Support multiple guardians per student where the existing system allows.
- View parent contact information.
- Import parents in bulk if needed.
- Track parent/student relationships.

### Parent Information Fields

- First Name.
- Middle Name.
- Last Name.
- Phone Number.
- Alternative Phone Number.
- Email Address.
- National ID Number.
- Gender.
- Relationship to Student (Father, Mother, Guardian, Other).
- Physical Address.
- Occupation.

### Parent Integration

The Parents module must automatically receive parent information from student bulk imports.

When a student is registered:
- If the parent already exists, link the student to that parent.
- If the parent does not exist, create a parent record.
- If the parent has multiple children, associate all children with the same parent record.
- Avoid duplicate parent records.

Changes to parent contact information should reflect wherever that parent is displayed in the system.

---

## 5. Staff Management – `/staff`

Create a dedicated `/staff` page to manage teachers and all other school employees.

This module should handle both teaching and non-teaching staff.

### Staff Bulk Import Template

The Excel/CSV template must contain exactly these core columns:

| Column | Description |
|---|---|
| NAME | Full name of the staff member |
| PHONE | Contact phone number |
| TITLE | Job title (e.g. Teacher, Principal, Accountant) |
| GENDER | Male/Female |
| NATIONAL_ID_NO | National identification number |
| EMPLOYEE NUMBER | Unique employee number |
| GROUP | Staff category/group |

These seven fields must be included in the downloadable template.

### Staff Categories (GROUP)

Support configurable groups such as:

- Teaching Staff.
- Non-Teaching Staff.
- Administration.
- Management.
- Support Staff.

Allow administrators to add additional groups.

### Staff Management Features

- Register individual staff members.
- Bulk upload staff using Excel/CSV.
- Download staff import template.
- Edit staff information.
- View staff profiles.
- Search and filter staff.
- Assign staff roles and categories.
- Activate/deactivate staff records.
- Identify duplicate employee numbers and national ID numbers.
- Import validation and error reporting.

### Additional System Fields

Where required by the existing application, support:
- Staff email.
- Employment date.
- Employment status.
- Department.
- User account association.

Do not change the seven core template columns.

---

## 6. Integration Between Modules

The four modules must operate as one connected system.

Implement the following relationships:

**Classes → Staff**
- Classes obtain their supervisors from registered teaching staff.
- Class supervisors are selected from `/staff`.
- Supervisor information is displayed on the Classes page.

**Classes → Students**
- Students are assigned to classes.
- Each class displays its allocated students.
- Student transfers update the relevant class records.

**Students → Parents**
- Student registration captures parent/guardian information.
- Bulk imports create or match parent records.
- Parents can have multiple children.

**Staff → Classes**
- Only active and eligible teaching staff can be assigned as class supervisors.
- Staff deactivation should trigger appropriate validation if the staff member supervises a class.

**Parents → Students**
- Parents can view all linked children.
- Changes to parent information should be reflected throughout the application.

---

## 7. Database Design

Review the existing database before creating or modifying tables.

Ensure appropriate relationships and avoid duplicating information.

Suggested entities:

- `classes`
- `students`
- `parents`
- `student_parent` (pivot/relationship table)
- `staff`
- `class_supervisors` (if supervisor history is required)
- `academic_years`

Use proper foreign keys, indexes, unique constraints, and soft deletes where appropriate.

Important considerations:
- Admission numbers should be unique within the appropriate school scope.
- Employee numbers should be unique within the school.
- National ID numbers should have appropriate uniqueness validation.
- A parent should be reusable across multiple students.
- Class assignments should preserve academic-year history.
- All records must respect the existing multi-tenant/school isolation architecture.

---

## 8. User Interface and Experience

Maintain the existing application's design system and navigation.

Each module should provide:

- Clean dashboard/listing view.
- Search and filters.
- Add/Edit forms.
- Bulk import button.
- Download template button.
- Import preview.
- Validation messages.
- Pagination.
- Confirmation dialogs.
- Empty states.
- Loading states.
- Responsive layouts.

Do not introduce a completely different UI framework or redesign unrelated sections.

---

## 9. Permissions and Security

Integrate with the existing authentication and role-based permission system.

Suggested permissions:

| Role | Permissions |
|---|---|
| School Admin | Full access to all four modules |
| Principal | Manage classes, staff, students and parents according to policy |
| Teacher | View assigned classes and their students |
| Registrar | Manage students and parents |
| HR/Admin | Manage staff records |
| Parent | View their linked children only |

Validate all imports on the backend.

Prevent unauthorized access to another school's records.

Use transactions during bulk imports so partially failed imports do not leave inconsistent relationships.

Log important operations such as imports, student transfers, supervisor changes, and staff updates.

---

## 10. Testing and Acceptance Criteria

Test the complete workflow, not just individual pages.

### Test Scenario 1: Create a Class
- Navigate to `/classes`.
- Create Grade 7 East.
- Select an existing teacher as supervisor.
- Save the class.
- Verify that the class appears in the listing.

### Test Scenario 2: Import Students
- Navigate to `/students`.
- Download the import template.
- Populate student details, class information, and parent information.
- Upload the Excel file.
- Review validation results.
- Confirm import.
- Verify that students are created and allocated to the correct class.

### Test Scenario 3: Verify Parents
- Navigate to `/parents`.
- Verify that parents from the student import appear.
- Verify that their children are correctly linked.
- Import another student with the same parent.
- Confirm that the existing parent record is reused.

### Test Scenario 4: Import Staff
- Navigate to `/staff`.
- Download the staff template.
- Upload a file containing teachers and non-teaching staff.
- Verify that all seven core fields are imported correctly.
- Verify that duplicates and invalid records are flagged.

### Test Scenario 5: Assign Class Supervisor
- Navigate to `/classes`.
- Open an existing class.
- Change its supervisor.
- Select a different eligible teacher.
- Save and verify the new assignment.

### Test Scenario 6: Data Consistency
- Transfer a student to another class.
- Verify that the student disappears from the old class and appears in the new class.
- Verify that parent relationships remain intact.
- Deactivate a teacher and verify that the system handles their supervised classes correctly.

---

## 11. Implementation Instructions

Follow these rules throughout development:

1. Inspect the existing codebase before making changes.
2. Reuse existing models, controllers, services, components, and APIs where possible.
3. Do not create duplicate database tables or conflicting relationships.
4. Preserve existing student, parent, class, and staff data.
5. Create database migrations for necessary changes.
6. Implement backend validation, not just frontend validation.
7. Support Excel and CSV imports with clear error reporting.
8. Use database transactions for bulk imports.
9. Preserve the existing multi-tenant architecture.
10. Do not break existing dashboards, authentication, subscriptions, or other school management features.

### Final Deliverables

- Fully functional `/classes` module.
- Fully functional `/students` module with bulk import.
- Fully functional `/parents` module.
- New `/staff` module with bulk import.
- Downloadable Excel/CSV templates.
- Correct database relationships.
- Integrated supervisor assignment.
- Complete bulk import validation and reporting.
- Automated tests for the main workflows.
- Documentation of database changes and implementation details.

**Important:** Do not just create four independent CRUD pages. Build a connected school data management workflow where classes, students, parents, and staff share consistent records and relationships.
