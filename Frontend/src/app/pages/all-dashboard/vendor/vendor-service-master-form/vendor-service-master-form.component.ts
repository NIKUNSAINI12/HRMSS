import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router, ActivatedRoute, RouterLink } from '@angular/router';
import { ToastrService } from 'ngx-toastr';
import { NgSelectModule } from '@ng-select/ng-select';
import { VendorServiceMasterService } from '../Service/vendor-service-master.service';

@Component({
  selector: 'app-vendor-service-master-form',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink, NgSelectModule],
  templateUrl: './vendor-service-master-form.component.html',
  styleUrls: ['./vendor-service-master-form.component.scss']
})
export class VendorServiceMasterFormComponent implements OnInit {
  isEditMode: boolean = false;
  editId: number = 0;
  isLoading: boolean = false;
  isSaving: boolean = false;

  // Dropdown data sources
  vendors: any[] = [];
  locations: any[] = [];
  clients: any[] = [];

  // Service Type options (from General Master CodeType 9)
  serviceTypes: { label: string, value: string }[] = [];

  // Percentage of options (from General Master CodeType 10)
  percentageOfOptions: { label: string, value: string }[] = [];

  // Form model
  formData: any = {
    vendorID: '',
    locationID: '',
    clientID: '',
    serviceType: 'Flat',
    percentageType: '',
    serviceCharge: 0,
    isGratuity: false
  };

  constructor(
    private vendorServiceMaster: VendorServiceMasterService,
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
    this.router.navigate(['/dash/vendor_management/vendor_managementdashboard/vendor_service_master_list']);
  }

  loadDropdowns(): void {
    const compId = sessionStorage.getItem('companyId') || '';

    // 1. Vendors (from General/dropdownList/Vendor)
    this.vendorServiceMaster.getVendors().subscribe({
      next: (res: any) => {
        const list = res?.data ?? res?.Data ?? (Array.isArray(res) ? res : []);
        this.vendors = list
          .filter((v: any) => v.value != null && v.value !== '' && v.value !== 'null')
          .map((v: any) => ({
            value: (v.value ?? v.Value ?? '').toString(),
            text: v.name ?? v.Name ?? v.text ?? v.Text ?? v.value
          }));
      },
      error: (err) => console.error('Error fetching vendors dropdown:', err)
    });

    // 2. Locations (from General/dropdownList/Location)
    this.vendorServiceMaster.getLocations().subscribe({
      next: (res: any) => {
        const list = res?.data ?? res?.Data ?? (Array.isArray(res) ? res : []);
        this.locations = list
          .filter((l: any) => l.value != null && l.value !== '' && l.value !== 'null')
          .map((l: any) => ({
            value: (l.value ?? l.Value ?? '').toString(),
            text: l.name ?? l.Name ?? l.text ?? l.Text ?? l.locname ?? l.value
          }));
      },
      error: (err) => console.error('Error fetching locations dropdown:', err)
    });

    // 3. Clients (from General/dropdownList/Client)
    this.vendorServiceMaster.getClients().subscribe({
      next: (res: any) => {
        const list = res?.data ?? res?.Data ?? (Array.isArray(res) ? res : []);
        this.clients = list
          .filter((c: any) => c.value != null && c.value !== '' && c.value !== 'null')
          .map((c: any) => ({
            value: (c.value ?? c.Value ?? '').toString(),
            text: c.name ?? c.Name ?? c.text ?? c.Text ?? c.value
          }));
      },
      error: (err) => console.error('Error fetching clients dropdown:', err)
    });

    // 4. Service Types (from General Master CodeType 11)
    this.vendorServiceMaster.getDdlListBasedOnCodeType('11', compId).subscribe({
      next: (res: any) => {
        const list = res?.data ?? res?.Data ?? res?.list ?? res?.List ?? (Array.isArray(res) ? res : []);
        this.serviceTypes = list.map((item: any) => {
          let label = item.name ?? item.Name ?? item.text ?? item.Text ?? item.codeDescription ?? '';
          if (label.includes(':')) label = label.split(':')[1];
          return { label: label.trim(), value: label.trim() };
        });
      },
      error: (err) => console.error('Error fetching service types from general master:', err)
    });

    // 5. Percentage Types (from General Master CodeType 12)
    this.vendorServiceMaster.getDdlListBasedOnCodeType('12', compId).subscribe({
      next: (res: any) => {
        const list = res?.data ?? res?.Data ?? res?.list ?? res?.List ?? (Array.isArray(res) ? res : []);
        this.percentageOfOptions = list.map((item: any) => {
          let label = item.name ?? item.Name ?? item.text ?? item.Text ?? item.codeDescription ?? '';
          if (label.includes(':')) label = label.split(':')[1];
          return { label: label.trim(), value: label.trim() };
        });
      },
      error: (err) => console.error('Error fetching percentage types from general master:', err)
    });
  }

