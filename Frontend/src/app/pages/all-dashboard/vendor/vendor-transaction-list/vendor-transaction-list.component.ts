import { Component, OnInit } from '@angular/core';
import { FormBuilder, FormGroup, ReactiveFormsModule, FormsModule } from '@angular/forms';
import { CommonModule } from '@angular/common';
import { NgSelectModule } from '@ng-select/ng-select';
import { NgxPaginationModule } from 'ngx-pagination';
import { ToastrService } from 'ngx-toastr';
import { NgxUiLoaderService } from 'ngx-ui-loader';
import { Subject, Observable, of, concat } from 'rxjs';
import { catchError, debounceTime, distinctUntilChanged, switchMap, tap } from 'rxjs/operators';

import { VendorService } from '../Service/vendor.service';
import { ManualPunchBio } from '../../payroll/services/manual-puch-bio.service';
import { ClientMasterService } from '../../payroll/services/client-master.service';
import { DropdownService } from '../../../../shared/services/dropdown.service';
import { environment } from '../../../../../environments/environment';
import * as FileSaver from 'file-saver';

@Component({
  selector: 'app-vendor-transaction-list',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule, FormsModule, NgSelectModule, NgxPaginationModule],
  templateUrl: './vendor-transaction-list.component.html',
  styleUrls: ['./vendor-transaction-list.component.scss']
})
export class VendorTransactionListComponent implements OnInit {
  filterForm!: FormGroup;

  clientList: any[] = [];
  modelList: any[] = [];
  locationList: any[] = [];
  transactionRanges: any[] = [];

  vendorCodes$: Observable<any[]>;
  vendorCodeInput$ = new Subject<string>();
  isVendorsLoading = false;

  transactions: any[] = [];
  previewKeys: string[] = [];
  formulaMap: any = {};
  totalItems: number = 0;
  pageIndex: number = 1;
  pageSize: number = 10;
  searchTerm: string = '';

  constructor(
    private fb: FormBuilder,
    private vendorService: VendorService,
    private commonMasterService: ManualPunchBio,
    private clientService: ClientMasterService,
    private dropdownService: DropdownService,
    private toastrService: ToastrService,
    private ngxService: NgxUiLoaderService
  ) {
    this.vendorCodes$ = concat(
      of([]), // default empty list
      this.vendorCodeInput$.pipe(
        debounceTime(300),
        distinctUntilChanged(),
        tap(() => (this.isVendorsLoading = true)),
        switchMap((term) => {
          if (!term || term.length < 3) {
            this.isVendorsLoading = false;
            return of([]);
          }
          return this.vendorService.searchVendors(term).pipe(
            catchError(() => of({ data: [] })),
            switchMap(res => {
              this.isVendorsLoading = false;
              return of(res?.data || []);
            })
          );
        })
      )
    );
  }

  ngOnInit(): void {
    this.filterForm = this.fb.group({
      client: [null],
      model: [null],
      location: [null],
      transactionRange: [null],
      vendorCode: [null]
    });

    this.getCostCenterList();
    this.loadLocations();

    this.filterForm.get('client')?.valueChanges.subscribe(clientId => {
      this.filterForm.get('model')?.setValue(null);
      this.filterForm.get('transactionRange')?.setValue(null);
      this.modelList = [];
      this.transactionRanges = [];
      this.filterModelsByClient(clientId || 0);
    });

    this.filterForm.get('model')?.valueChanges.subscribe(modelId => {
      this.filterForm.get('transactionRange')?.setValue(null);
      this.transactionRanges = [];
      const clientId = this.filterForm.get('client')?.value;
      if (clientId && modelId) {
        this.loadTransactionRanges(clientId, modelId);
      }
    });
  }

  getCostCenterList(): void {
    this.commonMasterService.getCommanList('CostCenter').subscribe({
      next: (res: any) => {
        if (res?.data) {
          this.clientList = res.data;
        } else {
          this.clientList = [];
        }
      },
      error: () => {
        this.clientList = [];
      }
    });
  }

  loadLocations(): void {
    this.dropdownService.getLocations().subscribe({
      next: (data: any[]) => {
        this.locationList = data || [];
      },
      error: () => {
        this.locationList = [];
      }
    });
  }

  filterModelsByClient(clientId: any = 0): void {
    const costCentreId = clientId ? (typeof clientId === 'object' ? (clientId?.value || clientId?.id) : clientId) : 0;
    if (costCentreId === 0) return;

    this.clientService.getModelListByClient(costCentreId).subscribe({
      next: (res: any) => {
        if (res?.isSuccess && Array.isArray(res.data)) {
          this.modelList = res.data;
        } else {
          this.modelList = [];
        }
      },
      error: () => {
        this.modelList = [];
      }
    });
  }

