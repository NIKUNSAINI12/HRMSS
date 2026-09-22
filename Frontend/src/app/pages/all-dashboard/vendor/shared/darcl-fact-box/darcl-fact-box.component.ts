import { Component, Input, Output, EventEmitter } from '@angular/core';
import { CommonModule, NgIf, NgFor, NgClass, DatePipe } from '@angular/common';
import { NgxPaginationModule } from 'ngx-pagination';
import * as XLSX from 'xlsx';
import { UploadFileHistoryService } from '../../Service/upload-file-history.service';

@Component({
  selector: 'app-darcl-fact-box, app-fact-box',
  standalone: true,
  imports: [CommonModule, NgIf, NgFor, NgClass, DatePipe, NgxPaginationModule],
  templateUrl: './darcl-fact-box.component.html',
  styleUrls: ['./darcl-fact-box.component.scss']
})
export class DarclFactBoxComponent {
  @Input() title: string = 'DARCL Fact Box';
  @Input() files: any[] = [];
  @Input() isLoading: boolean = false;
  @Input() isOpen: boolean = false;

  // Pagination inputs (can be overridden by parent for server-side pagination)
  @Input() totalItems?: number;
  @Input() currentPage: number = 1;
  @Input() itemsPerPage: number = 5;

  @Output() onToggle = new EventEmitter<void>();
  @Output() onView = new EventEmitter<any>();
  @Output() onDownload = new EventEmitter<any>();
  @Output() onPageChange = new EventEmitter<number>();

  // --- Pop-up Excel Preview State ---
  isPreviewOpen: boolean = false;
  isPreviewLoading: boolean = false;
  previewErrorMessage: string = '';
  previewFileName: string = '';
  previewHeaders: string[] = [];
  previewRows: any[] = [];
  previewCurrentItem: any = null;
  totalPreviewRowsCount: number = 0;
  previewWorkbook: any = null;
  previewSheetNames: string[] = [];
  activeSheetIndex: number = 0;

  constructor(private uploadHistoryService: UploadFileHistoryService) { }

  toggleFactBox(): void {
    this.onToggle.emit();
  }

  viewUploadedFile(item: any): void {
    this.openPreview(item);
  }

  openPreview(item: any): void {
    const fileId = item.id || item.pk_id || item.fileId || item.File_Id;
    this.previewFileName = this.getFileName(item);
    this.previewCurrentItem = item;
    this.previewHeaders = [];
    this.previewRows = [];
    this.previewErrorMessage = '';
    this.totalPreviewRowsCount = 0;
    this.previewSheetNames = [];
    this.activeSheetIndex = 0;
    this.previewWorkbook = null;
    this.isPreviewOpen = true;
    this.isPreviewLoading = true;

    if (!fileId) {
      this.isPreviewLoading = false;
      this.previewErrorMessage = 'File identifier not found.';
      return;
    }

    this.uploadHistoryService.viewFile(fileId).subscribe({
      next: async (blob: Blob) => {
        try {
          const buffer = await blob.arrayBuffer();
          const workbook = XLSX.read(buffer, { type: 'array' });
          if (!workbook.SheetNames || workbook.SheetNames.length === 0) {
            this.previewErrorMessage = 'No sheets found in Excel file.';
            this.isPreviewLoading = false;
            return;
          }

          this.previewWorkbook = workbook;
          this.previewSheetNames = workbook.SheetNames;
          this.selectSheet(0);
        } catch (e) {
          console.error('Error parsing Excel file for preview:', e);
          this.previewErrorMessage = 'Unable to parse Excel file contents.';
        } finally {
          this.isPreviewLoading = false;
        }
      },
      error: (err) => {
        console.error('Error loading file for preview:', err);
        this.previewErrorMessage = 'Unable to fetch file for preview from server.';
        this.isPreviewLoading = false;
      }
    });
  }

