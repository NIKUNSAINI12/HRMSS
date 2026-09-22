import { Component, ElementRef, OnInit, ViewChild, NgZone, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormBuilder, FormGroup, FormsModule, ReactiveFormsModule, Validators } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { ToastrService } from 'ngx-toastr';
import { NgxMaskDirective } from 'ngx-mask';
import { NgSelectModule } from '@ng-select/ng-select';

import { NgxUiLoaderService } from 'ngx-ui-loader';
import { KycService } from '../../pages/setting/service/kyc.service';
import { CandidateMasterService } from '../../pages/all-dashboard/recruitment/RecruitServices/candidate-master.service';
import { CandidateExperienceDetailService } from '../services/candidate-experience-details.service';
import { CompanyConfigService, CompanyConfig } from '../services/company-config.service';
import Tesseract from 'tesseract.js';

declare var bootstrap: any;

@Component({
  selector: 'app-aadhar-verification',
  standalone: true,
  imports: [CommonModule, FormsModule, ReactiveFormsModule, NgxMaskDirective, NgSelectModule],
  templateUrl: './aadhar-verification.component.html',
  styleUrl: './aadhar-verification.component.scss'
})
export class AadharVerificationComponent implements OnInit {
  @ViewChild('otpModal') otpModal!: ElementRef;
  aadhaarForm!: FormGroup;
  submitted = false;
  userId: string = '';
  fileName: { [key: string]: string } = {};
  IsverifyAddhar=false
  message: string = ''; 
  pk_recId: string = '';      
 isViewMode = false;
 aadhaarData: any;
 imageMap: { [filename: string]: string } = {};  // Stores base64 images
  otp: string[] = ['', '', '', '', '', ''];  // For 6-digit OTP
  // isAadhaarVerified = true
  previewAadhaarFront: string | null = null;
previewAadhaarBack: string | null = null;
previewFatherAadhaarFront: string | null = null;
previewFatherAadhaarBack: string | null = null;

originalAadhaarFrontUrl: string | null = null;
originalAadhaarBackUrl: string | null = null;
isAadhaarDuplicate: boolean = false;
aadhaarDuplicateMessage: string = '';

  // State/City lists
  statList: any[] = [];
  cityList: any[] = [];

  // OCR state properties
  isScanning: boolean = false;
  isScanningPerFile: { [key: string]: boolean } = {};
  ocrError: { [key: string]: string } = {};

     // Company Config Properties
  companyConfig: CompanyConfig | null = null;
  isAadhaarMandatory: boolean = false;
  isAadhaarVerificationRequired: boolean = false;
  previewImageSrc: string = '';
previewImageTitle: string = '';

  constructor(
    private formBuilder: FormBuilder,
    private toastrService: ToastrService,
    private router: Router,
     private kycService: CandidateExperienceDetailService,
    private ngxUILoaderService: NgxUiLoaderService,
    private route: ActivatedRoute,
    private companyConfigService: CompanyConfigService,
    private zone: NgZone,
    private cdr: ChangeDetectorRef
  ) {}
ngOnInit(): void {
  // Load company config first
  this.loadCompanyConfig();

  this.route.queryParams.subscribe(p => {
    this.pk_recId = p['pk_recId'] ?? '';
    this.initializeForm();
    this.loadAadhaarDetails();
  });
}


private validateAadhaarFormat(aadhaarNo: string): boolean {
  if (!aadhaarNo || aadhaarNo.length !== 12) {
    return false;
  }
  const aadhaarRegex = /^\d{12}$/;
  return aadhaarRegex.test(aadhaarNo);
}

checkAadhaarDuplicate(): void {
  let aadhaarNo = this.aadhaarForm.get('AadhaarNo')?.value || '';

  // Remove spaces
  aadhaarNo = aadhaarNo.replace(/\s+/g, '');

  // API call only for valid 12 digit Aadhaar
  if (!this.validateAadhaarFormat(aadhaarNo)) {
    return;
  }

  const existingSavedAadhaar = (this.aadhaarData?.aadhaarNo || '').replace(/\s+/g, '');
  const control = this.aadhaarForm.get('AadhaarNo');

  // If in edit/update mode and user enters their own already-saved Aadhaar
  if (existingSavedAadhaar && aadhaarNo === existingSavedAadhaar) {
    if (control?.hasError('duplicate')) {
      const errors = { ...control.errors };
      delete errors['duplicate'];
      control.setErrors(Object.keys(errors).length > 0 ? errors : null);
    }
    return;
  }

  this.kycService.CheckDuplicate(
    'Aadhaar No',
    aadhaarNo,
    this.pk_recId || undefined
  ).subscribe({
    next: (res: any) => {

      if (!res.isSuccess) {

        control?.setErrors({
          ...(control.errors || {}),
          duplicate: res.message || 'Aadhaar No already exists.'
        });

        this.toastrService.error(
          res.message || 'Aadhaar No already exists.',
          'Duplicate Aadhaar'
        );

      } else {

        if (control?.hasError('duplicate')) {
          const errors = { ...control.errors };
          delete errors['duplicate'];

          control.setErrors(
            Object.keys(errors).length > 0 ? errors : null
          );
        }
      }
    },
    error: () => {
      this.toastrService.error(
        'Unable to check Aadhaar number.',
        'Error'
      );
    }
  });
}
  /**
   * Load company configuration from service or API
   */
  loadCompanyConfig(): void {
    // Try to get from service first
    this.companyConfig = this.companyConfigService.getConfig();
    
    if (!this.companyConfig) {
      // Load from API if not in service
      this.kycService.getMandatoryDetails().subscribe({
        next: (res) => {
          if (res.isSuccess && res.data) {
            this.companyConfig = res.data;
            this.companyConfigService.setConfig(res.data);
            this.updateConfigFlags();
          } else {
            this.useDefaultConfig();
          }
        },
        error: () => {
          this.useDefaultConfig();
        }
      });
    } else {
      this.updateConfigFlags();
    }
  }

