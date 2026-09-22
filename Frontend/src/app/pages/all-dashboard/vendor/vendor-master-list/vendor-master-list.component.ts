import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { NgxPaginationModule } from 'ngx-pagination';
import { ToastrService } from 'ngx-toastr';
import { VendorService } from '../Service/vendor.service';
import { EncryptionService } from '../../../../shared/services/encryption.service';
import { CandidateMasterService } from '../../recruitment/RecruitServices/candidate-master.service';
import * as XLSX from 'xlsx';
import * as FileSaver from 'file-saver';
import { Subject } from 'rxjs';
import { debounceTime, distinctUntilChanged } from 'rxjs/operators';

@Component({
  selector: 'app-vendor-master-list',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink, NgxPaginationModule],
  templateUrl: './vendor-master-list.component.html',
  styles: [] // empty style array to respect 'don't write scss file code'
})
export class VendorMasterListComponent implements OnInit {
  vendorList: any[] = [];
  allLoadedVendors: any[] = [];
  isSendingEmail: boolean = false;
  sendingEmailForId: string = '';
  models: any[] = [];
  searchTerm: string = '';
  pageIndex: number = 1;
  pageSize: number = 10;
  totalItems: number = 0;
  private searchSubject = new Subject<string>();

  constructor(
    private vendorService: VendorService,
    private toastrService: ToastrService,
    private router: Router,
    public encryptionService: EncryptionService,
    private candidateMasterService: CandidateMasterService
  ) { }

  ngOnInit(): void {
    this.searchSubject.pipe(
      debounceTime(300),
      distinctUntilChanged()
    ).subscribe(() => {
      this.pageIndex = 1;
      this.getAllVendors();
    });

    this.loadModels();
    this.getAllVendors();
  }

  loadModels(): void {
    const compId = sessionStorage.getItem('companyId') || 'GU-1';
    this.vendorService.getDdlListBasedOnCodeType('4', compId).subscribe(res => {
      if (res.isSuccess && res.data) {
        this.models = res.data.map((m: any) => {
          let cleanName = m.name || '';
          if (cleanName.includes(':')) {
            cleanName = cleanName.split(':')[1];
          }
          return {
            value: m.value,
            name: m.name,
            displayName: cleanName
          };
        });
      }
    });
  }

  getModelName(modelId: any): string {
    if (!modelId) return '';
    const found = this.models.find(m => m.value?.toString() === modelId?.toString());
    return found ? found.displayName : modelId;
  }

  sortVendorList(list: any[]): any[] {
    return (list || []).slice().sort((a, b) => {
      const codeA = (a.vendor_Code || a.vendorCode || a.Vendor_Code || '').toString();
      const codeB = (b.vendor_Code || b.vendorCode || b.Vendor_Code || '').toString();
      if (!codeA && !codeB) return 0;
      if (!codeA) return 1;
      if (!codeB) return -1;
      return codeA.localeCompare(codeB, undefined, { numeric: true, sensitivity: 'base' });
    });
  }

  getAllVendors(): void {
    this.vendorService.getAllVendors(this.pageIndex, this.pageSize, this.searchTerm).subscribe({
      next: (response) => {
        if (response.isSuccess) {
          const vendors = response.data.vendors || [];
          this.vendorList = [...vendors];

          // Store base loaded vendors when search term is empty
          if (!this.searchTerm || !this.searchTerm.trim()) {
            this.allLoadedVendors = [...vendors];
          }

          this.totalItems = response.data.totalCount || 0;
        } else {
          this.toastrService.error(response.message || 'Failed to fetch vendor list.');
        }
      },
      error: (err) => {
        console.error(err);
        this.toastrService.error('Error fetching vendors from server.');
      }
    });
  }

