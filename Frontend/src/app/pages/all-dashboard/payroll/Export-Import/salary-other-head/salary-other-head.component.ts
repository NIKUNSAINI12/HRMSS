import { CommonModule } from '@angular/common';
import { Component } from '@angular/core';
import { FormBuilder, FormControl, FormGroup, FormsModule, ReactiveFormsModule, Validators } from '@angular/forms';
import { Router } from '@angular/router';
import { NgSelectModule } from '@ng-select/ng-select';
import { NgxPaginationModule } from 'ngx-pagination';
import { ToastrService } from 'ngx-toastr';
import { NgxUiLoaderService } from 'ngx-ui-loader';
import { forkJoin } from 'rxjs';
import { MonthlyRentDetailService } from '../../services/monthly-rent-detail.service'; // Update service if different
import { DropdownService } from '../../../../../shared/services/dropdown.service';
import { CommonSearchComponent } from '../../Employee/common-search/common-search.component';
import { ImportAttendancePunchService } from '../../services/import-attendance-punch.service';
import * as XLSX from 'xlsx';
import * as FileSaver from 'file-saver';
import { ManualPunchBio } from '../../services/manual-puch-bio.service';
import { DarclFactBoxComponent } from '../../../vendor/shared/darcl-fact-box/darcl-fact-box.component';
import { UploadFileHistoryService } from '../../../vendor/Service/upload-file-history.service';

@Component({
  selector: 'app-export-import-salary-other-head',
  standalone: true,
  imports: [ReactiveFormsModule, FormsModule, CommonModule, NgSelectModule, CommonSearchComponent, NgxPaginationModule, DarclFactBoxComponent],
  templateUrl: './salary-other-head.component.html',
  styleUrl: './salary-other-head.component.scss'
})
export class ExportImportSalaryOtherHeadComponent {

  EmployeeForm!: FormGroup;
  submitted = false;
  showError = false;
  totalCount: number = 0;
  pageIndex: number = 1;
  pageSize: number = 10;
  messag: string = '';
  isExporting = false;
  showImportView = false;
  isImporting = false;
  errormessag: string = '';
  salaryHeadList: any[] = [];
  filteredData: any[] = [];
  searchtext: string = '';
  months: any[] = [];
  years: any[] = [];
  selectedFile: File | undefined;
  exportsalaryheadlist: any[] = [];
  searchControl = new FormControl('');
  CostCenter: { name: string; value: string | null }[] = [];
  selectedCostCenters: string[] = [];

  isContractApplicable = false;
  headlist = [];
  isViewing = false;

  // --- Fact Box Properties ---
  isFactBoxOpen: boolean = true;
  factBoxFiles: any[] = [];
  pageIndexFactBox: number = 1;
  pageSizeFactBox: number = 5;
  totalUploadedFiles: number = 0;
  isLoadingFactBox: boolean = false;

  constructor(
    private fb: FormBuilder,
    private toastrService: ToastrService,
    private router: Router,
    private httpservice: ImportAttendancePunchService, // Update service if required
    private loader: NgxUiLoaderService,
    private dropdownService: DropdownService,
    private commanService: ManualPunchBio,
    private uploadHistoryService: UploadFileHistoryService
  ) { }

  ngOnInit() {
    this.isContractApplicable = sessionStorage.getItem('ContractApplicable') == "false" ? false : true || false;
    this.loadFactBoxFiles();


    this.searchControl.valueChanges.subscribe(value => {
      this.searchtext = value?.toLowerCase() || '';
      this.filterData();
    });
    this.EmployeeForm = this.fb.group({
      empCode: [''],
      empName: [''],
      selectedLocations: [[]],
      selectedDepartments: [[]],
      selectedDesignation: [''],
      selectedNature: [''],
      selectedCity: [''],
      sortBy: [''],
      empStatus: [''],
      Fk_FinId: [''],
      Fk_CompanyId: [''],
      EffectiveDate: [Date],
      file: [null, [Validators.required, Validators.pattern(/\.(xlsx)$/i)]],
      headType: ['E,R'],
      fk_costcentreid: [[]],
       heads: [[]]
    });

     this.getCostCenterList();
     this.getheadList();
  }



