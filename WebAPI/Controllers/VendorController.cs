using ClosedXML.Excel;
using Dapper;
using DocumentFormat.OpenXml.EMMA;
using DocumentFormat.OpenXml.Spreadsheet;
using HRMSWebAPI.Helper;
using HRMSWebAPI.Models;
using HRMSWebAPI.Repository;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using System;
using System.Collections.Generic;
using System.Data.SqlClient;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Xml.Serialization;

namespace HRMSWebAPI.Controllers
{
    [Route("api/v1/[controller]")]
    [ApiController]
    public class VendorController : ControllerBase
    {
        private readonly IVendorRepository _vendorRepository;
        private readonly IConfiguration _configuration;
        public VendorController(IVendorRepository vendorRepository, IConfiguration configuration)
        {
            _vendorRepository = vendorRepository;
            _configuration = configuration;
        }

        [HttpGet("DownloadVendorVerificationExcel")]
        [Authorize]
        public async Task<IActionResult> DownloadVendorVerificationExcel([FromQuery] string searchTerm = "")
        {
            try
            {
                var companyId = HttpContext.Items["DecryptedCompanyId"]?.ToString() ?? "";
                var userId = HttpContext.Items["DecryptedUserId"]?.ToString() ?? "";
                var (_, vendors) = await _vendorRepository.GetVendorDownloadVerificationListAsync(1, 100000, companyId, userId, searchTerm);

                var vendorList = vendors?.ToList() ?? new List<VendorVerificationListModel>();
                if (!vendorList.Any())
                {
                    return BadRequest(new { IsSuccess = false, Message = "No vendor data found to download." });
                }

                using (var workbook = new XLWorkbook())
                {
                    var worksheet = workbook.Worksheets.Add("Vendor Verification");

                    // Header styling
                    var headers = new[] { "Sr. No.", "Vendor Code", "Vendor Name", "Email", "Verification Link", "Status" };
                    for (int i = 0; i < headers.Length; i++)
                    {
                        var cell = worksheet.Cell(1, i + 1);
                        cell.Value = headers[i];
                        cell.Style.Font.Bold = true;
                        cell.Style.Fill.BackgroundColor = XLColor.FromArgb(13, 110, 253);
                        cell.Style.Font.FontColor = XLColor.White;
                        cell.Style.Alignment.Horizontal = XLAlignmentHorizontalValues.Center;
                        cell.Style.Border.OutsideBorder = XLBorderStyleValues.Thin;
                        cell.Style.Border.OutsideBorderColor = XLColor.FromArgb(200, 200, 200);
                    }

                    int row = 2;
                    int srNo = 1;
                    foreach (var item in vendorList)
                    {
                        worksheet.Cell(row, 1).Value = srNo++;
                        worksheet.Cell(row, 1).Style.Alignment.Horizontal = XLAlignmentHorizontalValues.Center;

                        worksheet.Cell(row, 2).Value = item.VendorCode ?? "";
                        worksheet.Cell(row, 3).Value = item.VendorName ?? "";
                        worksheet.Cell(row, 4).Value = item.Email ?? "";
                        worksheet.Cell(row, 5).Value = item.VerificationLink ?? "";
                        worksheet.Cell(row, 6).Value = item.Status ?? "";

                        for (int col = 1; col <= headers.Length; col++)
                        {
                            worksheet.Cell(row, col).Style.Border.OutsideBorder = XLBorderStyleValues.Thin;
                            worksheet.Cell(row, col).Style.Border.OutsideBorderColor = XLColor.FromArgb(230, 230, 230);
                        }

                        row++;
                    }

                    worksheet.Columns().AdjustToContents();

                    using (var stream = new MemoryStream())
                    {
                        workbook.SaveAs(stream);
                        var fileBytes = stream.ToArray();
                        return File(
                            fileBytes,
                            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                            $"Vendor_Verification_List_{DateTime.Now:yyyyMMdd_HHmmss}.xlsx"
                        );
                    }
                }
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { IsSuccess = false, Message = ex.Message });
            }
        }


        [HttpPost("RateCardExcelUpload")]
        [Authorize]
        public async Task<IActionResult> UploadRateCard(IFormFile file)
        {
            ModelResponse modelResponse = new ModelResponse();
            try
            {
                if (file == null || file.Length == 0)
                    return Ok(new ModelResponse { IsSuccess = false, Message = "Excel file is required.", StatusCode = 400 });

                var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
                if (ext != ".xlsx" && ext != ".xls")
                    return Ok(new ModelResponse { IsSuccess = false, Message = "Only .xlsx or .xls files are allowed.", StatusCode = 400 });

                // STEP 1: Save uploaded Excel file to path configured in appsettings.json (VendorRateCardUploads)
                var uploadsFolder = _configuration["AppSettings:VendorRateCardUploads"];
                if (string.IsNullOrEmpty(uploadsFolder))
                {
                    uploadsFolder = Path.Combine(Directory.GetCurrentDirectory(), "VendorRateCardUploads");
                }
                if (!Directory.Exists(uploadsFolder))
                    Directory.CreateDirectory(uploadsFolder);

                var fileNameWithoutExt = Path.GetFileNameWithoutExtension(file.FileName);
                var savedFileName = $"{fileNameWithoutExt}_{DateTime.Now:ddMMyyyy_HHmmss}{ext}";
                var physicalPath = Path.Combine(uploadsFolder, savedFileName);

                using (var stream = new FileStream(physicalPath, FileMode.Create))
                {
                    await file.CopyToAsync(stream);
                }

                // STEP 2: Read Excel
                var data = ExcelHelper.ReadExcelDynamic(file);
                if (data == null || !data.Any())
                    return Ok(new ModelResponse { IsSuccess = false, Message = "Excel file has no data.", StatusCode = 400 });

                // STEP 3: Convert dynamic Excel rows to VendorRateCardModel
                var rateCards = MapToVendorRateCardModels(data);
                foreach (var card in rateCards)
                {
                    card.Source = savedFileName;
                    card.FilePath = physicalPath;
                }

                // STEP 4: Wrap in request object
                var request = new VendorRateCardUploadRequest
                {
                    RateCards = rateCards
                };

                // STEP 5: User context
                var userId = HttpContext.Items["DecryptedUserId"]?.ToString() ?? "";
                var companyId = HttpContext.Items["DecryptedCompanyId"]?.ToString() ?? "";
                var locationId = HttpContext.Items["DecryptedLocationId"]?.ToString() ?? "";

                // STEP 6: Call repository SP passing savedFileName
                var result = (await _vendorRepository.UploadRateCardAsync(request, userId, companyId, locationId, savedFileName))?.ToList()
                             ?? new List<dynamic>();


                //added code 31 aug 2026 starts
                // Multi-Tab Excel: Background Task to append Tab 2 (Upload Summary & Status)
                var resultsForExcel = result.ToList();
                _ = Task.Run(() =>
                {
                    try
                    {
                        using (var wb = new XLWorkbook(physicalPath))
                        {
                            var sourceWs = wb.Worksheets.FirstOrDefault(w => !w.Name.Equals("Upload Summary & Status", StringComparison.OrdinalIgnoreCase))
                                           ?? wb.Worksheet(1);

                            string summarySheetName = "Upload Summary & Status";
                            var existingSummary = wb.Worksheets.FirstOrDefault(w => w.Name.Equals(summarySheetName, StringComparison.OrdinalIgnoreCase));
                            if (existingSummary != null)
                            {
                                wb.Worksheets.Delete(existingSummary.Name);
                            }

                            var summaryWs = wb.Worksheets.Add(summarySheetName);

                            int totalCount = resultsForExcel.Count;
                            int successCount = resultsForExcel.Count(r =>
                            {
                                var dict = (IDictionary<string, object>)r;
                                var st = dict.ContainsKey("Status") ? Convert.ToString(dict["Status"]) : "";
                                return st == "Uploaded" || st == "Inserted" || st == "Updated" || st == "Success";
                            });
                            int failedCount = totalCount - successCount;

                            // Top Summary Metrics
                            summaryWs.Cell(1, 1).Value = "Total Records";
                            summaryWs.Cell(1, 1).Style.Font.Bold = true;
                            summaryWs.Cell(1, 1).Style.Fill.BackgroundColor = XLColor.FromArgb(13, 110, 253);
                            summaryWs.Cell(1, 1).Style.Font.FontColor = XLColor.White;
                            summaryWs.Cell(1, 1).Style.Alignment.Horizontal = XLAlignmentHorizontalValues.Center;

                            summaryWs.Cell(1, 2).Value = "Success / Uploaded";
                            summaryWs.Cell(1, 2).Style.Font.Bold = true;
                            summaryWs.Cell(1, 2).Style.Fill.BackgroundColor = XLColor.FromArgb(25, 135, 84);
                            summaryWs.Cell(1, 2).Style.Font.FontColor = XLColor.White;
                            summaryWs.Cell(1, 2).Style.Alignment.Horizontal = XLAlignmentHorizontalValues.Center;

                            summaryWs.Cell(1, 3).Value = "Failed / Not Uploaded";
                            summaryWs.Cell(1, 3).Style.Font.Bold = true;
                            summaryWs.Cell(1, 3).Style.Fill.BackgroundColor = XLColor.FromArgb(220, 53, 69);
                            summaryWs.Cell(1, 3).Style.Font.FontColor = XLColor.White;
                            summaryWs.Cell(1, 3).Style.Alignment.Horizontal = XLAlignmentHorizontalValues.Center;

                            summaryWs.Cell(2, 1).Value = totalCount;
                            summaryWs.Cell(2, 1).Style.Font.Bold = true;
                            summaryWs.Cell(2, 1).Style.Alignment.Horizontal = XLAlignmentHorizontalValues.Center;

                            summaryWs.Cell(2, 2).Value = successCount;
                            summaryWs.Cell(2, 2).Style.Font.Bold = true;
                            summaryWs.Cell(2, 2).Style.Alignment.Horizontal = XLAlignmentHorizontalValues.Center;

                            summaryWs.Cell(2, 3).Value = failedCount;
                            summaryWs.Cell(2, 3).Style.Font.Bold = true;
                            summaryWs.Cell(2, 3).Style.Alignment.Horizontal = XLAlignmentHorizontalValues.Center;

                            // Tab 2 Detailed Header (Sr. No + Status / Remarks + All original Tab 1 columns)
                            int summaryHeaderRow = 4;
                            summaryWs.Cell(summaryHeaderRow, 1).Value = "Sr. No";
                            summaryWs.Cell(summaryHeaderRow, 1).Style.Font.Bold = true;
                            summaryWs.Cell(summaryHeaderRow, 1).Style.Fill.BackgroundColor = XLColor.FromArgb(52, 58, 64);
                            summaryWs.Cell(summaryHeaderRow, 1).Style.Font.FontColor = XLColor.White;

                            summaryWs.Cell(summaryHeaderRow, 2).Value = "Status / Remarks";
                            summaryWs.Cell(summaryHeaderRow, 2).Style.Font.Bold = true;
                            summaryWs.Cell(summaryHeaderRow, 2).Style.Fill.BackgroundColor = XLColor.FromArgb(52, 58, 64);
                            summaryWs.Cell(summaryHeaderRow, 2).Style.Font.FontColor = XLColor.White;

                            var firstRow = sourceWs.FirstRowUsed();
                            int sourceColCount = firstRow != null ? firstRow.LastCellUsed()?.Address.ColumnNumber ?? 0 : 0;
                            if (sourceColCount == 0 && sourceWs.LastColumnUsed() != null)
                            {
                                sourceColCount = sourceWs.LastColumnUsed().ColumnNumber();
                            }

                            for (int col = 1; col <= sourceColCount; col++)
                            {
                                var cell = summaryWs.Cell(summaryHeaderRow, col + 2);
                                cell.Value = sourceWs.Cell(1, col).Value;
                                cell.Style.Font.Bold = true;
                                cell.Style.Fill.BackgroundColor = XLColor.FromArgb(52, 58, 64);
                                cell.Style.Font.FontColor = XLColor.White;
                            }

                            // Copy Data rows from Tab 1 and attach Status / Remarks
                            int sourceLastRow = sourceWs.LastRowUsed()?.RowNumber() ?? 1;
                            int currRow = 5;

                            for (int r = 2; r <= sourceLastRow; r++)
                            {
                                int dataIdx = r - 2;
                                summaryWs.Cell(currRow, 1).Value = dataIdx + 1;

                                if (dataIdx < resultsForExcel.Count)
                                {
                                    var dict = (IDictionary<string, object>)resultsForExcel[dataIdx];
                                    string st = dict.ContainsKey("Status") ? Convert.ToString(dict["Status"]) ?? "" : "";
                                    string rem = dict.ContainsKey("Remarks") ? Convert.ToString(dict["Remarks"]) ?? "" : "";

                                    string statusDisplay = "Uploaded";
                                    if (st == "Failed" || st == "Not Uploaded" || st == "Error" || (st != "Uploaded" && st != "Inserted" && st != "Updated"))
                                    {
                                        statusDisplay = $"Failed - {(string.IsNullOrEmpty(rem) ? "Validation error" : rem)}";
                                        summaryWs.Cell(currRow, 2).Value = statusDisplay;
                                        summaryWs.Cell(currRow, 2).Style.Font.FontColor = XLColor.Red;
                                        summaryWs.Cell(currRow, 2).Style.Font.Bold = true;
                                    }
                                    else if (st == "Already Exists" || st == "Skipped")
                                    {
                                        statusDisplay = "Already Exists";
                                        summaryWs.Cell(currRow, 2).Value = statusDisplay;
                                        summaryWs.Cell(currRow, 2).Style.Font.FontColor = XLColor.FromArgb(255, 140, 0);
                                        summaryWs.Cell(currRow, 2).Style.Font.Bold = true;
                                    }
                                    else
                                    {
                                        statusDisplay = "Uploaded";
                                        summaryWs.Cell(currRow, 2).Value = statusDisplay;
                                        summaryWs.Cell(currRow, 2).Style.Font.FontColor = XLColor.Green;
                                        summaryWs.Cell(currRow, 2).Style.Font.Bold = true;
                                    }
                                }
                                else
                                {
                                    summaryWs.Cell(currRow, 2).Value = "Uploaded";
                                    summaryWs.Cell(currRow, 2).Style.Font.FontColor = XLColor.Green;
                                    summaryWs.Cell(currRow, 2).Style.Font.Bold = true;
                                }

                                // Copy all columns exactly as in Tab 1
                                for (int col = 1; col <= sourceColCount; col++)
                                {
                                    summaryWs.Cell(currRow, col + 2).Value = sourceWs.Cell(r, col).Value;
                                }

                                currRow++;
                            }

                            summaryWs.Columns().AdjustToContents();
                            wb.Save();
                        }
                    }
                    catch (Exception exWb)
                    {
                        Console.WriteLine("Could not append summary sheet to Rate Card Excel: " + exWb.Message);
                    }
                });
                //added code 31 aug 2026 ends



                var uploadedCount = result.Count(r =>
                {
                    var status = Convert.ToString(((IDictionary<string, object>)r)["Status"]);
                    return status == "Uploaded" || status == "Inserted" || status == "Updated";
                });
                var notUploadedCount = result.Count - uploadedCount;




                modelResponse.IsSuccess = true;
                modelResponse.Message = $"Upload complete. Processed: {uploadedCount}, Failed: {notUploadedCount}.";
                modelResponse.Data = result;
                modelResponse.StatusCode = 200;

                return Ok(modelResponse);
            }
            catch (Exception ex)
            {
                string details = ex.InnerException != null
                    ? $"{ex.Message} | Inner: {ex.InnerException.Message}"
                    : ex.Message;

                if (ex is SqlException sqlEx)
                {
                    var realErrors = sqlEx.Errors.Cast<SqlError>()
                        .Where(e => e.Number != 3930)
                        .Select(e => $"[{e.Number}] {e.Message}")
                        .ToList();

                    if (realErrors.Any())
                    {
                        details = string.Join(" | ", realErrors);
                    }
                    else
                    {
                        details = $"{ex.Message} | Full: {sqlEx.ToString()}";
                    }
                }
                return Ok(new ModelResponse { IsSuccess = false, Message = details, StatusCode = 500 });
            }
            //catch (Exception ex)
            //{
            //    return Ok(new ModelResponse { IsSuccess = false, Message = ex.Message, StatusCode = 500 });
            //}
        }







        [HttpGet("GetAll")]
        [Authorize]
        public async Task<IActionResult> GetAll([FromQuery] int pageIndex = 0, [FromQuery] int pageSize = 100, [FromQuery] string searchTerm = "")
        {
            ModelResponse modelResponse = new ModelResponse();
            try
            {
                var companyId = HttpContext.Items["DecryptedCompanyId"]!.ToString();

                var (totalCount, list) = await _vendorRepository.GetVendorListAsync(pageIndex, pageSize, companyId, searchTerm);

                modelResponse.IsSuccess = true;
                modelResponse.Message = "Vendor Rate Card list retrieved successfully.";
                modelResponse.Data = new { totalCount, list };
                modelResponse.StatusCode = 200;

                return Ok(modelResponse);
            }
            catch (Exception ex)
            {
                modelResponse.IsSuccess = false;
                modelResponse.Message = ex.Message;
                return Ok(modelResponse);
            }
        }



        private static List<VendorRateCardModel> MapToVendorRateCardModels(List<Dictionary<string, string>> data)
        {
            var list = new List<VendorRateCardModel>();
            foreach (var row in data)
            {
                var model = new VendorRateCardModel();
                string? rawNormalRate = null;
                string? rawPickupRate = null;
                string? rawMfnRate = null;
                string? rawVanRate = null;
                string? rawU2sRate = null;
                string? rawShopsyRate = null;
                string? rawPrexoRate = null;
                string? rawGroceryRate = null;
                string? rawRtoRate = null;
                string? rawDtoRate = null;
                string? rawFmRate  = null;

                foreach (var kvp in row)
                {
                    if (string.IsNullOrWhiteSpace(kvp.Key)) continue;
                    var keyNorm = kvp.Key.Replace(" ", "").Replace("_", "").ToLowerInvariant();
                    var val = kvp.Value?.Trim();

                    switch (keyNorm)
                    {
                        case "vendorcode":
                        case "code":
                            model.Vendor_Code = val;
                            break;
                        case "vendorname":
                        case "name":
                            model.Vendor_Name = val;
                            break;
                        case "clientname":
                        case "client":
                        case "costcentre":
                            model.Client_Name = val;
                            break;
                        case "location":
                        case "locationid":
                            model.LocationID = val;
                            break;
                        case "vendorhfrid":
                        case "hfrid":
                        case "fhrid":
                            model.FHRID = val;
                            model.Vendor_HFRID = val;
                            break;
                        case "vendorratetype":
                        case "ratetype":
                            model.Vendor_RateType = val;
                            break;
                        case "vendortype":
                        case "type":
                            model.Vendor_Type = val;
                            break;
                        case "model":
                        case "modelname":
                            var cleanMod = val;
                            if (!string.IsNullOrEmpty(cleanMod) && cleanMod.Contains(":"))
                            {
                                cleanMod = cleanMod.Split(':')[0].Trim();
                            }
                            model.Model = cleanMod;
                            break;
                        case "vendorcategoryid":
                        case "categoryid":
                        case "category":
                            model.Vendor_CategoryID = val;
                            break;
                        case "vehicletype":
                        case "largevehicletypename":
                            model.Large_VehicleTypeName = val;
                            break;
                        case "normalrate":
                            rawNormalRate = val;
                            break;
                        case "normalratetype":
                            model.Normal_RateType = FormatRateType(val);
                            break;
                        case "normalslabexpr":
                            model.Normal_SlabExpr = val;
                            break;
                        case "vendorrate":
                        case "rate":
                            rawNormalRate = val;
                            break;
                        case "vendorratededuction":
                        case "ratededuction":
                        case "deduction":
                            if (decimal.TryParse(val, out var rdVal)) model.Vendor_RateDeduction = rdVal;
                            break;
                        case "vendordeliveryrate":
                        case "deliveryrate":
                            if (decimal.TryParse(val, out var drVal)) model.Vendor_DeliveryRate = drVal;
                            break;
                        case "vendorpickuprate":
                        case "pickuprate":
                            rawPickupRate = val;
                            break;
                        case "pickupratetype":
                            model.Pickup_RateType = FormatRateType(val);
                            break;
                        case "pickupslabexpr":
                            model.Pickup_SlabExpr = val;
                            break;
                        case "vendortds":
                        case "vendortdspercentage":
                        case "tds":
                        case "tdspercentage":
                            if (decimal.TryParse(val, out var tdsVal)) model.Vendor_TDS = tdsVal;
                            break;
                        case "vendormfnrate":
                        case "mfnrate":
                        case "mfn":
                            rawMfnRate = val;
                            break;
                        case "mfnratetype":
                            model.MFN_RateType = FormatRateType(val);
                            break;
                        case "mfnslabexpr":
                            model.MFN_SlabExpr = val;
                            break;
                        case "vanrate":
                            rawVanRate = val;
                            break;
                        case "vanratetype":
                            model.Van_RateType = FormatRateType(val);
                            break;
                        case "vanslabexpr":
                            model.Van_SlabExpr = val;
                            break;
                        case "u2srate":
                            rawU2sRate = val;
                            break;
                        case "u2sratetype":
                            model.U2S_RateType = FormatRateType(val);
                            break;
                        case "u2sslabexpr":
                            model.U2S_SlabExpr = val;
                            break;
                        case "shopsydeductionrate":
                        case "shopsyrate":
                            rawShopsyRate = val;
                            break;

                        case "shopsyratetype":
                            model.Shopsy_RateType = FormatRateType(val);
                            break;
                        case "shopsydeductionratetype":
                            model.Shopsy_RateType = FormatRateType(val);
                            break; // given by raj


                        case "shopsyslabexpr":
                            model.Shopsy_SlabExpr = val;
                            break;
                        case "prexorate":
                            rawPrexoRate = val;
                            break;
                        case "prexoratetype":
                            model.Prexo_RateType = FormatRateType(val);
                            break;
                        case "prexoslabexpr":
                            model.Prexo_SlabExpr = val;
                            break;
                        case "groceryrate":
                            rawGroceryRate = val;
                            break;
                        case "groceryratetype":
                            model.Grocery_RateType = FormatRateType(val);
                            break;
                        case "groceryslabexpr":
                            model.Grocery_SlabExpr = val;
                            break;

                        case "rtorate":
                            rawRtoRate = val;
                            break;
                        case "rtoratetype":
                            model.Rto_RateType = FormatRateType(val);
                            break;
                        case "rtoslabexpr":
                            model.Rto_SlabExpr = val;
                            break;

                        case "dtorate":
                            rawDtoRate = val;
                            break;
                        case "dtoratetype":
                            model.Dto_RateType = FormatRateType(val);
                            break;
                        case "dtoslabexpr":
                            model.Dto_SlabExpr = val;
                            break;

                        case "fmrate":
                            rawFmRate = val;
                            break;
                        case "fmratetype":
                            model.Fm_RateType = FormatRateType(val);
                            break;
                        case "fmslabexpr":
                            model.Fm_SlabExpr = val;
                            break;
                        case "effectivefrom":
                        case "startdate":
                            model.EffectiveFrom = FormatEffectiveDate(val);
                            break;
                    }
                }

                // Process Normal Rate / Slab
                var normalType = model.Normal_RateType ?? "Fixed";
                if (normalType.Equals("Slab", StringComparison.OrdinalIgnoreCase))
                {
                    if (string.IsNullOrEmpty(model.Normal_SlabExpr)) model.Normal_SlabExpr = rawNormalRate;
                    model.Normal_Rate = null;
                }
                else
                {
                    model.Normal_SlabExpr = null;
                    if (decimal.TryParse(rawNormalRate, out var nVal)) model.Normal_Rate = nVal;
                }
                if (model.Normal_Rate.HasValue) model.Vendor_Rate = model.Normal_Rate.Value;

                // Process Pickup Rate / Slab
                var pickupType = model.Pickup_RateType ?? "Fixed";
                if (pickupType.Equals("Slab", StringComparison.OrdinalIgnoreCase))
                {
                    if (string.IsNullOrEmpty(model.Pickup_SlabExpr)) model.Pickup_SlabExpr = rawPickupRate;
                    model.Pickup_Rate = null;
                }
                else
                {
                    model.Pickup_SlabExpr = null;
                    if (decimal.TryParse(rawPickupRate, out var pVal)) model.Pickup_Rate = pVal;
                }
                if (model.Pickup_Rate.HasValue) model.Vendor_PickupRate = model.Pickup_Rate.Value;

                // Process MFN Rate / Slab
                var mfnType = model.MFN_RateType ?? "Fixed";
                if (mfnType.Equals("Slab", StringComparison.OrdinalIgnoreCase))
                {
                    if (string.IsNullOrEmpty(model.MFN_SlabExpr)) model.MFN_SlabExpr = rawMfnRate;
                    model.MFN_Rate = null;
                }
                else
                {
                    model.MFN_SlabExpr = null;
                    if (decimal.TryParse(rawMfnRate, out var mVal)) model.MFN_Rate = mVal;
                }
                if (model.MFN_Rate.HasValue) model.Vendor_MFNRate = model.MFN_Rate.Value;

                // Process Van Rate / Slab
                var vanType = model.Van_RateType ?? "Fixed";
                if (vanType.Equals("Slab", StringComparison.OrdinalIgnoreCase))
                {
                    if (string.IsNullOrEmpty(model.Van_SlabExpr)) model.Van_SlabExpr = rawVanRate;
                    model.Van_Rate = null;
                }
                else
                {
                    model.Van_SlabExpr = null;
                    if (decimal.TryParse(rawVanRate, out var vVal)) model.Van_Rate = vVal;
                }

                // Process U2S Rate / Slab
                var u2sType = model.U2S_RateType ?? "Fixed";
                if (u2sType.Equals("Slab", StringComparison.OrdinalIgnoreCase))
                {
                    if (string.IsNullOrEmpty(model.U2S_SlabExpr)) model.U2S_SlabExpr = rawU2sRate;
                    model.U2S_Rate = null;
                }
                else
                {
                    model.U2S_SlabExpr = null;
                    if (decimal.TryParse(rawU2sRate, out var uVal)) model.U2S_Rate = uVal;
                }

                // Process Shopsy Rate / Slab
                var shopsyType = model.Shopsy_RateType ?? "Fixed";
                if (shopsyType.Equals("Slab", StringComparison.OrdinalIgnoreCase))
                {
                    if (string.IsNullOrEmpty(model.Shopsy_SlabExpr)) model.Shopsy_SlabExpr = rawShopsyRate;
                    model.Shopsy_Deduction_Rate = null;
                }
                else
                {
                    model.Shopsy_SlabExpr = null;
                    if (decimal.TryParse(rawShopsyRate, out var sVal)) model.Shopsy_Deduction_Rate = sVal;
                }

                // Process Prexo Rate / Slab
                var prexoType = model.Prexo_RateType ?? "Fixed";
                if (prexoType.Equals("Slab", StringComparison.OrdinalIgnoreCase))
                {
                    if (string.IsNullOrEmpty(model.Prexo_SlabExpr)) model.Prexo_SlabExpr = rawPrexoRate;
                    model.Prexo_Rate = null;
                }
                else
                {
                    model.Prexo_SlabExpr = null;
                    if (decimal.TryParse(rawPrexoRate, out var prVal)) model.Prexo_Rate = prVal;
                }

                // Process Grocery Rate / Slab
                var groceryType = model.Grocery_RateType ?? "Fixed";
                if (groceryType.Equals("Slab", StringComparison.OrdinalIgnoreCase))
                {
                    if (string.IsNullOrEmpty(model.Grocery_SlabExpr)) model.Grocery_SlabExpr = rawGroceryRate;
                    model.Grocery_Rate = null;
                }
                else
                {
                    model.Grocery_SlabExpr = null;
                    if (decimal.TryParse(rawGroceryRate, out var gVal)) model.Grocery_Rate = gVal;
                }

                // Process RTO Rate / Slab
                var rtoType = model.Rto_RateType ?? "Fixed";
                if (rtoType.Equals("Slab", StringComparison.OrdinalIgnoreCase))
                {
                    if (string.IsNullOrEmpty(model.Rto_SlabExpr)) model.Rto_SlabExpr = rawRtoRate;
                    model.Rto_Rate = null;
                }
                else
                {
                    model.Rto_SlabExpr = null;
                    if (decimal.TryParse(rawRtoRate, out var rtoVal)) model.Rto_Rate = rtoVal;
                }

                // Process DTO Rate / Slab
                var dtoType = model.Dto_RateType ?? "Fixed";
                if (dtoType.Equals("Slab", StringComparison.OrdinalIgnoreCase))
                {
                    if (string.IsNullOrEmpty(model.Dto_SlabExpr)) model.Dto_SlabExpr = rawDtoRate;
                    model.Dto_Rate = null;
                }
                else
                {
                    model.Dto_SlabExpr = null;
                    if (decimal.TryParse(rawDtoRate, out var dtoVal)) model.Dto_Rate = dtoVal;
                }

                // Process FM Rate / Slab
                var fmType = model.Fm_RateType ?? "Fixed";
                if (fmType.Equals("Slab", StringComparison.OrdinalIgnoreCase))
                {
                    if (string.IsNullOrEmpty(model.Fm_SlabExpr)) model.Fm_SlabExpr = rawFmRate;
                    model.Fm_Rate = null;
                }
                else
                {
                    model.Fm_SlabExpr = null;
                    if (decimal.TryParse(rawFmRate, out var fmVal)) model.Fm_Rate = fmVal;
                }

                list.Add(model);
            }
            return list;
        }
        // by rupesh and aryan