  onSearch(): void {
    const term = (this.searchTerm || '').trim().toLowerCase();

    if (!term) {
      // Search cleared! Restore base loaded vendors instantly
      if (this.allLoadedVendors && this.allLoadedVendors.length > 0) {
        this.vendorList = [...this.allLoadedVendors];
      }
      // Reload fresh page 1 from server to reset total items count
      this.pageIndex = 1;
      this.getAllVendors();
      return;
    }

    // Tier 1: Search locally in base 10 loaded vendors
    const localMatches = this.allLoadedVendors.filter(v => {
      const code = (v.vendor_Code || v.vendorCode || v.Vendor_Code || '').toLowerCase();
      const name = (v.vendor_Name || v.vendorName || v.Vendor_Name || '').toLowerCase();
      const father = (v.vendor_FatherName || v.Vendor_FatherName || '').toLowerCase();
      const contact = (v.vendor_ContactNo || v.Vendor_ContactNo || '').toLowerCase();
      const type = (v.vendor_Type || v.Vendor_Type || '').toLowerCase();
      const client = (v.clientName || v.ClientName || '').toLowerCase();
      const model = (this.getModelName(v.vendor_FK_ModelId || v.Vendor_FK_ModelId) || '').toLowerCase();
      const status = (v.vendor_Status || v.Vendor_Status || '').toLowerCase();

      return code.includes(term) ||
        name.includes(term) ||
        father.includes(term) ||
        contact.includes(term) ||
        type.includes(term) ||
        client.includes(term) ||
        model.includes(term) ||
        status.includes(term);
    });

    if (localMatches.length > 0) {
      // Matches found in base loaded records => Display local matches without API call!
      this.vendorList = localMatches;
    } else {
      // Not found in base loaded records => Trigger backend API search!
      this.searchSubject.next(this.searchTerm);
    }
  }

  onPageChange(page: number): void {
    this.pageIndex = page;
    this.getAllVendors();
  }

  editVendor(pk_recId: string): void {
    const encryptedId = this.encryptionService.encryptText(pk_recId);
    this.router.navigate(['/dash/vendor_management/vendor_managementdashboard/vendor_master_form', encryptedId]);
  }

  sendMail(pk_recId: string): void {
    this.toastrService.info('Mail functionality to be implemented.');
  }

  viewVendor(pk_recId: string): void {
    const encryptedId = this.encryptionService.encryptText(pk_recId);
    this.router.navigate(['/dash/on_boarding/on_boardingdashboard/OnboardCandidateView', encryptedId], { queryParams: { source: 'vendor_master' } });
  }

  deleteVendor(pk_recId: string): void {
    if (confirm('Are you sure you want to delete this vendor?')) {
      this.vendorService.deleteVendor(pk_recId).subscribe({
        next: (response) => {
          if (response.isSuccess) {
            this.toastrService.success('Vendor deleted successfully.');
            this.getAllVendors();
          } else {
            this.toastrService.error(response.message || 'Failed to delete vendor.');
          }
        },
        error: (err) => {
          console.error(err);
          this.toastrService.error('Error deleting vendor.');
        }
      });
    }
  }

