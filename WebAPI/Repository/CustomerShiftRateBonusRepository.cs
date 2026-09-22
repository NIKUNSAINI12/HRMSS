using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using System.Threading.Tasks;
using Dapper;
using HRMSWebAPI.Helper;
using HRMSWebAPI.Models;

namespace HRMSWebAPI.Repository
{
    public class CustomerShiftRateBonusRepository : ICustomerShiftRateBonusRepository
    {
        public async Task<Result> InsertAsync(CustomerShiftRateBonusModel model, string userId, string locationId, string companyId)
        {
            return await Task.Run(() =>
            {
                try
                {
                    CustomerShiftRateBonusDataSet dataset = new CustomerShiftRateBonusDataSet
                    {
                        CustomerShiftRateBonus = model
                    };

                    string xmlData = XmlUtility.XmlSerializeToString(dataset);
                    if (xmlData.StartsWith("<?xml"))
                    {
                        int idx = xmlData.IndexOf("?>");
                        if (idx != -1)
                            xmlData = xmlData.Substring(idx + 2).Trim();
                    }

                    DynamicParameters dynamicParameters = new DynamicParameters();
                    dynamicParameters.Add("@Doc", xmlData, DbType.Xml);
                    dynamicParameters.Add("@fk_companyId", companyId ?? "", DbType.String);
                    dynamicParameters.Add("@fk_userId", userId ?? "", DbType.String);
                    dynamicParameters.Add("@fk_locId", locationId ?? "", DbType.String);

                    var result = DataBaseFactory.QuerySP<CustomerShiftRateBonusSpResult>("USP_Customer_ShiftRateBonus_Ins", dynamicParameters, "CustomerShiftRateBonus_Ins");
                    var first = result?.FirstOrDefault();

                    if (first != null && first.IsSuccess == 1)
                    {
                        return new Result { IsSuccessfull = true, Message = first.Message ?? "Customer Shift Rate & Bonus added successfully." };
                    }

                    return new Result { IsSuccessfull = false, Message = first?.Message ?? "Failed to add Customer Shift Rate & Bonus." };
                }
                catch (Exception ex)
                {
                    return new Result { IsSuccessfull = false, Message = ex.Message };
                }
            });
        }

        public async Task<Result> BulkInsertAsync(List<CustomerShiftRateBonusModel> list, string userId, string locationId, string companyId)
        {
            return await Task.Run(() =>
            {
                try
                {
                    if (list == null || list.Count == 0)
                    {
                        return new Result { IsSuccessfull = false, Message = "No records to upload." };
                    }

                    CustomerShiftRateBonusBulkDataSet dataset = new CustomerShiftRateBonusBulkDataSet
                    {
                        CustomerShiftRateBonusList = list
                    };

                    string xmlData = XmlUtility.XmlSerializeToString(dataset);
                    if (xmlData.StartsWith("<?xml"))
                    {
                        int idx = xmlData.IndexOf("?>");
                        if (idx != -1)
                            xmlData = xmlData.Substring(idx + 2).Trim();
                    }

                    DynamicParameters dynamicParameters = new DynamicParameters();
                    dynamicParameters.Add("@Doc", xmlData, DbType.Xml);
                    dynamicParameters.Add("@fk_companyId", companyId ?? "", DbType.String);
                    dynamicParameters.Add("@fk_userId", userId ?? "", DbType.String);
                    dynamicParameters.Add("@fk_locId", locationId ?? "", DbType.String);

                    var result = DataBaseFactory.QuerySP<CustomerShiftRateBonusBulkResult>("USP_Customer_ShiftRateBonus_BulkIns", dynamicParameters, "CustomerShiftRateBonus_BulkIns");
                    var first = result?.FirstOrDefault();

                    if (first != null && first.IsSuccess == 1)
                    {
                        return new Result { IsSuccessfull = true, Message = first.Message ?? "Bulk upload processed successfully." };
                    }

                    return new Result { IsSuccessfull = false, Message = first?.Message ?? "Failed to process bulk upload." };
                }
                catch (Exception ex)
                {
                    return new Result { IsSuccessfull = false, Message = ex.Message };
                }
            });
        }

        public async Task<Result> UpdateAsync(CustomerShiftRateBonusModel model, string userId, string locationId, string companyId)
        {
            return await Task.Run(() =>
            {
                try
                {
                    CustomerShiftRateBonusDataSet dataset = new CustomerShiftRateBonusDataSet
                    {
                        CustomerShiftRateBonus = model
                    };

                    string xmlData = XmlUtility.XmlSerializeToString(dataset);
                    if (xmlData.StartsWith("<?xml"))
                    {
                        int idx = xmlData.IndexOf("?>");
                        if (idx != -1)
                            xmlData = xmlData.Substring(idx + 2).Trim();
                    }

                    DynamicParameters dynamicParameters = new DynamicParameters();
                    dynamicParameters.Add("@Doc", xmlData, DbType.Xml);
                    dynamicParameters.Add("@fk_companyId", companyId ?? "", DbType.String);
                    dynamicParameters.Add("@fk_userId", userId ?? "", DbType.String);
                    dynamicParameters.Add("@fk_locId", locationId ?? "", DbType.String);

                    var result = DataBaseFactory.QuerySP<CustomerShiftRateBonusSpResult>("USP_Customer_ShiftRateBonus_Upd", dynamicParameters, "CustomerShiftRateBonus_Upd");
                    var first = result?.FirstOrDefault();

                    if (first != null && first.IsSuccess == 1)
                    {
                        return new Result { IsSuccessfull = true, Message = first.Message ?? "Customer Shift Rate & Bonus updated successfully." };
                    }

                    return new Result { IsSuccessfull = false, Message = first?.Message ?? "Failed to update Customer Shift Rate & Bonus." };
                }
                catch (Exception ex)
                {
                    return new Result { IsSuccessfull = false, Message = ex.Message };
                }
            });
        }

