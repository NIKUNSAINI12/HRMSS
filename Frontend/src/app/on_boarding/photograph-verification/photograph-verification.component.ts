import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormBuilder, FormGroup, ReactiveFormsModule, Validators } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { ToastrService } from 'ngx-toastr';
import { NgxUiLoaderService } from 'ngx-ui-loader';
import { CandidateExperienceDetailService } from '../services/candidate-experience-details.service';
import { CompanyConfigService, CompanyConfig } from '../services/company-config.service';

@Component({
  selector: 'app-photograph-verification',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule],
  templateUrl: './photograph-verification.component.html',
  styleUrl: './photograph-verification.component.scss'
})
export class PhotographVerificationComponent implements OnInit {
  photoForm!: FormGroup;
  submitted = false;
  isViewMode = false;
  photoData: any = null;
  previewPhoto: string | null = null;
  originalPhotoUrl: string | null = null;
  fileName: string = '';
  pk_recId: string = '';

  companyConfig: CompanyConfig | null = null;
  isPhotoMandatory: boolean = false;

  constructor(
    private fb: FormBuilder,
    private toastr: ToastrService,
    private router: Router,
    private route: ActivatedRoute,
    private loader: NgxUiLoaderService,
    private kycService: CandidateExperienceDetailService,
    private companyConfigService: CompanyConfigService
  ) {}

  ngOnInit(): void {
    this.pk_recId = sessionStorage.getItem('candidateKey') || '';
    this.initializeForm();
    this.loadCompanyConfig();
    this.loadPhotoDetails();
  }

  initializeForm(): void {
    this.photoForm = this.fb.group({
      PhotoFile: ['', Validators.required]
    });
  }

  get validate() {
    return this.photoForm.controls;
  }

  loadCompanyConfig(): void {
    this.companyConfig = this.companyConfigService.getConfig();
    if (this.companyConfig) {
      this.isPhotoMandatory = this.companyConfig.photographMandatory;
    } else {
      this.kycService.getMandatoryDetails().subscribe({
        next: (res) => {
          if (res.isSuccess && res.data) {
            this.companyConfig = res.data;
            this.companyConfigService.setConfig(res.data);
            this.isPhotoMandatory = res.data.photographMandatory;
          }
        }
      });
    }
  }

  loadPhotoDetails(): void {
    this.kycService.Get_Photograph_ById().subscribe({
      next: (res) => {
        if (!res.isSuccess || !res.data || !res.data.photo) {
          this.isViewMode = false;
          return;
        }

        this.photoData = res.data;
        this.isViewMode = true;
        this.loadImageToView(res.data.photo);
        this.photoForm.get('PhotoFile')?.clearValidators();
        this.photoForm.get('PhotoFile')?.updateValueAndValidity();
      },
      error: () => {
        this.isViewMode = false;
      }
    });
  }

  loadImageToView(filename: string): void {
    this.kycService.getImageOnboard(filename).subscribe({
      next: (blob) => {
        const reader = new FileReader();
        reader.onload = () => {
          this.originalPhotoUrl = reader.result as string;
          this.photoData.photo = this.originalPhotoUrl;
        };
        reader.readAsDataURL(blob);
      }
    });
  }

  onFileSelected(event: any): void {
    const file = event.target.files[0];
    if (!file) return;

    const allowedTypes = ['image/jpeg', 'image/jpg', 'image/png'];
    if (!allowedTypes.includes(file.type)) {
      this.toastr.error('Only JPG or PNG images are allowed for photograph', 'Error');
      return;
    }

    if (file.size > 5 * 1024 * 1024) {
      this.toastr.error('File size cannot exceed 5MB', 'Error');
      return;
    }

    this.photoForm.patchValue({ PhotoFile: file });
    this.fileName = file.name;

    const reader = new FileReader();
    reader.onload = () => {
      this.previewPhoto = reader.result as string;
    };
    reader.readAsDataURL(file);
  }

  editPhoto(): void {
    this.isViewMode = false;
    this.photoForm.get('PhotoFile')?.clearValidators();
    this.photoForm.get('PhotoFile')?.updateValueAndValidity();
  }

  onSubmit(): void {
    this.submitted = true;

    const file = this.photoForm.get('PhotoFile')?.value;
    if (!file && !this.photoData?.photo) {
      this.toastr.error('Please upload your photograph.', 'Validation Error');
      return;
    }

    const fd = new FormData();
    fd.append('pk_recId', this.pk_recId);

    if (file && typeof file !== 'string') {
      fd.append('PhotoFile', file);
    }

    this.loader.start();
    this.kycService.verifyPhotograph(fd).subscribe({
      next: (res) => {
        this.loader.stop();
        if (res.isSuccess) {
          this.toastr.success(res.message || 'Photograph saved successfully.', 'Success');
          this.loadPhotoDetails();
          this.isViewMode = true;
          window.dispatchEvent(new Event('refresh-onboarding-status'));
        } else {
          this.toastr.error(res.message || 'Failed to save photograph.', 'Error');
        }
      },
      error: () => {
        this.loader.stop();
        this.toastr.error('An error occurred while saving photograph.', 'Error');
      }
    });
  }

  reset(): void {
    this.photoForm.reset();
    this.submitted = false;
    this.fileName = '';
    this.previewPhoto = null;
  }
}