  exportToExcel(): void {
    this.vendorService.getAllVendors(1, 100000, this.searchTerm).subscribe({
      next: (res: any) => {
        const list = res?.data?.vendors || this.vendorList;
        if (!list || list.length === 0) {
          this.toastrService.warning('No vendor data available to export.');
          return;
        }

        const exportData = list.map((item: any, index: number) => ({
          'Sr. No.': index + 1,
          'Vendor Code': item.vendor_Code || item.vendorCode || item.Vendor_Code || '',
          'Vendor Name': item.vendor_Name || item.vendorName || item.Vendor_Name || '',
          'Father Name': item.vendor_FatherName || item.Vendor_FatherName || '',
          'Contact No': item.vendor_ContactNo || item.Vendor_ContactNo || '',
          'Gender': item.vendor_Gender || item.Vendor_Gender || '',
          'Date of Birth': item.vendor_DOB || item.Vendor_DOB ? new Date(item.vendor_DOB || item.Vendor_DOB).toLocaleDateString('en-GB') : '',
          // 'Vendor Type': item.vendor_Type || item.Vendor_Type || '',
          // 'Client Name': item.clientName || item.ClientName || item.vendor_FKClientId || '',
          // 'Model Name': this.getModelName(item.vendor_FK_ModelId || item.Vendor_FK_ModelId),
          // 'HFRID': item.vendor_HFRID || item.Vendor_HFRID || '',
          // 'Rate Type': item.vendor_RateType || item.Vendor_RateType || '',
          // 'Category ID': item.vendor_CategoryID || item.Vendor_CategoryID || '',
          // 'Rate': item.vendor_Rate ?? item.Vendor_Rate ?? '',
          // 'Rate Deduction': item.vendor_RateDeduction ?? item.Vendor_RateDeduction ?? '',
          // 'Delivery Rate': item.vendor_DeliveryRate ?? item.Vendor_DeliveryRate ?? '',
          // 'Pickup Rate': item.vendor_PickupRate ?? item.Vendor_PickupRate ?? '',
          // 'MFN Rate': item.vendor_MFNRate ?? item.Vendor_MFNRate ?? '',
          // 'TDS Percentage': item.vendor_TDSPercentage ?? item.Vendor_TDSPercentage ?? '',
          // 'Verification Status': item.vendor_Status || item.Vendor_Status || 'Not Verified',
          'Registration Date': item.vendor_RegistrationDate || item.Vendor_RegistrationDate ? new Date(item.vendor_RegistrationDate || item.Vendor_RegistrationDate).toLocaleDateString('en-GB') : '',
          'Current Address': item.vendor_Address || item.Vendor_Address || '',
          'State': item.stateName || item.StateName || item.vendor_State || item.Vendor_State || '',
          'City': item.cityName || item.CityName || item.vendor_City || item.Vendor_City || '',
          'Permanent Address': item.vendor_PermanentAddress || item.Vendor_PermanentAddress || item.vendor_Address || item.Vendor_Address || '',
          'Permanent State': item.vendor_PermState || item.Vendor_PermState || item.stateName || item.StateName || item.vendor_State || item.Vendor_State || '',
          'Permanent City': item.vendor_PermCity || item.Vendor_PermCity || item.cityName || item.CityName || item.vendor_City || item.Vendor_City || '',
          'Bank Name': item.bankMasterName || item.BankMasterName || item.vendor_BankName || item.Vendor_BankName || '',
          'Account No': item.vendor_AccountNo || item.Vendor_AccountNo || '',
          'IFSC Code': item.bankIFSC || item.BankIFSC || item.vendor_IFSCCode || item.Vendor_IFSCCode || '',
          'PAN No': item.vendor_PanNo || item.Vendor_PanNo || '',
          'Aadhaar No': item.vendor_AaddharNo || item.Vendor_AaddharNo || '',
          'GST No': item.vendor_GSTNo || item.Vendor_GSTNo || '',
          'GST Applicable': (item.vendor_IsGSTApplicable || item.Vendor_IsGSTApplicable) ? 'Yes' : 'No',
          'GST %': item.vendor_GSTRate ?? item.Vendor_GSTRate ?? '',
          'TDS Applicable': (item.vendor_IsTDSApplicable || item.Vendor_IsTDSApplicable) ? 'Yes' : 'No',
          'TDS %': item.vendor_TDSPercentage ?? item.Vendor_TDSPercentage ?? ''
        }));

        const worksheet: XLSX.WorkSheet = XLSX.utils.json_to_sheet(exportData);

        // --- ADD THIS BLOCK FOR AUTO-EXPANDING COLUMNS ---
        const columnWidths: any[] = [];

        exportData.forEach((row: any) => {
          Object.keys(row).forEach((key, index) => {
            // Get the length of the actual cell value
            const cellValue = row[key] ? row[key].toString() : '';
            const valueLength = cellValue.length;

            // Get current max width for this column, default to the header name's length
            const currentMaxWidth = columnWidths[index] || key.length;

            // Set the new max width
            columnWidths[index] = Math.max(currentMaxWidth, valueLength);
          });
        });
        // Apply the calculated widths to the worksheet (adding 2 for slight padding)
        worksheet['!cols'] = columnWidths.map(w => ({ wch: w + 2 }));
        // -------------------------------------------------

        const workbook: XLSX.WorkBook = {
          Sheets: { 'VendorMasterList': worksheet },
          SheetNames: ['VendorMasterList']
        };

        const excelBuffer: any = XLSX.write(workbook, {
          bookType: 'xlsx',
          type: 'array'
        });

        const data: Blob = new Blob([excelBuffer], {
          type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;charset=UTF-8'
        });

        FileSaver.saveAs(data, `Vendor_Master_List_${new Date().getTime()}.xlsx`);
        this.toastrService.success('Vendor Master List exported to Excel successfully!');
      },
      error: (err: any) => {
        console.error(err);
        this.toastrService.error('Failed to export vendor list.');
      }
    });
  }

