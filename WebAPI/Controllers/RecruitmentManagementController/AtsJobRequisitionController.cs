using Dapper;
using HRMSWebAPI.Helper;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Data;
using System.Text.Json;

namespace HRMSWebAPI.Controllers.RecruitmentManagementController
{
    [Route("api/v1/[controller]")]
    [ApiController]
    [AllowAnonymous]
    public class AtsJobRequisitionController : ControllerBase
    {
        /// <summary>
        /// Retrieves master data for creating/editing a requisition:
        /// Departments, Locations (with Buffer Metrics), Designations, Employees,
        /// and default user location prefill.
        /// Stored Procedure: dbo.usp_REC_GetRequisitionMasterData
        /// </summary>
        [HttpGet("GetRequisitionMasterData")]
        public async Task<IActionResult> GetRequisitionMasterData(
            [FromQuery] string? userId = null,
            [FromQuery] string? loginName = null,
            [FromQuery] string? companyId = null)
        {
            try
            {
                var decryptedCompanyId = HttpContext.Items["DecryptedCompanyId"]?.ToString();
                if (!string.IsNullOrEmpty(decryptedCompanyId))
                {
                    companyId = decryptedCompanyId;
                }

                using var conn = DataBaseFactory.ConnString();

                using var multi = await conn.QueryMultipleAsync(
                    "dbo.usp_REC_GetRequisitionMasterData",
                    new { UserId = userId, LoginName = loginName, CompanyId = companyId },
                    commandType: CommandType.StoredProcedure);

                var depts = await multi.ReadAsync<dynamic>();
                var locs = await multi.ReadAsync<dynamic>();
                var desigs = await multi.ReadAsync<dynamic>();
                var emps = await multi.ReadAsync<dynamic>();
                var defaultLoc = await multi.ReadFirstOrDefaultAsync<dynamic>();

                return Ok(new
                {
                    departments = depts,
                    locations = locs,
                    designations = desigs,
                    employees = emps,
                    defaultLocationId = defaultLoc?.defaultLocationId?.ToString(),
                    defaultLocationName = defaultLoc?.defaultLocationName?.ToString()
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Error fetching master data", error = ex.Message });
            }
        }

        /// <summary>
        /// Retrieves all job requisitions with workflow approval status.
        /// Stored Procedure: dbo.usp_REC_GetJobRequisitions
        /// </summary>
        [HttpGet("GetJobRequisitions")]
        public async Task<IActionResult> GetJobRequisitions([FromQuery] string? companyId = null)
        {
            try
            {
                var decryptedCompanyId = HttpContext.Items["DecryptedCompanyId"]?.ToString();
                var scopedCompanyId = !string.IsNullOrEmpty(decryptedCompanyId) ? decryptedCompanyId : companyId;

                using var conn = DataBaseFactory.ConnString();

                var jobs = await conn.QueryAsync<dynamic>(
                    "dbo.usp_REC_GetJobRequisitions",
                    new { CompanyId = scopedCompanyId },
                    commandType: CommandType.StoredProcedure);

                return Ok(jobs);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Error fetching job requisitions", error = ex.Message });
            }
        }

        /// <summary>
        /// Persists all wizard fields into REC_JobRequisition_Mst, initializes L1 workflow,
        /// and writes initial approval and audit logs.
        /// Stored Procedure: dbo.usp_REC_SaveJobRequisition
        /// </summary>
        [HttpPost("SaveJobRequisition")]
        public async Task<IActionResult> SaveJobRequisition([FromBody] JsonElement payload)
        {
            try
            {
                using var conn = DataBaseFactory.ConnString();

                string jobTitle = GetSafeString(payload, "jobTitle");
                string serviceType = GetSafeString(payload, "serviceType");
                string designation = GetSafeString(payload, "designation");
                string skillCategory = GetSafeString(payload, "skillCategory");
                int openPositions = GetSafeInt(payload, "openPositions") ?? 1;
                string location = GetSafeString(payload, "location");
                string department = GetSafeString(payload, "department");
                string hiringType = GetSafeString(payload, "hiringType", "New");
                bool? isDiversityHiring = null;
                if (payload.TryGetProperty("isDiversityHiring", out var idh) && idh.ValueKind != JsonValueKind.Null && idh.ValueKind != JsonValueKind.Undefined)
                {
                    if (idh.ValueKind == JsonValueKind.True || idh.ValueKind == JsonValueKind.False)
                        isDiversityHiring = idh.GetBoolean();
                    else if (bool.TryParse(idh.GetString(), out var bVal))
                        isDiversityHiring = bVal;
                }
                string diversityCategory = GetSafeString(payload, "diversityCategory");
                
                string workplaceType = GetSafeString(payload, "workplaceType", "On-Site");
                string employmentType = GetSafeString(payload, "employmentType", "Full-Time");
                
                decimal? experienceMin = GetSafeDecimal(payload, "experienceMin");
                decimal? experienceMax = GetSafeDecimal(payload, "experienceMax");
                decimal? ctcMin = GetSafeDecimal(payload, "ctcMin");
                decimal? ctcMax = GetSafeDecimal(payload, "ctcMax");
                
                string currency = GetSafeString(payload, "currency", "INR");
                string priority = GetSafeString(payload, "priority", "Medium");
                string targetStartDate = GetSafeString(payload, "targetStartDate");
                string educationLevel = GetSafeString(payload, "educationLevel");
                string primarySkills = GetSafeString(payload, "primarySkills");
                string secondarySkills = GetSafeString(payload, "secondarySkills");
                int? noticePeriodMaxDays = GetSafeInt(payload, "noticePeriodMaxDays");
                string industry = GetSafeString(payload, "industry", "Logistics & Supply Chain");
                
                string jobDescription = GetSafeString(payload, "jobDescription");
                string responsibilities = GetSafeString(payload, "responsibilities");
                string qualifications = GetSafeString(payload, "qualifications");
                string benefits = GetSafeString(payload, "benefits");
                
                string hiringManager = GetSafeString(payload, "hiringManager");
                string hiringManagerId = GetSafeString(payload, "hiringManagerId");
                string leadRecruiter = GetSafeString(payload, "leadRecruiter");
                string leadRecruiterId = GetSafeString(payload, "leadRecruiterId");
                string l1Approver = GetSafeString(payload, "l1Approver");
                if (string.IsNullOrWhiteSpace(l1Approver))
                {
                    l1Approver = GetSafeString(payload, "l1ApproverName");
                }
                string l1ApproverId = GetSafeString(payload, "l1ApproverId");

                string fk_locid = GetSafeString(payload, "fk_locid");
                string fk_deptid = GetSafeString(payload, "fk_deptid");
                string fk_subdeptid = GetSafeString(payload, "fk_subdeptid");
                string fk_desgid = GetSafeString(payload, "fk_desgid");
                string fk_classid = GetSafeString(payload, "fk_classid");
                string fk_catid = GetSafeString(payload, "fk_catid");
                long? fk_costcentreid = GetSafeLong(payload, "fk_costcentreid");
                string fk_zoneId = GetSafeString(payload, "fk_zoneId");
                string fk_cityid = GetSafeString(payload, "fk_cityid");
                string businessVertical = GetSafeString(payload, "businessVertical");
                
                string interviewers = "";
                if (payload.TryGetProperty("interviewers", out var inv) && inv.ValueKind == JsonValueKind.Array)
                {
                    var list = new List<string>();
                    foreach (var item in inv.EnumerateArray())
                    {
                        if (item.ValueKind == JsonValueKind.String)
                        {
                            var s = item.GetString();
                            if (!string.IsNullOrWhiteSpace(s))
                                list.Add(s.Trim());
                        }
                    }
                    interviewers = string.Join(", ", list);
                }

                bool isDraft = GetSafeBool(payload, "isDraft");
                bool isBufferUtilized = GetSafeBool(payload, "isBufferUtilized");
                int bufferHeadsUtilized = GetSafeInt(payload, "bufferHeadsUtilized") ?? 0;
                string submittedBy = GetSafeString(payload, "submittedBy");
                string submittedById = GetSafeString(payload, "submittedById");
                string decryptedUserId = HttpContext.Items["DecryptedUserId"]?.ToString();
                if (!string.IsNullOrWhiteSpace(decryptedUserId))
                {
                    decryptedUserId = decryptedUserId.Replace("GU-", "", StringComparison.OrdinalIgnoreCase).Trim();
                }

                if (string.IsNullOrWhiteSpace(submittedById) || submittedById == "1")
                {
                    if (!string.IsNullOrWhiteSpace(decryptedUserId))
                    {
                        submittedById = decryptedUserId;
                    }
                }

                // If submittedBy is missing or default fallback, look up real name from UM_Users_Mst / SAL_Employee_Mst via Stored Procedure (Zero Inline SQL)
                if (string.IsNullOrWhiteSpace(submittedBy) || submittedBy.Equals("Site HR Admin", StringComparison.OrdinalIgnoreCase) || submittedBy.Equals("Site HR", StringComparison.OrdinalIgnoreCase))
                {
                    try
                    {
                        var userRecord = await conn.QueryFirstOrDefaultAsync<dynamic>(
                            "dbo.usp_UM_ResolveUserName",
                            new { UserId = submittedById },
                            commandType: CommandType.StoredProcedure);

                        if (userRecord != null && !string.IsNullOrWhiteSpace((string)userRecord.ResolvedName))
                        {
                            submittedBy = (string)userRecord.ResolvedName;
                        }
                    }
                    catch { }
                }

                if (string.IsNullOrWhiteSpace(submittedBy))
                {
                    submittedBy = "HR Administrator";
                }

                string companyId = GetSafeString(payload, "companyId");
                if (string.IsNullOrWhiteSpace(companyId))
                {
                    companyId = GetSafeString(payload, "fk_companyId");
                }
                if (string.IsNullOrWhiteSpace(companyId))
                {
                    companyId = HttpContext.Items["DecryptedCompanyId"]?.ToString();
                }

                var parameters = new DynamicParameters();
                parameters.Add("JobTitle", jobTitle);
                parameters.Add("ServiceType", serviceType);
                parameters.Add("Designation", designation);
                parameters.Add("SkillCategory", skillCategory);
                parameters.Add("OpenPositions", openPositions);
                parameters.Add("Location", location);
                parameters.Add("Department", department);
                parameters.Add("HiringType", hiringType);
                parameters.Add("IsDiversityHiring", isDiversityHiring);
                parameters.Add("DiversityCategory", diversityCategory);
                parameters.Add("WorkplaceType", workplaceType);
                parameters.Add("EmploymentType", employmentType);
                parameters.Add("ExperienceMin", experienceMin);
                parameters.Add("ExperienceMax", experienceMax);
                parameters.Add("CtcMin", ctcMin);
                parameters.Add("CtcMax", ctcMax);
                parameters.Add("Currency", currency);
                parameters.Add("Priority", priority);
                parameters.Add("TargetStartDate", targetStartDate);
                parameters.Add("EducationLevel", educationLevel);
                parameters.Add("PrimarySkills", primarySkills);
                parameters.Add("SecondarySkills", secondarySkills);
                parameters.Add("NoticePeriodMaxDays", noticePeriodMaxDays);
                parameters.Add("Industry", industry);
                parameters.Add("JobDescription", jobDescription);
                parameters.Add("Responsibilities", responsibilities);
                parameters.Add("Qualifications", qualifications);
                parameters.Add("Benefits", benefits);
                parameters.Add("HiringManager", hiringManager);
                parameters.Add("HiringManagerId", hiringManagerId);
                parameters.Add("LeadRecruiter", leadRecruiter);
                parameters.Add("LeadRecruiterId", leadRecruiterId);
                parameters.Add("L1ApproverName", l1Approver);
                parameters.Add("L1ApproverId", l1ApproverId);
                parameters.Add("Interviewers", interviewers);
                parameters.Add("IsDraft", isDraft);
                parameters.Add("IsBufferUtilized", isBufferUtilized);
                parameters.Add("BufferHeadsUtilized", bufferHeadsUtilized);
                parameters.Add("SubmittedBy", submittedBy);
                parameters.Add("SubmittedById", submittedById);
                parameters.Add("CompanyId", companyId);
                parameters.Add("fk_companyId", companyId);
                parameters.Add("fk_locid", string.IsNullOrWhiteSpace(fk_locid) ? null : fk_locid);
                parameters.Add("fk_deptid", string.IsNullOrWhiteSpace(fk_deptid) ? null : fk_deptid);
                parameters.Add("fk_subdeptid", string.IsNullOrWhiteSpace(fk_subdeptid) ? null : fk_subdeptid);
                parameters.Add("fk_desgid", string.IsNullOrWhiteSpace(fk_desgid) ? null : fk_desgid);
                parameters.Add("fk_classid", string.IsNullOrWhiteSpace(fk_classid) ? null : fk_classid);
                parameters.Add("fk_catid", string.IsNullOrWhiteSpace(fk_catid) ? null : fk_catid);
                parameters.Add("fk_costcentreid", fk_costcentreid);
                parameters.Add("fk_zoneId", string.IsNullOrWhiteSpace(fk_zoneId) ? null : fk_zoneId);
                parameters.Add("fk_cityid", string.IsNullOrWhiteSpace(fk_cityid) ? null : fk_cityid);
                parameters.Add("BusinessVertical", businessVertical);

                var result = await conn.QueryFirstOrDefaultAsync<dynamic>(
                    "dbo.usp_REC_SaveJobRequisition",
                    parameters,
                    commandType: CommandType.StoredProcedure);

                return Ok(new
                {
                    success = true,
                    requisitionId = result?.mrfCode?.ToString(),
                    dbId = result?.reqId,
                    message = result?.Message?.ToString() ?? "Requisition submitted successfully"
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Error saving requisition", error = ex.Message });
            }
        }

        /// <summary>
        /// Retrieves complete details of a specific job requisition by ID.
        /// Stored Procedure: dbo.usp_REC_GetJobRequisitionById (100% Stored Procedure, Zero Inline SQL)
        /// </summary>
        [HttpGet("GetJobRequisitionById")]
        public async Task<IActionResult> GetJobRequisitionById([FromQuery] long reqId, [FromQuery] string? companyId = null)
        {
            try
            {
                var decryptedCompanyId = HttpContext.Items["DecryptedCompanyId"]?.ToString();
                var scopedCompanyId = !string.IsNullOrEmpty(decryptedCompanyId) ? decryptedCompanyId : companyId;

                using var conn = DataBaseFactory.ConnString();

                var requisition = await conn.QueryFirstOrDefaultAsync<dynamic>(
                    "dbo.usp_REC_GetJobRequisitionById",
                    new { ReqId = reqId, CompanyId = scopedCompanyId },
                    commandType: CommandType.StoredProcedure);

                if (requisition == null)
                {
                    return NotFound(new { message = "Job requisition not found." });
                }

                return Ok(requisition);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Error fetching job requisition details", error = ex.Message });
            }
        }

        /// <summary>
        /// Updates an existing job requisition's editable fields while keeping MRF Code immutable.
        /// Stored Procedure: dbo.usp_REC_UpdateJobRequisition (100% Stored Procedure, Zero Inline SQL)
        /// </summary>
        [HttpPost("UpdateJobRequisition")]
        public async Task<IActionResult> UpdateJobRequisition([FromBody] JsonElement payload)
        {
            try
            {
                using var conn = DataBaseFactory.ConnString();

                long reqId = GetSafeLong(payload, "reqId") ?? GetSafeLong(payload, "jobId") ?? 0;
                if (reqId <= 0)
                {
                    return BadRequest(new { message = "A valid requisition ID (reqId) is required." });
                }

                string jobTitle = GetSafeString(payload, "jobTitle");
                string serviceType = GetSafeString(payload, "serviceType");
                string designation = GetSafeString(payload, "designation");
                string skillCategory = GetSafeString(payload, "skillCategory");
                int openPositions = GetSafeInt(payload, "openPositions") ?? 1;
                string location = GetSafeString(payload, "location");
                string department = GetSafeString(payload, "department");
                string hiringType = GetSafeString(payload, "hiringType", "New");
                string replacedEmpName = GetSafeString(payload, "replacedEmpName");
                string replacementReason = GetSafeString(payload, "replacementReason");

                bool? isDiversityHiring = null;
                if (payload.TryGetProperty("isDiversityHiring", out var idh) && idh.ValueKind != JsonValueKind.Null && idh.ValueKind != JsonValueKind.Undefined)
                {
                    if (idh.ValueKind == JsonValueKind.True || idh.ValueKind == JsonValueKind.False)
                        isDiversityHiring = idh.GetBoolean();
                    else if (bool.TryParse(idh.GetString(), out var bVal))
                        isDiversityHiring = bVal;
                }
                string diversityCategory = GetSafeString(payload, "diversityCategory");
                
                string workplaceType = GetSafeString(payload, "workplaceType", "On-Site");
                string employmentType = GetSafeString(payload, "employmentType", "Full-Time");
                
                decimal? experienceMin = GetSafeDecimal(payload, "experienceMin");
                decimal? experienceMax = GetSafeDecimal(payload, "experienceMax");
                decimal? ctcMin = GetSafeDecimal(payload, "ctcMin");
                decimal? ctcMax = GetSafeDecimal(payload, "ctcMax");
                
                string currency = GetSafeString(payload, "currency", "INR");
                string priority = GetSafeString(payload, "priority", "Medium");
                string targetStartDate = GetSafeString(payload, "targetStartDate");
                string educationLevel = GetSafeString(payload, "educationLevel");
                string primarySkills = GetSafeString(payload, "primarySkills");
                string secondarySkills = GetSafeString(payload, "secondarySkills");
                int? noticePeriodMaxDays = GetSafeInt(payload, "noticePeriodMaxDays");
                string industry = GetSafeString(payload, "industry", "Logistics & Supply Chain");
                
                string jobDescription = GetSafeString(payload, "jobDescription");
                string responsibilities = GetSafeString(payload, "responsibilities");
                string qualifications = GetSafeString(payload, "qualifications");
                string benefits = GetSafeString(payload, "benefits");

                string fk_locid = GetSafeString(payload, "fk_locid");
                string fk_deptid = GetSafeString(payload, "fk_deptid");
                string fk_subdeptid = GetSafeString(payload, "fk_subdeptid");
                string fk_desgid = GetSafeString(payload, "fk_desgid");
                string fk_classid = GetSafeString(payload, "fk_classid");
                string fk_catid = GetSafeString(payload, "fk_catid");
                long? fk_costcentreid = GetSafeLong(payload, "fk_costcentreid");
                string fk_zoneId = GetSafeString(payload, "fk_zoneId");
                string fk_cityid = GetSafeString(payload, "fk_cityid");
                string businessVertical = GetSafeString(payload, "businessVertical");

                bool isDraft = GetSafeBool(payload, "isDraft");
                bool isBufferUtilized = GetSafeBool(payload, "isBufferUtilized");
                int bufferHeadsUtilized = GetSafeInt(payload, "bufferHeadsUtilized") ?? 0;

                string updatedBy = GetSafeString(payload, "updatedBy") ?? GetSafeString(payload, "submittedBy");
                string updatedById = GetSafeString(payload, "updatedById") ?? GetSafeString(payload, "submittedById");
                string decryptedUserId = HttpContext.Items["DecryptedUserId"]?.ToString();
                if (!string.IsNullOrWhiteSpace(decryptedUserId))
                {
                    decryptedUserId = decryptedUserId.Replace("GU-", "", StringComparison.OrdinalIgnoreCase).Trim();
                }

                if (string.IsNullOrWhiteSpace(updatedById) || updatedById == "1")
                {
                    if (!string.IsNullOrWhiteSpace(decryptedUserId))
                    {
                        updatedById = decryptedUserId;
                    }
                }

                if (string.IsNullOrWhiteSpace(updatedBy) || updatedBy.Equals("Site HR Admin", StringComparison.OrdinalIgnoreCase) || updatedBy.Equals("Site HR", StringComparison.OrdinalIgnoreCase))
                {
                    try
                    {
                        var userRecord = await conn.QueryFirstOrDefaultAsync<dynamic>(
                            "dbo.usp_UM_ResolveUserName",
                            new { UserId = updatedById },
                            commandType: CommandType.StoredProcedure);

                        if (userRecord != null && !string.IsNullOrWhiteSpace((string)userRecord.ResolvedName))
                        {
                            updatedBy = (string)userRecord.ResolvedName;
                        }
                    }
                    catch { }
                }

                if (string.IsNullOrWhiteSpace(updatedBy))
                {
                    updatedBy = "HR Administrator";
                }

                string companyId = GetSafeString(payload, "companyId");
                if (string.IsNullOrWhiteSpace(companyId))
                {
                    companyId = GetSafeString(payload, "fk_companyId");
                }
                if (string.IsNullOrWhiteSpace(companyId))
                {
                    companyId = HttpContext.Items["DecryptedCompanyId"]?.ToString();
                }

                var parameters = new DynamicParameters();
                parameters.Add("ReqId", reqId);
                parameters.Add("JobTitle", jobTitle);
                parameters.Add("ServiceType", serviceType);
                parameters.Add("Designation", designation);
                parameters.Add("SkillCategory", skillCategory);
                parameters.Add("OpenPositions", openPositions);
                parameters.Add("Location", location);
                parameters.Add("Department", department);
                parameters.Add("HiringType", hiringType);
                parameters.Add("ReplacedEmpName", replacedEmpName);
                parameters.Add("ReplacementReason", replacementReason);
                parameters.Add("IsDiversityHiring", isDiversityHiring);
                parameters.Add("DiversityCategory", diversityCategory);
                parameters.Add("WorkplaceType", workplaceType);
                parameters.Add("EmploymentType", employmentType);
                parameters.Add("ExperienceMin", experienceMin);
                parameters.Add("ExperienceMax", experienceMax);
                parameters.Add("CtcMin", ctcMin);
                parameters.Add("CtcMax", ctcMax);
                parameters.Add("Currency", currency);
                parameters.Add("Priority", priority);
                parameters.Add("TargetStartDate", targetStartDate);
                parameters.Add("EducationLevel", educationLevel);
                parameters.Add("PrimarySkills", primarySkills);
                parameters.Add("SecondarySkills", secondarySkills);
                parameters.Add("NoticePeriodMaxDays", noticePeriodMaxDays);
                parameters.Add("Industry", industry);
                parameters.Add("JobDescription", jobDescription);
                parameters.Add("Responsibilities", responsibilities);
                parameters.Add("Qualifications", qualifications);
                parameters.Add("Benefits", benefits);
                parameters.Add("IsDraft", isDraft);
                parameters.Add("IsBufferUtilized", isBufferUtilized);
                parameters.Add("BufferHeadsUtilized", bufferHeadsUtilized);
                parameters.Add("UpdatedBy", updatedBy);
                parameters.Add("UpdatedById", updatedById);
                parameters.Add("CompanyId", companyId);
                parameters.Add("fk_companyId", companyId);
                parameters.Add("fk_locid", string.IsNullOrWhiteSpace(fk_locid) ? null : fk_locid);
                parameters.Add("fk_deptid", string.IsNullOrWhiteSpace(fk_deptid) ? null : fk_deptid);
                parameters.Add("fk_subdeptid", string.IsNullOrWhiteSpace(fk_subdeptid) ? null : fk_subdeptid);
                parameters.Add("fk_desgid", string.IsNullOrWhiteSpace(fk_desgid) ? null : fk_desgid);
                parameters.Add("fk_classid", string.IsNullOrWhiteSpace(fk_classid) ? null : fk_classid);
                parameters.Add("fk_catid", string.IsNullOrWhiteSpace(fk_catid) ? null : fk_catid);
                parameters.Add("fk_costcentreid", fk_costcentreid);
                parameters.Add("fk_zoneId", string.IsNullOrWhiteSpace(fk_zoneId) ? null : fk_zoneId);
                parameters.Add("fk_cityid", string.IsNullOrWhiteSpace(fk_cityid) ? null : fk_cityid);
                parameters.Add("BusinessVertical", businessVertical);

                var result = await conn.QueryFirstOrDefaultAsync<dynamic>(
                    "dbo.usp_REC_UpdateJobRequisition",
                    parameters,
                    commandType: CommandType.StoredProcedure);

                return Ok(new
                {
                    success = true,
                    requisitionId = result?.mrfCode?.ToString(),
                    dbId = result?.reqId,
                    message = result?.Message?.ToString() ?? "Requisition updated successfully"
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Error updating requisition", error = ex.Message });
            }
        }

        // ─────────────────────────────────────────────────────────────────────
        // APPROVAL WORKFLOW ENDPOINTS (All backed by Stored Procedures)
        // ─────────────────────────────────────────────────────────────────────

        /// <summary>
        /// Returns the approval level (1/2/3) for the logged-in user based on their role.
        /// Stored Procedure: dbo.usp_REC_GetMyApprovalLevel
        /// </summary>
        [HttpGet("GetMyApprovalLevel")]
        public async Task<IActionResult> GetMyApprovalLevel([FromQuery] string userId)
        {
            try
            {
                using var conn = DataBaseFactory.ConnString();

                var info = await conn.QueryFirstOrDefaultAsync<dynamic>(
                    "dbo.usp_REC_GetMyApprovalLevel",
                    new { UserId = userId },
                    commandType: CommandType.StoredProcedure);

                int level = info?.ApprovalLevel ?? 0;
                bool isAdmin = ((int?)(info?.IsAdmin) ?? 0) == 1 || (info?.RoleLabel?.ToString() ?? "").ToUpper().Contains("ADMIN");
                return Ok(new
                {
                    approvalLevel = level,
                    levelLabel = info?.LevelLabel?.ToString(),
                    roleLabel = info?.RoleLabel?.ToString(),
                    hasApprovalRights = level > 0 || isAdmin,
                    isAdmin = isAdmin
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Error getting approval level", error = ex.Message });
            }
        }

        /// <summary>
        /// Returns all requisitions pending action for the given user's approval level.
        /// Stored Procedure: dbo.usp_REC_GetPendingApprovals
        /// </summary>
        [HttpGet("GetPendingApprovals")]
        public async Task<IActionResult> GetPendingApprovals([FromQuery] string userId)
        {
            try
            {
                using var conn = DataBaseFactory.ConnString();

                using var multi = await conn.QueryMultipleAsync(
                    "dbo.usp_REC_GetPendingApprovals",
                    new { UserId = userId },
                    commandType: CommandType.StoredProcedure);

                var summary = await multi.ReadFirstOrDefaultAsync<dynamic>();
                var requisitions = (await multi.ReadAsync<dynamic>()).ToList();

                return Ok(new
                {
                    approvalLevel = summary?.approvalLevel ?? 0,
                    pendingCount = summary?.pendingCount ?? 0,
                    requisitions = requisitions
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Error fetching pending approvals", error = ex.Message });
            }
        }

        /// <summary>
        /// Approve a requisition at L1, L2, or L3. Advances workflow or opens hiring.
        /// Stored Procedure: dbo.usp_REC_ApproveRequisition
        /// </summary>
        [HttpPost("ApproveRequisition")]
        public async Task<IActionResult> ApproveRequisition([FromBody] ApprovalActionDto dto)
        {
            try
            {
                using var conn = DataBaseFactory.ConnString();

                var result = await conn.QueryFirstOrDefaultAsync<dynamic>(
                    "dbo.usp_REC_ApproveRequisition",
                    new
                    {
                        ReqId = dto.ReqId,
                        ApprovalLevel = dto.ApprovalLevel,
                        ApproverId = dto.ApproverId,
                        ApproverName = dto.ApproverName,
                        ApproverRole = dto.ApproverRole,
                        Remarks = dto.Remarks
                    },
                    commandType: CommandType.StoredProcedure);

                if (result == null || (int)result.Success == 0)
                {
                    return BadRequest(new { message = result?.Message?.ToString() ?? "Failed to approve requisition" });
                }

                // Send notification email asynchronously with recipients returned by USP (Page Rights L1, L2, L3)
                _ = SendWorkflowEmailAsync(
                    dto,
                    result.MrfCode?.ToString() ?? dto.ReqId,
                    result.JobTitle?.ToString() ?? "Requisition",
                    result.Department?.ToString() ?? "Operations",
                    result.Location?.ToString() ?? "Hub Operations",
                    result.Openings != null ? (int)result.Openings : 1,
                    result.SubmittedBy?.ToString() ?? "Site HR",
                    result.ApproverName?.ToString() ?? dto.ApproverName ?? "Approver",
                    result.Remarks?.ToString() ?? dto.Remarks ?? "Approved",
                    result.NewStatus?.ToString() ?? "Active",
                    result.NextLevelEmails?.ToString() ?? "",
                    result.SiteHrEmail?.ToString() ?? "",
                    isApproval: true);

                return Ok(new
                {
                    success = true,
                    newStatus = result.NewStatus?.ToString(),
                    message = result.Message?.ToString()
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Error approving requisition", error = ex.Message });
            }
        }

        /// <summary>
        /// Reject a requisition. Resets it to Submitted status — Site HR must resubmit from L1.
        /// Stored Procedure: dbo.usp_REC_RejectRequisition
        /// </summary>
        [HttpPost("RejectRequisition")]
        public async Task<IActionResult> RejectRequisition([FromBody] ApprovalActionDto dto)
        {
            try
            {
                using var conn = DataBaseFactory.ConnString();

                var result = await conn.QueryFirstOrDefaultAsync<dynamic>(
                    "dbo.usp_REC_RejectRequisition",
                    new
                    {
                        ReqId = dto.ReqId,
                        ApprovalLevel = dto.ApprovalLevel,
                        ApproverId = dto.ApproverId,
                        ApproverName = dto.ApproverName,
                        ApproverRole = dto.ApproverRole,
                        Remarks = dto.Remarks
                    },
                    commandType: CommandType.StoredProcedure);

                if (result == null || (int)result.Success == 0)
                {
                    return BadRequest(new { message = result?.Message?.ToString() ?? "Failed to reject requisition" });
                }

                // Notify Site HR by email asynchronously with template metadata
                _ = SendWorkflowEmailAsync(
                    dto,
                    result.MrfCode?.ToString() ?? dto.ReqId,
                    result.JobTitle?.ToString() ?? "Requisition",
                    result.Department?.ToString() ?? "Operations",
                    result.Location?.ToString() ?? "Hub Operations",
                    result.Openings != null ? (int)result.Openings : 1,
                    result.SubmittedBy?.ToString() ?? "Site HR",
                    result.ApproverName?.ToString() ?? dto.ApproverName ?? "Approver",
                    result.Remarks?.ToString() ?? dto.Remarks ?? "Rejected",
                    "Submitted",
                    "",
                    result.SiteHrEmail?.ToString() ?? "",
                    isApproval: false);

                return Ok(new
                {
                    success = true,
                    newStatus = result.NewStatus?.ToString() ?? "Rejected",
                    message = result.Message?.ToString()
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Error rejecting requisition", error = ex.Message });
            }
        }

        /// <summary>
        /// Returns the full approval history/timeline and current state for a requisition.
        /// Stored Procedure: dbo.usp_REC_GetApprovalHistory
        /// </summary>
        [HttpGet("GetApprovalHistory/{reqId}")]
        public async Task<IActionResult> GetApprovalHistory(string reqId)
        {
            try
            {
                using var conn = DataBaseFactory.ConnString();

                using var multi = await conn.QueryMultipleAsync(
                    "dbo.usp_REC_GetApprovalHistory",
                    new { ReqId = reqId },
                    commandType: CommandType.StoredProcedure);

                var history = await multi.ReadAsync<dynamic>();
                var currentState = await multi.ReadFirstOrDefaultAsync<dynamic>();

                return Ok(new { history, currentState });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Error fetching approval history", error = ex.Message });
            }
        }

        // ─── Private: Email notification helper (Zero DB queries — pure SMTP) ─────

        private static async Task SendWorkflowEmailAsync(
            ApprovalActionDto dto,
            string mrfCode,
            string jobTitle,
            string department,
            string location,
            int openings,
            string submittedBy,
            string approverName,
            string remarks,
            string newStatus,
            string nextLevelEmails,
            string siteHrEmail,
            bool isApproval)
        {
            try
            {
                string toEmail = "";
                string subject = "";
                string templateFileName = "";

                if (!isApproval)
                {
                    // Rejection — notify Site HR (original creator)
                    toEmail = siteHrEmail;
                    subject = $"[ACTION NEEDED] Requisition {mrfCode} Rejected at L{dto.ApprovalLevel}";
                    templateFileName = "Requisition_Rejected.html";
                }
                else if (newStatus == "Active")
                {
                    // Level 3 Approved — hiring is open — notify Site HR
                    toEmail = !string.IsNullOrEmpty(siteHrEmail) ? siteHrEmail : "";
                    subject = $"[HIRING OPEN] Requisition {mrfCode} Fully Approved";
                    templateFileName = "Requisition_Approved.html";
                }
                else if (newStatus == "L2_Pending")
                {
                    // Approved at L1 — notify L2 approvers (Page Rights L2_Access = 1)
                    toEmail = nextLevelEmails;
                    subject = $"[APPROVAL NEEDED] Requisition {mrfCode} — L2 Action Required";
                    templateFileName = "L2_Approval_Request.html";
                }
                else if (newStatus == "L3_Pending")
                {
                    // Approved at L2 — notify L3 approvers (Page Rights L3_Access = 1)
                    toEmail = nextLevelEmails;
                    subject = $"[APPROVAL NEEDED] Requisition {mrfCode} — L3 Action Required";
                    templateFileName = "L3_Approval_Request.html";
                }

                if (string.IsNullOrWhiteSpace(toEmail)) return;

                // Load HTML template from Templates/Email/ folder (Editable by user anytime)
                string templatePath = Path.Combine(AppContext.BaseDirectory, "Templates", "Email", templateFileName);
                if (!System.IO.File.Exists(templatePath))
                {
                    templatePath = Path.Combine(Directory.GetCurrentDirectory(), "Templates", "Email", templateFileName);
                }

                string body = "";
                if (System.IO.File.Exists(templatePath))
                {
                    body = await System.IO.File.ReadAllTextAsync(templatePath);
                    body = body.Replace("{{MRF_CODE}}", mrfCode ?? "")
                               .Replace("{{JOB_TITLE}}", jobTitle ?? "")
                               .Replace("{{DEPARTMENT}}", department ?? "Operations")
                               .Replace("{{LOCATION}}", location ?? "Hub Operations")
                               .Replace("{{OPENINGS}}", openings.ToString())
                               .Replace("{{SUBMITTED_BY}}", submittedBy ?? "Site HR")
                               .Replace("{{APPROVER_NAME}}", approverName ?? dto.ApproverName ?? "Approver")
                               .Replace("{{APPROVAL_LEVEL}}", dto.ApprovalLevel.ToString())
                               .Replace("{{ACTION_DATE}}", DateTime.Now.ToString("dd-MMM-yyyy HH:mm"))
                               .Replace("{{REMARKS}}", remarks ?? dto.Remarks ?? "Approved")
                               .Replace("{{PORTAL_URL}}", "http://localhost:4200/#/dash/recruitment/recruitmentdashboard/job-management");
                }
                else
                {
                    // Fallback HTML if file is not found
                    body = $@"<div style='font-family: Arial, sans-serif; padding: 20px;'>
                        <h3>CJ DARCL Recruitment Workflow</h3>
                        <p>Requisition <b>{mrfCode} — {jobTitle}</b> status updated to <b>{newStatus}</b> by {approverName}.</p>
                        <p><b>Remarks:</b> {remarks}</p>
                    </div>";
                }

                using var smtp = new System.Net.Mail.SmtpClient("smtp.gmail.com", 587)
                {
                    EnableSsl = true,
                    Credentials = new System.Net.NetworkCredential("ofctesting62@gmail.com", "owzxcappjvuvaxzh")
                };

                var mail = new System.Net.Mail.MailMessage
                {
                    From = new System.Net.Mail.MailAddress("ofctesting62@gmail.com", "CJ DARCL HR System"),
                    Subject = subject,
                    Body = body,
                    IsBodyHtml = true
                };

                foreach (var addr in toEmail.Split(',', StringSplitOptions.RemoveEmptyEntries))
                {
                    var trimmed = addr.Trim();
                    if (!string.IsNullOrWhiteSpace(trimmed))
                        mail.To.Add(trimmed);
                }

                if (mail.To.Count > 0)
                {
                    await smtp.SendMailAsync(mail);
                }
            }
            catch
            {
                // Email delivery failure is non-fatal to workflow transaction
            }
        }

        /// <summary>
        /// Updates BaseDemand, BufferPercent, BufferHeads, and TargetCapacity for a Location.
        /// Stored Procedure: dbo.Location_Update_Manpower_Buffer
        /// </summary>
        [HttpPost("UpdateLocationManpowerBuffer")]
        public async Task<IActionResult> UpdateLocationManpowerBuffer([FromBody] LocationBufferUpdateDto dto)
        {
            try
            {
                var decryptedUserId = HttpContext.Items["DecryptedUserId"]?.ToString() ?? dto.ModifiedBy ?? "Admin";

                using var conn = DataBaseFactory.ConnString();
                var result = await conn.QueryFirstOrDefaultAsync<dynamic>(
                    "dbo.Location_Update_Manpower_Buffer",
                    new
                    {
                        pk_locid = dto.LocationId,
                        BaseDemand = dto.BaseDemand,
                        BufferPercent = dto.BufferPercent,
                        ModifiedBy = decryptedUserId
                    },
                    commandType: CommandType.StoredProcedure);

                return Ok(new
                {
                    success = true,
                    message = result?.Message?.ToString() ?? "Location manpower and buffer updated successfully"
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Error updating location manpower buffer", error = ex.Message });
            }
        }

        /// <summary>
        /// Retrieves company-specific locations with actual manpower base demand, buffer %,
        /// buffer heads, target capacity, and active employee headcount.
        /// Stored Procedure: dbo.usp_REC_GetLocationManpowerList
        /// </summary>
        [HttpGet("GetLocationManpowerList")]
        public async Task<IActionResult> GetLocationManpowerList([FromQuery] string? companyId = null)
        {
            try
            {
                var decryptedCompanyId = HttpContext.Items["DecryptedCompanyId"]?.ToString();
                if (!string.IsNullOrEmpty(decryptedCompanyId))
                {
                    companyId = decryptedCompanyId;
                }

                using var conn = DataBaseFactory.ConnString();
                var locations = await conn.QueryAsync<dynamic>(
                    "dbo.usp_REC_GetLocationManpowerList",
                    new { CompanyId = companyId },
                    commandType: CommandType.StoredProcedure);

                return Ok(new
                {
                    isSuccess = true,
                    data = locations
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { isSuccess = false, message = "Error fetching location manpower list", error = ex.Message });
            }
        }

        // =========================================================================
        // PUBLIC LOCATION QR WALK-IN CANDIDATE APPLICATION (STORED PROCEDURES)
        // =========================================================================

        /// <summary>
        /// Public Walk-in QR endpoint: Retrieves Hub details, active open jobs, and mapped vendors
        /// Stored Procedure: dbo.usp_REC_GetPublicLocationJobsAndVendors
        /// </summary>
        [HttpGet("GetPublicLocationJobsWithVendors")]
        [AllowAnonymous]
        public async Task<IActionResult> GetPublicLocationJobsWithVendors(
            [FromQuery] string? locationId = null,
            [FromQuery] string? companyId = null)
        {
            try
            {
                var qrHeader = Request.Headers["X-QR-Token"].ToString();
                if (string.IsNullOrEmpty(companyId))
                {
                    companyId = "1";
                }

                using var conn = DataBaseFactory.ConnString();

                using var multi = await conn.QueryMultipleAsync(
                    "dbo.usp_REC_GetPublicLocationJobsAndVendors",
                    new { LocationId = locationId ?? "", CompanyId = companyId ?? "1" },
                    commandType: CommandType.StoredProcedure);

                var location = await multi.ReadFirstOrDefaultAsync<dynamic>();
                var openJobs = (await multi.ReadAsync<dynamic>()).ToList();
                var vendors = (await multi.ReadAsync<dynamic>()).ToList();
                var locations = !multi.IsConsumed ? (await multi.ReadAsync<dynamic>()).ToList() : new List<dynamic>();

                return Ok(new
                {
                    isSuccess = true,
                    locationName = location?.locationName?.ToString() ?? "Operational Hub",
                    locationCode = location?.locationCode?.ToString() ?? "HUB",
                    state = location?.state?.ToString() ?? "Operational Hub",
                    zone = location?.zone?.ToString() ?? "North Zone",
                    companyName = location?.companyName?.ToString() ?? "HRMS Portal",
                    companyLogo = location?.companyLogo?.ToString() ?? "",
                    openJobs = openJobs,
                    vendors = vendors,
                    locations = locations
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { isSuccess = false, message = "Error loading location walk-in data", error = ex.Message });
            }
        }

        /// <summary>
        /// Public Walk-in check: Validates if Aadhaar number is present in REC_Candidate_Applications / Details
        /// and verifies their interview/recruitment status.
        /// Stored Procedure: dbo.usp_REC_CheckCandidateAadhaarStatus
        /// </summary>
        [HttpPost("CheckCandidateAadhaarStatus")]
        [AllowAnonymous]
        public async Task<IActionResult> CheckCandidateAadhaarStatus([FromBody] JsonElement payload)
        {
            try
            {
                string aadharNo = GetSafeString(payload, "aadharNo", "").Trim().Replace("-", "").Replace(" ", "");
                string companyId = GetSafeString(payload, "companyId", "");
                string locationId = GetSafeString(payload, "locationId", "");

                if (string.IsNullOrEmpty(aadharNo) || aadharNo.Length < 12)
                {
                    return BadRequest(new { isSuccess = false, message = "Please enter a valid 12-digit Aadhaar Card number." });
                }

                using var conn = DataBaseFactory.ConnString();

                var result = await conn.QueryFirstOrDefaultAsync<dynamic>(
                    "dbo.usp_REC_CheckCandidateAadhaarStatus",
                    new
                    {
                        AadhaarNo = aadharNo,
                        CompanyId = companyId,
                        LocationId = locationId
                    },
                    commandType: CommandType.StoredProcedure);

                bool canProceed = ((int?)(result?.CanProceed) ?? 1) == 1;
                bool exists = ((int?)(result?.ExistsStatus) ?? 0) == 1;

                return Ok(new
                {
                    isSuccess = true,
                    exists = exists,
                    canProceed = canProceed,
                    candidateName = result?.CandidateName?.ToString() ?? "",
                    status = result?.CurrentStatus?.ToString() ?? "",
                    jobTitle = result?.JobTitle?.ToString() ?? "",
                    message = result?.Message?.ToString() ?? "Aadhaar verified."
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { isSuccess = false, message = "Error validating Aadhaar status", error = ex.Message });
            }
        }

        /// <summary>
        /// Public Walk-in Candidate submission endpoint.
        /// Saves candidate into REC_Candidate_Applications and REC_Candidate_Details.
        /// Stored Procedure: dbo.usp_REC_SubmitWalkInCandidate
        /// </summary>
        [HttpPost("SubmitWalkInCandidate")]
        [AllowAnonymous]
        public async Task<IActionResult> SubmitWalkInCandidate([FromBody] JsonElement payload)
        {
            try
            {
                string candidateName = GetSafeString(payload, "candidateName", "").Trim();
                string mobileNumber = GetSafeString(payload, "mobileNumber", "").Trim();
                string aadharNo = GetSafeString(payload, "aadharNo", "").Trim().Replace("-", "").Replace(" ", "");
                string vendorId = GetSafeString(payload, "vendorId", "");
                string vendorName = GetSafeString(payload, "vendorName", "");
                string jobId = GetSafeString(payload, "jobId", "");
                string jobTitle = GetSafeString(payload, "jobTitle", "");
                string locationId = GetSafeString(payload, "locationId", "");
                string companyId = GetSafeString(payload, "companyId", "");

                if (string.IsNullOrEmpty(candidateName) || string.IsNullOrEmpty(mobileNumber))
                {
                    return BadRequest(new { isSuccess = false, message = "Candidate Name and Mobile Number are mandatory." });
                }

                if (!string.IsNullOrEmpty(aadharNo) && aadharNo.Length < 12)
                {
                    return BadRequest(new { isSuccess = false, message = "Aadhaar Number must be 12 digits if provided." });
                }

                using var conn = DataBaseFactory.ConnString();

                var result = await conn.QueryFirstOrDefaultAsync<dynamic>(
                    "dbo.usp_REC_SubmitWalkInCandidate",
                    new
                    {
                        CandidateName = candidateName,
                        MobileNumber = mobileNumber,
                        AadhaarNo = aadharNo,
                        VendorId = vendorId,
                        VendorName = vendorName,
                        JobId = jobId,
                        JobTitle = jobTitle,
                        LocationId = locationId,
                        CompanyId = companyId
                    },
                    commandType: CommandType.StoredProcedure);

                int success = ((int?)(result?.Success) ?? 1);
                if (success == 0)
                {
                    return Ok(new
                    {
                        isSuccess = false,
                        message = result?.Message?.ToString() ?? "Candidate with this phone number or details already exists."
                    });
                }

                return Ok(new
                {
                    isSuccess = true,
                    applicationRef = result?.ApplicationRef?.ToString() ?? "",
                    candidateName = result?.CandidateName?.ToString() ?? candidateName,
                    jobTitle = result?.JobTitle?.ToString() ?? jobTitle,
                    message = result?.Message?.ToString() ?? "Application submitted successfully."
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { isSuccess = false, message = "Error submitting walk-in application", error = ex.Message });
            }
        }

        // ─── Safe Helpers for JsonElement extraction ─────────────────────────────
        private static int? GetSafeInt(JsonElement parent, string propName)
        {
            if (parent.TryGetProperty(propName, out var el))
            {
                if (el.ValueKind == JsonValueKind.Number && el.TryGetInt32(out var val))
                    return val;
                if (el.ValueKind == JsonValueKind.String && int.TryParse(el.GetString(), out var sVal))
                    return sVal;
            }
            return null;
        }

        private static long? GetSafeLong(JsonElement parent, string propName)
        {
            if (parent.TryGetProperty(propName, out var el))
            {
                if (el.ValueKind == JsonValueKind.Number && el.TryGetInt64(out var val))
                    return val;
                if (el.ValueKind == JsonValueKind.String && long.TryParse(el.GetString(), out var sVal))
                    return sVal;
            }
            return null;
        }

        private static decimal? GetSafeDecimal(JsonElement parent, string propName)
        {
            if (parent.TryGetProperty(propName, out var el))
            {
                if (el.ValueKind == JsonValueKind.Number && el.TryGetDecimal(out var val))
                    return val;
                if (el.ValueKind == JsonValueKind.String && decimal.TryParse(el.GetString(), out var sVal))
                    return sVal;
            }
            return null;
        }

        private static bool GetSafeBool(JsonElement parent, string propName, bool defaultValue = false)
        {
            if (parent.TryGetProperty(propName, out var el))
            {
                if (el.ValueKind == JsonValueKind.True) return true;
                if (el.ValueKind == JsonValueKind.False) return false;
                if (el.ValueKind == JsonValueKind.String && bool.TryParse(el.GetString(), out var bVal))
                    return bVal;
            }
            return defaultValue;
        }

        private static string GetSafeString(JsonElement parent, string propName, string defaultValue = "")
        {
            if (parent.TryGetProperty(propName, out var el))
            {
                if (el.ValueKind == JsonValueKind.String)
                    return el.GetString() ?? defaultValue;
                if (el.ValueKind != JsonValueKind.Null && el.ValueKind != JsonValueKind.Undefined)
                    return el.ToString() ?? defaultValue;
            }
            return defaultValue;
        }

        // ─────────────────────────────────────────────────────────────────────
        // PIPELINE STAGE CONFIG — Company-wise enable/disable
        // ─────────────────────────────────────────────────────────────────────

        /// <summary>
        /// Returns all pipeline stages for a company with IsEnabled flag.
        /// If no config rows exist for the company, returns global defaults.
        /// Stored Procedure: dbo.usp_REC_GetPipelineStageConfig
        /// </summary>
        [HttpGet("GetPipelineStageConfig")]
        public async Task<IActionResult> GetPipelineStageConfig([FromQuery] string? companyId = null)
        {
            try
            {
                var decryptedCompanyId = HttpContext.Items["DecryptedCompanyId"]?.ToString();
                var scopedCompanyId = !string.IsNullOrEmpty(decryptedCompanyId) ? decryptedCompanyId : companyId;

                if (string.IsNullOrWhiteSpace(scopedCompanyId))
                    return BadRequest(new { message = "CompanyId is required." });

                using var conn = DataBaseFactory.ConnString();
                var stages = await conn.QueryAsync<dynamic>(
                    "dbo.usp_REC_GetPipelineStageConfig",
                    new { CompanyId = scopedCompanyId },
                    commandType: CommandType.StoredProcedure);

                return Ok(stages);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Error fetching pipeline stage config", error = ex.Message });
            }
        }

        /// <summary>
        /// Inserts or updates a single stage config row for a company.
        /// Used to toggle IsEnabled or rename/reorder a stage.
        /// Stored Procedure: dbo.usp_REC_UpsertPipelineStageConfig
        /// </summary>
        [HttpPost("UpsertPipelineStageConfig")]
        public async Task<IActionResult> UpsertPipelineStageConfig([FromBody] JsonElement payload)
        {
            try
            {
                var decryptedCompanyId = HttpContext.Items["DecryptedCompanyId"]?.ToString();
                string companyId = !string.IsNullOrEmpty(decryptedCompanyId)
                    ? decryptedCompanyId
                    : GetSafeString(payload, "companyId");

                if (string.IsNullOrWhiteSpace(companyId))
                    return BadRequest(new { message = "CompanyId is required." });

                using var conn = DataBaseFactory.ConnString();
                var result = await conn.QueryFirstOrDefaultAsync<dynamic>(
                    "dbo.usp_REC_UpsertPipelineStageConfig",
                    new
                    {
                        CompanyId  = companyId,
                        StageCode  = GetSafeString(payload, "stageCode"),
                        StageLabel = GetSafeString(payload, "stageLabel"),
                        StageIcon  = GetSafeString(payload, "stageIcon"),
                        StageColor = GetSafeString(payload, "stageColor"),
                        StageOrder = GetSafeInt(payload, "stageOrder") ?? 1,
                        IsEnabled  = GetSafeBool(payload, "isEnabled"),
                        ModifiedBy = GetSafeString(payload, "modifiedBy", "Site HR Admin")
                    },
                    commandType: CommandType.StoredProcedure);

                return Ok(new { success = true, result });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Error saving pipeline stage config", error = ex.Message });
            }
        }
    }

    // ─── DTO for approval actions ────────────────────────────────────────────
    public class ApprovalActionDto
    {
        public long ReqId { get; set; }
        public int ApprovalLevel { get; set; }          // 1, 2, or 3
        public string ApproverId { get; set; } = "";
        public string ApproverName { get; set; } = "";
        public string? ApproverRole { get; set; }
        public string Remarks { get; set; } = "";
    }

    public class LocationBufferUpdateDto
    {
        public string LocationId { get; set; } = "";
        public int BaseDemand { get; set; }
        public decimal BufferPercent { get; set; }
        public string? ModifiedBy { get; set; }
    }
}
