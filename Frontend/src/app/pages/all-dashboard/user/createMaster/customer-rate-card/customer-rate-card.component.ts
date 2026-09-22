import { CommonModule } from '@angular/common';
import { Component, OnInit } from '@angular/core';
import { FormArray, FormBuilder, FormControl, FormGroup, FormsModule, ReactiveFormsModule, Validators } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { NgSelectComponent } from '@ng-select/ng-select';
import { NgxUiLoaderService } from 'ngx-ui-loader';
import { ToastrService } from 'ngx-toastr';
import { CustomerRateCardService } from '../../services/customer-rate-card.service';
import { EmployeeMasterService } from '../../../payroll/services/employee-master.service';
import { GeneralService } from '../../../payroll/services/general.service';

@Component({
  selector: 'app-customer-rate-card',
  standalone: true,
  imports: [ReactiveFormsModule, NgSelectComponent, CommonModule, FormsModule, RouterLink],
  templateUrl: './customer-rate-card.component.html',
  styleUrl: './customer-rate-card.component.scss'
})
export class CustomerRateCardComponent implements OnInit {

  rateCardForm!: FormGroup;
  earningHeadsList = new FormArray<FormGroup>([]);

  CustomerList: { name: string, value: string }[] = [];
  LocationList: { name: string, value: string }[] = [];
  ServiceTypeList: { name: string, value: string }[] = [];
  CategoryList: { name: string, value: string }[] = [];
  WorkDurationList: { name: string, value: string }[] = [];

  showError = false;
  submitted = false;
  rateCardId!: string | null;
  Isedit = false;

  constructor(
    private fb: FormBuilder,
    private rateCardService: CustomerRateCardService,
    private employeeMasterService: EmployeeMasterService,
    private generalService: GeneralService,
    private toastrService: ToastrService,
    private router: Router,
    private route: ActivatedRoute,
    private ngxLoader: NgxUiLoaderService
  ) { }

  ngOnInit(): void {
    this.initializeForm();
    this.loadDropdowns();

    this.route.paramMap.subscribe(params => {
      this.rateCardId = params.get('rateCardId');
      if (this.rateCardId && this.rateCardId !== 'undefined') {
        this.Isedit = true;
        this.loadRateCardData(Number(this.rateCardId));
      } else {
        this.getHeads();
      }
    });
  }

  initializeForm() {
    this.rateCardForm = this.fb.group({
      CustomerId: [null, Validators.required],
      LocationId: [null, Validators.required],
      ServiceTypeId: [null, Validators.required],
      CategoryId: [null, Validators.required],
      WorkDuration: [null, Validators.required],
      earningHeads: this.fb.array([])
    });

    this.earningHeadsList = this.rateCardForm.get('earningHeads') as FormArray;
  }

  get earningHeads(): FormArray {
    return this.rateCardForm.get('earningHeads') as FormArray;
  }

  loadDropdowns() {
    // Customers
    this.employeeMasterService.get_DropdownList('Client').subscribe(res => {
      if (res.isSuccess && res.data) {
        this.CustomerList = res.data.map((x: any) => ({ name: x.name, value: x.value }));
      }
    });

    // Locations
    this.employeeMasterService.get_DropdownList('Location').subscribe(res => {
      if (res.isSuccess && res.data) {
        this.LocationList = res.data.map((x: any) => ({ name: x.name, value: x.value }));
      }
    });

    // Service Type (CodetypeId = 14 from General Master)
    this.generalService.GetDdlListBasedOnCodeType('14').subscribe((res: any) => {
      if (res.isSuccess && res.data) {
        this.ServiceTypeList = res.data.map((x: any) => ({ name: x.text || x.name, value: Number(x.value) }));
      }
    });

    // Category
    this.employeeMasterService.get_DropdownList('Category').subscribe(res => {
      if (res.isSuccess && res.data) {
        this.CategoryList = res.data.map((x: any) => ({ name: x.name, value: x.value }));
      }
    });

    // Work Duration from Shift Master (company-specific distinct durations)
    this.employeeMasterService.get_DropdownList('ShiftDuration').subscribe(res => {
      if (res.isSuccess && res.data) {
        this.WorkDurationList = res.data.map((x: any) => ({ name: x.name, value: x.value }));
      }
    });
  }

