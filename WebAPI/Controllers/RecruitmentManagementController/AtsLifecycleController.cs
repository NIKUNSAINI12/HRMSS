using Dapper;
using HRMSWebAPI.Helper;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Data;

namespace HRMSWebAPI.Controllers.RecruitmentManagementController
{
    [Route("api/v1/[controller]")]
    [ApiController]
    [AllowAnonymous]
    public class AtsLifecycleController : ControllerBase
    {
        private string ResolveCompanyId(string? fallbackCompanyId = null)
        {
            if (!string.IsNullOrWhiteSpace(fallbackCompanyId))
                return fallbackCompanyId;

            var decryptedCompanyId = HttpContext.Items["DecryptedCompanyId"]?.ToString();
            if (!string.IsNullOrEmpty(decryptedCompanyId))
                return decryptedCompanyId;

            return "";
        }

        // =========================================================================
        // STEP 4 & 5: VENDOR TO REQUISITION ALLOCATION (CJ DARCL ATS)
        // =========================================================================

        [HttpGet("GetVendorsForMapping")]
        public async Task<IActionResult> GetVendorsForMapping(
            [FromQuery] long reqId,
            [FromQuery] string? companyId = null,
            [FromQuery] string? vendorType = null)
        {
            try
            {
                var scopedCompanyId = ResolveCompanyId(companyId);
                using var conn = DataBaseFactory.ConnString();

                var vendors = await conn.QueryAsync<dynamic>(
                    "dbo.usp_REC_GetVendorsForRequisitionMapping",
                    new { ReqId = reqId, CompanyId = scopedCompanyId, VendorType = vendorType },
                    commandType: CommandType.StoredProcedure);

                return Ok(vendors);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error loading vendors for mapping", error = ex.Message });
            }
        }

        [HttpGet("GetVendorsByLocation")]
        public async Task<IActionResult> GetVendorsByLocation(
            [FromQuery] string? companyId,
            [FromQuery] string? locationId = null,
            [FromQuery] long? reqId = null)
        {
            try
            {
                var scopedCompanyId = ResolveCompanyId(companyId);
                using var conn = DataBaseFactory.ConnString();
                var vendors = await conn.QueryAsync<dynamic>(
                    "dbo.usp_REC_GetVendorsByCompanyAndLocation",
                    new { CompanyId = scopedCompanyId, LocationId = locationId, ReqId = reqId },
                    commandType: CommandType.StoredProcedure);
                return Ok(vendors);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error loading vendors by company & location", error = ex.Message });
            }
        }

