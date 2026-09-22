import { CommonModule } from '@angular/common';
import { Component, inject } from '@angular/core';
import { FormBuilder, FormGroup, FormsModule, ReactiveFormsModule, Validators } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { NgSelectComponent, NgSelectModule } from '@ng-select/ng-select';
import { NgxPaginationModule } from 'ngx-pagination';
import { ToastrService } from 'ngx-toastr';
import { NgxUiLoaderService } from 'ngx-ui-loader';
import { EncryptionService } from '../../../../../shared/services/encryption.service';
import { ClientMasterService } from '../../services/client-master.service';
import { FormArray } from '@angular/forms';
@Component({
  selector: 'app-client-master',
  standalone: true,
  imports: [FormsModule, RouterLink, ReactiveFormsModule, CommonModule, NgxPaginationModule, NgSelectModule],
  templateUrl: './client-master.component.html',
  styleUrl: './client-master.component.scss'
})
export class ClientMasterComponent {
  ClientForm!: FormGroup;
  submited = false;
  Isedit = false;
  pk_cost_centre_id: any = 0;

  ZoneList: { name: string; value: string }[] = [];
  CityList: { name: string; value: string }[] = [];
  StateList: { name: string; value: string }[] = [];
  ServiceTypeList: { name: string; value: string }[] = [];
  LeavePolicyList: { name: string; value: string }[] = [];

  ClientCodeList: { name: string; value: string }[] = [];


  // added new for chnage ui

  ExtraDayStatus: string = '';
  DayConsider: string | null = null;

  ExtraDayList: any[] = [];

  ExtraDayEditIndex: number = -1;
  IsExtraDayEdit: boolean = false;
  modelList: any[] = [];
  DayConsiderList = [
    { name: 'Half Day', value: 'H' },
    { name: 'Full Day', value: 'F' }
  ];


  //




  editIndex: number = -1;



  ngxUILoaderService = inject(NgxUiLoaderService);

  constructor(
    private fb: FormBuilder,
    private clientMasterService: ClientMasterService,
    private toastrService: ToastrService,
    private router: Router,
    public encryption: EncryptionService,
    private route: ActivatedRoute,

  ) { }

  ngOnInit(): void {
    this.ClientForm = this.fb.group({
      ClientCode: ['', [Validators.required]],
      ClientName: ['', [Validators.required]],
      EmpCodePrefix: [''],
      Grouping: [''],
      ContactPerson: [''],
      EmailID: [''],
      CINNo: [''],
      TAN: [''],
      GST: [''],
      gst_state: [null],
      PAN: [''],
      Address: [''],
      fk_cityId: [null],
      fk_stateId: [null],
      fk_zoneId: [null],
      Pincode: [''],
      Phone: ['', [Validators.pattern('^[0-9]{10}$')]],
      StartDate: [null],
      EndDate: [null],
      LeavePolicy: [null],
      CommissionPercent: [0],
      ServiceTypeIds: [[]],
      ModelTypeIds: [[]],
      gst_rate: [0],


      //added new..

      // NEW
      ExtraDayDetails: this.fb.array([]) // ADD THIS
    });



    this.getZone();
    this.getState();
    this.getCity();
    this.ServiceTypeDDL();
    this.ClientCodeTypeDDL();
    this.loadModelTypes();
    this.getLeavePolicy();
    this.addExtraDay();

    const encryptedId = this.route.snapshot.paramMap.get('pk_cost_centre_id');

    debugger
    if (encryptedId) {
      this.pk_cost_centre_id = this.encryption.decryptText(encryptedId);
      this.Isedit = true;
      this.patchFormForEdit(this.pk_cost_centre_id);
    }
  }
  get ExtraDayDetails(): FormArray {
    return this.ClientForm.get('ExtraDayDetails') as FormArray;
  }

  private loadModelTypes(): void {
    this.clientMasterService.GetDdlListBasedOnCodeType(4).subscribe({
      next: (res: any) => {
        if (res?.isSuccess && res.data) {
          this.modelList = res.data;
        }
      }
    });
  }
  onSubmit() {
    if (this.ClientForm.invalid) {
      this.submited = true;
      this.toastrService.error("Please fill all required fields correctly.");
      return;
    }

    const data = {
      ...this.ClientForm.value,
      pk_cost_centre_id: Number(this.pk_cost_centre_id) || 0,
      ExtraDayDetails: this.ExtraDayDetails.value
    };


    if (this.Isedit) {
      this.clientMasterService.update_clientmaster(data).subscribe({
        next: (result) => {
          if (result.isSuccess) {
            this.toastrService.success(result.message || 'Client Master updated successfully!');
            this.router.navigate(['/dash/user/userdashboard/clientMaster_list']);
          } else {
            this.toastrService.error(result.message);
          }
        },
        error: () => {
          this.toastrService.error('An error occurred during form submission');
        }
      });
    } else {
      this.clientMasterService.add_clientmaster(data).subscribe({
        next: (result) => {
          if (result.isSuccess) {
            this.toastrService.success(result.message || 'Client Master added successfully!');
            this.router.navigate(['/dash/user/userdashboard/clientMaster_list']);
          } else {
            this.toastrService.error(result.message);
          }
        },
        error: () => {
          this.toastrService.error('An error occurred during form submission');
        }
      });
    }
  }

