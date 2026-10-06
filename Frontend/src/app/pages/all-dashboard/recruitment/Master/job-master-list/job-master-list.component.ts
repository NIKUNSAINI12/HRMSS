import { Component, inject } from '@angular/core';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { NgxPaginationModule } from 'ngx-pagination';
import { FormsModule, ReactiveFormsModule } from '@angular/forms';
import { ToastrService } from 'ngx-toastr';
import { NgxUiLoaderService } from 'ngx-ui-loader';
import { CommonModule } from '@angular/common';
import * as XLSX from 'xlsx';
import { EncryptionService } from '../../../../../shared/services/encryption.service';
import { JobMasterService } from '../../RecruitServices/job-master.service';

@Component({
  selector: 'app-job-master-list',
  standalone: true,
imports: [RouterLink, CommonModule, ReactiveFormsModule, FormsModule, NgxPaginationModule],
  templateUrl: './job-master-list.component.html',
  styleUrl: './job-master-list.component.scss'
})
export class JobMasterListComponent {
  jobMasterList: any[] = [];
  searchText: string = '';
  pageIndex: number = 1;
  pageSize: number = 10;
  totalItems: number = 0;



  constructor(
    private jobMasterService: JobMasterService,
    private toastrService: ToastrService,
    private loaderService: NgxUiLoaderService,
    private router: Router,
    private route: ActivatedRoute,
    public encryptionService: EncryptionService
  ) {}

  ngOnInit(): void {
    this.loaderService.start();
    
    this.getAllJobs();
    this.loaderService.stop();

  }

  totalJobsCount: number = 0;
  openJobsCount: number = 0;
  closedJobsCount: number = 0;

  getAllJobs(): void {
    this.jobMasterService.getAllJobMasters(this.pageIndex - 1, this.pageSize).subscribe({
      next: (response) => {
        console.log('Data retrieved successfully:', response);
        if (response.isSuccess) {
          this.jobMasterList = response.data;
          this.totalItems = response.totalCount || response.data.length;
          this.calculateStats();
        } else {
          console.error('Failed to retrieve data:', response.message);
          this.toastrService.error(response.message || 'Failed to fetch jobs');
        }
      },
      error: (error) => {
        console.error('Error retrieving data:', error);
        this.toastrService.error('Error fetching jobs');
      }
    });
  }

  calculateStats() {
    this.totalJobsCount = this.jobMasterList.length;
    let closed = 0;
    const now = new Date();
    
    this.jobMasterList.forEach(job => {
      let isClosed = false;
      if (job.job_closed === 1 || job.job_closed === true || job.job_closed === 'Y' || job.job_closed === '1') {
        isClosed = true;
      }
      
      if (!isClosed && job.job_closing_date) {
        const closeDate = new Date(job.job_closing_date);
        if (closeDate < now) {
           isClosed = true;
        }
      }

      if (isClosed) closed++;
    });

    this.closedJobsCount = closed;
    this.openJobsCount = this.totalJobsCount - closed;
  }

  download(filename: string): void {
    this.jobMasterService.getImage(filename).subscribe({
      next: (blob) => {
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = filename;
        a.click();
        window.URL.revokeObjectURL(url);
      },
      error: (err) => {
        console.error('Failed to load attachment:', err);
        this.toastrService.error('Failed to download attachment');
      }
    });
  }

  onPageChange(event: number): void {
    this.pageIndex = event;
    this.getAllJobs();
  }

  delete(pk_JobId: string): void {
    if (confirm('Are you sure you want to delete this job?')) {
      this.jobMasterService.deleteJobMaster(pk_JobId).subscribe({
        next: (response) => {
          if (response.isSuccess) {
            this.toastrService.success(response.message || 'Job deleted successfully');
            this.getAllJobs();
          } else {
            this.toastrService.error(response.message || 'Failed to delete job');
          }
        },
        error: (error) => {
          console.error('Error deleting job:', error);
          this.toastrService.error('Failed to delete job');
        }
      });
    }
  }

  edit(pk_JobId: string): void {
    const encryptedId = this.encryptionService.encryptText(pk_JobId);
    this.router.navigate(['/dash/recruitment/recruitmentdashboard/jobMaster', encryptedId]);
  }



filteredData() {
  if (!this.searchText) {
    return this.jobMasterList;
  }

  const searchTextLower = this.searchText.toLowerCase();

  return this.jobMasterList.filter(data =>
    data.job_title?.toLowerCase().includes(searchTextLower) ||
    data.designation?.toLowerCase().includes(searchTextLower) ||
    data.no_of_post?.toString().toLowerCase().includes(searchTextLower) ||
    data.job_opening_date?.toLowerCase().includes(searchTextLower) ||
    data.job_closing_date?.toLowerCase().includes(searchTextLower)
  );
}





 




 
}