  loadTransactionRanges(clientId: any, modelId: any): void {
    const cId = typeof clientId === 'object' ? (clientId?.value || clientId?.id) : clientId;
    const mId = typeof modelId === 'object' ? (modelId?.value || modelId?.id) : modelId;
    
    this.vendorService.getVendorTransactionRanges(cId, mId).subscribe({
      next: (res: any) => {
        if (res?.success) {
          this.transactionRanges = res.data.map((item: any) => ({
            name: item.TransactionRange || item.transactionRange,
            value: item.TransactionRange || item.transactionRange
          }));
        }
      }
    });
  }

  searchTransactions(): void {
    const client = this.filterForm.get('client')?.value;
    const model = this.filterForm.get('model')?.value;

    if (!client || !model) {
      this.toastrService.warning('Client and Model are mandatory for filtering.');
      return;
    }

    this.pageIndex = 1;
    this.loadTransactions();
  }

  onGlobalSearch(): void {
    this.pageIndex = 1;
    this.loadTransactions();
  }

  loadTransactions(): void {
    const client = this.filterForm.get('client')?.value;
    const model = this.filterForm.get('model')?.value;
    
    if (!client || !model) {
      return; // Handled by search validation
    }

    const cId = typeof client === 'object' ? (client?.value || client?.id) : client;
    const mId = typeof model === 'object' ? (model?.value || model?.id) : model;
    const locId = this.filterForm.get('location')?.value || '';
    const transRange = this.filterForm.get('transactionRange')?.value?.TransactionRange || this.filterForm.get('transactionRange')?.value || '';
    const vendorCode = this.filterForm.get('vendorCode')?.value || '';

    this.ngxService.start();
    this.vendorService.getVendorTransactionList(cId, mId, locId, transRange, vendorCode, this.searchTerm, this.pageIndex, this.pageSize).subscribe({
      next: (res: any) => {
        this.ngxService.stop();
        if (res?.success) {
          this.transactions = res.data;
          this.totalItems = res.totalCount;
          this.formulaMap = res.formulas || {};
          
          if (this.transactions.length > 0) {
            const rawKeys = Object.keys(this.transactions[0]);
            const excludeKeys = ['TotalRows', 'TransactionID', 'UploadBatchID', 'fk_cost_centre_id', 'fk_model_id', 'fk_rec_id', 'ClientID', 'ModelID', 'LocationID', 'CreatedBy', 'CreatedDate', 'IsProcessed', 'Vendor_IFSCCode', 'Vendor_PanNo', 'Vendor_AaddharNo', 'Vendor_BankName', 'Vendor_AccountNo', 'fk_File_Id', 'FHRID', 'FromDate', 'ToDate', 'CycleName', 'BudgetaryCode', 'StateName', 'Payment_Status', 'Payment Status', 'HR_Remark', 'HR Remark', 'Central_Remark', 'Central Remark'];
            this.previewKeys = rawKeys.filter(k => !excludeKeys.includes(k) && !k.toLowerCase().includes('id'));
          } else {
            this.previewKeys = [];
          }
        } else {
          this.transactions = [];
          this.totalItems = 0;
          this.toastrService.error('Failed to load transactions.');
        }
      },
      error: () => {
        this.ngxService.stop();
        this.transactions = [];
        this.totalItems = 0;
        this.toastrService.error('Server error while loading transactions.');
      }
    });
  }

  downloadExcel(): void {
    const client = this.filterForm.get('client')?.value;
    const model = this.filterForm.get('model')?.value;
    if (!client || !model) {
      this.toastrService.warning('Client and Model are mandatory for export.');
      return;
    }
    const cId = typeof client === 'object' ? (client?.value || client?.id) : client;
    const mId = typeof model === 'object' ? (model?.value || model?.id) : model;
    const locId = this.filterForm.get('location')?.value || '';
    const transRange = this.filterForm.get('transactionRange')?.value?.TransactionRange || this.filterForm.get('transactionRange')?.value || '';
    const vendorCode = this.filterForm.get('vendorCode')?.value || '';

    this.ngxService.start();
    this.vendorService.exportTransactionList(cId, mId, locId, transRange, vendorCode, this.searchTerm).subscribe({
      next: (blob: Blob) => {
        this.ngxService.stop();
        const fileName = 'TransactionList_' + cId + '_' + mId + '_' + new Date().getTime() + '.xlsx';
        FileSaver.saveAs(blob, fileName);
        this.toastrService.success('Export downloaded successfully!');
      },
      error: (err: any) => {
        this.ngxService.stop();
        console.error('Export failed:', err);
        this.toastrService.error('Failed to download export. Please try again.');
      }
    });
  }

  onPageChange(event: number): void {
    this.pageIndex = event;
    this.loadTransactions();
  }

  resetForm(): void {
    this.filterForm.reset();
    this.modelList = [];
    this.transactionRanges = [];
    this.transactions = [];
    this.totalItems = 0;
    this.pageIndex = 1;
    this.searchTerm = '';
    this.toastrService.info('Filters cleared.');
  }
}














