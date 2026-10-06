import { CommonModule } from '@angular/common';
import { Component } from '@angular/core';
import { FormBuilder, FormGroup, FormsModule, ReactiveFormsModule, Validators } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { NgSelectComponent, NgSelectModule } from '@ng-select/ng-select';
import { NgxPaginationModule } from 'ngx-pagination';
import { ToastrService } from 'ngx-toastr';
import { CommonSearchComponent } from '../../Employee/common-search/common-search.component';
// import { TransactionService } from '../../services/transaction.service';
import { SalarySleepMessageService } from '../../services/salary-sleep-message.service';
import { NgxUiLoaderService } from 'ngx-ui-loader';
// import { re } from 'mathjs';
import { LoanTransactionService } from '../../services/loan-transaction.service';
import { ManualPunchBio } from '../../services/manual-puch-bio.service';

@Component({
  selector: 'app-salary-lock',
  standalone: true,
  imports: [FormsModule,ReactiveFormsModule,CommonModule,NgxPaginationModule,NgSelectComponent,CommonSearchComponent],
  templateUrl: './salary-lock.component.html',
  styleUrl: './salary-lock.component.scss'
})
export class SalaryLockComponent {
EmployeeForm!: FormGroup;
isContractApplicable= false;
CostCenter:any[]=[];
  submitted=false;
  showEmployeeList: boolean = false;
  employees: { name: string, value: string }[] = [];
  showError =false;
  EmployeeList:any={}
  searchText:string="";
Isedit=false;
pageIndex1: number = 1;
pageSize1: number = 10;
pageIndex2: number = 1;
pageSize2: number = 10;
searchTextLock = '';
searchTextUnUnLock = '';
salarylockedcount: number = 0;
salaryunlockcount: number = 0;
filteredLockedList: any[] = [];
filteredUnLockedList: any[] = [];

months = [];
years = [];
  constructor(
    private fb: FormBuilder,
    private  toastrService: ToastrService,
    private router: Router,
    private commanservice: ManualPunchBio,
    private httpservice: SalarySleepMessageService,     private Loader:NgxUiLoaderService,) {}

  ngOnInit() {
    this.isContractApplicable =   sessionStorage.getItem('ContractApplicable')=="true" ? true:false;
  
    this.filteredLockedList = this.EmployeeList.salarylocked || [];
    this.filteredUnLockedList = this.EmployeeList.salaryunlock || [];

    this.EmployeeForm = this.fb.group({
      empCode: [''],
      fk_monthId: ['',[ Validators.required]],
      fk_yearId: ['',[ Validators.required]],
       fk_costcentreid:[null],
      empCodeManual: [''],
      empName: [''],
      selectedDepartments: [[]],
      selectedDesignation: [''],
      selectedLocations: [[]],
      selectedNature: [''],
      selectedCity: [''],
      sortBy: [''],
      // Fk_userid: [''],
      // Fk_locid:['']
    });
    this.getMonthsList();
    this.getyearsList();
    this.getList();
  } 
  
  
  onpageChange(event:number)
  
  {this.pageIndex2=event;
    debugger
    this.OnVeiw()

  }  

  
  onpageChange1(event:number)

  {this.pageIndex1=event;
  
    this.OnVeiw()

  }  
  getMonthsList() {
    this.commanservice.getCommanList('month').subscribe({
      next: (res) => {
        this.months = res.data
      }
    })
  }
  getyearsList() {
    this.commanservice.getCommanList('Year').subscribe({
      next: (res) => {
        this.years = res.data
      }
    })
  }

  getList() {
    this.commanservice.getCommanList('CostCenter').subscribe({
      next: (res) => {
        this.CostCenter = res.data
      }
    })
  }
      
