# User Interaction & Click Audit Logging Rule

## 1. Overview & Mandate
All user interactions across the application (especially recruitment, masters, and administrative modules) must support comprehensive **Click & Action Audit Logging**.
Every user action must log **who** did it, **what** action they took, on **which page/route**, at what **timestamp**, and the **target entity/record** affected.

---

## 2. Required Audit Payload Structure
Whenever user interaction logging is triggered, capture the following parameters:

| Field | Description | Example |
| :--- | :--- | :--- |
| `userId` / `userCode` | Unique ID/Code of the logged-in user | `EMP-1049` / `admin@cjdarcl.com` |
| `userName` | Display name and role of the actor | `Principal Employer Admin` |
| `pageRoute` | Exact client route at moment of click | `/dash/recruitment/recruitmentdashboard/location-manpower-headcount` |
| `pageTitle` | Human-readable title of the active screen | `Location Manpower & Buffer Master` |
| `actionType` | Categorized user action | `CLICK`, `ADD_RECORD`, `UPDATE_BUFFER`, `DELETE_RECORD`, `EXPORT_CSV` |
| `elementTarget` | Identifier or label of clicked UI element | `btn-save-master-record`, `inline-buffer-select` |
| `entityName` | Database / domain entity affected | `Location_Mst` / `LocationManpowerMaster` |
| `recordIdentifier` | Target entity key or business code | `GU-146 (Bhiwandi Central Fulfillment)` |
| `previousState` | Prior value before edit (for audit diff) | `{ bufferPercentage: 10, baseRequired: 310 }` |
| `newState` | New value applied | `{ bufferPercentage: 15, baseRequired: 310 }` |
| `timestamp` | Exact timestamp in ISO format | `2026-09-22T14:44:00+05:30` |
| `clientIp` | Client network / device context | `10.1.16.5` / Browser Agent |

---

## 3. Implementation Guidelines for Antigravity Agent
1. **Always preserve audit logging context**: When creating or modifying pages, forms, or actions, record user details (`lastUpdatedBy: 'Principal Employer Admin'`, `lastUpdatedDate`, audit remarks).
2. **Global Click Interceptor / Service**: In future steps, wire a shared `AuditLoggerService` that hooks into Angular router events and UI click events to dispatch audit records to backend audit endpoints.
3. **No Silent Mutations**: Any change to headcount, buffer %, salary, qualification, or status must produce an audit log entry.
