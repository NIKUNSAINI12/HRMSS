using ClosedXML.Excel;
using Dapper;
using DocumentFormat.OpenXml.Spreadsheet;
using HRMSWebAPI.Helper;
using HRMSWebAPI.Models;
using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using System.Threading.Tasks;

namespace HRMSWebAPI.Repository
{
    public class VendorRepository : IVendorRepository
    {
        private readonly IConfiguration? _configuration;
        public VendorRepository(IConfiguration? configuration = null)
        {
            _configuration = configuration;
        }
        public async Task<IEnumerable<dynamic>> UploadRateCardAsync(
    VendorRateCardUploadRequest request, string userId, string companyId, string locationId, string filePath = null)
        {
            var p = new DynamicParameters();

            string xmlData = XmlUtility.XmlSerializeToString(request);
            if (xmlData.StartsWith("<?xml"))
            {
                int idx = xmlData.IndexOf("?>");
                if (idx != -1)
                    xmlData = xmlData.Substring(idx + 2).Trim();
            }

            p.Add("@Doc", xmlData, DbType.Xml);
            p.Add("@fk_companyId", companyId ?? "", DbType.String);
            p.Add("@fk_userId", userId ?? "", DbType.String);
            p.Add("@fk_locId", locationId ?? "", DbType.String);
            p.Add("@FilePath", filePath ?? "", DbType.String);
            p.Add("@FileName", filePath ?? "", DbType.String);
            // Use dynamic so ALL SP columns come through (Model-wise: ODH/XRM/LARGE)
            var dbResult = DataBaseFactory.QuerySP<dynamic>(
                "RateCardExcel_Upload", p, "RateCardExcel_Upload");

            return dbResult ?? Enumerable.Empty<dynamic>();
        }
        public async Task<(int totalCount, IEnumerable<VendorRateCardModel> list)> GetVendorListAsync(int pageIndex, int pageSize, string companyId, string searchTerm)
        {
            try
            {
                DynamicParameters dynamicParameters = new DynamicParameters();
                dynamicParameters.Add("@fk_companyId", companyId ?? "", DbType.String);
                dynamicParameters.Add("@pageIndex", pageIndex, DbType.Int32);
                dynamicParameters.Add("@pageSize", pageSize, DbType.Int32);
                dynamicParameters.Add("@SearchTerm", searchTerm ?? "", DbType.String);

                var dbResult = DataBaseFactory.QuerySP<VendorRateCardModel>("LSP_VendorRateCard_GetList", dynamicParameters, "VendorRateCard_GetList");

                var list = dbResult?.ToList() ?? new List<VendorRateCardModel>();
                return (list.Count, list);
            }
            catch (Exception)
            {
                return (0, new List<VendorRateCardModel>());
            }
        }


        // by aaryn and rupesh

        public async Task<VendorResponseModel> InsertVendorAsync(VendorModel model, string userId, string companyId, string locationId)

        {
            try
            {

                // Wrap the candidate object in the dataset wrapper
                VendorModelDataset dataset = new VendorModelDataset
                {
                    Vendor = model
                };

                string xmlData = XmlUtility.XmlSerializeToString(dataset);
                DynamicParameters dynamicParameters = new DynamicParameters();
                dynamicParameters.Add("@XmlVendor", xmlData, DbType.String);
                dynamicParameters.Add("@fk_companyId", companyId ?? "", DbType.String);
                dynamicParameters.Add("@fk_userId", userId ?? "", DbType.String);
                dynamicParameters.Add("@fk_locId", locationId ?? "", DbType.String);
                dynamicParameters.Add("@pk_recId", dbType: DbType.String, size: 15, direction: ParameterDirection.Output);
                dynamicParameters.Add("@IsSuccessfull", dbType: DbType.Boolean, direction: ParameterDirection.Output);
                dynamicParameters.Add("@Message", dbType: DbType.String, size: 255, direction: ParameterDirection.Output);

                var result = DataBaseFactory.QuerySP("Vendor_Ins", dynamicParameters);
                return new VendorResponseModel
                {
                    pk_recId = dynamicParameters.Get<string>("@pk_recId"),
                    IsSuccessfully = dynamicParameters.Get<bool>("@IsSuccessfull"),
                    IsMessage = dynamicParameters.Get<string>("@Message")
                };
            }
            catch (Exception ex)
            {
                return new VendorResponseModel { IsSuccessfully = false, IsMessage = ex.Message };
            }
        }


        public async Task<(int totalCount, IEnumerable<VendorFHRIDHistoryModel> list)> GetVendorFHRIDHistoryAsync(string pk_recId, int pageIndex, int pageSize)
        {
            try
            {
                DynamicParameters dynamicParameters = new DynamicParameters();
                dynamicParameters.Add("@pk_recId", pk_recId ?? "", DbType.String);
                dynamicParameters.Add("@pageIndex", pageIndex, DbType.Int32);
                dynamicParameters.Add("@pageSize", pageSize, DbType.Int32);

                var dbResult = DataBaseFactory.QuerySP<VendorFHRIDHistoryModel>("USP_Vendor_GetFHRIDHistory", dynamicParameters, "USP_Vendor_GetFHRIDHistory");

                var list = dbResult?.ToList() ?? new List<VendorFHRIDHistoryModel>();
                int totalCount = list.FirstOrDefault()?.TotalCount ?? 0;

                return (totalCount, list);
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error in GetVendorFHRIDHistoryAsync: " + ex.Message);
                return (0, Enumerable.Empty<VendorFHRIDHistoryModel>());
            }
        }



        public async Task<IEnumerable<dynamic>> GetFHRIDsAsync(string clientId, string modelId, string companyId)
        {
            try
            {
                var param = new DynamicParameters();
                param.Add("@ClientId", clientId);
                param.Add("@ModelId", modelId);
                param.Add("@CompanyId", companyId);

                var result = await DataBaseFactory.QuerySPAsync<dynamic>("USP_VendorRateCard_GetLinkedFHRIDs", param, "VendorRateCard - GetLinkedFHRIDs");
                return result;
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error in GetFHRIDsAsync: " + ex.Message);
                return Enumerable.Empty<dynamic>();
            }
        }

        public async Task<VendorResponseModel> UpdateVendorAsync(VendorModel model, string userId, string companyId)
        {
            try
            {
                // Wrap the candidate object in the dataset wrapper
                VendorModelDataset dataset = new VendorModelDataset
                {
                    Vendor = model
                };

                string xmlData = XmlUtility.XmlSerializeToString(dataset);
                DynamicParameters dynamicParameters = new DynamicParameters();
                dynamicParameters.Add("@XmlVendor", xmlData, DbType.String);
                dynamicParameters.Add("@pk_recId", model.pk_recId, DbType.String);
                dynamicParameters.Add("@fk_companyId", companyId ?? "", DbType.String);
                dynamicParameters.Add("@fk_userId", userId ?? "", DbType.String);

                var result = DataBaseFactory.QuerySP<VendorResponseModel>("Vendor_Upd", dynamicParameters, "Vendor_Upd").FirstOrDefault();

                return result ?? new VendorResponseModel { IsSuccessfully = false, IsMessage = "Failed to update vendor." };
            }
            catch (Exception ex)
            {
                return new VendorResponseModel { IsSuccessfully = false, IsMessage = ex.Message };
            }
        }



        public async Task<VendorResponseModel> DeleteVendorAsync(string pk_recId)
        {
            try
            {
                DynamicParameters dynamicParameters = new DynamicParameters();
                dynamicParameters.Add("@pk_recId", pk_recId, DbType.String);

                var result = DataBaseFactory.QuerySP<VendorResponseModel>("Vendor_Del", dynamicParameters, "Vendor_Del").FirstOrDefault();
                return result ?? new VendorResponseModel { IsSuccessfully = false, IsMessage = "Failed to delete vendor." };
            }
            catch (Exception ex)
            {
                return new VendorResponseModel { IsSuccessfully = false, IsMessage = ex.Message };
            }
        }


        public async Task<VendorModel?> GetVendorByIdAsync(string pk_recId)
        {
            try
            {
                using var conn = DataBaseFactory.ConnString();

                // Ek hi SP call se dono result sets fetch karna
                using var multi = await conn.QueryMultipleAsync("Vendor_GetById", new { pk_recId = pk_recId },
                    commandType: CommandType.StoredProcedure
                );

                // First SELECT se Vendor data read karna
                var vendor = multi.Read<VendorModel>().FirstOrDefault();

                if (vendor != null)
                {
                    // Second SELECT se Rate Cards read karna
                    var rateCards = multi.Read<VendorRateCardItemModel>().ToList();
                    vendor.RateCards = rateCards;

                    if (rateCards.Count > 0)
                    {
                        var first = rateCards[0];

                        // Handle mappings if SP returns Vendor_FKClientId instead of fk_cost_centre_id
                        var allClients = rateCards
                            .Select(r => r.fk_cost_centre_id != 0 ? r.fk_cost_centre_id.ToString() : (r.Vendor_FKClientId ?? ""))
                            .Where(id => !string.IsNullOrWhiteSpace(id))
                            .Distinct();
                        vendor.Vendor_FKClientId = string.Join(",", allClients);

                        var allModels = rateCards
                            .Select(r => {
                                string cId = r.fk_cost_centre_id != 0 ? r.fk_cost_centre_id.ToString() : (r.Vendor_FKClientId ?? "");
                                string mId = !string.IsNullOrEmpty(r.fk_modelId) ? r.fk_modelId : (r.Vendor_FK_ModelId ?? "");
                                return $"{cId}_{mId}";
                            })
                            .Where(id => !string.IsNullOrWhiteSpace(id) && id != "_")
                            .Distinct();
                        vendor.Vendor_FK_ModelId = string.Join(",", allModels);

                        // Combine multiple FHRIDs into a comma-separated string of composite IDs
                        var allHfrids = rateCards
                            .Where(r => !string.IsNullOrEmpty(r.Vendor_FHRID))
                            .Select(r => {
                                string cId = r.fk_cost_centre_id != 0 ? r.fk_cost_centre_id.ToString() : (r.Vendor_FKClientId ?? "");
                                string mId = !string.IsNullOrEmpty(r.fk_modelId) ? r.fk_modelId : (r.Vendor_FK_ModelId ?? "");
                                return $"{cId}_{mId}_{r.Vendor_FHRID}";
                            })
                            .Distinct();
                        vendor.Vendor_HFRID = string.Join(",", allHfrids);

                        vendor.Vendor_RateType = first.Vendor_RateType;
                        vendor.Vendor_Type = first.Vendor_Type;
                        vendor.Vendor_CategoryID = first.Vendor_CategoryID;
                        vendor.Vendor_Rate = first.Vendor_Rate;
                        vendor.Vendor_RateDeduction = first.Vendor_RateDeduction;
                        vendor.Vendor_DeliveryRate = first.Vendor_DeliveryRate ?? vendor.Vendor_DeliveryRate;
                        vendor.Vendor_PickupRate = first.Vendor_PickupRate ?? vendor.Vendor_PickupRate;
                        vendor.Vendor_TDSPercentage = vendor.Vendor_TDSPercentage ?? first.Vendor_TDSPercentage;
                        vendor.Vendor_MFNRate = first.Vendor_MFNRate ?? vendor.Vendor_MFNRate;
                    }
                }
                return vendor;
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error in GetVendorByIdAsync: " + ex.Message);
                return null;
            }
        }


