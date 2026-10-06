import { Component, inject } from '@angular/core';
import { FormBuilder, FormGroup, FormsModule, ReactiveFormsModule, Validators } from '@angular/forms';
import { NgSelectModule } from '@ng-select/ng-select';

import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { CommonModule } from '@angular/common';
import { NgxUiLoaderService } from 'ngx-ui-loader';
import { EncryptionService } from '../../../../../shared/services/encryption.service';
import { ToastrService } from 'ngx-toastr';

import { PageRightsService } from '../../services/page-rights.service';

@Component({
  selector: 'app-page-rights',
  standalone: true,
  imports: [ReactiveFormsModule,CommonModule,NgSelectModule,FormsModule],
  templateUrl: './page-rights.component.html',
  styleUrl: './page-rights.component.scss'
})
export class PageRightsComponent {


  ngxUILoaderService = inject(NgxUiLoaderService);
   webpages: any[] = [];
    Form!: FormGroup;
    submitted = false;
    showError = false;
    Isedit = false;
    
    selectedLocations: string[] = [];
   
    Location: { name: string, value: string }[] = []; 
    Userlist: { name: string, value: string }[] = []; 
    ModuleList: { name: string, value: string }[] = [];

    //table variable
    Selected: boolean = false;
    allL1: boolean = false;
    allL2: boolean = false;
    allL3: boolean = false;
    allRaiseReq: boolean = false;
    allEditManpower: boolean = false;

   constructor(
      private fb: FormBuilder,
      private http:PageRightsService,
      private toastrService: ToastrService,private router: Router,private route: ActivatedRoute,public encryptionserivce:EncryptionService) { }
  

  
   ngOnInit() {
      this.Form = this.fb.group({
        fk_locid: [[],Validators.required],
        fk_userId:[null,Validators.required],
         fk_moduleId: [null, Validators.required]
      });
  
     
       this.getLocationList('Location');
       this.getUSerList('User');
       this.GetModulelist();
       

         //  Trigger when either User or Module changes
  this.Form.get('fk_userId')?.valueChanges.subscribe(() => {
    this.checkAndLoadWebPages();
  });

  this.Form.get('fk_moduleId')?.valueChanges.subscribe(() => {
    this.checkAndLoadWebPages();
  });
    }

   //Selects/deselects all locations.
    toggleSelectAll() {
      if (this.isAllSelected()) {
        this.selectedLocations = [];
      } else {
        this.selectedLocations = this.Location.map(loc => loc.value);
      }
      this.Form.patchValue({ fk_locid: this.selectedLocations });
    }
    //for check all location selected or not return true if checked all otherwise false
    isAllSelected(): boolean {
      return this.selectedLocations.length === this.Location.length;
    }
    //Returns appropriate display text based on selection.
    getLocationDisplayText(): string {
      if (this.isAllSelected()) {
        return "All Selected";
      } 
      else if (this.selectedLocations.length === 1) {
        // Sirf ek value select ho tab uska naam dikhana hai
        return this.Location.find(item => item.value === this.selectedLocations[0])?.name || "--Select Locations--";
      } 
      else if (this.selectedLocations.length > 1) {
        // Multiple values select ho to pehla naam + "..."
        const firstSelected = this.Location.find(item => item.value === this.selectedLocations[0])?.name;
        return firstSelected ? `${firstSelected}...` : "--Select Locations--";
      } 
      else {
        return "--Select Locations--";
      }
    }
    
