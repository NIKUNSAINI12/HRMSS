-- =========================================================================================
-- Script: 41_CJ_DARCL_ATS_Talent_Suite_WebPages_And_PageRights.sql
-- Description:
--   Registers 'ATS Talent Suite' as a dynamic parent menu and registers all 9 ATS screens
--   as child web pages in dbo.UM_WebPage_Mst under Recruitment Management (Module ID 5).
--   Grants page rights in dbo.UM_UserPageRights to all authorized recruitment users and admins.
-- =========================================================================================

SET NOCOUNT ON;

DECLARE @moduleId TINYINT = 5; -- Recruitment Management
DECLARE @parentPageId INT;
DECLARE @maxPageId INT;

-- 1. Ensure Module 5 exists and is active
IF NOT EXISTS (SELECT 1 FROM dbo.UM_Module_Mst WHERE pk_moduleId = @moduleId)
BEGIN
    RAISERROR('Module ID 5 (Recruitment Management) does not exist.', 16, 1);
    RETURN;
END;

-- 2. Ensure or Insert Parent Menu: 'ATS Talent Suite'
SELECT @parentPageId = pk_webpageId 
FROM dbo.UM_WebPage_Mst 
WHERE menucaption = 'ATS Talent Suite' AND fk_moduleId = @moduleId;

IF @parentPageId IS NULL
BEGIN
    SELECT @maxPageId = ISNULL(MAX(pk_webpageId), 9000) FROM dbo.UM_WebPage_Mst;
    SET @parentPageId = @maxPageId + 1;

    INSERT INTO dbo.UM_WebPage_Mst (
        pk_webpageId,
        menucaption,
        webpagename,
        pagepath,
        tooltip,
        parentId,
        displayorder,
        activestatus,
        fk_moduleId,
        fk_pagetypeId,
        pagedescription,
        selectable,
        orderby,
        icon
    )
    VALUES (
        @parentPageId,
        'ATS Talent Suite',
        'NONE',
        '#',
        'ATS Talent Acquisition Suite',
        NULL,
        3, -- After Recruitment Masters (1) and Recruitment Transactions (2)
        1,
        @moduleId,
        1,
        'ATS Talent Acquisition Suite for CJ DARCL Logistics',
        1,
        3,
        'feather feather-users'
    );

    PRINT 'Created Parent Menu: ATS Talent Suite (pk_webpageId: ' + CAST(@parentPageId AS VARCHAR(10)) + ')';
END
ELSE
BEGIN
    PRINT 'Parent Menu ATS Talent Suite already exists (pk_webpageId: ' + CAST(@parentPageId AS VARCHAR(10)) + ')';
END;

-- 3. Temporary table for the 9 child pages
DECLARE @Pages TABLE (
    menucaption     VARCHAR(100),
    webpagename     VARCHAR(100),
    pagepath        VARCHAR(100),
    tooltip         VARCHAR(100),
    displayorder    INT,
    icon            VARCHAR(50)
);

INSERT INTO @Pages (menucaption, webpagename, pagepath, tooltip, displayorder, icon)
VALUES
('Jobs Directory',      'MRFJobsDirectory',        'recruitment/recruitmentdashboard/mrf-list',                   'MRF & Jobs Directory',        1, 'bi bi-card-list me-2'),
('Create Job',          'CreateJobWizard',           'recruitment/recruitmentdashboard/create-job-wizard',          'Create Job Wizard',           2, 'bi bi-plus-circle me-2'),
('Approvals',           'RequisitionApprovals',       'recruitment/recruitmentdashboard/job-management',             'Requisition Approvals',       3, 'bi bi-check2-circle me-2'),
('Headcount & Buffer',  'LocationHeadcountBuffer', 'recruitment/recruitmentdashboard/location-manpower-headcount', 'Location Headcount & Buffer', 4, 'bi bi-geo-alt me-2'),
('Pipeline',            'CandidatePipeline',          'recruitment/recruitmentdashboard/pipeline',                   'Candidate Pipeline',          5, 'bi bi-kanban me-2'),
('Job Boards',          'JobBoardsManager',          'recruitment/recruitmentdashboard/job-boards',                 'Job Boards Manager',          6, 'bi bi-share me-2'),
('Analytics',           'HiringAnalytics',            'recruitment/recruitmentdashboard/analytics',                  'Hiring Analytics',            7, 'bi bi-graph-up me-2'),
('Vendor Portal',       'VendorSourcingPortal',      'recruitment/recruitmentdashboard/vendor-portal',              'Vendor Sourcing Portal',      8, 'bi bi-person-lines-fill me-2'),
('Talent Pool',         'CandidateTalentPool',       'recruitment/recruitmentdashboard/vendor-candidates',          'Candidate Talent Pool',       9, 'bi bi-people-fill me-2');

