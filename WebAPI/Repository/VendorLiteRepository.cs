using Dapper;
using HRMSWebAPI.Helper;
using HRMSWebAPI.Models;
using System.Data;

namespace HRMSWebAPI.Repository
{
    public class VendorLiteRepository : IVendorLiteRepository
    {
        // ── INSERT ──────────────────────────────────────────────────────────────
        public async Task<VendorLiteResponseModel> InsertVendorLiteAsync(
            VendorLiteModel model, string userId, string companyId, string locationId)
        {
            try
            {
                string xmlData = XmlUtility.XmlSerializeToString(model);

                var p = new DynamicParameters();
                p.Add("@xmlDoc",       xmlData,    DbType.Xml);
                p.Add("@fk_companyId", companyId,  DbType.String);
                p.Add("@fk_userId",    userId,     DbType.String);
                p.Add("@fk_locId",     locationId, DbType.String);

                var result = DataBaseFactory.QuerySP<VendorLiteResponseModel>(
                    "VendorLite_Ins", p, "VendorLite_Ins").FirstOrDefault();

                return result ?? new VendorLiteResponseModel
                {
                    IsSuccessfully = false,
                    IsMessage = "Failed to insert vendor."
                };
            }
            catch (Exception ex)
            {
                return new VendorLiteResponseModel { IsSuccessfully = false, IsMessage = ex.Message };
            }
        }

        // ── UPDATE ──────────────────────────────────────────────────────────────
        public async Task<VendorLiteResponseModel> UpdateVendorLiteAsync(
            VendorLiteModel model, string userId, string companyId)
        {
            try
            {
                string xmlData = XmlUtility.XmlSerializeToString(model);

                var p = new DynamicParameters();
                p.Add("@xmlDoc",       xmlData,   DbType.Xml);
                p.Add("@fk_companyId", companyId, DbType.String);
                p.Add("@fk_userId",    userId,    DbType.String);

                var result = DataBaseFactory.QuerySP<VendorLiteResponseModel>(
                    "VendorLite_Upd", p, "VendorLite_Upd").FirstOrDefault();

                return result ?? new VendorLiteResponseModel
                {
                    IsSuccessfully = false,
                    IsMessage = "Failed to update vendor."
                };
            }
            catch (Exception ex)
            {
                return new VendorLiteResponseModel { IsSuccessfully = false, IsMessage = ex.Message };
            }
        }

        // ── GET BY ID ────────────────────────────────────────────────────────────
        public async Task<VendorLiteModel?> GetVendorLiteByIdAsync(string pk_recId)
        {
            try
            {
                var p = new DynamicParameters();
                p.Add("@pk_recId", pk_recId, DbType.String);

                return DataBaseFactory.QuerySP<VendorLiteModel>(
                    "VendorLite_GetById", p, "VendorLite_GetById").FirstOrDefault();
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error in GetVendorLiteByIdAsync: " + ex.Message);
                return null;
            }
        }

        // ── GET ALL (GRID) ───────────────────────────────────────────────────────
        public async Task<(int totalCount, IEnumerable<VendorLiteModel> vendors)> GetAllVendorLiteAsync(
            int pageIndex, int pageSize, string companyId, string searchTerm)
        {
            try
            {
                var p = new DynamicParameters();
                p.Add("@pageIndex",    pageIndex,  DbType.Int32);
                p.Add("@pageSize",     pageSize,   DbType.Int32);
                p.Add("@fk_companyId", companyId,  DbType.String);
                p.Add("@searchTerm",   searchTerm, DbType.String);

                var tuple = DataBaseFactory.QueryMultipleSP<dynamic, VendorLiteModel>(
                    "VendorLite_SelForGrid", p, "VendorLite_SelForGrid");

                if (tuple == null || tuple.Item2 == null)
                    return (0, Enumerable.Empty<VendorLiteModel>());

                int totalCount = 0;
                if (tuple.Item1 is IEnumerable<dynamic> countList && countList.Any())
                {
                    var firstRow = (IDictionary<string, object>)countList.First();
                    if (firstRow.ContainsKey("TotalCount"))
                        totalCount = Convert.ToInt32(firstRow["TotalCount"]);
                }

                return (totalCount, tuple.Item2.ToList());
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error in GetAllVendorLiteAsync: " + ex.Message);
                return (0, Enumerable.Empty<VendorLiteModel>());
            }
        }

        // ── SAVE DOCUMENT ────────────────────────────────────────────────────────
        public async Task<VendorLiteResponseModel> SaveVendorDocumentAsync(
            VendorDocumentModel doc, string userId, string companyId)
        {
            try
            {
                string xmlData = XmlUtility.XmlSerializeToString(doc);

                var p = new DynamicParameters();
                p.Add("@xmlDoc",       xmlData,   DbType.Xml);
                p.Add("@fk_companyId", companyId, DbType.String);
                p.Add("@fk_userId",    userId,    DbType.String);

                var result = DataBaseFactory.QuerySP<VendorLiteResponseModel>(
                    "VendorDocument_Ins", p, "VendorDocument_Ins").FirstOrDefault();

                return result ?? new VendorLiteResponseModel
                {
                    IsSuccessfully = false,
                    IsMessage = "Document save failed."
                };
            }
            catch (Exception ex)
            {
                return new VendorLiteResponseModel { IsSuccessfully = false, IsMessage = ex.Message };
            }
        }

        // ── GET DOCUMENTS BY VENDOR ID ───────────────────────────────────────────
        public async Task<IEnumerable<VendorDocumentModel>> GetVendorDocumentsByVendorIdAsync(
            string vendorId)
        {
            try
            {
                var p = new DynamicParameters();
                p.Add("@fk_vendorId", vendorId, DbType.String);

                return DataBaseFactory.QuerySP<VendorDocumentModel>(
                    "VendorDocument_GetByVendorId", p, "VendorDocument_GetByVendorId")
                    ?? Enumerable.Empty<VendorDocumentModel>();
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error in GetVendorDocumentsByVendorIdAsync: " + ex.Message);
                return Enumerable.Empty<VendorDocumentModel>();
            }
        }

        // ── DELETE DOCUMENT (soft) ───────────────────────────────────────────────
        public async Task<VendorLiteResponseModel> DeleteVendorDocumentAsync(
            long pk_docId, string userId)
        {
            try
            {
                var p = new DynamicParameters();
                p.Add("@pk_docId",  pk_docId, DbType.Int64);
                p.Add("@fk_userId", userId,   DbType.String);

                var result = DataBaseFactory.QuerySP<VendorLiteResponseModel>(
                    "VendorDocument_Del", p, "VendorDocument_Del").FirstOrDefault();

                return result ?? new VendorLiteResponseModel
                {
                    IsSuccessfully = false,
                    IsMessage = "Delete failed."
                };
            }
            catch (Exception ex)
            {
                return new VendorLiteResponseModel { IsSuccessfully = false, IsMessage = ex.Message };
            }
        }

        // ── GET DOCUMENT BY ID ───────────────────────────────────────────────────
        public async Task<VendorDocumentModel?> GetVendorDocumentByIdAsync(long pk_docId)
        {
            try
            {
                using var conn = DataBaseFactory.ConnString();
                var sql = "SELECT * FROM Vendor_Document WHERE pk_docId = @pk_docId AND IsActive = 1";
                return conn.QueryFirstOrDefault<VendorDocumentModel>(sql, new { pk_docId });
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error in GetVendorDocumentByIdAsync: " + ex.Message);
                return null;
            }
        }
    }
}