  exportTemplate() {

     if (this.isExporting) return; // prevent double click
       const formData = { ...this.EmployeeForm.value };
        // validate heads selection
  if (!formData.heads || formData.heads.length === 0) {
    this.toastrService.warning('Please select a head', 'Warning'); 
    // or use whatever notification service you're using, e.g. alert('Please select a head');
    return;
  }

  const effDate = formData.EffectiveDate;
  const isInvalidDate = !effDate || 
                         typeof effDate === 'function' || 
                         effDate === Date || 
                         !effDate.toString().trim() ||
                         isNaN(new Date(effDate).getTime());

  if (isInvalidDate) {
    this.toastrService.warning('Please select an effective date.', 'Warning');
    return;
  }
    this.isExporting = true;
  

    Object.keys(formData).forEach(key => {
      if (formData[key] === null) {
        formData[key] = '';
      }
    });
    if (Array.isArray(formData.fk_costcentreid)) {
      formData.fk_costcentreid = formData.fk_costcentreid.join(',');
    }
    //  formData.heads = Array.isArray(formData.heads)
    //   ? formData.heads.filter((h: any) => h !== null && h !== undefined && h !== '').join(',')
    //   : (formData.heads || '');
    this.httpservice.ExportSalaryOtherHead(formData).subscribe({
      next: (res) => {
         this.isExporting = false;
        this.exportsalaryheadlist = res.data

        this.downloadExcel();
      }
    })
  }
  downloadExcel(): void {
    const filteredData = this.exportsalaryheadlist;
    const ws = XLSX.utils.json_to_sheet(filteredData);
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, 'Salary List');
    XLSX.writeFile(wb, 'SalaryHeadData.xlsx');
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

  onCostCenterChange() {
    let selectedValues = this.EmployeeForm.controls['fk_costcentreid'].value || [];
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
       this.EmployeeForm.controls['fk_costcentreid'].setValue(this.selectedCostCenters);
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
      this.EmployeeForm.controls['fk_costcentreid'].setValue(this.selectedCostCenters);
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
    this.EmployeeForm.controls['fk_costcentreid'].setValue([]);
  }

   getheadList() {
    this.commanService.getCommanList('Head_allowImportMonthly').subscribe({
      next: (res) => {
        res.data = res.data.slice(1);
        this.headlist = res.data

      }
    })
  }

  onSubmit() {
    debugger
    if (this.isViewing) return;
    this.submitted = true;
    this.showError = true;
    this.EmployeeForm.get('file')?.clearValidators();
    this.EmployeeForm.get('file')?.updateValueAndValidity();
    if (this.EmployeeForm.invalid) return;

    const formValues = this.EmployeeForm.value;

    if (!formValues.sortBy) {
      this.toastrService.warning('Please select Sort By');
      return;
    }
    if (!formValues.selectedDepartments.length) {
      this.toastrService.warning('Please select at least one Department');
      return;
    }
    if (!formValues.selectedLocations.length) {
      this.toastrService.warning('Please select at least one Location');
      return;
    }
     this.isViewing = true;

    this.getSalaryHeadData();
    this.EmployeeForm.get('file')?.setValidators([Validators.required, Validators.pattern(/\.(xlsx)$/i)]);
    this.EmployeeForm.get('file')?.updateValueAndValidity();
  }

  getSalaryHeadData() {
    const formData = { ...this.EmployeeForm.value };
    Object.keys(formData).forEach(key => {
      if (formData[key] === null) formData[key] = '';
    });
    if (Array.isArray(formData.fk_costcentreid)) {
      formData.fk_costcentreid = formData.fk_costcentreid.join(',');
    }

    const payload = {
      pageIndex: this.pageIndex - 1,
      pageSize: this.pageSize,
      ...formData
    };

    this.loader.start();
    this.httpservice.GetEmpOtherHeadExportImport(payload).subscribe({
      next: (res: any) => {
         this.isViewing = false;
        this.loader.stop();
        if (res.isSuccess) {

          this.salaryHeadList = res.data || [];
          this.totalCount = res.totalCount
          this.filteredData = [...this.salaryHeadList];
        } else {
          this.salaryHeadList = [];
          this.toastrService.info(res.message || 'No data found');
        }
      },
      error: (err) => {
         this.isViewing = false;
        this.loader.stop();
        this.toastrService.error(err.message || 'Failed to fetch data');
      }
    });
  }

  onPageChange(event: number): void {
    this.pageIndex = event;
    this.getSalaryHeadData();
  }

  filterData() {
    const lowerText = this.searchtext.toLowerCase();
    this.filteredData = this.salaryHeadList.filter(item =>
      Object.values(item).some(val =>
        val?.toString().toLowerCase().includes(lowerText)
      )
    );
  }