  /**
   * Update component flags based on company config
   */
  updateConfigFlags(): void {
    if (this.companyConfig) {
      this.isAadhaarMandatory = this.companyConfig.aadhaarMandatory;
      this.isAadhaarVerificationRequired = this.companyConfig.aadhaarVerification;
    }
  }

  /**
   * Use default config if API fails
   */
  useDefaultConfig(): void {
    this.companyConfig = this.companyConfigService.getDefaultConfig();
    this.updateConfigFlags();
  }



// getMandatoryDetails() {
//   this.kycService.getMandatoryDetails().subscribe({
//     next: (res) => {
//   if(res.isSuccess){
//   this.isAadhaarVerified=  res.data.aadhaarMandatory
//   }
//   else{
//     this.isAadhaarVerified=true
//   }       
//     },
//     error: () => {    
//     }
//   });
// }


  initializeForm(): void {
    this.aadhaarForm = this.formBuilder.group({
     AadhaarNo: ['', [
      Validators.required,
      Validators.minLength(14), // 12 digits + 2 spaces (with mask format)
      Validators.maxLength(14)
    ]],
      AadhaarName: ['', Validators.required],
      AadhaarDob: ['', Validators.required],
      AadhaarAddress: ['', Validators.required],
      StateId: ['', Validators.required],
      CityId: ['', Validators.required],
      AadhaarFrontFile: [null, Validators.required],
      AadhaarBackFile: [null, Validators.required],
      FatherAadhaarFrontFile: [null],
      FatherAadhaarBackFile: [null]
    });
  }

  onStateChange(selectedState: string): void {
    if (!selectedState) {
      this.cityList = [];
      this.aadhaarForm.get('CityId')?.reset();
    } else {
      this.getCity(selectedState);
      this.aadhaarForm.get('CityId')?.reset();
    }
  }

  getStateList(fieldName: string): void {
    this.kycService.getStateList(fieldName).subscribe({
      next: (res) => {
        if (res.isSuccess && res.data) {
          this.statList = res.data.map((state: any) => ({
            name: state.name,
            value: state.value ? state.value.toString() : state.value
          }));
          
          // Map State Name for View Mode
          if (this.aadhaarData && this.aadhaarData.stateId) {
            const foundState = this.statList.find(s => s.value == this.aadhaarData.stateId);
            if (foundState) {
              this.aadhaarData.stateName = foundState.name;
            }
          }
        }
      },
      error: () => {}
    });
  }

