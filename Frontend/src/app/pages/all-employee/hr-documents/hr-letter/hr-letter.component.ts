import { CommonModule } from '@angular/common';
import { Component, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { NgSelectComponent } from '@ng-select/ng-select';
import { NgxPaginationModule } from 'ngx-pagination';
import { CommonSearchComponent } from '../../../all-dashboard/payroll/Employee/common-search/common-search.component';
import { NgxUiLoaderService } from 'ngx-ui-loader';
import { HrLetterService } from '../hrdocumentService/hr-letter.service';
import { ToastrService } from 'ngx-toastr';
import { EncryptionService } from '../../../../shared/services/encryption.service';
import { DomSanitizer, SafeResourceUrl } from '@angular/platform-browser';
declare var bootstrap: any;

@Component({
  selector: 'app-hr-letter',
  standalone: true,
  imports: [RouterLink, CommonModule,FormsModule,NgxPaginationModule,NgSelectComponent,CommonSearchComponent],
  templateUrl: './hr-letter.component.html',
  styleUrl: './hr-letter.component.scss'
})
export class HrLetterComponent {
   ngxUILoaderService = inject(NgxUiLoaderService);
      List: any[] = [];
      remark: string = '';


      searchText: string = '';
          pageIndex: number = 1;
          pageSize: number = 10;
          totalItems: number = 0;
selectedLetter: any = { fileUrl: null as SafeResourceUrl | null };
         
          constructor(
           public Service: HrLetterService,
            private router: Router,
            private toastrService: ToastrService,
            public encryptionService: EncryptionService,
            private sanitizer: DomSanitizer 
          ) {}
        
            ngOnInit() {
            this.getdata();
          }
            
        
          getdata(): void {
            this.ngxUILoaderService.start(); 
            this.Service.get_HrLetter().subscribe({
              next: (res) => {
                if (res.isSuccess) {
                  this.ngxUILoaderService.stop(); 
                  this.List = res.data;
                  this.totalItems = res.totalCount;
                } else {
                  this.List = [];
                  this.totalItems = 0;
                  this.toastrService.error(res.message, 'Error');
                  this.ngxUILoaderService.stop(); 
        
                }
              },
              error: (error) => {
                this.List = [];
                  this.totalItems = 0;
                this.toastrService.error('Failed to retrieve employees', 'Error');
              }
            });
          }
            filteredData(): any[] {
            if (!this.searchText) return this.List;
            const search = this.searchText.toLowerCase();
            return this.List.filter(item =>
              Object.values(item).some(val =>
                String(val).toLowerCase().includes(search)
              )
            );
          }
        
            onPageChange(event: number): void {
            this.pageIndex = event;
            this.getdata();
          }
        
        
      
      //   download(filename: string) {
      //   this.Service.getHrdoc(filename).subscribe({
      //     next: (blob) => {
      //       const url = window.URL.createObjectURL(blob);
      
      //       const cleanedDownloadName = filename.replace(/\s+/g, '_');
      //       const a = document.createElement('a');
      //       a.href = url;
      //       a.download = cleanedDownloadName;
      //       a.click();
      //       window.URL.revokeObjectURL(url);
      //     },
      //     error: (err) => {
      //       console.error('Failed to load image:', err);
      //     }
      //   });
      // }
      

    //    download(filename: string) {
    //   this.Service.getImage(filename).subscribe({
    //     next: (blob) => {
    //       const url = window.URL.createObjectURL(blob);
    //       const a = document.createElement('a');
    //       a.href = url;
    //       a.download = filename; // Set the filename for download
    //       a.click();
    //       window.URL.revokeObjectURL(url); // Clean up
    //     },
    //     error: (err) => {
    //       console.error('Failed to load image:', err);
    //     }
    //   });
    // }





   

  //  CHANGED: Download letter using pk_trnid (not filename)
  // downloadLetter(pk_trnid: number) {
  //   this.Service.downloadFormat(pk_trnid).subscribe({
  //     next: (response: Blob) => {

  //       if (!response) {
  //         this.toastrService.error("File not received from server");
  //         return;
  //       }

  //       // Detect PDF or DOCX
  //       const fileType = response.type;
  //       const extension = fileType.includes('pdf') ? 'pdf' : 'docx';

  //       const blob = new Blob([response], { type: fileType });
  //       const url = window.URL.createObjectURL(blob);

  //       const a = document.createElement('a');
  //       a.href = url;
  //       a.download = `Letter.${extension}`;
  //       a.click();

  //       window.URL.revokeObjectURL(url);

  //       this.toastrService.success("Letter downloaded successfully");
  //     },
  //     error: (err) => {
  //       console.error(err);
  //       this.toastrService.error("Failed to download letter");
  //     }
  //   });
  // }

downloadLetter(pk_trnid: number) {
  this.ngxUILoaderService.start(); // Start loader before processing the response

  this.Service.downloadFormat(pk_trnid).subscribe({
    next: (response: Blob) => {
      if (!response) {
        this.toastrService.error("File not received from server");
        return;
      }

      // Detect PDF or DOCX
      const fileType = response.type;
      const extension = fileType.includes('pdf') ? 'pdf' : 'docx';

      const blob = new Blob([response], { type: fileType });
      const blobUrl = window.URL.createObjectURL(blob);

      // Now you have the blob URL - use it however you need
      console.log('Blob URL:', blobUrl);
      
      // Example: Open in new tab (for PDF)
      if (extension === 'pdf') {
        window.open(blobUrl, '_blank');
      }
      
      // Example: Store it for later use
      // this.fileUrl = blobUrl;
      
      // Example: Pass to an iframe
      // this.pdfSrc = blobUrl;

      this.toastrService.success("File loaded successfully");
      
      // IMPORTANT: Clean up the blob URL when you're done with it
      // Don't revoke immediately if you're using it elsewhere
      // window.URL.revokeObjectURL(blobUrl);
    },
    error: (err) => {
      console.error(err);
      this.toastrService.error("Failed to load file");
    }
  });
          this.ngxUILoaderService.stop(); // Stop loader on error

}

downloadLetterAfterAccept(pk_trnid: number) {
  this.ngxUILoaderService.start();

  this.Service.downloadFormat(pk_trnid).subscribe({
    next: (response: Blob) => {
      this.ngxUILoaderService.stop();

      if (!response) {
        this.toastrService.error("File not received from server");
        return;
      }

      const fileType = response.type;
      const extension = fileType.includes('pdf') ? 'pdf' : 'docx';

      const blob = new Blob([response], { type: fileType });
      const blobUrl = window.URL.createObjectURL(blob);

      // 🔥 DIRECT DOWNLOAD
      const a = document.createElement('a');
      a.href = blobUrl;
      a.download = `Letter.${extension}`;  // file name
      a.click();

      // cleanup
      window.URL.revokeObjectURL(blobUrl);

      this.toastrService.success("File downloaded successfully");
    },
    error: (err) => {
      this.ngxUILoaderService.stop();
      console.error(err);
      this.toastrService.error("Failed to download file");
    }
  });
}
// updateStatus(id: number, status: number) {
//   const boolStatus = status === 1 ? true : false;
//   this.Service.updateLetterStatus(id, boolStatus).subscribe({
//     next: (res) => {
//       if (res.isSuccess) {
//         this.toastrService.success(res.message, 'Success');
//         this.getdata(); // refresh grid
//       } else {
//         this.toastrService.error(res.message, 'Error');
//       }
//     },
//     error: (err) => {
//       this.toastrService.error('Something went wrong', 'Error');
//       console.error(err);
//     }
//   });
// }

updateStatus(id: number, status: number) {
  const boolStatus = status === 1;

  // validation (optional but good)
  if (!this.remark || this.remark.trim() === '') {
    this.toastrService.warning('Please enter remark');
    return;
  }

  this.Service.updateLetterStatus(id, boolStatus, this.remark).subscribe({
    next: (res) => {
      if (res.isSuccess) {
        this.toastrService.success(res.message, 'Success');
         
           // 2. close modal
          const modalElement = document.getElementById('letterModal');
          if (modalElement) {
            const modal = bootstrap.Modal.getInstance(modalElement);
            modal?.hide();
          }
        
        
        this.remark = '';   // reset after save
        this.getdata();     // refresh grid
      } else {
        this.toastrService.error(res.message, 'Error');
      }
    },
    error: (err) => {
      this.toastrService.error('Something went wrong', 'Error');
      console.error(err);
    }
  });
}

openLetterModal(item: any) {
  this.selectedLetter = item;

  this.ngxUILoaderService.start();

  this.Service.downloadFormat(item.pk_trnid).subscribe({
    next: (response: Blob) => {
      this.ngxUILoaderService.stop();

      if (!response) {
        this.toastrService.error("File not received");
        return;
      }
      console.log(response.type);

      const blob = new Blob([response], { type: response.type });
      //const blobUrl = window.URL.createObjectURL(blob);

      const blobUrl = window.URL.createObjectURL(blob) + '#toolbar=0&navpanes=0&scrollbar=0';

      //  MAIN FIX
      //this.selectedLetter.fileUrl = blobUrl;
      this.selectedLetter.fileUrl =
  this.sanitizer.bypassSecurityTrustResourceUrl(blobUrl);

    
const modalElement = document.getElementById('letterModal');
if (modalElement) {
  const modal = new bootstrap.Modal(modalElement);
  modal.show();


  }
    },
    error: () => {
      this.ngxUILoaderService.stop();
      this.toastrService.error("Failed to load file");
    }
  });
}

}




