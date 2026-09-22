import { CommonModule } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { NgxPaginationModule } from 'ngx-pagination';
import { ToastrService } from 'ngx-toastr';
import { EncryptionService } from '../../../../shared/services/encryption.service';
import { VendorEmpDocService } from '../Service/vendor-emp-doc.service';

@Component({
  selector: 'app-vendor-emp-doc-list',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink, NgxPaginationModule],
  templateUrl: './vendor-emp-doc-list.component.html',
  styleUrl: './vendor-emp-doc-list.component.scss'
})
export class VendorEmpDocListComponent implements OnInit {
  vendorDocService = inject(VendorEmpDocService);
  encryptionService = inject(EncryptionService);
  toastr = inject(ToastrService);
  router = inject(Router);

  employeeDocList: any[] = [];
  totalCount = 0;
  searchTerm = '';
  pageIndex = 1;
  pageSize = 10;
  isLoading = false;
  vendorId = '';

  ngOnInit(): void {
    this.loadList();
  }

  loadList(): void {
    this.isLoading = true;
    const backendPageIndex = this.pageIndex - 1;
    this.vendorDocService.getVendorEmpDocList(this.searchTerm, backendPageIndex, this.pageSize, this.vendorId).subscribe({
      next: (res: any) => {
        this.isLoading = false;
        if (res?.isSuccess && res.data) {
          this.employeeDocList = res.data.list || [];
          this.totalCount = res.data.totalCount || 0;
          if (res.data.vendorId) {
            this.vendorId = res.data.vendorId;
          }
        } else {
          this.employeeDocList = [];
          this.totalCount = 0;
        }
      },
      error: () => {
        this.isLoading = false;
        this.employeeDocList = [];
        this.toastr.error('Failed to load employee document list.', 'Error');
      }
    });
  }

  onSearch(): void {
    this.pageIndex = 1;
    this.loadList();
  }

  onPageChange(page: number): void {
    this.pageIndex = page;
    this.loadList();
  }

  openUploadForm(empId?: string): void {
    if (empId) {
      const encryptedId = this.encryptionService.encryptText(empId.toString());
      this.router.navigate(['/dash/vendor_management/vendor_managementdashboard/vendor_emp_doc_form', encryptedId]);
    } else {
      this.router.navigate(['/dash/vendor_management/vendor_managementdashboard/vendor_emp_doc_form']);
    }
  }

  getProgressPercent(row: any): number {
    const total = row.totalDocs || row.TotalDocs || 0;
    const approved = row.approvedDocs || row.ApprovedDocs || 0;
    if (total > 0) {
      return Math.round((approved / total) * 100);
    }
    const prog = (row.docProgress || row.DocProgress || '').toString();
    if (prog.includes('/')) {
      const parts = prog.split('/');
      const a = parseInt(parts[0], 10) || 0;
      const t = parseInt(parts[1], 10) || 0;
      return t > 0 ? Math.round((a / t) * 100) : 0;
    }
    return 0;
  }

  getRowStatus(row: any): string {
    const status = (row.status || row.Status || '').trim();
    const total = row.totalDocs || row.TotalDocs || 0;
    const approved = row.approvedDocs || row.ApprovedDocs || 0;
    const rejected = row.rejectedDocs || row.RejectedDocs || 0;

    if (status.toLowerCase() === 'approved' || (total > 0 && approved === total)) {
      return 'Completed';
    }
    if (status.toLowerCase() === 'rejected' || rejected > 0) {
      return 'Rejected';
    }
    return 'Pending';
  }
}