      // Handle filter updates from common search
      handleFilters(filters: any) {

        this.EmployeeForm.patchValue(filters);
      }


      
      filtersalaryData(type: 'Locked' | 'UnLocked') {
 
    
    let list: any[] = [];
    let searchText = '';
  
    switch (type) {
      case 'Locked':
        list = this.EmployeeList.salarylocked || [];
        searchText = this.searchTextLock;
        this.filteredLockedList= this.applySearch(list, searchText);
        break;
      case 'UnLocked':
        list = this.EmployeeList.salaryunlock || [];
        searchText = this.searchTextUnUnLock;
        this.filteredUnLockedList = this.applySearch(list, searchText);
        break;  
    }
  }
  
  applySearch(list: any[], searchText: string): any[] {
    if (!searchText) return list;
    const search = searchText.toLowerCase();
    return list.filter(emp =>
      (emp.empname?.toLowerCase().includes(search) || '') ||
      (emp.empcode?.toLowerCase().includes(search) || '') ||
      (emp.manualempcode?.toLowerCase().includes(search) || '') ||
      (emp.location?.toLowerCase().includes(search) || '') ||
      (emp.department?.toLowerCase().includes(search) || '') ||
      (emp.designation?.toLowerCase().includes(search)  || '')
    );
  }


    OnVeiw(){
    this.submitted = true;
    if (this. EmployeeForm.invalid) {
      this.showError = true;
     
       return;
    }
  
  const payload = this.EmployeeForm.value ;
  
  Object.keys(payload).forEach(key=>{
    if(payload[key]===null){
     payload[key]='';
  }
  })

  
  

 // this.Loader.start();
    this.httpservice.get_Salarylock(this.pageIndex1 - 1, this.pageSize1 ,this.pageIndex2 - 1, this.pageSize2,payload).subscribe({
      next: (res) => {
        if (res.isSuccess) {
          this.showEmployeeList = true
          //this.Loader.stop();
          this.EmployeeList = res.data;
          this.filteredLockedList=[]
          this.filteredUnLockedList=[]
          this.searchTextLock=''
          this.searchTextUnUnLock=''
           this.salarylockedcount = res.data.salarylockedcount;
           this.salaryunlockcount = res.data.salaryunlockcount;
           this.filtersalaryData('Locked');
           this.filtersalaryData('UnLocked');
         

        } else {
       
          this.toastrService.info(res.message)
          this.filteredLockedList = [];
          this.filteredUnLockedList = [];
          this.EmployeeList={}
          this.salarylockedcount=0,
          this.salaryunlockcount=0
        }
      },
      error: (error) => {
        this.employees = [];
        this.toastrService.error('Failed to retrieve employees', error);
      }
    });
  }

//update lock or unlock 

updateunLock(){
  this.submitted = true;
  if (this. EmployeeForm.invalid) {
    this.showError = true;
   
     return;
  }
const payload = this.EmployeeForm.value ;
  
  Object.keys(payload).forEach(key=>{
    if(payload[key]===null){
     payload[key]='';
  }
  })

  this.httpservice.get_emplyeeSalaryunlock(payload).subscribe({
next:(res)=>{
  if(res.isSuccess){
    this.toastrService.success(res.message);
    //this.filteredUnLockedList=res.data;
    this.OnVeiw()
  }
  else{
    this.toastrService.info(res.message);
  }
},
error: (error) => {
  this.employees = [];
  this.toastrService.error('Failed to retrieve employees', error);
}
  })

}
   
updateLock(){
  this.submitted = true;
  if (this. EmployeeForm.invalid) {
    this.showError = true;
   
     return;
  }

  const payload = this.EmployeeForm.value ;
  
  Object.keys(payload).forEach(key=>{
    if(payload[key]===null){
     payload[key]='';
  }
  })

  this.httpservice.get_emplyeeSalarylock(payload).subscribe({
next:(res)=>{
  if(res.isSuccess){
    this.toastrService.success(res.message);
 //   this.filteredLockedList=res.data;
 this.OnVeiw()
  }
  else{
    this.toastrService.info(res.message);
  }
},
error: (error) => {
  this.employees = [];
  this.toastrService.error('Failed to retrieve employees', error);
}
  })

}
}