  selectSheet(sheetIndex: number): void {
    if (!this.previewWorkbook || !this.previewSheetNames || sheetIndex < 0 || sheetIndex >= this.previewSheetNames.length) {
      return;
    }

    this.activeSheetIndex = sheetIndex;
    const sheetName = this.previewSheetNames[sheetIndex];
    const sheet = this.previewWorkbook.Sheets[sheetName];
    if (!sheet) {
      this.previewHeaders = [];
      this.previewRows = [];
      return;
    }

    const data: any[][] = XLSX.utils.sheet_to_json(sheet, { header: 1, defval: '' });
    if (data && data.length > 0) {
      const rawHeaders = data[0] || [];
      this.previewHeaders = rawHeaders.map((h: any, idx: number) => {
        const str = (h !== undefined && h !== null) ? String(h).trim() : '';
        return str || `Col ${idx + 1}`;
      });

      // Filter out completely blank rows
      const rows = data.slice(1).filter((row: any) =>
        row && row.some((cell: any) => cell !== undefined && cell !== null && String(cell).trim() !== '')
      );
      this.totalPreviewRowsCount = rows.length;
      // Take up to 1000 rows for smooth rendering in modal
      this.previewRows = rows.slice(0, 1000);
    } else {
      this.previewHeaders = [];
      this.previewRows = [];
      this.totalPreviewRowsCount = 0;
    }
  }

  closePreview(): void {
    this.isPreviewOpen = false;
    this.previewHeaders = [];
    this.previewRows = [];
    this.previewCurrentItem = null;
    this.previewWorkbook = null;
    this.previewSheetNames = [];
    this.activeSheetIndex = 0;
    this.previewErrorMessage = '';
    this.totalPreviewRowsCount = 0;
  }

  downloadFromPreview(): void {
    if (this.previewCurrentItem) {
      this.downloadUploadedFile(this.previewCurrentItem);
    }
  }

  downloadUploadedFile(item: any): void {
    this.onDownload.emit(item);
  }

  handlePageChange(page: number): void {
    this.currentPage = page;
    this.onPageChange.emit(page);
  }

  getFileName(item: any): string {
    return item.file_name || item.fileName || item.savedFileName || item.originalFileName || item.name || 'Uploaded File';
  }

  hasMetrics(item: any): boolean {
    const total = item.totalRecords ?? item.TotalRecords ?? item.Total ?? item.total ?? item.totalCount ?? item.TotalCount;
    return total !== undefined && total !== null && total > 0;
  }

  getUploaderDisplayName(item: any): string {
    const rawName = item.uploadedByName || item.uploadedBy || item.UploadedBy || item.uploadedby || item.userName || item.UserName || item.name || item.entry_by_name || item.EmpName || item.empName;
    if (rawName && typeof rawName === 'string' && isNaN(Number(rawName)) && !rawName.startsWith('GU-') && !rawName.startsWith('USR-')) {
      return rawName.trim();
    }

    const currentUserName = sessionStorage.getItem('username') || localStorage.getItem('username') || sessionStorage.getItem('name') || localStorage.getItem('name') || '';
    const currentUserId = sessionStorage.getItem('UserId') || sessionStorage.getItem('userId') || sessionStorage.getItem('USERID') || localStorage.getItem('UserId') || '';

    const entryBy = String(item.entry_by || item.fk_userId || item.fk_InsUserID || item.uploadedBy || '').trim();

    if (currentUserName && (entryBy === currentUserId || !entryBy || entryBy.startsWith('GU-') || entryBy.startsWith('USR-') || !isNaN(Number(entryBy)))) {
      return currentUserName;
    }

    if (rawName) {
      if (typeof rawName === 'string' && rawName.includes('-')) {
        const parts = rawName.split('-');
        const cleanPart = parts.slice(1).join('-').trim();
        if (cleanPart && isNaN(Number(cleanPart))) return cleanPart;
      }
      if (isNaN(Number(rawName))) {
        return rawName.toString();
      }
    }

    return currentUserName || 'HR User';
  }
}

// Alias for backwards compatibility
export { DarclFactBoxComponent as FactBoxComponent };