        [HttpPost("InsertVendor")]
        [Authorize]
        public async Task<IActionResult> InsertVendor([FromBody] VendorModel model)
        {
            ModelResponse modelResponse = new ModelResponse();
            try
            {
                var userId = HttpContext.Items["DecryptedUserId"]?.ToString() ?? "";
                var companyId = HttpContext.Items["DecryptedCompanyId"]?.ToString() ?? "";
                var locationId = HttpContext.Items["DecryptedLocationId"]?.ToString() ?? "";


                var response = await _vendorRepository.InsertVendorAsync(model, userId, companyId, locationId);
                if (response.IsSuccessfully && !string.IsNullOrEmpty(response.pk_recId))
                {
                    await GenerateAndSaveVerificationLinkAsync(response.pk_recId);
                }

                modelResponse.IsSuccess = response.IsSuccessfully;
                modelResponse.Message = response.IsMessage;
                modelResponse.Data = response.pk_recId;
                modelResponse.StatusCode = response.IsSuccessfully ? 200 : 400;
                return Ok(modelResponse);
            }
            catch (Exception ex)
            {
                modelResponse.IsSuccess = false;
                modelResponse.Message = ex.Message;
                modelResponse.StatusCode = 500;
                return StatusCode(500, modelResponse);
            }
        }


        [HttpPost("UpdateVendor")]
        [Authorize]

        public async Task<IActionResult> UpdateVendor([FromBody] VendorModel model)
        {
            ModelResponse modelResponse = new ModelResponse();
            try
            {
                var userId = HttpContext.Items["DecryptedUserId"]?.ToString() ?? "";
                var companyId = HttpContext.Items["DecryptedCompanyId"]?.ToString() ?? "";

                var response = await _vendorRepository.UpdateVendorAsync(model, userId, companyId);
                if (response.IsSuccessfully && !string.IsNullOrEmpty(model.pk_recId))
                {
                    await GenerateAndSaveVerificationLinkAsync(model.pk_recId);
                }
                modelResponse.IsSuccess = response.IsSuccessfully;
                modelResponse.Message = response.IsMessage;
                modelResponse.Data = response.pk_recId;
                modelResponse.StatusCode = response.IsSuccessfully ? 200 : 400;
                return Ok(modelResponse);
            }
            catch (Exception ex)
            {
                modelResponse.IsSuccess = false;
                modelResponse.Message = ex.Message;
                modelResponse.StatusCode = 500;
                return StatusCode(500, modelResponse);
            }
        }

        [HttpGet("GetVendorFHRIDMappingStats")]
        [Authorize]
        public async Task<IActionResult> GetVendorFHRIDMappingStats()
        {
            ModelResponse modelResponse = new ModelResponse();
            try
            {
                var companyId = HttpContext.Items["DecryptedCompanyId"]?.ToString() ?? "";
                var stats = await _vendorRepository.GetVendorFHRIDMappingStatsAsync(companyId);
                modelResponse.IsSuccess = true;
                modelResponse.Message = "Vendor FHRID mapping stats fetched successfully.";
                modelResponse.Data = stats;
                modelResponse.StatusCode = 200;
                return Ok(modelResponse);
            }
            catch (Exception ex)
            {
                modelResponse.IsSuccess = false;
                modelResponse.Message = ex.Message;
                modelResponse.StatusCode = 500;
                return StatusCode(500, modelResponse);
            }
        }

        [HttpGet("GetVendorMappedUnmappedList")]
        [Authorize]
        public async Task<IActionResult> GetVendorMappedUnmappedList([FromQuery] bool isMapped)
        {
            ModelResponse modelResponse = new ModelResponse();
            try
            {
                var companyId = HttpContext.Items["DecryptedCompanyId"]?.ToString() ?? "";
                var list = await _vendorRepository.GetVendorMappedUnmappedListAsync(companyId, isMapped);
                modelResponse.IsSuccess = true;
                modelResponse.Message = "Vendor list fetched successfully.";
                modelResponse.Data = list;
                modelResponse.StatusCode = 200;
                return Ok(modelResponse);
            }
            catch (Exception ex)
            {
                modelResponse.IsSuccess = false;
                modelResponse.Message = ex.Message;
                modelResponse.StatusCode = 500;
                return StatusCode(500, modelResponse);
            }
        }


        [HttpDelete("DeleteVendor/{pk_recId}")]
        [Authorize]
        public async Task<IActionResult> DeleteVendor(string pk_recId)
        {
            ModelResponse modelResponse = new ModelResponse();
            try
            {
                var response = await _vendorRepository.DeleteVendorAsync(pk_recId);
                modelResponse.IsSuccess = response.IsSuccessfully;
                modelResponse.Message = response.IsMessage;
                modelResponse.StatusCode = response.IsSuccessfully ? 200 : 400;
                return Ok(modelResponse);
            }
            catch (Exception ex)
            {
                modelResponse.IsSuccess = false;
                modelResponse.Message = ex.Message;
                modelResponse.StatusCode = 500;
                return StatusCode(500, modelResponse);
            }
        }

        [HttpGet("GetVendorById/{pk_recId}")]
        [Authorize]
        public async Task<IActionResult> GetVendorById(string pk_recId)
        {
            ModelResponse modelResponse = new ModelResponse();
            try
            {
                var vendor = await _vendorRepository.GetVendorByIdAsync(pk_recId);
                if (vendor != null)
                {
                    modelResponse.IsSuccess = true;
                    modelResponse.Message = "Vendor fetched successfully.";
                    modelResponse.Data = vendor;
                    modelResponse.StatusCode = 200;
                }
                else
                {
                    modelResponse.IsSuccess = false;
                    modelResponse.Message = "Vendor not found.";
                    modelResponse.StatusCode = 404;
                }
                return Ok(modelResponse);
            }
            catch (Exception ex)
            {
                modelResponse.IsSuccess = false;
                modelResponse.Message = ex.Message;
                modelResponse.StatusCode = 500;
                return StatusCode(500, modelResponse);
            }
        }

        [HttpGet("GetAllVendors")]
        [Authorize]
        public async Task<IActionResult> GetAllVendors([FromQuery] int pageIndex = 1, [FromQuery] int pageSize = 10, [FromQuery] string searchTerm = "", [FromQuery] string locationId = "", [FromQuery] string agentCode = "", [FromQuery] string status = "", [FromQuery] string fhridMappingStatus = "")
        {
            ModelResponse modelResponse = new ModelResponse();
            try
            {

                var userId = HttpContext.Items["DecryptedUserId"]?.ToString() ?? "";
                var companyId = HttpContext.Items["DecryptedCompanyId"]?.ToString() ?? "";

                var (totalCount, counts, vendors) = await _vendorRepository.GetAllVendorsAsync(pageIndex, pageSize, companyId, searchTerm, locationId, agentCode, status, fhridMappingStatus, userId);
                modelResponse.IsSuccess = true;
                modelResponse.Message = "Vendors fetched successfully.";
                modelResponse.Data = new
                {
                    TotalCount = totalCount,
                    Counts = counts,
                    Vendors = vendors
                };
                modelResponse.StatusCode = 200;
                return Ok(modelResponse);
            }
            catch (Exception ex)
            {
                modelResponse.IsSuccess = false;
                modelResponse.Message = ex.Message;
                modelResponse.StatusCode = 500;
                return StatusCode(500, modelResponse);
            }
        }

        [HttpPost("UploadVendorExcel")]
        [Authorize]
        public async Task<IActionResult> UploadVendorExcel([FromQuery] string? companyId, [FromForm] UploadVendorExcelRequest request)
        {
            ModelResponse modelResponse = new ModelResponse();
            try
            {
                var file = request.file;
                var fk_companyId = request.fk_companyId;
                var fk_insUserID = request.fk_insUserID;
                var userId = request.userId;

                if (file == null || file.Length == 0)
                {
                    modelResponse.IsSuccess = false;
                    modelResponse.Message = "Please select a valid Excel file.";
                    modelResponse.StatusCode = 400;
                    return Ok(modelResponse);
                }

                var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
                if (ext != ".xlsx" && ext != ".xls")
                {
                    modelResponse.IsSuccess = false;
                    modelResponse.Message = "Only Excel files (.xlsx, .xls) are allowed.";
                    modelResponse.StatusCode = 400;
                    return Ok(modelResponse);
                }

                userId = HttpContext.Items["DecryptedUserId"]?.ToString() ?? "";
                companyId = HttpContext.Items["DecryptedCompanyId"]?.ToString() ?? "";

                var uploadResults = await _vendorRepository.UploadVendorExcelAsync(file, companyId, userId);
                int successCount = uploadResults?.Count(r => r.IsSuccess || r.Status == "Uploaded" || r.Status == "Success" || r.Status == "Inserted" || r.Status == "Updated") ?? 0;

                modelResponse.IsSuccess = true;
                modelResponse.Message = successCount > 0
                    ? $"{successCount} vendor(s) processed successfully."
                    : "No valid vendors found to upload. Please correct invalid fields.";
                modelResponse.Data = uploadResults;
                modelResponse.StatusCode = 200;
                return Ok(modelResponse);
            }
            catch (Exception ex)
            {
                modelResponse.IsSuccess = false;
                modelResponse.Message = ex.Message;
                modelResponse.StatusCode = 500;
                return StatusCode(500, modelResponse);
            }
        }

        [HttpGet("GetVendorAuditLogs/{pk_recId}")]
        public async Task<IActionResult> GetVendorAuditLogs(string pk_recId)
        {
            ModelResponse modelResponse = new ModelResponse();
            try
            {
                var logs = await _vendorRepository.GetVendorAuditLogsAsync(pk_recId);
                modelResponse.IsSuccess = true;
                modelResponse.Message = "Audit logs fetched successfully.";
                modelResponse.Data = logs;
                modelResponse.StatusCode = 200;
                return Ok(modelResponse);
            }
            catch (Exception ex)
            {
                modelResponse.IsSuccess = false;
                modelResponse.Message = ex.Message;
                modelResponse.StatusCode = 500;
                return StatusCode(500, modelResponse);
            }
        }

        [HttpGet("GetVendorDashboardSummary")]
        [Authorize]
        public async Task<IActionResult> GetVendorDashboardSummary([FromQuery] string monthId = "", [FromQuery] string yearId = "")
        {
            ModelResponse modelResponse = new ModelResponse();
            try
            {
                var companyId = HttpContext.Items["DecryptedCompanyId"]?.ToString() ?? "";
                var summary = await _vendorRepository.GetVendorDashboardSummaryAsync(companyId, monthId, yearId);

                modelResponse.IsSuccess = true;
                modelResponse.Message = "Vendor dashboard summary fetched successfully.";
                modelResponse.Data = summary;
                modelResponse.StatusCode = 200;
                return Ok(modelResponse);
            }
            catch (Exception ex)
            {
                modelResponse.IsSuccess = false;
                modelResponse.Message = ex.Message;
                modelResponse.StatusCode = 500;
                return StatusCode(500, modelResponse);
            }
        }


        [HttpGet("GetVendorMasterUploadDocumentList")]
        [Authorize]
        public async Task<IActionResult> GetVendorMasterUploadDocumentList([FromQuery] string searchTerm = "", [FromQuery] int pageIndex = 1, [FromQuery] int pageSize = 10)
        {
            ModelResponse modelResponse = new ModelResponse();
            try
            {
                string companyId = HttpContext.Items["DecryptedCompanyId"]?.ToString() ?? "";
                var (totalCount, list) = await _vendorRepository.GetVendorExcelUploadListAsync(companyId, searchTerm, pageIndex, pageSize);

                modelResponse.IsSuccess = true;
                modelResponse.Message = "Uploaded excel documents list fetched successfully.";
                modelResponse.Data = new { totalCount, list };
                modelResponse.StatusCode = 200;
                return Ok(modelResponse);
            }
            catch (Exception ex)
            {
                modelResponse.IsSuccess = false;
                modelResponse.Message = ex.Message;
                modelResponse.StatusCode = 500;
                return StatusCode(500, modelResponse);
            }
        }