        public async Task SaveVendorRateCardsAsync(string pk_recId, List<VendorRateCardItemModel>? rateCards, VendorModel fallbackModel)
        {
            if (string.IsNullOrEmpty(pk_recId)) return;

            try
            {
                using var conn = DataBaseFactory.ConnString();
                if (conn.State != ConnectionState.Open) await conn.OpenAsync();

                using var trans = conn.BeginTransaction();
                try
                {
                    var rawItems = rateCards != null && rateCards.Count > 0
                        ? rateCards
                        : new List<VendorRateCardItemModel>();

                    if (rawItems.Count == 0 && !string.IsNullOrEmpty(fallbackModel.Vendor_FKClientId) && !string.IsNullOrEmpty(fallbackModel.Vendor_FK_ModelId))
                    {
                        if (long.TryParse(fallbackModel.Vendor_FKClientId, out long clientId))
                        {
                            rawItems.Add(new VendorRateCardItemModel
                            {
                                fk_cost_centre_id = clientId,
                                fk_modelId = fallbackModel.Vendor_FK_ModelId,
                                Vendor_HFRID = fallbackModel.Vendor_HFRID,
                                Vendor_RateType = fallbackModel.Vendor_RateType,
                                Vendor_Type = fallbackModel.Vendor_Type,
                                Vendor_CategoryID = fallbackModel.Vendor_CategoryID,
                                Vendor_Rate = fallbackModel.Vendor_Rate,
                                Vendor_RateDeduction = fallbackModel.Vendor_RateDeduction,
                                Vendor_DeliveryRate = fallbackModel.Vendor_DeliveryRate,
                                Vendor_PickupRate = fallbackModel.Vendor_PickupRate,
                                Vendor_TDSPercentage = fallbackModel.Vendor_TDSPercentage,
                                Vendor_MFNRate = fallbackModel.Vendor_MFNRate,
                                EffectiveFrom = fallbackModel.EffectiveFrom ?? DateTime.Today
                            });
                        }
                    }

                    // Deduplicate items to ensure only 1 rate card per Client, Model, and Category is processed
                    var itemsToInsert = rawItems
                        .GroupBy(x => new {
                            ClientId = x.fk_cost_centre_id > 0 ? x.fk_cost_centre_id : (long.TryParse(x.Vendor_FKClientId, out long cid) ? cid : 0),
                            ModelId = !string.IsNullOrEmpty(x.fk_modelId) ? x.fk_modelId : x.Vendor_FK_ModelId ?? "",
                            CatId = x.Vendor_CategoryID ?? 0
                        })
                        .Where(g => g.Key.ClientId > 0 && !string.IsNullOrEmpty(g.Key.ModelId))
                        .Select(g => g.Last())
                        .ToList();

                    foreach (var rc in itemsToInsert)
                    {
                        long clientId = rc.fk_cost_centre_id;
                        if (clientId == 0 && !string.IsNullOrEmpty(rc.Vendor_FKClientId) && long.TryParse(rc.Vendor_FKClientId, out long parsedId))
                        {
                            clientId = parsedId;
                        }
                        string modelId = !string.IsNullOrEmpty(rc.fk_modelId) ? rc.fk_modelId : rc.Vendor_FK_ModelId ?? "";

                        if (clientId > 0 && !string.IsNullOrEmpty(modelId))
                        {
                            DateTime effFromDate = rc.EffectiveFrom ?? fallbackModel.EffectiveFrom ?? DateTime.Today;
                            string effFromFormatted = effFromDate.ToString("yyyy-MM-dd");
                            int catId = rc.Vendor_CategoryID ?? 0;

                            var param = new DynamicParameters();
                            param.Add("@fk_recId", pk_recId);
                            param.Add("@fk_cost_centre_id", clientId);
                            param.Add("@fk_modelId", modelId);
                            param.Add("@Vendor_HFRID", rc.Vendor_HFRID);
                            param.Add("@Vendor_RateType", rc.Vendor_RateType);
                            param.Add("@Vendor_Type", rc.Vendor_Type);
                            param.Add("@Vendor_CategoryID", catId);
                            param.Add("@Vendor_Rate", rc.Vendor_Rate);
                            param.Add("@Vendor_RateDeduction", rc.Vendor_RateDeduction);
                            param.Add("@Vendor_DeliveryRate", rc.Vendor_DeliveryRate);
                            param.Add("@Vendor_PickupRate", rc.Vendor_PickupRate);
                            param.Add("@Vendor_TDSPercentage", rc.Vendor_TDSPercentage);
                            param.Add("@Vendor_MFNRate", rc.Vendor_MFNRate);
                            param.Add("@EffectiveFrom", effFromFormatted, DbType.String);

                            await conn.ExecuteAsync("LSP_VendorRateCard_InsertSingle", param, trans, commandType: CommandType.StoredProcedure);
                        }
                    }

                    trans.Commit();
                }
                catch (Exception ex)
                {
                    trans.Rollback();
                    Console.WriteLine("Error saving rate cards: " + ex.Message);
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error in SaveVendorRateCardsAsync: " + ex.Message);
            }
        }
        public async Task<(int totalCount, IEnumerable<VendorModel> vendors)> GetAllVendorsAsync(int pageIndex, int pageSize,string companyId, string searchTerm = "")
        {
            try
            {
                DynamicParameters dynamicParameters = new DynamicParameters();
                dynamicParameters.Add("@pageindex", pageIndex, DbType.Int32);
                dynamicParameters.Add("@pagesize", pageSize, DbType.Int32);
                dynamicParameters.Add("@searchTerm", searchTerm, DbType.String);
                dynamicParameters.Add("@fk_companyId", companyId, DbType.String);

                var tuple = DataBaseFactory.QueryMultipleSP<dynamic, VendorModel>("Vendor_SelForGrid", dynamicParameters, "Vendor_SelForGrid");
                if (tuple == null || tuple.Item2 == null) return (0, Enumerable.Empty<VendorModel>());

                int totalCount = 0;
                if (tuple.Item1 is IEnumerable<dynamic> countList && countList.Any())
                {
                    var firstRow = (IDictionary<string, object>)countList.First();
                    if (firstRow.ContainsKey("TotalCount"))
                    {
                        totalCount = Convert.ToInt32(firstRow["TotalCount"]);
                    }
                }

                return (totalCount, tuple.Item2.ToList());
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error in GetAllVendorsAsync: " + ex.Message);
                return (0, Enumerable.Empty<VendorModel>());
            }
        }

        public async Task<List<VendorUploadRowModel>> UploadVendorExcelAsync(IFormFile file, string? companyId = null, string? userId = null)
        {
            var resultList = new List<VendorUploadRowModel>();
            if (file == null || file.Length == 0) return resultList;

            try
            {
                // 1. Physical file saving with timestamped naming convention
                string uploadFolder = _configuration?["AppSettings:VendorMasterUploads"]!;
                if (string.IsNullOrEmpty(uploadFolder))
                {
                    uploadFolder = Path.Combine(Directory.GetCurrentDirectory(), "VendorMasterUploads");
                }
                if (!Directory.Exists(uploadFolder)) Directory.CreateDirectory(uploadFolder);

                string fileNameWithoutExt = Path.GetFileNameWithoutExtension(file.FileName);
                string ext = Path.GetExtension(file.FileName);
                string savedFileName = $"{fileNameWithoutExt}_{DateTime.Now:ddMMyy_HHmmss}{ext}";
                string savedFilePath = Path.Combine(uploadFolder, savedFileName);

                using (var fs = new FileStream(savedFilePath, FileMode.Create))
                {
                    await file.CopyToAsync(fs);
                }

                // 2. Read Excel rows and build XML Request
                using var workbook = new XLWorkbook(savedFilePath);
                var worksheet = workbook.Worksheets.FirstOrDefault();
                if (worksheet == null) return resultList;

                var headerRow = worksheet.Row(1);
                var colMap = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
                foreach (var cell in headerRow.CellsUsed())
                {
                    string headerText = cell.GetValue<string>().Trim().Replace(" ", "").Replace("_", "").Replace("*", "").Replace("%", "");
                    if (!string.IsNullOrEmpty(headerText) && !colMap.ContainsKey(headerText))
                    {
                        colMap[headerText] = cell.Address.ColumnNumber;
                    }
                }

                string GetVal(IXLRow r, string[] keys, int fallbackCol)
                {
                    foreach (var k in keys)
                    {
                        if (colMap.TryGetValue(k, out int colIdx))
                        {
                            var cell = r.Cell(colIdx);
                            if (cell != null && !cell.IsEmpty())
                            {
                                return cell.GetFormattedString()?.Trim() ?? cell.Value.ToString().Trim();
                            }
                        }
                    }

                    if (fallbackCol > 0)
                    {
                        var cell = r.Cell(fallbackCol);
                        if (cell != null && !cell.IsEmpty())
                        {
                            return cell.GetFormattedString()?.Trim() ?? cell.Value.ToString().Trim();
                        }
                    }

                    return string.Empty;
                }

                int lastRowNumber = worksheet.LastRowUsed()?.RowNumber() ?? 0;
                var xmlRequest = new VendorXmlUploadRequest();

                for (int rowNumber = 2; rowNumber <= lastRowNumber; rowNumber++)
                {
                    var row = worksheet.Row(rowNumber);
                    string vendorName = GetVal(row, new[] { "VENDORNAME", "VENDOR", "NAME" }, 1);
                    string fatherName = GetVal(row, new[] { "FATHERNAME" }, 2);
                    string contactNo = GetVal(row, new[] { "CONTACTNO", "CONTACT" }, 3);
                    string gender = GetVal(row, new[] { "GENDER", "SEX" }, 4);
                    string dobStr = GetVal(row, new[] { "DOB", "DATEOFBIRTH" }, 5);
                    string address = GetVal(row, new[] { "ADDRESS" }, 6);
                    string state = GetVal(row, new[] { "STATE", "STATENAME" }, 7);
                    string city = GetVal(row, new[] { "CITY", "CITYNAME" }, 8);
                    string bankName = GetVal(row, new[] { "BANKNAME", "BANK" }, 9);
                    string accountNo = GetVal(row, new[] { "ACCOUNTNO", "ACCOUNTNUMBER", "ACNO", "ACCNO" }, 10);
                    string ifscCode = GetVal(row, new[] { "IFSCCODE", "IFSC" }, 11);
                    string panNo = GetVal(row, new[] { "PANNO", "PAN" }, 12);
                    string aadhaarNo = GetVal(row, new[] { "AADHAARNO", "AADHARNO", "AADHAAR" }, 13);
                    string gstNo = GetVal(row, new[] { "GSTNO", "GST" }, 14);
                    string gstPercentage = GetVal(row, new[] { "GSTPERCENTAGE", "GSTPERCENT" }, 15);
                    string tdsPercentage = GetVal(row, new[] { "TDSPERCENTAGE", "TDS", "TDSPERCENT" }, 16);
                    string status = GetVal(row, new[] { "STATUS" }, 17);

                    string agentName = GetVal(row, new[] { "AGENTCODE", "AGENTNAME", "AGENT" }, 17);
                    string legalName = GetVal(row, new[] { "LEGALNAME" }, 18);
                    string emergencyContactNo = GetVal(row, new[] { "EMERGENCYCONTACTNO" }, 19);
                    string emailID = GetVal(row, new[] { "EMAILID", "EMAIL" }, 20);
                    string eShramCardNo = GetVal(row, new[] { "ESHRAMCARDNO" }, 21);
                    string ayushmanCardNo = GetVal(row, new[] { "AYUSHMANCARDNO" }, 22);
                    string accountHolderName = GetVal(row, new[] { "ACCOUNTHOLDERNAME", "ACCOUNTHOLDER", "HOLDERNAME" }, 23);
                    string permanentPinCode = GetVal(row, new[] { "PERMANENTPINCODE" }, 24);
                    string currentPinCode = GetVal(row, new[] { "CURRENTPINCODE" }, 25);
                    string ayushmanCard = !string.IsNullOrWhiteSpace(ayushmanCardNo) ? "Yes" : "No";

                    // Skip completely empty rows
                    if (string.IsNullOrWhiteSpace(vendorName) && string.IsNullOrWhiteSpace(contactNo) && string.IsNullOrWhiteSpace(accountNo) && string.IsNullOrWhiteSpace(bankName))
                    {
                        continue;
                    }

                    xmlRequest.Rows.Add(new VendorXmlUploadItem
                    {
                        Vendor_Name = vendorName,
                        Vendor_FatherName = fatherName,
                        Vendor_ContactNo = contactNo,
                        Vendor_Gender = gender,
                        Vendor_DOB = dobStr,
                        Vendor_Address = address,
                        Vendor_State = state,
                        Vendor_City = city,
                        Vendor_BankName = bankName,
                        Vendor_AccountNo = accountNo,
                        Vendor_IFSCCode = ifscCode,
                        Vendor_PanNo = panNo,
                        Vendor_AaddharNo = aadhaarNo,
                        Vendor_GSTNo = gstNo,
                        GstPercentage = gstPercentage,
                        TdsPercentage = tdsPercentage,
                        Vendor_Status = status,
                        AgentName = agentName,
                        LegalName = legalName,
                        EmergencyContactNo = emergencyContactNo,
                        EmailID = emailID,
                        EShramCardNo = eShramCardNo,
                        AyushmanCard = ayushmanCard,
                        AyushmanCardNo = ayushmanCardNo,
                        AccountHolderName = accountHolderName,
                        PermanentPinCode = permanentPinCode,
                        CurrentPinCode = currentPinCode
                    });
                }

                if (xmlRequest.Rows.Count == 0)
                {
                    resultList.Add(new VendorUploadRowModel
                    {
                        Status = "Failed",
                        Message = "No valid data rows found in Excel file.",
                        IsSuccess = false
                    });
                    return resultList;
                }

                // 3. Serialize to XML
                string xmlData = XmlUtility.XmlSerializeToString(xmlRequest);
                if (xmlData.StartsWith("<?xml"))
                {
                    int idx = xmlData.IndexOf("?>");
                    if (idx != -1)
                    {
                        xmlData = xmlData.Substring(idx + 2).Trim();
                    }
                }

                // 4. Call Single Stored Procedure
                var p = new DynamicParameters();
                p.Add("@Doc", xmlData, DbType.Xml);
                p.Add("@FileName", savedFileName, DbType.String);
                p.Add("@FilePath", savedFilePath, DbType.String);
                p.Add("@fk_companyId", companyId ?? "", DbType.String);
                p.Add("@fk_userId", userId ?? "", DbType.String);

                var dbResult = DataBaseFactory.QuerySP<VendorUploadRowModel>(
                    "Vendor_upload",
                    p,
                    "Vendor_upload"
                );

                if (dbResult != null && dbResult.Any())
                {
                    resultList = dbResult.ToList();
                }
                else
                {
                    resultList.Add(new VendorUploadRowModel
                    {
                        Status = "Uploaded",
                        Message = "Vendor records processed successfully.",
                        IsSuccess = true
                    });
                }

                // 5. Multi-Tab Excel: Append 'Upload Summary & Status' worksheet in background task
                if (resultList.Any())
                {
                    var resultsForExcel = resultList.ToList();
                    _ = Task.Run(() =>
                    {
                        try
                        {
                            if (File.Exists(savedFilePath))
                            {
                                using (var wb = new XLWorkbook(savedFilePath))
                                {
                                    string summarySheetName = "Upload Summary & Status";
                                    var existingSummary = wb.Worksheets.FirstOrDefault(w => w.Name.Equals(summarySheetName, StringComparison.OrdinalIgnoreCase));
                                    if (existingSummary != null)
                                    {
                                        wb.Worksheets.Delete(existingSummary.Name);
                                    }

                                    var summaryWs = wb.Worksheets.Add(summarySheetName);

                                    int totalRecords = resultsForExcel.Count;
                                    int successCount = resultsForExcel.Count(r => r.IsSuccess || r.Status == "Uploaded" || r.Status == "Success" || r.Status == "Inserted" || r.Status == "Updated");
                                    int failedCount = totalRecords - successCount;

                                    // Top Summary Metrics Header
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

                                    // Top Summary Metrics Values
                                    summaryWs.Cell(2, 1).Value = totalRecords;
                                    summaryWs.Cell(2, 1).Style.Font.Bold = true;
                                    summaryWs.Cell(2, 1).Style.Alignment.Horizontal = XLAlignmentHorizontalValues.Center;

                                    summaryWs.Cell(2, 2).Value = successCount;
                                    summaryWs.Cell(2, 2).Style.Font.Bold = true;
                                    summaryWs.Cell(2, 2).Style.Alignment.Horizontal = XLAlignmentHorizontalValues.Center;

                                    summaryWs.Cell(2, 3).Value = failedCount;
                                    summaryWs.Cell(2, 3).Style.Font.Bold = true;
                                    summaryWs.Cell(2, 3).Style.Alignment.Horizontal = XLAlignmentHorizontalValues.Center;

                                    // Detailed Rows Header
                                    int summaryHeaderRow = 4;
                                    string[] headers = new string[] {
                                   "Sr. No", "Status", "Vendor Name", "Father Name", "Contact No",
                                   "Gender", "DOB", "Address", "State", "City",
                                   "Bank Name", "Account No", "IFSC Code", "PAN No", "Aadhaar No",
                                   "GST No", "GST %", "TDS %", "Agent Code", "Legal Name", "Emergency Contact", "Email ID", "E-Shram Card", "Ayushman Card", "Ayushman Card No", "Account Holder Name", "Permanent Pin", "Current Pin"
                               };
                                    for (int i = 0; i < headers.Length; i++)
                                    {
                                        var cell = summaryWs.Cell(summaryHeaderRow, i + 1);
                                        cell.Value = headers[i];
                                        cell.Style.Font.Bold = true;
                                        cell.Style.Fill.BackgroundColor = XLColor.FromArgb(52, 58, 64);
                                        cell.Style.Font.FontColor = XLColor.White;
                                    }

                                    // Detailed Rows Data
                                    int currRow = 5;
                                    for (int i = 0; i < resultsForExcel.Count; i++)
                                    {
                                        var item = resultsForExcel[i];
                                        bool isRowUploaded = item.IsSuccess || item.Status == "Uploaded" || item.Status == "Updated" || item.Status == "Success" || item.Status == "Inserted";
                                        string rowStatus = isRowUploaded
                                            ? "Uploaded"
                                            : (!string.IsNullOrEmpty(item.Message) ? item.Message : (!string.IsNullOrEmpty(item.Status) ? item.Status : "Failed"));

                                        summaryWs.Cell(currRow, 1).Value = i + 1;
                                        summaryWs.Cell(currRow, 2).Value = rowStatus;
                                        summaryWs.Cell(currRow, 3).Value = item.Vendor_Name ?? "";
                                        summaryWs.Cell(currRow, 4).Value = item.Vendor_FatherName ?? "";
                                        summaryWs.Cell(currRow, 5).Value = item.Vendor_ContactNo ?? "";
                                        summaryWs.Cell(currRow, 6).Value = item.Vendor_Gender ?? "";
                                        summaryWs.Cell(currRow, 7).Value = item.Vendor_DOB ?? "";
                                        summaryWs.Cell(currRow, 8).Value = item.Vendor_Address ?? "";
                                        summaryWs.Cell(currRow, 9).Value = item.Vendor_State ?? "";
                                        summaryWs.Cell(currRow, 10).Value = item.Vendor_City ?? "";
                                        summaryWs.Cell(currRow, 11).Value = item.Vendor_BankName ?? "";
                                        summaryWs.Cell(currRow, 12).Value = item.Vendor_AccountNo ?? "";
                                        summaryWs.Cell(currRow, 13).Value = item.Vendor_IFSCCode ?? "";
                                        summaryWs.Cell(currRow, 14).Value = item.Vendor_PanNo ?? "";
                                        summaryWs.Cell(currRow, 15).Value = item.Vendor_AaddharNo ?? "";
                                        summaryWs.Cell(currRow, 16).Value = item.Vendor_GSTNo ?? "";
                                        summaryWs.Cell(currRow, 17).Value = item.Vendor_GstPercentage ?? "";
                                        summaryWs.Cell(currRow, 18).Value = item.Vendor_TdsPercentage ?? "";
                                        summaryWs.Cell(currRow, 19).Value = item.AgentName ?? "";
                                        summaryWs.Cell(currRow, 20).Value = item.LegalName ?? "";
                                        summaryWs.Cell(currRow, 21).Value = item.EmergencyContactNo ?? "";
                                        summaryWs.Cell(currRow, 22).Value = item.EmailID ?? "";
                                        summaryWs.Cell(currRow, 23).Value = item.EShramCardNo ?? "";
                                        summaryWs.Cell(currRow, 24).Value = item.AyushmanCard ?? "";
                                        summaryWs.Cell(currRow, 25).Value = item.AyushmanCardNo ?? "";
                                        summaryWs.Cell(currRow, 26).Value = item.AccountHolderName ?? "";
                                        summaryWs.Cell(currRow, 27).Value = item.PermanentPinCode ?? "";
                                        summaryWs.Cell(currRow, 28).Value = item.CurrentPinCode ?? "";

                                        if (isRowUploaded)
                                        {
                                            summaryWs.Cell(currRow, 2).Style.Font.FontColor = XLColor.Green;
                                            summaryWs.Cell(currRow, 2).Style.Font.Bold = true;
                                        }
                                        else
                                        {
                                            summaryWs.Cell(currRow, 2).Style.Font.FontColor = XLColor.Red;
                                            summaryWs.Cell(currRow, 2).Style.Font.Bold = true;
                                        }

                                        currRow++;
                                    }

                                    summaryWs.Columns().AdjustToContents();
                                    wb.Save();
                                }
                            }
                        }
                        catch (Exception exWb)
                        {
                            Console.WriteLine("Could not append summary sheet to Excel: " + exWb.Message);
                        }
                    });
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error in UploadVendorExcelAsync: " + ex.Message);
                resultList.Add(new VendorUploadRowModel
                {
                    Status = "Failed",
                    Message = "File parsing/database error: " + ex.Message,
                    IsSuccess = false
                });
            }

            return resultList;
        }

        //public async Task<List<VendorUploadRowModel>> UploadVendorExcelAsync(IFormFile file, string? companyId = null, string? userId = null)
        //{
        //    var resultList = new List<VendorUploadRowModel>();
        //    if (file == null || file.Length == 0) return resultList;

        //    try
        //    {
        //        // 1. Physical file saving with timestamped naming convention
        //        string uploadFolder = _configuration?["AppSettings:VendorMasterUploads"]!;
        //        if (string.IsNullOrEmpty(uploadFolder))
        //        {
        //            uploadFolder = Path.Combine(Directory.GetCurrentDirectory(), "VendorMasterUploads");
        //        }
        //        if (!Directory.Exists(uploadFolder)) Directory.CreateDirectory(uploadFolder);

        //        string fileNameWithoutExt = Path.GetFileNameWithoutExtension(file.FileName);
        //        string ext = Path.GetExtension(file.FileName);
        //        string savedFileName = $"{fileNameWithoutExt}_{DateTime.Now:ddMMyy_HHmmss}{ext}";
        //        string savedFilePath = Path.Combine(uploadFolder, savedFileName);

        //        using (var fs = new FileStream(savedFilePath, FileMode.Create))
        //        {
        //            await file.CopyToAsync(fs);
        //        }

        //        // 2. Read Excel rows and build XML Request
        //        using var workbook = new XLWorkbook(savedFilePath);
        //        var worksheet = workbook.Worksheets.FirstOrDefault();
        //        if (worksheet == null) return resultList;

        //        var headerRow = worksheet.Row(1);
        //        var colMap = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        //        foreach (var cell in headerRow.CellsUsed())
        //        {
        //            string headerText = cell.GetValue<string>().Trim().Replace(" ", "").Replace("_", "");
        //            if (!string.IsNullOrEmpty(headerText) && !colMap.ContainsKey(headerText))
        //            {
        //                colMap[headerText] = cell.Address.ColumnNumber;
        //            }
        //        }

        //        string GetVal(IXLRow r, string key, int fallbackCol)
        //        {
        //            if (colMap.TryGetValue(key, out int colIdx))
        //            {
        //                return r.Cell(colIdx).GetValue<string>().Trim();
        //            }

        //            if (fallbackCol > 0)
        //            {
        //                return r.Cell(fallbackCol).GetValue<string>().Trim();
        //            }

        //            return string.Empty;
        //        }

        //        int lastRowNumber = worksheet.LastRowUsed()?.RowNumber() ?? 0;
        //        var xmlRequest = new VendorXmlUploadRequest();

        //        for (int rowNumber = 2; rowNumber <= lastRowNumber; rowNumber++)
        //        {
        //            var row = worksheet.Row(rowNumber);
        //            string vendorName = GetVal(row, "VENDORNAME", 1);
        //            string fatherName = GetVal(row, "FATHERNAME", 2);
        //            string contactNo = GetVal(row, "CONTACTNO", 3);
        //            string gender = GetVal(row, "GENDER", 4);
        //            string dobStr = GetVal(row, "DOB", 5);
        //            string address = GetVal(row, "ADDRESS", 6);
        //            string state = GetVal(row, "STATE", 7);
        //            string city = GetVal(row, "CITY", 8);
        //            string bankName = GetVal(row, "BANKNAME", 9);
        //            string accountNo = GetVal(row, "ACCOUNTNO", 10);
        //            string ifscCode = GetVal(row, "IFSCCODE", 11);
        //            string panNo = GetVal(row, "PANNO", 12);
        //            string aadhaarNo = GetVal(row, "AADHAARNO", 13);
        //            string gstNo = GetVal(row, "GSTNO", 14);
        //            string gstPercentage = GetVal(row, "GSTPERCENTAGE", 15);
        //            string tdsPercentage = GetVal(row, "TDSPERCENTAGE", 16);
        //            string status = GetVal(row, "STATUS", 17);

        //            string agentName = GetVal(row, "AGENTNAME", 17);
        //            string legalName = GetVal(row, "LEGALNAME", 18);
        //            string emergencyContactNo = GetVal(row, "EMERGENCYCONTACTNO", 19);
        //            string emailID = GetVal(row, "EMAILID", 20);
        //            string eShramCardNo = GetVal(row, "ESHRAMCARDNO", 21);
        //            string ayushmanCardNo = GetVal(row, "AYUSHMANCARDNO", 22);
        //            string accountHolderName = GetVal(row, "ACCOUNTHOLDERNAME", 23);
        //            string permanentPinCode = GetVal(row, "PERMANENTPINCODE", 24);
        //            string currentPinCode = GetVal(row, "CURRENTPINCODE", 25);
        //            string ayushmanCard = !string.IsNullOrWhiteSpace(ayushmanCardNo) ? "Yes" : "No";

        //            // Skip completely empty rows
        //            if (string.IsNullOrWhiteSpace(vendorName) && string.IsNullOrWhiteSpace(contactNo))
        //            {
        //                continue;
        //            }

        //            xmlRequest.Rows.Add(new VendorXmlUploadItem
        //            {
        //                Vendor_Name = vendorName,
        //                Vendor_FatherName = fatherName,
        //                Vendor_ContactNo = contactNo,
        //                Vendor_Gender = gender,
        //                Vendor_DOB = dobStr,
        //                Vendor_Address = address,
        //                Vendor_State = state,
        //                Vendor_City = city,
        //                Vendor_BankName = bankName,
        //                Vendor_AccountNo = accountNo,
        //                Vendor_IFSCCode = ifscCode,
        //                Vendor_PanNo = panNo,
        //                Vendor_AaddharNo = aadhaarNo,
        //                Vendor_GSTNo = gstNo,
        //                GstPercentage = gstPercentage,
        //                TdsPercentage = tdsPercentage,
        //                Vendor_Status = status,
        //                AgentName = agentName,
        //                LegalName = legalName,
        //                EmergencyContactNo = emergencyContactNo,
        //                EmailID = emailID,
        //                EShramCardNo = eShramCardNo,
        //                AyushmanCard = ayushmanCard,
        //                AyushmanCardNo = ayushmanCardNo,
        //                AccountHolderName = accountHolderName,
        //                PermanentPinCode = permanentPinCode,
        //                CurrentPinCode = currentPinCode
        //            });
        //        }

        //        if (xmlRequest.Rows.Count == 0)
        //        {
        //            resultList.Add(new VendorUploadRowModel
        //            {
        //                Status = "Failed",
        //                Message = "No valid data rows found in Excel file.",
        //                IsSuccess = false
        //            });
        //            return resultList;
        //        }

        //        // 3. Serialize to XML
        //        string xmlData = XmlUtility.XmlSerializeToString(xmlRequest);
        //        if (xmlData.StartsWith("<?xml"))
        //        {
        //            int idx = xmlData.IndexOf("?>");
        //            if (idx != -1)
        //            {
        //                xmlData = xmlData.Substring(idx + 2).Trim();
        //            }
        //        }

        //        // 4. Call Single Stored Procedure
        //        var p = new DynamicParameters();
        //        p.Add("@Doc", xmlData, DbType.Xml);
        //        p.Add("@FileName", savedFileName, DbType.String);
        //        p.Add("@FilePath", savedFilePath, DbType.String);
        //        p.Add("@fk_companyId", companyId ?? "", DbType.String);
        //        p.Add("@fk_userId", userId ?? "", DbType.String);

        //        var dbResult = DataBaseFactory.QuerySP<VendorUploadRowModel>(
        //            "Vendor_upload",
        //            p,
        //            "Vendor_upload"
        //        );

        //        if (dbResult != null && dbResult.Any())
        //        {
        //            resultList = dbResult.ToList();
        //        }
        //        else
        //        {
        //            resultList.Add(new VendorUploadRowModel
        //            {
        //                Status = "Uploaded",
        //                Message = "Vendor records processed successfully.",
        //                IsSuccess = true
        //            });
        //        }

        //        // 5. Multi-Tab Excel: Append 'Upload Summary & Status' worksheet in background task
        //        if (resultList.Any())
        //        {
        //            var resultsForExcel = resultList.ToList();
        //            _ = Task.Run(() =>
        //            {
        //                try
        //                {
        //                    if (File.Exists(savedFilePath))
        //                    {
        //                        using (var wb = new XLWorkbook(savedFilePath))
        //                        {
        //                            string summarySheetName = "Upload Summary & Status";
        //                            var existingSummary = wb.Worksheets.FirstOrDefault(w => w.Name.Equals(summarySheetName, StringComparison.OrdinalIgnoreCase));
        //                            if (existingSummary != null)
        //                            {
        //                                wb.Worksheets.Delete(existingSummary.Name);
        //                            }

        //                            var summaryWs = wb.Worksheets.Add(summarySheetName);

        //                            int totalRecords = resultsForExcel.Count;
        //                            int successCount = resultsForExcel.Count(r => r.IsSuccess || r.Status == "Uploaded" || r.Status == "Success" || r.Status == "Inserted" || r.Status == "Updated");
        //                            int failedCount = totalRecords - successCount;

        //                            // Top Summary Metrics Header
        //                            summaryWs.Cell(1, 1).Value = "Total Records";
        //                            summaryWs.Cell(1, 1).Style.Font.Bold = true;
        //                            summaryWs.Cell(1, 1).Style.Fill.BackgroundColor = XLColor.FromArgb(13, 110, 253);
        //                            summaryWs.Cell(1, 1).Style.Font.FontColor = XLColor.White;
        //                            summaryWs.Cell(1, 1).Style.Alignment.Horizontal = XLAlignmentHorizontalValues.Center;

        //                            summaryWs.Cell(1, 2).Value = "Success / Uploaded";
        //                            summaryWs.Cell(1, 2).Style.Font.Bold = true;
        //                            summaryWs.Cell(1, 2).Style.Fill.BackgroundColor = XLColor.FromArgb(25, 135, 84);
        //                            summaryWs.Cell(1, 2).Style.Font.FontColor = XLColor.White;
        //                            summaryWs.Cell(1, 2).Style.Alignment.Horizontal = XLAlignmentHorizontalValues.Center;

        //                            summaryWs.Cell(1, 3).Value = "Failed / Not Uploaded";
        //                            summaryWs.Cell(1, 3).Style.Font.Bold = true;
        //                            summaryWs.Cell(1, 3).Style.Fill.BackgroundColor = XLColor.FromArgb(220, 53, 69);
        //                            summaryWs.Cell(1, 3).Style.Font.FontColor = XLColor.White;
        //                            summaryWs.Cell(1, 3).Style.Alignment.Horizontal = XLAlignmentHorizontalValues.Center;

        //                            // Top Summary Metrics Values
        //                            summaryWs.Cell(2, 1).Value = totalRecords;
        //                            summaryWs.Cell(2, 1).Style.Font.Bold = true;
        //                            summaryWs.Cell(2, 1).Style.Alignment.Horizontal = XLAlignmentHorizontalValues.Center;

        //                            summaryWs.Cell(2, 2).Value = successCount;
        //                            summaryWs.Cell(2, 2).Style.Font.Bold = true;
        //                            summaryWs.Cell(2, 2).Style.Alignment.Horizontal = XLAlignmentHorizontalValues.Center;

        //                            summaryWs.Cell(2, 3).Value = failedCount;
        //                            summaryWs.Cell(2, 3).Style.Font.Bold = true;
        //                            summaryWs.Cell(2, 3).Style.Alignment.Horizontal = XLAlignmentHorizontalValues.Center;

        //                            // Detailed Rows Header
        //                            int summaryHeaderRow = 4;
        //                            string[] headers = new string[] {
        //                           "Sr. No", "Status", "Vendor Name", "Father Name", "Contact No",
        //                           "Gender", "DOB", "Address", "State", "City",
        //                           "Bank Name", "Account No", "IFSC Code", "PAN No", "Aadhaar No",
        //                           "GST No", "GST %", "TDS %", "Agent Name", "Legal Name", "Emergency Contact", "Email ID", "E-Shram Card", "Ayushman Card", "Ayushman Card No", "Account Holder Name", "Permanent Pin", "Current Pin"
        //                       };
        //                            for (int i = 0; i < headers.Length; i++)
        //                            {
        //                                var cell = summaryWs.Cell(summaryHeaderRow, i + 1);
        //                                cell.Value = headers[i];
        //                                cell.Style.Font.Bold = true;
        //                                cell.Style.Fill.BackgroundColor = XLColor.FromArgb(52, 58, 64);
        //                                cell.Style.Font.FontColor = XLColor.White;
        //                            }

        //                            // Detailed Rows Data
        //                            int currRow = 5;
        //                            for (int i = 0; i < resultsForExcel.Count; i++)
        //                            {
        //                                var item = resultsForExcel[i];
        //                                bool isRowUploaded = item.IsSuccess || item.Status == "Uploaded" || item.Status == "Updated" || item.Status == "Success" || item.Status == "Inserted";
        //                                string rowStatus = isRowUploaded
        //                                    ? "Uploaded"
        //                                    : (!string.IsNullOrEmpty(item.Message) ? item.Message : (!string.IsNullOrEmpty(item.Status) ? item.Status : "Failed"));

        //                                summaryWs.Cell(currRow, 1).Value = i + 1;
        //                                summaryWs.Cell(currRow, 2).Value = rowStatus;
        //                                summaryWs.Cell(currRow, 3).Value = item.Vendor_Name ?? "";
        //                                summaryWs.Cell(currRow, 4).Value = item.Vendor_FatherName ?? "";
        //                                summaryWs.Cell(currRow, 5).Value = item.Vendor_ContactNo ?? "";
        //                                summaryWs.Cell(currRow, 6).Value = item.Vendor_Gender ?? "";
        //                                summaryWs.Cell(currRow, 7).Value = item.Vendor_DOB ?? "";
        //                                summaryWs.Cell(currRow, 8).Value = item.Vendor_Address ?? "";
        //                                summaryWs.Cell(currRow, 9).Value = item.Vendor_State ?? "";
        //                                summaryWs.Cell(currRow, 10).Value = item.Vendor_City ?? "";
        //                                summaryWs.Cell(currRow, 11).Value = item.Vendor_BankName ?? "";
        //                                summaryWs.Cell(currRow, 12).Value = item.Vendor_AccountNo ?? "";
        //                                summaryWs.Cell(currRow, 13).Value = item.Vendor_IFSCCode ?? "";
        //                                summaryWs.Cell(currRow, 14).Value = item.Vendor_PanNo ?? "";
        //                                summaryWs.Cell(currRow, 15).Value = item.Vendor_AaddharNo ?? "";
        //                                summaryWs.Cell(currRow, 16).Value = item.Vendor_GSTNo ?? "";
        //                                summaryWs.Cell(currRow, 17).Value = item.Vendor_GstPercentage ?? "";
        //                                summaryWs.Cell(currRow, 18).Value = item.Vendor_TdsPercentage ?? "";
        //                                summaryWs.Cell(currRow, 19).Value = item.AgentName ?? "";
        //                                summaryWs.Cell(currRow, 20).Value = item.LegalName ?? "";
        //                                summaryWs.Cell(currRow, 21).Value = item.EmergencyContactNo ?? "";
        //                                summaryWs.Cell(currRow, 22).Value = item.EmailID ?? "";
        //                                summaryWs.Cell(currRow, 23).Value = item.EShramCardNo ?? "";
        //                                summaryWs.Cell(currRow, 24).Value = item.AyushmanCard ?? "";
        //                                summaryWs.Cell(currRow, 25).Value = item.AyushmanCardNo ?? "";
        //                                summaryWs.Cell(currRow, 26).Value = item.AccountHolderName ?? "";
        //                                summaryWs.Cell(currRow, 27).Value = item.PermanentPinCode ?? "";
        //                                summaryWs.Cell(currRow, 28).Value = item.CurrentPinCode ?? "";

        //                                if (isRowUploaded)
        //                                {
        //                                    summaryWs.Cell(currRow, 2).Style.Font.FontColor = XLColor.Green;
        //                                    summaryWs.Cell(currRow, 2).Style.Font.Bold = true;
        //                                }
        //                                else
        //                                {
        //                                    summaryWs.Cell(currRow, 2).Style.Font.FontColor = XLColor.Red;
        //                                    summaryWs.Cell(currRow, 2).Style.Font.Bold = true;
        //                                }

        //                                currRow++;
        //                            }

        //                            summaryWs.Columns().AdjustToContents();
        //                            wb.Save();
        //                        }
        //                    }
        //                }
        //                catch (Exception exWb)
        //                {
        //                    Console.WriteLine("Could not append summary sheet to Excel: " + exWb.Message);
        //                }
        //            });
        //        }
        //    }
        //    catch (Exception ex)
        //    {
        //        Console.WriteLine("Error in UploadVendorExcelAsync: " + ex.Message);
        //        resultList.Add(new VendorUploadRowModel
        //        {
        //            Status = "Failed",
        //            Message = "File parsing/database error: " + ex.Message,
        //            IsSuccess = false
        //        });
        //    }

        //    return resultList;
        //}



        public async Task<IEnumerable<dynamic>> GetVendorAuditLogsAsync(string pk_recId)
        {
            try
            {
                DynamicParameters dynamicParameters = new DynamicParameters();
                dynamicParameters.Add("@pk_recId", pk_recId, DbType.String);

                return DataBaseFactory.QuerySP<dynamic>("Vendor_GetAuditLogById", dynamicParameters, "Vendor_GetAuditLogById").ToList();
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error in GetVendorAuditLogsAsync: " + ex.Message);
                return Enumerable.Empty<dynamic>();
            }
        }

        public async Task<dynamic> GetVendorDashboardSummaryAsync(string companyId, string monthId, string yearId)
        {
            try
            {
                DynamicParameters dynamicParameters = new DynamicParameters();
                dynamicParameters.Add("@fk_companyId", companyId ?? "", DbType.String);
                dynamicParameters.Add("@monthId", monthId ?? "", DbType.String);
                dynamicParameters.Add("@yearId", yearId ?? "", DbType.String);

                var result = DataBaseFactory.QuerySP<dynamic>("LSP_VendorDashboard_GetSummary", dynamicParameters, "VendorDashboard_GetSummary");
                return result?.FirstOrDefault();
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error in GetVendorDashboardSummaryAsync: " + ex.Message);
                return null;
            }
        }

        public async Task<VendorResponseModel> SaveVendorExcelUploadAsync(VendorExcelUploadSaveRequest request, string originalFileName, string savedFileName, string savedFilePath, long fileSize, string? companyId, string? userId)
        {
            try
            {
                DynamicParameters p = new DynamicParameters();
                p.Add("@fk_clientId", request.fk_clientId, DbType.Int64);
                p.Add("@clientName", request.clientName ?? "", DbType.String);
                p.Add("@modelId", request.modelId ?? "", DbType.String);
                p.Add("@modelName", request.modelName ?? "", DbType.String);
                p.Add("@fromDate", string.IsNullOrEmpty(request.fromDate) ? null : request.fromDate, DbType.Date);
                p.Add("@toDate", string.IsNullOrEmpty(request.toDate) ? null : request.toDate, DbType.Date);
                p.Add("@originalFileName", originalFileName ?? "", DbType.String);
                p.Add("@savedFileName", savedFileName ?? "", DbType.String);
                p.Add("@savedFilePath", savedFilePath ?? "", DbType.String);
                p.Add("@fileSize", fileSize, DbType.Int64);
                p.Add("@fk_companyId", companyId ?? "", DbType.String);
                p.Add("@fk_userId", userId ?? "", DbType.String);

                var result = DataBaseFactory.QuerySP<VendorResponseModel>("sp_VendorExcelUpload_Save", p, "sp_VendorExcelUpload_Save").FirstOrDefault();
                return result ?? new VendorResponseModel { IsSuccessfully = false, IsMessage = "Failed to save file upload details." };
            }
            catch (Exception ex)
            {
                return new VendorResponseModel { IsSuccessfully = false, IsMessage = ex.Message };
            }
        }

        public async Task<(int totalCount, IEnumerable<VendorExcelUploadFileModel> list)> GetVendorExcelUploadListAsync(string? companyId, string? searchTerm, int pageIndex = 1, int pageSize = 10)
        {
            try
            {
                DynamicParameters p = new DynamicParameters();
                p.Add("@fk_companyId", companyId ?? "", DbType.String);
                p.Add("@searchTerm", searchTerm ?? "", DbType.String);
                p.Add("@pageIndex", pageIndex, DbType.Int32);
                p.Add("@pageSize", pageSize, DbType.Int32);

                var list = DataBaseFactory.QuerySP<VendorExcelUploadFileModel>("Vendor_Upload_GetFileList", p, "Vendor_Upload_GetFileList")?.ToList() ?? new List<VendorExcelUploadFileModel>();
                int totalCount = list.FirstOrDefault()?.TotalCount ?? list.Count;
                return (totalCount, list);
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error in Vendor_Upload_GetFileList, trying fallback: " + ex.Message);
                try
                {
                    DynamicParameters pFallback = new DynamicParameters();
                    pFallback.Add("@fk_companyId", companyId ?? "", DbType.String);
                    pFallback.Add("@searchTerm", searchTerm ?? "", DbType.String);
                    pFallback.Add("@pageIndex", pageIndex, DbType.Int32);
                    pFallback.Add("@pageSize", pageSize, DbType.Int32);

                    var allList = DataBaseFactory.QuerySP<VendorExcelUploadFileModel>("sp_VendorExcelUpload_GetAll", pFallback, "sp_VendorExcelUpload_GetAll")?.ToList() ?? new List<VendorExcelUploadFileModel>();
                    int totalCount = allList.FirstOrDefault()?.TotalCount ?? allList.Count;
                    return (totalCount, allList);
                }
                catch (Exception ex2)
                {
                    Console.WriteLine("Error in GetVendorExcelUploadListAsync: " + ex2.Message);
                    return (0, Enumerable.Empty<VendorExcelUploadFileModel>());
                }
            }
        }

        public async Task<VendorExcelUploadFileModel?> GetVendorExcelUploadByIdAsync(long id)
        {
            try
            {
                DynamicParameters p = new DynamicParameters();
                p.Add("@File_Id", (int)id, DbType.Int32);

                var result = DataBaseFactory.QuerySP<VendorExcelUploadFileModel>("Vendor_Upload_GetFileById", p, "Vendor_Upload_GetFileById")?.FirstOrDefault();
                if (result == null)
                {
                    DynamicParameters p2 = new DynamicParameters();
                    p2.Add("@pk_id", id, DbType.Int64);
                    result = DataBaseFactory.QuerySP<VendorExcelUploadFileModel>("sp_VendorExcelUpload_GetById", p2, "sp_VendorExcelUpload_GetById")?.FirstOrDefault();
                }
                return result;
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error in GetVendorExcelUploadByIdAsync: " + ex.Message);
                return null;
            }
        }
        public async Task<IEnumerable<VendorRateCardAuditItemModel>> GetVendorRateCardAuditHistoryAsync(string pk_recId)
        {
            try
            {
                DynamicParameters dynamicParameters = new DynamicParameters();
                dynamicParameters.Add("@fk_recId", pk_recId ?? "", DbType.String);

                var list = DataBaseFactory.QuerySP<VendorRateCardAuditItemModel>("LSP_VendorRateCard_GetAuditByVendorId", dynamicParameters, "LSP_VendorRateCard_GetAuditByVendorId");
                return list ?? Enumerable.Empty<VendorRateCardAuditItemModel>();
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error in GetVendorRateCardAuditHistoryAsync: " + ex.Message);
                return Enumerable.Empty<VendorRateCardAuditItemModel>();
            }
        }
        public async Task<IEnumerable<VendorRateCardAuditItemModel>> GetVendorRateCardsAsync(string pk_recId)
        {
            try
            {
                DynamicParameters dynamicParameters = new DynamicParameters();
                dynamicParameters.Add("@fk_recId", pk_recId ?? "", DbType.String);

                var list = DataBaseFactory.QuerySP<VendorRateCardAuditItemModel>("LSP_VendorRateCard_GetByVendorId", dynamicParameters, "LSP_VendorRateCard_GetByVendorId");
                return list ?? Enumerable.Empty<VendorRateCardAuditItemModel>();
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error in GetVendorRateCardsAsync: " + ex.Message);
                return Enumerable.Empty<VendorRateCardAuditItemModel>();
            }
        }


        public async Task<IEnumerable<AuditLogDocumentNameItem>> GetAuditLogDocumentNamesAsync()
        {
            try
            {
                var list = DataBaseFactory.QuerySP<AuditLogDocumentNameItem>(
                    "Usp_UpdateAuditLog_GetDocumentNameList",
                    null,
                    "Usp_UpdateAuditLog_GetDocumentNameList"
                );
                return list ?? Enumerable.Empty<AuditLogDocumentNameItem>();
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error in GetAuditLogDocumentNamesAsync: " + ex.Message);
                return Enumerable.Empty<AuditLogDocumentNameItem>();
            }
        }

        public async Task<IEnumerable<AuditLogItemModel>> GetAuditLogsAsync(AuditLogFilterRequest filter)
        {
            try
            {
                string xmlData = XmlUtility.XmlSerializeToString(filter);
                DynamicParameters dynamicParameters = new DynamicParameters();
                dynamicParameters.Add("@xmlDoc", xmlData, DbType.Xml);

                var list = DataBaseFactory.QuerySP<AuditLogItemModel>(
                    "Usp_UpdateAuditLog_GetAll",
                    dynamicParameters,
                    "Usp_UpdateAuditLog_GetAll"
                );
                return list ?? Enumerable.Empty<AuditLogItemModel>();
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error in GetAuditLogsAsync: " + ex.Message);
                return Enumerable.Empty<AuditLogItemModel>();
            }
        }


        public async Task<IEnumerable<dynamic>> UploadTransactionsAsync(string clientId, string modelId, DateTime fromDate, DateTime toDate, string xmlData, string fileName, string userId, string companyId)
        {
            var p = new DynamicParameters();
            
            p.Add("@ClientID", clientId, DbType.String);
            p.Add("@ModelID", modelId, DbType.String);
            p.Add("@FromDate", fromDate, DbType.Date);
            p.Add("@ToDate", toDate, DbType.Date);
            p.Add("@UploadXML", xmlData, DbType.Xml);
            p.Add("@FileName", fileName ?? "", DbType.String);
            p.Add("@UserId", userId ?? "", DbType.String);
            p.Add("@CompanyId", companyId ?? "", DbType.String);

            var dbResult = DataBaseFactory.QuerySP<dynamic>(
                "USP_ProcessVendorTransactions_Upload", p, "USP_ProcessVendorTransactions_Upload");

            return dbResult ?? Enumerable.Empty<dynamic>();
        }

        //added code 31 Aug 2026 starts

        public async Task<List<VendorFHRIDMappingRow>> UploadVendorFHRIDMappingExcelAsync(IFormFile file, string? companyId = null, string? userId = null)
        {
            var resultList = new List<VendorFHRIDMappingRow>();
            if (file == null || file.Length == 0) return resultList;

            try
            {
                // 1. Physical file saving with filename_date_time naming convention
                string uploadFolder = _configuration?["AppSettings:VendorFHRIDUploads"];
                if (string.IsNullOrEmpty(uploadFolder))
                {
                    uploadFolder = "C:/Candidate/VendorFHRIDUploads";
                }

                if (!Directory.Exists(uploadFolder))
                {
                    Directory.CreateDirectory(uploadFolder);
                }

                string origFileName = Path.GetFileName(file.FileName);
                string fileNameWithoutExt = Path.GetFileNameWithoutExtension(origFileName);
                string ext = Path.GetExtension(origFileName);
                string timestampedFileName = $"{fileNameWithoutExt}_{DateTime.Now:ddMMyyyy_HHmmss}{ext}";
                string physicalPath = Path.Combine(uploadFolder, timestampedFileName);

                using (var fileStream = new FileStream(physicalPath, FileMode.Create))
                {
                    await file.CopyToAsync(fileStream);
                }

                // 2. Read Excel contents and construct XML request
                using var stream = file.OpenReadStream();
                using var workbook = new XLWorkbook(stream);
                var worksheet = workbook.Worksheets.FirstOrDefault();
                if (worksheet == null) return resultList;

                var headerRow = worksheet.Row(1);
                var colMap = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
                foreach (var cell in headerRow.CellsUsed())
                {
                    string headerText = cell.GetValue<string>().Trim().Replace(" ", "").Replace("_", "");
                    if (!string.IsNullOrEmpty(headerText) && !colMap.ContainsKey(headerText))
                    {
                        colMap[headerText] = cell.Address.ColumnNumber;
                    }
                }

                // Check mandatory 4 columns
                bool hasVendor = colMap.ContainsKey("VENDORCODE") || colMap.ContainsKey("CODE") || colMap.ContainsKey("PKRECID") || colMap.ContainsKey("VENDOR");
                bool hasClient = colMap.ContainsKey("CLIENT") || colMap.ContainsKey("CLIENTID") || colMap.ContainsKey("FKCLIENTID") || colMap.ContainsKey("VENDORFKCLIENTID") || colMap.ContainsKey("COSTCENTRE");
                bool hasModel = colMap.ContainsKey("MODEL") || colMap.ContainsKey("MODELID") || colMap.ContainsKey("FKMODELID") || colMap.ContainsKey("VENDORFKMODELID");
                bool hasFhr = colMap.ContainsKey("FHRID") || colMap.ContainsKey("VENDORFHRID") || colMap.ContainsKey("VENDORHFRID") || colMap.ContainsKey("HFRID");

                if (!hasVendor || !hasClient || !hasModel || !hasFhr)
                {
                    var missing = new List<string>();
                    if (!hasVendor) missing.Add("Vendor Code");
                    if (!hasClient) missing.Add("Client");
                    if (!hasModel) missing.Add("Model");
                    if (!hasFhr) missing.Add("FHR ID");

                    resultList.Add(new VendorFHRIDMappingRow
                    {
                        Status = "Failed",
                        Message = $"Invalid Excel Template. Missing required column(s): {string.Join(", ", missing)}"
                    });
                    return resultList;
                }

                string GetVal(IXLRow r, string[] keys, int fallbackCol)
                {
                    try
                    {
                        foreach (var k in keys)
                        {
                            if (colMap.TryGetValue(k, out int colIdx))
                            {
                                var cell = r.Cell(colIdx);
                                if (cell == null || cell.IsEmpty()) continue;
                                string val = cell.GetFormattedString()?.Trim() ?? cell.Value.ToString().Trim();
                                if (!string.IsNullOrEmpty(val)) return val;
                            }
                        }
                        if (fallbackCol > 0)
                        {
                            var cell = r.Cell(fallbackCol);
                            if (cell != null && !cell.IsEmpty())
                            {
                                return cell.GetFormattedString()?.Trim() ?? cell.Value.ToString().Trim();
                            }
                        }
                    }
                    catch
                    {
                        // fallback
                    }
                    return string.Empty;
                }

                int lastRowNumber = worksheet.LastRowUsed()?.RowNumber() ?? 0;
                var xmlRequest = new VendorFHRIDMappingXmlRequest();

                for (int rowNumber = 2; rowNumber <= lastRowNumber; rowNumber++)
                {
                    var row = worksheet.Row(rowNumber);
                    string vendorCode = GetVal(row, new[] { "VENDORCODE", "CODE", "PKRECID", "VENDOR" }, 1);
                    string client = GetVal(row, new[] { "CLIENT", "CLIENTID", "FKCLIENTID", "VENDORFKCLIENTID", "COSTCENTRE" }, 2);
                    string model = GetVal(row, new[] { "MODEL", "MODELID", "FKMODELID", "VENDORFKMODELID" }, 3);
                    string fhrId = GetVal(row, new[] { "FHRID", "VENDORFHRID", "VENDORHFRID", "HFRID" }, 4);

                    // Skip completely empty rows
                    if (string.IsNullOrWhiteSpace(vendorCode) && string.IsNullOrWhiteSpace(client) && string.IsNullOrWhiteSpace(model) && string.IsNullOrWhiteSpace(fhrId))
                    {
                        continue;
                    }

                    xmlRequest.Rows.Add(new VendorFHRIDMappingXmlItem
                    {
                        VendorCode = vendorCode,
                        Client = client,
                        Model = model,
                        FHRID = fhrId
                    });
                }

                if (xmlRequest.Rows.Count == 0)
                {
                    resultList.Add(new VendorFHRIDMappingRow
                    {
                        Status = "Failed",
                        Message = "No valid data rows found in Excel file."
                    });
                    return resultList;
                }

                // 3. Serialize to XML
                string xmlData = XmlUtility.XmlSerializeToString(xmlRequest);
                if (xmlData.StartsWith("<?xml"))
                {
                    int idx = xmlData.IndexOf("?>");
                    if (idx != -1)
                    {
                        xmlData = xmlData.Substring(idx + 2).Trim();
                    }
                }

                // 4. Call Stored Procedure
                var p = new DynamicParameters();
                p.Add("@Doc", xmlData, DbType.Xml);
                p.Add("@FileName", timestampedFileName, DbType.String);
                p.Add("@FilePath", physicalPath, DbType.String);
                p.Add("@fk_companyId", companyId ?? "", DbType.String);
                p.Add("@fk_userId", userId ?? "", DbType.String);

                var dbResult = DataBaseFactory.QuerySP<VendorFHRIDMappingRow>(
                    "USP_Vendor_UploadFHRIDMapping",
                    p,
                    "USP_Vendor_UploadFHRIDMapping"
                );

                if (dbResult != null && dbResult.Any())
                {
                    resultList = dbResult.ToList();
                }
                else
                {
                    resultList.Add(new VendorFHRIDMappingRow
                    {
                        Status = "Uploaded",
                        Message = "Vendor FHR ID mapping records processed successfully."
                    });
                }

                // 5. Multi-Tab Excel: Background Task so that 8,000+ rows return instantly to the UI
                var resultsForExcel = resultList.ToList();
                _ = Task.Run(() =>
                {
                    try
                    {
                        using (var wb = new XLWorkbook(physicalPath))
                        {
                            string summarySheetName = "Upload Summary & Status";
                            var existingSummary = wb.Worksheets.FirstOrDefault(w => w.Name.Equals(summarySheetName, StringComparison.OrdinalIgnoreCase));
                            if (existingSummary != null)
                            {
                                wb.Worksheets.Delete(existingSummary.Name);
                            }

                            var summaryWs = wb.Worksheets.Add(summarySheetName);

                            int totalCount = resultsForExcel.Count;
                            int successCount = resultsForExcel.Count(r => r.Status == "Inserted" || r.Status == "Updated" || r.Status == "Already Exists" || r.Status == "Uploaded" || r.Status == "Success");
                            int failedCount = resultsForExcel.Count(r => r.Status == "Failed");

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
                            var sourceWs = wb.Worksheets.FirstOrDefault(w => !w.Name.Equals("Upload Summary & Status", StringComparison.OrdinalIgnoreCase))
                                           ?? wb.Worksheet(1);

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

                            // Detailed Rows Data
                            int sourceLastRow = sourceWs.LastRowUsed()?.RowNumber() ?? 1;
                            int currRow = 5;

                            for (int r = 2; r <= sourceLastRow; r++)
                            {
                                int dataIdx = r - 2;
                                summaryWs.Cell(currRow, 1).Value = dataIdx + 1;

                                if (dataIdx < resultsForExcel.Count)
                                {
                                    var item = resultsForExcel[dataIdx];
                                    string statusDisplay = "Uploaded";
                                    if (item.Status == "Failed" || item.Status == "Error")
                                    {
                                        statusDisplay = $"Failed - {(string.IsNullOrEmpty(item.Message) ? "Validation error" : item.Message)}";
                                        summaryWs.Cell(currRow, 2).Value = statusDisplay;
                                        summaryWs.Cell(currRow, 2).Style.Font.FontColor = XLColor.Red;
                                        summaryWs.Cell(currRow, 2).Style.Font.Bold = true;
                                    }
                                    else if (item.Status == "Already Exists" || item.Status == "Skipped")
                                    {
                                        statusDisplay = "Already Exists";
                                        summaryWs.Cell(currRow, 2).Value = statusDisplay;
                                        summaryWs.Cell(currRow, 2).Style.Font.FontColor = XLColor.FromArgb(217, 119, 6);
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
                        Console.WriteLine("Could not append summary sheet to Excel: " + exWb.Message);
                    }
                });
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error in UploadVendorFHRIDMappingExcelAsync: " + ex.Message);
                resultList.Add(new VendorFHRIDMappingRow
                {
                    Status = "Failed",
                    Message = "File parsing/database error: " + ex.Message
                });
            }

            return resultList;
        }

        public async Task<IEnumerable<VendorFHRIDFileModel>> GetVendorFHRIDFilesAsync(string? companyId)
        {
            try
            {
                var p = new DynamicParameters();
                p.Add("@fk_companyId", companyId ?? "", DbType.String);

                var files = DataBaseFactory.QuerySP<VendorFHRIDFileModel>(
                    "USP_Vendor_GetFHRIDUploadedFiles",
                    p,
                    "USP_Vendor_GetFHRIDUploadedFiles"
                );

                return files ?? Enumerable.Empty<VendorFHRIDFileModel>();
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error in GetVendorFHRIDFilesAsync: " + ex.Message);
                return Enumerable.Empty<VendorFHRIDFileModel>();
            }
        }

        public async Task<VendorFHRIDFileModel?> GetVendorFHRIDFileByIdAsync(int id)
        {
            try
            {
                var p = new DynamicParameters();
                p.Add("@File_Id", id, DbType.Int32);
                p.Add("@Id", id, DbType.Int32);

                var files = DataBaseFactory.QuerySP<VendorFHRIDFileModel>(
                    "USP_Vendor_GetFHRIDFileById",
                    p,
                    "USP_Vendor_GetFHRIDFileById"
                );

                return files?.FirstOrDefault();
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error in GetVendorFHRIDFileByIdAsync: " + ex.Message);
                return null;
            }
        }

        public async Task<IEnumerable<VendorRateCardFileModel>> GetRateCardUploadedFilesAsync(string? companyId)
        {
            try
            {
                var p = new DynamicParameters();
                p.Add("@fk_companyId", companyId ?? "", DbType.String);

                var files = DataBaseFactory.QuerySP<VendorRateCardFileModel>(
                    "USP_Vendor_GetRateCardUploadedFiles",
                    p,
                    "USP_Vendor_GetRateCardUploadedFiles"
                );

                return files ?? Enumerable.Empty<VendorRateCardFileModel>();
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error in GetRateCardUploadedFilesAsync: " + ex.Message);
                return Enumerable.Empty<VendorRateCardFileModel>();
            }
        }

        public async Task<VendorRateCardFileModel?> GetRateCardFileByIdAsync(int id)
        {
            try
            {
                var p = new DynamicParameters();
                p.Add("@File_Id", id, DbType.Int32);
                p.Add("@Id", id, DbType.Int32);

                var files = DataBaseFactory.QuerySP<VendorRateCardFileModel>(
                    "USP_Vendor_GetRateCardFileById",
                    p,
                    "USP_Vendor_GetRateCardFileById"
                );

                return files?.FirstOrDefault();
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error in GetRateCardFileByIdAsync: " + ex.Message);
                return null;
            }
        }
        public async Task<dynamic> GetTransactionFileByIdAsync(int id)
        {
            try
            {
                var p = new DynamicParameters();
                p.Add("@File_Id", id, DbType.Int32);

                var result = DataBaseFactory.QuerySP<dynamic>("USP_Vendor_GetTransactionFileById", p, "USP_Vendor_GetTransactionFileById");
                return result?.FirstOrDefault();
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error in GetTransactionFileByIdAsync: " + ex.Message);
                return null;
            }
        }

        public async Task<IEnumerable<dynamic>> GetTransactionUploadedFilesAsync(string companyId)
        {
            try
            {
                var p = new DynamicParameters();
                p.Add("@fk_companyId", companyId ?? "", DbType.String);

                var files = DataBaseFactory.QuerySP<dynamic>(
                    "USP_Vendor_GetTransactionUploadedFiles",
                    p,
                    "USP_Vendor_GetTransactionUploadedFiles"
                );

                return files ?? Enumerable.Empty<dynamic>();
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error in GetTransactionUploadedFilesAsync: " + ex.Message);
                return Enumerable.Empty<dynamic>();
            }
        }
        //added code 31 Aug 2026 ends
        public async Task<IEnumerable<dynamic>> GetVendorTransactionRangesAsync(int clientId, int modelId)
        {
            var parameters = new DynamicParameters();
            parameters.Add("@ClientID", clientId);
            parameters.Add("@ModelID", modelId);
            return await DataBaseFactory.QuerySPAsync<dynamic>("USP_GetVendorTransactionRanges", parameters, "Vendor - GetVendorTransactionRanges");
        }

        public async Task<IEnumerable<dynamic>> GetTransactionTemplateDataAsync(int clientId, int modelId)
        {
            var parameters = new DynamicParameters();
            parameters.Add("@ClientID", clientId);
            parameters.Add("@ModelID", modelId);
            return await DataBaseFactory.QuerySPAsync<dynamic>("USP_GetVendorTransactionTemplateData", parameters, "Vendor - GetTransactionTemplateData");
        }
        public async Task<IEnumerable<dynamic>> SearchVendorsAsync(string searchTerm)
        {
            var parameters = new DynamicParameters();
            parameters.Add("@SearchTerm", searchTerm);
            return await DataBaseFactory.QuerySPAsync<dynamic>("USP_SearchVendors", parameters, "Vendor - SearchVendors");
        }

        public async Task<(int totalCount, IEnumerable<dynamic> transactions)> GetVendorPaymentTransactionsListAsync(int clientId, int modelId, string? locationId, string? transactionRange, string? vendorCode, string? searchTerm, int pageIndex, int pageSize)
        {
            var parameters = new DynamicParameters();
            parameters.Add("@ClientID", clientId);
            parameters.Add("@ModelID", modelId);
            parameters.Add("@LocationID", locationId);
            parameters.Add("@TransactionRange", transactionRange);
            parameters.Add("@VendorCode", vendorCode);
            parameters.Add("@SearchTerm", searchTerm);
            parameters.Add("@PageIndex", pageIndex);
            parameters.Add("@PageSize", pageSize);

            var transactions = await DataBaseFactory.QuerySPAsync<dynamic>("USP_GetVendorPaymentTransactions_List", parameters, "Vendor - GetVendorPaymentTransactions_List");
            int totalCount = transactions.FirstOrDefault()?.TotalRecords ?? 0;
            return (totalCount, transactions);
        }

        public async Task<dynamic> GetVendorFHRIDMappingStatsAsync(string companyId)
        {
            try
            {
                var param = new DynamicParameters();
                param.Add("@fk_companyId", companyId);

                var result = await DataBaseFactory.QuerySPAsync<dynamic>(
                    "Vendor_GetFHRIDMappingStats",
                    param,
                    "VendorRateCard - GetFHRIDMappingStats"
                );

                var stats = result?.FirstOrDefault();

                if (stats == null)
                {
                    return new
                    {
                        Vendor_TotalCount = 0,
                        Vendor_MappedFHRID = 0,
                        Vendor_UnmappedFHRID = 0
                    };
                }

                return stats;
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error in GetVendorFHRIDMappingStatsAsync: " + ex.Message);
                return new
                {
                    Vendor_TotalCount = 0,
                    Vendor_MappedFHRID = 0,
                    Vendor_UnmappedFHRID = 0
                };
            }
        }

        public async Task<IEnumerable<VendorListModel>> GetVendorMappedUnmappedListAsync(string companyId, bool isMapped)
        {
            try
            {
                var param = new DynamicParameters();
                param.Add("@fk_companyId", companyId);
                param.Add("@IsMapped", isMapped ? 1 : 0);

                var list = await DataBaseFactory.QuerySPAsync<VendorListModel>(
                    "Vendor_GetFHRIDMappedUnmappedList",
                    param,
                    "VendorRateCard - GetVendorMappedUnmappedList"
                );
                return list ?? Enumerable.Empty<VendorListModel>();
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error in GetVendorMappedUnmappedListAsync: " + ex.Message);
                return Enumerable.Empty<VendorListModel>();
            }
        }
        public async Task<dynamic> UpdateVendorStatusAsync(string pkRecId, int statusId)
        {
            try
            {
                var dynamicParameters = new DynamicParameters();
                dynamicParameters.Add("@pk_recId", pkRecId);
                dynamicParameters.Add("@OnboardFormStatusId", statusId);

                using var conn = DataBaseFactory.ConnString();
                var result = await conn.QueryFirstOrDefaultAsync<dynamic>("Vendor_UpdateStatus", dynamicParameters, commandType: CommandType.StoredProcedure);
                return result;
            }
            catch (Exception ex)
            {
                throw;
            }
        }

        public async Task<IEnumerable<dynamic>> GetVendorTemplateConfigAsync(int clientId, int modelId)
        {
            var p = new DynamicParameters();
            p.Add("@ClientID", clientId, DbType.Int32);
            p.Add("@ModelID", modelId, DbType.Int32);
            var result = DataBaseFactory.QuerySP<dynamic>("USP_GetVendorTemplateConfig", p, "USP_GetVendorTemplateConfig");
            return await Task.FromResult(result ?? Enumerable.Empty<dynamic>());
        }

        public async Task<string> GetClientNameAsync(int clientId)
        {
            var p = new DynamicParameters();
            p.Add("@ClientID", clientId, DbType.Int32);
            var result = DataBaseFactory.QuerySP<dynamic>("USP_GetClientName", p, "USP_GetClientName")?.FirstOrDefault();
            if (result != null && ((IDictionary<string, object>)result).ContainsKey("ClientName"))
            {
                return Convert.ToString(((IDictionary<string, object>)result)["ClientName"]) ?? "";
            }
            return "";
        }

        public async Task<string> GetModelNameAsync(int modelId)
        {
            var p = new DynamicParameters();
            p.Add("@ModelID", modelId, DbType.Int32);
            var result = DataBaseFactory.QuerySP<dynamic>("USP_GetModelName", p, "USP_GetModelName")?.FirstOrDefault();
            if (result != null && ((IDictionary<string, object>)result).ContainsKey("Name"))
            {
                return Convert.ToString(((IDictionary<string, object>)result)["Name"]) ?? "";
            }
            return "";
        }



        public async Task<(int totalCount, IEnumerable<VendorVerificationListModel> vendors)> GetVendorDownloadVerificationListAsync(int pageIndex, int pageSize, string companyId,string userId, string searchTerm)
        {
            try
            {
                DynamicParameters dynamicParameters = new DynamicParameters();
                dynamicParameters.Add("@pageindex", pageIndex, DbType.Int32);
                dynamicParameters.Add("@pagesize", pageSize, DbType.Int32);
                dynamicParameters.Add("@searchTerm", searchTerm ?? "", DbType.String);
                dynamicParameters.Add("@fk_companyId", companyId, DbType.String);
                dynamicParameters.Add("@fk_userId", userId, DbType.String);

                var tuple = DataBaseFactory.QueryMultipleSP<dynamic, VendorVerificationListModel>("Vendor_GetVerificationList", dynamicParameters, "Vendor_GetVerificationList");
                if (tuple == null || tuple.Item2 == null)
                    return (0, Enumerable.Empty<VendorVerificationListModel>());

                int totalCount = 0;
                if (tuple.Item1 is IEnumerable<dynamic> countList && countList.Any())
                {
                    var firstRow = (IDictionary<string, object>)countList.First();
                    if (firstRow.ContainsKey("TotalCount"))
                    {
                        totalCount = Convert.ToInt32(firstRow["TotalCount"]);
                    }
                }

                return (totalCount, tuple.Item2.ToList());
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error in GetVendorDownloadListAsync: " + ex.Message);
                return (0, Enumerable.Empty<VendorVerificationListModel>());
            }
        }


    }
}