        public async Task<Result> DeleteAsync(long id, string userId, string companyId)
        {
            return await Task.Run(() =>
            {
                try
                {
                    DynamicParameters dynamicParameters = new DynamicParameters();
                    dynamicParameters.Add("@pk_id", id, DbType.Int64);
                    dynamicParameters.Add("@fk_userId", userId ?? "", DbType.String);
                    dynamicParameters.Add("@fk_companyId", companyId ?? "", DbType.String);

                    var result = DataBaseFactory.QuerySP<CustomerShiftRateBonusSpResult>("USP_Customer_ShiftRateBonus_Del", dynamicParameters, "CustomerShiftRateBonus_Del");
                    var first = result?.FirstOrDefault();

                    if (first != null && first.IsSuccess == 1)
                    {
                        return new Result { IsSuccessfull = true, Message = first.Message ?? "Customer Shift Rate & Bonus deleted successfully." };
                    }

                    return new Result { IsSuccessfull = false, Message = first?.Message ?? "Failed to delete Customer Shift Rate & Bonus." };
                }
                catch (Exception ex)
                {
                    return new Result { IsSuccessfull = false, Message = ex.Message };
                }
            });
        }

        public async Task<CustomerShiftRateBonusModel?> GetByIdAsync(long id, string companyId)
        {
            return await Task.Run(() =>
            {
                try
                {
                    DynamicParameters dynamicParameters = new DynamicParameters();
                    dynamicParameters.Add("@pk_id", id, DbType.Int64);
                    dynamicParameters.Add("@fk_companyId", companyId ?? "", DbType.String);

                    var result = DataBaseFactory.QuerySP<CustomerShiftRateBonusModel>("USP_Customer_ShiftRateBonus_GetById", dynamicParameters, "CustomerShiftRateBonus_GetById");
                    return result?.FirstOrDefault();
                }
                catch (Exception ex)
                {
                    Console.WriteLine("Error in GetByIdAsync: " + ex.Message);
                    return null;
                }
            });
        }

        public async Task<(int totalCount, IEnumerable<CustomerShiftRateBonusModel> list)> GetListAsync(CustomerShiftRateBonusFilterDto filter, string companyId)
        {
            return await Task.Run(() =>
            {
                try
                {
                    DynamicParameters dynamicParameters = new DynamicParameters();
                    dynamicParameters.Add("@pageIndex", filter.PageIndex > 0 ? filter.PageIndex : 1, DbType.Int32);
                    dynamicParameters.Add("@pageSize", filter.PageSize > 0 ? filter.PageSize : 10, DbType.Int32);
                    dynamicParameters.Add("@searchTerm", filter.SearchTerm ?? "", DbType.String);
                    dynamicParameters.Add("@clientId", string.IsNullOrWhiteSpace(filter.ClientID) ? null : filter.ClientID.Trim(), DbType.String);
                    dynamicParameters.Add("@locationId", string.IsNullOrWhiteSpace(filter.LocationID) ? null : filter.LocationID.Trim(), DbType.String);
                    dynamicParameters.Add("@fk_companyId", companyId ?? "", DbType.String);

                    var tuple = DataBaseFactory.QueryMultipleSP<dynamic, CustomerShiftRateBonusModel>("USP_Customer_ShiftRateBonus_SelForGrid", dynamicParameters, "CustomerShiftRateBonus_GetAll");

                    if (tuple == null || tuple.Item2 == null)
                        return (0, Enumerable.Empty<CustomerShiftRateBonusModel>());

                    int totalCount = 0;
                    if (tuple.Item1 is IEnumerable<dynamic> countList && countList.Any())
                    {
                        var firstRow = (IDictionary<string, object>)countList.First();
                        if (firstRow.ContainsKey("TotalCount"))
                            totalCount = Convert.ToInt32(firstRow["TotalCount"]);
                        else if (firstRow.Values.Any())
                            totalCount = Convert.ToInt32(firstRow.Values.First());
                    }

                    var list = tuple.Item2.ToList();
                    return (totalCount > 0 ? totalCount : list.Count, list);
                }
                catch (Exception ex)
                {
                    Console.WriteLine("Error in GetListAsync: " + ex.Message);
                    return (0, Enumerable.Empty<CustomerShiftRateBonusModel>());
                }
            });
        }
    }
}
