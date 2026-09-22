import { CommonModule } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DomSanitizer, SafeResourceUrl } from '@angular/platform-browser';
import { NgSelectModule } from '@ng-select/ng-select';
import { NgxPaginationModule } from 'ngx-pagination';
import { ToastrService } from 'ngx-toastr';
import { VendorEmpDocService } from '../Service/vendor-emp-doc.service';

declare var bootstrap: any;

@Component({
  selector: 'app-vendor-emp-doc-approval',
  standalone: true,
  imports: [CommonModule, FormsModule, NgSelectModule, NgxPaginationModule],
  templateUrl: './vendor-emp-doc-approval.component.html',
  styleUrl: './vendor-emp-doc-approval.component.scss'
})
export class VendorEmpDocApprovalComponent implements OnInit {
  vendorDocService = inject(VendorEmpDocService);
  toastr = inject(ToastrService);
  sanitizer = inject(DomSanitizer);

  hrList: any[] = [];
  totalCount = 0;
  isLoading = false;

  // Filters
  selectedVendorId: string = '';
  selectedLocationId: string = '';
  selectedStatus: string = '';
  searchTerm: string = '';
  pageIndex = 1;
  pageSize = 10;
  pageSizeOptions = [10, 20, 50, 100];

  vendorList: any[] = [];
  locationList: any[] = [];
  statusOptions = [
    { name: 'All Statuses', value: '' },
    { name: 'Pending', value: 'Pending' },
    { name: 'Approved', value: 'Approved' },
    { name: 'Rejected', value: 'Rejected' }
  ];

  // Role Detection
  isVendorUser: boolean = false;

  // Review Modal State
  selectedRow: any = null;
  employeeDocs: any[] = [];
  isLoadingDocs = false;
  selectedDocForView: any = null;

  // Reject State
  docToReject: any = null;
  rejectDocId: number | null = null;
  rejectionRemarks: string = '';
  isProcessingAction = false;

  reviewModal: any;
  previewModal: any;
  rejectModal: any;

  ngOnInit(): void {
    this.checkUserRole();
    this.loadDropdowns();
    this.loadList();
  }

  checkUserRole(): void {
    const userType = sessionStorage.getItem('usertype') || '';
    if (userType.toLowerCase() === 'vendor' || sessionStorage.getItem('isVendor') === 'true') {
      this.isVendorUser = true;
    }

    this.vendorDocService.getUserRoleInfo().subscribe({
      next: (res: any) => {
        if (res?.isSuccess && res.data) {
          this.isVendorUser = res.data.isVendor === true;
        }
      }
    });
  }

  loadDropdowns(): void {
    this.vendorDocService.getVendors().subscribe({
      next: (res: any) => {
        if (res?.isSuccess && res.data) {
          this.vendorList = res.data.map((v: any) => ({ name: v.name, value: v.value }));
        }
      }
    });

    this.vendorDocService.getLocations().subscribe({
      next: (res: any) => {
        if (res?.isSuccess && res.data) {
          this.locationList = res.data.map((l: any) => ({ name: l.name, value: l.value }));
        }
      }
    });
  }

  loadList(): void {
    this.isLoading = true;
    const backendPageIndex = this.pageIndex - 1;
    this.vendorDocService.getHREmpDocList(
      this.selectedVendorId,
      this.selectedLocationId,
      this.selectedStatus,
      this.searchTerm,
      backendPageIndex,
      this.pageSize
    ).subscribe({
      next: (res: any) => {
        this.isLoading = false;
        if (res?.isSuccess && res.data) {
          this.hrList = res.data.list || [];
          this.totalCount = res.data.totalCount || 0;
        } else {
          this.hrList = [];
          this.totalCount = 0;
        }
      },
      error: () => {
        this.isLoading = false;
        this.hrList = [];
        this.toastr.error('Failed to load HR document list.', 'Error');
      }
    });
  }

  onFilterChange(): void {
    this.pageIndex = 1;
    this.loadList();
  }

  onPageChange(page: number): void {
    this.pageIndex = page;
    this.loadList();
  }

  resetFilters(): void {
    this.selectedVendorId = '';
    this.selectedLocationId = '';
    this.selectedStatus = '';
    this.searchTerm = '';
    this.pageIndex = 1;
    this.loadList();
  }

