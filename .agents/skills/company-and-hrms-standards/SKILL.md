---
name: company-and-hrms-standards
description: >-
  Enforces mandatory HRMS enterprise guidelines: 100% company-specific SQL queries,
  zero hardcoding across USPs/Repos/Controllers, universal dropdown usage, and 
  consistent ATS theme typography and design standards.
---

# Enterprise Architecture & Coding Standards (HRMS Suite)

This skill documents and enforces mandatory coding, database, and UI standards across the entire HRMS project.

---

## 1. 100% Company-Specific Queries (Mandatory `CompanyId` Scoping)

- **Rule**: Every single SQL query, Stored Procedure, Repository method, and API endpoint MUST filter data by `CompanyId` / `fk_companyId`.
- **Backend (C# Controllers & Repos)**:
  - Retrieve `CompanyId` dynamically from request context: `var decryptedCompanyId = HttpContext.Items["DecryptedCompanyId"]?.ToString();`.
  - Pass `@CompanyId` / `fk_companyId` to all stored procedures and repository methods.
- **SQL Stored Procedures**:
  - Accept `@CompanyId` / `@fk_companyId` parameter.
  - Include `WHERE fk_companyId = @CompanyId` (or `WHERE (fk_companyId = @CompanyId OR @CompanyId IS NULL)` when multi-tenant fallback is required).
- **Prohibited**: Never execute multi-tenant table queries (`Location_Mst`, `Department_Mst`, `SAL_Designation_Mst`, `REC_JobRequisition_Mst`, `SAL_Employee_Mst`, etc.) without company filtering.

---

## 2. Zero Hardcoding Directive (100% Dynamic Execution)

- **Rule**: Absolutely ZERO hardcoded IDs, fallbacks, or static literal values in SQL scripts/USPs, C# Repositories, or Controllers.
- **Forbidden Examples**:
  - `SET @fk_locid = 'GU-1'` $\rightarrow$ **STRICTLY FORBIDDEN**.
  - `SubmittedById = '1'` $\rightarrow$ **STRICTLY FORBIDDEN**.
  - Static fallback emails, static company IDs, or hardcoded master keys.
- **Mandatory Dynamic Standard**:
  - Always resolve default locations, user IDs, designations, and parameters dynamically via logged-in user context (`HttpContext.Items["DecryptedUserId"]`, `HttpContext.Items["DecryptedCompanyId"]`) or via database lookup queries based on the active user session.

---

## 3. Universal Dropdown Standard

- **Rule**: All frontend dropdown selectors must consume the universal dropdown mechanism and APIs (`Comm_SelectForDDL` / universal dropdown endpoint) used across the HRMS portal.
- **Implementation**:
  - Avoid inline or isolated static dropdown lists in component TS files unless explicitly static system masters (e.g. Yes/No).
  - Use standardized dropdown services (`ManpowerRequisitionService.getDropdownData`, universal master lookup endpoints) with standard payload signatures (`{ name: string, value: string }`).

---

## 4. UI Design System, Typography & Font Consistency

- **Rule**: All Angular components, forms, tables, modal dialogs, and bento cards MUST adhere strictly to the ATS Suite design system.
- **Typography & Font Family**:
  - Font Family: `Work Sans`, sans-serif.
  - Font Sizes:
    - Page Title: `18px` – `20px` (Font Weight: `700`).
    - Section / Card Title: `14px` – `15px` (Font Weight: `600`).
    - Table Headers: `11px` – `12px` (Uppercase, Font Weight: `600`, letter-spacing: `0.5px`).
    - Body / Table Cell Text: `12px` – `13px` (Font Weight: `400` / `500`).
    - Subtext / Badges / Labels: `10px` – `11px`.
- **Color Palette & UI Components**:
  - Background: Clean enterprise gray `#f6f8fa`.
  - Corporate Action Buttons: Primary Blue `#0051d5` (hover `#0040ab`).
  - Table Structures: Clean borders (`#e2e8f0`), compact row height, crisp index columns.
  - Bento KPI Cards: Glassmorphism / clean subtle borders (`#e2e8f0`), rounded corners (`8px`), metric values (`22px` - `24px` bold).
