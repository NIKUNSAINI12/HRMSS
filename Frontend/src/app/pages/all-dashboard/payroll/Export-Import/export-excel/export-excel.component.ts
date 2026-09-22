declare const html2pdf: any;
import { Component, inject } from '@angular/core';
import { FormBuilder, FormGroup, FormsModule, ReactiveFormsModule, Validators } from '@angular/forms';
import { NgSelectComponent, NgSelectModule } from '@ng-select/ng-select';
import { CommonModule } from '@angular/common';
import { CommonSearchComponent } from '../../Employee/common-search/common-search.component';
import { ToastrService } from 'ngx-toastr';
import { Router } from '@angular/router';
import { EmployeeService } from '../../services/employee.service';
import { NgxUiLoaderService } from 'ngx-ui-loader';
import { ManualPunchBio } from '../../services/manual-puch-bio.service';
import { NgxPaginationModule } from 'ngx-pagination';
import * as XLSX from 'xlsx';
import * as FileSaver from 'file-saver';
import { convertAmountToWordsIndian } from '../../../../../healpers/commonlib';
import { HttpErrorResponse } from '@angular/common/http';
import { CompanyConfig } from '../../../../../on_boarding/services/company-config.service';
import { CompanyParameterService } from '../../services/company-parameter.service';


@Component({
  selector: 'app-export-excel',
  standalone: true,
  imports: [FormsModule, ReactiveFormsModule, CommonModule, NgSelectModule, CommonSearchComponent, NgxPaginationModule],
  templateUrl: './export-excel.component.html',
  styleUrl: './export-excel.component.scss'
})
export class ExportExcelComponent {
  combinedData: any[] = [];
  ExportExcel!: FormGroup;
  isExporting = false;
  searchText: string = "";
  submitted = false;
  showError = false;
  totalCount: number = 0;
  pageIndex: number = 1;
  pageSize: number = 10;
  showEmployeeList: boolean = false;
  EmployeeList: any[] = []
  EmployeeListExcle: any[] = [];
  months = []
  years = []
  // CostCenter=[]
  CostCenter: { name: string; value: string | null }[] = [];
  selectedCostCenters: string[] = [];
  tableHeaders: string[] = []
  isContractApplicable = false;
  ExportTypelist = [
    //{name: '--select Grade --', Value:0},
    //{name:'Employee Details',value:0},
    { name: 'Employees Salary', value: 2 },
    { name: 'Bank Salary Statement', value: 1 },
    { name: 'New Joinees Salary', value: 3 },
    { name: 'Left Employees Salary', value: 4 },
    { name: 'Stoped Salary Details', value: 9 },
    { name: 'Pay Stoped Salary Details', value: 10 },
    { name: 'OT Statement', value: 31 },
    { name: 'Monthly PF Statement', value: 5 },
    { name: 'Monthly ESI Statement', value: 6 },
    { name: 'Monthly LWF Statement', value: 11 },
    { name: 'Monthly Prof. Tax Statement', value: 12 },
    //{ name: 'Monthly Loan/Advance Details', value: 13 },
    // {name:'Employee Increment Details',value:8},
    // { name: 'Monthly Salary Slip', value: 35 },
    //added code PP 17AUG2025
    { name: 'Monthly PF Challan', value: 36 },
    { name: 'Monthly ESI Challan', value: 37 },
    // {name:'Monthly LWF Challan',value:38},
    { name: 'PF Form  10', value: 39 },
    { name: 'PF Form  5', value: 40 },
    { name: 'PF Form 12A', value: 41 },
    { name: 'Muster Roll Form A', value: 51 },
    { name: 'Form D', value: 52 },
    // { name: 'PF Statement Detail', value: 42 },
    // { name: 'ESI Statement Detail', value: 43 },
    { name: 'Bonus Statement', value: 50 },
    { name: 'LTA Statement', value: 55 },
    { name: 'Incentive Statement', value: 56 },

    //{ name: 'NAV Account Posting', value: 53 },
    { name: 'Gratuity', value: 54 },

    { name: 'Leave Encashment Statement', value: 27 },


    { name: 'Arrear  Statement', value: 57 }


  ]

  SalTransfer = [
    { name: 'All', value: "A" },
    { name: 'Bank', value: "B" },
    { name: 'Cash', value: "C" },
    { name: 'Stop', value: "S" }
  ]


  companyLogo: String =
    'assets/Image/Logo/empower.jpg';

  constructor(
    private fb: FormBuilder,
    private toastrService: ToastrService,
    private router: Router,
    private httpService: EmployeeService,
    private ngxUILoaderService: NgxUiLoaderService,
    private commanService: ManualPunchBio,
    private service: CompanyParameterService) { }
  ngOnInit() {
    this.isContractApplicable = sessionStorage.getItem('ContractApplicable') == "false" ? false : true || false;

    this.ExportExcel = this.fb.group({
      empCode: [''],
      fk_monthId: [null],
      fk_yearId: [null],
      fk_costcentreid: [[]],
      EmplyeeType: [''],
      empCodeManual: [''],
      empName: [''],
      selectedDepartments: [[]],
      selectedDesignation: [''],
      selectedLocations: [[]],
      selectedNature: [''],
      selectedCity: [''],
      sortBy: [''],
      ExportType: [null],
      SalTransfer: ['A']
    });

    this.getMonthsList();
    this.getyearsList();
    this.getCostCenterList();
  }

  getMonthsList() {
    this.commanService.getCommanList('month').subscribe({
      next: (res) => {
        res.data = res.data.slice(1);
        this.months = res.data

      }
    })
  }
  getyearsList() {
    this.commanService.getCommanList('Year').subscribe({
      next: (res) => {
        res.data = res.data.slice(1);
        this.years = res.data
      }
    })
  }

