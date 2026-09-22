using System.Collections.Generic;
using System.Threading.Tasks;
using HRMSWebAPI.Models;
using System;
using Microsoft.AspNetCore.Http;

namespace HRMSWebAPI.Repository
{
    public interface IVendorRepository
    {
        Task<dynamic> UpdateVendorStatusAsync(string pkRecId, int statusId);
        Task<dynamic> GetVendorFHRIDMappingStatsAsync(string companyId);
        Task<IEnumerable<VendorListModel>> GetVendorMappedUnmappedListAsync(string companyId, bool isMapped);
        Task<IEnumerable<dynamic>> UploadRateCardAsync(VendorRateCardUploadRequest request, string userId, string companyId, string locationId, string filePath = null);
        Task<(int totalCount, IEnumerable<VendorRateCardModel> list)> GetVendorListAsync(int pageIndex, int pageSize, string companyId, string searchTerm);
        Task<VendorResponseModel> UpdateVendorAsync(VendorModel model, string userId, string companyId);
        Task<VendorResponseModel> DeleteVendorAsync(string pk_recId);
        Task<VendorModel?> GetVendorByIdAsync(string pk_recId);
        Task<(int totalCount, IEnumerable<VendorModel> vendors)> GetAllVendorsAsync(int pageIndex, int pageSize, string companyId, string searchTerm = "");
        
        Task<IEnumerable<dynamic>> GetVendorAuditLogsAsync(string pk_recId);
        Task<dynamic> GetVendorDashboardSummaryAsync(string companyId, string monthId, string yearId);
        Task<VendorResponseModel> SaveVendorExcelUploadAsync(VendorExcelUploadSaveRequest request, string originalFileName, string savedFileName, string savedFilePath, long fileSize, string? companyId, string? userId);
      

        Task<IEnumerable<VendorRateCardAuditItemModel>> GetVendorRateCardAuditHistoryAsync(string pk_recId);
        Task<IEnumerable<VendorRateCardAuditItemModel>> GetVendorRateCardsAsync(string pk_recId);
        Task<IEnumerable<AuditLogDocumentNameItem>> GetAuditLogDocumentNamesAsync();
        Task<IEnumerable<AuditLogItemModel>> GetAuditLogsAsync(AuditLogFilterRequest filter);
        Task<VendorResponseModel> InsertVendorAsync(VendorModel model, string userId, string companyId, string locationId);
        Task<(int totalCount, IEnumerable<VendorFHRIDHistoryModel> list)> GetVendorFHRIDHistoryAsync(string pk_recId, int pageIndex, int pageSize);
        Task<IEnumerable<dynamic>> GetFHRIDsAsync(string clientId, string modelId, string companyId);

        Task<IEnumerable<dynamic>> UploadTransactionsAsync(string clientId, string modelId, DateTime fromDate, DateTime toDate, string xmlData, string fileName, string userId, string companyId);
        Task<IEnumerable<dynamic>> GetTransactionUploadedFilesAsync(string companyId);
        Task<dynamic> GetTransactionFileByIdAsync(int id);

        //code added 31 Aug 2026 starts
        Task<List<VendorFHRIDMappingRow>> UploadVendorFHRIDMappingExcelAsync(IFormFile file, string? companyId = null, string? userId = null);
        Task<IEnumerable<VendorFHRIDFileModel>> GetVendorFHRIDFilesAsync(string? companyId);
        Task<VendorFHRIDFileModel?> GetVendorFHRIDFileByIdAsync(int id);
        Task<IEnumerable<VendorRateCardFileModel>> GetRateCardUploadedFilesAsync(string? companyId);
        Task<VendorRateCardFileModel?> GetRateCardFileByIdAsync(int id);
        //code added 31 Aug 2026 ends

        Task<(int totalCount, IEnumerable<VendorExcelUploadFileModel> list)> GetVendorExcelUploadListAsync(string? companyId, string? searchTerm, int pageIndex = 1, int pageSize = 10);
        Task<VendorExcelUploadFileModel?> GetVendorExcelUploadByIdAsync(long id);
        Task<List<VendorUploadRowModel>> UploadVendorExcelAsync(IFormFile file, string? companyId = null, string? userId = null);
    Task<IEnumerable<dynamic>> GetVendorTransactionRangesAsync(int clientId, int modelId);
        Task<IEnumerable<dynamic>> GetTransactionTemplateDataAsync(int clientId, int modelId);
        Task<IEnumerable<dynamic>> SearchVendorsAsync(string searchTerm);
        Task<(int totalCount, IEnumerable<dynamic> transactions)> GetVendorPaymentTransactionsListAsync(int clientId, int modelId, string? locationId, string? transactionRange, string? vendorCode, string? searchTerm, int pageIndex, int pageSize);

        Task<IEnumerable<dynamic>> GetVendorTemplateConfigAsync(int clientId, int modelId);
        Task<string> GetClientNameAsync(int clientId);
        Task<string> GetModelNameAsync(int modelId);

        Task<(int totalCount, IEnumerable<VendorVerificationListModel> vendors)> GetVendorDownloadVerificationListAsync(int pageIndex, int pageSize, string companyId, string userId, string searchTerm = "");



    }
}





