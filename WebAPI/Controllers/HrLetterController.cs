using HRMSWebAPI.Models;
using HRMSWebAPI.Repository;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using Syncfusion.DocIO;
using Syncfusion.DocIO.DLS;
using Syncfusion.DocIORenderer;
using Syncfusion.Pdf;

namespace HRMSWebAPI.Controllers
{
    [Route("api/v1/[controller]")]
    [ApiController]
    public class HrLetterController : ControllerBase
    {
        private readonly IHrLetterRepository hrLetterRepository;
        private readonly FileService fileService;
        private readonly IGenerateLetterRepository generateLetterRepository;

        private readonly AppSettings appSettings;

        public HrLetterController(IHrLetterRepository _hrLetterRepository, IGenerateLetterRepository _generateLetterRepository, FileService _fileService, IOptions<AppSettings> _appSettings)

        {
            hrLetterRepository = _hrLetterRepository;
            fileService = _fileService;
            appSettings = _appSettings.Value;
            generateLetterRepository = _generateLetterRepository;
        }

        [HttpGet]
        [Authorize]
        //public async Task<IActionResult> GetAllFileDownload()
        //{
        //    ModelResponse modelResponse = new ModelResponse();

        //    try
        //    {
        //        var decryptedCompanyId = HttpContext.Items["DecryptedCompanyId"]?.ToString();
        //        var fk_empid = HttpContext.Items["DecryptedUserId"]?.ToString();
        //        var filetype = "C";
        //        // Validate input
        //        if (string.IsNullOrEmpty(fk_empid) || string.IsNullOrEmpty(filetype) || string.IsNullOrEmpty(decryptedCompanyId))
        //        {
        //            modelResponse.IsSuccess = false;
        //            modelResponse.Message = "Required parameters are missing.";
        //            modelResponse.StatusCode = 400;
        //            return Ok(modelResponse);
        //        }

        //        //  Call repository
        //        var (totalCount, result) = await hrLetterRepository.GetAllFileDownload(fk_empid, filetype, decryptedCompanyId);

        //        //  Check empty result
        //        if (result == null || !result.Any())
        //        {
        //            modelResponse.IsSuccess = false;
        //            modelResponse.Message = "No record found.";
        //            modelResponse.StatusCode = 404;
        //            return Ok(modelResponse);
        //        }

        //        //  Success response
        //        modelResponse.IsSuccess = true;
        //        modelResponse.Message = "List retrieved successfully.";
        //        modelResponse.Data = result;
        //        modelResponse.TotalCount = totalCount;
        //        modelResponse.StatusCode = 200;

        //        return Ok(modelResponse);
        //    }
        //    catch (Exception ex)
        //    {
        //        // Error handling
        //        modelResponse.IsSuccess = false;
        //        modelResponse.Message = ex.Message;
        //        modelResponse.StatusCode = 500;
        //        return Ok(modelResponse);
        //    }
        //}

        public async Task<IActionResult> GetAllFileDownload()
        {
            ModelResponse modelResponse = new ModelResponse();
            try
            {
                var decryptedCompanyId = HttpContext.Items["DecryptedCompanyId"]?.ToString();
                var fk_empid = HttpContext.Items["DecryptedUserId"]?.ToString();

                // ✅ REMOVED filetype parameter - not needed for HR letters

                // Validate input
                if (string.IsNullOrEmpty(fk_empid))
                {
                    modelResponse.IsSuccess = false;
                    modelResponse.Message = "Employee ID is required.";
                    modelResponse.StatusCode = 400;
                    return Ok(modelResponse);
                }

                // ✅ CHANGED: Call new repository method for HR Letters
                var result = await hrLetterRepository.GetEmployeeHRLetters(fk_empid);

                // Check empty result
                if (result == null || !result.Any())
                {
                    modelResponse.IsSuccess = false;
                    modelResponse.Message = "No letters found.";
                    modelResponse.StatusCode = 404;
                    return Ok(modelResponse);
                }

                // Success response
                modelResponse.IsSuccess = true;
                modelResponse.Message = "Letters retrieved successfully.";
                modelResponse.Data = result;
                modelResponse.TotalCount = result.Count();
                modelResponse.StatusCode = 200;

                return Ok(modelResponse);
            }
            catch (Exception ex)
            {
                modelResponse.IsSuccess = false;
                modelResponse.Message = ex.Message;
                modelResponse.StatusCode = 500;
                return Ok(modelResponse);
            }
        }

