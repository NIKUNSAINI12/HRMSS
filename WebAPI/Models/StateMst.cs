namespace HRMSWebAPI.Models
{
    public class StateMst
    {
        public string? pk_stateid { get; set; }
        public string? code { get; set; }

        public string description { get; set; }

        public bool? lwf_applicable { get; set; }

        public bool? pt_applicable { get; set; }

        public string? lwf_applicable_status { get; set; }

        public string? pt_applicable_status { get; set; }

        public string?fk_companyId { get; set; }

        public string? pt_number { get; set; }

        public string? lwf_number { get; set; }

        public string? esi_number { get; set; }
        public string? pf_number { get; set; }
        public decimal? minimum_wages { get; set; }
    }
}