  getCity(StateId: string): void {
    this.kycService.getcityByStateId(StateId).subscribe({
      next: (res) => {
        if (res?.isSuccess && res.data?.length) {
          this.cityList = res.data.map((city: any) => ({
            name: city.name,
            value: city.value ? city.value.toString() : city.value
          }));
          
          // Map City Name for View Mode
          if (this.aadhaarData && this.aadhaarData.cityId) {
            const foundCity = this.cityList.find(c => c.value == this.aadhaarData.cityId);
            if (foundCity) {
              this.aadhaarData.cityName = foundCity.name;
            }
          }
        } else {
          this.cityList = [];
        }
      },
      error: () => { this.cityList = []; }
    });
  }

  
editAadhaar(): void {
  this.isViewMode = false;
  const control = this.aadhaarForm.get('AadhaarNo');
  if (control?.hasError('duplicate')) {
    const errors = { ...control.errors };
    delete errors['duplicate'];
    control.setErrors(Object.keys(errors).length > 0 ? errors : null);
  }
}

loadAadhaarDetails() {
  this.kycService.Get_Aadhaar_ById(this.pk_recId).subscribe({
    next: (res) => {
      if (res.isSuccess && res.data) {
        this.aadhaarData = res.data;  // <-- Store data for View Mode
        if (res.data.pk_recId) {
          this.pk_recId = res.data.pk_recId;
        }

        const control = this.aadhaarForm.get('AadhaarNo');
        if (control?.hasError('duplicate')) {
          const errors = { ...control.errors };
          delete errors['duplicate'];
          control.setErrors(Object.keys(errors).length > 0 ? errors : null);
        }

        let formattedAadhaar = res.data.aadhaarNo || '';
        const cleanAadhaar = formattedAadhaar.replace(/\s+/g, '');
        if (cleanAadhaar.length === 12) {
          formattedAadhaar = `${cleanAadhaar.substring(0, 4)} ${cleanAadhaar.substring(4, 8)} ${cleanAadhaar.substring(8, 12)}`;
        }

        this.aadhaarForm.patchValue({
          AadhaarNo: formattedAadhaar,
          AadhaarName: res.data.aadhaarName || '',
          AadhaarDob: res.data.aadhaarDob || '',
          AadhaarAddress: res.data.aadhaarAddress || '',
          StateId: res.data.stateId || '',
          CityId: res.data.cityId || ''
        });

        // Load state/city lists if editing
        if (res.data.stateId) {
          this.getStateList('State');
          this.getCity(res.data.stateId);
        } else {
          this.getStateList('State');
        }

        // Load Father Aadhaar images
        if (res.data.fatherAadhaarFront) {
          this.loadFatherImageToView(res.data.fatherAadhaarFront, 'fatherFront');
        }
        if (res.data.fatherAadhaarBack) {
          this.loadFatherImageToView(res.data.fatherAadhaarBack, 'fatherBack');
        }

        if (res.data.aadhaarFront || res.data.aadhaarBack) {
          if (res.data.aadhaarFront) {
            this.loadImageToView(res.data.aadhaarFront, 'front');
            // File pehle se saved hai — required validator hata do
            this.aadhaarForm.get('AadhaarFrontFile')?.clearValidators();
            this.aadhaarForm.get('AadhaarFrontFile')?.updateValueAndValidity();
          }
          if (res.data.aadhaarBack) {
            this.loadImageToView(res.data.aadhaarBack, 'back');
            // File pehle se saved hai — required validator hata do
            this.aadhaarForm.get('AadhaarBackFile')?.clearValidators();
            this.aadhaarForm.get('AadhaarBackFile')?.updateValueAndValidity();
          }
          this.isViewMode = true;
        } else {
          this.isViewMode = false;
        }
      } else {
        this.isViewMode = false;
        this.getStateList('State');
      }
    },
    error: () => {
      this.isViewMode = false;
      this.getStateList('State');
    }
  });
}


  get validate() {
    return this.aadhaarForm.controls;
  }


   OTPAadhaar() {    
   let aadhaarNo = this.aadhaarForm.get('AadhaarNo')?.value || '';

    aadhaarNo = aadhaarNo?.replace(/\s+/g, '');
    // if (!aadhaarNo || aadhaarNo.trim().length === 0) {
    //   this.toastrService.error('Please enter a valid Aadhaar number!', 'Error');
    //   return;
    // }
  
    // Use validation method
  if (!this.validateAadhaarFormat(aadhaarNo)) {
    this.toastrService.error('Please enter a valid 12-digit Aadhaar number!', 'Error');
    return;
  }


    this.ngxUILoaderService.start()
    
    this.kycService.Verify_Aadhaar(aadhaarNo).subscribe({
      next: (res) => {
        if (res.isSuccess) {
          // Extract client_id from the nested response
          const clientId = res.data?.client_id || 'Unknown Client ID';
          sessionStorage.setItem('client_id', clientId);
         // this.ClientId = clientId; // Store client_id for future use
          this.open_OTP_Modal();
          this.IsverifyAddhar = true;
          this.toastrService.success(res.Message||`OTP sent successfully!`, 'Success');
        }
         else {
          this.IsverifyAddhar = false;
          this.toastrService.error('Please enter Valid Number', 'Error');
        }
        
      },
      error: (error) => {
      
        this.IsverifyAddhar = false;
        this.toastrService.error('An error occurred while verifying Aadhaar. Please try again.', 'Error');
      },
    });
    this.ngxUILoaderService.stop()
  }

