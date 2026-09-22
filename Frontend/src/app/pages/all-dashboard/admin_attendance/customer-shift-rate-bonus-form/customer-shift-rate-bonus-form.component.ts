import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router, ActivatedRoute, RouterLink } from '@angular/router';
import { ToastrService } from 'ngx-toastr';
import { NgSelectModule } from '@ng-select/ng-select';
import { CustomerShiftRateBonusService } from '../service/customer-shift-rate-bonus.service';

@Component({
  selector: 'app-customer-shift-rate-bonus-form',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink, NgSelectModule],
  templateUrl: './customer-shift-rate-bonus-form.component.html',
  styleUrls: ['./customer-shift-rate-bonus-form.component.scss']
})
export class CustomerShiftRateBonusFormComponent implements OnInit {
  isEditMode: boolean = false;
  editId: number = 0;
  isLoading: boolean = false;
  isSaving: boolean = false;

  // Dropdown data
  clients: any[] = [];
  locations: any[] = [];

  // Payout type options
  payoutTypeOptions = [
    { label: 'Monthly', value: 'Monthly' },
    { label: 'Yearly', value: 'Yearly' }
  ];

  // Form model
  formData: any = {
    pk_id: 0,
    fk_clientId: null,
    fk_locId: null,
    shiftTypeA: null,
    shiftTypeB: null,
    shiftTypeC: null,
    attendanceBonus: null,
    isBonusApplicable: false,
    bonusPayoutType: null,
    attendanceApplicableDays: null,
    isActive: true
  };

  constructor(
    private service: CustomerShiftRateBonusService,
    private toastr: ToastrService,
    private router: Router,
    private route: ActivatedRoute
  ) { }

  ngOnInit(): void {
    this.loadDropdowns();

    this.route.params.subscribe(params => {
      if (params['id']) {
        this.editId = +params['id'];
        this.isEditMode = true;
        this.loadRecordForEdit(this.editId);
      }
    });
  }

  goBack(): void {
    this.router.navigate(['/dash/adminAttendance/adminAttendancedashboard/customer_shift_rate_bonus_list']);
  }

  loadDropdowns(): void {
    // 1. Clients (Company-wise from General/dropdownList/Client)
    this.service.getClients().subscribe({
      next: (res: any) => {
        const list = res?.data ?? res?.Data ?? (Array.isArray(res) ? res : []);
        this.clients = list
          .filter((c: any) => c.value != null && c.value !== '' && c.value !== 'null')
          .map((c: any) => ({
            value: (c.value ?? c.Value ?? '').toString(),
            text: c.name ?? c.Name ?? c.text ?? c.Text ?? c.value
          }));
      },
      error: (err: any) => console.error('Error fetching clients dropdown:', err)
    });

    // 2. Locations (Company-wise from General/dropdownList/Location)
    this.service.getLocations().subscribe({
      next: (res: any) => {
        const list = res?.data ?? res?.Data ?? (Array.isArray(res) ? res : []);
        this.locations = list
          .filter((l: any) => l.value != null && l.value !== '' && l.value !== 'null')
          .map((l: any) => ({
            value: (l.value ?? l.Value ?? '').toString(),
            text: l.name ?? l.Name ?? l.text ?? l.Text ?? l.locname ?? l.value
          }));
      },
      error: (err: any) => console.error('Error fetching locations dropdown:', err)
    });
  }

  onBonusApplicableChange(): void {
    if (!this.formData.isBonusApplicable) {
      this.formData.bonusPayoutType = null;
    }
  }

  loadRecordForEdit(id: number): void {
    this.isLoading = true;
    this.service.getById(id).subscribe({
      next: (res: any) => {
        this.isLoading = false;
        const data = res?.data ?? res?.Data ?? res;
        if (data) {
          this.formData = {
            pk_id: data.pk_id,
            fk_clientId: data.fk_clientId ? data.fk_clientId.toString() : null,
            fk_locId: data.fk_locId ? data.fk_locId.toString() : null,
            shiftTypeA: data.shiftTypeA != null ? data.shiftTypeA : 0,
            shiftTypeB: data.shiftTypeB != null ? data.shiftTypeB : 0,
            shiftTypeC: data.shiftTypeC != null ? data.shiftTypeC : 0,
            attendanceBonus: data.attendanceBonus != null ? data.attendanceBonus : 0,
            isBonusApplicable: !!data.isBonusApplicable,
            bonusPayoutType: data.bonusPayoutType || null,
            attendanceApplicableDays: data.attendanceApplicableDays != null
              ? data.attendanceApplicableDays
              : (data.AttendanceApplicableDays != null ? data.AttendanceApplicableDays : null),
            isActive: data.isActive !== false
          };
        }
      },
      error: (err: any) => {
        this.isLoading = false;
        this.toastr.error('Failed to load record details.');
        console.error('Error loading record:', err);
      }
    });
  }