  //Adds/removes a location from the selection.
    toggleLocation(location: string) {
      if (this.selectedLocations.includes(location)) {
        this.selectedLocations = this.selectedLocations.filter(item => item !== location);
      } else {
        this.selectedLocations.push(location);
      }
      this.Form.patchValue({ fk_locid: this.selectedLocations });
    }
// Get location list
getLocationList(fieldName: string) {
  this.ngxUILoaderService.start(); // Start loader before API call

  this.http.getLocation(fieldName).subscribe({
    next: (res) => {
      if (res?.isSuccess && res.data?.length) {
        // Transform response data into name-value pairs
      //  const processedData = res.data.slice(1); // Create a new array without the first element

       const processedData = res.data;

        this.Location = processedData.map((location: any) => ({
          name: location.name,
          value: location.value
        }));
      } else {
        this.toastrService.error("Failed to load location list.");
      }
      this.ngxUILoaderService.stop(); // Stop loader after response
    },
    error: (err) => {
      console.error("Error fetching location list:", err);
      this.toastrService.error("Error fetching location list. Please try again.");
      this.ngxUILoaderService.stop(); // Ensure loader stops even on error
    }
  });
}

getUSerList(fieldName: string) {
  this.ngxUILoaderService.start(); // Start loader before API call

  this.http.getLocation(fieldName).subscribe({
    next: (res) => {
      if (res?.isSuccess && res.data?.length) {
        // Transform response data into name-value pairs
        this.Userlist = res.data.map((location: any) => ({
          name: location.name,
          value: location.value
        }));
      } else {
        this.toastrService.error("Failed to load user list.");
      }
      this.ngxUILoaderService.stop(); // Stop loader after response
    },
    error: (err) => {
      console.error("Error fetching user list:", err);
      this.toastrService.error("Error fetching user list. Please try again.");
      this.ngxUILoaderService.stop(); // Ensure loader stops even on error
    }
  });
}
    
   
  
  GetModulelist() {
    this.http.getModuelList().subscribe({
      next: (res) => {
        if (res.isSuccess && res.data) {
          this.ModuleList = res.data.map((m: any) => ({
            name: (Number(m.value) === 5 || (m.name && m.name.toLowerCase().includes('recruitment')))
              ? 'Recruitment Management (ATS Talent Suite)'
              : m.name,
            value: m.value
          }));

          const queryModId = this.route.snapshot.queryParams['moduleId'];
          if (queryModId) {
            const found = this.ModuleList.find(x => String(x.value) === String(queryModId));
            if (found) {
              this.Form.patchValue({ fk_moduleId: found.value });
            }
          }
        } else {
          this.toastrService.error("Failed to load module list.");
        }
      },
      error: (err) => {
        console.error("Error fetching module list:", err);
        this.toastrService.error("Error fetching module.");
      }
    });
  }

  
  


  submit() {
  this.submitted = true;
  if (this.Form.invalid) {
      this.showError = true;
     this.submitted = true;
    return;
  }

  const formValues = this.Form.value;

  if(this.selectedLocations[0]==null)
     this.selectedLocations.splice(0,1);
  // Build location list
  console.log(this.selectedLocations)
  const locationList = (this.selectedLocations || []).map(loc => ({
    fk_locid: loc
  }));

     
    

  // Build page rights list
  const isRec = this.isRecruitmentModule();
  const uM_UserPageRights = this.webpages
    .filter(page => page.isSelected) // only selected rows
    .map(page => ({
      fk_webpageId: page.pk_webpageId,
      allowAdd: page.AllowAdd ?? true,
      allowUpdate: page.AllowUpdate ?? true,
      allowDelete: page.AllowDelete ?? true,
      allowView: page.AllowView ?? true,
      L1_Access: isRec && this.isApprovalPage(page) ? !!page.L1_Access : false,
      L2_Access: isRec && this.isApprovalPage(page) ? !!page.L2_Access : false,
      L3_Access: isRec && this.isApprovalPage(page) ? !!page.L3_Access : false,
      CanRaiseRequisition: isRec && this.isRaiseReqPage(page) ? true : false,
      CanEditManpower: isRec && this.isHeadcountPage(page) ? true : false
    }));

  if (!uM_UserPageRights.length) {
    this.toastrService.warning('Please select at least one page.');
    return;
  }

  const payload = {
    userid: formValues.fk_userId,
    moduleid: Number(formValues.fk_moduleId),
    locationList,
    uM_UserPageRights
  };

  console.log('Payload:', payload);

  // API Call
  this.ngxUILoaderService.start();
  this.http.add_pageRight(payload).subscribe({
    next: (res: any) => {
      this.ngxUILoaderService.stop();
      if (res.isSuccess) {
        this.toastrService.success('Page rights saved successfully!');
       // this.router.navigate(['/dashboard/page-rights-list']);
      } else {
        this.toastrService.error(res.message || 'Failed to save page rights.');
      }
    },
    error: (err) => {
      this.ngxUILoaderService.stop();
      console.error('Error:', err);
      this.toastrService.error('Something went wrong.');
    }
  });
}