  getCostCenterList() {
    this.commanService.getCommanList('CostCenter').subscribe({
      next: (res) => {
        this.CostCenter = [
          { name: 'Select All', value: '__select_all__' },
          ...res.data.slice(1)
        ];
      }
    })
  }


  // added new pp 3/9/2025

  get isPdfExport(): boolean {
    return this.ExportExcel?.value?.ExportType === 2;
  }
  restfrom() {
    this.EmployeeList = [];
  }
  // Handle filter updates from common search
  handleFilters(filters: any) {

    this.ExportExcel.patchValue(filters);
  }
  filteredData() {
    if (!this.searchText) {
      return this.EmployeeList;
    }
    const searchTextLower = this.searchText.toLowerCase();
    return this.EmployeeList.filter(res =>
      res.EmpCode?.toLowerCase().includes(searchTextLower) ||
      res.EmpName?.toLowerCase().includes(searchTextLower) ||
      res.Code?.toLowerCase().includes(searchTextLower) ||
      res.Name?.toLowerCase().includes(searchTextLower) ||
      res.Branch?.toLowerCase().includes(searchTextLower) ||
      res.zoneDescription?.toLowerCase().includes(searchTextLower) ||
      res.Department?.toLowerCase().includes(searchTextLower) ||
      res.Designation?.toLowerCase().includes(searchTextLower),);
  }


  onpagechange(event: number): void {
    debugger
    this.pageIndex = event;
    this.OnVeiw();
  }
  OnSubmit() {
    this.pageIndex = 1;
    this.totalCount = 0;
    this.OnVeiw();
  }

  OnVeiw() {
    this.submitted = true;
    this.ngxUILoaderService.start();
    if (this.ExportExcel.invalid) {
      this.showError = true;
      this.ngxUILoaderService.stop();
      return;
    }


    const exportType = this.ExportExcel.value.ExportType;
    //const foreignTypes = [11, 12, 36, 37, 42,43];

    const payload = {
      ...this.ExportExcel.value,
      // ExportType: foreignTypes.includes(exportType) ? 2 : exportType, // ✅ override if in list

      ExportType: exportType, //  override if in list
      pageIndex: this.pageIndex - 1,
      pageSize: this.pageSize
    };


    //     const payload = {
    //   ...this.ExportExcel.value,  
    //   pageIndex: this.pageIndex - 1,  
    //   pageSize: this.pageSize
    // };

    Object.keys(payload).forEach(key => {
      if (payload[key] === null) {
        payload[key] = '';
      }
    })

    if (Array.isArray(payload.fk_costcentreid)) {
      payload.fk_costcentreid = payload.fk_costcentreid.join(',');
    }

    this.EmployeeListExcle = [];
    this.httpService.Export_Employeelist(payload).subscribe({
      next: (res) => {
        if (res.isSuccess) {
          this.EmployeeList = res.data;
          this.totalCount = res.totalCount
          //console.log( this.totalCount)
          this.tableHeaders = Object.keys(res.data[0] ?? {});
          this.showEmployeeList = true


          // this.toastrService.success(res.message)        
        } else {
          this.tableHeaders = []
          this.EmployeeList = []
          this.totalCount = 0
          this.toastrService.info(res.message)
        }
        this.ngxUILoaderService.stop();
      },
      error: (error) => {
        this.ngxUILoaderService.stop();
        this.toastrService.error('Failed to retrieve employees', error);
      }


    });
  }

  //    downloadExcel(): void {
  //       const payload = {
  //     ...this.ExportExcel.value,
  //     pageIndex: 0,
  //     pageSize: 10000
  //   };

  //   Object.keys(payload).forEach(key => {
  //     if (payload[key] === null) {
  //       payload[key] = '';
  //     }
  //   });

  //   this.httpService.Export_Employeelist(payload).subscribe({
  //     next: (res) => {
  //       if (res.isSuccess) {
  //         this.EmployeeListExcle = res.data;


  //       let selectedMonthId = this.ExportExcel.get('fk_monthId')?.value;
  //       let selectedMonth: {name: string, value: string} | undefined = this.months.find((m: {name: string, value: string}) => m.value === selectedMonthId);
  //       let {name : month,value}={...selectedMonth!}

  //       let selectedYearId = this.ExportExcel.get('fk_yearId')?.value;
  //       let selectedYear: {name: string, value: string} | undefined = this.years.find((m: {name: string, value: string}) => m.value === selectedYearId);
  //       let {name : Year,value : Yearvalue}={...selectedYear!}

  //       let selectedReportId = this.ExportExcel.get('ExportType')?.value;
  //       let selectedReport: {name: string, value: number} | undefined = this.ExportTypelist.find((m: {name: string, value: number}) => m.value === selectedReportId);
  //       let {name : Report,value : Reportvalue}={...selectedReport!}

  //       let ReportName =Report +'_'+ month+'_'+Year+'.xlsx';

  //      try {
  //     const worksheet = XLSX.utils.json_to_sheet(this.EmployeeListExcle);
  //     const workbook = XLSX.utils.book_new();
  //     XLSX.utils.book_append_sheet(workbook, worksheet, 'Data');

  //     const excelBuffer: any = XLSX.write(workbook, { bookType: 'xlsx', type: 'array' });
  //     const blob = new Blob([excelBuffer], { type: 'application/octet-stream' });
  //     FileSaver.saveAs(blob, ReportName);
  //    } catch (error) {
  //           console.error('Error exporting Excel:', error);
  //           this.toastrService.error('Failed to export Excel');
  //         }
  //       } else {
  //         this.EmployeeListExcle = [];
  //         this.toastrService.info(res.message);
  //       }
  //       this.ngxUILoaderService.stop();
  //     },
  //     error: (error) => {
  //       this.toastrService.error('Failed to retrieve employees', error);
  //       this.ngxUILoaderService.stop();
  //     }
  //   });
  // }

