import { CommonModule } from '@angular/common';
import { Component, inject } from '@angular/core';
import { FormBuilder, FormGroup, FormsModule, ReactiveFormsModule, Validators } from '@angular/forms';
import { Route, Router, RouterLink } from '@angular/router';
import { NgSelectModule } from '@ng-select/ng-select';
import { NgxPaginationModule } from 'ngx-pagination';
import { CommonSearchComponent } from '../../../payroll/Employee/common-search/common-search.component';
import { ToastrService } from 'ngx-toastr';
import { EncryptionService } from '../../../../../shared/services/encryption.service';
import { HrAppreciationMasterService } from '../../HRservices/hr-appreciation-master.service';
import { EmployeeMasterService } from '../../../payroll/services/employee-master.service';
import { GenerateLettersService } from '../../HRservices/generate-letters.service';
import { NgxUiLoaderService } from 'ngx-ui-loader';
import { CandidateService } from '../../HRservices/candidate.service';
import { FormArray } from '@angular/forms';
@Component({
  selector: 'app-generate-letters',
  standalone: true,
  imports: [
    FormsModule,
    RouterLink,
    ReactiveFormsModule,
    CommonModule,
    NgxPaginationModule,
    NgSelectModule,
    CommonSearchComponent,
  ],
  templateUrl: './generate-letters.component.html',
  styleUrl: './generate-letters.component.scss'
})
export class GenerateLettersComponent {

  form!: FormGroup;
  EmployeeList: { name: string; value: string }[] = [];
  Location: { label: string, value: string }[]  = []; 
  submitted = false;
  selectedFormType: string = '';
  ngxUILoaderService = inject(NgxUiLoaderService);
  HeadsList: any[] = [];

  FormateType = [
    { name: 'Appointment Letter', value: 'A' },
    { name: 'Confirmation Letter without Increment', value: 'C' },
    { name: 'Confirmation Letter with Increment', value: 'B' },
    { name: 'Confirmation Ext.', value: 'X' },
    { name: 'Promotion Letter', value: 'R' },
    { name: 'Retirement Letter', value: 'L' },
    { name: 'Transfer Letter', value: 'F' },
    { name: 'Experience Letter', value: 'E' },
  ];

  employeeFilters = {
    empCode: '',
    empCodeManual: '',
    empName: '',
    selectedDepartments: [],
    selectedDesignation: '',
    selectedLocations: [],
    selectedNature: '',
    selectedCity: '',
    sortBy: '',
    empStatus: '',
  };

  
  locationList: { name: string; value: string }[] = [];
  designationList: { name: string; value: string }[] = [];
  departmentList: { name: string; value: string }[] = [];
  HRList: { name: string; value: string }[] = [];
  cityList: { name: string; value: string }[] = [];
  constructor(
    private fb: FormBuilder,
    private Service: HrAppreciationMasterService,
    private employeeMasterService:EmployeeMasterService,
    private toastrService: ToastrService,
    private encryptionService: EncryptionService,
    private services :GenerateLettersService,
    private CandidateService:CandidateService,
    private Router:Router
  ) {}

  ngOnInit() {
    this.createForm();
    this.getEmployees();
      this.getLocationList('Location')
    
   this.getlocationlist('location');
   this.getdepartmentlist('department');
   this.getdesignationlist('designation');
   this.getcitylist('city');
   this.getHrlist('Employee');
    this.loadHeads();
  }

