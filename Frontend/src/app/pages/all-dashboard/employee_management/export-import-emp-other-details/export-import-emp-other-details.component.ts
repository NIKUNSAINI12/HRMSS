import { CommonModule } from '@angular/common';
import { Component } from '@angular/core';
import { FormBuilder, FormControl, FormGroup, FormsModule, ReactiveFormsModule, Validators } from '@angular/forms';
import { Router } from '@angular/router';
import { NgSelectModule } from '@ng-select/ng-select';
import { NgxPaginationModule } from 'ngx-pagination';
import { ToastrService } from 'ngx-toastr';
import { NgxUiLoaderService } from 'ngx-ui-loader';
import { forkJoin } from 'rxjs';
import * as XLSX from 'xlsx'
import { ImportAttendancePunchService } from '../../payroll/services/import-attendance-punch.service';
import { DropdownService } from '../../../../shared/services/dropdown.service';
import { ManualPunchBio } from '../../payroll/services/manual-puch-bio.service';
import { CommonSearchComponent } from '../../payroll/Employee/common-search/common-search.component';
@Component({
  selector: 'app-export-import-emp-other-details',
  standalone: true,
  imports: [ReactiveFormsModule, FormsModule, CommonModule, NgSelectModule, CommonSearchComponent, NgxPaginationModule],

  templateUrl: './export-import-emp-other-details.component.html',
  styleUrl: './export-import-emp-other-details.component.scss'
})
export class ExportImportEmpOtherDetailsComponent {

  EmployeeForm!: FormGroup;
  submitted = false;
  showError = false;
  totalCount: number = 0
  pageIndex: number = 1;
  pageSize: number = 10;
  pagesize: number = 10000;
  messag: string = '';
  showImportView = false
  errormessag: string = '';
  isExporting = false;

  empOtherDetlList: any[] = [];

  filteredData: any[] = [];
  searchtext: string = ''
  months: any[] = [];
  years: any[] = [];
  selectedFile: File | undefined | null = null;
  exportsalaryheadlist: any[] = [];
  searchControl = new FormControl('');
  CostCenter: { name: string; value: string | null }[] = [];
  selectedCostCenters: string[] = [];
  isContractApplicable = false;
  constructor(
    private fb: FormBuilder,
    private toastrService: ToastrService,
    private router: Router,
    private httpservice: ImportAttendancePunchService, // Update service if required
    private loader: NgxUiLoaderService,
    private dropdownService: DropdownService,
    private commanService: ManualPunchBio,
  ) { }

  ngOnInit() {
    this.isContractApplicable = sessionStorage.getItem('ContractApplicable') == "false" ? false : true || false;

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
      fk_costcentreid: [[]],
      file: [null, [Validators.required, Validators.pattern(/\.(xlsx)$/i)]],
    });

    this.getCostCenterList();
  }



  exportTemplate() {
    if (this.isExporting) return; // prevent double click
    this.isExporting = true;

    const formData = { ...this.EmployeeForm.value };

    Object.keys(formData).forEach(key => {
      if (formData[key] === null) {
        formData[key] = '';
      }
    });

    const payload = {
      pageIndex: this.pageIndex - 1,
      pageSize: this.pageSize,
      ...formData
    };

    if (Array.isArray(payload.fk_costcentreid)) {
      payload.fk_costcentreid = payload.fk_costcentreid.join(',');
    }
    this.httpservice.GetEmpOtherDetailExportImport(payload).subscribe({
      next: (res) => {
        this.exportsalaryheadlist = res.data

        this.downloadExcel();
        this.isExporting = false;
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
    });
  }

  downloadExcel(): void {
    const filteredData = this.exportsalaryheadlist;
    const ws = XLSX.utils.json_to_sheet(filteredData);
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, 'Sheet1');
    XLSX.writeFile(wb, 'EmpOtherDetails.xlsx');
  }


  onSubmit() {
    debugger
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
    console.log(this.getEmpOtherData());
    this.getEmpOtherData();
    this.EmployeeForm.get('file')?.setValidators([Validators.required, Validators.pattern(/\.(xlsx)$/i)]);
    this.EmployeeForm.get('file')?.updateValueAndValidity();
  }

  getEmpOtherData() {
    const formData = { ...this.EmployeeForm.value };
    Object.keys(formData).forEach(key => {
      if (formData[key] === null) formData[key] = '';
    });

    const payload = {
      pageIndex: this.pageIndex - 1,
      pageSize: this.pagesize,
      ...formData
    };

    if (Array.isArray(payload.fk_costcentreid)) {
      payload.fk_costcentreid = payload.fk_costcentreid.join(',');
    }


    this.loader.start();
    // this.httpservice.GetEmpHeadExportImport(payload).subscribe({
    this.httpservice.GetEmpOtherDetailExportImport(payload).subscribe({
      next: (res: any) => {
        this.loader.stop();
        if (res.isSuccess) {

          this.empOtherDetlList = res.data || [];
          this.totalCount = res.totalCount
          this.filteredData = [...this.empOtherDetlList];
        } else {
          this.empOtherDetlList = [];
          this.toastrService.info(res.message || 'No data found');
        }
      },
      error: (err) => {
        this.loader.stop();
        this.toastrService.error(err.message || 'Failed to fetch data');
      }
    });
  }

  onPageChange(event: number): void {
    this.pageIndex = event;
    this.getEmpOtherData();
  }

  filterData() {
    const lowerText = this.searchtext.toLowerCase();
    this.filteredData = this.empOtherDetlList.filter(item =>
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


  Importtt() {
    if (this.EmployeeForm.invalid) {
      this.EmployeeForm.markAllAsTouched();
      return;
    }

    if (this.selectedFile) {
      const formData = new FormData();
      formData.append('file', this.selectedFile!, this.selectedFile!.name);
      this.loader.start();
      this.httpservice.EmpOtherDetailImport(formData).subscribe({
        next: (res) => {
          if (res.isSuccess) {
            this.messag = res.message;
            this.errormessag = '';
          } else {
            this.errormessag = res.message;
            this.messag = '';
          }

          //  Reset file after import
          this.selectedFile = null;
          this.EmployeeForm.get('file')?.reset();


          this.loader.stop();
        },
        error: (error) => {
          this.errormessag = error?.error?.message;
          this.messag = "";

          //  Reset file when import fails also
          this.selectedFile = null;
          this.EmployeeForm.get('file')?.reset();

          // const inputFile = document.getElementById('fileInput') as HTMLInputElement;
          // if (inputFile) inputFile.value = "";
          this.loader.stop();
        }
      });
    }
  }

  Import() {

    if (this.EmployeeForm.invalid) {
      this.EmployeeForm.markAllAsTouched();
      return;
    }

    if (this.selectedFile) {
      const formData = new FormData();
      formData.append('file', this.selectedFile!, this.selectedFile!.name);
      // formData.append('FkYearId', this.EmployeeForm.get('FkYearId')?.value);
      this.loader.start();
      this.httpservice.EmpOtherDetailImport(formData).subscribe({
        next: (res) => {
          if (res.isSuccess) {
            this.messag = res.message; //  corrected
            this.errormessag = '';      // clear error message
          } else {
            this.errormessag = res.message; // ✅ corrected
            this.messag = '';               // clear success message
          }
          this.loader.stop();
        }
      });
    }
  }
  toggleImportView(): void {
    this.messag = '';
    this.errormessag = '';
    this.showImportView = !this.showImportView;
    // Clear the file
    this.selectedFile = undefined;
    this.EmployeeForm.get('file')?.reset();
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


}