    open_OTP_Modal() {
    const modalElement = this.otpModal.nativeElement;
    const modalInstance = new bootstrap.Modal(modalElement, {
      backdrop: 'static', // Keeps modal open until explicitly closed
      keyboard: false,   // Prevents closing with keyboard ESC
    });
    modalInstance.show();
  }
  
  close_OTP_Modal() {
    const modalElement = this.otpModal.nativeElement;
    const modalInstance = bootstrap.Modal.getInstance(modalElement);
    if (modalInstance) {
      modalInstance.hide();
    }
  }
   closeMessage() {
    this.message = ''; 
  }
 
   SubmitOtp() {
    const otp = this.otp.join(''); // Combine digits into a single string
    const client_id = sessionStorage.getItem('client_id') || '';
   
     // Create SendData object for submission
    var SendData = {
      client_id: client_id,
      otp: otp
    };

  
    if (!otp || otp.length !== 6) {
      this.toastrService.error('Please enter a valid 6-digit OTP!', 'Error');
      return;
    }
    // Submit the OTP
    this.kycService.Verify_Aadhaar_Submit_OTP(SendData).subscribe({
      next: (response) => {
        if (response.isSuccess) {
          this.aadhaarForm.patchValue({
            AadhaarName: response.data.full_name,
            AadhaarDob: response.data.dob,
            AadhaarAddress: response.data.address
          });
          this.toastrService.success(response.Message ||'Adhar Verification  Successfully', 'Success');
         this.close_OTP_Modal();
        } else {
          this.toastrService.error(response.Message || 'Please enter valid Otp', 'Error');
        }
      },
      error: () => {
        this.toastrService.error('An error occurred while submitting . Please try again.', 'Error');
      }
    });
    
  }


  


  // Handle file selection
  // onFileSelected(event: Event, fileType: string): void {
  //   const input = event.target as HTMLInputElement;
  //   if (input.files && input.files.length > 0) {
  //     const file = input.files[0];
      
  //     // Validate file type
  //     const allowedTypes = ['image/jpeg', 'image/jpg', 'image/png', 'application/pdf'];
  //     if (!allowedTypes.includes(file.type)) {
  //       this.toastrService.error('Only JPG, PNG, or PDF files are allowed', 'Error');
  //       return;
  //     }

  //     // Validate file size (max 5MB)
  //     if (file.size > 5 * 1024 * 1024) {
  //       this.toastrService.error('File size should not exceed 5MB', 'Error');
  //       return;
  //     }

  //     this.aadhaarForm.patchValue({
  //       [fileType]: file
  //     });
  //     this.fileName[fileType] = file.name;
  //   }
  // }

  onFileSelected(event: Event, fileType: string): void {
    const input = event.target as HTMLInputElement;

    if (input.files && input.files.length > 0) {
      const file = input.files[0];

      const allowedTypes = ['image/jpeg', 'image/jpg', 'image/png', 'application/pdf'];
      if (!allowedTypes.includes(file.type)) {
        this.toastrService.error('Only JPG, PNG, or PDF files are allowed', 'Error');
        return;
      }

      if (file.size > 5 * 1024 * 1024) {
        this.toastrService.error('File size should not exceed 5MB', 'Error');
        return;
      }

      this.aadhaarForm.patchValue({
        [fileType]: file
      });

      this.fileName[fileType] = file.name;

      // FILE PREVIEW SET HERE
      const reader = new FileReader();
      reader.onload = (e: any) => {
        if (fileType === 'AadhaarFrontFile') {
          this.previewAadhaarFront = e.target.result;
        } else if (fileType === 'AadhaarBackFile') {
          this.previewAadhaarBack = e.target.result;
        } else if (fileType === 'FatherAadhaarFrontFile') {
          this.previewFatherAadhaarFront = e.target.result;
        } else if (fileType === 'FatherAadhaarBackFile') {
          this.previewFatherAadhaarBack = e.target.result;
        }
      };

      reader.readAsDataURL(file);

      // Trigger OCR for image files (Tesseract scans images)
      if (file.type.startsWith('image/') && this.companyConfig?.aadhaarOcr) {
        if (fileType === 'AadhaarFrontFile' || fileType === 'AadhaarBackFile') {
          this.processAadhaarOCR(file, fileType);
        } else if (fileType === 'FatherAadhaarFrontFile' || fileType === 'FatherAadhaarBackFile') {
          this.processFatherAadhaarOCR(file, fileType);
        }
      }
    }
  }