  createForm() {
  this.form = this.fb.group({
    fk_empid: [null, Validators.required],

     
           name: ['',Validators.required],
           nname: [''],
           fk_locid:  [null,Validators.required],
           fk_deptid: [null,Validators.required],
           fk_desgid: [null,Validators.required],
           fk_cityid: [null,Validators.required],
           pinno:[''],
           joiningdate: [null,Validators.required],
           ctc:[null,Validators.required],
           contactno: [null,Validators.required],
           address:[''],
           fk_emphrid:[null,Validators.required],

           statusId: [false],  // <-- Anajli

    // === HR_Format_Trn ===
   // fk_formatid: [''],
    formattype: ['', Validators.required],
    refno: [''],
    dated: [null,Validators.required],
    eperiod: [''],
    fk_pdesgid: [''],
    newctc: [0],
    effectivedate: [null],
    fk_empcooid: [''],
    confirmdate: [null],
    resigndate: [null],
    relievedate: [null],
    trandate: [null],
    fk_tran_tolocid: [null],
    description: [''],
    IncrementAmount: [0],
    PerMonthSalary: [0],
    PLI: [''],
    fk_Offerdesgid: [''],
    fk_Offergrade: [''],
    fk_Offerempid: [''],
    offergender: [''],
    fk_Offercostcentreid: [''],
    comments1: [''],
    comments2: [''],
    comments3: [''],
    comments4: [''],

  //   // === HR_Format_Head ===
  //   fk_headid: [0],
  //   annualamount: [0],
  //   amount: [0]
   // === DYNAMIC HEADS ===
      FormatHeads: this.fb.array([])   // <- ARRAY HERE
  });

 
}
// get FormatHeads() {
//   return this.form.get('FormatHeads') as any;
// }
get FormatHeads(): FormArray<FormGroup> {
  return this.form.get('FormatHeads') as FormArray<FormGroup>;
}



//ANAJLI 


 // In your generate-letters.component.ts

onEmployeeChange(event: any) {
 // const selectedEmpId = event;
    const selectedEmpId = event?.value || event?.pk_empid || event;

  if (!selectedEmpId) {
    return;
  }

  this.ngxUILoaderService.start();
  
  // ✅ Call the new service method
  this.services.getEmployeeById(selectedEmpId).subscribe({
    next: (res) => {
      if (res?.isSuccess && res.data) {
        const empData = res.data;
        
        // Auto-populate form fields
        this.form.patchValue({
          name: empData.empname || '',
          nname: empData.nname || '',
          fk_locid: empData.fk_locid || null,
          fk_deptid: empData.fk_deptid || null,
          fk_desgid: empData.fk_desgid || null,
          fk_cityid: empData.fk_cityid || null,
          fk_emphrid: empData.fk_emphrid || null,
          contactno: empData.contactno || '',
          pinno: empData.pinno || '',
          address: empData.address || '',
         // joiningdate: empData.dateofjoining || null,
        joiningdate: empData.dateofjoining ? empData.dateofjoining.split('T')[0] : null,
          ctc: empData.ctc || 0
        });

        this.toastrService.success('Employee details loaded successfully');
      } else {
        this.toastrService.error('Failed to load employee details');
      }
      this.ngxUILoaderService.stop();
    },
    error: (err) => {
      console.error('Error fetching employee details:', err);
      this.toastrService.error('Error loading employee details');
      this.ngxUILoaderService.stop();
    }
  });
}

//


  onFormTypeChange(event: any) {
    this.selectedFormType = event.value;
  }

  handleFilters(filters: any) {
    this.employeeFilters = filters;
    this.getEmployees();
  }
loadHeads() {
  this.services.Getheads().subscribe({
    next: (res) => {
      if (res) {

        // Store all dynamic heads
        this.HeadsList = res.data;

      
      
  const headsFormArray: FormArray<FormGroup> = new FormArray<FormGroup>([]);

      this.HeadsList.forEach((h: any) => {
        headsFormArray.push(
          this.fb.group({
            fk_headid: [h.pk_headid],
            headname: [h.shortdesc],
            annualamount: [h.annualamount || 0],
            amount: [h.amount || 0]
          })
        );
      });

this.form.setControl('FormatHeads', headsFormArray);

       
      }
    },
    error: (err) => {
      console.error("Error loading heads:", err);
      this.toastrService.error("Failed to load heads");
    }
  });
}