  getZone() {
    this.clientMasterService.getDropdownList('Zone').subscribe({
      next: (res) => {
        if (res?.isSuccess && res.data) {
          this.ZoneList = res.data;
        }
      }
    });
  }

  getState() {
    this.clientMasterService.getDropdownList('State').subscribe({
      next: (res) => {
        if (res?.isSuccess && res.data) {
          this.StateList = res.data;
        }
      }
    });
  }

  getCity() {
    this.clientMasterService.getDropdownList('City').subscribe({
      next: (res) => {
        if (res?.isSuccess && res.data) {
          this.CityList = res.data;
        }
      }
    });
  }
  ServiceTypeDDL() {
    this.clientMasterService.GetDdlListBasedOnCodeType(1).subscribe({
      next: (res) => {
        if (res?.isSuccess && res.data) {
          this.ServiceTypeList = res.data;
        }
      }
    });
  }

  ClientCodeTypeDDL() {
    this.clientMasterService.GetDdlListBasedOnCodeType(3).subscribe({
      next: (res) => {
        if (res?.isSuccess && res.data) {
          this.ClientCodeList = res.data;
        }
      }
    });
  }

  onStateChange(event: any) {
    // Client-side filtering can be done here if needed
  }

  getServiceType() {
    this.clientMasterService.getDropdownList('ServiceType').subscribe({
      next: (res) => {
        if (res?.isSuccess && res.data) {
          this.ServiceTypeList = res.data;
        }
      }
    });
  }

  getLeavePolicy() {
    this.clientMasterService.getDropdownList('LeavePolicy').subscribe({
      next: (res) => {
        if (res?.isSuccess && res.data) {
          this.LeavePolicyList = res.data;
        }
      }
    });
  }

  patchFormForEdit(locId: any): void {
    this.ngxUILoaderService.start();
    this.clientMasterService.getById_clientmaster(locId).subscribe({
      next: (res) => {
        if (res?.isSuccess && res.data) {
          const data = res.data;

          this.ClientForm.patchValue({
            ClientCode: data.clientCode,
            ClientName: data.clientName,
            EmpCodePrefix: data.empCodePrefix,
            Grouping: data.grouping,
            ContactPerson: data.contactPerson,
            EmailID: data.emailID,
            CINNo: data.cinNo,
            TAN: data.tan,
            GST: data.gst,
            gst_state: data.gst_state,
            PAN: data.pan,
            Address: data.address,
            fk_cityId: data.fk_cityId,
            fk_stateId: data.fk_stateId,
            fk_zoneId: data.fk_zoneId,
            Pincode: data.pincode,
            gst_rate: data.gst_rate,
            Phone: data.phone,
            StartDate: data.startDate ? data.startDate.split('T')[0] : null,
            EndDate: data.endDate ? data.endDate.split('T')[0] : null,
            LeavePolicy: data.leavePolicy,
            CommissionPercent: data.commissionPercent,
            ServiceTypeIds: data.serviceTypeIds || [],
            ModelTypeIds: data.modelTypeIds || data.modelIds || [],
          });
          // this.ExtraDayList = data.extraDayDetails || [];
          this.ExtraDayDetails.clear();

          if (data.extraDayDetails?.length > 0) {

            data.extraDayDetails.forEach((x: any) => {

              this.ExtraDayDetails.push(
                this.fb.group({
                  extraDayStatus: [x.extraDayStatus],
                  dayConsider: [x.dayConsider]
                })
              );

            });

          }
          else {

            this.addExtraDay();
          }
        }

        this.ngxUILoaderService.stop();
      },
      error: (err) => {
        this.toastrService.error("Error loading details.");
        this.ngxUILoaderService.stop();
      }
    });
  }

  checkCodeAvailability(code: string): void {
    if (!code) return;
    this.clientMasterService.CheckDuplicateValue('ClientCode', code, this.pk_cost_centre_id).subscribe({
      next: (response) => {
        if (response && response.isSuccess === false) {
          this.ClientForm.get('ClientCode')?.setErrors({ duplicate: response.message });
        } else {
          this.ClientForm.get('ClientCode')?.setErrors(null);
        }
      }
    });
  }


  checkNameAvailability(code: string): void {
    if (!code) return;
    this.clientMasterService.CheckDuplicateValue('ClientName', code, this.pk_cost_centre_id).subscribe({
      next: (response) => {
        if (response && response.isSuccess === false) {
          this.ClientForm.get('ClientName')?.setErrors({ duplicate: response.message });
        } else {
          this.ClientForm.get('ClientName')?.setErrors(null);
        }
      }
    });
  }

  //added new



  addExtraDay() {

    const lastIndex = this.ExtraDayDetails.length - 1;

    // check only when already one row exists
    if (lastIndex >= 0) {

      const lastRow = this.ExtraDayDetails.at(lastIndex);

      const extraDayStatus = lastRow.get('extraDayStatus')?.value;
      const dayConsider = lastRow.get('dayConsider')?.value;

      // stop adding new row if current row empty
      if (!extraDayStatus || !dayConsider) {

        this.toastrService.error('Please fill Extra Day Status and Day Consider');

        return;
      }
    }


    this.ExtraDayDetails.push(
      this.fb.group({
        extraDayStatus: [''],
        dayConsider: [null]
      })
    );
  }
  removeExtraDay(index: number) {

    this.ExtraDayDetails.removeAt(index);
  }
}
