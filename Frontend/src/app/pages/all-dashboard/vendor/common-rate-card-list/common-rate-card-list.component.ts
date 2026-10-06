import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { ToastrService } from 'ngx-toastr';
import { NgxPaginationModule } from 'ngx-pagination';
import * as XLSX from 'xlsx-js-style';
import * as FileSaver from 'file-saver';
import { Subject } from 'rxjs';
import { debounceTime, distinctUntilChanged } from 'rxjs/operators';

import { EncryptionService } from '../../../../shared/services/encryption.service';
import { CommonRateCardService } from '../common-rate-card.service';

@Component({
  selector: 'app-common-rate-card-list',
  standalone: true,
  imports: [RouterLink, CommonModule, FormsModule, NgxPaginationModule],
  templateUrl: './common-rate-card-list.component.html',
  styles: []
})
export class CommonRateCardListComponent implements OnInit {
  rateCards: any[] = [];
  allLoadedRateCards: any[] = [];
  searchText: string = '';
  searchTerm: string = '';
  pageIndex: number = 1;
  pageSize: number = 10;
  totalItems: number = 0;
  isLoading: boolean = false;
  private searchSubject = new Subject<string>();

  constructor(
    private rateCardService: CommonRateCardService,
    private toastr: ToastrService,
    private router: Router,
    public encryptionService: EncryptionService
  ) {}

  ngOnInit(): void {
    this.searchSubject.pipe(
      debounceTime(300),
      distinctUntilChanged()
    ).subscribe(() => {
      this.pageIndex = 1;
      this.getRateCards();
    });

    this.getRateCards();
  }

  getRateCards(): void {
    this.isLoading = true;
    this.rateCardService.getAll(this.pageIndex - 1, this.pageSize, this.searchTerm).subscribe({
      next: (res: any) => {
        this.isLoading = false;
        if (res?.isSuccess && res?.data) {
          let list: any[] = [];
          if (Array.isArray(res.data)) {
            list = res.data;
          } else if (Array.isArray(res.data.list)) {
            list = res.data.list;
          }
          this.rateCards = [...list];

          // Store base loaded rate cards when search term is empty
          if (!this.searchTerm || !this.searchTerm.trim()) {
            this.allLoadedRateCards = [...list];
          }

          this.totalItems = res.totalCount || res.data?.totalCount || this.rateCards.length;
        } else {
          this.rateCards = [];
          this.totalItems = 0;
        }
      },
      error: (err: any) => {
        this.isLoading = false;
        this.rateCards = [];
        this.totalItems = 0;
        this.toastr.error(err?.error?.message || 'Error loading Rate Cards.', 'Error');
      }
    });
  }

  onPageChange(event: number): void {
    this.pageIndex = event;
    this.getRateCards();
  }

  onSearch(): void {
    const term = (this.searchText || '').trim().toLowerCase();

    if (!term) {
      // Search cleared! Restore base loaded rate cards instantly
      if (this.allLoadedRateCards && this.allLoadedRateCards.length > 0) {
        this.rateCards = [...this.allLoadedRateCards];
      }
      this.searchTerm = '';
      this.pageIndex = 1;
      this.getRateCards();
      return;
    }

    // Tier 1: Search locally in base loaded rate cards
    const localMatches = (this.allLoadedRateCards || []).filter((rc: any) => {
      const client = (rc.ClientName || '').toLowerCase();
      const model = (rc.ModelName || '').toLowerCase();
      const fhrId = (rc.FHRID || '').toLowerCase();
      const location = (rc.LocationName || '').toLowerCase();
      const largeVehicle = (rc.Large_VehicleTypeName || '').toLowerCase();
      const vehicle = (rc.VehicleTypeName || '').toLowerCase();
      const effectiveFrom = (this.formatDateDMY(rc.EffectiveFrom) || '').toLowerCase();

      return client.includes(term) ||
        model.includes(term) ||
        fhrId.includes(term) ||
        location.includes(term) ||
        largeVehicle.includes(term) ||
        vehicle.includes(term) ||
        effectiveFrom.includes(term);
    });

    if (localMatches.length > 0) {
      // Matches found in base loaded records => Display local matches without API call!
      this.rateCards = localMatches;
    } else {
      // Not found in base loaded records => Trigger backend API search with debounce!
      this.searchTerm = this.searchText ? this.searchText.trim() : '';
      this.searchSubject.next(this.searchTerm);
    }
  }