-- 4. Cursor / Loop to insert child pages
DECLARE @curCaption VARCHAR(100), @curPageName VARCHAR(100), @curPath VARCHAR(100), @curTip VARCHAR(100), @curOrder INT, @curIcon VARCHAR(50);
DECLARE @newPageId INT;

DECLARE page_cursor CURSOR FOR 
SELECT menucaption, webpagename, pagepath, tooltip, displayorder, icon FROM @Pages ORDER BY displayorder;

OPEN page_cursor;
FETCH NEXT FROM page_cursor INTO @curCaption, @curPageName, @curPath, @curTip, @curOrder, @curIcon;

WHILE @@FETCH_STATUS = 0
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.UM_WebPage_Mst WHERE menucaption = @curCaption AND fk_moduleId = @moduleId)
    BEGIN
        SELECT @maxPageId = ISNULL(MAX(pk_webpageId), 9000) FROM dbo.UM_WebPage_Mst;
        SET @newPageId = @maxPageId + 1;

        INSERT INTO dbo.UM_WebPage_Mst (
            pk_webpageId,
            menucaption,
            webpagename,
            pagepath,
            tooltip,
            parentId,
            displayorder,
            activestatus,
            fk_moduleId,
            fk_pagetypeId,
            pagedescription,
            selectable,
            orderby,
            icon
        )
        VALUES (
            @newPageId,
            @curCaption,
            @curPageName,
            @curPath,
            @curTip,
            @parentPageId,
            @curOrder,
            1,
            @moduleId,
            1,
            @curCaption + ' (Recruitment Management)',
            1,
            @curOrder,
            @curIcon
        );

        PRINT 'Inserted WebPage: ' + @curCaption + ' (pk_webpageId: ' + CAST(@newPageId AS VARCHAR(10)) + ')';
    END
    ELSE
    BEGIN
        -- Update existing record to guarantee parentId, path, and icon are correct
        UPDATE dbo.UM_WebPage_Mst
        SET parentId     = @parentPageId,
            pagepath     = @curPath,
            displayorder = @curOrder,
            activestatus = 1,
            icon         = @curIcon
        WHERE menucaption = @curCaption AND fk_moduleId = @moduleId;

        PRINT 'Updated WebPage: ' + @curCaption;
    END;

    FETCH NEXT FROM page_cursor INTO @curCaption, @curPageName, @curPath, @curTip, @curOrder, @curIcon;
END;

CLOSE page_cursor;
DEALLOCATE page_cursor;

-- 5. Grant Page Rights to all users associated with Recruitment Module or active admin/HR roles
-- Gather all relevant users:
DECLARE @TargetUsers TABLE (fk_userId VARCHAR(15));

INSERT INTO @TargetUsers (fk_userId)
SELECT DISTINCT fk_userId FROM dbo.UM_UserModuleDetails WHERE fk_moduleId = @moduleId
UNION
SELECT DISTINCT fk_userId FROM dbo.UM_UserPageRights WHERE fk_webpageId IN (SELECT pk_webpageId FROM dbo.UM_WebPage_Mst WHERE fk_moduleId = @moduleId)
UNION
SELECT pk_userId FROM dbo.UM_Users_Mst WHERE pk_userId IN ('GU-1', 'GU-15', 'GU-7') AND active = 1;

-- All ATS web page IDs (parent + 9 children)
DECLARE @TargetPages TABLE (pk_webpageId INT);
INSERT INTO @TargetPages (pk_webpageId)
SELECT pk_webpageId FROM dbo.UM_WebPage_Mst 
WHERE parentId = @parentPageId OR pk_webpageId = @parentPageId;

-- Insert into UM_UserPageRights if missing
INSERT INTO dbo.UM_UserPageRights (
    fk_userId,
    fk_webpageId,
    AllowAdd,
    AllowUpdate,
    AllowDelete,
    AllowView
)
SELECT 
    u.fk_userId,
    p.pk_webpageId,
    1, 1, 1, 1
FROM @TargetUsers u
CROSS JOIN @TargetPages p
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.UM_UserPageRights r 
    WHERE r.fk_userId = u.fk_userId AND r.fk_webpageId = p.pk_webpageId
);

PRINT 'Page rights successfully granted for ATS Talent Suite.';

-- 6. Verification output
SELECT 
    WPM.pk_webpageId,
    WPM.menucaption,
    WPM.pagepath,
    WPM.parentId,
    WPM.displayorder,
    WPM.icon,
    COUNT(UPR.pk_pagerightid) AS AssignedUsersCount
FROM dbo.UM_WebPage_Mst WPM
LEFT JOIN dbo.UM_UserPageRights UPR ON UPR.fk_webpageId = WPM.pk_webpageId
WHERE WPM.parentId = @parentPageId OR WPM.pk_webpageId = @parentPageId
GROUP BY 
    WPM.pk_webpageId,
    WPM.menucaption,
    WPM.pagepath,
    WPM.parentId,
    WPM.displayorder,
    WPM.icon
ORDER BY WPM.parentId, WPM.displayorder;
