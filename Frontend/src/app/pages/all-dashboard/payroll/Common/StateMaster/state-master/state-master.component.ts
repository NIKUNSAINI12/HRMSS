import { Component, inject } from '@angular/core';
import { FormBuilder, FormGroup, ReactiveFormsModule, Validators } from '@angular/forms';
import { ActivatedRoute, Router, } from '@angular/router';
import { StateService } from '../../../services/state.service';
import { ToastrService } from 'ngx-toastr';
import { CommonModule } from '@angular/common';
import { EncryptionService } from '../../../../../../shared/services/encryption.service';

@Component({
  selector: 'app-state-master',
  standalone: true,
  imports: [ReactiveFormsModule, CommonModule],
  templateUrl: './state-master.component.html',
  styleUrl: './state-master.component.scss'
})
export class StateMasterComponent {
  StatemasterForm!: FormGroup;
  submitted = false;
  showError = false;
  stateId: string = '';
  isEditMode: boolean = false;
  route = inject(ActivatedRoute);

  constructor(
    private fb: FormBuilder,
    private stateService: StateService,
    private toastrService: ToastrService,
    private router: Router,
    public encryptionService: EncryptionService
  ) { }
  ngOnInit(): void {
    this.StatemasterForm = this.fb.group({
      description: ['', [Validators.required, Validators.maxLength(150)]],
      lwf_applicable: [false],
      pt_applicable: [false],
      pt_number: [''],
      lwf_number: [''],
      esi_number: [''],
      pf_number: [''],
      minimum_wages: [0]

    });


    this.StatemasterForm.get('description')?.valueChanges.subscribe(value => {
      if (value) {
        this.checkOperationalAvailability(value);
      }
    });
    this.route.paramMap.subscribe(params => {
      const id = params.get('pk_stateid');
      if (id) {
        this.stateId = this.encryptionService.decryptText(id.toString());
        this.isEditMode = true;
        this.getStateById(this.stateId);
      }
    });


  }

  checkOperationalAvailability(description: string): void {
    const fieldName = 'State';
    const fieldValue = description;
    const generalId = this.stateId || '';

    this.stateService.checkDuplicateValue(fieldName, fieldValue, generalId).subscribe({
      next: (response) => {
        if (response && response.isSuccess === false) {
          this.StatemasterForm.get('description')?.setErrors({ duplicate: response.message });
        } else {
          this.StatemasterForm.get('description')?.setErrors(null);
        }
      },
      error: (err) => {
        console.error('Duplicate Check API Error:', err);
        this.StatemasterForm.get('OperationalDescription')?.setErrors({ duplicate: 'Error checking availability.' });
      }
    });
  }


  getStateById(id: string) {
    this.stateService.getStateById(id).subscribe(
      (response) => {
        if (response.isSuccess && response.data) {
          this.StatemasterForm.patchValue({
            description: response.data.description,
            lwf_applicable: response.data.lwf_applicable,
            pt_applicable: response.data.pt_applicable,
            pt_number: response.data.pt_number,
            lwf_number: response.data.lwf_number,
            esi_number: response.data.lwf_number,
            pf_number: response.data.lwf_number,
            minimum_wages: response.data.minimum_wages
          });
        } else {
          console.error('Failed to fetch State:', response.message);
          this.toastrService.error(response.message || 'Failed to load state data');
        }
      },
      (error) => {
        console.error('Error fetching State:', error);
        this.toastrService.error('Error loading state data');
      }
    );
  }

  onSubmit(): void {
    this.submitted = true;
    if (this.StatemasterForm.invalid) {
      this.showError = true;
      return;
    }
    const formData = this.StatemasterForm.value;
    if (this.isEditMode && this.stateId) {
      this.stateService.updateState({ pk_stateid: this.stateId, ...formData }).subscribe(
        response => {
          if (response.isSuccess) {
            this.toastrService.success(response.message || 'State updated successfully!');
            this.view();
          } else {
            this.toastrService.error(response.message || 'Failed to update state');
          }
        },
        error => {
          console.error('Error updating state:', error);
          this.toastrService.error('Error updating state data');
        }
      );
    } else {
      this.stateService.addStateMaster(formData).subscribe(
        response => {
          if (response.isSuccess) {
            this.toastrService.success(response.message || 'State created successfully!');
            this.view();
          } else {
            this.toastrService.error(response.message || 'Failed to create state');
          }
        },
        error => {
          console.error('Error creating state:', error);
          this.toastrService.error('Error saving state data');
        }
      );
    }
  }

  view(): void {
    this.router.navigateByUrl("/dash/user/userdashboard/StateMaster_list");
  }

  resetForm(): void {
    this.StatemasterForm.reset({
      description: '',
      lwf_applicable: false,
      pt_applicable: false,
      pt_number: '',
      lwf_number: '',
      esi_number: '',
      pf_number: '',
      minimum_wages: 0
    });
    this.showError = false;
    this.submitted = false;
  }
}