  getHeads() {
    this.earningHeads.clear();

    this.rateCardService.getDynamicHeads().subscribe((response: any) => {
      if (response.isSuccess && response.data) {
        const headList: any[] = response.data;

        headList.forEach((item: any) => {
          const group = this.fb.group({
            fk_headid: item.pk_headid || item.fk_headid,
            shortDesc: item.shortdesc || item.shortDesc || item.headName,
            amount: [0, Validators.required]
          });
          this.earningHeads.push(group);
        });
      }
    });
  }

  get totalEarningCount(): number {
    let total = 0;
    this.earningHeadsList.controls.forEach(control => {
      total += Number(control.value.amount) || 0;
    });
    return total;
  }

  restrictInputDecimal(event: KeyboardEvent) {
    const pattern = /^[0-9.]$/;
    const inputChar = event.key;
    if (!pattern.test(inputChar)) {
      event.preventDefault();
    }
  }

  onSubmit(): void {
    this.submitted = true;
    if (this.rateCardForm.invalid) {
      this.showError = true;
      this.toastrService.error('Please fill all required fields', 'Validation Error');
      return;
    }

    const formVal = this.rateCardForm.value;
    const details = this.earningHeads.controls.map(control => {
      return {
        HeadId: control.value.fk_headid,
        Amount: Number(control.value.amount)
      };
    });

    const payload = {
      RateCardId: this.Isedit ? Number(this.rateCardId) : 0,
      CustomerId: formVal.CustomerId,
      LocationId: formVal.LocationId,
      ServiceTypeId: Number(formVal.ServiceTypeId),
      CategoryId: formVal.CategoryId,
      WorkDuration: formVal.WorkDuration ? formVal.WorkDuration.toString() : '',
      Details: details
    };

    if (this.Isedit) {
      this.rateCardService.update(payload).subscribe({
        next: (res) => {
          if (res?.isSuccess) {
            this.toastrService.success('Rate Card updated successfully!', 'Success');
            this.router.navigateByUrl("/dash/user/userdashboard/customerRateCard_list"); // Adjust list route if created later
          } else {
            this.toastrService.error(res?.message || 'Update Failed', 'Error');
          }
        },
        error: (err) => this.toastrService.error('Error updating rate card')
      });
    } else {
      this.rateCardService.insert(payload).subscribe({
        next: (res) => {
          if (res?.isSuccess) {
            this.toastrService.success('Rate Card created successfully!', 'Success');
            this.rateCardForm.reset();
            this.earningHeads.clear();
            this.submitted = false;
            this.showError = false;
          } else {
            this.toastrService.error(res?.message || 'Insert Failed', 'Error');
          }
        },
        error: (err) => this.toastrService.error('Error creating rate card')
      });
    }
  }

  loadRateCardData(id: number) {
    this.rateCardService.getById(id).subscribe({
      next: (res) => {
        if (res.isSuccess && res.data) {
          const data = res.data;
          this.rateCardForm.patchValue({
            CustomerId: data.customerId?.toString(),
            LocationId: data.locationId?.toString(),
            ServiceTypeId: data.serviceTypeId,
            CategoryId: data.categoryId?.toString(),
            WorkDuration: data.workDuration ? data.workDuration.toString() : ''
          });

          this.earningHeads.clear();
          (data.details || []).forEach((item: any) => {
            const group = this.fb.group({
              fk_headid: item.headId,
              shortDesc: item.headName || 'Head',
              amount: [item.amount, Validators.required]
            });
            this.earningHeads.push(group);
          });
        }
      }
    });
  }

  clearForm(): void {
    this.rateCardForm.reset();
    this.earningHeads.clear();
    this.submitted = false;
    this.showError = false;
  }
}