  /** Select/Deselect all rows */
  AllSelect(): void {
    this.webpages.forEach(item => (item.isSelected = this.Selected));
  }

  toggleAllL1(): void {
    this.webpages.forEach(item => {
      item.L1_Access = this.allL1;
      if (this.allL1) item.isSelected = true;
    });
  }

  toggleAllL2(): void {
    this.webpages.forEach(item => {
      item.L2_Access = this.allL2;
      if (this.allL2) item.isSelected = true;
    });
  }

  toggleAllL3(): void {
    this.webpages.forEach(item => {
      item.L3_Access = this.allL3;
      if (this.allL3) item.isSelected = true;
    });
  }



  isRecruitmentModule(): boolean {
    const mod = this.Form?.get('fk_moduleId')?.value;
    return Number(mod) === 5;
  }

  isApprovalPage(page: any): boolean {
    if (!this.isRecruitmentModule() || !page) return false;
    const name = (page.menucaption || '').toLowerCase();
    const path = (page.pagepath || '').toLowerCase();
    return page.pk_webpageId === 9011 || name.includes('approval') || path.includes('job-management');
  }

  isRaiseReqPage(page: any): boolean {
    if (!this.isRecruitmentModule() || !page) return false;
    const name = (page.menucaption || '').toLowerCase();
    const path = (page.pagepath || '').toLowerCase();
    return page.pk_webpageId === 9010 || page.pk_webpageId === 9009 || page.pk_webpageId === 795 ||
           name.includes('create mrf') || name.includes('create job') || name.includes('open new job') || path.includes('create-job-wizard');
  }

  isHeadcountPage(page: any): boolean {
    if (!this.isRecruitmentModule() || !page) return false;
    const name = (page.menucaption || '').toLowerCase();
    const path = (page.pagepath || '').toLowerCase();
    return page.pk_webpageId === 9012 || name.includes('headcount') || path.includes('location-manpower-headcount');
  }

  onRightChange(page: any): void {
    if (page.L1_Access || page.L2_Access || page.L3_Access) {
      page.isSelected = true;
    }
  }

  checkAndLoadWebPages() {
  const fk_userId = this.Form.get('fk_userId')?.value;
  const fk_moduleId = this.Form.get('fk_moduleId')?.value;

  if (fk_userId && fk_moduleId) {
    this.http.get_Webpage(fk_userId, fk_moduleId).subscribe({
      next: (res: any) => {
        if (res.isSuccess && res.data) {
          this.webpages = res.data.map((item: any) => ({
            ...item,
            isSelected: item.IsAssigned === 1,
            AllowAdd: item.AllowAdd === 1 || item.AllowAdd === true,
            AllowUpdate: item.AllowUpdate === 1 || item.AllowUpdate === true,
            AllowDelete: item.AllowDelete === 1 || item.AllowDelete === true,
            AllowView: item.AllowView === 1 || item.AllowView === true,
            L1_Access: item.L1_Access === 1 || item.L1_Access === true,
            L2_Access: item.L2_Access === 1 || item.L2_Access === true,
            L3_Access: item.L3_Access === 1 || item.L3_Access === true,
            CanRaiseRequisition: item.CanRaiseRequisition === 1 || item.CanRaiseRequisition === true,
            CanEditManpower: item.CanEditManpower === 1 || item.CanEditManpower === true
          }));
          this.Selected = this.webpages.length > 0 && this.webpages.every(w => w.isSelected);
        } else {
          this.webpages = [];
          this.toastrService.warning(res.message || 'No records found.');
        }
      },
      error: () => {
        this.webpages = [];
        this.toastrService.error('Failed to fetch web pages.');
      }
    });

    // Also load assigned locations from GetUserAccessRights
    this.http.getUserAccessRights(fk_userId, fk_moduleId).subscribe({
      next: (res: any) => {
        if (res?.isSuccess && res.data?.assignedLocationIds?.length) {
          this.selectedLocations = res.data.assignedLocationIds.map((id: any) => String(id));
          this.Form.patchValue({ fk_locid: this.selectedLocations });
        }
      },
      error: () => {
        // Non-blocking if no access rights yet
      }
    });
  }
}
}