  /**
   * Clear Aadhaar fields and reset upload on invalid document
   */
  clearAadhaarFields(fileType: string, errorMessage?: string): void {
    if (fileType === 'AadhaarFrontFile') {
      this.aadhaarForm.patchValue({
        AadhaarFrontFile: null,
        AadhaarNo: '',
        AadhaarName: '',
        AadhaarDob: ''
      });
      delete this.fileName['AadhaarFrontFile'];
      this.previewAadhaarFront = null;
    } else if (fileType === 'AadhaarBackFile') {
      this.aadhaarForm.patchValue({
        AadhaarBackFile: null,
        AadhaarAddress: ''
      });
      delete this.fileName['AadhaarBackFile'];
      this.previewAadhaarBack = null;
    }
    if (errorMessage) {
      this.ocrError[fileType] = errorMessage;
      this.toastrService.error(errorMessage, 'Invalid Document');
    }
    this.cdr.detectChanges();
  }

  /**
   * Process Father's Aadhaar Front/Back image with Tesseract OCR
   */
  async processFatherAadhaarOCR(file: File, fileType: string): Promise<void> {
    this.isScanningPerFile[fileType] = true;
    this.ocrError[fileType] = '';
    this.cdr.detectChanges();

    try {
      const result = await Tesseract.recognize(file, 'eng');

      this.zone.run(() => {
        const rawText = result.data.text || '';
        const upperText = rawText.toUpperCase();

        console.log(`Father Aadhaar OCR (${fileType}) Confidence: ${result.data.confidence}%`);

        if (fileType === 'FatherAadhaarFrontFile') {
          // Extract 12-digit Aadhaar number
          const aadhaarRegex = /\b(\d{4})\s?(\d{4})\s?(\d{4})\b/;
          const match = upperText.match(aadhaarRegex);
          if (!match) {
            this.ocrError[fileType] = 'Aadhaar number not detected. Please upload a valid Aadhaar Front image.';
            this.toastrService.error(this.ocrError[fileType], 'Invalid Document');
          } else {
            this.ocrError[fileType] = '';
            this.toastrService.success('Father\'s Aadhaar Front scanned successfully!', 'OCR Complete');
          }
        } else if (fileType === 'FatherAadhaarBackFile') {
          // Check for address or PIN code as a basic validation
          const pinMatch = rawText.match(/\b\d{6}\b/);
          if (!pinMatch) {
            this.ocrError[fileType] = 'Could not read Aadhaar Back. Please upload a valid image.';
            this.toastrService.error(this.ocrError[fileType], 'Invalid Document');
          } else {
            this.ocrError[fileType] = '';
            this.toastrService.success('Father\'s Aadhaar Back scanned successfully!', 'OCR Complete');
          }
        }

        this.isScanningPerFile[fileType] = false;
        this.cdr.detectChanges();
      });
    } catch (error) {
      this.zone.run(() => {
        this.ocrError[fileType] = 'OCR failed. Please try again.';
        this.isScanningPerFile[fileType] = false;
        this.cdr.detectChanges();
      });
    }
  }