  loadRecordForEdit(id: number): void {
    this.isLoading = true;
    this.vendorServiceMaster.getById(id).subscribe({
      next: (res) => {
        this.isLoading = false;
        if (res?.isSuccess && res?.data) {
          const d = res.data;
          const vId = d.vendorID ?? d.VendorID ?? '';
          const lId = d.locationID ?? d.LocationID ?? '';
          const cId = d.clientID ?? d.ClientID ?? '';
          const sType = d.serviceType ?? d.ServiceType ?? 'Flat';
          const pType = d.percentageType ?? d.PercentageType ?? '';
          const sCharge = d.serviceCharge ?? d.ServiceCharge ?? 0;
          const isGrat = d.isGratuity ?? d.IsGratuity ?? false;
          const pkId = d.pK_VendorServiceID ?? d.pk_VendorServiceID ?? d.PK_VendorServiceID ?? id;

          this.formData = {
            pk_VendorServiceID: pkId,
            vendorID: vId.toString(),
            locationID: lId.toString(),
            clientID: cId.toString(),
            serviceType: sType === 'Percentage' ? 'Percentage' : 'Flat',
            percentageType: pType,
            serviceCharge: sCharge,
            isGratuity: isGrat === true || isGrat === 1 || isGrat === 'true' || isGrat === '1'
          };
        } else {
          this.toastr.error(res?.message || 'Failed to load record details.');
        }
      },
      error: (err) => {
        this.isLoading = false;
        console.error('Error loading vendor service:', err);
        this.toastr.error('Error loading record.');
      }
    });
  }

  onServiceTypeChange(): void {
    if (this.formData.serviceType !== 'Percentage') {
      this.formData.percentageType = '';
    } else {
      if (!this.formData.percentageType) {
        this.formData.percentageType = 'CTC';
      }
    }
  }

  onSave(): void {
    // Validations
    if (!this.formData.vendorID) {
      this.toastr.warning('Please select a Vendor.');
      return;
    }
    if (!this.formData.locationID) {
      this.toastr.warning('Please select a Location.');
      return;
    }
    if (!this.formData.clientID) {
      this.toastr.warning('Please select a Client.');
      return;
    }
    if (!this.formData.serviceType) {
      this.toastr.warning('Please select a Service Type.');
      return;
    }
    if (this.formData.serviceType === 'Percentage' && !this.formData.percentageType) {
      this.toastr.warning('Please select Percentage of (CTC / Gross).');
      return;
    }
    if (this.formData.serviceCharge == null || this.formData.serviceCharge < 0) {
      this.toastr.warning('Please enter a valid Service Charge.');
      return;
    }

    this.isSaving = true;

    if (this.isEditMode) {
      this.vendorServiceMaster.update(this.formData).subscribe({
        next: (res) => {
          this.isSaving = false;
          if (res?.isSuccess) {
            this.toastr.success(res.message || 'Vendor service updated successfully.');
            this.router.navigate(['/dash/vendor_management/vendor_managementdashboard/vendor_service_master_list']);
          } else {
            this.toastr.error(res?.message || 'Failed to update vendor service.');
          }
        },
        error: (err) => {
          this.isSaving = false;
          console.error(err);
          this.toastr.error('Error updating vendor service.');
        }
      });
    } else {
      this.vendorServiceMaster.insert(this.formData).subscribe({
        next: (res) => {
          this.isSaving = false;
          if (res?.isSuccess) {
            this.toastr.success(res.message || 'Vendor service created successfully.');
            this.router.navigate(['/dash/vendor_management/vendor_managementdashboard/vendor_service_master_list']);
          } else {
            this.toastr.error(res?.message || 'Failed to add vendor service.');
          }
        },
        error: (err) => {
          this.isSaving = false;
          console.error(err);
          this.toastr.error('Error adding vendor service.');
        }
      });
    }
  }

  onCancel(): void {
    this.router.navigate(['/dash/vendor_management/vendor_managementdashboard/vendor_service_master_list']);
  }
}