  validateForm(): boolean {
    if (!this.formData.fk_clientId) {
      this.toastr.warning('Please select a Customer.');
      return false;
    }
    if (!this.formData.fk_locId) {
      this.toastr.warning('Please select a Location.');
      return false;
    }
    if (this.formData.shiftTypeA == null || this.formData.shiftTypeA === '' || isNaN(this.formData.shiftTypeA)) {
      this.toastr.warning('Please enter a valid numeric value for Shift Type A.');
      return false;
    }
    if (this.formData.shiftTypeB == null || this.formData.shiftTypeB === '' || isNaN(this.formData.shiftTypeB)) {
      this.toastr.warning('Please enter a valid numeric value for Shift Type B.');
      return false;
    }
    if (this.formData.shiftTypeC == null || this.formData.shiftTypeC === '' || isNaN(this.formData.shiftTypeC)) {
      this.toastr.warning('Please enter a valid numeric value for Shift Type C.');
      return false;
    }
    if (this.formData.attendanceBonus == null || this.formData.attendanceBonus === '' || isNaN(this.formData.attendanceBonus)) {
      this.toastr.warning('Please enter a valid numeric value for Attendance Bonus.');
      return false;
    }
    if (this.formData.isBonusApplicable && !this.formData.bonusPayoutType) {
      this.toastr.warning('Please select a Bonus Payout Type (Monthly/Yearly).');
      return false;
    }
    return true;
  }

  onSave(): void {
    if (!this.validateForm()) return;

    this.isSaving = true;

    const payload = {
      pk_id: this.isEditMode ? this.editId : 0,
      fk_clientId: this.formData.fk_clientId,
      fk_locId: this.formData.fk_locId,
      shiftTypeA: Number(this.formData.shiftTypeA),
      shiftTypeB: Number(this.formData.shiftTypeB),
      shiftTypeC: Number(this.formData.shiftTypeC),
      attendanceBonus: Number(this.formData.attendanceBonus),
      isBonusApplicable: !!this.formData.isBonusApplicable,
      bonusPayoutType: this.formData.isBonusApplicable ? this.formData.bonusPayoutType : null,
      attendanceApplicableDays: Number(this.formData.attendanceApplicableDays || 0),
      isActive: true
    };

    const request$ = this.isEditMode
      ? this.service.update(payload)
      : this.service.insert(payload);

    request$.subscribe({
      next: (res: any) => {
        this.isSaving = false;
        if (res?.isSuccess || res?.IsSuccess || res?.statusCode === 200) {
          this.toastr.success(res?.message || (this.isEditMode ? 'Updated successfully!' : 'Saved successfully!'));
          this.router.navigate(['/dash/adminAttendance/adminAttendancedashboard/customer_shift_rate_bonus_list']);
        } else {
          this.toastr.error(res?.message || 'Operation failed. Please try again.');
        }
      },
      error: (err: any) => {
        this.isSaving = false;
        const msg = err?.error?.message || err?.message || 'Server error occurred.';
        this.toastr.error(msg);
        console.error('Error saving record:', err);
      }
    });
  }

  resetForm(): void {
    this.formData = {
      pk_id: this.isEditMode ? this.editId : 0,
      fk_clientId: null,
      fk_locId: null,
      shiftTypeA: null,
      shiftTypeB: null,
      shiftTypeC: null,
      attendanceBonus: null,
      isBonusApplicable: false,
      bonusPayoutType: null,
      attendanceApplicableDays: null,
      isActive: true
    };
  }

  onCancel(): void {
    this.goBack();
  }
}
