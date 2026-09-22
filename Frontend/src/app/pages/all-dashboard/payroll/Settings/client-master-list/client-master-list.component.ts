import { CommonModule } from '@angular/common';
import { Component, inject } from '@angular/core';
import { FormsModule, ReactiveFormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { NgxPaginationModule } from 'ngx-pagination';
import { ToastrService } from 'ngx-toastr';
import { NgxUiLoaderService } from 'ngx-ui-loader';
import { EncryptionService } from '../../../../../shared/services/encryption.service';
import { ClientMasterService } from '../../services/client-master.service';
import * as XLSX from 'xlsx';

@Component({
  selector: 'app-client-master-list',
  standalone: true,
  imports: [RouterLink, ReactiveFormsModule, FormsModule, CommonModule, NgxPaginationModule],
  templateUrl: './client-master-list.component.html',
  styleUrl: './client-master-list.component.scss'
})
export class ClientMasterListComponent {
  searchText: string = '';
  searchTerm: string = '';
  list: any[] = [];
  filteredMaster: any[] = [];
  page: number = 1;         // ✅ same name as Bank Master
  pageSize: number = 10;
  totalItems: number = 0;
  ngxUILoaderService = inject(NgxUiLoaderService);

  constructor(
    private service: ClientMasterService,
    private toastrService: ToastrService,
    private router: Router,
    public encryptionService: EncryptionService   // ✅ same name as Bank Master
  ) { }

  ngOnInit(): void {
    this.getList();
  }

  onPageChange(event: number): void {
    this.page = event;       // ✅ same as Bank Master
    this.getList();
  }


  getList() {
    this.ngxUILoaderService.start();
    this.service.get_All_clientmaster(this.page - 1, this.pageSize, this.searchText).subscribe({  // ✅ page-1 same as Bank Master
      next: (res) => {
        if (res.isSuccess && res.data) {
          this.list = res.data.list;
          this.totalItems = res.data.totalCount;
          this.applyFilter();
        } else {
          this.toastrService.error(res.message);
        }
        this.ngxUILoaderService.stop();
      },
      error: () => {
        this.toastrService.error("An error occurred while loading client list.");
        this.ngxUILoaderService.stop();
      }
    });
  }




  applyFilter() {
    if (!this.searchText) {
      this.filteredMaster = this.list;
      return;
    }

    const searchLower = this.searchText.toLowerCase();
    const local = this.list.filter(req =>
      req.clientName?.toLowerCase().includes(searchLower) ||
      req.clientCode?.toLowerCase().includes(searchLower) ||
      req.grouping?.toLowerCase().includes(searchLower) ||
      req.contactPerson?.toLowerCase().includes(searchLower) ||
      req.phone?.toLowerCase().includes(searchLower) ||
      req.emailID?.toLowerCase().includes(searchLower) ||
      req.zoneName?.toLowerCase().includes(searchLower) ||
      req.cityName?.toLowerCase().includes(searchLower) ||
      req.stateName?.toLowerCase().includes(searchLower) ||
      req.empCodePrefix?.toLowerCase().includes(searchLower) ||
      req.cinNo?.toLowerCase().includes(searchLower) ||
      req.tan?.toLowerCase().includes(searchLower) ||
      req.gst?.toLowerCase().includes(searchLower) ||
      req.pan?.toLowerCase().includes(searchLower) ||
      req.address?.toLowerCase().includes(searchLower) ||
      req.pincode?.toLowerCase().includes(searchLower) ||
      req.startDate?.toLowerCase().includes(searchLower) ||
      req.endDate?.toLowerCase().includes(searchLower) ||
      req.leavePolicy?.toLowerCase().includes(searchLower) ||
      req.commissionPercent?.toString().toLowerCase().includes(searchLower)
    );
    this.filteredMaster = local;
  }

  onSearchTextChanged(): void {
    this.applyFilter();
    if (this.filteredMaster.length === 0 && this.searchText.trim()) {
      this.searchTerm = this.searchText.trim();
      this.page = 1;
      this.getList();
    } else if (!this.searchText.trim()) {
      this.searchTerm = '';
      this.getList();
    }
  }
  edit(encryptedId: any) {
    this.router.navigate(["/dash/user/userdashboard/clientMaster", encryptedId]);
  }

  deleteRecord(pk_cost_centre_id: any) {
    if (confirm("Are you sure you want to delete this Client Master record?")) {
      this.ngxUILoaderService.start();
      this.service.delete_clientmaster(pk_cost_centre_id).subscribe({
        next: (res) => {
          if (res.isSuccess) {
            this.toastrService.success(res.message || "Deleted successfully!");
            this.getList();
          } else {
            this.toastrService.error(res.message || "Failed to delete.");
            this.ngxUILoaderService.stop();
          }
        },
        error: () => {
          this.toastrService.error("An error occurred while deleting.");
          this.ngxUILoaderService.stop();
        }
      });
    }
  }

  exportToExcel(): void {
    this.ngxUILoaderService.start();
    this.service.DownloadExcel().subscribe({
      next: (res) => {
        if (res.isSuccess && res.data && res.data.list && res.data.list.length > 0) {
          const excludedColumns = ['pk_cost_centre_id'];

          const columnMappings: Record<string, string> = {
            clientCode: 'Client Code',
            clientName: 'Client Name',
            grouping: 'Grouping',
            contactPerson: 'Contact Person',
            phone: 'Phone',
            emailID: 'Email ID',
            zoneName: 'Zone',
            cityName: 'City',
            stateName: 'State',
            empCodePrefix: 'Emp Code Prefix',
            cinNo: 'CIN No',
            tan: 'TAN',
            address: 'Address',
            pincode: 'Pincode',
            startDate: 'Start Date',
            endDate: 'End Date',
            leavePolicy: 'Leave Policy',
            commissionPercent: 'Commission Percent'
          };

          const filteredData = res.data.list.map((item: Record<string, any>) => {
            return Object.keys(item)
              .filter(key => !excludedColumns.includes(key))
              .reduce((obj: Record<string, any>, key: string) => {
                obj[columnMappings[key] || key] = item[key];
                return obj;
              }, {});
          });

          const worksheet: XLSX.WorkSheet = XLSX.utils.json_to_sheet(filteredData);
          const workbook: XLSX.WorkBook = XLSX.utils.book_new();
          XLSX.utils.book_append_sheet(workbook, worksheet, 'Clients');

          const excelBuffer: any = XLSX.write(workbook, { bookType: 'xlsx', type: 'array' });
          const data: Blob = new Blob([excelBuffer], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });

          const fileName = 'ClientList.xlsx';
          const link = document.createElement('a');
          link.href = URL.createObjectURL(data);
          link.setAttribute('download', fileName);
          document.body.appendChild(link);
          link.click();
          document.body.removeChild(link);
          this.ngxUILoaderService.stop();
        } else {
          this.toastrService.warning('No data available to export');
          this.ngxUILoaderService.stop();
        }
      },
      error: () => {
        this.toastrService.error('Failed to download excel');
        this.ngxUILoaderService.stop();
      }
    });
  }
}