  /**
   * Process Aadhaar Front/Back image with Tesseract OCR
   */
  async processAadhaarOCR(file: File, fileType: string): Promise<void> {
    this.isScanning = true;
    this.isScanningPerFile[fileType] = true;
    this.ocrError[fileType] = '';
    this.cdr.detectChanges();

    try {
      const result = await Tesseract.recognize(file, 'eng');

      this.zone.run(() => {
        const confidence = result.data.confidence;
        const rawText = result.data.text || '';
        const upperText = rawText.toUpperCase();

        console.log(`Aadhaar OCR (${fileType}) Confidence: ${confidence}%, Text length: ${rawText.length}`);

        if (fileType === 'AadhaarFrontFile') {
          // Check if user accidentally uploaded a PAN card
          const hasPanKeywords = /INCOME\s+TAX|PERMANENT\s+ACCOUNT/i.test(upperText) || /[A-Z]{5}[0-9]{4}[A-Z]{1}/.test(upperText);

          // 1. Aadhaar Number (12 digits, often formatted as XXXX XXXX XXXX)
          const aadhaarRegex = /\b(\d{4})\s?(\d{4})\s?(\d{4})\b/;
          const match = upperText.match(aadhaarRegex);
          let aadhaarNumber = '';
          if (match) {
            aadhaarNumber = `${match[1]} ${match[2]} ${match[3]}`;
          }

          // A valid Aadhaar front MUST have an Aadhaar number and not be a PAN card!
          if (!aadhaarNumber || hasPanKeywords) {
            const errorMsg = hasPanKeywords
              ? 'Wrong document uploaded! You uploaded a PAN card instead of an Aadhaar card.'
              : 'Invalid document format. Aadhaar Number not detected. Please upload a valid Aadhaar Front image.';
            this.clearAadhaarFields(fileType, errorMsg);
            return;
          }

          this.aadhaarForm.patchValue({ AadhaarNo: aadhaarNumber });
          this.toastrService.success(`Aadhaar Number detected: ${aadhaarNumber}`, 'OCR Success');

          // 2. Date of Birth (DOB)
          const dobRegex = /(?:DOB|BIRTH|YEAR OF BIRTH|जन्म\s*तारीख|जन्म\s*वर्ष)[:\s]*([0-9]{2}[\/\.\-][0-9]{2}[\/\.\-][0-9]{4}|[0-9]{4})/i;
          const dobMatch = rawText.match(dobRegex);
          if (dobMatch) {
            const val = dobMatch[1];
            if (val.includes('/') || val.includes('-') || val.includes('.')) {
              const parts = val.split(/[\/\.\-]/);
              if (parts.length === 3) {
                const yyyy = parts[2].length === 4 ? parts[2] : parts[0];
                const mm = parts[1].padStart(2, '0');
                const dd = (parts[2].length === 4 ? parts[0] : parts[2]).padStart(2, '0');
                this.aadhaarForm.patchValue({ AadhaarDob: `${yyyy}-${mm}-${dd}` });
              }
            } else if (val.length === 4) {
              this.aadhaarForm.patchValue({ AadhaarDob: `${val}-01-01` });
            }
          } else {
            const genDateMatch = upperText.match(/\b([0-3]?[0-9])[\/\.\-]([0-1]?[0-9])[\/\.\-](19\d{2}|20\d{2})\b/);
            if (genDateMatch) {
              const dd = genDateMatch[1].padStart(2, '0');
              const mm = genDateMatch[2].padStart(2, '0');
              const yyyy = genDateMatch[3];
              this.aadhaarForm.patchValue({ AadhaarDob: `${yyyy}-${mm}-${dd}` });
            }
          }

          // 3. Name: line before DOB or line following Government of India header
          const lines = rawText.split(/\r?\n/).map(l => l.trim()).filter(l => l.length > 2);
          const dobIdx = lines.findIndex(l => /DOB|DATE\s+OF\s+BIRTH|YEAR\s+OF\s+BIRTH|जन्म/i.test(l));
          const govIdx = lines.findIndex(l => /GOVERNMENT\s+OF\s+INDIA|UNIQUE\s+IDENTIFICATION|MERA\s+AADHAAR/i.test(l));

          const isAadhaarNameLine = (str: string) => {
            const up = str.toUpperCase().trim();
            if (!up || up.length < 3 || up.length > 50) return false;
            if (/GOVERNMENT|INDIA|UNIQUE|AUTHORITY|ENROLMENT|MALE|FEMALE|HELP|AADHAAR|DOB|DATE|BIRTH|YEAR/i.test(up)) return false;
            if (/^[X\s]+$/i.test(up) || /^[0-9\s]+$/.test(up)) return false;
            const clean = str.replace(/[^A-Za-z\s\.]/g, '').trim();
            if (clean.length < 3) return false;
            const distinctLetters = new Set(clean.toUpperCase().replace(/[^A-Z]/g, '').split(''));
            if (distinctLetters.size < 2) return false;
            return /^[A-Za-z\s\.]+$/.test(clean);
          };

          let candidateName = '';
          if (dobIdx > 0) {
            for (let i = dobIdx - 1; i >= 0; i--) {
              if (isAadhaarNameLine(lines[i])) {
                candidateName = lines[i].replace(/[^A-Za-z\s]/g, '').trim();
                break;
              }
            }
          } else if (govIdx !== -1 && lines.length > govIdx + 1) {
            for (let i = govIdx + 1; i < lines.length; i++) {
              if (isAadhaarNameLine(lines[i])) {
                candidateName = lines[i].replace(/[^A-Za-z\s]/g, '').trim();
                break;
              }
            }
          }

          if (candidateName) {
            this.aadhaarForm.patchValue({ AadhaarName: candidateName });
          }

          this.ocrError[fileType] = '';
          this.toastrService.success('Aadhaar front details extracted! Please verify.', 'OCR Complete');

        } else if (fileType === 'AadhaarBackFile') {
          // 4. Address extraction from Aadhaar Back
          const addressRegex = /(?:Address|पता|Addres)[:\s]*([\s\S]+?)(?=\b\d{6}\b|$)/i;
          const addrMatch = rawText.match(addressRegex);
          let extractedAddress = '';
          const pinMatch = rawText.match(/\b\d{6}\b/);

          if (addrMatch && addrMatch[1]) {
            extractedAddress = addrMatch[1].replace(/[\r\n]+/g, ', ').replace(/\s{2,}/g, ' ').trim();
            extractedAddress = extractedAddress.replace(/^,\s*|,\s*$/g, '');
            if (pinMatch && !extractedAddress.includes(pinMatch[0])) {
              extractedAddress += `, ${pinMatch[0]}`;
            }
          } else if (pinMatch) {
            const lines = rawText.split(/\r?\n/).map(l => l.trim()).filter(l => l.length > 3);
            const pinIndex = lines.findIndex(l => l.includes(pinMatch[0]));
            if (pinIndex !== -1) {
              const startIdx = Math.max(0, pinIndex - 3);
              extractedAddress = lines.slice(startIdx, pinIndex + 1).join(', ');
            }
          }

          if (!extractedAddress || extractedAddress.length < 10) {
            this.clearAadhaarFields(fileType, 'Invalid document format. Address/PIN not detected. Please upload a valid Aadhaar Back image.');
            return;
          }

          this.aadhaarForm.patchValue({ AadhaarAddress: extractedAddress });
          this.toastrService.success('Address extracted from Aadhaar Back!', 'OCR Complete');
          this.ocrError[fileType] = '';
        }
      });
    } catch (error) {
      console.error('Aadhaar OCR Error:', error);
      this.zone.run(() => {
        this.clearAadhaarFields(fileType, 'OCR processing failed. Please enter details manually.');
      });
    } finally {
      this.zone.run(() => {
        this.isScanningPerFile[fileType] = false;
        this.isScanning = Object.values(this.isScanningPerFile).some(s => s);
        this.cdr.detectChanges();
      });
    }
  }

