-- ============================================================================
-- CJ DARCL Recruitment Architecture: Save Requisition with Approver & Team
-- Stored Procedure: dbo.usp_REC_SaveJobRequisition
-- Persists Hiring Manager, Lead Recruiter, Panelists, and L1 Approver
-- ============================================================================

USE [HRBook_22];
GO

CREATE OR ALTER PROCEDURE dbo.usp_REC_SaveJobRequisition
    @JobTitle            NVARCHAR(200),
    @ServiceType         NVARCHAR(100) = NULL,
    @Designation         NVARCHAR(150) = NULL,
    @SkillCategory       NVARCHAR(100) = NULL,
    @OpenPositions       INT           = 1,
    @Location            NVARCHAR(150) = NULL,
    @Department          NVARCHAR(150) = NULL,
    @HiringType          NVARCHAR(50)  = 'New',
    @IsDiversityHiring   BIT           = NULL,
    @DiversityCategory   VARCHAR(MAX)  = NULL,
    @WorkplaceType       NVARCHAR(50)  = 'On-Site',
    @EmploymentType      NVARCHAR(50)  = 'Full-Time',
    @ExperienceMin       DECIMAL(5,2)  = NULL,
    @ExperienceMax       DECIMAL(5,2)  = NULL,
    @CtcMin              DECIMAL(12,2) = NULL,
    @CtcMax              DECIMAL(12,2) = NULL,
    @Currency            NVARCHAR(10)  = 'INR',
    @Priority            NVARCHAR(50)  = 'Medium',
    @TargetStartDate     NVARCHAR(50)  = NULL,
    @EducationLevel      NVARCHAR(100) = NULL,
    @PrimarySkills       NVARCHAR(MAX) = NULL,
    @SecondarySkills     NVARCHAR(MAX) = NULL,
    @NoticePeriodMaxDays INT           = NULL,
    @Industry            NVARCHAR(100) = 'Logistics & Supply Chain',
    @JobDescription      NVARCHAR(MAX) = NULL,
    @Responsibilities    NVARCHAR(MAX) = NULL,
    @Qualifications      NVARCHAR(MAX) = NULL,
    @Benefits            NVARCHAR(MAX) = NULL,
    @HiringManager       NVARCHAR(150) = NULL,
    @HiringManagerId     NVARCHAR(50)  = NULL,
    @LeadRecruiter       NVARCHAR(150) = NULL,
    @LeadRecruiterId     NVARCHAR(50)  = NULL,
    @L1ApproverName      NVARCHAR(200) = NULL,
    @L1ApproverId        NVARCHAR(50)  = NULL,
    @Interviewers        NVARCHAR(MAX) = NULL,
    @IsDraft             BIT           = 0,
    @IsBufferUtilized    BIT           = 0,
    @BufferHeadsUtilized INT           = 0,
    @SubmittedBy         NVARCHAR(150) = 'Site HR Admin',
    @SubmittedById       NVARCHAR(50)  = NULL,
    @CompanyId           NVARCHAR(50)  = NULL,
    @fk_companyId        NVARCHAR(50)  = NULL,
    -- Specific Foreign Key IDs from Employee Master Standard Dropdowns
    @fk_locid            NVARCHAR(50)  = NULL,
    @fk_deptid           NVARCHAR(50)  = NULL,
    @fk_subdeptid        NVARCHAR(50)  = NULL,
    @fk_desgid           NVARCHAR(50)  = NULL,
    @fk_classid          NVARCHAR(50)  = NULL, -- Grade
    @fk_catid            NVARCHAR(50)  = NULL, -- Category
    @fk_costcentreid     BIGINT        = NULL, -- Cost Center
    @fk_zoneId           NVARCHAR(50)  = NULL,
    @fk_cityid           NVARCHAR(50)  = NULL,
    @BusinessVertical    NVARCHAR(150) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Normalize Company ID
    IF (@CompanyId IS NULL OR @CompanyId = '') AND (@fk_companyId IS NOT NULL AND @fk_companyId <> '')
        SET @CompanyId = @fk_companyId;
    IF (@fk_companyId IS NULL OR @fk_companyId = '') AND (@CompanyId IS NOT NULL AND @CompanyId <> '')
        SET @fk_companyId = @CompanyId;

    -- Dynamic Lookup location ID if not explicitly provided
    IF @fk_locid IS NULL OR @fk_locid = ''
    BEGIN
        SELECT TOP 1 
            @fk_locid = pk_locid,
            @CompanyId = COALESCE(@CompanyId, fk_companyId),
            @fk_companyId = COALESCE(@fk_companyId, fk_companyId)
        FROM dbo.Location_Mst WITH (NOLOCK)
        WHERE locname = @Location OR pk_locid = @Location OR locationCode = @Location;
    END
    ELSE
    BEGIN
        -- Also populate location name if missing
        IF @Location IS NULL OR @Location = ''
        BEGIN
            SELECT TOP 1 @Location = locname FROM dbo.Location_Mst WITH (NOLOCK) WHERE pk_locid = @fk_locid;
        END;
    END;

    -- Dynamic Lookup designation ID if not explicitly provided
    IF @fk_desgid IS NULL OR @fk_desgid = ''
    BEGIN
        SELECT TOP 1 @fk_desgid = pk_desgid 
        FROM dbo.SAL_Designation_Mst WITH (NOLOCK)
        WHERE designation = @Designation OR pk_desgid = @Designation;
    END
    ELSE
    BEGIN
        IF @Designation IS NULL OR @Designation = ''
        BEGIN
            SELECT TOP 1 @Designation = designation FROM dbo.SAL_Designation_Mst WITH (NOLOCK) WHERE pk_desgid = @fk_desgid;
        END;
    END;

    -- Dynamic Lookup department ID if not explicitly provided
    IF @fk_deptid IS NULL OR @fk_deptid = ''
    BEGIN
        SELECT TOP 1 @fk_deptid = pk_deptid 
        FROM dbo.Department_Mst WITH (NOLOCK)
        WHERE description = @Department OR pk_deptid = @Department;
    END
    ELSE
    BEGIN
        IF @Department IS NULL OR @Department = ''
        BEGIN
            SELECT TOP 1 @Department = description FROM dbo.Department_Mst WITH (NOLOCK) WHERE pk_deptid = @fk_deptid;
        END;
    END;

    -- Default user ID if null
    IF @SubmittedById IS NULL OR @SubmittedById = ''
        SET @SubmittedById = '1';

    -- Format Status and MRF Code
    DECLARE @statusChar CHAR(1) = CASE WHEN @IsDraft = 1 THEN 'D' WHEN @IsBufferUtilized = 1 THEN 'B' ELSE 'P' END;
    DECLARE @requisitionStatus NVARCHAR(50) = CASE WHEN @IsDraft = 1 THEN 'Draft' WHEN @IsBufferUtilized = 1 THEN 'Pending Buffer Approval' ELSE 'Pending Approval' END;
    DECLARE @remarks NVARCHAR(500) = CONCAT('HM: ', @HiringManager, ' | Recruiter: ', @LeadRecruiter, ' | Approver: ', @L1ApproverName, ' | Sub: ', @SubmittedBy);
    
    DECLARE @GeneratedMrfCode NVARCHAR(100) = CONCAT('MRF/', YEAR(GETDATE()), '/', RIGHT('0000' + CAST(ABS(CHECKSUM(NEWID())) % 10000 AS VARCHAR(4)), 4));

    -- Insert Requisition Record with All Employee Master Standard Dropdowns
    INSERT INTO dbo.REC_JobRequisition_Mst (
        jobtitle, fk_locid, fk_deptid, fk_desgid, fk_classid, fk_costcentreid,
        fk_subdeptid, fk_catid, fk_zoneId, fk_cityid, BusinessVertical,
        HiringManagerId, LeadRecruiterId, L1ApproverId, L1ApproverName,
        No_of_post, dated, status,
        RequisitionStatus, Reason_of_Requirement, ServiceType, SkillCategory,
        IsDiversityHiring, DiversityCategory, WorkplaceType, EmploymentType,
        Experience_From, Experience_To, CTC_From, CTC_To, Currency, Priority,
        TargetStartDate, EducationLevel, PrimarySkills, SecondarySkills,
        NoticePeriodMaxDays, Industry, JobDescription, Justification_of_Position,
        Roles_Responsibilities, quali, Benefits, HiringManager, LeadRecruiter,
        Interviewers, IsBufferUtilized, BufferHeadsUtilized, SubmittedBy, SubmittedById,
        Mrfcode, Remarks,
        WorkflowStatus, CurrentApprovalLevel, SubmittedDate, LastWorkflowActionDate,
        CompanyId, fk_companyId
    ) VALUES (
        @JobTitle, @fk_locid, @fk_deptid, @fk_desgid, @fk_classid, @fk_costcentreid,
        @fk_subdeptid, @fk_catid, @fk_zoneId, @fk_cityid, @BusinessVertical,
        @HiringManagerId, @LeadRecruiterId, @L1ApproverId, @L1ApproverName,
        @OpenPositions, GETDATE(), @statusChar,
        @requisitionStatus, @HiringType, @ServiceType, @SkillCategory,
        @IsDiversityHiring, @DiversityCategory, @WorkplaceType, @EmploymentType,
        @ExperienceMin, @ExperienceMax, @CtcMin, @CtcMax, @Currency, @Priority,
        @TargetStartDate, @EducationLevel, @PrimarySkills, @SecondarySkills,
        @NoticePeriodMaxDays, @Industry, @JobDescription, @JobDescription,
        @Responsibilities, @Qualifications, @Benefits, @HiringManager, @LeadRecruiter,
        @Interviewers, @IsBufferUtilized, @BufferHeadsUtilized, @SubmittedBy, @SubmittedById,
        @GeneratedMrfCode, @remarks,
        'L1_Pending', 1, GETDATE(), GETDATE(),
        @CompanyId, @fk_companyId
    );

    DECLARE @NewReqId BIGINT = SCOPE_IDENTITY();

    -- Insert initial submit audit log in REC_JobRequisition_Mst_Approval with Company Mapping
    INSERT INTO dbo.REC_JobRequisition_Mst_Approval (
        fk_reqid, fk_empId, dated, approvelOrder, remarks, isActive, 
        approvalLevel, action, approverName, approverRole, workflowStatus,
        CompanyId, fk_companyId
    ) VALUES (
        @NewReqId, @SubmittedById, GETDATE(), 0, 'Requisition submitted for approval', 1, 
        0, 'Submitted', @SubmittedBy, 'Site HR', 'L1_Pending',
        @CompanyId, @fk_companyId
    );

    -- Mandatory Audit Logging: Insert into CL_UpdateAudit_Log
    BEGIN TRY
        INSERT INTO dbo.CL_UpdateAudit_Log (
            DocumentId, DocumentCode, DocumentName, FieldName,
            PreviousValue, CurrentValue, EntryBy, EntryDate
        ) VALUES (
            @NewReqId, @GeneratedMrfCode, 'REC_JobRequisition_Mst', 'WorkflowStatus',
            'None', 'L1_Pending', @SubmittedBy, GETDATE()
        );
    END TRY
    BEGIN CATCH
        -- Non-blocking audit log catch
    END CATCH;

    -- Return the result
    SELECT 
        1 AS Success,
        @NewReqId AS reqId, 
        @GeneratedMrfCode AS mrfCode,
        CASE WHEN @IsDraft = 1 THEN 'Draft saved successfully' ELSE 'Manpower requisition raised successfully — sent for L1 approval' END AS Message;
END;
GO
