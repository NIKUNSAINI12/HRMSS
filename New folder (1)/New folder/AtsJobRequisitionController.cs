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
        public async Task<IActionResult> GetJobRequisitions()
        {
            try
            {
                using var conn = DataBaseFactory.ConnString();

                var jobs = await conn.QueryAsync<dynamic>(
                    "dbo.usp_REC_GetJobRequisitions",
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
                bool isDiversityHiring = GetSafeBool(payload, "isDiversityHiring");
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
                string leadRecruiter = GetSafeString(payload, "leadRecruiter");

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
                string submittedBy = GetSafeString(payload, "submittedBy", "Site HR Admin");
                string submittedById = GetSafeString(payload, "submittedById", "1");

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
                parameters.Add("LeadRecruiter", leadRecruiter);
                parameters.Add("Interviewers", interviewers);
                parameters.Add("IsDraft", isDraft);
                parameters.Add("IsBufferUtilized", isBufferUtilized);
                parameters.Add("BufferHeadsUtilized", bufferHeadsUtilized);
                parameters.Add("SubmittedBy", submittedBy);
                parameters.Add("SubmittedById", submittedById);

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

                // Send notification email asynchronously with recipients returned by USP (Zero inline SQL)
                _ = SendWorkflowEmailAsync(
                    dto,
                    result.MrfCode?.ToString() ?? dto.ReqId,
                    result.JobTitle?.ToString() ?? "Requisition",
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

                // Notify Site HR by email asynchronously (Zero inline SQL)
                _ = SendWorkflowEmailAsync(
                    dto,
                    result.MrfCode?.ToString() ?? dto.ReqId,
                    result.JobTitle?.ToString() ?? "Requisition",
                    "Submitted",
                    "",
                    result.SiteHrEmail?.ToString() ?? "",
                    isApproval: false);

                return Ok(new
                {
                    success = true,
                    newStatus = "Submitted",
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
            string newStatus,
            string nextLevelEmails,
            string siteHrEmail,
            bool isApproval)
        {
            try
            {
                string toEmail = "";
                string subject = "";
                string body = "";

                if (!isApproval)
                {
                    // Rejection — email Site HR
                    toEmail = siteHrEmail;
                    subject = $"[ACTION NEEDED] Requisition {mrfCode} Rejected at L{dto.ApprovalLevel}";
                    body = $@"Dear Site HR,<br/><br/>
                        Your manpower requisition <b>{mrfCode} — {jobTitle}</b> has been <b>REJECTED</b> at Level {dto.ApprovalLevel} by {dto.ApproverName}.<br/>
                        <b>Remarks:</b> {dto.Remarks}<br/><br/>
                        Please log in to review and resubmit the requisition.<br/><br/>
                        Regards,<br/>CJ DARCL HR System";
                }
                else if (newStatus == "Active")
                {
                    // All approved — hiring is open
                    toEmail = !string.IsNullOrEmpty(siteHrEmail) ? siteHrEmail : "";
                    subject = $"[HIRING OPEN] Requisition {mrfCode} Fully Approved";
                    body = $@"The requisition <b>{mrfCode} — {jobTitle}</b> has been approved by all levels.<br/>
                        <b>Hiring is now OPEN.</b> Recruiters can begin sourcing candidates.<br/><br/>
                        Approved by L3: {dto.ApproverName}<br/>Regards,<br/>CJ DARCL HR System";
                }
                else
                {
                    // Approved — notify next level approvers
                    toEmail = nextLevelEmails;
                    int nextLevel = dto.ApprovalLevel + 1;
                    subject = $"[APPROVAL NEEDED] Requisition {mrfCode} — L{nextLevel} Action Required";
                    body = $@"Dear L{nextLevel} Approver,<br/><br/>
                        A manpower requisition requires your approval.<br/>
                        <b>MRF:</b> {mrfCode}<br/>
                        <b>Role:</b> {jobTitle}<br/>
                        <b>Approved by L{dto.ApprovalLevel}:</b> {dto.ApproverName}<br/><br/>
                        Please log in to review and approve/reject.<br/><br/>
                        Regards,<br/>CJ DARCL HR System";
                }

                if (string.IsNullOrWhiteSpace(toEmail)) return;

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
            [FromQuery] string locationId,
            [FromQuery] string? companyId = null)
        {
            try
            {
                var qrHeader = Request.Headers["X-QR-Token"].ToString();
                if (string.IsNullOrEmpty(qrHeader) && string.IsNullOrEmpty(locationId))
                {
                    return Unauthorized(new { isSuccess = false, message = "Access Denied: Missing or unauthorized QR Code token." });
                }

                using var conn = DataBaseFactory.ConnString();

                using var multi = await conn.QueryMultipleAsync(
                    "dbo.usp_REC_GetPublicLocationJobsAndVendors",
                    new { LocationId = locationId, CompanyId = companyId },
                    commandType: CommandType.StoredProcedure);

                var location = await multi.ReadFirstOrDefaultAsync<dynamic>();
                var openJobs = (await multi.ReadAsync<dynamic>()).ToList();
                var vendors = (await multi.ReadAsync<dynamic>()).ToList();

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
                    vendors = vendors
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

                if (string.IsNullOrEmpty(candidateName) || string.IsNullOrEmpty(mobileNumber) || string.IsNullOrEmpty(vendorId))
                {
                    return BadRequest(new { isSuccess = false, message = "Candidate Name, Mobile Number, and Sourcing Vendor are mandatory." });
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
                    applicationRef = result?.ApplicationRef?.ToString(),
                    candidateName = result?.CandidateName?.ToString() ?? candidateName,
                    jobTitle = result?.JobTitle?.ToString() ?? jobTitle,
                    message = result?.Message?.ToString() ?? "Application submitted successfully."
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { isSuccess = false, message = "Error submitting candidate application", error = ex.Message });
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