        [HttpGet("DownloadVendorMasterDocument/{id}")]
        [Authorize]
        public async Task<IActionResult> DownloadVendorMasterDocument(long id)
        {
            try
            {
                var doc = await _vendorRepository.GetVendorExcelUploadByIdAsync(id);
                if (doc == null || string.IsNullOrEmpty(doc.savedFilePath))
                {
                    return NotFound(new ModelResponse { IsSuccess = false, Message = "File metadata not found." });
                }

                string fileName = Path.GetFileName(doc.savedFilePath);
                string configuredFolder = _configuration["AppSettings:VendorMasterUploads"] ?? Path.Combine(Directory.GetCurrentDirectory(), "VendorMasterUploads");
                string fullPath = Path.Combine(configuredFolder, fileName);

                // 1. Check configured folder path
                if (!System.IO.File.Exists(fullPath) && Directory.Exists(configuredFolder))
                {
                    string nameNoExt = Path.GetFileNameWithoutExtension(fileName);
                    int lastUnder = nameNoExt.LastIndexOf('_');
                    string prefix = lastUnder > 0 ? nameNoExt.Substring(0, lastUnder) : nameNoExt;

                    var matching = Directory.GetFiles(configuredFolder, $"{prefix}*")
                        .OrderByDescending(f => System.IO.File.GetLastWriteTime(f))
                        .FirstOrDefault();
                    if (!string.IsNullOrEmpty(matching) && System.IO.File.Exists(matching))
                    {
                        fullPath = matching;
                    }
                }

                // 2. Check if savedFilePath itself was an absolute path that exists
                if (!System.IO.File.Exists(fullPath))
                {
                    if (System.IO.File.Exists(doc.savedFilePath))
                    {
                        fullPath = doc.savedFilePath;
                    }
                }

                // 3. Fallback for legacy files in wwwroot
                if (!System.IO.File.Exists(fullPath))
                {
                    string wwwrootPath = Path.Combine(Directory.GetCurrentDirectory(), "wwwroot", doc.savedFilePath.TrimStart('/'));
                    if (System.IO.File.Exists(wwwrootPath))
                    {
                        fullPath = wwwrootPath;
                    }
                    else
                    {
                        return NotFound(new ModelResponse { IsSuccess = false, Message = "Physical file not found on server." });
                    }
                }

                byte[] fileBytes = await System.IO.File.ReadAllBytesAsync(fullPath);
                string contentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
                string downloadName = doc.originalFileName ?? "VendorUpload.xlsx";

                return File(fileBytes, contentType, downloadName);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new ModelResponse { IsSuccess = false, Message = ex.Message });
            }
        }


        [HttpGet("ratecard-history/{vendorId}")]
        [Authorize]
        public async Task<IActionResult> GetVendorRateCardHistory(string vendorId)
        {
            ModelResponse modelResponse = new ModelResponse();
            try
            {
                var history = await _vendorRepository.GetVendorRateCardAuditHistoryAsync(vendorId);
                modelResponse.IsSuccess = true;
                modelResponse.Message = "Rate card history fetched successfully.";
                modelResponse.Data = history;
                modelResponse.StatusCode = 200;
                return Ok(modelResponse);
            }
            catch (Exception ex)
            {
                modelResponse.IsSuccess = false;
                modelResponse.Message = ex.Message;
                modelResponse.StatusCode = 500;
                return StatusCode(500, modelResponse);
            }
        }

        [HttpGet("GetVendorRateCards/{vendorId}")]
        [Authorize]
        public async Task<IActionResult> GetVendorRateCards(string vendorId)
        {
            ModelResponse modelResponse = new ModelResponse();
            try
            {
                var rateCards = await _vendorRepository.GetVendorRateCardsAsync(vendorId);
                modelResponse.IsSuccess = true;
                modelResponse.Message = "Vendor rate cards fetched successfully.";
                modelResponse.Data = rateCards;
                modelResponse.StatusCode = 200;
                return Ok(modelResponse);
            }
            catch (Exception ex)
            {
                modelResponse.IsSuccess = false;
                modelResponse.Message = ex.Message;
                modelResponse.StatusCode = 500;
                return StatusCode(500, modelResponse);
            }
        }




        private static string? FormatEffectiveDate(string? val)
        {
            if (string.IsNullOrWhiteSpace(val)) return null;
            val = val.Trim();

            // Check if it's an OLE Automation date (numeric Excel serial)
            if (double.TryParse(val, System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out double oaDate) && oaDate > 30000 && oaDate < 80000)
            {
                try
                {
                    return DateTime.FromOADate(oaDate).ToString("yyyy-MM-dd");
                }
                catch { }
            }

            string[] formats = {
        "dd/MM/yyyy", "d/M/yyyy", "dd-MM-yyyy", "d-M-yyyy", "dd.MM.yyyy", "d.M.yyyy",
        "dd/MM/yyyy HH:mm:ss", "dd/MM/yyyy hh:mm:ss tt", "dd/MM/yyyy H:mm:ss",
        "dd-MM-yyyy HH:mm:ss", "dd-MM-yyyy hh:mm:ss tt",
        "yyyy-MM-dd", "yyyy/MM/dd", "yyyy-MM-ddTHH:mm:ss", "yyyy-MM-dd HH:mm:ss",
        "dd/MM/yy", "d/M/yy", "dd-MM-yy", "d-M-yy",
        "MM/dd/yyyy", "M/d/yyyy", "MM/dd/yyyy HH:mm:ss", "MM/dd/yyyy hh:mm:ss tt"
    };

            if (DateTime.TryParseExact(val, formats, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.None, out var dt) ||
                DateTime.TryParse(val, new System.Globalization.CultureInfo("en-GB"), System.Globalization.DateTimeStyles.None, out dt) ||
                DateTime.TryParse(val, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.None, out dt) ||
                DateTime.TryParse(val, out dt))
            {
                return dt.ToString("yyyy-MM-dd");
            }
            return val;
        }


        [HttpGet("audit-log/document-names")]
        [Authorize]
        public async Task<IActionResult> GetAuditLogDocumentNames()
        {
            ModelResponse modelResponse = new ModelResponse();
            try
            {
                var result = await _vendorRepository.GetAuditLogDocumentNamesAsync();
                modelResponse.IsSuccess = true;
                modelResponse.Data = result;
                modelResponse.StatusCode = 200;
                return Ok(modelResponse);
            }
            catch (Exception ex)
            {
                modelResponse.IsSuccess = false;
                modelResponse.Message = ex.Message;
                modelResponse.StatusCode = 500;
                return StatusCode(500, modelResponse);
            }
        }

        [HttpPost("audit-log/list")]
        [Authorize]
        public async Task<IActionResult> GetAuditLogs([FromBody] AuditLogFilterRequest filter)
        {
            ModelResponse modelResponse = new ModelResponse();
            try
            {
                var result = await _vendorRepository.GetAuditLogsAsync(filter);
                modelResponse.IsSuccess = true;
                modelResponse.Data = result;
                modelResponse.StatusCode = 200;
                return Ok(modelResponse);
            }
            catch (Exception ex)
            {
                modelResponse.IsSuccess = false;
                modelResponse.Message = ex.Message;
                modelResponse.StatusCode = 500;
                return StatusCode(500, modelResponse);
            }
        }

        private static string FormatRateType(string? val)
        {
            if (string.IsNullOrWhiteSpace(val)) return "Fixed";
            var trimmed = val.Trim();
            if (trimmed.Equals("slab", StringComparison.OrdinalIgnoreCase)) return "Slab";
            if (trimmed.Equals("fixed", StringComparison.OrdinalIgnoreCase)) return "Fixed";
            if (trimmed.Equals("percentage", StringComparison.OrdinalIgnoreCase)) return "Percentage";
            return trimmed;
        }


        [HttpGet("GetLinkedFHRIDs")]
        [Authorize]
        public async Task<IActionResult> GetLinkedFHRIDs([FromQuery] string clientId, [FromQuery] string modelId)
        {
            ModelResponse modelResponse = new ModelResponse();
            try
            {
                string companyId = HttpContext.Items["DecryptedCompanyId"]?.ToString() ?? "";
                var list = await _vendorRepository.GetFHRIDsAsync(clientId, modelId, companyId);

                modelResponse.IsSuccess = true;
                modelResponse.Message = "FHR IDs fetched successfully.";
                modelResponse.Data = list;
                modelResponse.StatusCode = 200;
                return Ok(modelResponse);
            }
            catch (Exception ex)
            {
                modelResponse.IsSuccess = false;
                modelResponse.Message = ex.Message;
                modelResponse.StatusCode = 500;
                return StatusCode(500, modelResponse);
            }
        }

        [HttpGet("fhrid-history/{pk_recId}")]
        public async Task<IActionResult> GetVendorFHRIDHistory(string pk_recId, [FromQuery] int pageIndex = 1, [FromQuery] int pageSize = 10)
        {
            var modelResponse = new ModelResponse();
            try
            {
                if (string.IsNullOrEmpty(pk_recId))
                {
                    modelResponse.IsSuccess = false;
                    modelResponse.Message = "Vendor ID is required.";
                    return Ok(modelResponse);
                }

                var (totalCount, list) = await _vendorRepository.GetVendorFHRIDHistoryAsync(pk_recId, pageIndex, pageSize);

                modelResponse.IsSuccess = true;
                modelResponse.Message = "FHRID History fetched successfully.";
                modelResponse.Data = new { totalCount, list };
                modelResponse.StatusCode = 200;

                return Ok(modelResponse);
            }
            catch (Exception ex)
            {
                modelResponse.IsSuccess = false;
                modelResponse.Message = ex.Message;
                return Ok(modelResponse);
            }
        }


        [HttpPost("TransactionExcelUpload")]
        [Authorize]
        public async Task<IActionResult> UploadTransaction(IFormFile file, [FromForm] string? clientId, [FromForm] string? modelId, [FromForm] string? clientName, [FromForm] string? modelName, [FromForm] DateTime fromDate, [FromForm] DateTime toDate)
        {
            ModelResponse modelResponse = new ModelResponse();
            try
            {
                string companyId = HttpContext.Items["DecryptedCompanyId"]?.ToString() ?? "";
                if (file == null || file.Length == 0)
                    return Ok(new ModelResponse { IsSuccess = false, Message = "Excel file is required.", StatusCode = 400 });

                var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
                if (ext != ".xlsx" && ext != ".xls")
                    return Ok(new ModelResponse { IsSuccess = false, Message = "Only .xlsx or .xls files are allowed.", StatusCode = 400 });

                var uploadsFolder = _configuration["AppSettings:VendorTransactions"];
                if (string.IsNullOrEmpty(uploadsFolder)) uploadsFolder = Path.Combine(Directory.GetCurrentDirectory(), "VendorTransactions");
                if (!Directory.Exists(uploadsFolder)) Directory.CreateDirectory(uploadsFolder);

                var fileNameWithoutExt = Path.GetFileNameWithoutExtension(file.FileName);
                var savedFileName = $"{fileNameWithoutExt}_{DateTime.Now:ddMMyyyy_HHmmss}{ext}";
                var physicalPath = Path.Combine(uploadsFolder, savedFileName);

                using (var stream = new FileStream(physicalPath, FileMode.Create))
                {
                    await file.CopyToAsync(stream);
                }

                var data = ExcelHelper.ReadExcelDynamic(file);
                if (data == null || !data.Any())
                    return Ok(new ModelResponse { IsSuccess = false, Message = "Excel file has no data.", StatusCode = 400 });

                var inputMap = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                var outputRenameMap = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

                int cId = 0, mId = 0;
                int.TryParse(clientId, out cId);
                int.TryParse(modelId, out mId);

                try
                {
                    var configData = await _vendorRepository.GetVendorTemplateConfigAsync(cId, mId);
                    foreach (var row in configData)
                    {
                        var dict = (IDictionary<string, object>)row;
                        var stdCol = dict.ContainsKey("StandardDbColumn") ? Convert.ToString(dict["StandardDbColumn"]) ?? "" : "";
                        var excelHeader = dict.ContainsKey("ExcelHeaderName") ? Convert.ToString(dict["ExcelHeaderName"]) ?? "" : "";
                        inputMap[excelHeader.Replace(" ", "").ToLower()] = stdCol;
                        outputRenameMap[stdCol] = excelHeader;
                    }
                }
                catch { }

                string GetDynamicVal(System.Collections.Generic.Dictionary<string, string> row, string stdColName, string fallbackKey)
                {
                    // 1. Try to find dynamic header in file based on DB config mapping
                    var matchingDynamicKey = inputMap.FirstOrDefault(x => x.Value.Equals(stdColName, StringComparison.OrdinalIgnoreCase)).Key;
                    if (!string.IsNullOrEmpty(matchingDynamicKey))
                    {
                        var val = row.Keys.FirstOrDefault(k => k.Replace(" ", "").ToLower() == matchingDynamicKey);
                        if (val != null && !string.IsNullOrWhiteSpace(row[val])) return row[val];
                    }

                    // 2. Try the fallback standard key directly
                    var valFallback = row.Keys.FirstOrDefault(k => k.Replace(" ", "").ToLower() == fallbackKey.ToLower());
                    if (valFallback != null && !string.IsNullOrWhiteSpace(row[valFallback])) return row[valFallback];

                    // 3. Just in case they uploaded with exact DB column name
                    var valExact = row.Keys.FirstOrDefault(k => k.Replace(" ", "").ToLower() == stdColName.ToLower());
                    if (valExact != null && !string.IsNullOrWhiteSpace(row[valExact])) return row[valExact];

                    return "0";
                }

                string GetCoreVal(System.Collections.Generic.Dictionary<string, string> row, string coreKey)
                {
                    var val = row.Keys.FirstOrDefault(k => k.Replace(" ", "").ToLower() == coreKey.ToLower());
                    if (val != null && !string.IsNullOrWhiteSpace(row[val])) return row[val];
                    return "";
                }

                System.Xml.Linq.XElement xmlUploads = new System.Xml.Linq.XElement("Uploads");
                foreach (var row in data)
                {
                    var xRow = new System.Xml.Linq.XElement("Row",
                        new System.Xml.Linq.XAttribute("VendorCode", GetCoreVal(row, "code")),
                        new System.Xml.Linq.XAttribute("VendorName", GetCoreVal(row, "name")),
                        new System.Xml.Linq.XAttribute("LocationName", GetCoreVal(row, "location")),
                        new System.Xml.Linq.XAttribute("AreaManager", GetCoreVal(row, "areamanager")),
                        new System.Xml.Linq.XAttribute("HubCode", GetCoreVal(row, "hubcode")),
                        new System.Xml.Linq.XAttribute("Assigned_Volume", GetDynamicVal(row, "Assigned_Volume", "sumoftotalofd")),
                        new System.Xml.Linq.XAttribute("Delivered_Volume", GetDynamicVal(row, "Delivered_Volume", "sumoftotaldelivered")),
                        new System.Xml.Linq.XAttribute("Ded_Shipment", GetDynamicVal(row, "Ded_Shipment", "shipmentdeduction")),
                        new System.Xml.Linq.XAttribute("Ded_COD", GetDynamicVal(row, "Ded_COD", "coddeduction")),
                        new System.Xml.Linq.XAttribute("Ded_Other", GetDynamicVal(row, "Ded_Other", "otherdeduction")),
                        new System.Xml.Linq.XAttribute("Ded_Arrear", GetDynamicVal(row, "Ded_Arrear", "arrearamt")),
                        new System.Xml.Linq.XAttribute("Ded_Insurance", GetDynamicVal(row, "Ded_Insurance", "insurance")),
                        new System.Xml.Linq.XAttribute("Ded_SD", GetDynamicVal(row, "Ded_SD", "sd")),
                        new System.Xml.Linq.XAttribute("Ded_Welfare", GetDynamicVal(row, "Ded_Welfare", "welfare")),
                        new System.Xml.Linq.XAttribute("Ded_Hold", GetDynamicVal(row, "Ded_Hold", "hold")),
                        new System.Xml.Linq.XAttribute("Ded_KarmaLife", GetDynamicVal(row, "Ded_KarmaLife", "karmalife")),
                        new System.Xml.Linq.XAttribute("Vehicle_Type", GetDynamicVal(row, "Vehicle_Type", "type")),
                        new System.Xml.Linq.XAttribute("Working_Days", GetDynamicVal(row, "Working_Days", "workingdays")),
                        new System.Xml.Linq.XAttribute("Pickup_Assigned", GetDynamicVal(row, "Pickup_Assigned", "pickupassign")),
                        new System.Xml.Linq.XAttribute("Pickup_Done", GetDynamicVal(row, "Pickup_Done", "pickupdone")),
                        new System.Xml.Linq.XAttribute("RTO_Assigned", GetDynamicVal(row, "RTO_Assigned", "rtoassign")),
                        new System.Xml.Linq.XAttribute("RTO_Done",     GetDynamicVal(row, "RTO_Done",     "rtodone")),
                        new System.Xml.Linq.XAttribute("DTO_Assigned", GetDynamicVal(row, "DTO_Assigned", "dtoassign")),
                        new System.Xml.Linq.XAttribute("DTO_Done",     GetDynamicVal(row, "DTO_Done",     "dtodone")),
                        new System.Xml.Linq.XAttribute("FM_Assigned",  GetDynamicVal(row, "FM_Assigned",  "fmassign")),
                        new System.Xml.Linq.XAttribute("FM_Done",      GetDynamicVal(row, "FM_Done",      "fmdone")),
                        new System.Xml.Linq.XAttribute("Assigned_RVP", GetDynamicVal(row, "Assigned_RVP", "assignedrvp")),
                        new System.Xml.Linq.XAttribute("Delivered_RVP", GetDynamicVal(row, "Delivered_RVP", "deliveredrvp")),
                        new System.Xml.Linq.XAttribute("SR_LM_Return", GetDynamicVal(row, "SR_LM_Return", "srlmreturn")),
                        new System.Xml.Linq.XAttribute("SR_FM_Return", GetDynamicVal(row, "SR_FM_Return", "srfmreturn")),
                        new System.Xml.Linq.XAttribute("Assign_RVP_Normal", GetDynamicVal(row, "Assign_RVP_Normal", "assignrvpnormal")),
                        new System.Xml.Linq.XAttribute("Total_Delivered_RVP_Shopsy", GetDynamicVal(row, "Total_Delivered_RVP_Shopsy", "totaldeliveredrvpshopsy")),
                        new System.Xml.Linq.XAttribute("U2S", GetDynamicVal(row, "U2S", "u2s")),
                        new System.Xml.Linq.XAttribute("Shopsy", GetDynamicVal(row, "Shopsy", "shopsy")),
                        new System.Xml.Linq.XAttribute("Prexo", GetDynamicVal(row, "Prexo", "prexo")),
                        new System.Xml.Linq.XAttribute("Grocery_Assigned", GetDynamicVal(row, "Grocery_Assigned", "groceryassigned")),
                        new System.Xml.Linq.XAttribute("Grocery_Delivered", GetDynamicVal(row, "Grocery_Delivered", "grocerydelivered")),
                        new System.Xml.Linq.XAttribute("Route", GetCoreVal(row, "route")),
                        new System.Xml.Linq.XAttribute("MFN_Assigned", GetDynamicVal(row, "MFN_Assigned", "mfnassign")),
                        new System.Xml.Linq.XAttribute("MFN_Done", GetDynamicVal(row, "MFN_Done", "mfndone")),
                        new System.Xml.Linq.XAttribute("PresentDays", GetDynamicVal(row, "PresentDays", "presentdays")),
                        new System.Xml.Linq.XAttribute("Special_Charge", GetDynamicVal(row, "Special_Charge", "sc")),
                        new System.Xml.Linq.XAttribute("Ded_Rent", GetDynamicVal(row, "Ded_Rent", "rentdeduction")),
                        new System.Xml.Linq.XAttribute("Ded_Advance", GetDynamicVal(row, "Ded_Advance", "advancededuction")),
                        new System.Xml.Linq.XAttribute("Ded_TNT", GetDynamicVal(row, "Ded_TNT", "tntdeduction"))
                    );
                    xmlUploads.Add(xRow);
                }
                string xmlString = xmlUploads.ToString();
                var userId = HttpContext.Items["DecryptedUserId"]?.ToString() ?? "";
                var processedData = await _vendorRepository.UploadTransactionsAsync(clientId, modelId, fromDate, toDate, xmlString, savedFileName, userId, companyId);

                // --- 1. RENAME JSON KEYS FOR UI ---
                var renamedList = new List<Dictionary<string, object>>();
                if (processedData != null)
                {
                    foreach (var rawRow in processedData)
                    {
                        var rawDict = (IDictionary<string, object>)rawRow;
                        var renamedRow = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);

                        foreach (var kvp in rawDict)
                        {
                            var internalExclude = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase) {
                                "TotalRows", "TotalRecords", "TransactionID", "UploadBatchID", "fk_cost_centre_id", "fk_model_id", "fk_rec_id",
                                "ClientID", "ModelID", "LocationID", "CreatedBy", "CreatedDate", "IsProcessed", "fk_File_Id", "FHRID",
                                "FromDate", "ToDate", "CycleName", "BudgetaryCode", "StateName", "Payment_Status", "Payment Status",
                                "HR_Remark", "HR Remark", "Central_Remark", "Central Remark", "TransactionRange", "UploadedByName"
                            };
                            if (internalExclude.Contains(kvp.Key)) continue;

                            bool isPickupEnabled = outputRenameMap.ContainsKey("Pickup_Assigned") || outputRenameMap.ContainsKey("pickup_assigned") || outputRenameMap.Values.Contains("Pickup Assign");
                            var ebeesCols = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase) { "Pickup_Assigned", "Pickup_Done", "Pickup_Conversion_Percentage", "Pickup_Applied_Rate", "Pickup_Rate_Type", "Delivery_Payable", "Pickup_Payable" };
                            if (ebeesCols.Contains(kvp.Key) && !isPickupEnabled) continue;
                            var dedCols = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase) { "Ded_Shipment", "Ded_COD", "Ded_Other", "Ded_Arrear", "Ded_Insurance", "Ded_SD", "Ded_Welfare", "Ded_Hold", "Ded_KarmaLife" };
                            if (dedCols.Contains(kvp.Key) && !outputRenameMap.ContainsKey(kvp.Key)) continue;
                            if (modelId != null && modelId.ToString() == "3" && kvp.Key.Equals("Assigned_Volume", StringComparison.OrdinalIgnoreCase)) continue;
                            var fmCols = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase) { "Total_Assigned_FM_RVP", "Total_Delivered_FM_RVP", "Assigned_RVP", "Delivered_RVP", "Vehicle_Type", "Working_Days" };
                            if (fmCols.Contains(kvp.Key) && !outputRenameMap.ContainsKey(kvp.Key)) continue;

                            string displayKey = kvp.Key;

                            if (outputRenameMap.ContainsKey(kvp.Key))
                            {
                                displayKey = outputRenameMap[kvp.Key];
                            }
                            else if (kvp.Key.Equals("VendorCode", StringComparison.OrdinalIgnoreCase)) displayKey = "Code";
                            else if (kvp.Key.Equals("VendorName", StringComparison.OrdinalIgnoreCase)) displayKey = "Name";
                            else if (kvp.Key.Equals("LocationName", StringComparison.OrdinalIgnoreCase)) displayKey = "Location";
                    else if (kvp.Key.Equals("FHRID", StringComparison.OrdinalIgnoreCase)) displayKey = "FHRID";
                            else if (kvp.Key.Equals("HubCode", StringComparison.OrdinalIgnoreCase)) displayKey = "Hub code";
                            else if (kvp.Key.Equals("Working_Days", StringComparison.OrdinalIgnoreCase)) displayKey = "No. of Days";
                            else if (kvp.Key.Equals("Processing_Status", StringComparison.OrdinalIgnoreCase)) displayKey = "Processing Status";
                            else if (kvp.Key.Equals("System_Remarks", StringComparison.OrdinalIgnoreCase)) displayKey = "System Remarks";
                            else if (kvp.Key.Equals("Assigned_Volume", StringComparison.OrdinalIgnoreCase)) displayKey = "Sum of Total OFD";
                            else if (kvp.Key.Equals("Delivered_Volume", StringComparison.OrdinalIgnoreCase)) displayKey = "Sum of Total Delivered";
                            else if (kvp.Key.Equals("Conversion_Percentage", StringComparison.OrdinalIgnoreCase)) displayKey = "Conversion %";
                            else if (kvp.Key.Equals("Applied_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "Applied BaseRate";
                            else if (kvp.Key.Equals("Rate_Type", StringComparison.OrdinalIgnoreCase)) displayKey = "Rate Type";
                            else if (kvp.Key.Equals("Base_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "Base payable";
                            else if (kvp.Key.Equals("GST_Percentage", StringComparison.OrdinalIgnoreCase)) displayKey = "GST Percentage";
                            else if (kvp.Key.Equals("GST_Amount", StringComparison.OrdinalIgnoreCase)) displayKey = "GST Amount";
                            else if (kvp.Key.Equals("Total_Payable_After_GST", StringComparison.OrdinalIgnoreCase)) displayKey = "Total Payable After GST";
                            else if (kvp.Key.Equals("TDS_Percentage", StringComparison.OrdinalIgnoreCase)) displayKey = "TDS Percentage";
                            else if (kvp.Key.Equals("TDS_Amount", StringComparison.OrdinalIgnoreCase)) displayKey = "TDS Amount";
                            else if (kvp.Key.Equals("Net_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "Net Payable";
                            else if (kvp.Key.Equals("Vendor_BankName", StringComparison.OrdinalIgnoreCase)) displayKey = "Bank Name";
                            else if (kvp.Key.Equals("Vendor_AccountNo", StringComparison.OrdinalIgnoreCase)) displayKey = "Account No";
                            else if (kvp.Key.Equals("Vendor_IFSCCode", StringComparison.OrdinalIgnoreCase)) displayKey = "IFSC Code";
                            else if (kvp.Key.Equals("Vendor_PanNo", StringComparison.OrdinalIgnoreCase)) displayKey = "PAN No";
                            else if (kvp.Key.Equals("Vendor_AaddharNo", StringComparison.OrdinalIgnoreCase)) displayKey = "Aadhar No";
                            else if (kvp.Key.Equals("TransactionRange", StringComparison.OrdinalIgnoreCase)) displayKey = "Date Range";
                            else if (kvp.Key.Equals("UploadedByName", StringComparison.OrdinalIgnoreCase)) displayKey = "Uploaded By";
                            else if (kvp.Key.Equals("Ded_Shipment", StringComparison.OrdinalIgnoreCase)) displayKey = "Deduction";
                            else if (kvp.Key.Equals("Ded_COD", StringComparison.OrdinalIgnoreCase)) displayKey = "COD Deduction";
                            else if (kvp.Key.Equals("Ded_Other", StringComparison.OrdinalIgnoreCase)) displayKey = "Other Deduction";
                            else if (kvp.Key.Equals("Ded_Arrear", StringComparison.OrdinalIgnoreCase)) displayKey = "Arrear";
                            else if (kvp.Key.Equals("Ded_Insurance", StringComparison.OrdinalIgnoreCase)) displayKey = "Insurance";
                            else if (kvp.Key.Equals("Ded_SD", StringComparison.OrdinalIgnoreCase)) displayKey = "SD";
                            else if (kvp.Key.Equals("Ded_Welfare", StringComparison.OrdinalIgnoreCase)) displayKey = "Welfare Deduction";
                            else if (kvp.Key.Equals("Ded_Hold", StringComparison.OrdinalIgnoreCase)) displayKey = "Hold";
                            else if (kvp.Key.Equals("Ded_KarmaLife", StringComparison.OrdinalIgnoreCase)) displayKey = "Karma Life Deduction";
                            else if (kvp.Key.Equals("Ded_Rent", StringComparison.OrdinalIgnoreCase)) displayKey = "Rent Deduction";
                            else if (kvp.Key.Equals("Ded_Advance", StringComparison.OrdinalIgnoreCase)) displayKey = "Advance Deduction";
                            else if (kvp.Key.Equals("Ded_TNT", StringComparison.OrdinalIgnoreCase)) displayKey = "TNT Deduction";
                            else if (kvp.Key.Equals("SR_LM_Return", StringComparison.OrdinalIgnoreCase)) displayKey = "SR LM Return";
                            else if (kvp.Key.Equals("SR_FM_Return", StringComparison.OrdinalIgnoreCase)) displayKey = "SR FM Return";
                            else if (kvp.Key.Equals("Assign_RVP_Normal", StringComparison.OrdinalIgnoreCase)) displayKey = "Assign RVP+Normal";
                            else if (kvp.Key.Equals("Total_Delivered_RVP_Shopsy", StringComparison.OrdinalIgnoreCase)) displayKey = "Total Delivered+RVP+Shopsy";
                            else if (kvp.Key.Equals("FWD_RVP_Del_Wo_SR", StringComparison.OrdinalIgnoreCase)) displayKey = "FWD+RVP Del-W/o SR";
                            else if (kvp.Key.Equals("Delivery_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "Payable";
                            else if (kvp.Key.Equals("U2S_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "U2S Rate";
                            else if (kvp.Key.Equals("U2S_Rate_Type", StringComparison.OrdinalIgnoreCase)) displayKey = "U2S Rate Type";
                            else if (kvp.Key.Equals("U2S_Applied_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "U2S Applied Rate";
                            else if (kvp.Key.Equals("U2S_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "U2S Payable";
                            else if (kvp.Key.Equals("Shopsy_RateDeduction", StringComparison.OrdinalIgnoreCase)) displayKey = "Shopsy RateDeduction";
                            else if (kvp.Key.Equals("Shopsy_RateType", StringComparison.OrdinalIgnoreCase)) displayKey = "Shopsy Rate Type";
                            else if (kvp.Key.Equals("Shopsy_Applied_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "Shopsy RateApplied";
                            else if (kvp.Key.Equals("Shopsy_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "Shopsy Payable";
                            else if (kvp.Key.Equals("Prexo_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "Prexo Rate";
                            else if (kvp.Key.Equals("Prexo_Rate_Type", StringComparison.OrdinalIgnoreCase)) displayKey = "Prexo Rate Type";
                            else if (kvp.Key.Equals("Prexo_Applied_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "Prexo Applied Rate";
                            else if (kvp.Key.Equals("Prexo_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "Prexo Payable";
                            else if (kvp.Key.Equals("Grocery_Assigned", StringComparison.OrdinalIgnoreCase)) displayKey = "Grocery Assigned";
                            else if (kvp.Key.Equals("Grocery_Delivered", StringComparison.OrdinalIgnoreCase)) displayKey = "Grocery Delivered";
                            else if (kvp.Key.Equals("Grocery_Conversion_Percentage", StringComparison.OrdinalIgnoreCase)) displayKey = "Grocery Conversion %";
                            else if (kvp.Key.Equals("Grocery_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "Grocery Rate";
                            else if (kvp.Key.Equals("Grocery_Rate_Type", StringComparison.OrdinalIgnoreCase)) displayKey = "Grocery Rate Type";
                            else if (kvp.Key.Equals("Grocery_Applied_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "Grocery Applied Rate";
                            else if (kvp.Key.Equals("Grocery_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "Grocery Payable";
                            else if (kvp.Key.Equals("Pickup_Conversion_Percentage", StringComparison.OrdinalIgnoreCase)) displayKey = "Pickup %";
                            else if (kvp.Key.Equals("Pickup_Applied_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "Pickup Rate";
                            else if (kvp.Key.Equals("Pickup_Rate_Type", StringComparison.OrdinalIgnoreCase)) displayKey = "Pickup Rate Type";
                            else if (kvp.Key.Equals("Pickup_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "Pickup Payable";
                            // *** NEW: RTO display mappings ***
                            else if (kvp.Key.Equals("RTO_Assigned",              StringComparison.OrdinalIgnoreCase)) displayKey = "RTO Assign";
                            else if (kvp.Key.Equals("RTO_Done",                  StringComparison.OrdinalIgnoreCase)) displayKey = "RTO Done";
                            else if (kvp.Key.Equals("RTO_Conversion_Percentage", StringComparison.OrdinalIgnoreCase)) displayKey = "RTO %";
                            else if (kvp.Key.Equals("RTO_Applied_Rate",          StringComparison.OrdinalIgnoreCase)) displayKey = "RTO Rate";
                            else if (kvp.Key.Equals("RTO_Rate_Type",             StringComparison.OrdinalIgnoreCase)) displayKey = "RTO Rate Type";
                            else if (kvp.Key.Equals("RTO_Payable",               StringComparison.OrdinalIgnoreCase)) displayKey = "RTO Payable";
                            // *** NEW: DTO display mappings ***
                            else if (kvp.Key.Equals("DTO_Assigned",              StringComparison.OrdinalIgnoreCase)) displayKey = "DTO Assign";
                            else if (kvp.Key.Equals("DTO_Done",                  StringComparison.OrdinalIgnoreCase)) displayKey = "DTO Done";
                            else if (kvp.Key.Equals("DTO_Conversion_Percentage", StringComparison.OrdinalIgnoreCase)) displayKey = "DTO %";
                            else if (kvp.Key.Equals("DTO_Applied_Rate",          StringComparison.OrdinalIgnoreCase)) displayKey = "DTO Rate";
                            else if (kvp.Key.Equals("DTO_Rate_Type",             StringComparison.OrdinalIgnoreCase)) displayKey = "DTO Rate Type";
                            else if (kvp.Key.Equals("DTO_Payable",               StringComparison.OrdinalIgnoreCase)) displayKey = "DTO Payable";
                            // *** NEW: FM display mappings ***
                            else if (kvp.Key.Equals("FM_Assigned",               StringComparison.OrdinalIgnoreCase)) displayKey = "FM Assign";
                            else if (kvp.Key.Equals("FM_Done",                   StringComparison.OrdinalIgnoreCase)) displayKey = "FM Done";
                            else if (kvp.Key.Equals("FM_Conversion_Percentage",  StringComparison.OrdinalIgnoreCase)) displayKey = "FM %";
                            else if (kvp.Key.Equals("FM_Applied_Rate",           StringComparison.OrdinalIgnoreCase)) displayKey = "FM Rate";
                            else if (kvp.Key.Equals("FM_Rate_Type",              StringComparison.OrdinalIgnoreCase)) displayKey = "FM Rate Type";
                            else if (kvp.Key.Equals("FM_Payable",                StringComparison.OrdinalIgnoreCase)) displayKey = "FM Payable";
                            else if (kvp.Key.Equals("Total_Assigned_FM_RVP", StringComparison.OrdinalIgnoreCase)) displayKey = "Total Assigne FM+RVP";
                            else if (kvp.Key.Equals("Total_Delivered_FM_RVP", StringComparison.OrdinalIgnoreCase)) displayKey = "Total Delivered FM+RVP";
                            else if (kvp.Key.Equals("Route", StringComparison.OrdinalIgnoreCase)) displayKey = "Route";
                            else if (kvp.Key.Equals("MFN_Assigned", StringComparison.OrdinalIgnoreCase)) displayKey = "MFN Assign";
                            else if (kvp.Key.Equals("MFN_Done", StringComparison.OrdinalIgnoreCase)) displayKey = "MFN Done";
                            else if (kvp.Key.Equals("MFN_Conversion_Percentage", StringComparison.OrdinalIgnoreCase)) displayKey = "MFN Conversion %";
                            else if (kvp.Key.Equals("MFN_Rate_Type", StringComparison.OrdinalIgnoreCase)) displayKey = "MFN RateType";
                            else if (kvp.Key.Equals("MFN_Applied_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "MFN AppliedRate";
                            else if (kvp.Key.Equals("MFN_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "MFN Payable";
                            else if (kvp.Key.Equals("Van_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "Van Rate";
                            else if (kvp.Key.Equals("Van_Rate_Type", StringComparison.OrdinalIgnoreCase)) displayKey = "Van RateType";
                            else if (kvp.Key.Equals("Van_Applied_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "VAN AppliedRate";
                            else if (kvp.Key.Equals("PresentDays", StringComparison.OrdinalIgnoreCase)) displayKey = "PresentDays";
                            else if (kvp.Key.Equals("Van_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "VAN Payable";
                            else if (kvp.Key.Equals("PresentDaysPayableRate", StringComparison.OrdinalIgnoreCase)) displayKey = "PresentDaysPayableRate";
                            else if (kvp.Key.Equals("PresentDaysPayable", StringComparison.OrdinalIgnoreCase)) displayKey = "PresentDaysPayable";
                            else if (kvp.Key.Equals("Special_Charge", StringComparison.OrdinalIgnoreCase)) displayKey = "SC";
                            else if (kvp.Key.Equals("Total_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "totalPayable";

                            // HIDE irrelevant columns for ODH-MDH (ModelId = 1)
                            if (modelId != null && modelId.ToString() == "1")
                            {
                                var odhHideCols = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase) {
                            "Assigned_Volume", "Delivered_Volume", "Sum of Total OFD", "Sum of Total Delivered",
                            "Total_Assigned_FM_RVP", "Total_Delivered_FM_RVP", "Assigned_RVP", "Delivered_RVP",
                            "Pickup_Assigned", "Pickup_Done", "Pickup_Conversion_Percentage", "Pickup_Applied_Rate",
                            "Pickup_Rate_Type", "Delivery_Payable", "Pickup_Payable", "Ded_Insurance", "Insurance",
                            "Vehicle_Type", "Shopsy_Rate_Type"
                        };
                                if (odhHideCols.Contains(kvp.Key) || odhHideCols.Contains(displayKey)) continue;
                            }

                            // HIDE ODH-MDH specific columns for ALL OTHER models
                            if (modelId == null || modelId.ToString() != "1")
                            {
                                var nonOdhHideCols = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase) {
                            "SR_LM_Return", "SR LM Return", "SR_FM_Return", "SR FM Return",
                            "Assign_RVP_Normal", "Assign RVP+Normal", "Total_Delivered_RVP_Shopsy", "Total Delivered+RVP+Shopsy",
                            "FWD_RVP_Del_Wo_SR", "FWD+RVP Del-W/o SR",
                            "U2S", "U2S_Rate", "U2S Rate", "U2S_Rate_Type", "U2S Rate Type", "U2S_Applied_Rate", "U2S Applied Rate", "U2S_Payable", "U2S Payable",
                            "Shopsy", "Shopsy_RateDeduction", "Shopsy RateDeduction", "Shopsy_RateType", "Shopsy_Rate_Type", "Shopsy Rate Type", "Shopsy_Applied_Rate", "Shopsy RateApplied", "Shopsy_Payable", "Shopsy Payable",
                            "Prexo", "Prexo_Rate", "Prexo Rate", "Prexo_Rate_Type", "Prexo Rate Type", "Prexo_Applied_Rate", "Prexo Applied Rate", "Prexo_Payable", "Prexo Payable",
                            "Grocery_Assigned", "Grocery Assigned", "Grocery_Delivered", "Grocery Delivered",
                            "Grocery_Conversion_Percentage", "Grocery Conversion %", "Grocery_Rate", "Grocery Rate",
                            "Grocery_Rate_Type", "Grocery Rate Type", "Grocery_Applied_Rate", "Grocery Applied Rate", "Grocery_Payable", "Grocery Payable",
                            "Ded_Rent", "Rent Deduction", "Ded_Advance", "Advance Deduction", "Ded_TNT", "TNT Deduction"
                        };
                                if (modelId != null && modelId.ToString() == "4")
                                {
                                    nonOdhHideCols.Remove("Ded_Advance");
                                    nonOdhHideCols.Remove("Advance Deduction");
                                }
                                if (nonOdhHideCols.Contains(kvp.Key) || nonOdhHideCols.Contains(displayKey)) continue;
                            }

                            // HIDE Amazon DSP / EDSP specific columns for other models (not model 4 or 5)
                            if (modelId == null || (modelId.ToString() != "4" && modelId.ToString() != "5"))
                            {
                                var dspHideCols = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase) {
                            "Route", "MFN_Assigned", "MFN Assign", "MFN_Done", "MFN Done", "MFN  Done",
                            "MFN_Conversion_Percentage", "MFN Conversion %",
                            "MFN_Rate_Type", "MFN RateType", "MFN Rate Type", "MFN_Applied_Rate", "MFN AppliedRate", "MFN Applied Rate", "MFN_Payable", "MFN Payable",
                            "Van_Rate", "Van Rate", "Van_Rate_Type", "Van RateType", "Van Rate Type", "Van_Applied_Rate", "VAN AppliedRate", "Van Applied Rate", "Van_Payable", "VAN Payable",
                            "PresentDays", "PresentDaysPayableRate", "PresentDaysPayable",
                            "Special_Charge", "SC", "Total_Payable", "totalPayable"
                        };
                                if (dspHideCols.Contains(kvp.Key) || dspHideCols.Contains(displayKey)) continue;
                            }

                            // HIDE DSP-only columns for EDSP (Model 5)
                            if (modelId != null && modelId.ToString() == "5")
                            {
                                var edspHideCols = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase) {
                            "Route", "Van_Rate", "Van Rate", "Van_Rate_Type", "Van RateType", "Van Rate Type", "Van_Applied_Rate", "VAN AppliedRate", "Van Applied Rate", "Van_Payable", "VAN Payable",
                            "PresentDays", "PresentDaysPayableRate", "PresentDaysPayable",
                            "Special_Charge", "SC", "Ded_Advance", "Advance Deduction",
                            "Assigned_RVP", "Delivered_RVP", "Total_Assigned_FM_RVP", "Total_Delivered_FM_RVP", "Total Assigne FM+RVP", "Total Delivered FM+RVP",
                            "Ded_Rent", "Rent Deduction", "Ded_TNT", "TNT Deduction",
                            "Ded_Insurance", "Insurance", "Ded_SD", "SD",
                            "Working_Days", "No. of Days", "Delivery_Payable", "Payable"
                        };
                                if (edspHideCols.Contains(kvp.Key) || edspHideCols.Contains(displayKey)) continue;
                            }

                            // HIDE irrelevant columns for Amazon DSP (Model 4)
                            if (modelId != null && modelId.ToString() == "4")
                            {
                                var dspSpecificHide = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase) {
                            "Assigned_RVP", "Delivered_RVP", "Total_Assigned_FM_RVP", "Total_Delivered_FM_RVP", "Total Assigne FM+RVP", "Total Delivered FM+RVP",
                            "Ded_Rent", "Rent Deduction", "Ded_TNT", "TNT Deduction",
                            "Ded_Insurance", "Insurance", "Ded_SD", "SD",
                            "Working_Days", "No. of Days", "Delivery_Payable", "Payable"
                        };
                                if (dspSpecificHide.Contains(kvp.Key) || dspSpecificHide.Contains(displayKey)) continue;
                            }

                            renamedRow[displayKey] = kvp.Value;
                        }

                        var orderedRow = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);
                        if (modelId != null && modelId.ToString() == "1")
                        {
                            var prefOrder = new string[] {
                                "Processing Status", "System Remarks",
                                "Code", "Name", "Location", "FHRID", "AreaManager", "Hub code", "No. of Days",
                                "SR LM Return", "SR FM Return", "Assign RVP+Normal", "Total Delivered+RVP+Shopsy", "FWD+RVP Del-W/o SR", "Conversion %",
                                "Rate Type", "Applied BaseRate", "Payable",
                                "U2S", "U2S Rate", "U2S Rate Type", "U2S Applied Rate", "U2S Payable",
                                "Shopsy", "Shopsy Rate Type", "Shopsy RateDeduction", "Shopsy RateApplied", "Shopsy Payable",
                                "Prexo", "Prexo Rate", "Prexo Rate Type", "Prexo Applied Rate", "Prexo Payable",
                                "Grocery Assigned", "Grocery Delivered", "Grocery Conversion %", "Grocery Rate", "Grocery Rate Type", "Grocery Applied Rate", "Grocery Payable",
                                "Base payable", "Shipment Deduction", "COD Deduction", "Other Deduction", "Rent Deduction", "Advance Deduction", "Hold", "Karma Life Deduction", "Arrear", "SD", "TNT Deduction", "Welfare Deduction",
                                "GST Percentage", "GST Amount", "Total Payable After GST", "TDS Percentage", "TDS Amount", "Net Payable",
                                "Bank Name", "Account No", "IFSC Code", "PAN No", "Aadhar No"
                            };
                            foreach (var k in prefOrder) { if (renamedRow.ContainsKey(k)) orderedRow[k] = renamedRow[k]; }
                            foreach (var kv in renamedRow) { if (!orderedRow.ContainsKey(kv.Key)) orderedRow[kv.Key] = kv.Value; }
                        }
                        else if (modelId != null && modelId.ToString() == "4")
                        {
                            var dspOrder = new string[] {
                                "Processing Status", "System Remarks",
                                "Code", "Name", "Location", "FHRID", "AreaManager", "Hub code", "Route", "Vehicle Type",
                                "Total OFD", "Total Delivered", "Conversion %", "Applied_Rate", "Rate_Type", "Base Payable",
                                "Pickup Assign", "Pickup Done", "Pickup Conversion%", "Pickup RateType", "Pickup AppliedRate", "Pickup Payable",
                                "MFN Assign", "MFN Done", "MFN Conversion %", "MFN RateType", "MFN AppliedRate", "MFN Payable",
                                "Van Rate", "Van RateType", "VAN AppliedRate", "PresentDays", "VAN Payable",
                                "PresentDaysPayableRate", "PresentDaysPayable", "SC", "totalPayable",
                                "gst%", "GstAmount", "TotalPayableAfterGST", "TDS%", "TDSAmount",
                                "Shipment Deduction", "COD Deduction", "Other Deduction", "Arrear", "Hold", "Karmalife Deduction", "Welfare Deduction", "Advance Deduction", "net payable",
                                "Bank Name", "Account No", "IFSC Code", "PAN No", "Aadhar No", "Account Holder Name"
                            };
                            foreach (var k in dspOrder) { if (renamedRow.ContainsKey(k)) orderedRow[k] = renamedRow[k]; }
                        }
                        else if (modelId != null && modelId.ToString() == "5")
                        {
                            var edspOrder = new string[] {
                                "Processing Status", "System Remarks",
                                "Code", "Name", "Location", "FHRID", "AreaManager", "Hub code", "Vehicle Type",
                                "Total OFD", "Total Delivered", "Conversion %", "Applied_Rate", "Rate_Type", "Base Payable",
                                "Pickup Assign", "Pickup Done", "Pickup Conversion%", "Pickup RateType", "Pickup AppliedRate", "Pickup Payable",
                                "MFN Assign", "MFN Done", "MFN Conversion %", "MFN RateType", "MFN AppliedRate", "MFN Payable",
                                "totalPayable",
                                "gst%", "GstAmount", "TotalPayableAfterGST", "TDS%", "TDSAmount",
                                "Shipment Deduction", "COD Deduction", "Other Deduction", "Arrear", "Hold", "Karmalife Deduction", "Welfare Deduction", "net payable",
                                "Bank Name", "Account No", "IFSC Code", "PAN No", "Aadhar No", "Account Holder Name"
                            };
                            foreach (var k in edspOrder) { if (renamedRow.ContainsKey(k)) orderedRow[k] = renamedRow[k]; }
                        }
                        else if (modelId != null && modelId.ToString() == "7")
                        {
                            var ebeesOrder = new string[] {
                                "Processing Status", "System Remarks",
                                "Code", "VendorCode", "Name", "VendorName", "Location", "LocationName", "FHRID", "FHRID", "AreaManager", "Hub code", "HubCode", 
                                "Sum of Total OFD", "Assigned_Volume", "OFD", 
                                "Sum of Total Delivered", "Delivered_Volume", "Delivered", 
                                "Conversion %", "Conversion_Percentage", 
                                "Applied BaseRate", "Applied_Rate", "Applied Rate", 
                                "Rate Type", "Rate_Type",
                                
                                "Delivery Payable", "Delivery_Payable", "Payable",
                                
                                "RTO Assign", "RTO_Assigned", "RTO Done", "RTO_Done", "RTO %", "RTO_Conversion_Percentage", "RTO Rate", "RTO_Applied_Rate", "RTO Rate Type", "RTO_Rate_Type", "RTO Payable", "RTO_Payable",
                                "DTO Assign", "DTO_Assigned", "DTO Done", "DTO_Done", "DTO %", "DTO_Conversion_Percentage", "DTO Rate", "DTO_Applied_Rate", "DTO Rate Type", "DTO_Rate_Type", "DTO Payable", "DTO_Payable",
                                "FM Assign", "FM_Assigned", "FM Done", "FM_Done", "FM %", "FM_Conversion_Percentage", "FM Rate", "FM_Applied_Rate", "FM Rate Type", "FM_Rate_Type", "FM Payable", "FM_Payable",
                                
                                "Pickup Assign", "Pickup_Assigned", "Pickup Done", "Pickup_Done", "Pickup %", "Pickup_Conversion_Percentage", "Pickup Rate", "Pickup_Applied_Rate", "Pickup Rate Type", "Pickup_Rate_Type", "Pickup Payable", "Pickup_Payable",
                                
                                "Base payable", "Base_Payable", "Base Payable",
                                
                                "Deduction", "Ded_Shipment", "COD Deduction", "Ded_COD", "Other Deduction", "Ded_Other", "Arrear", "Ded_Arrear", "Insurance", "Ded_Insurance", "SD", "Ded_SD", "Welfare Deduction", "Ded_Welfare", "Hold", "Ded_Hold", "Karma Life Deduction", "Ded_KarmaLife", "Rent Deduction", "Ded_Rent", "Advance Deduction", "Ded_Advance", "TNT Deduction", "Ded_TNT",
                                
                                "GST Percentage", "GST_Percentage", "GST Amount", "GST_Amount", "Total Payable After GST", "Total_Payable_After_GST", "TDS Percentage", "TDS_Percentage", "TDS Amount", "TDS_Amount", "Net Payable", "Net_Payable",
                                
                                "Bank Name", "Vendor_BankName", "Account No", "Vendor_AccountNo", "IFSC Code", "Vendor_IFSCCode", "PAN No", "Vendor_PanNo", "Aadhar No", "Vendor_AaddharNo", "Account Holder Name", "Vendor_AccountHolderName", "Date Range", "TransactionRange", "Uploaded By", "UploadedByName"
                            };
                            foreach (var k in ebeesOrder) { if (renamedRow.ContainsKey(k)) orderedRow[k] = renamedRow[k]; }
                            foreach (var kv in renamedRow) { if (!orderedRow.ContainsKey(kv.Key)) orderedRow[kv.Key] = kv.Value; }
                        }
                        else
                        {
                            // For all other models, preserve natural DB config order
                            foreach (var kv in renamedRow) { orderedRow[kv.Key] = kv.Value; }
                        }
                        renamedList.Add(orderedRow);

                    }
                }

                // --- 2. ADD TAB 2 USING CLOSEDXML ---
                try
                {
                    using (var wb = new ClosedXML.Excel.XLWorkbook(physicalPath))
                    {
                        string summarySheetName = "Upload Summary";
                        var existingSummary = wb.Worksheets.FirstOrDefault(w => w.Name.Equals(summarySheetName, StringComparison.OrdinalIgnoreCase));
                        if (existingSummary != null) wb.Worksheets.Delete(existingSummary.Name);

                        var ws = wb.Worksheets.Add(summarySheetName);

                        int totalCount = renamedList.Count;
                        int successCount = renamedList.Count(r =>
                        {
                            var dict = r as IDictionary<string, object>;
                            var st = dict.ContainsKey("Processing Status") ? Convert.ToString(dict["Processing Status"]) : "";
                            return st == "Success" || st == "Processed";
                        });
                        int failedCount = totalCount - successCount;

                        // Top Summary Metrics
                        ws.Cell(1, 1).Value = "Client:";
                        ws.Cell(1, 1).Style.Font.Bold = true;
                        ws.Cell(1, 2).Value = clientName;
                        ws.Cell(1, 2).Style.Font.Bold = true;
                        ws.Cell(1, 2).Style.Font.FontColor = ClosedXML.Excel.XLColor.FromArgb(13, 110, 253);

                        ws.Cell(1, 4).Value = "Model:";
                        ws.Cell(1, 4).Style.Font.Bold = true;
                        ws.Cell(1, 5).Value = modelName;
                        ws.Cell(1, 5).Style.Font.Bold = true;
                        ws.Cell(1, 5).Style.Font.FontColor = ClosedXML.Excel.XLColor.FromArgb(13, 110, 253);

                        ws.Cell(2, 1).Value = "Total Records";
                        ws.Cell(2, 1).Style.Font.Bold = true;
                        ws.Cell(2, 1).Style.Fill.BackgroundColor = ClosedXML.Excel.XLColor.FromArgb(13, 110, 253);
                        ws.Cell(2, 1).Style.Font.FontColor = ClosedXML.Excel.XLColor.White;

                        ws.Cell(2, 2).Value = totalCount;
                        ws.Cell(2, 2).Style.Font.Bold = true;

                        ws.Cell(2, 4).Value = "Success";
                        ws.Cell(2, 4).Style.Font.Bold = true;
                        ws.Cell(2, 4).Style.Fill.BackgroundColor = ClosedXML.Excel.XLColor.FromArgb(25, 135, 84);
                        ws.Cell(2, 4).Style.Font.FontColor = ClosedXML.Excel.XLColor.White;

                        ws.Cell(2, 5).Value = successCount;
                        ws.Cell(2, 5).Style.Font.Bold = true;

                        ws.Cell(2, 7).Value = "Failed";
                        ws.Cell(2, 7).Style.Font.Bold = true;
                        ws.Cell(2, 7).Style.Fill.BackgroundColor = ClosedXML.Excel.XLColor.FromArgb(220, 53, 69);
                        ws.Cell(2, 7).Style.Font.FontColor = ClosedXML.Excel.XLColor.White;

                        ws.Cell(2, 8).Value = failedCount;
                        ws.Cell(2, 8).Style.Font.Bold = true;

                        // Fetch Formulas and Names
                        var formulaMap = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                        var stdColToDisplayName = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                        string finalClientName = clientName ?? "";
                        string finalModelName = modelName ?? "";

                        try
                        {
                            if (string.IsNullOrEmpty(finalClientName)) finalClientName = await _vendorRepository.GetClientNameAsync(cId);
                            if (string.IsNullOrEmpty(finalModelName)) finalModelName = await _vendorRepository.GetModelNameAsync(mId);

                            var configData = await _vendorRepository.GetVendorTemplateConfigAsync(cId, mId);
                            foreach (var row in configData)
                            {
                                var dict = (IDictionary<string, object>)row;
                                var stdCol = dict.ContainsKey("StandardDbColumn") ? Convert.ToString(dict["StandardDbColumn"]) ?? "" : "";
                                var excelHeader = dict.ContainsKey("ExcelHeaderName") ? Convert.ToString(dict["ExcelHeaderName"]) ?? "" : "";
                                var formula = dict.ContainsKey("FormulaDescription") ? Convert.ToString(dict["FormulaDescription"]) ?? "" : "";
                                stdColToDisplayName[stdCol] = excelHeader;
                                if (!string.IsNullOrEmpty(formula)) formulaMap[stdCol] = formula;
                            }
                        }
                        catch { }

                        // Update Top Summary Metrics with DB names if form was empty
                        ws.Cell(1, 2).Value = finalClientName;
                        ws.Cell(1, 5).Value = finalModelName;

                        var resolvedFormulaMap = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                        foreach (var kv in formulaMap)
                        {
                            var resolved = kv.Value;
                            foreach (var stdKv in stdColToDisplayName)
                                resolved = resolved.Replace("{" + stdKv.Key + "}", "[" + stdKv.Value + "]");

                            if (stdColToDisplayName.ContainsKey(kv.Key))
                            {
                                resolvedFormulaMap[stdColToDisplayName[kv.Key]] = resolved;
                            }
                            else
                            {
                                resolvedFormulaMap[kv.Key] = resolved;
                            }
                        }
                        formulaMap = new Dictionary<string, string>(resolvedFormulaMap, StringComparer.OrdinalIgnoreCase);

                        int summaryHeaderRow = 4;
                        if (renamedList.Any())
                        {
                            var firstRow = renamedList.First();
                            var excludeKeys = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "TotalRows", "TransactionID", "UploadBatchID", "fk_cost_centre_id", "fk_model_id", "fk_rec_id", "ClientID", "ModelID", "LocationID", "CreatedBy", "CreatedDate", "IsProcessed", "fk_File_Id", "FHRID", "FromDate", "ToDate", "CycleName", "BudgetaryCode", "StateName", "Payment_Status", "HR_Remark", "Central_Remark" };
                            var keys = firstRow.Keys.Where(k => !excludeKeys.Contains(k)).ToList();

                            // Headers
                            for (int c = 0; c < keys.Count; c++)
                            {
                                var cell = ws.Cell(summaryHeaderRow, c + 1);
                                cell.Value = keys[c];
                                cell.Style.Font.Bold = true;
                                cell.Style.Fill.BackgroundColor = ClosedXML.Excel.XLColor.FromArgb(52, 58, 64);
                                cell.Style.Font.FontColor = ClosedXML.Excel.XLColor.White;
                            }

                            // Formulas
                            int formulaRow = summaryHeaderRow + 1;
                            ws.Cell(formulaRow, 1).Value = "Formula:";
                            ws.Cell(formulaRow, 1).Style.Font.Italic = true;
                            ws.Cell(formulaRow, 1).Style.Font.FontColor = ClosedXML.Excel.XLColor.Gray;
                            for (int c = 0; c < keys.Count; c++)
                            {
                                if (formulaMap.ContainsKey(keys[c]))
                                {
                                    var fCell = ws.Cell(formulaRow, c + 1);
                                    fCell.Value = formulaMap[keys[c]];
                                    fCell.Style.Font.Italic = true;
                                    fCell.Style.Font.FontColor = ClosedXML.Excel.XLColor.Gray;
                                }
                            }

                            // Data
                            int rowIdx = formulaRow + 1;
                            foreach (var dataRow in renamedList)
                            {
                                for (int c = 0; c < keys.Count; c++)
                                {
                                    if (dataRow.ContainsKey(keys[c]))
                                    {
                                        ws.Cell(rowIdx, c + 1).Value = dataRow[keys[c]]?.ToString();
                                    }
                                }
                                rowIdx++;
                            }
                        }
                        ws.Columns().AdjustToContents();
                        wb.Save();
                    }
                }
                catch (Exception cwEx)
                {
                    Console.WriteLine("Error generating tab 2: " + cwEx.Message);
                }

                modelResponse.IsSuccess = true;
                modelResponse.Message = "Transaction processed and saved successfully.";
                modelResponse.Data = renamedList;
                modelResponse.StatusCode = 200;

                return Ok(modelResponse);
            }
            catch (Exception ex)
            {
                return Ok(new ModelResponse { IsSuccess = false, Message = ex.Message, StatusCode = 500 });
            }
        }

        [HttpGet("TransactionList")]
        public async Task<IActionResult> GetTransactionList([FromQuery] int clientId, [FromQuery] int modelId, [FromQuery] string? locationId = null, [FromQuery] string? transactionRange = null, [FromQuery] string? vendorCode = null, [FromQuery] string? searchTerm = null)
        {
            var (totalCount, list) = await _vendorRepository.GetVendorPaymentTransactionsListAsync(clientId, modelId, locationId, transactionRange, vendorCode, searchTerm, 1, 999999);

            var outputRenameMap = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            var formulaMap = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            var stdColToDisplayName = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            var templateConfigHeaderOrder = new List<string>();

            try
            {
                var configData = await _vendorRepository.GetVendorTemplateConfigAsync(clientId, modelId);
                foreach (var row in configData)
                {
                    var dict = (IDictionary<string, object>)row;
                    var stdCol = dict.ContainsKey("StandardDbColumn") ? Convert.ToString(dict["StandardDbColumn"]) ?? "" : "";
                    var excelHeader = dict.ContainsKey("ExcelHeaderName") ? Convert.ToString(dict["ExcelHeaderName"]) ?? "" : "";
                    var formula = dict.ContainsKey("FormulaDescription") ? Convert.ToString(dict["FormulaDescription"]) ?? "" : "";
                    stdColToDisplayName[stdCol] = excelHeader;
                    outputRenameMap[stdCol] = excelHeader;
                    if (!string.IsNullOrEmpty(excelHeader) && !templateConfigHeaderOrder.Contains(excelHeader)) templateConfigHeaderOrder.Add(excelHeader);
                    if (!string.IsNullOrEmpty(formula)) formulaMap[stdCol] = formula;
                }
            }
            catch { }

            var resolvedFormulaMap = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var kv in formulaMap)
            {
                var resolved = kv.Value;
                foreach (var stdKv in stdColToDisplayName)
                    resolved = resolved.Replace("{" + stdKv.Key + "}", "[" + stdKv.Value + "]");

                if (stdColToDisplayName.ContainsKey(kv.Key))
                {
                    resolvedFormulaMap[stdColToDisplayName[kv.Key]] = resolved;
                }
                else
                {
                    resolvedFormulaMap[kv.Key] = resolved;
                }
            }
            formulaMap = new Dictionary<string, string>(resolvedFormulaMap, StringComparer.OrdinalIgnoreCase);

            var renamedList = new List<Dictionary<string, object>>();
            foreach (var rawRow in list)
            {
                var rawDict = (IDictionary<string, object>)rawRow;
                var renamedRow = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);

                foreach (var kvp in rawDict)
                {
                    var internalExclude = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase) {
                        "TotalRows", "TotalRecords", "TransactionID", "UploadBatchID", "fk_cost_centre_id", "fk_model_id", "fk_rec_id",
                        "ClientID", "ModelID", "LocationID", "CreatedBy", "CreatedDate", "IsProcessed", "fk_File_Id", "FHRID",
                        "FromDate", "ToDate", "CycleName", "BudgetaryCode", "StateName", "Payment_Status", "Payment Status",
                        "HR_Remark", "HR Remark", "Central_Remark", "Central Remark"
                    };
                    if (internalExclude.Contains(kvp.Key)) continue;

                    bool isPickupEnabled = outputRenameMap.ContainsKey("Pickup_Assigned") || outputRenameMap.ContainsKey("pickup_assigned") || outputRenameMap.Values.Contains("Pickup Assign");
                    var ebeesCols = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase) { "Pickup_Assigned", "Pickup_Done", "Pickup_Conversion_Percentage", "Pickup_Applied_Rate", "Pickup_Rate_Type", "Delivery_Payable", "Pickup_Payable" };
                    if (ebeesCols.Contains(kvp.Key) && !isPickupEnabled) continue;
                    var dedCols = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase) { "Ded_Shipment", "Ded_COD", "Ded_Other", "Ded_Arrear", "Ded_Insurance", "Ded_SD", "Ded_Welfare", "Ded_Hold", "Ded_KarmaLife" };
                    if (dedCols.Contains(kvp.Key) && !outputRenameMap.ContainsKey(kvp.Key)) continue;
                    if (modelId != null && modelId.ToString() == "3" && kvp.Key.Equals("Assigned_Volume", StringComparison.OrdinalIgnoreCase)) continue;
                    var fmCols = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase) { "Total_Assigned_FM_RVP", "Total_Delivered_FM_RVP", "Assigned_RVP", "Delivered_RVP", "Vehicle_Type", "Working_Days" };
                    if (fmCols.Contains(kvp.Key) && !outputRenameMap.ContainsKey(kvp.Key)) continue;

                    string displayKey = kvp.Key;

                    if (outputRenameMap.ContainsKey(kvp.Key))
                    {
                        displayKey = outputRenameMap[kvp.Key];
                    }
                    else if (kvp.Key.Equals("VendorCode", StringComparison.OrdinalIgnoreCase)) displayKey = "Code";
                    else if (kvp.Key.Equals("VendorName", StringComparison.OrdinalIgnoreCase)) displayKey = "Name";
                    else if (kvp.Key.Equals("LocationName", StringComparison.OrdinalIgnoreCase)) displayKey = "Location";
                    else if (kvp.Key.Equals("FHRID", StringComparison.OrdinalIgnoreCase)) displayKey = "FHRID";
                    else if (kvp.Key.Equals("HubCode", StringComparison.OrdinalIgnoreCase)) displayKey = "Hub code";
                    else if (kvp.Key.Equals("Working_Days", StringComparison.OrdinalIgnoreCase)) displayKey = "No. of Days";
                    else if (kvp.Key.Equals("Processing_Status", StringComparison.OrdinalIgnoreCase)) displayKey = "Processing Status";
                    else if (kvp.Key.Equals("System_Remarks", StringComparison.OrdinalIgnoreCase)) displayKey = "System Remarks";
                    else if (kvp.Key.Equals("Assigned_Volume", StringComparison.OrdinalIgnoreCase)) displayKey = "Sum of Total OFD";
                    else if (kvp.Key.Equals("Delivered_Volume", StringComparison.OrdinalIgnoreCase)) displayKey = "Sum of Total Delivered";
                    else if (kvp.Key.Equals("Conversion_Percentage", StringComparison.OrdinalIgnoreCase)) displayKey = "Conversion %";
                    else if (kvp.Key.Equals("Applied_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "Applied BaseRate";
                    else if (kvp.Key.Equals("Rate_Type", StringComparison.OrdinalIgnoreCase)) displayKey = "Rate Type";
                    else if (kvp.Key.Equals("Base_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "Base payable";
                    else if (kvp.Key.Equals("GST_Percentage", StringComparison.OrdinalIgnoreCase)) displayKey = "GST Percentage";
                    else if (kvp.Key.Equals("GST_Amount", StringComparison.OrdinalIgnoreCase)) displayKey = "GST Amount";
                    else if (kvp.Key.Equals("Total_Payable_After_GST", StringComparison.OrdinalIgnoreCase)) displayKey = "Total Payable After GST";
                    else if (kvp.Key.Equals("TDS_Percentage", StringComparison.OrdinalIgnoreCase)) displayKey = "TDS Percentage";
                    else if (kvp.Key.Equals("TDS_Amount", StringComparison.OrdinalIgnoreCase)) displayKey = "TDS Amount";
                    else if (kvp.Key.Equals("Net_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "Net Payable";
                    else if (kvp.Key.Equals("Vendor_BankName", StringComparison.OrdinalIgnoreCase)) displayKey = "Bank Name";
                    else if (kvp.Key.Equals("Vendor_AccountNo", StringComparison.OrdinalIgnoreCase)) displayKey = "Account No";
                    else if (kvp.Key.Equals("Vendor_IFSCCode", StringComparison.OrdinalIgnoreCase)) displayKey = "IFSC Code";
                    else if (kvp.Key.Equals("Vendor_PanNo", StringComparison.OrdinalIgnoreCase)) displayKey = "PAN No";
                    else if (kvp.Key.Equals("Vendor_AaddharNo", StringComparison.OrdinalIgnoreCase)) displayKey = "Aadhar No";
                    else if (kvp.Key.Equals("Vendor_AccountHolderName", StringComparison.OrdinalIgnoreCase)) displayKey = "Account Holder Name";
                    else if (kvp.Key.Equals("TransactionRange", StringComparison.OrdinalIgnoreCase)) displayKey = "Date Range";
                    else if (kvp.Key.Equals("UploadedByName", StringComparison.OrdinalIgnoreCase)) displayKey = "Uploaded By";
                    else if (kvp.Key.Equals("Ded_Shipment", StringComparison.OrdinalIgnoreCase)) displayKey = "Deduction";
                    else if (kvp.Key.Equals("Ded_COD", StringComparison.OrdinalIgnoreCase)) displayKey = "COD Deduction";
                    else if (kvp.Key.Equals("Ded_Other", StringComparison.OrdinalIgnoreCase)) displayKey = "Other Deduction";
                    else if (kvp.Key.Equals("Ded_Arrear", StringComparison.OrdinalIgnoreCase)) displayKey = "Arrear";
                    else if (kvp.Key.Equals("Ded_Insurance", StringComparison.OrdinalIgnoreCase)) displayKey = "Insurance";
                    else if (kvp.Key.Equals("Ded_SD", StringComparison.OrdinalIgnoreCase)) displayKey = "SD";
                    else if (kvp.Key.Equals("Ded_Welfare", StringComparison.OrdinalIgnoreCase)) displayKey = "Welfare Deduction";
                    else if (kvp.Key.Equals("Ded_Hold", StringComparison.OrdinalIgnoreCase)) displayKey = "Hold";
                    else if (kvp.Key.Equals("Ded_KarmaLife", StringComparison.OrdinalIgnoreCase)) displayKey = "Karma Life Deduction";
                    else if (kvp.Key.Equals("Ded_Rent", StringComparison.OrdinalIgnoreCase)) displayKey = "Rent Deduction";
                    else if (kvp.Key.Equals("Ded_Advance", StringComparison.OrdinalIgnoreCase)) displayKey = "Advance Deduction";
                    else if (kvp.Key.Equals("Ded_TNT", StringComparison.OrdinalIgnoreCase)) displayKey = "TNT Deduction";
                    else if (kvp.Key.Equals("SR_LM_Return", StringComparison.OrdinalIgnoreCase)) displayKey = "SR LM Return";
                    else if (kvp.Key.Equals("SR_FM_Return", StringComparison.OrdinalIgnoreCase)) displayKey = "SR FM Return";
                    else if (kvp.Key.Equals("Assign_RVP_Normal", StringComparison.OrdinalIgnoreCase)) displayKey = "Assign RVP+Normal";
                    else if (kvp.Key.Equals("Total_Delivered_RVP_Shopsy", StringComparison.OrdinalIgnoreCase)) displayKey = "Total Delivered+RVP+Shopsy";
                    else if (kvp.Key.Equals("FWD_RVP_Del_Wo_SR", StringComparison.OrdinalIgnoreCase)) displayKey = "FWD+RVP Del-W/o SR";
                    else if (kvp.Key.Equals("Delivery_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "Payable";
                    else if (kvp.Key.Equals("U2S_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "U2S Rate";
                    else if (kvp.Key.Equals("U2S_Rate_Type", StringComparison.OrdinalIgnoreCase)) displayKey = "U2S Rate Type";
                    else if (kvp.Key.Equals("U2S_Applied_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "U2S Applied Rate";
                    else if (kvp.Key.Equals("U2S_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "U2S Payable";
                    else if (kvp.Key.Equals("Shopsy_RateDeduction", StringComparison.OrdinalIgnoreCase)) displayKey = "Shopsy RateDeduction";
                    else if (kvp.Key.Equals("Shopsy_RateType", StringComparison.OrdinalIgnoreCase)) displayKey = "Shopsy Rate Type";
                    else if (kvp.Key.Equals("Shopsy_Applied_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "Shopsy RateApplied";
                    else if (kvp.Key.Equals("Shopsy_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "Shopsy Payable";
                    else if (kvp.Key.Equals("Prexo_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "Prexo Rate";
                    else if (kvp.Key.Equals("Prexo_Rate_Type", StringComparison.OrdinalIgnoreCase)) displayKey = "Prexo Rate Type";
                    else if (kvp.Key.Equals("Prexo_Applied_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "Prexo Applied Rate";
                    else if (kvp.Key.Equals("Prexo_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "Prexo Payable";
                    else if (kvp.Key.Equals("Grocery_Assigned", StringComparison.OrdinalIgnoreCase)) displayKey = "Grocery Assigned";
                    else if (kvp.Key.Equals("Grocery_Delivered", StringComparison.OrdinalIgnoreCase)) displayKey = "Grocery Delivered";
                    else if (kvp.Key.Equals("Grocery_Conversion_Percentage", StringComparison.OrdinalIgnoreCase)) displayKey = "Grocery Conversion %";
                    else if (kvp.Key.Equals("Grocery_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "Grocery Rate";
                    else if (kvp.Key.Equals("Grocery_Rate_Type", StringComparison.OrdinalIgnoreCase)) displayKey = "Grocery Rate Type";
                    else if (kvp.Key.Equals("Grocery_Applied_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "Grocery Applied Rate";
                    else if (kvp.Key.Equals("Grocery_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "Grocery Payable";
                    else if (kvp.Key.Equals("Pickup_Conversion_Percentage", StringComparison.OrdinalIgnoreCase)) displayKey = "Pickup %";
                    else if (kvp.Key.Equals("Pickup_Applied_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "Pickup Rate";
                    else if (kvp.Key.Equals("Pickup_Rate_Type", StringComparison.OrdinalIgnoreCase)) displayKey = "Pickup Rate Type";
                    else if (kvp.Key.Equals("Pickup_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "Pickup Payable";
                    // *** NEW: RTO display mappings ***
                    else if (kvp.Key.Equals("RTO_Assigned",              StringComparison.OrdinalIgnoreCase)) displayKey = "RTO Assign";
                    else if (kvp.Key.Equals("RTO_Done",                  StringComparison.OrdinalIgnoreCase)) displayKey = "RTO Done";
                    else if (kvp.Key.Equals("RTO_Conversion_Percentage", StringComparison.OrdinalIgnoreCase)) displayKey = "RTO %";
                    else if (kvp.Key.Equals("RTO_Applied_Rate",          StringComparison.OrdinalIgnoreCase)) displayKey = "RTO Rate";
                    else if (kvp.Key.Equals("RTO_Rate_Type",             StringComparison.OrdinalIgnoreCase)) displayKey = "RTO Rate Type";
                    else if (kvp.Key.Equals("RTO_Payable",               StringComparison.OrdinalIgnoreCase)) displayKey = "RTO Payable";
                    // *** NEW: DTO display mappings ***
                    else if (kvp.Key.Equals("DTO_Assigned",              StringComparison.OrdinalIgnoreCase)) displayKey = "DTO Assign";
                    else if (kvp.Key.Equals("DTO_Done",                  StringComparison.OrdinalIgnoreCase)) displayKey = "DTO Done";
                    else if (kvp.Key.Equals("DTO_Conversion_Percentage", StringComparison.OrdinalIgnoreCase)) displayKey = "DTO %";
                    else if (kvp.Key.Equals("DTO_Applied_Rate",          StringComparison.OrdinalIgnoreCase)) displayKey = "DTO Rate";
                    else if (kvp.Key.Equals("DTO_Rate_Type",             StringComparison.OrdinalIgnoreCase)) displayKey = "DTO Rate Type";
                    else if (kvp.Key.Equals("DTO_Payable",               StringComparison.OrdinalIgnoreCase)) displayKey = "DTO Payable";
                    // *** NEW: FM display mappings ***
                    else if (kvp.Key.Equals("FM_Assigned",               StringComparison.OrdinalIgnoreCase)) displayKey = "FM Assign";
                    else if (kvp.Key.Equals("FM_Done",                   StringComparison.OrdinalIgnoreCase)) displayKey = "FM Done";
                    else if (kvp.Key.Equals("FM_Conversion_Percentage",  StringComparison.OrdinalIgnoreCase)) displayKey = "FM %";
                    else if (kvp.Key.Equals("FM_Applied_Rate",           StringComparison.OrdinalIgnoreCase)) displayKey = "FM Rate";
                    else if (kvp.Key.Equals("FM_Rate_Type",              StringComparison.OrdinalIgnoreCase)) displayKey = "FM Rate Type";
                    else if (kvp.Key.Equals("FM_Payable",                StringComparison.OrdinalIgnoreCase)) displayKey = "FM Payable";
                    else if (kvp.Key.Equals("Total_Assigned_FM_RVP", StringComparison.OrdinalIgnoreCase)) displayKey = "Total Assigne FM+RVP";
                    else if (kvp.Key.Equals("Route", StringComparison.OrdinalIgnoreCase)) displayKey = "Route";
                    else if (kvp.Key.Equals("MFN_Assigned", StringComparison.OrdinalIgnoreCase)) displayKey = "MFN Assign";
                    else if (kvp.Key.Equals("MFN_Done", StringComparison.OrdinalIgnoreCase)) displayKey = "MFN Done";
                    else if (kvp.Key.Equals("MFN_Conversion_Percentage", StringComparison.OrdinalIgnoreCase)) displayKey = "MFN Conversion %";
                    else if (kvp.Key.Equals("MFN_Rate_Type", StringComparison.OrdinalIgnoreCase)) displayKey = "MFN RateType";
                    else if (kvp.Key.Equals("MFN_Applied_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "MFN AppliedRate";
                    else if (kvp.Key.Equals("MFN_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "MFN Payable";
                    else if (kvp.Key.Equals("Van_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "Van Rate";
                    else if (kvp.Key.Equals("Van_Rate_Type", StringComparison.OrdinalIgnoreCase)) displayKey = "Van RateType";
                    else if (kvp.Key.Equals("Van_Applied_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "VAN AppliedRate";
                    else if (kvp.Key.Equals("PresentDays", StringComparison.OrdinalIgnoreCase)) displayKey = "PresentDays";
                    else if (kvp.Key.Equals("Van_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "VAN Payable";
                    else if (kvp.Key.Equals("PresentDaysPayableRate", StringComparison.OrdinalIgnoreCase)) displayKey = "PresentDaysPayableRate";
                    else if (kvp.Key.Equals("PresentDaysPayable", StringComparison.OrdinalIgnoreCase)) displayKey = "PresentDaysPayable";
                    else if (kvp.Key.Equals("Special_Charge", StringComparison.OrdinalIgnoreCase)) displayKey = "SC";
                    else if (kvp.Key.Equals("Total_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "totalPayable";

                    // HIDE irrelevant columns for ODH-MDH (ModelId = 1)
                    if (modelId.ToString() == "1")
                    {
                        var odhHideCols = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase) {
                            "Assigned_Volume", "Delivered_Volume", "Sum of Total OFD", "Sum of Total Delivered",
                            "Total_Assigned_FM_RVP", "Total_Delivered_FM_RVP", "Assigned_RVP", "Delivered_RVP",
                            "Pickup_Assigned", "Pickup_Done", "Pickup_Conversion_Percentage", "Pickup_Applied_Rate",
                            "Pickup_Rate_Type", "Delivery_Payable", "Pickup_Payable", "Ded_Insurance", "Insurance",
                            "Vehicle_Type", "Shopsy_Rate_Type"
                        };
                        if (odhHideCols.Contains(kvp.Key) || odhHideCols.Contains(displayKey)) continue;
                    }

                    // HIDE ODH-MDH specific columns for ALL OTHER models
                    if (modelId.ToString() != "1")
                    {
                        var nonOdhHideCols = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase) {
                            "SR_LM_Return", "SR LM Return", "SR_FM_Return", "SR FM Return",
                            "Assign_RVP_Normal", "Assign RVP+Normal", "Total_Delivered_RVP_Shopsy", "Total Delivered+RVP+Shopsy",
                            "FWD_RVP_Del_Wo_SR", "FWD+RVP Del-W/o SR",
                            "U2S", "U2S_Rate", "U2S Rate", "U2S_Rate_Type", "U2S Rate Type", "U2S_Applied_Rate", "U2S Applied Rate", "U2S_Payable", "U2S Payable",
                            "Shopsy", "Shopsy_RateDeduction", "Shopsy RateDeduction", "Shopsy_RateType", "Shopsy_Rate_Type", "Shopsy Rate Type", "Shopsy_Applied_Rate", "Shopsy RateApplied", "Shopsy_Payable", "Shopsy Payable",
                            "Prexo", "Prexo_Rate", "Prexo Rate", "Prexo_Rate_Type", "Prexo Rate Type", "Prexo_Applied_Rate", "Prexo Applied Rate", "Prexo_Payable", "Prexo Payable",
                            "Grocery_Assigned", "Grocery Assigned", "Grocery_Delivered", "Grocery Delivered",
                            "Grocery_Conversion_Percentage", "Grocery Conversion %", "Grocery_Rate", "Grocery Rate",
                            "Grocery_Rate_Type", "Grocery Rate Type", "Grocery_Applied_Rate", "Grocery Applied Rate", "Grocery_Payable", "Grocery Payable",
                            "Ded_Rent", "Rent Deduction", "Ded_Advance", "Advance Deduction", "Ded_TNT", "TNT Deduction"
                        };
                        if (modelId.ToString() == "4")
                        {
                            nonOdhHideCols.Remove("Ded_Advance");
                            nonOdhHideCols.Remove("Advance Deduction");
                        }
                        if (nonOdhHideCols.Contains(kvp.Key) || nonOdhHideCols.Contains(displayKey)) continue;
                    }

                    // HIDE Amazon DSP / EDSP specific columns for other models (not model 4 or 5)
                    if (modelId.ToString() != "4" && modelId.ToString() != "5")
                    {
                        var dspHideCols = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase) {
                            "Route", "MFN_Assigned", "MFN Assign", "MFN_Done", "MFN Done", "MFN  Done",
                            "MFN_Conversion_Percentage", "MFN Conversion %",
                            "MFN_Rate_Type", "MFN RateType", "MFN Rate Type", "MFN_Applied_Rate", "MFN AppliedRate", "MFN Applied Rate", "MFN_Payable", "MFN Payable",
                            "Van_Rate", "Van Rate", "Van_Rate_Type", "Van RateType", "Van Rate Type", "Van_Applied_Rate", "VAN AppliedRate", "Van Applied Rate", "Van_Payable", "VAN Payable",
                            "PresentDays", "PresentDaysPayableRate", "PresentDaysPayable",
                            "Special_Charge", "SC", "Total_Payable", "totalPayable"
                        };
                        if (dspHideCols.Contains(kvp.Key) || dspHideCols.Contains(displayKey)) continue;
                    }

                    // HIDE DSP-only columns for EDSP (Model 5)
                    if (modelId.ToString() == "5")
                    {
                        var edspHideCols = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase) {
                            "Route", "Van_Rate", "Van Rate", "Van_Rate_Type", "Van RateType", "Van Rate Type", "Van_Applied_Rate", "VAN AppliedRate", "Van Applied Rate", "Van_Payable", "VAN Payable",
                            "PresentDays", "PresentDaysPayableRate", "PresentDaysPayable",
                            "Special_Charge", "SC", "Ded_Advance", "Advance Deduction",
                            "Assigned_RVP", "Delivered_RVP", "Total_Assigned_FM_RVP", "Total_Delivered_FM_RVP", "Total Assigne FM+RVP", "Total Delivered FM+RVP",
                            "Ded_Rent", "Rent Deduction", "Ded_TNT", "TNT Deduction",
                            "Ded_Insurance", "Insurance", "Ded_SD", "SD",
                            "Working_Days", "No. of Days", "Delivery_Payable", "Payable"
                        };
                        if (edspHideCols.Contains(kvp.Key) || edspHideCols.Contains(displayKey)) continue;
                    }

                    // HIDE irrelevant columns for Amazon DSP (Model 4)
                    if (modelId.ToString() == "4")
                    {
                        var dspSpecificHide = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase) {
                            "Assigned_RVP", "Delivered_RVP", "Total_Assigned_FM_RVP", "Total_Delivered_FM_RVP", "Total Assigne FM+RVP", "Total Delivered FM+RVP",
                            "Ded_Rent", "Rent Deduction", "Ded_TNT", "TNT Deduction",
                            "Ded_Insurance", "Insurance", "Ded_SD", "SD",
                            "Working_Days", "No. of Days", "Delivery_Payable", "Payable"
                        };
                        if (dspSpecificHide.Contains(kvp.Key) || dspSpecificHide.Contains(displayKey)) continue;
                    }

                    renamedRow[displayKey] = kvp.Value;
                }

                var orderedRow = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);
                if (modelId.ToString() == "1")
                {
                    var prefOrder = new string[] {
                                "Processing Status", "System Remarks",
                                "Code", "Name", "Location", "FHRID", "AreaManager", "Hub code", "No. of Days",
                                "SR LM Return", "SR FM Return", "Assign RVP+Normal", "Total Delivered+RVP+Shopsy", "FWD+RVP Del-W/o SR", "Conversion %",
                                "Rate Type", "Applied BaseRate", "Payable",
                                "U2S", "U2S Rate", "U2S Rate Type", "U2S Applied Rate", "U2S Payable",
                                "Shopsy", "Shopsy Rate Type", "Shopsy RateDeduction", "Shopsy RateApplied", "Shopsy Payable",
                                "Prexo", "Prexo Rate", "Prexo Rate Type", "Prexo Applied Rate", "Prexo Payable",
                                "Grocery Assigned", "Grocery Delivered", "Grocery Conversion %", "Grocery Rate", "Grocery Rate Type", "Grocery Applied Rate", "Grocery Payable",
                                "Base payable", "Shipment Deduction", "COD Deduction", "Other Deduction", "Rent Deduction", "Advance Deduction", "Hold", "Karma Life Deduction", "Arrear", "SD", "TNT Deduction", "Welfare Deduction",
                                "GST Percentage", "GST Amount", "Total Payable After GST", "TDS Percentage", "TDS Amount", "Net Payable",
                                "Bank Name", "Account No", "IFSC Code", "PAN No", "Aadhar No"
                            };
                    foreach (var k in prefOrder)
                    {
                        if (renamedRow.ContainsKey(k)) orderedRow[k] = renamedRow[k];
                    }
                    foreach (var kv in renamedRow)
                    {
                        if (!orderedRow.ContainsKey(kv.Key)) orderedRow[kv.Key] = kv.Value;
                    }
                }
                else if (modelId.ToString() == "4")
                {
                    var dspOrder = new string[] {
                                "Code", "Name", "Location", "FHRID", "AreaManager", "Hub code", "Route", "Vehicle Type",
                                "Total OFD", "Total Delivered", "Conversion %", "Applied_Rate", "Rate_Type", "Base Payable",
                                "Pickup Assign", "Pickup Done", "Pickup Conversion%", "Pickup RateType", "Pickup AppliedRate", "Pickup Payable",
                                "MFN Assign", "MFN Done", "MFN Conversion %", "MFN RateType", "MFN AppliedRate", "MFN Payable",
                                "Van Rate", "Van RateType", "VAN AppliedRate", "PresentDays", "VAN Payable",
                                "PresentDaysPayableRate", "PresentDaysPayable", "SC", "totalPayable",
                                "gst%", "GstAmount", "TotalPayableAfterGST", "TDS%", "TDSAmount",
                                "Shipment Deduction", "COD Deduction", "Other Deduction", "Arrear", "Hold", "Karmalife Deduction", "Welfare Deduction", "Advance Deduction", "net payable",
                                "Processing Status", "System Remarks", "Bank Name", "Account No", "IFSC Code", "PAN No", "Aadhar No", "Account Holder Name", "Date Range", "Uploaded By"
                            };
                    foreach (var k in dspOrder)
                    {
                        if (renamedRow.ContainsKey(k)) orderedRow[k] = renamedRow[k];
                    }
                }
                else if (modelId.ToString() == "5")
                {
                    var edspOrder = new string[] {
                                "Code", "Name", "Location", "FHRID", "AreaManager", "Hub code", "Vehicle Type",
                                "Total OFD", "Total Delivered", "Conversion %", "Applied_Rate", "Rate_Type", "Base Payable",
                                "Pickup Assign", "Pickup Done", "Pickup Conversion%", "Pickup RateType", "Pickup AppliedRate", "Pickup Payable",
                                "MFN Assign", "MFN Done", "MFN Conversion %", "MFN RateType", "MFN AppliedRate", "MFN Payable",
                                "totalPayable",
                                "gst%", "GstAmount", "TotalPayableAfterGST", "TDS%", "TDSAmount",
                                "Shipment Deduction", "COD Deduction", "Other Deduction", "Arrear", "Hold", "Karmalife Deduction", "Welfare Deduction", "net payable",
                                "Processing Status", "System Remarks", "Bank Name", "Account No", "IFSC Code", "PAN No", "Aadhar No", "Account Holder Name", "Date Range", "Uploaded By"
                            };
                    foreach (var k in edspOrder)
                    {
                        if (renamedRow.ContainsKey(k)) orderedRow[k] = renamedRow[k];
                    }
                }
                else if (modelId.ToString() == "7")
                {
                    var ebeesOrder = new string[] {
                                "Processing Status", "System Remarks",
                                "Code", "VendorCode", "Name", "VendorName", "Location", "LocationName", "FHRID", "FHRID", "AreaManager", "Hub code", "HubCode", 
                                "Sum of Total OFD", "Assigned_Volume", "OFD", 
                                "Sum of Total Delivered", "Delivered_Volume", "Delivered", 
                                "Conversion %", "Conversion_Percentage", 
                                "Applied BaseRate", "Applied_Rate", "Applied Rate", 
                                "Rate Type", "Rate_Type",
                                
                                "Delivery Payable", "Delivery_Payable", "Payable",
                                
                                "RTO Assign", "RTO_Assigned", "RTO Done", "RTO_Done", "RTO %", "RTO_Conversion_Percentage", "RTO Rate", "RTO_Applied_Rate", "RTO Rate Type", "RTO_Rate_Type", "RTO Payable", "RTO_Payable",
                                "DTO Assign", "DTO_Assigned", "DTO Done", "DTO_Done", "DTO %", "DTO_Conversion_Percentage", "DTO Rate", "DTO_Applied_Rate", "DTO Rate Type", "DTO_Rate_Type", "DTO Payable", "DTO_Payable",
                                "FM Assign", "FM_Assigned", "FM Done", "FM_Done", "FM %", "FM_Conversion_Percentage", "FM Rate", "FM_Applied_Rate", "FM Rate Type", "FM_Rate_Type", "FM Payable", "FM_Payable",
                                
                                "Pickup Assign", "Pickup_Assigned", "Pickup Done", "Pickup_Done", "Pickup %", "Pickup_Conversion_Percentage", "Pickup Rate", "Pickup_Applied_Rate", "Pickup Rate Type", "Pickup_Rate_Type", "Pickup Payable", "Pickup_Payable",
                                
                                "Base payable", "Base_Payable", "Base Payable",
                                
                                "Deduction", "Ded_Shipment", "COD Deduction", "Ded_COD", "Other Deduction", "Ded_Other", "Arrear", "Ded_Arrear", "Insurance", "Ded_Insurance", "SD", "Ded_SD", "Welfare Deduction", "Ded_Welfare", "Hold", "Ded_Hold", "Karma Life Deduction", "Ded_KarmaLife", "Rent Deduction", "Ded_Rent", "Advance Deduction", "Ded_Advance", "TNT Deduction", "Ded_TNT",
                                
                                "GST Percentage", "GST_Percentage", "GST Amount", "GST_Amount", "Total Payable After GST", "Total_Payable_After_GST", "TDS Percentage", "TDS_Percentage", "TDS Amount", "TDS_Amount", "Net Payable", "Net_Payable",
                                
                                "Bank Name", "Vendor_BankName", "Account No", "Vendor_AccountNo", "IFSC Code", "Vendor_IFSCCode", "PAN No", "Vendor_PanNo", "Aadhar No", "Vendor_AaddharNo", "Account Holder Name", "Vendor_AccountHolderName", "Date Range", "TransactionRange", "Uploaded By", "UploadedByName"
                            };
                    foreach (var k in ebeesOrder)
                    {
                        if (renamedRow.ContainsKey(k)) orderedRow[k] = renamedRow[k];
                    }
                    foreach (var kv in renamedRow)
                    {
                        if (!orderedRow.ContainsKey(kv.Key)) orderedRow[kv.Key] = kv.Value;
                    }
                }
                else
                {
                    var metaCols = new string[] { "Processing Status", "System Remarks" };
                    foreach (var m in metaCols) { if (renamedRow.ContainsKey(m)) orderedRow[m] = renamedRow[m]; }

                    foreach (var kv in renamedRow)
                    {
                        if (!orderedRow.ContainsKey(kv.Key)) orderedRow[kv.Key] = kv.Value;
                    }
                }
                renamedList.Add(orderedRow);



            }

            return Ok(new { success = true, totalCount, data = renamedList, formulas = formulaMap });
        }

        [HttpGet("TransactionList/Export")]
        public async Task<IActionResult> ExportTransactionList([FromQuery] int clientId, [FromQuery] int modelId, [FromQuery] string? locationId = null, [FromQuery] string? transactionRange = null, [FromQuery] string? vendorCode = null, [FromQuery] string? searchTerm = null)
        {
            var (_, list) = await _vendorRepository.GetVendorPaymentTransactionsListAsync(clientId, modelId, locationId, transactionRange, vendorCode, searchTerm, 1, 999999);

            var outputRenameMap = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            var formulaMap = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            var stdColToDisplayName = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            var templateConfigHeaderOrder = new List<string>();
            string finalClientName = "";
            string finalModelName = "";

            try
            {
                finalClientName = await _vendorRepository.GetClientNameAsync(clientId);
                finalModelName = await _vendorRepository.GetModelNameAsync(modelId);

                var configData = await _vendorRepository.GetVendorTemplateConfigAsync(clientId, modelId);
                foreach (var row in configData)
                {
                    var dict = (IDictionary<string, object>)row;
                    var stdCol = dict.ContainsKey("StandardDbColumn") ? Convert.ToString(dict["StandardDbColumn"]) ?? "" : "";
                    var excelHeader = dict.ContainsKey("ExcelHeaderName") ? Convert.ToString(dict["ExcelHeaderName"]) ?? "" : "";
                    var formula = dict.ContainsKey("FormulaDescription") ? Convert.ToString(dict["FormulaDescription"]) ?? "" : "";
                    stdColToDisplayName[stdCol] = excelHeader;
                    outputRenameMap[stdCol] = excelHeader;
                    if (!string.IsNullOrEmpty(excelHeader) && !templateConfigHeaderOrder.Contains(excelHeader)) templateConfigHeaderOrder.Add(excelHeader);
                    if (!string.IsNullOrEmpty(formula)) formulaMap[stdCol] = formula;
                }
            }
            catch { }

            var resolvedFormulaMap = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var kv in formulaMap)
            {
                var resolved = kv.Value;
                foreach (var stdKv in stdColToDisplayName)
                    resolved = resolved.Replace("{" + stdKv.Key + "}", "[" + stdKv.Value + "]");

                if (stdColToDisplayName.ContainsKey(kv.Key))
                {
                    resolvedFormulaMap[stdColToDisplayName[kv.Key]] = resolved;
                }
                else
                {
                    resolvedFormulaMap[kv.Key] = resolved;
                }
            }
            formulaMap = new Dictionary<string, string>(resolvedFormulaMap, StringComparer.OrdinalIgnoreCase);

            var renamedList = new List<Dictionary<string, object>>();
            foreach (var rawRow in list)
            {
                var rawDict = (IDictionary<string, object>)rawRow;
                var renamedRow = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);

                foreach (var kvp in rawDict)
                {
                    var internalExclude = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase) {
                        "TotalRows", "TotalRecords", "TransactionID", "UploadBatchID", "fk_cost_centre_id", "fk_model_id", "fk_rec_id",
                        "ClientID", "ModelID", "LocationID", "CreatedBy", "CreatedDate", "IsProcessed", "fk_File_Id", "FHRID",
                        "FromDate", "ToDate", "CycleName", "BudgetaryCode", "StateName", "Payment_Status", "Payment Status",
                        "HR_Remark", "HR Remark", "Central_Remark", "Central Remark"
                    };
                    if (internalExclude.Contains(kvp.Key)) continue;

                    bool isPickupEnabled = outputRenameMap.ContainsKey("Pickup_Assigned") || outputRenameMap.ContainsKey("pickup_assigned") || outputRenameMap.Values.Contains("Pickup Assign");
                    var ebeesCols = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase) { "Pickup_Assigned", "Pickup_Done", "Pickup_Conversion_Percentage", "Pickup_Applied_Rate", "Pickup_Rate_Type", "Delivery_Payable", "Pickup_Payable" };
                    if (ebeesCols.Contains(kvp.Key) && !isPickupEnabled) continue;
                    var dedCols = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase) { "Ded_Shipment", "Ded_COD", "Ded_Other", "Ded_Arrear", "Ded_Insurance", "Ded_SD", "Ded_Welfare", "Ded_Hold", "Ded_KarmaLife" };
                    if (dedCols.Contains(kvp.Key) && !outputRenameMap.ContainsKey(kvp.Key)) continue;
                    if (modelId != null && modelId.ToString() == "3" && kvp.Key.Equals("Assigned_Volume", StringComparison.OrdinalIgnoreCase)) continue;
                    var fmCols = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase) { "Total_Assigned_FM_RVP", "Total_Delivered_FM_RVP", "Assigned_RVP", "Delivered_RVP", "Vehicle_Type", "Working_Days" };
                    if (fmCols.Contains(kvp.Key) && !outputRenameMap.ContainsKey(kvp.Key)) continue;

                    string displayKey = kvp.Key;

                    if (outputRenameMap.ContainsKey(kvp.Key))
                    {
                        displayKey = outputRenameMap[kvp.Key];
                    }
                    else if (kvp.Key.Equals("VendorCode", StringComparison.OrdinalIgnoreCase)) displayKey = "Code";
                    else if (kvp.Key.Equals("VendorName", StringComparison.OrdinalIgnoreCase)) displayKey = "Name";
                    else if (kvp.Key.Equals("LocationName", StringComparison.OrdinalIgnoreCase)) displayKey = "Location";
                    else if (kvp.Key.Equals("FHRID", StringComparison.OrdinalIgnoreCase)) displayKey = "FHRID";
                    else if (kvp.Key.Equals("HubCode", StringComparison.OrdinalIgnoreCase)) displayKey = "Hub code";
                    else if (kvp.Key.Equals("Working_Days", StringComparison.OrdinalIgnoreCase)) displayKey = "No. of Days";
                    else if (kvp.Key.Equals("Processing_Status", StringComparison.OrdinalIgnoreCase)) displayKey = "Processing Status";
                    else if (kvp.Key.Equals("System_Remarks", StringComparison.OrdinalIgnoreCase)) displayKey = "System Remarks";
                    else if (kvp.Key.Equals("Assigned_Volume", StringComparison.OrdinalIgnoreCase)) displayKey = "Sum of Total OFD";
                    else if (kvp.Key.Equals("Delivered_Volume", StringComparison.OrdinalIgnoreCase)) displayKey = "Sum of Total Delivered";
                    else if (kvp.Key.Equals("Conversion_Percentage", StringComparison.OrdinalIgnoreCase)) displayKey = "Conversion %";
                    else if (kvp.Key.Equals("Applied_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "Applied BaseRate";
                    else if (kvp.Key.Equals("Rate_Type", StringComparison.OrdinalIgnoreCase)) displayKey = "Rate Type";
                    else if (kvp.Key.Equals("Base_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "Base payable";
                    else if (kvp.Key.Equals("GST_Percentage", StringComparison.OrdinalIgnoreCase)) displayKey = "GST Percentage";
                    else if (kvp.Key.Equals("GST_Amount", StringComparison.OrdinalIgnoreCase)) displayKey = "GST Amount";
                    else if (kvp.Key.Equals("Total_Payable_After_GST", StringComparison.OrdinalIgnoreCase)) displayKey = "Total Payable After GST";
                    else if (kvp.Key.Equals("TDS_Percentage", StringComparison.OrdinalIgnoreCase)) displayKey = "TDS Percentage";
                    else if (kvp.Key.Equals("TDS_Amount", StringComparison.OrdinalIgnoreCase)) displayKey = "TDS Amount";
                    else if (kvp.Key.Equals("Net_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "Net Payable";
                    else if (kvp.Key.Equals("Vendor_BankName", StringComparison.OrdinalIgnoreCase)) displayKey = "Bank Name";
                    else if (kvp.Key.Equals("Vendor_AccountNo", StringComparison.OrdinalIgnoreCase)) displayKey = "Account No";
                    else if (kvp.Key.Equals("Vendor_IFSCCode", StringComparison.OrdinalIgnoreCase)) displayKey = "IFSC Code";
                    else if (kvp.Key.Equals("Vendor_PanNo", StringComparison.OrdinalIgnoreCase)) displayKey = "PAN No";
                    else if (kvp.Key.Equals("Vendor_AaddharNo", StringComparison.OrdinalIgnoreCase)) displayKey = "Aadhar No";
                    else if (kvp.Key.Equals("Vendor_AccountHolderName", StringComparison.OrdinalIgnoreCase)) displayKey = "Account Holder Name";
                    else if (kvp.Key.Equals("TransactionRange", StringComparison.OrdinalIgnoreCase)) displayKey = "Date Range";
                    else if (kvp.Key.Equals("UploadedByName", StringComparison.OrdinalIgnoreCase)) displayKey = "Uploaded By";
                    else if (kvp.Key.Equals("Ded_Shipment", StringComparison.OrdinalIgnoreCase)) displayKey = "Deduction";
                    else if (kvp.Key.Equals("Ded_COD", StringComparison.OrdinalIgnoreCase)) displayKey = "COD Deduction";
                    else if (kvp.Key.Equals("Ded_Other", StringComparison.OrdinalIgnoreCase)) displayKey = "Other Deduction";
                    else if (kvp.Key.Equals("Ded_Arrear", StringComparison.OrdinalIgnoreCase)) displayKey = "Arrear";
                    else if (kvp.Key.Equals("Ded_Insurance", StringComparison.OrdinalIgnoreCase)) displayKey = "Insurance";
                    else if (kvp.Key.Equals("Ded_SD", StringComparison.OrdinalIgnoreCase)) displayKey = "SD";
                    else if (kvp.Key.Equals("Ded_Welfare", StringComparison.OrdinalIgnoreCase)) displayKey = "Welfare Deduction";
                    else if (kvp.Key.Equals("Ded_Hold", StringComparison.OrdinalIgnoreCase)) displayKey = "Hold";
                    else if (kvp.Key.Equals("Ded_KarmaLife", StringComparison.OrdinalIgnoreCase)) displayKey = "Karma Life Deduction";
                    else if (kvp.Key.Equals("Ded_Rent", StringComparison.OrdinalIgnoreCase)) displayKey = "Rent Deduction";
                    else if (kvp.Key.Equals("Ded_Advance", StringComparison.OrdinalIgnoreCase)) displayKey = "Advance Deduction";
                    else if (kvp.Key.Equals("Ded_TNT", StringComparison.OrdinalIgnoreCase)) displayKey = "TNT Deduction";
                    else if (kvp.Key.Equals("SR_LM_Return", StringComparison.OrdinalIgnoreCase)) displayKey = "SR LM Return";
                    else if (kvp.Key.Equals("SR_FM_Return", StringComparison.OrdinalIgnoreCase)) displayKey = "SR FM Return";
                    else if (kvp.Key.Equals("Assign_RVP_Normal", StringComparison.OrdinalIgnoreCase)) displayKey = "Assign RVP+Normal";
                    else if (kvp.Key.Equals("Total_Delivered_RVP_Shopsy", StringComparison.OrdinalIgnoreCase)) displayKey = "Total Delivered+RVP+Shopsy";
                    else if (kvp.Key.Equals("FWD_RVP_Del_Wo_SR", StringComparison.OrdinalIgnoreCase)) displayKey = "FWD+RVP Del-W/o SR";
                    else if (kvp.Key.Equals("Delivery_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "Payable";
                    else if (kvp.Key.Equals("U2S_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "U2S Rate";
                    else if (kvp.Key.Equals("U2S_Rate_Type", StringComparison.OrdinalIgnoreCase)) displayKey = "U2S Rate Type";
                    else if (kvp.Key.Equals("U2S_Applied_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "U2S Applied Rate";
                    else if (kvp.Key.Equals("U2S_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "U2S Payable";
                    else if (kvp.Key.Equals("Shopsy_RateDeduction", StringComparison.OrdinalIgnoreCase)) displayKey = "Shopsy RateDeduction";
                    else if (kvp.Key.Equals("Shopsy_RateType", StringComparison.OrdinalIgnoreCase)) displayKey = "Shopsy Rate Type";
                    else if (kvp.Key.Equals("Shopsy_Applied_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "Shopsy RateApplied";
                    else if (kvp.Key.Equals("Shopsy_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "Shopsy Payable";
                    else if (kvp.Key.Equals("Prexo_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "Prexo Rate";
                    else if (kvp.Key.Equals("Prexo_Rate_Type", StringComparison.OrdinalIgnoreCase)) displayKey = "Prexo Rate Type";
                    else if (kvp.Key.Equals("Prexo_Applied_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "Prexo Applied Rate";
                    else if (kvp.Key.Equals("Prexo_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "Prexo Payable";
                    else if (kvp.Key.Equals("Grocery_Assigned", StringComparison.OrdinalIgnoreCase)) displayKey = "Grocery Assigned";
                    else if (kvp.Key.Equals("Grocery_Delivered", StringComparison.OrdinalIgnoreCase)) displayKey = "Grocery Delivered";
                    else if (kvp.Key.Equals("Grocery_Conversion_Percentage", StringComparison.OrdinalIgnoreCase)) displayKey = "Grocery Conversion %";
                    else if (kvp.Key.Equals("Grocery_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "Grocery Rate";
                    else if (kvp.Key.Equals("Grocery_Rate_Type", StringComparison.OrdinalIgnoreCase)) displayKey = "Grocery Rate Type";
                    else if (kvp.Key.Equals("Grocery_Applied_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "Grocery Applied Rate";
                    else if (kvp.Key.Equals("Grocery_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "Grocery Payable";
                    else if (kvp.Key.Equals("Pickup_Conversion_Percentage", StringComparison.OrdinalIgnoreCase)) displayKey = "Pickup %";
                    else if (kvp.Key.Equals("Pickup_Applied_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "Pickup Rate";
                    else if (kvp.Key.Equals("Pickup_Rate_Type", StringComparison.OrdinalIgnoreCase)) displayKey = "Pickup Rate Type";
                    else if (kvp.Key.Equals("Pickup_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "Pickup Payable";
                    else if (kvp.Key.Equals("Total_Assigned_FM_RVP", StringComparison.OrdinalIgnoreCase)) displayKey = "Total Assigne FM+RVP";
                    else if (kvp.Key.Equals("Route", StringComparison.OrdinalIgnoreCase)) displayKey = "Route";
                    else if (kvp.Key.Equals("MFN_Assigned", StringComparison.OrdinalIgnoreCase)) displayKey = "MFN Assign";
                    else if (kvp.Key.Equals("MFN_Done", StringComparison.OrdinalIgnoreCase)) displayKey = "MFN Done";
                    else if (kvp.Key.Equals("MFN_Conversion_Percentage", StringComparison.OrdinalIgnoreCase)) displayKey = "MFN Conversion %";
                    else if (kvp.Key.Equals("MFN_Rate_Type", StringComparison.OrdinalIgnoreCase)) displayKey = "MFN RateType";
                    else if (kvp.Key.Equals("MFN_Applied_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "MFN AppliedRate";
                    else if (kvp.Key.Equals("MFN_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "MFN Payable";
                    else if (kvp.Key.Equals("Van_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "Van Rate";
                    else if (kvp.Key.Equals("Van_Rate_Type", StringComparison.OrdinalIgnoreCase)) displayKey = "Van RateType";
                    else if (kvp.Key.Equals("Van_Applied_Rate", StringComparison.OrdinalIgnoreCase)) displayKey = "VAN AppliedRate";
                    else if (kvp.Key.Equals("PresentDays", StringComparison.OrdinalIgnoreCase)) displayKey = "PresentDays";
                    else if (kvp.Key.Equals("Van_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "VAN Payable";
                    else if (kvp.Key.Equals("PresentDaysPayableRate", StringComparison.OrdinalIgnoreCase)) displayKey = "PresentDaysPayableRate";
                    else if (kvp.Key.Equals("PresentDaysPayable", StringComparison.OrdinalIgnoreCase)) displayKey = "PresentDaysPayable";
                    else if (kvp.Key.Equals("Special_Charge", StringComparison.OrdinalIgnoreCase)) displayKey = "SC";
                    else if (kvp.Key.Equals("Total_Payable", StringComparison.OrdinalIgnoreCase)) displayKey = "totalPayable";

                    // HIDE irrelevant columns for ODH-MDH (ModelId = 1)
                    if (modelId.ToString() == "1")
                    {
                        var odhHideCols = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase) {
                            "Assigned_Volume", "Delivered_Volume", "Sum of Total OFD", "Sum of Total Delivered",
                            "Total_Assigned_FM_RVP", "Total_Delivered_FM_RVP", "Assigned_RVP", "Delivered_RVP",
                            "Pickup_Assigned", "Pickup_Done", "Pickup_Conversion_Percentage", "Pickup_Applied_Rate",
                            "Pickup_Rate_Type", "Delivery_Payable", "Pickup_Payable", "Ded_Insurance", "Insurance",
                            "Vehicle_Type", "Shopsy_Rate_Type"
                        };
                        if (odhHideCols.Contains(kvp.Key) || odhHideCols.Contains(displayKey)) continue;
                    }

                    // HIDE ODH-MDH specific columns for ALL OTHER models
                    if (modelId.ToString() != "1")
                    {
                        var nonOdhHideCols = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase) {
                            "SR_LM_Return", "SR LM Return", "SR_FM_Return", "SR FM Return",
                            "Assign_RVP_Normal", "Assign RVP+Normal", "Total_Delivered_RVP_Shopsy", "Total Delivered+RVP+Shopsy",
                            "FWD_RVP_Del_Wo_SR", "FWD+RVP Del-W/o SR",
                            "U2S", "U2S_Rate", "U2S Rate", "U2S_Rate_Type", "U2S Rate Type", "U2S_Applied_Rate", "U2S Applied Rate", "U2S_Payable", "U2S Payable",
                            "Shopsy", "Shopsy_RateDeduction", "Shopsy RateDeduction", "Shopsy_RateType", "Shopsy_Rate_Type", "Shopsy Rate Type", "Shopsy_Applied_Rate", "Shopsy RateApplied", "Shopsy_Payable", "Shopsy Payable",
                            "Prexo", "Prexo_Rate", "Prexo Rate", "Prexo_Rate_Type", "Prexo Rate Type", "Prexo_Applied_Rate", "Prexo Applied Rate", "Prexo_Payable", "Prexo Payable",
                            "Grocery_Assigned", "Grocery Assigned", "Grocery_Delivered", "Grocery Delivered",
                            "Grocery_Conversion_Percentage", "Grocery Conversion %", "Grocery_Rate", "Grocery Rate",
                            "Grocery_Rate_Type", "Grocery Rate Type", "Grocery_Applied_Rate", "Grocery Applied Rate", "Grocery_Payable", "Grocery Payable",
                            "Ded_Rent", "Rent Deduction", "Ded_Advance", "Advance Deduction", "Ded_TNT", "TNT Deduction"
                        };
                        if (modelId.ToString() == "4")
                        {
                            nonOdhHideCols.Remove("Ded_Advance");
                            nonOdhHideCols.Remove("Advance Deduction");
                        }
                        if (nonOdhHideCols.Contains(kvp.Key) || nonOdhHideCols.Contains(displayKey)) continue;
                    }

                    // HIDE Amazon DSP / EDSP specific columns for other models (not model 4 or 5)
                    if (modelId.ToString() != "4" && modelId.ToString() != "5")
                    {
                        var dspHideCols = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase) {
                            "Route", "MFN_Assigned", "MFN Assign", "MFN_Done", "MFN Done", "MFN  Done",
                            "MFN_Conversion_Percentage", "MFN Conversion %",
                            "MFN_Rate_Type", "MFN RateType", "MFN Rate Type", "MFN_Applied_Rate", "MFN AppliedRate", "MFN Applied Rate", "MFN_Payable", "MFN Payable",
                            "Van_Rate", "Van Rate", "Van_Rate_Type", "Van RateType", "Van Rate Type", "Van_Applied_Rate", "VAN AppliedRate", "Van Applied Rate", "Van_Payable", "VAN Payable",
                            "PresentDays", "PresentDaysPayableRate", "PresentDaysPayable",
                            "Special_Charge", "SC", "Total_Payable", "totalPayable"
                        };
                        if (dspHideCols.Contains(kvp.Key) || dspHideCols.Contains(displayKey)) continue;
                    }

                    // HIDE DSP-only columns for EDSP (Model 5)
                    if (modelId.ToString() == "5")
                    {
                        var edspHideCols = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase) {
                            "Route", "Van_Rate", "Van Rate", "Van_Rate_Type", "Van RateType", "Van Rate Type", "Van_Applied_Rate", "VAN AppliedRate", "Van Applied Rate", "Van_Payable", "VAN Payable",
                            "PresentDays", "PresentDaysPayableRate", "PresentDaysPayable",
                            "Special_Charge", "SC", "Ded_Advance", "Advance Deduction",
                            "Assigned_RVP", "Delivered_RVP", "Total_Assigned_FM_RVP", "Total_Delivered_FM_RVP", "Total Assigne FM+RVP", "Total Delivered FM+RVP",
                            "Ded_Rent", "Rent Deduction", "Ded_TNT", "TNT Deduction",
                            "Ded_Insurance", "Insurance", "Ded_SD", "SD",
                            "Working_Days", "No. of Days", "Delivery_Payable", "Payable"
                        };
                        if (edspHideCols.Contains(kvp.Key) || edspHideCols.Contains(displayKey)) continue;
                    }

                    // HIDE irrelevant columns for Amazon DSP (Model 4)
                    if (modelId.ToString() == "4")
                    {
                        var dspSpecificHide = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase) {
                            "Assigned_RVP", "Delivered_RVP", "Total_Assigned_FM_RVP", "Total_Delivered_FM_RVP", "Total Assigne FM+RVP", "Total Delivered FM+RVP",
                            "Ded_Rent", "Rent Deduction", "Ded_TNT", "TNT Deduction",
                            "Ded_Insurance", "Insurance", "Ded_SD", "SD",
                            "Working_Days", "No. of Days", "Delivery_Payable", "Payable"
                        };
                        if (dspSpecificHide.Contains(kvp.Key) || dspSpecificHide.Contains(displayKey)) continue;
                    }

                    renamedRow[displayKey] = kvp.Value;
                }

                var orderedRow = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);
                if (modelId.ToString() == "1")
                {
                    var prefOrder = new string[] {
                                "Processing Status", "System Remarks",
                                "Code", "Name", "Location", "FHRID", "AreaManager", "Hub code", "No. of Days",
                                "SR LM Return", "SR FM Return", "Assign RVP+Normal", "Total Delivered+RVP+Shopsy", "FWD+RVP Del-W/o SR", "Conversion %",
                                "Rate Type", "Applied BaseRate", "Payable",
                                "U2S", "U2S Rate", "U2S Rate Type", "U2S Applied Rate", "U2S Payable",
                                "Shopsy", "Shopsy Rate Type", "Shopsy RateDeduction", "Shopsy RateApplied", "Shopsy Payable",
                                "Prexo", "Prexo Rate", "Prexo Rate Type", "Prexo Applied Rate", "Prexo Payable",
                                "Grocery Assigned", "Grocery Delivered", "Grocery Conversion %", "Grocery Rate", "Grocery Rate Type", "Grocery Applied Rate", "Grocery Payable",
                                "Base payable", "Shipment Deduction", "COD Deduction", "Other Deduction", "Rent Deduction", "Advance Deduction", "Hold", "Karma Life Deduction", "Arrear", "SD", "TNT Deduction", "Welfare Deduction",
                                "GST Percentage", "GST Amount", "Total Payable After GST", "TDS Percentage", "TDS Amount", "Net Payable",
                                "Bank Name", "Account No", "IFSC Code", "PAN No", "Aadhar No", "Account Holder Name", "Date Range", "Uploaded By"
                            };
                    foreach (var k in prefOrder)
                    {
                        if (renamedRow.ContainsKey(k)) orderedRow[k] = renamedRow[k];
                    }
                    foreach (var kv in renamedRow)
                    {
                        if (!orderedRow.ContainsKey(kv.Key)) orderedRow[kv.Key] = kv.Value;
                    }
                }
                else if (modelId.ToString() == "4")
                {
                    var dspOrder = new string[] {
                                "Code", "Name", "Location", "FHRID", "AreaManager", "Hub code", "Route", "Vehicle Type",
                                "Total OFD", "Total Delivered", "Conversion %", "Applied_Rate", "Rate_Type", "Base Payable",
                                "Pickup Assign", "Pickup Done", "Pickup Conversion%", "Pickup RateType", "Pickup AppliedRate", "Pickup Payable",
                                "MFN Assign", "MFN Done", "MFN Conversion %", "MFN RateType", "MFN AppliedRate", "MFN Payable",
                                "Van Rate", "Van RateType", "VAN AppliedRate", "PresentDays", "VAN Payable",
                                "PresentDaysPayableRate", "PresentDaysPayable", "SC", "totalPayable",
                                "gst%", "GstAmount", "TotalPayableAfterGST", "TDS%", "TDSAmount",
                                "Shipment Deduction", "COD Deduction", "Other Deduction", "Arrear", "Hold", "Karmalife Deduction", "Welfare Deduction", "Advance Deduction", "net payable",
                                "Bank Name", "Account No", "IFSC Code", "PAN No", "Aadhar No", "Account Holder Name", "Date Range", "Uploaded By"
                            };
                    foreach (var k in dspOrder)
                    {
                        if (renamedRow.ContainsKey(k)) orderedRow[k] = renamedRow[k];
                    }
                }
                else if (modelId.ToString() == "5")
                {
                    var edspOrder = new string[] {
                                "Code", "Name", "Location", "FHRID", "AreaManager", "Hub code", "Vehicle Type",
                                "Total OFD", "Total Delivered", "Conversion %", "Applied_Rate", "Rate_Type", "Base Payable",
                                "Pickup Assign", "Pickup Done", "Pickup Conversion%", "Pickup RateType", "Pickup AppliedRate", "Pickup Payable",
                                "MFN Assign", "MFN Done", "MFN Conversion %", "MFN RateType", "MFN AppliedRate", "MFN Payable",
                                "totalPayable",
                                "gst%", "GstAmount", "TotalPayableAfterGST", "TDS%", "TDSAmount",
                                "Shipment Deduction", "COD Deduction", "Other Deduction", "Arrear", "Hold", "Karmalife Deduction", "Welfare Deduction", "net payable",
                                "Bank Name", "Account No", "IFSC Code", "PAN No", "Aadhar No", "Account Holder Name", "Date Range", "Uploaded By"
                            };
                    foreach (var k in edspOrder)
                    {
                        if (renamedRow.ContainsKey(k)) orderedRow[k] = renamedRow[k];
                    }
                }
                else if (modelId.ToString() == "7")
                {
                    var ebeesOrder = new string[] {
                                "Processing Status", "System Remarks",
                                "Code", "VendorCode", "Name", "VendorName", "Location", "LocationName", "FHRID", "FHRID", "AreaManager", "Hub code", "HubCode", 
                                "Sum of Total OFD", "Assigned_Volume", "OFD", 
                                "Sum of Total Delivered", "Delivered_Volume", "Delivered", 
                                "Conversion %", "Conversion_Percentage", 
                                "Applied BaseRate", "Applied_Rate", "Applied Rate", 
                                "Rate Type", "Rate_Type",
                                
                                "Delivery Payable", "Delivery_Payable", "Payable",
                                
                                "RTO Assign", "RTO_Assigned", "RTO Done", "RTO_Done", "RTO %", "RTO_Conversion_Percentage", "RTO Rate", "RTO_Applied_Rate", "RTO Rate Type", "RTO_Rate_Type", "RTO Payable", "RTO_Payable",
                                "DTO Assign", "DTO_Assigned", "DTO Done", "DTO_Done", "DTO %", "DTO_Conversion_Percentage", "DTO Rate", "DTO_Applied_Rate", "DTO Rate Type", "DTO_Rate_Type", "DTO Payable", "DTO_Payable",
                                "FM Assign", "FM_Assigned", "FM Done", "FM_Done", "FM %", "FM_Conversion_Percentage", "FM Rate", "FM_Applied_Rate", "FM Rate Type", "FM_Rate_Type", "FM Payable", "FM_Payable",
                                
                                "Pickup Assign", "Pickup_Assigned", "Pickup Done", "Pickup_Done", "Pickup %", "Pickup_Conversion_Percentage", "Pickup Rate", "Pickup_Applied_Rate", "Pickup Rate Type", "Pickup_Rate_Type", "Pickup Payable", "Pickup_Payable",
                                
                                "Base payable", "Base_Payable", "Base Payable",
                                
                                "Deduction", "Ded_Shipment", "COD Deduction", "Ded_COD", "Other Deduction", "Ded_Other", "Arrear", "Ded_Arrear", "Insurance", "Ded_Insurance", "SD", "Ded_SD", "Welfare Deduction", "Ded_Welfare", "Hold", "Ded_Hold", "Karma Life Deduction", "Ded_KarmaLife", "Rent Deduction", "Ded_Rent", "Advance Deduction", "Ded_Advance", "TNT Deduction", "Ded_TNT",
                                
                                "GST Percentage", "GST_Percentage", "GST Amount", "GST_Amount", "Total Payable After GST", "Total_Payable_After_GST", "TDS Percentage", "TDS_Percentage", "TDS Amount", "TDS_Amount", "Net Payable", "Net_Payable",
                                
                                "Bank Name", "Vendor_BankName", "Account No", "Vendor_AccountNo", "IFSC Code", "Vendor_IFSCCode", "PAN No", "Vendor_PanNo", "Aadhar No", "Vendor_AaddharNo", "Account Holder Name", "Vendor_AccountHolderName", "Date Range", "TransactionRange", "Uploaded By", "UploadedByName"
                            };
                    foreach (var k in ebeesOrder)
                    {
                        if (renamedRow.ContainsKey(k)) orderedRow[k] = renamedRow[k];
                    }
                    foreach (var kv in renamedRow)
                    {
                        if (!orderedRow.ContainsKey(kv.Key)) orderedRow[kv.Key] = kv.Value;
                    }
                }
                else
                {
                    var metaCols = new string[] { "Processing Status", "System Remarks" };
                    foreach (var m in metaCols) { if (renamedRow.ContainsKey(m)) orderedRow[m] = renamedRow[m]; }

                    foreach (var kv in renamedRow)
                    {
                        if (!orderedRow.ContainsKey(kv.Key)) orderedRow[kv.Key] = kv.Value;
                    }
                }
                renamedList.Add(orderedRow);


            }

            using (var wb = new ClosedXML.Excel.XLWorkbook())
            {
                var summaryWs = wb.Worksheets.Add("Transaction List");
                int totalCount = renamedList.Count;

                summaryWs.Cell(1, 1).Value = "Client:";
                summaryWs.Cell(1, 1).Style.Font.Bold = true;
                summaryWs.Cell(1, 2).Value = finalClientName;
                summaryWs.Cell(1, 2).Style.Font.Bold = true;
                summaryWs.Cell(1, 2).Style.Font.FontColor = ClosedXML.Excel.XLColor.FromArgb(13, 110, 253);
                summaryWs.Cell(1, 4).Value = "Model:";
                summaryWs.Cell(1, 4).Style.Font.Bold = true;
                summaryWs.Cell(1, 5).Value = finalModelName;
                summaryWs.Cell(1, 5).Style.Font.Bold = true;
                summaryWs.Cell(1, 5).Style.Font.FontColor = ClosedXML.Excel.XLColor.FromArgb(13, 110, 253);

                int summaryHeaderRow = 3;
                summaryWs.Cell(summaryHeaderRow, 1).Value = "Sr. No";
                summaryWs.Cell(summaryHeaderRow, 1).Style.Font.Bold = true;
                summaryWs.Cell(summaryHeaderRow, 1).Style.Fill.BackgroundColor = ClosedXML.Excel.XLColor.FromArgb(52, 58, 64);
                summaryWs.Cell(summaryHeaderRow, 1).Style.Font.FontColor = ClosedXML.Excel.XLColor.White;

                if (renamedList.Any())
                {
                    var excludeKeys = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "TotalRows", "TransactionID", "UploadBatchID", "fk_cost_centre_id", "fk_model_id", "fk_rec_id", "ClientID", "ModelID", "LocationID", "CreatedBy", "CreatedDate", "IsProcessed", "fk_File_Id", "FHRID", "FromDate", "ToDate", "CycleName", "BudgetaryCode", "StateName", "Payment_Status", "HR_Remark", "Central_Remark" };
                    var keys = renamedList.First().Keys.Where(k => !excludeKeys.Contains(k)).ToList();

                    for (int c = 0; c < keys.Count; c++)
                    {
                        var cell = summaryWs.Cell(summaryHeaderRow, c + 2);
                        cell.Value = keys[c];
                        cell.Style.Font.Bold = true;
                        cell.Style.Fill.BackgroundColor = ClosedXML.Excel.XLColor.FromArgb(52, 58, 64);
                        cell.Style.Font.FontColor = ClosedXML.Excel.XLColor.White;
                    }

                    int formulaRow = summaryHeaderRow + 1;
                    summaryWs.Cell(formulaRow, 1).Value = "Formula:";
                    summaryWs.Cell(formulaRow, 1).Style.Font.Italic = true;
                    summaryWs.Cell(formulaRow, 1).Style.Font.FontColor = ClosedXML.Excel.XLColor.Gray;
                    for (int c = 0; c < keys.Count; c++)
                    {
                        if (formulaMap.ContainsKey(keys[c]))
                        {
                            var fCell = summaryWs.Cell(formulaRow, c + 2);
                            fCell.Value = formulaMap[keys[c]];
                            fCell.Style.Font.Italic = true;
                            fCell.Style.Font.FontColor = ClosedXML.Excel.XLColor.Gray;
                            fCell.Style.Fill.BackgroundColor = ClosedXML.Excel.XLColor.FromArgb(242, 242, 242);
                        }
                    }

                    int currRow = formulaRow + 1;
                    for (int r = 0; r < renamedList.Count; r++)
                    {
                        summaryWs.Cell(currRow, 1).Value = r + 1;
                        var rowDict = renamedList[r];
                        for (int c = 0; c < keys.Count; c++)
                        {
                            var val = rowDict.ContainsKey(keys[c]) ? rowDict[keys[c]]?.ToString() ?? "" : "";
                            summaryWs.Cell(currRow, c + 2).Value = val;
                        }
                        currRow++;
                    }
                    summaryWs.Columns().AdjustToContents();
                }

                using (var stream = new MemoryStream())
                {
                    wb.SaveAs(stream);
                    var outputContent = stream.ToArray();
                    return File(outputContent, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", $"Transaction_List_{DateTime.Now:yyyyMMdd_HHmmss}.xlsx");
                }
            }
        }

        [HttpGet("TransactionRanges")]
        public async Task<IActionResult> GetTransactionRanges([FromQuery] int clientId, [FromQuery] int modelId)
        {
            var ranges = await _vendorRepository.GetVendorTransactionRangesAsync(clientId, modelId);
            return Ok(new { success = true, data = ranges });
        }

        [HttpGet("TransactionTemplateData")]
        public async Task<IActionResult> GetTransactionTemplateData([FromQuery] int clientId, [FromQuery] int modelId)
        {
            var data = await _vendorRepository.GetTransactionTemplateDataAsync(clientId, modelId);
            return Ok(new { success = true, data });
        }

        [HttpGet("DownloadTransactionTemplate")]
        public async Task<IActionResult> DownloadTransactionTemplate([FromQuery] int clientId, [FromQuery] int modelId)
        {
            try
            {
                string clientName = await _vendorRepository.GetClientNameAsync(clientId) ?? "";
                string modelName = await _vendorRepository.GetModelNameAsync(modelId) ?? "";
                var vendorsData = await _vendorRepository.GetTransactionTemplateDataAsync(clientId, modelId);
                var vendorsList = vendorsData?.ToList() ?? new List<dynamic>();

                List<string> headers = GetExpectedTemplateHeaders(clientName, modelName);

                using (var wb = new ClosedXML.Excel.XLWorkbook())
                {
                    var ws = wb.Worksheets.Add("TransactionTemplate");

                    // 1. Write and Style Header Row (Row 1)
                    for (int col = 0; col < headers.Count; col++)
                    {
                        var cell = ws.Cell(1, col + 1);
                        cell.Value = headers[col];
                        cell.Style.Font.Bold = true;
                        cell.Style.Font.FontSize = 11;
                        cell.Style.Font.FontColor = ClosedXML.Excel.XLColor.White;
                        cell.Style.Fill.BackgroundColor = ClosedXML.Excel.XLColor.FromArgb(13, 110, 253); // #0D6EFD
                        cell.Style.Alignment.Horizontal = ClosedXML.Excel.XLAlignmentHorizontalValues.Center;
                        cell.Style.Alignment.Vertical = ClosedXML.Excel.XLAlignmentVerticalValues.Center;
                    }

                    int vehicleTypeColIdx = headers.IndexOf("Vehicle Type"); // 0-based
                    int routeColIdx = headers.IndexOf("Route"); // 0-based

                    int currentRow = 2;

                    if (vendorsList.Any())
                    {
                        for (int i = 0; i < vendorsList.Count; i++)
                        {
                            var v = vendorsList[i];
                            string vCode = "";
                            string vName = "";
                            string vLoc = "";
                            string vFhrid = "";
                            string vAreaManager = "";
                            string vHubCode = "";

                            if (v is IDictionary<string, object> dict)
                            {
                                vCode = dict.ContainsKey("vendorCode") ? dict["vendorCode"]?.ToString() ?? "" : (dict.ContainsKey("VendorCode") ? dict["VendorCode"]?.ToString() ?? "" : "");
                                vName = dict.ContainsKey("vendorName") ? dict["vendorName"]?.ToString() ?? "" : (dict.ContainsKey("VendorName") ? dict["VendorName"]?.ToString() ?? "" : "");
                                vLoc = dict.ContainsKey("locationName") ? dict["locationName"]?.ToString() ?? "" : (dict.ContainsKey("LocationName") ? dict["LocationName"]?.ToString() ?? "" : "");
                                vFhrid = dict.ContainsKey("FHRID") ? dict["FHRID"]?.ToString() ?? "" : "";
                                vAreaManager = dict.ContainsKey("AreaManager") ? dict["AreaManager"]?.ToString() ?? "" : "";
                                vHubCode = dict.ContainsKey("HubCode") ? dict["HubCode"]?.ToString() ?? "" : "";
                            }
                            else
                            {
                                try { vCode = v.vendorCode?.ToString() ?? v.VendorCode?.ToString() ?? ""; } catch { }
                                try { vName = v.vendorName?.ToString() ?? v.VendorName?.ToString() ?? ""; } catch { }
                                try { vLoc = v.locationName?.ToString() ?? v.LocationName?.ToString() ?? ""; } catch { }
                                try { vFhrid = v.FHRID?.ToString() ?? ""; } catch { }
                                try { vAreaManager = v.AreaManager?.ToString() ?? ""; } catch { }
                                try { vHubCode = v.HubCode?.ToString() ?? ""; } catch { }
                            }

                            ws.Cell(currentRow, 1).Value = vCode;
                            ws.Cell(currentRow, 2).Value = vName;
                            ws.Cell(currentRow, 3).Value = vLoc;
                            ws.Cell(currentRow, 4).Value = vFhrid;
                            ws.Cell(currentRow, 5).Value = vAreaManager;
                            ws.Cell(currentRow, 6).Value = vHubCode;

                            for (int c = 6; c < headers.Count; c++)
                            {
                                if (c == vehicleTypeColIdx)
                                {
                                    ws.Cell(currentRow, c + 1).Value = (i % 2 == 0) ? "VAN" : "Bike";
                                }
                                else if (c == routeColIdx)
                                {
                                    ws.Cell(currentRow, c + 1).Value = "";
                                }
                                else
                                {
                                    ws.Cell(currentRow, c + 1).Value = "0";
                                }
                            }
                            currentRow++;
                        }
                    }
                    else
                    {
                        // Fallback: 2 sample rows if no vendors exist
                        for (int r = 0; r < 2; r++)
                        {
                            ws.Cell(currentRow, 1).Value = "";
                            ws.Cell(currentRow, 2).Value = "";
                            ws.Cell(currentRow, 3).Value = "";
                            ws.Cell(currentRow, 4).Value = "";
                            ws.Cell(currentRow, 5).Value = "";
                            ws.Cell(currentRow, 6).Value = "";

                            for (int c = 6; c < headers.Count; c++)
                            {
                                if (c == vehicleTypeColIdx)
                                {
                                    ws.Cell(currentRow, c + 1).Value = (r == 0) ? "VAN" : "Bike";
                                }
                                else if (c == routeColIdx)
                                {
                                    ws.Cell(currentRow, c + 1).Value = "";
                                }
                                else
                                {
                                    ws.Cell(currentRow, c + 1).Value = "0";
                                }
                            }
                            currentRow++;
                        }
                    }

                    ws.Columns().AdjustToContents();

                    string cleanClientName = System.Text.RegularExpressions.Regex.Replace(clientName, @"[^a-zA-Z0-9_\-]", "_");
                    string cleanModelName = System.Text.RegularExpressions.Regex.Replace(modelName, @"[^a-zA-Z0-9_\-]", "_");
                    string fileDate = DateTime.Now.ToString("dd_MM_yyyy");
                    string fileName = $"Transaction_Upload_Template_{cleanClientName}_{cleanModelName}_{fileDate}.xlsx";

                    using (var stream = new System.IO.MemoryStream())
                    {
                        wb.SaveAs(stream);
                        return File(stream.ToArray(), "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", fileName);
                    }
                }
            }
            catch (Exception ex)
            {
                return BadRequest(new { success = false, message = "Failed to generate template: " + ex.Message });
            }
        }

        private static List<string> GetExpectedTemplateHeaders(string clientInput, string modelInput)
        {
            string clientName = (clientInput ?? "").ToLower().Trim();
            string modelName = (modelInput ?? "").ToLower().Trim();

            // 1. Flipkart ODH-MDH
            if (clientName.Contains("flipkart") && modelName.Contains("odh-mdh"))
            {
                return new List<string>
                {
                    "Code", "Name", "Location", "FHRID", "AreaManager", "Hub code",
                    "No. of Days", "SR LM Return", "SR FM Return", "Assign RVP+Normal",
                    "Total Delivered+RVP+Shopsy", "U2S", "Shopsy", "Prexo",
                    "Grocery Assigned", "Grocery Delivered", "Shipment Deduction",
                    "COD Deduction", "Other Deduction", "Rent Deduction", "Advance Deduction",
                    "Hold", "Karma Life Deduction", "Arrear", "SD", "TNT Deduction", "Welfare Deduction"
                };
            }

            // 2. Amazon DSP
            if (clientName.Contains("amazon") && modelName.Contains("dsp") && !modelName.Contains("edsp"))
            {
                return new List<string>
                {
                    "Code", "Name", "Location", "FHRID", "AreaManager", "Hub code", "Route", "Vehicle Type",
                    "Total OFD", "Total Delivered", "Pickup Assign", "Pickup Done",
                    "MFN Assign", "MFN Done", "PresentDays", "SC",
                    "Shipment Deduction", "COD Deduction", "Other Deduction", "Arrear",
                    "Hold", "Karmalife Deduction", "Welfare Deduction", "Advance Deduction"
                };
            }

            // 3. Amazon EDSP
            if (clientName.Contains("amazon") && modelName.Contains("edsp"))
            {
                return new List<string>
                {
                    "Code", "Name", "Location", "FHRID", "AreaManager", "Hub code", "Vehicle Type",
                    "Total OFD", "Total Delivered", "Pickup Assign", "Pickup Done",
                    "MFN Assign", "MFN Done",
                    "Shipment Deduction", "COD Deduction", "Other Deduction", "Arrear",
                    "Hold", "Karmalife Deduction", "Welfare Deduction"
                };
            }

            // 4. BlueDart Variable
            if (clientName.Contains("bluedart") && (modelName.Contains("variable") || modelName.Contains("b")))
            {
                return new List<string>
                {
                    "Code", "Name", "Location", "FHRID", "AreaManager", "Hub code",
                    "Total Assigned", "Total Delivered", "Shipment Deduction",
                    "COD Deduction", "Other Deduction", "Hold", "Arrear Amt", "SD"
                };
            }

            // 5. Ebees / Xbees
            if (clientName.Contains("ebees") || clientName.Contains("xbees"))
            {
                return new List<string>
                {
                    "Code", "Name", "Location", "FHRID", "AreaManager", "Hub code",
                    "OFD", "Delivered", "Pickup Assign", "Pickup Done",
                    "RTO Assign", "RTO Done",   // NEW
                    "DTO Assign", "DTO Done",   // NEW
                    "FM Assign",  "FM Done",    // NEW
                    "Deduction", "COD Deduction", "Other Deduction"
                };
            }

            // 6. Airtel FSE
            if (clientName.Contains("airtel") && modelName.Contains("fse"))
            {
                return new List<string>
                {
                    "Code", "Name", "Location", "FHRID", "AreaManager", "Hub code",
                    "Over System Pickup Count", "FSE System Pickup Count",
                    "Deduction", "COD Deduction", "Other Deduction", "Arrear Amt",
                    "Insurance", "SD", "Welfare"
                };
            }

            // 7. Flipkart FM
            if (clientName.Contains("flipkart") && (modelName.Contains("fm") || modelName.Contains("variable")))
            {
                return new List<string>
                {
                    "Code", "Name", "Location", "FHRID", "AreaManager", "Hub code",
                    "Assigned FM", "Delivered FM", "Assigned RVP", "Delivered RVP",
                    "Shipment Deduction", "COD Deduction", "Other Deduction", "Arrear", "Hold"
                };
            }

            // 8. Flipkart XRM
            if (clientName.Contains("flipkart") && modelName.Contains("xrm"))
            {
                return new List<string>
                {
                    "Code", "Name", "Location", "FHRID", "AreaManager", "Hub code",
                    "Total OFD", "Total Delivered", "Pickup Assign", "Pickup Done",
                    "Deduction", "COD Deduction", "Other Deduction", "Arrear Amt",
                    "Insurance", "Hold", "Karma Life", "Welfare Deduction"
                };
            }

            // 9. Flipkart Large
            if (clientName.Contains("flipkart") && modelName.Contains("large"))
            {
                return new List<string>
                {
                    "Code", "Name", "Location", "FHRID", "AreaManager", "Hub code",
                    "Vehicle Type", "Working Days", "Delivered Count", "Shipment Deduction",
                    "COD Deduction", "Other Deduction", "Arrear", "Hold",
                    "KarmaLife Deduction", "Welfare Deduction"
                };
            }

            // 10. Default / Fallback
            return new List<string>
            {
                "Code", "Name", "Location", "FHRID", "AreaManager", "Hub code",
                "Sum of Total OFD", "Sum of Total Delivered",
                "Shipment Deduction", "COD Deduction", "Other Deduction",
                "Arrear Amt", "Insurance", "SD", "Welfare"
            };
        }

        [HttpGet("SearchVendors")]
        public async Task<IActionResult> SearchVendors([FromQuery] string searchTerm)
        {
            var vendors = await _vendorRepository.SearchVendorsAsync(searchTerm);
            return Ok(new { success = true, data = vendors });
        }

        //added code 31 aug 2026 starts
        [HttpPost("UploadVendorFHRIDMappingExcel")]
        [Authorize]
        [Consumes("multipart/form-data")]
        public async Task<IActionResult> UploadVendorFHRIDMappingExcel([FromForm] UploadVendorFHRIDMappingRequest request)
        {
            ModelResponse modelResponse = new ModelResponse();
            try
            {
                var file = request?.file;
                if (file == null || file.Length == 0)
                {
                    modelResponse.IsSuccess = false;
                    modelResponse.Message = "Please select a valid Excel file.";
                    modelResponse.StatusCode = 400;
                    return Ok(modelResponse);
                }

                var userId = HttpContext.Items["DecryptedUserId"]?.ToString() ?? "";
                var companyId = HttpContext.Items["DecryptedCompanyId"]?.ToString() ?? "";

                var uploadResults = await _vendorRepository.UploadVendorFHRIDMappingExcelAsync(file, companyId, userId);

                int successCount = uploadResults.Count(r => r.Status == "Inserted" || r.Status == "Updated");
                int failedCount = uploadResults.Count(r => r.Status == "Failed");

                modelResponse.IsSuccess = true;
                modelResponse.Message = $"Vendor FHR ID Mapping processed: {successCount} successful, {failedCount} failed.";
                modelResponse.Data = uploadResults;
                modelResponse.StatusCode = 200;

                return Ok(modelResponse);
            }
            catch (Exception ex)
            {
                modelResponse.IsSuccess = false;
                modelResponse.Message = ex.Message;
                modelResponse.StatusCode = 500;
                return StatusCode(500, modelResponse);
            }
        }


        [HttpGet("GetVendorFHRIDFiles")]
        [Authorize]
        public async Task<IActionResult> GetVendorFHRIDFiles()
        {
            ModelResponse modelResponse = new ModelResponse();
            try
            {
                var companyId = HttpContext.Items["DecryptedCompanyId"]?.ToString() ?? "";
                var files = await _vendorRepository.GetVendorFHRIDFilesAsync(companyId);

                modelResponse.IsSuccess = true;
                modelResponse.Message = "Uploaded files list fetched successfully.";
                modelResponse.Data = files;
                modelResponse.StatusCode = 200;
                return Ok(modelResponse);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new ModelResponse { IsSuccess = false, Message = ex.Message });
            }
        }

        [HttpGet("DownloadVendorFHRIDFile/{id}")]
        [Authorize]
        public async Task<IActionResult> DownloadVendorFHRIDFile(int id)
        {
            try
            {
                var fileDoc = await _vendorRepository.GetVendorFHRIDFileByIdAsync(id);
                if (fileDoc == null)
                {
                    return NotFound(new ModelResponse { IsSuccess = false, Message = "File record not found." });
                }

                string fileName = Path.GetFileName(fileDoc.Path);
                string configuredFolder = _configuration["AppSettings:VendorFHRIDUploads"] ?? Path.Combine(Directory.GetCurrentDirectory(), "VendorFHRIDUploads");
                string fullPath = Path.Combine(configuredFolder, fileName);

                if (!System.IO.File.Exists(fullPath))
                {
                    return NotFound(new ModelResponse { IsSuccess = false, Message = "File not found on server." });
                }
                var bytes = System.IO.File.ReadAllBytes(fullPath);
                return File(bytes, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", fileDoc.Name);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new ModelResponse { IsSuccess = false, Message = ex.Message });
            }
        }

        [HttpGet("GetRateCardUploadedFiles")]
        [Authorize]
        public async Task<IActionResult> GetRateCardUploadedFiles()
        {
            try
            {
                var companyId = HttpContext.Items["DecryptedCompanyId"]?.ToString() ?? "";
                var files = await _vendorRepository.GetRateCardUploadedFilesAsync(companyId);
                return Ok(new ModelResponse
                {
                    IsSuccess = true,
                    Message = "Uploaded files list fetched successfully.",
                    Data = files,
                    StatusCode = 200
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new ModelResponse { IsSuccess = false, Message = ex.Message });
            }
        }

        [HttpGet("DownloadRateCardFile/{id}")]
        [Authorize]
        public async Task<IActionResult> DownloadRateCardFile(int id)
        {
            try
            {
                var fileDoc = await _vendorRepository.GetRateCardFileByIdAsync(id);
                if (fileDoc == null)
                {
                    return NotFound(new ModelResponse { IsSuccess = false, Message = "File record not found." });
                }

                string fileName = Path.GetFileName(fileDoc.Path);
                string configuredFolder = _configuration["AppSettings:VendorRateCardUploads"] ?? Path.Combine(Directory.GetCurrentDirectory(), "VendorRateCardUploads");
                string fullPath = Path.Combine(configuredFolder, fileName);

                if (!System.IO.File.Exists(fullPath))
                {
                    var fallbackPath = Path.Combine(Directory.GetCurrentDirectory(), "VendorRateCardUploads", fileName);
                    if (System.IO.File.Exists(fallbackPath))
                    {
                        fullPath = fallbackPath;
                    }
                    else
                    {
                        return NotFound(new ModelResponse { IsSuccess = false, Message = "File not found on server." });
                    }
                }
                var bytes = System.IO.File.ReadAllBytes(fullPath);
                return File(bytes, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", fileDoc.Name);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new ModelResponse { IsSuccess = false, Message = ex.Message });
            }
        }

        [HttpGet("GetTransactionUploadedFiles")]
        [Authorize]
        public async Task<IActionResult> GetTransactionUploadedFiles()
        {
            try
            {
                var companyId = HttpContext.Items["DecryptedCompanyId"]?.ToString() ?? "";
                var files = await _vendorRepository.GetTransactionUploadedFilesAsync(companyId);
                return Ok(new ModelResponse
                {
                    IsSuccess = true,
                    Message = "Transaction files fetched successfully",
                    Data = files,
                    StatusCode = 200
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new ModelResponse { IsSuccess = false, Message = ex.Message, StatusCode = 500 });
            }
        }

        [HttpGet("DownloadTransactionFile/{id}")]
        [Authorize]
        public async Task<IActionResult> DownloadTransactionFile(int id)
        {
            try
            {
                var fileDoc = await _vendorRepository.GetTransactionFileByIdAsync(id);
                if (fileDoc == null)
                {
                    return NotFound(new ModelResponse { IsSuccess = false, Message = "File record not found." });
                }

                string fileName = Path.GetFileName((string)fileDoc.name); // or whatever the property is
                string configuredFolder = _configuration["AppSettings:VendorTransactions"] ?? Path.Combine(Directory.GetCurrentDirectory(), "VendorTransactions");
                string fullPath = Path.Combine(configuredFolder, fileName);

                if (!System.IO.File.Exists(fullPath))
                {
                    return NotFound(new ModelResponse { IsSuccess = false, Message = "File not found on server." });
                }
                var bytes = System.IO.File.ReadAllBytes(fullPath);
                return File(bytes, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", fileName);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new ModelResponse { IsSuccess = false, Message = ex.Message });
            }
        }

        [HttpPost("ReInitiateVendor")]
        public async Task<IActionResult> ReInitiateVendor([FromBody] UpdateVendorStatusRequest request)
        {
            try
            {
                if (string.IsNullOrEmpty(request.PkRecId))
                    return BadRequest(new { IsSuccess = false, Message = "Candidate Key is required." });

                // 1. Get candidate details for email
                var candidateMasterRepository = HttpContext.RequestServices.GetService<ICandidateMasterRepository>();
                var candidate = await candidateMasterRepository.GetById(request.PkRecId);

                if (candidate?.Mst1 == null)
                    return Ok(new { IsSuccess = false, Message = "Candidate not found. Status not updated." });

                string emailToUse = !string.IsNullOrEmpty(candidate.Mst1.email)
                    ? candidate.Mst1.email
                    : candidate.Mst1.EmailID;

                if (string.IsNullOrEmpty(emailToUse))
                    return Ok(new { IsSuccess = false, Message = "Email is missing. Please add email first. Status not updated." });

                // 2. Get first visible route
                var candidateExperienceRepo = HttpContext.RequestServices.GetService<ICandidateExperienceDetailsRepository>();
                var companyConfig = await candidateExperienceRepo.GetMandatorySettings(request.PkRecId);
                string firstVisibleRoute = GetFirstVisibleRoute(companyConfig);

                // 3. Send re-initiation email
                var onboardingEmailService = HttpContext.RequestServices.GetService<OnboardingEmailService>();
                bool isEmailSent = await onboardingEmailService.SendReInitiateEmailAsync(
                    candidate.Mst1.candidate_name,
                    emailToUse,
                    candidate.Mst1.CandidateKey,
                    firstVisibleRoute
                );

                if (isEmailSent)
                {
                    // 4. Update status to ReInitiated (3) ONLY if email sent successfully
                    await _vendorRepository.UpdateVendorStatusAsync(request.PkRecId, 3);
                    return Ok(new { IsSuccess = true, Message = $"Re-Initiated successfully. Email sent to {emailToUse}." });
                }
                else
                {
                    return StatusCode(500, new { IsSuccess = false, Message = "Failed to send email. Status not updated." });
                }
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { IsSuccess = false, Message = ex.Message });
            }
        }


        private string GetFirstVisibleRoute(CompanyConfig config)
        {
            // Check in priority order
            if (config.pan_visible) return "pan";
            if (config.aadhaar_visible) return "aadhaar";
            if (config.bankaccount_visible) return "bank";
            if (config.driving_licence_visible) return "driving-licence";
            if (config.voter_visible) return "voter";
            if (config.vendor_gst_visible) return "vendor-gst";
            if (config.signature_visible) return "signature";
            if (config.photograph_visible) return "photograph";
            if (config.basicinfo_visible) return "basicInfo";
            if (config.qualification_visible) return "education";
            if (config.experience_visible) return "previous_experience";
            if (config.family_visible) return "family_details";
            if (config.voter_visible) return "voter";
            if (config.bankaccount_visible) return "bank_account";


            // Fallback to final submission if nothing is visible (edge case)
            return "final-submission";


        }

        [HttpPost("UpdateVendorStatus")]
        public async Task<IActionResult> UpdateVendorStatus([FromForm] UpdateVendorStatusRequest request)
        {
            try
            {
                if (string.IsNullOrEmpty(request.PkRecId))
                    return BadRequest(new { IsSuccess = false, Message = "Candidate Key is required." });

                string signatureFilePath = null;
                if (request.SignatureFile != null && request.SignatureFile.Length > 0)
                {
                    var ext = Path.GetExtension(request.SignatureFile.FileName).ToLowerInvariant();
                    if (ext != ".png" && ext != ".jpg" && ext != ".jpeg" && ext != ".pdf")
                        return Ok(new ModelResponse { IsSuccess = false, Message = "Invalid file type. Only PNG, JPG, JPEG, or PDF are allowed.", StatusCode = 400 });

                    //var uploadsFolder = Path.Combine(Directory.GetCurrentDirectory(), "wwwroot", "HR_Admin_Signature");
                    var uploadsFolder = _configuration["AppSettings:VendorVerificationSignatureUploads"];
                    if (!Directory.Exists(uploadsFolder))
                        Directory.CreateDirectory(uploadsFolder);

                    var fileNameWithoutExt = Path.GetFileNameWithoutExtension(request.SignatureFile.FileName);
                    var savedFileName = $"{fileNameWithoutExt}_{DateTime.Now:ddMMyyyy_HHmmss}{ext}";
                    var physicalPath = Path.Combine(uploadsFolder, savedFileName);

                    using (var stream = new FileStream(physicalPath, FileMode.Create))
                    {
                        await request.SignatureFile.CopyToAsync(stream);
                    }
                    signatureFilePath = savedFileName;
                }

                var result = await _vendorRepository.UpdateVendorStatusAsync(request.PkRecId, request.StatusId, request.ApprovedByName, signatureFilePath, request.ApproverRemarks);
                return Ok(new { IsSuccess = true, Data = result, Message = "Status updated successfully" });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { IsSuccess = false, Message = ex.Message });
            }
        }


        [HttpGet("GetVendorAgentDropdown")]
        [Authorize]
        public async Task<IActionResult> GetVendorAgentDropdown()
        {
            ModelResponse modelResponse = new ModelResponse();
            try
            {
                var companyId = HttpContext.Items["DecryptedCompanyId"]?.ToString() ?? "";
                var list = await _vendorRepository.GetVendorAgentDropdownAsync(companyId);
                modelResponse.IsSuccess = true;
                modelResponse.Message = "Agent dropdown fetched successfully.";
                modelResponse.Data = list;
                modelResponse.StatusCode = 200;
                return Ok(modelResponse);
            }
            catch (Exception ex)
            {
                modelResponse.IsSuccess = false;
                modelResponse.Message = ex.Message;
                modelResponse.StatusCode = 500;
                return StatusCode(500, modelResponse);
            }
        }



        [HttpGet("GetVendorDownloadVerificationList")]
        [Authorize]
        public async Task<IActionResult> GetVendorDownloadVerificationList([FromQuery] int pageIndex = 1, [FromQuery] int pageSize = 1000, [FromQuery] string searchTerm = "")
        {
            ModelResponse modelResponse = new ModelResponse();
            try
            {
                var companyId = HttpContext.Items["DecryptedCompanyId"]?.ToString() ?? "";
                var userId = HttpContext.Items["DecryptedUserId"]?.ToString() ?? "";
                var (totalCount, vendors) = await _vendorRepository.GetVendorDownloadVerificationListAsync(pageIndex, pageSize, companyId, userId, searchTerm);

                modelResponse.IsSuccess = true;
                modelResponse.Message = "Vendor Verification Download List fetched successfully.";
                modelResponse.Data = new
                {
                    TotalCount = totalCount,
                    Vendors = vendors
                };
                modelResponse.StatusCode = 200;
                return Ok(modelResponse);
            }
            catch (Exception ex)
            {
                modelResponse.IsSuccess = false;
                modelResponse.Message = ex.Message;
                modelResponse.StatusCode = 500;
                return StatusCode(500, modelResponse);
            }
        }


        private async Task<string> GenerateAndSaveVerificationLinkAsync(string pk_recId)
        {
            try
            {
                if (string.IsNullOrEmpty(pk_recId)) return string.Empty;

                var candidateMasterRepository = HttpContext.RequestServices.GetService<ICandidateMasterRepository>();
                if (candidateMasterRepository == null) return string.Empty;

                // Get candidate details
                var candidate = await candidateMasterRepository.GetById(pk_recId);
                if (candidate == null || candidate.Mst1 == null) return string.Empty;

                string candidateKey = candidate.Mst1.CandidateKey;
                string VerificationLink = candidate.Mst1.VerificationLink;

                if (!string.IsNullOrEmpty(VerificationLink))
                {
                    return string.Empty;
                }

                // Agar CandidateKey pehle se exist karti hai, to bar-bar generate/update karne ki jarurat nahi hai
                if (!string.IsNullOrEmpty(candidateKey))
                {
                    return string.Empty;
                }

                // Sirf tab generate & save karein jab CandidateKey missing/null ho
                candidateKey = CandidateKeyGenerator.GenerateUrlSafeKey();

                var candidateExperienceDetailsRepository = HttpContext.RequestServices.GetService<ICandidateExperienceDetailsRepository>();
                string firstVisibleRoute = "vendor-gst";
                if (candidateExperienceDetailsRepository != null)
                {
                    var companyConfig = await candidateExperienceDetailsRepository.GetMandatorySettings(pk_recId);
                    if (companyConfig != null)
                    {
                        firstVisibleRoute = GetFirstVisibleRoute(companyConfig);
                    }
                }

                string frontendBaseUrl = _configuration["FrontendSettings:Domain"] ?? "";
                string onboardingLink = $"{frontendBaseUrl}/#/on_boarding/{firstVisibleRoute}?key={candidateKey}";

                // Save CandidateKey & VerificationLink to Database
                var p = new DynamicParameters();
                p.Add("@pk_recId", pk_recId);
                p.Add("@CandidateKey", candidateKey);
                p.Add("@VerificationLink", onboardingLink);
                await DataBaseFactory.QuerySPAsync("REC_Candidate_UpdateVerificationLink", p);

                return onboardingLink;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error in GenerateAndSaveVerificationLinkAsync: {ex.Message}");
                return string.Empty;
            }
        }
    }



}