  isUpdate(pk_RateCardID: string): void {
    this.router.navigate(['/dash/vendor_management/vendor_managementdashboard/common_rate_card', pk_RateCardID]);
  }

  onEditClick(item: any): void {
    const rawId = item?.pk_RateCardID ?? item?.pk_RateCardId ?? item?.pk_rateCardID ?? item?.pk_ratecardid ?? item?.id ?? item?.PK_RateCardID;
    if (rawId !== null && rawId !== undefined && rawId !== '') {
      try {
        const encrypted = this.encryptionService.encryptText(rawId.toString());
        this.isUpdate(encrypted);
      } catch (err) {
        this.isUpdate(rawId.toString());
      }
    }
  }

  editRateCard(item: any): void {
    this.onEditClick(item);
  }

  deleteRateCard(id: number | undefined): void {
    if (!id) return;
    if (confirm('Are you sure you want to delete this Rate Card?')) {
      this.rateCardService.delete(id).subscribe({
        next: (res: any) => {
          if (res?.isSuccess) {
            this.toastr.success('Rate card deleted successfully.', 'Deleted');
            this.getRateCards();
          } else {
            this.toastr.error(res?.message || 'Failed to delete rate card.', 'Error');
          }
        },
        error: (err: any) => {
          this.toastr.error(err?.error?.message || 'Server error occurred while deleting.', 'Error');
        }
      });
    }
  }

  cleanVehicleName(rawName: string): string {
    if (!rawName) return '';
    let name = rawName.toString().trim();
    if (name.includes(':')) {
      const parts = name.split(':');
      name = parts[parts.length - 1].trim();
    }
    return name;
  }

  formatDateDMY(dateVal: any): string {
    if (!dateVal) return '-';
    try {
      const d = new Date(dateVal);
      if (isNaN(d.getTime())) return dateVal.toString();
      const day = String(d.getDate()).padStart(2, '0');
      const month = String(d.getMonth() + 1).padStart(2, '0');
      const year = d.getFullYear();
      return `${day}-${month}-${year}`;
    } catch {
      return dateVal.toString();
    }
  }

  exportToExcel(): void {
    this.rateCardService.getAll(0, 100000, this.searchTerm).subscribe({
      next: (res: any) => {
        const list = Array.isArray(res?.data) ? res.data : (Array.isArray(res?.data?.list) ? res.data.list : []);
        const exportData = list.map((rc: any, idx: number) => ({
          'Sr.No.': idx + 1,
          'Client': rc.ClientName || '-',
          'Model': rc.ModelName || '-',
          'FHR ID': rc.FHRID || '-',
          'Location': rc.LocationName || '-',
          'Effective From': this.formatDateDMY(rc.EffectiveFrom)
        }));

        if (exportData.length === 0) {
          this.toastr.warning('No rate card data found to export.', 'No Data');
          return;
        }

        const worksheet = XLSX.utils.json_to_sheet(exportData);
        const workbook = XLSX.utils.book_new();
        XLSX.utils.book_append_sheet(workbook, worksheet, 'CommonRateCards');

        const excelBuffer: any = XLSX.write(workbook, { bookType: 'xlsx', type: 'array' });
        const data: Blob = new Blob([excelBuffer], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;charset=UTF-8' });
        FileSaver.saveAs(data, `Common_Rate_Cards_${this.formatDateDMY(new Date())}.xlsx`);
        this.toastr.success('Rate cards exported to Excel successfully!', 'Export Success');
      },
      error: () => {
        this.toastr.error('Failed to export rate cards.', 'Export Error');
      }
    });
  }
}