   getHrlist(fieldName: string) {
    this.ngxUILoaderService.start();
    this.CandidateService.getEmployee(fieldName).subscribe({
      next: (res) => {
        if (res?.isSuccess && res.data?.length) {
          console.log(res.data)
          this.HRList= res.data.map((Emp: any) => ({
            name: Emp.name,
            value: Emp.value
          }));
        } else {
          this.toastrService.error("Failed to load Hr list.");
        }
        this.ngxUILoaderService.stop();
      },
      error: (err) => {
        console.error("Error fetching Hr list:", err);
        this.toastrService.error("Error fetching Hr list. Please try again.");
        this.ngxUILoaderService.stop();
      }
    });
  }
  getlocationlist(fieldName: string) {
    this.ngxUILoaderService.start();
    this.CandidateService.getEmployee(fieldName).subscribe({
      next: (res) => {
        if (res?.isSuccess && res.data?.length) {
          console.log(res.data)
          this.locationList= res.data.map((Emp: any) => ({
            name: Emp.name,
            value: Emp.value
          }));
        } else {
          this.toastrService.error("Failed to load  location list.");
        }
        this.ngxUILoaderService.stop();
      },
      error: (err) => {
        console.error("Error fetching location list:", err);
        this.toastrService.error("Error fetching employee list. Please try again.");
        this.ngxUILoaderService.stop();
      }
    });
  }

  getdepartmentlist(fieldName: string) {
    this.ngxUILoaderService.start();
    this.CandidateService.getEmployee(fieldName).subscribe({
      next: (res) => {
        if (res?.isSuccess && res.data?.length) {
          console.log(res.data)
          this.departmentList= res.data.map((Emp: any) => ({
            name: Emp.name,
            value: Emp.value
          }));
        } else {
          this.toastrService.error("Failed to load  department list.");
        }
        this.ngxUILoaderService.stop();
      },
      error: (err) => {
        console.error("Error fetching department list:", err);
        this.toastrService.error("Error fetching department list. Please try again.");
        this.ngxUILoaderService.stop();
      }
    });
  }

  getdesignationlist(fieldName: string) {
    this.ngxUILoaderService.start();
    this.CandidateService.getEmployee(fieldName).subscribe({
      next: (res) => {
        if (res?.isSuccess && res.data?.length) {
          console.log(res.data)
          this.designationList= res.data.map((Emp: any) => ({
            name: Emp.name,
            value: Emp.value
          }));
        } else {
          this.toastrService.error("Failed to load  designation list.");
        }
        this.ngxUILoaderService.stop();
      },
      error: (err) => {
        console.error("Error fetching designation list:", err);
        this.toastrService.error("Error fetching designation list. Please try again.");
        this.ngxUILoaderService.stop();
      }
    });
  }

  getcitylist(fieldName: string) {
    this.ngxUILoaderService.start();
    this.CandidateService.getEmployee(fieldName).subscribe({
      next: (res) => {
        if (res?.isSuccess && res.data?.length) {
          console.log(res.data)
          this.cityList= res.data.map((Emp: any) => ({
            name: Emp.name,
            value: Emp.value
          }));
        } else {
          this.toastrService.error("Failed to load  city list.");
        }
        this.ngxUILoaderService.stop();
      },
      error: (err) => {
        console.error("Error fetching city list:", err);
        this.toastrService.error("Error fetching city list. Please try again.");
        this.ngxUILoaderService.stop();
      }
    });
  }
  
   getLocationList(fieldName: string) {
        this.employeeMasterService.get_DropdownList(fieldName).subscribe({
            next: (res) => {
                if (res.isSuccess && res.data) {
                    this.Location = res.data.map((fk_locid: any) => ({
                        name: fk_locid.name,
                        value: fk_locid.value
                    }));
                } else {
                    this.toastrService.error("Failed to load Location list.");
                }
            },
            error: (err) => {
                this.toastrService.error("Error fetching Location list.");    
            }
        });
      }