  Exceldownload() {
    const exportType = this.ExportExcel.get('ExportType')?.value;

    if (exportType == 2) {
      this.downloadExcelforexporttype1();
    } else {
      this.downloadExcel();
    }
  }

  downloadExcel() {

    if (this.isExporting) return; // prevent double click
    this.isExporting = true;

    const payload = {
      ...this.ExportExcel.value,
      pageIndex: 0,
      pageSize: 10000
    };

    Object.keys(payload).forEach(key => {
      if (payload[key] === null) {
        payload[key] = '';
      }
    });
    let selectedMonthId = this.ExportExcel.get('fk_monthId')?.value;
    let selectedMonth: { name: string, value: string } | undefined = this.months.find((m: { name: string, value: string }) => m.value === selectedMonthId);
    let { name: month, value } = { ...selectedMonth! }

    let selectedYearId = this.ExportExcel.get('fk_yearId')?.value;
    let selectedYear: { name: string, value: string } | undefined = this.years.find((m: { name: string, value: string }) => m.value === selectedYearId);
    let { name: Year, value: Yearvalue } = { ...selectedYear! }

    let selectedReportId = this.ExportExcel.get('ExportType')?.value;
    let selectedReport: { name: string, value: number } | undefined = this.ExportTypelist.find((m: { name: string, value: number }) => m.value === selectedReportId);
    let { name: Report, value: Reportvalue } = { ...selectedReport! }

    let ReportName = Report + '_' + month + '_' + Year + '.xlsx';

    //added for contractor name
    // Find contractor name from CostCenter list
    // let contractorName = '';
    // if (payload.fk_costcentreid) {
    //   const selectedIds = Array.isArray(payload.fk_costcentreid) ? payload.fk_costcentreid : [payload.fk_costcentreid];
    //   const selectedContractors = this.CostCenter.filter(c => selectedIds.includes(c.value));
    //   contractorName = selectedContractors.map(c => c.name).join(', ');
    // }
    // Add to formData for backend
    // payload.contractorName = contractorName;
    payload.ReportName = Report;

    if (Array.isArray(payload.fk_costcentreid)) {
      payload.fk_costcentreid = payload.fk_costcentreid.join(',');
    }

    this.httpService.downloadViewSalaryReportlist(payload).subscribe({
      next: (res: Blob) => {
        const blob = new Blob([res], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        // a.download = `Canteen_${new Date().toISOString().split('T')[0]}.xlsx`; // dynamic filename
        a.download = ReportName;

        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        window.URL.revokeObjectURL(url);
        this.isExporting = false; // reset after download
      },
      error: (err) => {
        console.error('Download failed', err);
        this.isExporting = false; // reset even on error
      }
    });
  }


  downloadExcelforexporttype1() {

    if (this.isExporting) return; // prevent double click
    this.isExporting = true;

    const payload = {
      ...this.ExportExcel.value,
      pageIndex: 0,
      pageSize: 10000
    };

    Object.keys(payload).forEach(key => {
      if (payload[key] === null) {
        payload[key] = '';
      }
    });
    let selectedMonthId = this.ExportExcel.get('fk_monthId')?.value;
    let selectedMonth: { name: string, value: string } | undefined = this.months.find((m: { name: string, value: string }) => m.value === selectedMonthId);
    let { name: month, value } = { ...selectedMonth! }

    let selectedYearId = this.ExportExcel.get('fk_yearId')?.value;
    let selectedYear: { name: string, value: string } | undefined = this.years.find((m: { name: string, value: string }) => m.value === selectedYearId);
    let { name: Year, value: Yearvalue } = { ...selectedYear! }

    let selectedReportId = this.ExportExcel.get('ExportType')?.value;
    let selectedReport: { name: string, value: number } | undefined = this.ExportTypelist.find((m: { name: string, value: number }) => m.value === selectedReportId);
    let { name: Report, value: Reportvalue } = { ...selectedReport! }

    let ReportName = Report + '_' + month + '_' + Year + '.xlsx';

    //added for contractor name
    // Find contractor name from CostCenter list
    // let contractorName = '';
    // if (payload.fk_costcentreid) {
    //   const selectedIds = Array.isArray(payload.fk_costcentreid) ? payload.fk_costcentreid : [payload.fk_costcentreid];
    //   const selectedContractors = this.CostCenter.filter(c => selectedIds.includes(c.value));
    //   contractorName = selectedContractors.map(c => c.name).join(', ');
    // }
    // Add to formData for backend
    // payload.contractorName = contractorName;
    payload.ReportName = Report;

    if (Array.isArray(payload.fk_costcentreid)) {
      payload.fk_costcentreid = payload.fk_costcentreid.join(',');
    }

    this.httpService.downloadViewSalaryReportlistforexportype1(payload).subscribe({
      next: (res: Blob) => {
        const blob = new Blob([res], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        // a.download = `Canteen_${new Date().toISOString().split('T')[0]}.xlsx`; // dynamic filename
        a.download = ReportName;

        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        window.URL.revokeObjectURL(url);
        this.isExporting = false; // reset after download
      },
      error: (err) => {
        console.error('Download failed', err);
        this.isExporting = false; // reset even on error
      }
    });
  }

  downloadpdf(): void {
    const payload = {
      ...this.ExportExcel.value
    };

    // replace null with ''
    Object.keys(payload).forEach(key => {
      if (payload[key] === null) {
        payload[key] = '';
      }
    });

    if (Array.isArray(payload.fk_costcentreid)) {
      payload.fk_costcentreid = payload.fk_costcentreid.join(',');
    }

    this.httpService.Export_pdf(payload).subscribe({
      next: (file: Blob) => {

        const blob = new Blob([file], { type: 'application/pdf' });
        const url = window.URL.createObjectURL(blob);

        const a = document.createElement('a');
        a.href = url;
        a.download = 'Report.pdf'; // 👉 this is the filename shown in downloads
        a.click();

        window.URL.revokeObjectURL(url);
        this.ngxUILoaderService.stop();
      },


      error: (error) => {



        if (error.status === 500) {
          this.toastrService.warning('Record not found');
        } else {
          this.toastrService.error('Failed to download PDF');
        }
        this.ngxUILoaderService.stop();
      }
    });
  }



  //Salry Slip
  salarySlipData: any[] = []
  showPayslip: boolean = false;
  payColumns: { Fixed: string, Rate: string, Earnings: string, Arrears: string }[] = [];
  dedColumns: { Fixed: string, Amount: string }[] = [];
  LeaveList: any[] = [];

  get requestBody() {
  const payload = this.ExportExcel.value;

  if (Array.isArray(payload.fk_costcentreid)) {
    payload.fk_costcentreid = payload.fk_costcentreid.join(',');
  }

  return payload;
}

  viewData(requestBody: any, EmpCode: string): void {
    requestBody.empCode = EmpCode;
    this.httpService.Download_SalarySlip(requestBody).subscribe({
      next: (res) => {
        if (res.isSuccess) {
          this.salarySlipData = res.data;
          this.loadCompanyLogo(
            this.salarySlipData?.[0]?.company_logopath
          );
          this.LeaveList = res.data[4] != null ? res.data[4]["LeaveList"] : [];


          this.salarySlipData[0].website = convertAmountToWordsIndian(this.salarySlipData[3]?.NetPay);
          this.payColumns = [];
          this.dedColumns = [];

          // For Earning

          for (let i = 1; i <= 15; i++) {
            if (res.data[1]["Pay" + i] != null && res.data[1]["Pay" + i] != "" && res.data[3]["PayAmt" + i] > 0) {

              if (res.data[3]["PayAmt" + i] != 0) {
                let objPay = { Fixed: res.data[1]["Pay" + i], Rate: res.data[3]["Pay" + i], Earnings: res.data[3]["PayAmt" + i], Arrears: res.data[3]["PayAmt" + i + "_A"] };
                this.payColumns.push(objPay);
              }


            }
          }


          for (let i = 1; i <= 10; i++) {
            if (res.data[1]["PayR" + i] != null && res.data[1]["PayR" + i] != "") {
              if (res.data[3]["PayRAmt" + i] != 0) {
                var objR = { Fixed: res.data[1]["PayR" + i], Rate: res.data[3]["PayR" + i], Earnings: res.data[3]["PayRAmt" + i], Arrears: res.data[3]["PayRAmt" + i + "_A"] };
                this.payColumns.push(objR);
              }

            }
          }
          // For Deduction
          if (res.data[3]["PF"] != null && res.data[3]["PF"] != 0) {
            var objPF = { Fixed: "PF", Amount: res.data[3]["PF"] };
            this.dedColumns.push(objPF);
          }
          if (res.data[3]["VolPF"] != null && res.data[3]["VolPF"] != 0) {
            var objPF = { Fixed: "VolPF", Amount: res.data[3]["VolPF"] };
            this.dedColumns.push(objPF);
          }
          if (res.data[3]["ESI"] != null && res.data[3]["ESI"] != 0) {
            var objPF = { Fixed: "ESI", Amount: res.data[3]["ESI"] };
            this.dedColumns.push(objPF);
          }
          if (res.data[3]["ProfTax"] != null && res.data[3]["ProfTax"] != 0) {
            var objPF = { Fixed: "ProfTax", Amount: res.data[3]["ProfTax"] };
            this.dedColumns.push(objPF);
          }
          if (res.data[3]["IT"] != null && res.data[3]["IT"] != 0) {
            var objPF = { Fixed: "IT", Amount: res.data[3]["IT"] };
            this.dedColumns.push(objPF);
          }
          if (res.data[3]["LWF"] != null && res.data[3]["LWF"] != 0) {
            var objPF = { Fixed: "LWF", Amount: res.data[3]["LWF"] };
            this.dedColumns.push(objPF);
          }



          for (let i = 1; i <= 15; i++) {
            if (res.data[1]["PayD" + i] != null && res.data[1]["PayD" + i] != "") {
              if (res.data[3]["PayDAmt" + i] != 0) {
                var objDed = { Fixed: res.data[1]["PayD" + i], Amount: res.data[3]["PayDAmt" + i] };
                this.dedColumns.push(objDed);
              }
            }
          }
          for (let i = 1; i <= 15; i++) {
            if (res.data[1]["Loan" + i] != null && res.data[1]["Loan" + i] != "") {
              if (res.data[3]["LoanAmt" + i] != 0) {
                var objLoan = { Fixed: res.data[1]["Loan" + i], Amount: res.data[3]["LoanAmt" + i] };
                this.dedColumns.push(objLoan);
              }
            }
          }

          const maxLength = Math.max(this.payColumns.length, this.dedColumns.length);
          this.combinedData = Array(maxLength).fill({}).map((_, i) => ({
            pay: this.payColumns[i] || { Fixed: '', Rate: '', Earnings: '', Arrears: '' },
            ded: this.dedColumns[i] || { Fixed: '', Amount: '' }
          }));


        } else {
          this.salarySlipData = [];
        }
      },
      error: (err) => {
        console.error('Error downloading salary slip:', err);
      }
    });
  }

  downloadAndDisplaySalarySlip(requestBody: any, EmpCode: string): void {
    requestBody.empCode = EmpCode;
    this.httpService.Download_SalarySlip(requestBody).subscribe({
      next: (res) => {

        if (res.isSuccess) {
          this.salarySlipData = res.data;
          this.loadCompanyLogo(
            this.salarySlipData?.[0]?.company_logopath
          );

          this.LeaveList = res.data[4] != null ? res.data[4]["LeaveList"] : [];
          this.salarySlipData[0].website = convertAmountToWordsIndian(this.salarySlipData[3]?.NetPay);

          this.payColumns = [];
          this.dedColumns = [];
          // For Earning
          for (let i = 1; i <= 15; i++) {
            if (res.data[1]["Pay" + i] != null && res.data[1]["Pay" + i] != "" && res.data[3]["PayAmt" + i] > 0) {
              //console.log("downlaod",res.data[3]["PayAmt"+i]);
              if (res.data[3]["PayAmt" + i] != 0) {
                var obj = { Fixed: res.data[1]["Pay" + i], Rate: res.data[3]["Pay" + i], Earnings: res.data[3]["PayAmt" + i], Arrears: res.data[3]["PayAmt" + i + "_A"] };
                this.payColumns.push(obj);
              }
            }
          }

          for (let i = 1; i <= 10; i++) {
            if (res.data[1]["PayR" + i] != null && res.data[1]["PayR" + i] != "") {
              if (res.data[3]["PayRAmt" + i] != 0) {
                var objR = { Fixed: res.data[1]["PayR" + i], Rate: res.data[3]["PayR" + i], Earnings: res.data[3]["PayRAmt" + i], Arrears: res.data[3]["PayRAmt" + i + "_A"] };
                this.payColumns.push(objR);
              }
            }
          }

          // For Deduction
          if (res.data[3]["PF"] != null && res.data[3]["PF"] != 0) {
            var objPF = { Fixed: "PF", Amount: res.data[3]["PF"] };
            this.dedColumns.push(objPF);
          }
          if (res.data[3]["VolPF"] != null && res.data[3]["VolPF"] != 0) {
            var objPF = { Fixed: "VolPF", Amount: res.data[3]["VolPF"] };
            this.dedColumns.push(objPF);
          }
          if (res.data[3]["ESI"] != null && res.data[3]["ESI"] != 0) {
            var objPF = { Fixed: "ESI", Amount: res.data[3]["ESI"] };
            this.dedColumns.push(objPF);
          }
          if (res.data[3]["ProfTax"] != null && res.data[3]["ProfTax"] != 0) {
            var objPF = { Fixed: "ProfTax", Amount: res.data[3]["ProfTax"] };
            this.dedColumns.push(objPF);
          }
          if (res.data[3]["IT"] != null && res.data[3]["IT"] != 0) {
            var objPF = { Fixed: "IT", Amount: res.data[3]["IT"] };
            this.dedColumns.push(objPF);
          }
          if (res.data[3]["LWF"] != null && res.data[3]["LWF"] != 0) {
            var objPF = { Fixed: "LWF", Amount: res.data[3]["LWF"] };
            this.dedColumns.push(objPF);
          }



          for (let i = 1; i <= 15; i++) {
            if (res.data[1]["PayD" + i] != null && res.data[1]["PayD" + i] != "") {
              if (res.data[3]["PayDAmt" + i] != 0) {
                var objDed = { Fixed: res.data[1]["PayD" + i], Amount: res.data[3]["PayDAmt" + i] };
                this.dedColumns.push(objDed);
              }
            }
          }
          for (let i = 1; i <= 15; i++) {
            if (res.data[1]["Loan" + i] != null && res.data[1]["Loan" + i] != "") {
              if (res.data[3]["LoanAmt" + i] != 0) {
                var objLoan = { Fixed: res.data[1]["Loan" + i], Amount: res.data[3]["LoanAmt" + i] };
                this.dedColumns.push(objLoan);
              }
            }
          }
          const maxLength = Math.max(this.payColumns.length, this.dedColumns.length);
          this.combinedData = Array(maxLength).fill({}).map((_, i) => ({
            pay: this.payColumns[i] || { Fixed: '', Rate: '', Earnings: '', Arrears: '' },
            ded: this.dedColumns[i] || { Fixed: '', Amount: '' }
          }));


          setTimeout(() => this.downloadPDF(), 500);
        }
        else {
          this.salarySlipData = []
          this.toastrService.info(res.message)
        }
      },
      error: (err) => {
        console.error('Error downloading salary slip:', err);
      }
    });
  }

  downloadPDF(): void {
    this.showPayslip = true
    const element = document.getElementById('pdf-content') as HTMLElement;

    // Ensure the page scrolls to the top before rendering
    window.scrollTo(0, 0);

    const opt = {
      margin: [0, 0, 0, 0], // top, left, bottom, right
      filename: 'Payslip.pdf',
      image: { type: 'jpeg', quality: 0.98 },
      html2canvas: {
        scale: 2,
        scrollY: 0 // Prevent scroll-based displacement
      },
      jsPDF: { unit: 'mm', format: 'a4', orientation: 'portrait' },
      pagebreak: { avoid: 'tr' } // Optional: prevents breaks inside rows
    };

    if (element) {
      html2pdf().from(element).set(opt).save();
    } else {
      console.error("Element not found for PDF generation");
    }
  }



  downloadPdffile() {
    const payload = {
      ...this.ExportExcel.value,
      pageIndex: 0,      //  added
      pageSize: 100
    };

    // replace null with ''
    Object.keys(payload).forEach(key => {
      if (payload[key] === null) {
        payload[key] = '';
      }
    });

    if (Array.isArray(payload.fk_costcentreid)) {
      payload.fk_costcentreid = payload.fk_costcentreid.join(',');
    }

    this.httpService.DownloadPdfFile(payload).subscribe((res: Blob) => {
      const blob = new Blob([res], { type: 'application/pdf' });
      const url = window.URL.createObjectURL(blob);

      // Option 1: Auto Download
      const a = document.createElement('a');
      a.href = url;
      a.download = 'SalaryRegister.pdf';  // file ka naam
      a.click();

      //  Option 2: New Tab me open karne ke liye
      // window.open(url);
    });
  }

  //added

   downloadPdffileV2() {
    const payload = {
      ...this.ExportExcel.value,
      pageIndex: 0,      //  added
      pageSize: 100
    };

    // replace null with ''
    Object.keys(payload).forEach(key => {
      if (payload[key] === null) {
        payload[key] = '';
      }
    });

    if (Array.isArray(payload.fk_costcentreid)) {
      payload.fk_costcentreid = payload.fk_costcentreid.join(',');
    }

     this.httpService.DownloadPdfFileV2(payload).subscribe((res: Blob) => {
      const blob = new Blob([res], { type: 'application/pdf' });
      const url = window.URL.createObjectURL(blob);

      // Option 1: Auto Download
      const a = document.createElement('a');
      a.href = url;
      a.download = 'SalaryRegister.pdf';  
      a.click();

    });
  }


  downloadPFform5() {
    const payload = {
      ...this.ExportExcel.value
    };

    // replace null with ''
    Object.keys(payload).forEach(key => {
      if (payload[key] === null) {
        payload[key] = '';
      }
    });

    if (Array.isArray(payload.fk_costcentreid)) {
      payload.fk_costcentreid = payload.fk_costcentreid.join(',');
    }

    this.httpService.DownloadForm5(payload).subscribe((res: Blob) => {
      const blob = new Blob([res], { type: 'application/pdf' });
      const url = window.URL.createObjectURL(blob);

      //  Option 1: Auto Download
      const a = document.createElement('a');
      a.href = url;
      a.download = 'Generate Form 5.pdf';  // file ka naam
      a.click();

      //  Option 2: New Tab me open karne ke liye
      // window.open(url);
    });
  }

  downloadPFform10() {
    const payload = {
      ...this.ExportExcel.value
    };

    // replace null with ''
    Object.keys(payload).forEach(key => {
      if (payload[key] === null) {
        payload[key] = '';
      }
    });

    if (Array.isArray(payload.fk_costcentreid)) {
      payload.fk_costcentreid = payload.fk_costcentreid.join(',');
    }

    this.httpService.DownloadForm10(payload).subscribe((res: Blob) => {
      const blob = new Blob([res], { type: 'application/pdf' });
      const url = window.URL.createObjectURL(blob);

      //  Option 1: Auto Download
      const a = document.createElement('a');
      a.href = url;
      a.download = 'Generate Form 10.pdf';  // file ka naam
      a.click();

      //  Option 2: New Tab me open karne ke liye
      // window.open(url);
    });
  }
  GeneratePFStatement() {
    const payload = {
      ...this.ExportExcel.value
    };

    // replace null with ''
    Object.keys(payload).forEach(key => {
      if (payload[key] === null) {
        payload[key] = '';
      }
    });

    if (Array.isArray(payload.fk_costcentreid)) {
      payload.fk_costcentreid = payload.fk_costcentreid.join(',');
    }

    this.httpService.GeneratePFStatement(payload).subscribe((res: Blob) => {
      const blob = new Blob([res], { type: 'application/pdf' });
      const url = window.URL.createObjectURL(blob);

      //  Option 1: Auto Download
      const a = document.createElement('a');
      a.href = url;
      a.download = 'GeneratePFStatement.pdf';  // file ka naam
      a.click();

      //  Option 2: New Tab me open karne ke liye
      // window.open(url);
    });
  }


  // esi statement

  GenerateESIStatement() {
    const payload = {
      ...this.ExportExcel.value
    };

    // replace null with ''
    Object.keys(payload).forEach(key => {
      if (payload[key] === null) {
        payload[key] = '';
      }
    });

    if (Array.isArray(payload.fk_costcentreid)) {
      payload.fk_costcentreid = payload.fk_costcentreid.join(',');
    }

    this.httpService.GenerateESIStatement(payload).subscribe((res: Blob) => {
      const blob = new Blob([res], { type: 'application/pdf' });
      const url = window.URL.createObjectURL(blob);

      //  Option 1: Auto Download
      const a = document.createElement('a');
      a.href = url;
      a.download = 'Generate ESI Statement.pdf';  // file ka naam
      a.click();

      //  Option 2: New Tab me open karne ke liye
      // window.open(url);
    });
  }

  GeneratePFform12A() {
    const payload = {
      ...this.ExportExcel.value
    };

    // replace null with ''
    Object.keys(payload).forEach(key => {
      if (payload[key] === null) {
        payload[key] = '';
      }
    });

    if (Array.isArray(payload.fk_costcentreid)) {
      payload.fk_costcentreid = payload.fk_costcentreid.join(',');
    }

    this.httpService.GeneratePFform12A(payload).subscribe((res: Blob) => {
      const blob = new Blob([res], { type: 'application/pdf' });
      const url = window.URL.createObjectURL(blob);

      // ✅ Option 1: Auto Download
      const a = document.createElement('a');
      a.href = url;
      a.download = 'PF form 12A.pdf';  // file ka naam
      a.click();

      // ✅ Option 2: New Tab me open karne ke liye
      // window.open(url);
    });
  }
  onExportClick() {
    const exportType = this.ExportExcel.get('ExportType')?.value;

    if (exportType === 40) {
      this.downloadPFform5();
    }
    else if (exportType === 39) {
      this.downloadPFform10();
    }

    else if (exportType === 41) {
      this.GeneratePFform12A();
    }
    else if (exportType === 5) {
      this.GeneratePFStatement();
    }

    else if (exportType === 6) {
      this.GenerateESIStatement();
    }
    else if (exportType === 51) {
      this.DownloadMusterRollPdf();
    }
    else if (exportType === 52) {
      this.DownloadFORMDPdf();
    }
    else if (exportType === 54) {
      this.GenerateGratuityPdf();
    }
    else {
      this.downloadpdf();
    }

  }


  GenerateGratuityPdf() {
    const payload = {
      ...this.ExportExcel.value,
      pageIndex: 0,
      pageSize: 10000000
    };

    // replace null with ''
    Object.keys(payload).forEach(key => {
      if (payload[key] === null) {
        payload[key] = '';
      }
    });

    if (Array.isArray(payload.fk_costcentreid)) {
      payload.fk_costcentreid = payload.fk_costcentreid.join(',');
    }

    this.httpService.GenerateGratuityPdf(payload).subscribe((res: Blob) => {
      const blob = new Blob([res], { type: 'application/pdf' });
      const url = window.URL.createObjectURL(blob);

      // Option 1: Auto Download
      const a = document.createElement('a');
      a.href = url;
      a.download = 'Generate Gratuity.pdf';  // file ka naam
      a.click();

      //  Option 2: New Tab me open karne ke liye
      // window.open(url);
    });
  }





  DownloadMusterRollPdf() {
    const payload = {
      ...this.ExportExcel.value
    };

    // replace null with ''
    Object.keys(payload).forEach(key => {
      if (payload[key] === null) {
        payload[key] = '';
      }
    });

    if (Array.isArray(payload.fk_costcentreid)) {
      payload.fk_costcentreid = payload.fk_costcentreid.join(',');
    }

    this.httpService.DownloadMusterRollPdf(payload).subscribe((res: Blob) => {
      const blob = new Blob([res], { type: 'application/pdf' });
      const url = window.URL.createObjectURL(blob);


      const a = document.createElement('a');
      a.href = url;
      a.download = 'Generate MusterRollPdf.pdf';  // file ka naam
      a.click();

      // ✅ Option 2: New Tab me open karne ke liye
      // window.open(url);
    });
  }


  DownloadFORMDPdf() {
    const payload = {
      ...this.ExportExcel.value
    };

    // replace null with ''
    Object.keys(payload).forEach(key => {
      if (payload[key] === null) {
        payload[key] = '';
      }
    });

    if (Array.isArray(payload.fk_costcentreid)) {
      payload.fk_costcentreid = payload.fk_costcentreid.join(',');
    }

    this.httpService.DownloadFORMDPdf(payload).subscribe((res: Blob) => {
      const blob = new Blob([res], { type: 'application/pdf' });
      const url = window.URL.createObjectURL(blob);

      //  Option 1: Auto Download
      const a = document.createElement('a');
      a.href = url;
      a.download = 'Form D.pdf';  // file ka naam
      a.click();


      // window.open(url);
    });
  }


private buildExportPayload(pageIndex: number, pageSize: number) {
    const payload = {
      ...this.ExportExcel.value,
      pageIndex,
      pageSize
    };

    Object.keys(payload).forEach(key => {
      if (payload[key] === null) {
        payload[key] = '';
      }
    });
      if (Array.isArray(payload.fk_costcentreid)) {
      payload.fk_costcentreid = payload.fk_costcentreid.join(',');
    }

    return payload;
  
  
 }

  
  downloadTxtWrapper() {
    const exportType = this.ExportExcel.get('ExportType')?.value;

    if (exportType !== 36 && exportType !== 37) {
      this.toastrService.warning('Please select PF or ESI Challan');
      return;
    }

    this.ngxUILoaderService.start();

    // 🔥 Call API with LARGE pageSize
    const payload = this.buildExportPayload(0, 100000);

    this.httpService.Export_Employeelist(payload).subscribe({
      next: (res) => {
        this.ngxUILoaderService.stop();

        if (!res.isSuccess || !res.data || res.data.length === 0) {
          this.toastrService.warning('No data available for download');
          return;
        }

        //  Use FULL DATA
        if (exportType === 36) {
          this.generatePFTxt(res.data);
        } else {
          this.generateESITxt(res.data);
        }
      },
      error: () => {
        this.ngxUILoaderService.stop();
        this.toastrService.error('Failed to download TXT data');
      }
    });
  }
  // generatePFTxt(employeeList: any[]) {
  //   let txtContent = '';

  //   employeeList.forEach(emp => {

  //     const pfWages = Math.min(emp['Current Salary'] || 0, 15000);
  //     const employeePF = +(pfWages * 0.12).toFixed(2);
  //     const employerPF = +(pfWages * 0.0367).toFixed(2);
  //     const eps = +(pfWages * 0.0833).toFixed(2);

  //     const row = [
  //       emp['EmpCode'] || '',
  //       emp['EmpName'] || '',
  //       emp['UANNO'] || '',
  //       emp['Pfno'] || '',
  //       emp['DOB'] || '',
  //       emp['DOJ'] || '',
  //       emp['Gender'] || '',
  //       emp['Current Salary'] || 0,
  //       pfWages,
  //       employeePF,
  //       employerPF,
  //       eps
  //     ].join('#');

  //     txtContent += row + '\n';
  //   });

  //   this.downloadTxtFile(txtContent);
  // }
  generatePFTxt(employeeList: any[]) {
    let txtContent = '';

    employeeList.forEach(emp => {

      const row = [
        emp['UAN'] || '',
        emp['Member Name'] || '',
        emp['GROSS WAGES'] || 0,
        emp['EPF Wages'] || 0,
        emp['EPS Wages'] || 0,
        emp['EDLI WAGES'] || 0,
        emp['EPF CONTRI REMITTED'] || 0,
        emp['EPS CONTRI REMITTED'] || 0,
        emp['EPF EPS DIFF REMITTED'] || 0,
        emp['NCP DAYS'] || 0,
        emp['REFUND OF ADVANCES'] || 0
      ].join('#');

      txtContent += row + '\n';
    });

    this.downloadTxtFile(txtContent);
  }

  // generateESITxt(employeeList: any[]) {
  //   let txtContent = '';

  //   employeeList.forEach(emp => {
  //     const grossSalary = emp['Current Salary'] || 0;

  //     const employeeESI = +(grossSalary * 0.0075).toFixed(2);
  //     const employerESI = +(grossSalary * 0.0325).toFixed(2);

  //     const row = [
  //       emp['EmpCode'] || '',
  //       emp['EmpName'] || '',
  //       emp['FatherName'] || '',
  //       emp['Gender'] || '',
  //       emp['DOB'] || '',
  //       emp['DOJ'] || '',
  //       emp['Esino'] || '',
  //       grossSalary,
  //       employeeESI,
  //       employerESI
  //     ].join('#');

  //     txtContent += row + '\n';
  //   });

  //   this.downloadTxtFile(txtContent);
  // }

  generateESITxt(employeeList: any[]) {
    let txtContent = '';

    employeeList.forEach(emp => {

      const row = [
        emp['IP Number'] || '',
        emp['IP Name'] || '',
        emp['No of Days for which wages paid/payable during the month'] || 0,
        emp['Total Monthly Wages'] || 0,
        emp[' Reason Code for Zero workings days(numeric only; provide 0 for all other reasons- Click on the link for reference)'] || 0,
        emp['Last Working Day'] || ''
      ].join('#');

      txtContent += row + '\n';
    });

    this.downloadTxtFile(txtContent);
  }

  downloadTxtFile(content: string) {
    const blob = new Blob([content], { type: 'text/plain;charset=utf-8;' });
    const url = window.URL.createObjectURL(blob);

    const a = document.createElement('a');
    a.href = url;
    a.download = this.getTxtFileName();
    a.click();

    window.URL.revokeObjectURL(url);
  }

  getTxtFileName(): string {
    const exportType = this.ExportExcel.get('ExportType')?.value;
    const month = this.ExportExcel.get('fk_monthId')?.value;
    const year = this.ExportExcel.get('fk_yearId')?.value;

    if (exportType === 36) {
      return `PF_Challan_${month}_${year}.txt`;
    }

    if (exportType === 37) {
      return `ESI_Challan_${month}_${year}.txt`;
    }

    return `Salary_Report_${month}_${year}.txt`;
  }






  loadCompanyLogo(filename: string) {

    if (!filename) {
      this.companyLogo =
        'assets/Image/Logo/empower.jpg';
      return;
    }

    this.service.getImage(filename)
      .subscribe({

        next: (blob) => {
          const reader =
            new FileReader();

          reader.onload = () => {
            this.companyLogo = reader.result as string;

          };

          reader.readAsDataURL(blob);

        },

        error: (err) => {



          this.companyLogo =
            'assets/Image/Logo/empower.jpg';

        }

      });

  }

  onCostCenterChange() {
    let selectedValues = this.ExportExcel.controls['fk_costcentreid'].value || [];
    if (!Array.isArray(selectedValues)) {
      selectedValues = [selectedValues];
    }

    if (selectedValues.includes('__select_all__')) {
       if (this.isAllCostCentersSelected()) {
          this.selectedCostCenters = [];
       } else {
          const realValues = this.CostCenter
             .filter(c => c.value !== '__select_all__')
             .map(c => c.value);
          this.selectedCostCenters = realValues as string[];
       }
       this.ExportExcel.controls['fk_costcentreid'].setValue(this.selectedCostCenters);
    } else {
       this.selectedCostCenters = selectedValues;
    }
  }

  onCostCenterSearch(event: { term: string }) {
    if (event.term && event.term.trim().length > 0) {
      const term = event.term.toLowerCase();
      const filtered = this.CostCenter.filter(c => 
         c.value !== '__select_all__' && 
         c.name.toLowerCase().includes(term)
      );
      this.selectedCostCenters = filtered.map(c => c.value as string);
      this.ExportExcel.controls['fk_costcentreid'].setValue(this.selectedCostCenters);
    }
  }

  isAllCostCentersSelected(): boolean {
    const realCostCenters = this.CostCenter.filter(item => item.value !== '__select_all__');
    return (
      this.selectedCostCenters.length === realCostCenters.length &&
      realCostCenters.every(c => this.selectedCostCenters.includes(c.value as string))
    );
  }

  getCostCenterDisplayText(): string {
    const realCostCenters = this.CostCenter.filter(c => c.value !== '__select_all__');
    const selectedRealCostCenters = this.selectedCostCenters.filter(value => value !== '__select_all__');

    if (
      selectedRealCostCenters.length === realCostCenters.length &&
      realCostCenters.every(c => selectedRealCostCenters.includes(c.value as string))
    ) {
      return "All Selected";
    } else if (this.selectedCostCenters.length === 1) {
      return this.CostCenter.find(item => item.value === this.selectedCostCenters[0])?.name || "--Select --";
    } else if (this.selectedCostCenters.length > 1) {
      const firstSelected = this.CostCenter.find(item => item.value === this.selectedCostCenters[0])?.name;
      return firstSelected ? `${firstSelected}...` : "--Select --";
    } else {
      return "--Select --";
    }
  }

  clearCostCenters() {
    this.selectedCostCenters = [];
    this.ExportExcel.controls['fk_costcentreid'].setValue([]);
  }

}