  sendOnboardingEmail(pk_recId: string, vendorName: string): void {
    if (confirm(`Send onboarding email to ${vendorName}?`)) {
      this.isSendingEmail = true;
      this.sendingEmailForId = pk_recId;

      this.candidateMasterService.sendOnboardingEmail(pk_recId).subscribe({
        next: (response) => {
          this.isSendingEmail = false;
          this.sendingEmailForId = '';
          if (response.isSuccess) {
            this.toastrService.success(response.message || 'Onboarding email sent successfully', 'Success');
            this.getAllVendors();
          } else {
            this.toastrService.error(response.message || 'Failed to send onboarding email', 'Error');
          }
        },
        error: () => {
          this.isSendingEmail = false;
          this.sendingEmailForId = '';
          this.toastrService.error('Failed to send onboarding email', 'Error');
        }
      });
    }
  }


  downloadVendorVerificationExcel(): void {
    this.toastrService.info('Preparing Vendor Excel download...');
    this.vendorService.getVendorDownloadVerificationList(1, 100000, this.searchTerm).subscribe({
      next: (res: any) => {
        const list = res?.data?.vendors || [];
        if (!list || list.length === 0) {
          this.toastrService.warning('No vendor data available to download.');
          return;
        }

        const exportData = list.map((item: any) => ({
          'Vendor Code': item.vendorCode,
          'Vendor Name': item.vendorName,
          'Email': item.email,
          'Verification Link': item.verificationLink,
          'Status': item.status
        }));

        const worksheet: XLSX.WorkSheet = XLSX.utils.json_to_sheet(exportData);

        // Auto-expand columns width
        const columnWidths: any[] = [];
        exportData.forEach((row: any) => {
          Object.keys(row).forEach((key, index) => {
            const cellValue = row[key] ? row[key].toString() : '';
            const valueLength = cellValue.length;
            const currentMaxWidth = columnWidths[index] || key.length;
            columnWidths[index] = Math.max(currentMaxWidth, valueLength);
          });
        });
        worksheet['!cols'] = columnWidths.map(w => ({ wch: w + 3 }));

        const workbook: XLSX.WorkBook = {
          Sheets: { 'Vendors': worksheet },
          SheetNames: ['Vendors']
        };

        const excelBuffer: any = XLSX.write(workbook, {
          bookType: 'xlsx',
          type: 'array'
        });

        const data: Blob = new Blob([excelBuffer], {
          type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;charset=UTF-8'
        });

        FileSaver.saveAs(data, 'Vendor_List.xlsx');
        this.toastrService.success('Vendor Excel downloaded successfully!');
      },
      error: (err: any) => {
        console.error(err);
        this.toastrService.error('Failed to download vendor excel.');
      }
    });
  }
}