  // ── OPEN REVIEW MODAL ──────────────────────────────────────────────────────
  openReviewModal(row: any): void {
    this.selectedRow = { ...row };
    this.isLoadingDocs = true;
    this.employeeDocs = [];

    const modalEl = document.getElementById('reviewDocModal');
    if (modalEl) {
      this.reviewModal = new bootstrap.Modal(modalEl);
      this.reviewModal.show();
    }

    this.vendorDocService.getDocsByEmpAndVendor(row.fk_empId, row.fk_vendorId).subscribe({
      next: (res: any) => {
        this.isLoadingDocs = false;
        if (res?.isSuccess && res.data) {
          this.employeeDocs = res.data;
          if (this.employeeDocs.length > 0) {
            const first = this.employeeDocs[0];
            if (!this.selectedRow.locationName && (first.locationName || first.LocationName)) {
              this.selectedRow.locationName = first.locationName || first.LocationName;
            }
            if (!this.selectedRow.empname && (first.empName || first.empname || first.EmpName)) {
              this.selectedRow.empname = first.empName || first.empname || first.EmpName;
            }
            if (!this.selectedRow.empcode && (first.empCode || first.empcode || first.EmpCode)) {
              this.selectedRow.empcode = first.empCode || first.empcode || first.EmpCode;
            }
            if (!this.selectedRow.vendor_Name && (first.vendor_Name || first.Vendor_Name)) {
              this.selectedRow.vendor_Name = first.vendor_Name || first.Vendor_Name;
            }
            if (!this.selectedRow.vendor_Code && (first.vendor_Code || first.Vendor_Code)) {
              this.selectedRow.vendor_Code = first.vendor_Code || first.Vendor_Code;
            }
          }
        }
      },
      error: () => {
        this.isLoadingDocs = false;
        this.toastr.error('Failed to load employee documents.', 'Error');
      }
    });
  }

  // ── VIEW DOCUMENT PREVIEW ──────────────────────────────────────────────────
  viewDocument(doc: any): void {
    const docId = doc.pk_docId || doc.Pk_docId;
    this.selectedDocForView = { ...doc, safeUrl: null };

    const modalEl = document.getElementById('previewModalInApproval');
    if (modalEl) {
      this.previewModal = new bootstrap.Modal(modalEl);
      this.previewModal.show();
    }

    this.vendorDocService.downloadFileBlob(docId).subscribe({
      next: (blob: Blob) => {
        const mimeType = doc.mimeType || doc.MimeType || blob.type || 'application/pdf';
        const fileBlob = new Blob([blob], { type: mimeType });
        let blobUrl = URL.createObjectURL(fileBlob);
        if (mimeType.toLowerCase().includes('pdf')) {
          blobUrl += '#toolbar=0&navpanes=0&scrollbar=0';
        }
        this.selectedDocForView.safeUrl = this.sanitizer.bypassSecurityTrustResourceUrl(blobUrl);
      },
      error: () => {
        this.toastr.error('Failed to load document preview.', 'Error');
      }
    });
  }

  // ── APPROVE DOCUMENT ───────────────────────────────────────────────────────
  approveDocument(doc: any): void {
    if (this.isVendorUser) {
      this.toastr.warning('Only Company HR or Admin can approve documents.', 'Unauthorized');
      return;
    }
    if (!this.isDocPending(doc)) {
      this.toastr.warning('Document status has already been finalized and cannot be changed.', 'Locked');
      return;
    }
    this.isProcessingAction = true;
    this.vendorDocService.updateDocStatus({
      pk_docId: doc.pk_docId,
      status: 'Approved'
    }).subscribe({
      next: (res: any) => {
        this.isProcessingAction = false;
        if (res?.isSuccess) {
          this.toastr.success(`"${doc.docTypeName}" has been Approved.`, 'Success');
          doc.verificationStatus = 'Approved';
          doc.VerificationStatus = 'Approved';
          this.loadList();
        } else {
          this.toastr.error(res?.message || 'Failed to approve.', 'Error');
        }
      },
      error: () => {
        this.isProcessingAction = false;
        this.toastr.error('Error approving document.', 'Error');
      }
    });
  }

  // ── REJECT DOCUMENT MODAL ─────────────────────────────────────────────────
  openRejectModal(doc: any): void {
    if (this.isVendorUser) {
      this.toastr.warning('Only Company HR or Admin can reject documents.', 'Unauthorized');
      return;
    }
    if (!this.isDocPending(doc)) {
      this.toastr.warning('Document status has already been finalized and cannot be changed.', 'Locked');
      return;
    }
    this.docToReject = doc;
    this.rejectDocId = doc.pk_docId;
    this.rejectionRemarks = '';

    const modalEl = document.getElementById('rejectReasonModal');
    if (modalEl) {
      this.rejectModal = new bootstrap.Modal(modalEl);
      this.rejectModal.show();
    }
  }

