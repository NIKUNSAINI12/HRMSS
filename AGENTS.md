# Project Guidelines & Rules

## 1. Recruitment & Onboarding Architecture (16-Step CJ DARCL Flow)
- Build strictly step-by-step; do not jump ahead to future phases without user alignment.
- Zero touch to global `styles.scss`; all component styles must be strictly component-scoped.
- UI Design: Match the imported ATS Suite theme (`Work Sans`, `#f6f8fa`, `#3080e8` corporate action buttons with `#2b2b41` hover matching City Master, bento boxes, clean table structures).

## 2. Mandatory Audit Logging Rule (User Clicks & Actions)
- Maintain audit logging of every user click, action, and mutation:
  - **Who**: `userId`, `userCode`, `userName`, `role`.
  - **Where**: `pageRoute`, `pageTitle`, `elementTarget`.
  - **What**: `actionType` (`CLICK`, `ADD`, `UPDATE`, `DELETE`, `EXPORT`), `previousState`, `newState`, `recordIdentifier`.
  - **When**: Exact timestamp (IST + UTC).
- Ensure every master, form, and table modification retains user identity and audit timestamps.

## 3. Mandatory SQL Script Tracking Rule
- Any and all database schema modifications, table creations, alterations, stored procedures, or seed scripts **MUST** be saved as `.sql` files in the project `SQL/` directory (`d:\HRBook_18Sept_Code\SQL\`).
- Never perform silent database alterations without a corresponding, versioned script in `SQL/`.

## 4. Mandatory Company-Specific Scoping & Zero Hardcoding Rules
- **100% Company-Specific Queries**: Every SQL query, Stored Procedure (USP), Repository method, and Controller endpoint MUST filter by `CompanyId` / `fk_companyId`. Never query multi-tenant master tables without company scoping.
- **Zero Hardcoding Directive**: Absolutely NO hardcoded IDs (e.g. `'GU-1'`, `'1'`, fixed default fallback strings) in SQL scripts, USPs, C# Repositories, or Controllers. All IDs and fallback values must be dynamically retrieved from session context or database queries.
- **Universal Dropdown Standard**: All frontend dropdown controls MUST use the universal dropdown service / standard pattern (`Comm_SelectForDDL` / universal dropdown APIs) used across the HRMS portal.
- **Typography & Design System**: All UI components must use `Work Sans` font family, exact font size hierarchy (Headers: `11px`-`12px`, Body: `12px`-`13px`, Badges: `10px`-`11px`), `#f6f8fa` theme background, and `#3080e8` corporate action buttons (hover `#2b2b41` matching City Master / HRBook standard).

