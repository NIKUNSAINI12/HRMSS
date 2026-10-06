# Rule: Mandatory SQL Script Tracking

## Rule Statement
Any and all database schema modifications, table creations, alterations, stored procedures, index updates, and seed data changes **MUST** be written and saved into the project's dedicated `SQL/` directory (`d:\HRBook_18Sept_Code\SQL`).

## Standards
1. **Directory**: `d:\HRBook_18Sept_Code\SQL/`
2. **Naming Convention**: Use sequential and descriptive names:
   - Example: `01_REC_Location_Manpower_Master.sql`
   - Example: `02_REC_Location_Manpower_Audit_Trigger.sql`
3. **Script Contents**:
   - Standard idempotent SQL checks (`IF NOT EXISTS...`).
   - Detailed column comments and constraints (primary key, foreign keys to `Location_Mst`, defaults).
   - Audit trail columns (`CreatedBy`, `CreatedDate`, `ModifiedBy`, `ModifiedDate`, `IsActive`).
   - Rollback / verification comments.
4. **Execution Log**:
   - Keep a running record of when scripts are executed against database `HRBook_22`.