  confirmReject(): void {
    if (this.isVendorUser) {
      this.toastr.warning('Only Company HR or Admin can reject documents.', 'Unauthorized');
      return;
    }
    if (!this.rejectDocId) return;
    if (!this.rejectionRemarks.trim()) {
      this.toastr.warning('Please enter a rejection reason.', 'Warning');
      return;
    }

    this.isProcessingAction = true;
    this.vendorDocService.updateDocStatus({
      pk_docId: this.rejectDocId,
      status: 'Rejected',
      rejectionRemarks: this.rejectionRemarks
    }).subscribe({
      next: (res: any) => {
        this.isProcessingAction = false;
        if (res?.isSuccess) {
          this.toastr.success('Document marked as Rejected.', 'Success');
          if (this.rejectModal) {
            this.rejectModal.hide();
          }
          const doc = this.employeeDocs.find(d => d.pk_docId === this.rejectDocId);
          if (doc) {
            doc.verificationStatus = 'Rejected';
            doc.VerificationStatus = 'Rejected';
            doc.rejectionRemarks = this.rejectionRemarks;
            doc.RejectionRemarks = this.rejectionRemarks;
          }
          this.loadList();
        } else {
          this.toastr.error(res?.message || 'Failed to reject.', 'Error');
        }
      },
      error: () => {
        this.isProcessingAction = false;
        this.toastr.error('Error rejecting document.', 'Error');
      }
    });
  }

  // ── PROGRESS & STATUS HELPERS ──────────────────────────────────────────────
  isDocPending(doc: any): boolean {
    const s = String(doc?.verificationStatus || doc?.VerificationStatus || 'Pending').toLowerCase().trim();
    return s === 'pending' || s === '';
  }

  getApprovedCount(): number {
    if (!this.employeeDocs || this.employeeDocs.length === 0) return 0;
    return this.employeeDocs.filter(d => (d.verificationStatus || d.VerificationStatus) === 'Approved').length;
  }

  getApprovalPercent(): number {
    if (!this.employeeDocs || this.employeeDocs.length === 0) return 0;
    const approved = this.getApprovedCount();
    return Math.round((approved / this.employeeDocs.length) * 100);
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

  // ── MODAL GETTERS ──────────────────────────────────────────────────────────
  getSelectedEmpName(): string {
    const name = this.selectedRow?.empname || this.selectedRow?.empName || this.selectedRow?.EmpName || '';
    if (name && String(name).trim() && String(name).trim() !== '-') {
      return String(name).trim();
    }
    if (this.employeeDocs && this.employeeDocs.length > 0) {
      const docName = this.employeeDocs[0]?.empName || this.employeeDocs[0]?.empname || this.employeeDocs[0]?.EmpName;
      if (docName && String(docName).trim()) {
        return String(docName).trim();
      }
    }
    return '-';
  }

  getSelectedEmpCode(): string {
    const code = this.selectedRow?.empcode || this.selectedRow?.empCode || this.selectedRow?.EmpCode || '';
    if (code && String(code).trim() && String(code).trim() !== '-') {
      return String(code).trim();
    }
    if (this.employeeDocs && this.employeeDocs.length > 0) {
      const docCode = this.employeeDocs[0]?.empCode || this.employeeDocs[0]?.empcode || this.employeeDocs[0]?.EmpCode;
      if (docCode && String(docCode).trim()) {
        return String(docCode).trim();
      }
    }
    return '';
  }

  getSelectedVendorName(): string {
    const name = this.selectedRow?.vendor_Name || this.selectedRow?.Vendor_Name || this.selectedRow?.vendorName || '';
    if (name && String(name).trim() && String(name).trim() !== '-') {
      return String(name).trim();
    }
    if (this.employeeDocs && this.employeeDocs.length > 0) {
      const docVendor = this.employeeDocs[0]?.vendor_Name || this.employeeDocs[0]?.Vendor_Name || this.employeeDocs[0]?.vendorName;
      if (docVendor && String(docVendor).trim()) {
        return String(docVendor).trim();
      }
    }
    return '-';
  }

  getSelectedVendorCode(): string {
    const code = this.selectedRow?.vendor_Code || this.selectedRow?.Vendor_Code || this.selectedRow?.vendorCode || '';
    if (code && String(code).trim()) {
      return String(code).trim();
    }
    if (this.employeeDocs && this.employeeDocs.length > 0) {
      const docCode = this.employeeDocs[0]?.vendor_Code || this.employeeDocs[0]?.Vendor_Code || this.employeeDocs[0]?.vendorCode;
      if (docCode && String(docCode).trim()) {
        return String(docCode).trim();
      }
    }
    return '';
  }

  getSelectedLocation(): string {
    const loc = this.selectedRow?.locationName || this.selectedRow?.LocationName || this.selectedRow?.location_Name || this.selectedRow?.Location || this.selectedRow?.locName || '';
    if (loc && String(loc).trim() && String(loc).trim() !== '-') {
      return String(loc).trim();
    }
    if (this.employeeDocs && this.employeeDocs.length > 0) {
      const docLoc = this.employeeDocs[0]?.locationName || this.employeeDocs[0]?.LocationName || this.employeeDocs[0]?.locName;
      if (docLoc && String(docLoc).trim()) {
        return String(docLoc).trim();
      }
    }
    return '-';
  }
}
