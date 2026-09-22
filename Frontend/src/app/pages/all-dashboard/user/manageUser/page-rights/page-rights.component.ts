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
    // this.ngxUILoaderService.start(); // Start loader before API call
    this.http.getModuelList().subscribe({
        next: (res) => {
            if (res.isSuccess && res.data) {
              
                this.ModuleList = res.data.map((leaveType: any) => ({
                  name: leaveType.name,
                    value: leaveType.value
                }));
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
  const uM_UserPageRights = this.webpages
    .filter(page => page.isSelected) // only selected rows
    .map(page => ({
      fk_webpageId: page.pk_webpageId,  // Assuming API needs this property
      allowAdd: true,
      allowUpdate: true,
      allowDelete: true,
      allowView: true
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
 
    

  checkAndLoadWebPages() {
  const fk_userId = this.Form.get('fk_userId')?.value;
  const fk_moduleId = this.Form.get('fk_moduleId')?.value;

  if (fk_userId && fk_moduleId) {
    this.http.get_Webpage(fk_userId, fk_moduleId).subscribe({
      next: (res: any) => {
        if (res.isSuccess && res.data) {
           console.log('dfg',res.data)
          this.webpages = res.data.map((item: any) => ({

            ...item,
            isSelected: item.IsAssigned === 1
           
          }));
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
  }
}
  

  

}