        //[HttpGet("download-file")]
        //[Authorize]
        //public IActionResult DownloadFile(string filename)
        //{
        //    if (string.IsNullOrEmpty(filename))
        //        return BadRequest("Filename is required.");

        //    var folderPath = appSettings.UploadsFolderPath;
        //    var filePath = Path.Combine(folderPath, filename);

        //    if (!System.IO.File.Exists(filePath))
        //        return NotFound("File not found.");

        //    var contentType = GetMimeType(filePath);
        //    var fileBytes = System.IO.File.ReadAllBytes(filePath);
        //    return File(fileBytes, contentType, filename);
        //}

        //private string GetMimeType(string filePath)
        //{
        //    var fileExtension = Path.GetExtension(filePath).ToLower();
        //    return fileExtension switch
        //    {
        //        ".jpg" => "image/jpeg",
        //        ".jpeg" => "image/jpeg",
        //        ".png" => "image/png",
        //        ".gif" => "image/gif",
        //        ".bmp" => "image/bmp",
        //        ".tiff" => "image/tiff",
        //        ".pdf" => "application/pdf",
        //        _ => "application/octet-stream",
        //    };
        //}


        //[HttpGet("GetFile/{fileName}")]
        //[Authorize] // Optional: Secure it if needed
        //public IActionResult GetFile(string fileName)
        //{
        //    if (string.IsNullOrEmpty(fileName))
        //        return BadRequest("Filename not provided.");

        //    var uploadsPath = Path.Combine(Directory.GetCurrentDirectory(), "wwwroot/uploads");
        //    var filePath = Path.Combine(uploadsPath, fileName);

        //    if (!System.IO.File.Exists(filePath))
        //        return NotFound("File not found.");

        //    var mimeType = GetMimeType(filePath);
        //    var fileBytes = System.IO.File.ReadAllBytes(filePath);

        //    return File(fileBytes, mimeType, fileName); // Optional: replace fileName with original name if stored
        //}





        //Add ANJALI 5 FEB 2026