  getEmployees(): void {
    this.Service.get_Employees_Ddl(this.employeeFilters).subscribe({
      next: (res) => {
        if (res.isSuccess) {
          this.EmployeeList = res.data.map((emp: any) => ({
            name: emp.name,
            value: emp.value,
          }));
        } else {
          this.EmployeeList = [];
          this.toastrService.error(res.message, 'Error');
        }
      },
      error: () => {
        this.EmployeeList = [];
        this.toastrService.error('Failed to retrieve employees', 'Error');
      },
    });
  }

  

save() {
  this.submitted = true;

  if (this.form.invalid) {
    this.toastrService.error("Please fill all required fields");
    return;
  }

  // ---- HR_Format_Mst (Candidate/Employee basic profile) ----
  const Candidates = {
   // pk_formatid: this.form.value.pk_formatid,
    fk_empid: this.form.value.fk_empid,
    fk_locid: this.form.value.fk_locid,
    location: this.locationList.find(x => x.value == this.form.value.fk_locid)?.name || '',
    fk_deptid: this.form.value.fk_deptid,
    fk_desgid: this.form.value.fk_desgid,
    designation: this.designationList.find(x => x.value == this.form.value.fk_desgid)?.name || '',
    fk_cityid: this.form.value.fk_cityid,
    fk_emphrid: this.form.value.fk_emphrid,
    name: this.form.value.name,
    senderName :sessionStorage.getItem('username') ?? 'HR Team',
    nname: this.form.value.nname,
    contactno: this.form.value.contactno,
    pinno: this.form.value.pinno,
    address: this.form.value.address,
    joiningdate: this.form.value.joiningdate,
    ctc: this.form.value.ctc,
    ctcinword: '',  // If needed you may fill later
    statusId: this.form.value.statusId  // <-- Anajli
  };

    console.log("Status ID:", this.form.value.statusId);  

  // ---- HR_Format_Trn ----
  const FormatTrn = {
    //fk_formatid: this.form.value.fk_formatid,
    formattype: this.form.value.formattype,
    refno: this.form.value.refno,
    dated: this.form.value.dated,
    eperiod: this.form.value.eperiod,
    // fk_pdesgid: this.form.value.fk_pdesgid,
    fk_pdesgid: this.form.value.fk_desgid,
    newctc: this.form.value.newctc,
    effectivedate: this.form.value.effectivedate,
    // fk_empcooid: this.form.value.fk_empcooid,
     fk_empcooid: this.form.value.fk_empid,
    confirmdate: this.form.value.confirmdate,
    resigndate: this.form.value.resigndate,
    relievedate: this.form.value.relievedate,
    trandate: this.form.value.trandate,
    fk_tran_tolocid: this.form.value.fk_tran_tolocid,
    description: this.form.value.description,
    IncrementAmount: this.form.value.IncrementAmount,
    PerMonthSalary: this.form.value.PerMonthSalary,
    PLI: this.form.value.PLI,
    fk_Offerdesgid: this.form.value.fk_desgid,
    fk_Offergrade: this.form.value.fk_Offergrade,
    fk_Offerempid: this.form.value.fk_empid,
    offergender: this.form.value.offergender,
    fk_Offercostcentreid: this.form.value.fk_Offercostcentreid,
    comments1: this.form.value.comments1,
    comments2: this.form.value.comments2,
    comments3: this.form.value.comments3,
    comments4: this.form.value.comments4
  };

  
const FormatHeads = this.form.value.FormatHeads.map((h: any) => ({
  fk_headid: h.fk_headid,
  annualamount: h.annualamount || 0,
  amount: h.amount || 0
}));

  // ---- FINAL PAYLOAD (XML READY) ----
  const payload = {
    Candidates: Candidates,
    FormatTrn: FormatTrn,
    FormatHeads: FormatHeads
  };

  console.log("FINAL PAYLOAD SENT TO API:", payload);

  this.services.insert(payload).subscribe({
    next: (res: any) => {
      if (res.isSuccess === true) {
        this.toastrService.success("Letter Saved Successfully");
         this.Router.navigate(['/dash/hr/hrdashboard/Generate_letters_list']);
        // this.form.reset();
        //     //  this.loadHeads();     // <-- Reload dynamic heads

        // this.submitted = false;
      } else {
        this.toastrService.error(res.message || "Something went wrong");
      }
    },
    error: (err) => {
      this.toastrService.error("Server error");
      console.error(err);
    }
  });
}


  reset() {
    this.form.reset();
    this.submitted = false;
    this.selectedFormType = '';
  }
   validateNumber(event: KeyboardEvent) {
    const charCode = event.key.charCodeAt(0);
    if (charCode < 48 || charCode > 57) {
      event.preventDefault(); // Block non-numeric characters
    }
  }
}
