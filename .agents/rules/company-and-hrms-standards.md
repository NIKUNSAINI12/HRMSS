# Enterprise Architecture & Development Standards

## 1. 100% Company-Specific Queries
- Every SQL query, Stored Procedure (USP), Repository method, and WebAPI controller MUST filter data by `CompanyId` / `fk_companyId`.
- Always pass `decryptedCompanyId` from `HttpContext.Items["DecryptedCompanyId"]` to repositories and stored procedures.
- SQL Stored Procedures must accept `@CompanyId` / `@fk_companyId` parameter and apply `WHERE fk_companyId = @CompanyId`.

## 2. Zero Hardcoding Directive
- Absolutely ZERO hardcoded IDs (e.g. `'GU-1'`, `'1'`, default fallback strings) in SQL scripts, USPs, C# Repositories, or Controllers.
- All default values, user locations, user IDs, and master references must be dynamically queried or fetched from session context.

## 3. Universal Dropdown Standard
- All frontend dropdown controls MUST use the universal dropdown service / standard pattern (`Comm_SelectForDDL` / universal dropdown APIs) used across the HRMS portal.

## 4. Typography & Design Consistency
- Match the HRMS ATS Suite theme:
  - Font Family: `Work Sans`
  - Theme Background: `#f6f8fa`
  - Action Buttons: `#0051d5` corporate blue
  - Table & Bento Box Styling: Consistent font sizes (Headers: `11px`-`12px`, Body: `12px`-`13px`, Badges: `10px`-`11px`).