        [HttpGet("DownloadFormat/{pk_trnid}")]
        [Authorize]
        public async Task<IActionResult> DownloadFormat(long pk_trnid)
        {
            var response = new ModelResponse();

            try
            {
                // 1. Fetch All Data From SP
                var data = await generateLetterRepository.DownloadFormatAsync(pk_trnid);

                if (data == null || data.Trn == null)
                {
                    response.IsSuccess = false;
                    response.Message = "No record found.";
                    response.StatusCode = 404;
                    return Ok(response);
                }

                var company = data.Company;
                var trn = data.Trn;
                //var mst = data.Mst; // only one employee
                //var head = data.Head;
                var mst = ((IEnumerable<dynamic>)data.Mst).FirstOrDefault();
                var head = ((IEnumerable<dynamic>)data.Head).ToList();

                // 2. SELECT TEMPLATE BASED ON FORMAT TYPE
                string templateFile = trn.formattype switch
                {
                    "A" => "appointment_letter_template.docx",
                    "B" => "Confirmation_Letter_With_Increment.docx",
                    "R" => "promotion_letter_template.docx",
                    "D" => "increment_letter_template.docx",
                    "L" => "Retirement_Letter_Template.docx",
                    "F" => "Transfer_Letter_Template.docx",
                    "X" => "CONFIRMATIONOFEXTENSION.docx",
                    _ => "Default_Letter_Template.docx"

                };

                //string templatePath = Path.Combine(
                //   //  "D:\\VISHWANATH SIR LATEST\\HRMS currently working 30-09-2025\\Application\\WebAPI\\LetterTemplates",
                //   "D:\\HRMS_Code_2026\\LatestHRMS_28JAN\\WebAPI\\LetterTemplates",
                //    templateFile);

                string templatePath = Path.Combine(
    appSettings.LetterTemplatesFolderPath,
    templateFile);

                if (!System.IO.File.Exists(templatePath))
                {
                    response.IsSuccess = false;
                    response.Message = $"Template Not Found: {templateFile}";
                    response.StatusCode = 500;
                    return Ok(response);
                }

                // 3. Load Word Template
                using WordDocument document = new WordDocument(templatePath, FormatType.Docx);

                // 4. REPLACE PLACEHOLDERS
                //document.Replace("{{CompanyName}}", company.compname ?? "", true, true);
                document.Replace("{{CompanyName}}", "HR Book" ?? "", true, true);
                //document.Replace("{{CompanyAddress}}", company.address1 ?? "", true, true);
                document.Replace("{{CompanyAddress}}", "SVH Metro Street Sector 83" ?? "", true, true);
                // ========== CANDIDATE DETAILS ==========
                document.Replace("{{CandidateName}}", mst?.name ?? "", true, true);


                document.Replace("{{CandidateAddress}}", mst?.address ?? "", true, true);
                document.Replace("{{CandidateCityStatePin}}", mst?.pinno ?? "", true, true);

                document.Replace("{{HRName}}", mst?.HrName ?? "", true, true);
                document.Replace("{{Location}}", mst?.Location ?? "", true, true);

                document.Replace("{{CandidateName}}", mst?.name ?? "", true, true);
                document.Replace("{{Designation}}", mst?.DesignationName ?? "", true, true);
                document.Replace("{{DepartmentName}}", mst?.Department ?? "", true, true);
                document.Replace("{{JoiningDate}}",
                    mst?.joiningdate != null ? Convert.ToDateTime(mst.joiningdate).ToString("dd MMMM yyyy") : "", true, true);

                document.Replace("{{effectivedate}}",
                  trn.effectivedate != null ? Convert.ToDateTime(trn.effectivedate).ToString("dd MMMM yyyy") : "", true, true);

                document.Replace("{{Salary}}",
                    trn.ctc != null ? trn.ctc.ToString("N0") : "", true, true);

                document.Replace("{{CTCInWords}}", trn.newctcinword ?? "", true, true);
                //document.Replace("{{newctc}}", trn.newctc ?? "", true, true);


                document.Replace("{{EmployeeCode}}", trn.fk_empcooid ?? "", true, true);

                document.Replace("{{CurrentDate}}", DateTime.Now.ToString("dd MMMM yyyy"), true, true);

                document.Replace("{{resigndate}}",
                 trn.resigndate != null ? Convert.ToDateTime(trn.resigndate).ToString("dd MMMM yyyy") : "", true, true);

                document.Replace("{{contactno}}", trn.contactno ?? "", true, true);

                document.Replace("{{TransferLocation}}", trn.TransferLocation ?? "", true, true);
                document.Replace("{{trandate}}",
               trn.trandate != null ? Convert.ToDateTime(trn.trandate).ToString("dd MMMM yyyy") : "", true, true);

                document.Replace("{{IncrementAmount}}",
                   trn.IncrementAmount != null ? trn.IncrementAmount.ToString("N0") : "", true, true);

                document.Replace("{{PerMonthSalary}}",
                  trn.PerMonthSalary != null ? trn.PerMonthSalary.ToString("N0") : "", true, true);

                document.Replace("{{comments1}}", trn.comments1 ?? "", true, true);
                document.Replace("{{comments2}}", trn.comments2 ?? "", true, true);
                document.Replace("{{comments3}}", trn.comments3 ?? "", true, true);
                document.Replace("{{comments4}}", trn.comments4 ?? "", true, true);

                document.Replace("{{eperiod}}", trn.eperiod ?? "", true, true);

                //document.Replace("{{eperiod}}",
                //  trn.eperiod != null ? trn.eperiod.ToString("N0") : "", true, true);

                // 5. SAVE PDF
                //string outputFolder = Path.Combine(
                //        "D:\\VISHWANATH SIR LATEST\\HRMS currently working 30-09-2025\\Application\\WebAPI\\Templates");

                //Directory.CreateDirectory(outputFolder);

                //string fileName = $"Letter_{mst?.name}_{DateTime.Now:yyyyMMdd_HHmmss}";
                //string pdfPath = Path.Combine(outputFolder, fileName + ".pdf");

                //    using (DocIORenderer renderer = new DocIORenderer())
                //    {
                //        using (PdfDocument pdfDoc = renderer.ConvertToPDF(document))
                //        {
                //            pdfDoc.Save(pdfPath);
                //            pdfDoc.Close(true);
                //        }
                //    }

                //    document.Close();

                //    // 6. RETURN PDF FILE FOR DOWNLOAD  
                //    byte[] fileBytes = System.IO.File.ReadAllBytes(pdfPath);

                //    return File(
                //        fileBytes,
                //        "application/pdf",
                //        $"{fileName}.pdf"
                //    );
                //}

                using (DocIORenderer renderer = new DocIORenderer())
                {
                    using (PdfDocument pdfDoc = renderer.ConvertToPDF(document))
                    {
                        using (MemoryStream ms = new MemoryStream())
                        {
                            pdfDoc.Save(ms);
                            pdfDoc.Close(true);

                            byte[] pdfBytes = ms.ToArray();

                            string fileName = $"Letter_{mst?.name}_{DateTime.Now:yyyyMMdd_HHmmss}.pdf";

                            return File(
                                pdfBytes,
                                "application/pdf",
                                fileName
                            );
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                response.IsSuccess = false;
                response.Message = "Error: " + ex.Message;
                response.StatusCode = 500;
                return Ok(response);
            }
        }


        //[HttpGet("download-file/{pk_trnid}")]
        //[Authorize]
        //public async Task<IActionResult> DownloadFormats(long pk_trnid)
        //{
        //    var modelResponse = new ModelResponse();

        //    try
        //    {
        //        var result = await generateLetterRepository.DownloadFormatAsync(pk_trnid);

        //        // ❗ Same pattern check as your Leave Dashboard API
        //        //if (result == null ||
        //        //   (result.company == null && result.trn == null &&
        //        //    (result.mst == null)))
        //        //{
        //        //    modelResponse.IsSuccess = false;
        //        //    modelResponse.Message = "No record found.";
        //        //    modelResponse.StatusCode = 404;
        //        //    return Ok(modelResponse);
        //        //}

        //        // ✅ Success
        //        modelResponse.IsSuccess = true;
        //        modelResponse.Message = "Format details retrieved successfully.";
        //        modelResponse.Data = result;
        //        modelResponse.StatusCode = 200;

        //        return Ok(modelResponse);
        //    }
        //    catch (Exception ex)
        //    {
        //        // ❗ return error but still 200 OK as per your pattern
        //        modelResponse.IsSuccess = false;
        //        modelResponse.Message = ex.Message;
        //        modelResponse.StatusCode = 500;
        //        return Ok(modelResponse);
        //    }
        //}





        private string GetMimeType(string filePath)
        {
            var provider = new Microsoft.AspNetCore.StaticFiles.FileExtensionContentTypeProvider();
            if (!provider.TryGetContentType(filePath, out string contentType))
            {
                contentType = "application/octet-stream";
            }
            return contentType;
        }


    }
}