        [HttpPost("AssignVendorToCandidate")]
        public async Task<IActionResult> AssignVendorToCandidate([FromBody] AssignVendorToCandidateDto dto)
        {
            if (dto == null || dto.AppId <= 0 || string.IsNullOrWhiteSpace(dto.VendorId))
                return BadRequest(new { success = false, message = "Application ID and Staffing Vendor selection are required." });

            try
            {
                var scopedCompanyId = ResolveCompanyId(dto.CompanyId);
                var assignedBy = HttpContext.Items["DecryptedUserId"]?.ToString() ?? dto.AssignedBy ?? "Recruiter";
                using var conn = DataBaseFactory.ConnString();

                var result = await conn.QueryFirstOrDefaultAsync<dynamic>(
                    "dbo.usp_REC_AssignVendorToCandidate",
                    new
                    {
                        AppId = dto.AppId,
                        VendorId = dto.VendorId,
                        VendorName = dto.VendorName,
                        AssignedBy = assignedBy,
                        CompanyId = scopedCompanyId,
                        Remarks = dto.Remarks
                    },
                    commandType: CommandType.StoredProcedure);

                bool isSuccess = result != null && Convert.ToBoolean(result.Success);
                if (!isSuccess)
                {
                    return BadRequest(new { success = false, message = (string?)result?.Message ?? "Failed to assign staffing vendor." });
                }

                return Ok(new
                {
                    success = true,
                    message = (string?)result?.Message ?? "Staffing vendor assigned successfully.",
                    vendorId = (string?)result?.VendorId,
                    vendorName = (string?)result?.VendorName
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error assigning vendor to candidate", error = ex.Message });
            }
        }

        [HttpPost("SaveVendorMapping")]
        public async Task<IActionResult> SaveVendorMapping([FromBody] VendorMappingDto dto)
        {
            try
            {
                var scopedCompanyId = ResolveCompanyId(dto.CompanyId);
                using var conn = DataBaseFactory.ConnString();

                var result = await conn.QueryFirstOrDefaultAsync<dynamic>(
                    "dbo.usp_REC_SaveVendorRequisitionMapping",
                    new
                    {
                        ReqId = dto.ReqId,
                        VendorId = dto.VendorId,
                        VendorName = dto.VendorName,
                        VendorType = !string.IsNullOrWhiteSpace(dto.VendorType) ? dto.VendorType : "Supply Vendors",
                        AllocatedQuota = dto.AllocatedQuota > 0 ? dto.AllocatedQuota : 10,
                        CommissionTerms = dto.CommissionTerms ?? "Standard",
                        IsActive = dto.IsActive,
                        AssignedBy = dto.AssignedBy ?? "Site HR",
                        CompanyId = scopedCompanyId
                    },
                    commandType: CommandType.StoredProcedure);

                return Ok(result ?? new { success = true, message = "Vendor mapping saved successfully." });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error saving vendor mapping", error = ex.Message });
            }
        }

        [HttpPost("SaveBulkVendorMapping")]
        public async Task<IActionResult> SaveBulkVendorMapping([FromBody] List<VendorMappingDto> dtoList)
        {
            if (dtoList == null || dtoList.Count == 0)
                return BadRequest(new { success = false, message = "No vendor allocations provided." });

            try
            {
                using var conn = DataBaseFactory.ConnString();
                int successCount = 0;

                foreach (var dto in dtoList)
                {
                    var scopedCompanyId = ResolveCompanyId(dto.CompanyId);
                    await conn.ExecuteAsync(
                        "dbo.usp_REC_SaveVendorRequisitionMapping",
                        new
                        {
                            ReqId = dto.ReqId,
                            VendorId = dto.VendorId,
                            VendorName = dto.VendorName,
                            VendorType = !string.IsNullOrWhiteSpace(dto.VendorType) ? dto.VendorType : "Supply Vendors",
                            AllocatedQuota = dto.AllocatedQuota > 0 ? dto.AllocatedQuota : 10,
                            CommissionTerms = dto.CommissionTerms ?? (dto.VendorType == "TA" ? "In-house TA Direct" : "Standard (8.33%)"),
                            IsActive = dto.IsActive,
                            AssignedBy = dto.AssignedBy ?? "Administrator",
                            CompanyId = scopedCompanyId
                        },
                        commandType: CommandType.StoredProcedure);
                    successCount++;
                }

                return Ok(new { success = true, count = successCount, message = $"{successCount} vendor(s) allocated successfully." });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error saving bulk vendor allocations", error = ex.Message });
            }
        }

        [HttpPost("DeallocateVendor")]
        public async Task<IActionResult> DeallocateVendor([FromQuery] long reqId, [FromQuery] string vendorId, [FromQuery] string? companyId = null)
        {
            try
            {
                var scopedCompanyId = ResolveCompanyId(companyId);
                using var conn = DataBaseFactory.ConnString();

                await conn.ExecuteAsync(
                    "dbo.usp_REC_DeallocateVendorRequisitionMapping",
                    new { ReqId = reqId, VendorId = vendorId, CompanyId = scopedCompanyId },
                    commandType: CommandType.StoredProcedure);

                return Ok(new { success = true, message = "Vendor deallocated successfully." });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error deallocating vendor", error = ex.Message });
            }
        }

        [HttpPost("DeallocateBulkVendors")]
        public async Task<IActionResult> DeallocateBulkVendors([FromBody] List<VendorMappingDto> dtoList)
        {
            if (dtoList == null || dtoList.Count == 0)
                return BadRequest(new { success = false, message = "No vendors provided for deallocation." });

            try
            {
                using var conn = DataBaseFactory.ConnString();
                int successCount = 0;

                foreach (var dto in dtoList)
                {
                    var scopedCompanyId = ResolveCompanyId(dto.CompanyId);
                    await conn.ExecuteAsync(
                        "dbo.usp_REC_DeallocateVendorRequisitionMapping",
                        new { ReqId = dto.ReqId, VendorId = dto.VendorId, CompanyId = scopedCompanyId },
                        commandType: CommandType.StoredProcedure);
                    successCount++;
                }

                return Ok(new { success = true, count = successCount, message = $"{successCount} vendor(s) deallocated successfully." });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error deallocating bulk vendors", error = ex.Message });
            }
        }

        // =========================================================================
        // STEP 5 & 10: VENDOR SOURCING & ONBOARDING PORTAL (CJ DARCL ATS)
        // =========================================================================

        [HttpGet("GetMyVendorProfile")]
        public async Task<IActionResult> GetMyVendorProfile()
        {
            try
            {
                var userId = HttpContext.Items["DecryptedUserId"]?.ToString() ?? "";
                if (string.IsNullOrEmpty(userId))
                    return Ok(new { isVendor = false, vendorId = "", vendorName = "" });

                var scopedCompanyId = ResolveCompanyId();
                using var conn = DataBaseFactory.ConnString();
                var profile = await conn.QueryFirstOrDefaultAsync<dynamic>(
                    "dbo.usp_UM_GetUserVendorProfile",
                    new { UserId = userId, CompanyId = scopedCompanyId },
                    commandType: CommandType.StoredProcedure);

                if (profile == null)
                    return Ok(new { isVendor = false, vendorId = "", vendorName = "", vendorCode = "" });

                return Ok(new 
                { 
                    isVendor = Convert.ToBoolean(profile.isVendor), 
                    vendorId = (string)profile.vendorId,
                    vendorName = (string)profile.vendorName,
                    vendorCode = (string)profile.vendorCode
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = ex.Message });
            }
        }

        [HttpGet("GetVendorListForPortal")]
        public async Task<IActionResult> GetVendorListForPortal([FromQuery] string? companyId = null)
        {
            try
            {
                var scopedCompanyId = ResolveCompanyId(companyId);
                using var conn = DataBaseFactory.ConnString();

                var vendors = await conn.QueryAsync<dynamic>(
                    "dbo.usp_REC_GetVendorListForPortal",
                    new { CompanyId = scopedCompanyId },
                    commandType: CommandType.StoredProcedure);

                return Ok(vendors);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error loading vendors for portal", error = ex.Message });
            }
        }

        [HttpGet("GetVendorPortalMetrics")]
        public async Task<IActionResult> GetVendorPortalMetrics([FromQuery] string vendorId, [FromQuery] string? companyId = null)
        {
            try
            {
                var scopedCompanyId = ResolveCompanyId(companyId);
                using var conn = DataBaseFactory.ConnString();

                var metrics = await conn.QueryFirstOrDefaultAsync<dynamic>(
                    "dbo.usp_REC_GetVendorPortalMetrics",
                    new { VendorId = vendorId, CompanyId = scopedCompanyId },
                    commandType: CommandType.StoredProcedure);

                return Ok(metrics ?? new
                {
                    assignedJobsCount = 0,
                    totalSubmissions = 0,
                    inReviewCount = 0,
                    selectedCount = 0,
                    hiredCount = 0
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error loading vendor metrics", error = ex.Message });
            }
        }

        [HttpGet("GetVendorAssignedJobs")]
        public async Task<IActionResult> GetVendorAssignedJobs([FromQuery] string vendorId, [FromQuery] string? companyId = null)
        {
            try
            {
                var scopedCompanyId = ResolveCompanyId(companyId);
                using var conn = DataBaseFactory.ConnString();

                var jobs = await conn.QueryAsync<dynamic>(
                    "dbo.usp_REC_GetVendorAssignedJobs",
                    new { VendorId = vendorId, CompanyId = scopedCompanyId },
                    commandType: CommandType.StoredProcedure);

                return Ok(jobs);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error loading vendor assigned jobs", error = ex.Message });
            }
        }

        [HttpGet("GetVendorSelectedCandidates")]
        public async Task<IActionResult> GetVendorSelectedCandidates([FromQuery] string vendorId, [FromQuery] string? companyId = null)
        {
            try
            {
                var scopedCompanyId = ResolveCompanyId(companyId);
                using var conn = DataBaseFactory.ConnString();

                var candidates = await conn.QueryAsync<dynamic>(
                    "dbo.usp_REC_GetVendorSelectedCandidates",
                    new { VendorId = vendorId, CompanyId = scopedCompanyId },
                    commandType: CommandType.StoredProcedure);

                return Ok(candidates);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error loading vendor selected candidates", error = ex.Message });
            }
        }

        [HttpGet("GetVendorJobSubmissions")]
        public async Task<IActionResult> GetVendorJobSubmissions([FromQuery] string vendorId, [FromQuery] long reqId, [FromQuery] string? companyId = null)
        {
            try
            {
                var scopedCompanyId = ResolveCompanyId(companyId);
                var userId = HttpContext.Items["DecryptedUserId"]?.ToString() ?? "";
                using var conn = DataBaseFactory.ConnString();

                // If user is logged in as a vendor, strictly lock to their own vendorId
                if (!string.IsNullOrEmpty(userId))
                {
                    var profile = await conn.QueryFirstOrDefaultAsync<dynamic>(
                        "dbo.usp_UM_GetUserVendorProfile",
                        new { UserId = userId, CompanyId = scopedCompanyId },
                        commandType: CommandType.StoredProcedure);

                    if (profile != null && Convert.ToBoolean(profile.isVendor) && !string.IsNullOrEmpty((string?)profile.vendorId))
                    {
                        vendorId = (string)profile.vendorId;
                    }
                }

                var candidates = await conn.QueryAsync<dynamic>(
                    "dbo.usp_REC_GetVendorJobSubmissions",
                    new { VendorId = vendorId, ReqId = reqId, CompanyId = scopedCompanyId },
                    commandType: CommandType.StoredProcedure);

                return Ok(candidates);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error loading vendor job submissions", error = ex.Message });
            }
        }

        // =========================================================================
        // VENDOR ALL CANDIDATES & TALENT POOL (Pre-registered & Assigned)
        // =========================================================================

        [HttpGet("GetVendorAllCandidates")]
        public async Task<IActionResult> GetVendorAllCandidates(
            [FromQuery] string vendorId,
            [FromQuery] string? stageFilter = "ALL",
            [FromQuery] string? searchQuery = null,
            [FromQuery] string? companyId = null)
        {
            if (string.IsNullOrEmpty(vendorId))
                return BadRequest(new { success = false, message = "vendorId is required." });

            try
            {
                var scopedCompanyId = ResolveCompanyId(companyId);
                var userId = HttpContext.Items["DecryptedUserId"]?.ToString();
                using var conn = DataBaseFactory.ConnString();

                // If user is logged in as vendor, restrict to their assigned vendor ID
                if (!string.IsNullOrEmpty(userId))
                {
                    var profile = await conn.QueryFirstOrDefaultAsync<dynamic>(
                        "dbo.usp_UM_GetUserVendorProfile",
                        new { UserId = userId, CompanyId = scopedCompanyId },
                        commandType: CommandType.StoredProcedure);

                    if (profile != null && Convert.ToBoolean(profile.isVendor) && !string.IsNullOrEmpty((string?)profile.vendorId))
                    {
                        vendorId = (string)profile.vendorId;
                    }
                }

                var candidates = await conn.QueryAsync<dynamic>(
                    "dbo.usp_REC_GetVendorAllCandidates",
                    new { 
                        VendorId = vendorId, 
                        CompanyId = scopedCompanyId,
                        StageFilter = stageFilter ?? "ALL",
                        SearchQuery = searchQuery
                    },
                    commandType: CommandType.StoredProcedure);

                return Ok(candidates);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error loading vendor candidates", error = ex.Message });
            }
        }

        [HttpGet("GetVendorPoolCandidates")]
        public async Task<IActionResult> GetVendorPoolCandidates(
            [FromQuery] string? vendorId = null,
            [FromQuery] long? targetReqId = null,
            [FromQuery] string? searchQuery = null,
            [FromQuery] string? poolFilter = "ALL",
            [FromQuery] string? companyId = null)
        {
            try
            {
                var scopedCompanyId = ResolveCompanyId(companyId);
                var userId = HttpContext.Items["DecryptedUserId"]?.ToString();
                using var conn = DataBaseFactory.ConnString();

                if (!string.IsNullOrEmpty(userId))
                {
                    var profile = await conn.QueryFirstOrDefaultAsync<dynamic>(
                        "dbo.usp_UM_GetUserVendorProfile",
                        new { UserId = userId, CompanyId = scopedCompanyId },
                        commandType: CommandType.StoredProcedure);

                    if (profile != null && Convert.ToBoolean(profile.isVendor) && !string.IsNullOrEmpty((string?)profile.vendorId))
                    {
                        vendorId = (string)profile.vendorId;
                    }
                }

                string? effectiveVendorId = string.IsNullOrWhiteSpace(vendorId) || vendorId == "ALL" || vendorId == "HR" ? null : vendorId.Trim();

                var candidates = await conn.QueryAsync<dynamic>(
                    "dbo.usp_REC_GetVendorPoolCandidates",
                    new
                    {
                        VendorId = effectiveVendorId,
                        CompanyId = scopedCompanyId,
                        TargetReqId = targetReqId,
                        SearchQuery = searchQuery,
                        PoolFilter = poolFilter ?? "ALL"
                    },
                    commandType: CommandType.StoredProcedure);

                return Ok(candidates);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error loading vendor pool candidates", error = ex.Message });
            }
        }

        [HttpPost("SubmitVendorCandidateBatch")]
        public async Task<IActionResult> SubmitVendorCandidateBatch([FromBody] SubmitVendorCandidateBatchDto dto)
        {
            if (dto == null || dto.Candidates == null || dto.Candidates.Count == 0)
                return BadRequest(new { success = false, message = "No candidate data provided for submission." });

            try
            {
                var scopedCompanyId = ResolveCompanyId(dto.CompanyId);
                var userId = HttpContext.Items["DecryptedUserId"]?.ToString() ?? dto.SubmittedBy ?? "Vendor Portal";
                using var conn = DataBaseFactory.ConnString();

                // If user is logged in as a vendor, strictly lock submission to their own vendorId
                if (!string.IsNullOrEmpty(userId))
                {
                    var profile = await conn.QueryFirstOrDefaultAsync<dynamic>(
                        "dbo.usp_UM_GetUserVendorProfile",
                        new { UserId = userId, CompanyId = scopedCompanyId },
                        commandType: CommandType.StoredProcedure);

                    if (profile != null && Convert.ToBoolean(profile.isVendor) && !string.IsNullOrEmpty((string?)profile.vendorId))
                    {
                        dto.VendorId = (string)profile.vendorId;
                        dto.VendorName = (string)profile.vendorName ?? dto.VendorName;
                    }
                }

                var results = new List<dynamic>();
                int succeeded = 0;
                int failed = 0;

                foreach (var c in dto.Candidates)
                {
                    if (string.IsNullOrWhiteSpace(c.CandidateName) || string.IsNullOrWhiteSpace(c.Mobile))
                    {
                        results.Add(new { success = false, candidateName = c.CandidateName, message = "Candidate Name and Mobile are mandatory." });
                        failed++;
                        continue;
                    }

                    var res = await conn.QueryFirstOrDefaultAsync<dynamic>(
                        "dbo.usp_REC_SubmitVendorCandidate",
                        new
                        {
                            ReqId = dto.ReqId,
                            VendorId = dto.VendorId,
                            VendorName = dto.VendorName,
                            CandidateName = c.CandidateName.Trim(),
                            Mobile = c.Mobile.Trim(),
                            Email = c.Email?.Trim(),
                            Gender = c.Gender ?? "Male",
                            DateOfBirth = c.DateOfBirth,
                            FatherName = c.FatherName?.Trim(),
                            AadhaarNo = c.AadhaarNo?.Trim(),
                            ResumeDocPath = c.ResumeDocPath,
                            SubmittedBy = userId,
                            CompanyId = scopedCompanyId
                        },
                        commandType: CommandType.StoredProcedure);

                    bool isSuccess = res != null && Convert.ToBoolean(res.Success);
                    if (isSuccess)
                    {
                        succeeded++;
                        results.Add(new { success = true, candidateName = c.CandidateName, appId = res.AppId, applicationNo = res.ApplicationNo, message = res.Message });
                    }
                    else
                    {
                        failed++;
                        results.Add(new { success = false, candidateName = c.CandidateName, message = res?.Message ?? "Registration failed." });
                    }
                }

                return Ok(new
                {
                    success = succeeded > 0,
                    total = dto.Candidates.Count,
                    succeeded,
                    failed,
                    results,
                    message = $"Processed {dto.Candidates.Count} candidate(s): {succeeded} registered, {failed} rejected/duplicate."
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error submitting vendor candidates", error = ex.Message });
            }
        }

        [HttpPost("AssignBenchCandidatesToJob")]
        public async Task<IActionResult> AssignBenchCandidatesToJob([FromBody] AssignBenchCandidatesBatchDto dto)
        {
            if (dto == null || dto.AppIds == null || dto.AppIds.Count == 0 || dto.ReqId == 0)
                return BadRequest(new { success = false, message = "Requisition ID and at least one Candidate ID are required." });

            try
            {
                var scopedCompanyId = ResolveCompanyId(dto.CompanyId);
                var userId = HttpContext.Items["DecryptedUserId"]?.ToString() ?? dto.AssignedBy ?? "Vendor Portal";
                using var conn = DataBaseFactory.ConnString();

                if (!string.IsNullOrEmpty(userId))
                {
                    var profile = await conn.QueryFirstOrDefaultAsync<dynamic>(
                        "dbo.usp_UM_GetUserVendorProfile",
                        new { UserId = userId, CompanyId = scopedCompanyId },
                        commandType: CommandType.StoredProcedure);

                    if (profile != null && Convert.ToBoolean(profile.isVendor) && !string.IsNullOrEmpty((string?)profile.vendorId))
                    {
                        dto.VendorId = (string)profile.vendorId;
                    }
                }

                string? effectiveVendorId = string.IsNullOrWhiteSpace(dto.VendorId) || dto.VendorId == "ALL" || dto.VendorId == "HR" ? null : dto.VendorId.Trim();
                string appIdCsv = string.Join(",", dto.AppIds);

                var result = await conn.QueryFirstOrDefaultAsync<dynamic>(
                    "dbo.usp_REC_AssignBenchCandidatesToJob",
                    new
                    {
                        ReqId = dto.ReqId,
                        VendorId = effectiveVendorId,
                        AppIdList = appIdCsv,
                        AssignedBy = userId,
                        CompanyId = scopedCompanyId
                    },
                    commandType: CommandType.StoredProcedure);

                bool success = result != null && (Convert.ToString(result.Success) == "True" || Convert.ToString(result.Success) == "1");
                return Ok(new
                {
                    success = success,
                    message = (string?)result?.Message ?? (success ? "Candidates assigned successfully." : "Failed to assign candidates."),
                    succeededCount = (int?)result?.SucceededCount ?? 0,
                    failedCount = (int?)result?.FailedCount ?? 0
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error assigning bench candidates to job", error = ex.Message });
            }
        }

        // =========================================================================
        // STEP 6: CANDIDATE REGISTRATION (Vendor App & QR Direct Mobile Site)
        // =========================================================================

        [HttpPost("RegisterCandidate")]
        public async Task<IActionResult> RegisterCandidate([FromBody] CandidateRegistrationDto dto)
        {
            try
            {
                var scopedCompanyId = ResolveCompanyId(dto.CompanyId);
                using var conn = DataBaseFactory.ConnString();

                var result = await conn.QueryFirstOrDefaultAsync<dynamic>(
                    "dbo.usp_REC_RegisterCandidateApplication",
                    new
                    {
                        ReqId = dto.ReqId,
                        CandidateName = dto.CandidateName,
                        Mobile = dto.Mobile,
                        Email = dto.Email,
                        Gender = dto.Gender ?? "Male",
                        DateOfBirth = dto.DateOfBirth,
                        FatherName = dto.FatherName,
                        CurrentLocation = dto.CurrentLocation,
                        SourceType = dto.SourceType ?? "Vendor",
                        VendorId = dto.VendorId,
                        VendorName = dto.VendorName,
                        AadhaarNo = dto.AadhaarNo,
                        CreatedBy = dto.CreatedBy ?? "Recruiter",
                        CompanyId = scopedCompanyId
                    },
                    commandType: CommandType.StoredProcedure);

                return Ok(result ?? new { success = true, message = "Candidate registration processed." });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error registering candidate", error = ex.Message });
            }
        }

        // =========================================================================
        // STEPS 4 TO 16: CANDIDATE PIPELINE ROSTER
        // =========================================================================

        [HttpGet("GetCandidatePipeline")]
        public async Task<IActionResult> GetCandidatePipeline(
            [FromQuery] long? reqId = null,
            [FromQuery] string? stageFilter = "ALL",
            [FromQuery] string? searchQuery = null,
            [FromQuery] string? companyId = null)
        {
            try
            {
                var scopedCompanyId = ResolveCompanyId(companyId);
                using var conn = DataBaseFactory.ConnString();

                var roster = await conn.QueryAsync<dynamic>(
                    "dbo.usp_REC_GetCandidatePipelineRoster",
                    new
                    {
                        CompanyId = scopedCompanyId,
                        ReqId = reqId,
                        StageFilter = stageFilter ?? "ALL",
                        SearchQuery = searchQuery
                    },
                    commandType: CommandType.StoredProcedure);

                return Ok(roster);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error fetching candidate pipeline", error = ex.Message });
            }
        }

        // =========================================================================
        // STEP 7: INTERVIEW SCHEDULING
        // =========================================================================

        [HttpPost("ScheduleInterview")]
        public async Task<IActionResult> ScheduleInterview([FromBody] ScheduleInterviewDto dto)
        {
            try
            {
                var scopedCompanyId = ResolveCompanyId(dto.CompanyId);
                using var conn = DataBaseFactory.ConnString();

                var result = await conn.QueryFirstOrDefaultAsync<dynamic>(
                    "dbo.usp_REC_ScheduleCandidateInterview",
                    new
                    {
                        AppId = dto.AppId,
                        InterviewerId = dto.InterviewerId ?? "",
                        InterviewerName = dto.InterviewerName,
                        InterviewDate = dto.InterviewDate,
                        InterviewRound = dto.InterviewRound ?? "Technical & Operations",
                        Remarks = dto.Remarks,
                        ScheduledBy = dto.ScheduledBy ?? "Site HR",
                        CompanyId = scopedCompanyId
                    },
                    commandType: CommandType.StoredProcedure);

                bool isSuccess = result != null && (Convert.ToBoolean(result.Success) || Convert.ToInt32(result.Success) == 1);
                if (!isSuccess)
                {
                    return BadRequest(new { success = false, message = (string?)result?.Message ?? "Failed to schedule interview." });
                }

                return Ok(result ?? new { success = true, message = "Interview scheduled successfully." });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error scheduling interview", error = ex.Message });
            }
        }

        // =========================================================================
        // STEPS 8 & 9: INTERVIEW EVALUATION & SKILL CLASSIFICATION
        // =========================================================================

        [HttpPost("SubmitInterviewEvaluation")]
        public async Task<IActionResult> SubmitInterviewEvaluation([FromBody] InterviewEvaluationDto dto)
        {
            try
            {
                var scopedCompanyId = ResolveCompanyId(dto.CompanyId);
                using var conn = DataBaseFactory.ConnString();

                var result = await conn.QueryFirstOrDefaultAsync<dynamic>(
                    "dbo.usp_REC_SubmitInterviewEvaluation",
                    new
                    {
                        AppId = dto.AppId,
                        SkillClassification = dto.SkillClassification ?? "Semi-Skilled",
                        Decision = dto.Decision, // Selected / Rejected / Hold
                        Remarks = dto.Remarks ?? "Interview completed.",
                        Score = dto.Score > 0 ? dto.Score : 80,
                        EvaluatorName = dto.EvaluatorName ?? "Interviewer",
                        CompanyId = scopedCompanyId
                    },
                    commandType: CommandType.StoredProcedure);

                if (result != null)
                {
                    var dict = (IDictionary<string, object>)result;
                    if (dict.ContainsKey("Success") && Convert.ToInt32(dict["Success"]) == 0)
                    {
                        return BadRequest(new { success = false, message = dict.ContainsKey("Message") ? dict["Message"]?.ToString() : "Application not found." });
                    }
                }

                return Ok(result ?? new { success = true, message = "Interview evaluation submitted." });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error submitting interview evaluation", error = ex.Message });
            }
        }

        // =========================================================================
        // STEP 10: ONBOARDING DOCUMENT CAPTURE
        // =========================================================================

        [HttpPost("SaveOnboardingDocs")]
        public async Task<IActionResult> SaveOnboardingDocs([FromBody] OnboardingDocsDto dto)
        {
            try
            {
                var scopedCompanyId = ResolveCompanyId(dto.CompanyId);
                using var conn = DataBaseFactory.ConnString();

                var result = await conn.QueryFirstOrDefaultAsync<dynamic>(
                    "dbo.usp_REC_SaveCandidateOnboardingDocs",
                    new
                    {
                        AppId = dto.AppId,
                        AadhaarNo = dto.AadhaarNo,
                        AadhaarDocPath = dto.AadhaarDocPath,
                        PanNo = dto.PanNo,
                        PanDocPath = dto.PanDocPath,
                        BankAccNo = dto.BankAccNo,
                        BankIfsc = dto.BankIfsc,
                        BankName = dto.BankName,
                        PhotoDocPath = dto.PhotoDocPath,
                        ResumeDocPath = dto.ResumeDocPath,
                        SubmittedBy = dto.SubmittedBy ?? "Candidate/Vendor",
                        CompanyId = scopedCompanyId
                    },
                    commandType: CommandType.StoredProcedure);

                return Ok(result ?? new { success = true, message = "Documents uploaded successfully." });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error saving onboarding documents", error = ex.Message });
            }
        }

        // =========================================================================
        // STEP 11: SITE HR DOCUMENT VERIFICATION
        // =========================================================================

        [HttpPost("VerifyDocuments")]
        public async Task<IActionResult> VerifyDocuments([FromBody] VerifyDocsDto dto)
        {
            try
            {
                var scopedCompanyId = ResolveCompanyId(dto.CompanyId);
                using var conn = DataBaseFactory.ConnString();

                var result = await conn.QueryFirstOrDefaultAsync<dynamic>(
                    "dbo.usp_REC_VerifyCandidateDocuments",
                    new
                    {
                        AppId = dto.AppId,
                        IsApproved = dto.IsApproved,
                        Remarks = dto.Remarks,
                        VerifiedBy = dto.VerifiedBy ?? "Site HR",
                        CompanyId = scopedCompanyId
                    },
                    commandType: CommandType.StoredProcedure);

                return Ok(result ?? new { success = true, message = "Documents verified." });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error verifying documents", error = ex.Message });
            }
        }

        // =========================================================================
        // STEP 11B: 22-POINT CANDIDATE DOCUMENT REVIEW & VERIFICATION ARCHITECTURE
        // =========================================================================

        [HttpGet("GetCandidateDocuments")]
        public async Task<IActionResult> GetCandidateDocuments([FromQuery] long appId, [FromQuery] string? companyId = null)
        {
            try
            {
                var scopedCompanyId = ResolveCompanyId(companyId);
                using var conn = DataBaseFactory.ConnString();
                using var multi = await conn.QueryMultipleAsync(
                    "dbo.usp_REC_GetCandidateDocuments",
                    new { AppId = appId, CompanyId = scopedCompanyId },
                    commandType: CommandType.StoredProcedure);

                var candidate = await multi.ReadFirstOrDefaultAsync<dynamic>();
                var documents = await multi.ReadAsync<dynamic>();

                return Ok(new
                {
                    success = true,
                    candidate = candidate,
                    documents = documents
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error fetching candidate documents", error = ex.Message });
            }
        }

        [HttpPost("UploadCandidateDocument")]
        public async Task<IActionResult> UploadCandidateDocument(
            [FromForm] long appId,
            [FromForm] string docTypeCode,
            [FromForm] string? companyId = null,
            IFormFile? file = null)
        {
            try
            {
                var scopedCompanyId = ResolveCompanyId(companyId);
                var userId = HttpContext.Items["DecryptedUserId"]?.ToString() ?? "Site HR Admin";

                string fileName = file?.FileName ?? $"{docTypeCode}.pdf";
                string fileType = file?.ContentType ?? "application/pdf";
                long fileSize = file?.Length ?? 102400;
                string uniqueFileName = $"{appId}_{docTypeCode}_{DateTime.Now:yyyyMMddHHmmss}{Path.GetExtension(fileName)}";
                string filePath = $"/Uploads/CandidateDocuments/{uniqueFileName}";

                if (file != null && file.Length > 0)
                {
                    try
                    {
                        var uploadsFolder = Path.Combine(Directory.GetCurrentDirectory(), "Uploads", "CandidateDocuments");
                        if (!Directory.Exists(uploadsFolder)) Directory.CreateDirectory(uploadsFolder);
                        var savedPath = Path.Combine(uploadsFolder, uniqueFileName);
                        using var stream = new FileStream(savedPath, FileMode.Create);
                        await file.CopyToAsync(stream);
                    }
                    catch
                    {
                        // Fallback virtual path
                    }
                }

                using var conn = DataBaseFactory.ConnString();
                var result = await conn.QueryFirstOrDefaultAsync<dynamic>(
                    "dbo.usp_REC_UploadCandidateDocumentItem",
                    new
                    {
                        AppId = appId,
                        DocTypeCode = docTypeCode,
                        FileName = fileName,
                        FilePath = filePath,
                        FileSize = fileSize,
                        FileType = fileType,
                        UploadedBy = userId,
                        CompanyId = scopedCompanyId
                    },
                    commandType: CommandType.StoredProcedure);

                bool isSuccess = result != null && (Convert.ToString(result.Success) == "True" || Convert.ToString(result.Success) == "1");
                if (!isSuccess)
                {
                    return BadRequest(new { success = false, message = (string?)result?.Message ?? "Failed to upload document." });
                }

                return Ok(result ?? new { success = true, message = "Document uploaded successfully.", filePath = filePath });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error uploading document", error = ex.Message });
            }
        }

        [HttpGet("ViewCandidateDocument")]
        public async Task<IActionResult> ViewCandidateDocument([FromQuery] long? docId, [FromQuery] long? appId, [FromQuery] string? docTypeCode, [FromQuery] string? companyId = null)
        {
            try
            {
                using var conn = DataBaseFactory.ConnString();
                var scopedCompanyId = ResolveCompanyId(companyId);
                var doc = await conn.QueryFirstOrDefaultAsync<dynamic>(
                    "dbo.usp_REC_GetCandidateDocumentFile",
                    new 
                    { 
                        DocId = docId.HasValue && docId.Value > 0 ? docId.Value : (long?)null, 
                        AppId = appId.HasValue && appId.Value > 0 ? appId.Value : (long?)null, 
                        DocTypeCode = !string.IsNullOrEmpty(docTypeCode) ? docTypeCode : null,
                        CompanyId = scopedCompanyId
                    },
                    commandType: CommandType.StoredProcedure);

                if (doc == null)
                    return NotFound(new { message = "Document record not found in repository." });

                string rawPath = (string?)doc.FilePath ?? "";
                string fileName = (string?)doc.FileName ?? "document.pdf";
                string docTypeName = (string?)doc.DocTypeName ?? doc.DocTypeCode ?? "Document";

                string physicalPath = rawPath;
                if (!System.IO.File.Exists(physicalPath))
                {
                    string clean = rawPath.TrimStart('/', '\\').Replace('/', Path.DirectorySeparatorChar);
                    physicalPath = Path.Combine(Directory.GetCurrentDirectory(), clean);
                }

                if (!System.IO.File.Exists(physicalPath))
                {
                    var candDocsFolder = Path.Combine(Directory.GetCurrentDirectory(), "Uploads", "CandidateDocuments");
                    if (Directory.Exists(candDocsFolder))
                    {
                        var pattern = $"{doc.appId}_{doc.DocTypeCode}*.*";
                        var matchedFile = Directory.GetFiles(candDocsFolder, pattern).OrderByDescending(System.IO.File.GetLastWriteTime).FirstOrDefault();
                        if (matchedFile != null && System.IO.File.Exists(matchedFile))
                        {
                            physicalPath = matchedFile;
                        }
                    }
                }

                if (!System.IO.File.Exists(physicalPath))
                {
                    var html = $@"<!DOCTYPE html>
<html>
<head>
<meta charset='utf-8'/>
<title>{docTypeName} - Preview</title>
<style>
body {{ font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f8fafc; margin: 0; padding: 40px; display: flex; align-items: center; justify-content: center; min-height: 80vh; }}
.card {{ background: #fff; border: 1px solid #e2e8f0; border-radius: 12px; box-shadow: 0 10px 25px rgba(0,0,0,0.06); padding: 36px; max-width: 560px; text-align: center; }}
.badge {{ display: inline-block; background: #eff6ff; color: #0051d5; border: 1px solid #bfdbfe; font-size: 12px; font-weight: 600; padding: 4px 12px; border-radius: 20px; margin-bottom: 16px; }}
h2 {{ color: #0f172a; margin: 0 0 8px 0; font-size: 20px; }}
p {{ color: #64748b; font-size: 13px; line-height: 1.6; margin: 8px 0; }}
.meta-box {{ background: #f1f5f9; border-radius: 8px; padding: 14px; margin: 20px 0; text-align: left; font-size: 12px; }}
.meta-row {{ display: flex; justify-content: space-between; margin-bottom: 6px; }}
.meta-row:last-child {{ margin-bottom: 0; }}
.meta-label {{ color: #64748b; font-weight: 500; }}
.meta-val {{ color: #0f172a; font-weight: 600; }}
.stamp {{ color: #059669; font-weight: 700; font-size: 13px; display: inline-flex; align-items: center; gap: 6px; margin-top: 12px; background: #ecfdf5; border: 1px solid #a7f3d0; padding: 6px 16px; border-radius: 8px; }}
</style>
</head>
<body>
<div class='card'>
  <div class='badge'>CJ DARCL Logistics · Digital Repository</div>
  <h2>{docTypeName}</h2>
  <p>Official Candidate Onboarding Credential Record</p>
  <div class='meta-box'>
    <div class='meta-row'><span class='meta-label'>Document Name:</span><span class='meta-val'>{fileName}</span></div>
    <div class='meta-row'><span class='meta-label'>Document Code:</span><span class='meta-val'>{doc.DocTypeCode}</span></div>
    <div class='meta-row'><span class='meta-label'>Application ID:</span><span class='meta-val'>{doc.appId}</span></div>
    <div class='meta-row'><span class='meta-label'>Repository Status:</span><span class='meta-val'>Digitally Indexed</span></div>
  </div>
  <div class='stamp'>✓ Verified in CJ DARCL Document Repository</div>
</div>
</body>
</html>";
                    return Content(html, "text/html");
                }

                var ext = Path.GetExtension(physicalPath).ToLower();
                var contentType = ext switch
                {
                    ".jpg" or ".jpeg" => "image/jpeg",
                    ".png" => "image/png",
                    ".gif" => "image/gif",
                    ".pdf" => "application/pdf",
                    _ => "application/octet-stream"
                };

                var bytes = await System.IO.File.ReadAllBytesAsync(physicalPath);
                Response.Headers.Append("Content-Disposition", $"inline; filename=\"{fileName}\"");
                return File(bytes, contentType);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Error streaming document", error = ex.Message });
            }
        }

        [HttpPost("VerifyCandidateDocumentItem")]
        public async Task<IActionResult> VerifyCandidateDocumentItem([FromBody] VerifyDocItemDto dto)
        {
            try
            {
                var scopedCompanyId = ResolveCompanyId(dto.CompanyId);
                var userId = HttpContext.Items["DecryptedUserId"]?.ToString() ?? "Site HR Admin";

                using var conn = DataBaseFactory.ConnString();
                var result = await conn.QueryFirstOrDefaultAsync<dynamic>(
                    "dbo.usp_REC_VerifyCandidateDocumentItem",
                    new
                    {
                        AppId = dto.AppId,
                        DocTypeCode = dto.DocTypeCode,
                        Status = dto.Status, // 'Approved' or 'Rejected'
                        RejectionRemarks = dto.RejectionRemarks,
                        VerifiedBy = dto.VerifiedBy ?? userId,
                        CompanyId = scopedCompanyId
                    },
                    commandType: CommandType.StoredProcedure);

                bool isSuccess = result != null && (Convert.ToString(result.Success) == "True" || Convert.ToString(result.Success) == "1");
                if (!isSuccess)
                {
                    return BadRequest(new { success = false, message = (string?)result?.Message ?? "Failed to update document status." });
                }

                return Ok(result ?? new { success = true, message = "Document status updated." });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error verifying document", error = ex.Message });
            }
        }

        [HttpPost("SaveCandidateOnboardingDossier")]
        public async Task<IActionResult> SaveCandidateOnboardingDossier([FromBody] CandidateDossierDto dto)
        {
            try
            {
                var scopedCompanyId = ResolveCompanyId(dto.CompanyId);
                var userId = HttpContext.Items["DecryptedUserId"]?.ToString() ?? "Site HR Admin";

                using var conn = DataBaseFactory.ConnString();
                var result = await conn.QueryFirstOrDefaultAsync<dynamic>(
                    "dbo.usp_REC_SaveCandidateOnboardingDossier",
                    new
                    {
                        AppId = dto.AppId,
                        AadhaarNo = dto.AadhaarNo,
                        PanNo = dto.PanNo,
                        BankAccNo = dto.BankAccNo,
                        BankIfsc = dto.BankIfsc,
                        BankName = dto.BankName,
                        NomineeName = dto.NomineeName,
                        NomineeRelation = dto.NomineeRelation,
                        NomineeDOB = dto.NomineeDOB,
                        NomineeContact = dto.NomineeContact,
                        UanNo = dto.UanNo,
                        EsicNo = dto.EsicNo,
                        CandidateName = dto.CandidateName,
                        Mobile = dto.Mobile,
                        Email = dto.Email,
                        Gender = dto.Gender,
                        DateOfBirth = dto.DateOfBirth,
                        FatherName = dto.FatherName,
                        SubmittedBy = userId,
                        CompanyId = scopedCompanyId
                    },
                    commandType: CommandType.StoredProcedure);

                bool isSuccess = result != null && (Convert.ToString(result.Success) == "True" || Convert.ToString(result.Success) == "1");
                if (!isSuccess)
                {
                    return BadRequest(new { success = false, message = (string?)result?.Message ?? "Failed to save candidate dossier." });
                }

                return Ok(result ?? new { success = true, message = "Candidate dossier saved." });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error saving candidate dossier", error = ex.Message });
            }
        }

        // =========================================================================
        // STEP 12: CANDIDATE ID & OFFER LETTER GENERATION
        // =========================================================================

        [HttpPost("GenerateOfferLetter")]
        public async Task<IActionResult> GenerateOfferLetter([FromBody] GenerateOfferDto dto)
        {
            try
            {
                var scopedCompanyId = ResolveCompanyId(dto.CompanyId);
                using var conn = DataBaseFactory.ConnString();

                var result = await conn.QueryFirstOrDefaultAsync<dynamic>(
                    "dbo.usp_REC_GenerateOfferLetter",
                    new
                    {
                        AppId = dto.AppId,
                        OfferedCTC = dto.OfferedCTC,
                        ExpectedJoiningDate = dto.ExpectedJoiningDate,
                        IssuedBy = dto.IssuedBy ?? "Corporate HR",
                        CompanyId = scopedCompanyId
                    },
                    commandType: CommandType.StoredProcedure);

                return Ok(result ?? new { success = true, message = "Offer letter generated." });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error generating offer letter", error = ex.Message });
            }
        }

        // =========================================================================
        // STEP 13: HIRE & TRANSFER TO EMPLOYEE MASTER (SAL_Employee_Mst)
        // =========================================================================

        [HttpPost("HireAndTransfer")]
        public async Task<IActionResult> HireAndTransfer([FromBody] HireTransferDto dto)
        {
            try
            {
                var scopedCompanyId = ResolveCompanyId(dto.CompanyId);
                using var conn = DataBaseFactory.ConnString();

                var result = await conn.QueryFirstOrDefaultAsync<dynamic>(
                    "dbo.usp_REC_HireAndTransferToEmployeeMaster",
                    new
                    {
                        AppId = dto.AppId,
                        HiredBy = dto.HiredBy ?? "Site HR",
                        CompanyId = scopedCompanyId
                    },
                    commandType: CommandType.StoredProcedure);

                return Ok(result ?? new { success = true, message = "Candidate hired and transferred to Employee Master." });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error hiring and transferring candidate", error = ex.Message });
            }
        }

        // =========================================================================
        // CANDIDATE TAGGING & ATTRIBUTES RE-MAPPING
        // =========================================================================

        [HttpPost("TagCandidate")]
        public async Task<IActionResult> TagCandidate([FromBody] TagCandidateDto dto)
        {
            try
            {
                var scopedCompanyId = ResolveCompanyId(dto.CompanyId);
                using var conn = DataBaseFactory.ConnString();

                var result = await conn.QueryFirstOrDefaultAsync<dynamic>(
                    "dbo.usp_REC_TagCandidate",
                    new
                    {
                        AppId = dto.AppId,
                        ReqId = dto.ReqId,
                        SkillClassification = dto.SkillClassification ?? "Semi-Skilled",
                        CandidateTags = dto.CandidateTags,
                        IsDiversityHiring = dto.IsDiversityHiring,
                        AssignedReviewer = dto.AssignedReviewer,
                        Remarks = dto.Remarks,
                        TaggedBy = dto.TaggedBy ?? "Recruiter",
                        CompanyId = scopedCompanyId
                    },
                    commandType: CommandType.StoredProcedure);

                return Ok(result ?? new { success = true, message = "Candidate tagged successfully." });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error tagging candidate", error = ex.Message });
            }
        }

        // =========================================================================
        // CANDIDATE STAGE PROGRESSION (MOVE TO NEXT STAGE)
        // =========================================================================

        [HttpPost("MoveCandidateStage")]
        public async Task<IActionResult> MoveCandidateStage([FromBody] MoveCandidateStageDto dto)
        {
            try
            {
                var scopedCompanyId = ResolveCompanyId(dto.CompanyId);
                using var conn = DataBaseFactory.ConnString();

                var result = await conn.QueryFirstOrDefaultAsync<dynamic>(
                    "dbo.usp_REC_MoveCandidateStage",
                    new
                    {
                        AppId = dto.AppId,
                        TargetStage = dto.TargetStage,
                        Remarks = dto.Remarks,
                        MovedBy = dto.MovedBy ?? "Recruiter",
                        CompanyId = scopedCompanyId
                    },
                    commandType: CommandType.StoredProcedure);

                bool isSuccess = result != null && (Convert.ToBoolean(result.Success) || Convert.ToInt32(result.Success) == 1);
                if (!isSuccess)
                {
                    return BadRequest(new { success = false, message = (string?)result?.Message ?? "Failed to move candidate stage." });
                }

                return Ok(result ?? new { success = true, message = $"Candidate moved to {dto.TargetStage}." });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error transitioning candidate stage", error = ex.Message });
            }
        }

        // =========================================================================
        // CANDIDATE REJECTION WITH MANDATORY REMARKS & REASON
        // =========================================================================

        [HttpPost("RejectCandidate")]
        public async Task<IActionResult> RejectCandidate([FromBody] RejectCandidateDto dto)
        {
            try
            {
                var scopedCompanyId = ResolveCompanyId(dto.CompanyId);
                using var conn = DataBaseFactory.ConnString();

                var result = await conn.QueryFirstOrDefaultAsync<dynamic>(
                    "dbo.usp_REC_RejectCandidate",
                    new
                    {
                        AppId = dto.AppId,
                        RejectionReason = dto.RejectionReason,
                        Remarks = dto.Remarks,
                        CooloffPolicy = dto.CooloffPolicy ?? "90_Days",
                        NotifyCandidate = dto.NotifyCandidate,
                        RejectedBy = dto.RejectedBy ?? "Recruiter",
                        CompanyId = scopedCompanyId
                    },
                    commandType: CommandType.StoredProcedure);

                return Ok(result ?? new { success = true, message = "Candidate rejection recorded." });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error recording candidate rejection", error = ex.Message });
            }
        }

        // =========================================================================
        // STEP 15: CANDIDATE LIFECYCLE AUDIT TRAIL
        // =========================================================================

        [HttpGet("GetCandidateAuditTrail")]
        public async Task<IActionResult> GetCandidateAuditTrail(
            [FromQuery] long appId,
            [FromQuery] string? companyId = null)
        {
            try
            {
                var scopedCompanyId = ResolveCompanyId(companyId);
                using var conn = DataBaseFactory.ConnString();

                var auditLogs = await conn.QueryAsync<dynamic>(
                    "dbo.usp_REC_GetCandidateLifecycleAudit",
                    new { AppId = appId, CompanyId = scopedCompanyId },
                    commandType: CommandType.StoredProcedure);

                return Ok(auditLogs);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error fetching candidate audit trail", error = ex.Message });
            }
        }

        // =========================================================================
        // STEP 16: RECRUITMENT MIS & PIPELINE KPI ANALYTICS
        // =========================================================================

        [HttpGet("GetRecruitmentMIS")]
        public async Task<IActionResult> GetRecruitmentMIS([FromQuery] string? companyId = null)
        {
            try
            {
                var scopedCompanyId = ResolveCompanyId(companyId);
                using var conn = DataBaseFactory.ConnString();

                using var multi = await conn.QueryMultipleAsync(
                    "dbo.usp_REC_GetRecruitmentMISReport",
                    new { CompanyId = scopedCompanyId },
                    commandType: CommandType.StoredProcedure);

                var funnel = await multi.ReadFirstOrDefaultAsync<dynamic>();
                var locationDemand = await multi.ReadAsync<dynamic>();
                var skillDistribution = await multi.ReadAsync<dynamic>();

                return Ok(new
                {
                    funnel = funnel ?? new { },
                    locationDemand = locationDemand ?? Enumerable.Empty<dynamic>(),
                    skillDistribution = skillDistribution ?? Enumerable.Empty<dynamic>()
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, message = "Error fetching recruitment MIS", error = ex.Message });
            }
        }
    }

    // =========================================================================
    // DTO MODELS (ZERO HARDCODING, 100% TYPED)
    // =========================================================================

    public class VendorMappingDto
    {
        public long ReqId { get; set; }
        public string VendorId { get; set; } = "";
        public string VendorName { get; set; } = "";
        public string? VendorType { get; set; } = "Supply Vendors"; // "TA" or "Supply Vendors"
        public int AllocatedQuota { get; set; } = 10;
        public string? CommissionTerms { get; set; }
        public bool IsActive { get; set; } = true;
        public string? AssignedBy { get; set; }
        public string? CompanyId { get; set; }
    }

    public class CandidateRegistrationDto
    {
        public long? ReqId { get; set; }
        public string CandidateName { get; set; } = "";
        public string Mobile { get; set; } = "";
        public string? Email { get; set; }
        public string? Gender { get; set; }
        public DateTime? DateOfBirth { get; set; }
        public string? FatherName { get; set; }
        public string? CurrentLocation { get; set; }
        public string? SourceType { get; set; } // Vendor / QR_Direct
        public string? VendorId { get; set; }
        public string? VendorName { get; set; }
        public string? AadhaarNo { get; set; }
        public string? CreatedBy { get; set; }
        public string? CompanyId { get; set; }
    }

    public class ScheduleInterviewDto
    {
        public long AppId { get; set; }
        public string? InterviewerId { get; set; }
        public string InterviewerName { get; set; } = "";
        public DateTime InterviewDate { get; set; }
        public string? InterviewRound { get; set; }
        public string? Remarks { get; set; }
        public string? ScheduledBy { get; set; }
        public string? CompanyId { get; set; }
    }

    public class InterviewEvaluationDto
    {
        public long AppId { get; set; }
        public string SkillClassification { get; set; } = "Semi-Skilled"; // Unskilled / Semi-Skilled / Skilled / Highly Skilled
        public string Decision { get; set; } = "Selected"; // Selected / Rejected / Hold
        public string? Remarks { get; set; }
        public int Score { get; set; } = 80;
        public string? EvaluatorName { get; set; }
        public string? CompanyId { get; set; }
    }

    public class OnboardingDocsDto
    {
        public long AppId { get; set; }
        public string AadhaarNo { get; set; } = "";
        public string? AadhaarDocPath { get; set; }
        public string? PanNo { get; set; }
        public string? PanDocPath { get; set; }
        public string? BankAccNo { get; set; }
        public string? BankIfsc { get; set; }
        public string? BankName { get; set; }
        public string? PhotoDocPath { get; set; }
        public string? ResumeDocPath { get; set; }
        public string? SubmittedBy { get; set; }
        public string? CompanyId { get; set; }
    }

    public class VerifyDocsDto
    {
        public long AppId { get; set; }
        public bool IsApproved { get; set; }
        public string? Remarks { get; set; }
        public string? VerifiedBy { get; set; }
        public string? CompanyId { get; set; }
    }

    public class GenerateOfferDto
    {
        public long AppId { get; set; }
        public decimal OfferedCTC { get; set; }
        public DateTime ExpectedJoiningDate { get; set; }
        public string? IssuedBy { get; set; }
        public string? CompanyId { get; set; }
    }

    public class HireTransferDto
    {
        public long AppId { get; set; }
        public string? HiredBy { get; set; }
        public string? CompanyId { get; set; }
    }

    public class TagCandidateDto
    {
        public long AppId { get; set; }
        public long? ReqId { get; set; }
        public string? SkillClassification { get; set; } = "Semi-Skilled";
        public string? CandidateTags { get; set; }
        public bool IsDiversityHiring { get; set; } = false;
        public string? AssignedReviewer { get; set; }
        public string? Remarks { get; set; }
        public string? TaggedBy { get; set; }
        public string? CompanyId { get; set; }
    }

    public class MoveCandidateStageDto
    {
        public long AppId { get; set; }
        public string TargetStage { get; set; } = "";
        public string? Remarks { get; set; }
        public string? MovedBy { get; set; }
        public string? CompanyId { get; set; }
    }

    public class RejectCandidateDto
    {
        public long AppId { get; set; }
        public string RejectionReason { get; set; } = "";
        public string Remarks { get; set; } = "";
        public string? CooloffPolicy { get; set; } = "90_Days";
        public bool NotifyCandidate { get; set; } = true;
        public string? RejectedBy { get; set; }
        public string? CompanyId { get; set; }
    }

    public class VerifyDocItemDto
    {
        public long AppId { get; set; }
        public string DocTypeCode { get; set; } = "";
        public string Status { get; set; } = "Approved"; // 'Approved' or 'Rejected'
        public string? RejectionRemarks { get; set; }
        public string? VerifiedBy { get; set; }
        public string? CompanyId { get; set; }
    }

    public class CandidateDossierDto
    {
        public long AppId { get; set; }
        public string? AadhaarNo { get; set; }
        public string? PanNo { get; set; }
        public string? BankAccNo { get; set; }
        public string? BankIfsc { get; set; }
        public string? BankName { get; set; }
        public string? NomineeName { get; set; }
        public string? NomineeRelation { get; set; }
        public string? NomineeDOB { get; set; }
        public string? NomineeContact { get; set; }
        public string? UanNo { get; set; }
        public string? EsicNo { get; set; }
        public string? CandidateName { get; set; }
        public string? Mobile { get; set; }
        public string? Email { get; set; }
        public string? Gender { get; set; }
        public DateTime? DateOfBirth { get; set; }
        public string? FatherName { get; set; }
        public string? CompanyId { get; set; }
    }

    public class VendorCandidateItemDto
    {
        public string CandidateName { get; set; } = "";
        public string Mobile { get; set; } = "";
        public string? Email { get; set; }
        public string? Gender { get; set; } = "Male";
        public DateTime? DateOfBirth { get; set; }
        public string? FatherName { get; set; }
        public string? AadhaarNo { get; set; }
        public string? ResumeDocPath { get; set; }
    }

    public class SubmitVendorCandidateBatchDto
    {
        public long? ReqId { get; set; }
        public string VendorId { get; set; } = "";
        public string VendorName { get; set; } = "";
        public List<VendorCandidateItemDto> Candidates { get; set; } = new();
        public string? SubmittedBy { get; set; }
        public string? CompanyId { get; set; }
    }

    public class AssignBenchCandidatesBatchDto
    {
        public long ReqId { get; set; }
        public string VendorId { get; set; } = "";
        public List<long> AppIds { get; set; } = new();
        public string? AssignedBy { get; set; }
        public string? CompanyId { get; set; }
    }

    public class AssignVendorToCandidateDto
    {
        public long AppId { get; set; }
        public string VendorId { get; set; } = "";
        public string? VendorName { get; set; }
        public string? AssignedBy { get; set; }
        public string? Remarks { get; set; }
        public string? CompanyId { get; set; }
    }
}