  handleFilters(filters: any) {
    this.EmployeeForm.patchValue(filters);
  }

  onFileChange(event: any) {
    const file = event.target.files[0];
    if (file && file.name.endsWith('.xlsx')) {
      this.selectedFile = file;
      this.EmployeeForm.get('file')?.setValue(file); // Set value to form control
    } else {
      this.EmployeeForm.get('file')?.setErrors({ pattern: true });
    }
  }


  Import() {
    if (this.isImporting) return;

    if (this.EmployeeForm.invalid) {
      this.EmployeeForm.markAllAsTouched();
      return;
    }
    if (!this.EmployeeForm.get('EffectiveDate')?.value) {
      this.toastrService.warning('Please select an effective date.', 'Warning');
      return;
    }

    if (this.selectedFile) {
      this.isImporting = true;
      const formData = new FormData();
      formData.append('file', this.selectedFile!, this.selectedFile!.name);
      formData.append('EffectiveDate', this.EmployeeForm.get('EffectiveDate')?.value);

      this.loader.start();
      this.httpservice.SalaryOtherHead_ForImport(formData).subscribe({
        next: (res) => {
          if (res.isSuccess) {
            this.messag = res.message;
            this.errormessag = '';
          } else {
            this.errormessag = res.message;
            this.messag = '';
          }
          this.isImporting = false;
          this.loader.stop();

          // Save upload history and refresh Fact Box
          if (this.selectedFile) {
            const resultPayload = res?.data ? res.data : { isSuccess: res?.isSuccess, message: res?.message || this.errormessag };
            this.uploadHistoryService.saveUploadHistory(this.selectedFile, 'SALARY_OTHER_HEAD_IMPORT', resultPayload).subscribe({
              next: () => {
                this.pageIndexFactBox = 1;
                this.loadFactBoxFiles();
              },
              error: (e) => console.error('Error recording salary other head upload history:', e)
            });
          }
        },
        error: (err) => {
          this.isImporting = false;
          this.loader.stop();
          this.errormessag = err?.message || 'Error occurred during import.';
          if (this.selectedFile) {
            this.uploadHistoryService.saveUploadHistory(this.selectedFile, 'SALARY_OTHER_HEAD_IMPORT', { isSuccess: false, message: this.errormessag }).subscribe({
              next: () => {
                this.pageIndexFactBox = 1;
                this.loadFactBoxFiles();
              },
              error: (e) => console.error('Error recording salary other head upload history:', e)
            });
          }
        }
      });
    }
  }

  toggleFactBox(): void {
    this.isFactBoxOpen = !this.isFactBoxOpen;
  }

  loadFactBoxFiles(): void {
    this.isLoadingFactBox = true;
    this.uploadHistoryService.getUploadHistory('SALARY_OTHER_HEAD_IMPORT', this.pageIndexFactBox, this.pageSizeFactBox).subscribe({
      next: (res: any) => {
        this.isLoadingFactBox = false;
        if (res && res.data) {
          this.factBoxFiles = res.data.list || [];
          this.totalUploadedFiles = res.data.totalCount || 0;
        } else {
          this.factBoxFiles = [];
          this.totalUploadedFiles = 0;
        }
      },
      error: (err: any) => {
        this.isLoadingFactBox = false;
        console.error('Error loading Fact Box files:', err);
      }
    });
  }

  onFactBoxPageChange(page: number): void {
    this.pageIndexFactBox = page;
    this.loadFactBoxFiles();
  }

  downloadFactBoxFile(file: any): void {
    const fileId = file.id || file.pk_id || file.fileId;
    const fileName = file.file_name || file.fileName || 'SalaryOtherHead_Import.xlsx';
    if (!fileId) return;

    this.loader.start();
    this.uploadHistoryService.downloadFile(fileId).subscribe({
      next: (blob: Blob) => {
        this.loader.stop();
        FileSaver.saveAs(blob, fileName);
      },
      error: (err: any) => {
        this.loader.stop();
        console.error('Error downloading file from Fact Box:', err);
        this.toastrService.error('Unable to download file.');
      }
    });
  }

  toggleImportView(): void {
    this.messag = '';
    this.errormessag = '';
    this.showImportView = !this.showImportView;
    // Clear the file
    this.selectedFile = undefined;
    this.EmployeeForm.get('file')?.reset();
  }


}