  // Submit form and save to database
  OnSubmit(): void {
    this.submitted = true;
    // Check verification requirement based on company config
    if (this.isAadhaarVerificationRequired && !this.IsverifyAddhar) {
      this.toastrService.warning('Please verify Aadhaar number first', 'Warning');
      return;
    }

    //  If verification NOT required, validate Aadhaar format manually
  if (!this.isAadhaarVerificationRequired) {
    const aadhaarNo = this.aadhaarForm.get('AadhaarNo')?.value?.replace(/\s+/g, '') || '';
    if (!this.validateAadhaarFormat(aadhaarNo)) {
      this.toastrService.error('Please enter a valid 12-digit Aadhaar number', 'Error');
      return;
    }
  }

 
  if (this.aadhaarForm.get('AadhaarNo')?.hasError('duplicate')) {
  this.toastrService.error(
    'Aadhaar No already exists. Please enter another Aadhaar No.',
    'Duplicate Aadhaar'
  );
  return;
}
    if (this.aadhaarForm.invalid) {
      // this.toastrService.error('Please fill all required fields', 'Error');
      return;
    }

    const formData = new FormData();
    const aadhaarNo = this.aadhaarForm.get('AadhaarNo')?.value.replace(/\s+/g, '');

    // Append all form data
    formData.append("pk_recId", this.pk_recId);
    formData.append('AadhaarNo', aadhaarNo);
    formData.append('AadhaarName', this.aadhaarForm.get('AadhaarName')?.value);
    formData.append('AadhaarDob', this.aadhaarForm.get('AadhaarDob')?.value);
    formData.append('AadhaarAddress', this.aadhaarForm.get('AadhaarAddress')?.value);
    formData.append('StateId', this.aadhaarForm.get('StateId')?.value || '');
    formData.append('CityId', this.aadhaarForm.get('CityId')?.value || '');

    // Append files
    const frontFile = this.aadhaarForm.get('AadhaarFrontFile')?.value;
    const backFile = this.aadhaarForm.get('AadhaarBackFile')?.value;
    const fatherFrontFile = this.aadhaarForm.get('FatherAadhaarFrontFile')?.value;
    const fatherBackFile = this.aadhaarForm.get('FatherAadhaarBackFile')?.value;

    if (frontFile) formData.append('AadhaarFrontFile', frontFile);
    if (backFile) formData.append('AadhaarBackFile', backFile);
    if (fatherFrontFile) formData.append('FatherAadhaarFrontFile', fatherFrontFile);
    if (fatherBackFile) formData.append('FatherAadhaarBackFile', fatherBackFile);

    this.ngxUILoaderService.start();

    // Save to database
    this.kycService.verifyaadhaar(formData).subscribe({
      next: (result) => {
        this.ngxUILoaderService.stop();
        if (result.isSuccess) {
          this.toastrService.success(result.message || 'Aadhaar details saved successfully!', 'Success');
          this.loadAadhaarDetails();   // Load data
         this.isViewMode = true;
         window.dispatchEvent(new Event('refresh-onboarding-status'));
        } else {
          this.toastrService.error(result.message || 'Failed to save Aadhaar details', 'Error');
        }
      },
      error: (error) => {
        this.ngxUILoaderService.stop();
        
        this.toastrService.error('An error occurred while saving Aadhaar details', 'Error');
      }
    });
  }

  // Reset form
  reset(): void {
    this.aadhaarForm.reset();
    this.submitted = false;
    this.IsverifyAddhar = false;
    this.fileName = {};
  }

  // Navigate back
  goBack(): void {
    this.router.navigate(['/dash/setting']);
  }

    onKeyUp(event: KeyboardEvent, index: number): void {
    const input = event.target as HTMLInputElement;
  
    // Allow only numeric values
    if (/^\d$/.test(input.value)) {
      this.otp[index] = input.value; // Update OTP array
      const nextInput = document.querySelector(`#otp input:nth-child(${index + 2})`) as HTMLInputElement;
      if (nextInput) nextInput.focus(); // Move focus to the next input
    } else {
      input.value = ''; // Clear invalid input
    }
  
    // Handle backspace
    if (event.key === 'Backspace' && index > 0) {
      const prevInput = document.querySelector(`#otp input:nth-child(${index})`) as HTMLInputElement;
      if (prevInput) prevInput.focus();
    }
  }

    isOtpComplete(): boolean {
    return this.otp.every((digit) => digit !== ''); // Return true if all boxes are filled
  }

  downloadImage(filename: string) {
  this.kycService.getImageOnboard(filename).subscribe({
    next: (blob) => {
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = filename;
      a.click();
      window.URL.revokeObjectURL(url);
    },
    error: (err) => {
      
    }
  });
}


loadImageToView(filename: string, type: 'front' | 'back') {
  this.kycService.getImageOnboard(filename).subscribe({
    next: (blob) => {
      const reader = new FileReader();
      reader.onload = () => {
        if (!this.aadhaarData) this.aadhaarData = {};

        if (type === 'front') {
          this.aadhaarData.aadhaarFront = reader.result as string;
        } else {
          this.aadhaarData.aadhaarBack = reader.result as string;
        }
      };
      reader.readAsDataURL(blob);  // Convert blob → Base64 for <img>
    },
    error: () => {
     
    }
  });
}

loadFatherImageToView(filename: string, type: 'fatherFront' | 'fatherBack') {
  this.kycService.getImageOnboard(filename).subscribe({
    next: (blob) => {
      const reader = new FileReader();
      reader.onload = () => {
        if (!this.aadhaarData) this.aadhaarData = {};
        if (type === 'fatherFront') {
          this.previewFatherAadhaarFront = reader.result as string;
          this.aadhaarData.fatherAadhaarFront = reader.result as string;
        } else {
          this.previewFatherAadhaarBack = reader.result as string;
          this.aadhaarData.fatherAadhaarBack = reader.result as string;
        }
      };
      reader.readAsDataURL(blob);
    },
    error: () => {}
  });
}


openImagePreview(src: string, title: string) {
  this.previewImageSrc = src;
  this.previewImageTitle = title;
  const modalEl = document.getElementById('imagePreviewModal');
  const modal = new bootstrap.Modal(modalEl!);
  modal.show();
}

}