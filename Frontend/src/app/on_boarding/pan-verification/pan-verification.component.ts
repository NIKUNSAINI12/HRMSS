import { Component, OnInit, NgZone, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormBuilder, FormGroup, FormsModule, ReactiveFormsModule, Validators } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { ToastrService } from 'ngx-toastr';
import { NgxMaskDirective } from 'ngx-mask';
import { NgxUiLoaderService } from 'ngx-ui-loader';
import { KycService } from '../../pages/setting/service/kyc.service';
import { CandidateMasterService } from '../../pages/all-dashboard/recruitment/RecruitServices/candidate-master.service';
import { CandidateExperienceDetailService } from '../services/candidate-experience-details.service';
import { CompanyConfigService, CompanyConfig } from '../services/company-config.service';
import Tesseract from 'tesseract.js';


@Component({
 selector: 'app-pan-verification',
  standalone: true,
  imports: [CommonModule, FormsModule, ReactiveFormsModule, NgxMaskDirective],
  templateUrl: './pan-verification.component.html',
  styleUrl: './pan-verification.component.scss'
})
export class PanVerificationComponent implements OnInit {
  panForm!: FormGroup;
  isVerifying: boolean = false;
  submitted = false;
  isVerified = false;
  userId: string = '';
   fileName: string ='';

  panData: any;
  isViewMode = false;
  pk_recId: string = ''; 
  // isPanVerified =false

  previewPanImage: string | null = null;
  originalPanUrl: string = '';

  // OCR state properties
  isScanning: boolean = false;
  ocrError: string = '';

    // Company Config Properties
  companyConfig: CompanyConfig | null = null;
  isPanMandatory: boolean = false;
  isPanVerificationRequired: boolean = false;


  constructor(
    private formBuilder: FormBuilder,
    private toastrService: ToastrService,
    private router: Router,
     private route: ActivatedRoute,
    private kycService: CandidateExperienceDetailService,
    private ngxUILoaderService: NgxUiLoaderService,
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
      this.loadPanDetails();
    });
  }

/**
   * Load company configuration from service or API
   */
  loadCompanyConfig(): void {
    // Try to get from service first (if already loaded by another component)
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
      this.isPanMandatory = this.companyConfig.panMandatory;
      this.isPanVerificationRequired = this.companyConfig.panVerification;
    }
  }

  /**
   * Use default config if API fails
   */
  useDefaultConfig(): void {
    this.companyConfig = this.companyConfigService.getDefaultConfig();
    this.updateConfigFlags();
  }


  initializeForm(): void {
    this.panForm = this.formBuilder.group({
      PANNo: ['', [Validators.required]],
      PANName: ['', Validators.required],
      PANDob: ['', Validators.required],
      PanCardFile: [null, Validators.required]
    });
  }



private validatePANFormat(panNo: string): boolean {
  if (!panNo || panNo.length !== 10) {
    return false;
  }
  const panRegex = /^[A-Z]{5}[0-9]{4}[A-Z]{1}$/;
  return panRegex.test(panNo.toUpperCase());
}

formatDateForInput(dateVal: any): string {
  if (!dateVal) return '';
  if (typeof dateVal === 'string') {
    const trimmed = dateVal.trim();
    if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) {
      return trimmed;
    }
    if (trimmed.includes('T')) {
      const datePart = trimmed.split('T')[0];
      if (/^\d{4}-\d{2}-\d{2}$/.test(datePart)) {
        return datePart;
      }
    }
  }
  const d = new Date(dateVal);
  if (!isNaN(d.getTime())) {
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }
  if (typeof dateVal === 'string') {
    const datePart = dateVal.trim().split(' ')[0];
    const parts = datePart.split(/[-/]/);
    if (parts.length === 3) {
      if (parts[2].length === 4) {
        return `${parts[2]}-${parts[0].padStart(2, '0')}-${parts[1].padStart(2, '0')}`;
      } else if (parts[0].length === 4) {
        return `${parts[0]}-${parts[1].padStart(2, '0')}-${parts[2].padStart(2, '0')}`;
      }
    }
  }
  return '';
}

checkPANAvailability(panNo: string): void {
  if (!panNo || panNo.trim().length !== 10) {
    return;
  }

  const trimmedPan = panNo.trim().toUpperCase();
  const existingSavedPan = (this.panData?.panNo || '').trim().toUpperCase();
  const panControl = this.panForm.get('PANNo');

  // If user enters their own already-saved PAN in update mode, do not show duplicate error
  if (existingSavedPan && trimmedPan === existingSavedPan) {
    if (panControl?.errors?.['duplicate']) {
      const errors = { ...(panControl.errors || {}) };
      delete errors['duplicate'];
      panControl.setErrors(Object.keys(errors).length ? errors : null);
    }
    return;
  }

  const fieldName = 'PAN No';
  const fieldValue = trimmedPan;
  const generalId = this.pk_recId || '';

  this.kycService.CheckDuplicate(
    fieldName,
    fieldValue,
    generalId
  ).subscribe({
    next: (response: any) => {
      if (response && response.isSuccess === false) {
        panControl?.setErrors({
          ...(panControl.errors || {}),
          duplicate: response.message
        });
      } else {
        if (panControl?.errors?.['duplicate']) {
          const errors = { ...(panControl.errors || {}) };
          delete errors['duplicate'];

          panControl.setErrors(
            Object.keys(errors).length ? errors : null
          );
        }
      }
    },
    error: (err) => {
      console.error('PAN Duplicate Check API Error:', err);
    }
  });
}

//   getMandatoryDetails() {
//   this.kycService.getMandatoryDetails().subscribe({
//     next: (res) => {
//   if(res.isSuccess){
//   this.isPanVerified=  res.data.panMandatory
//   }
//   else{
//     this.isPanVerified=true
//   }
//     },
//     error: () => {
//     }
//   });
// }

  editPan(): void {
    this.isViewMode = false;
    const panControl = this.panForm.get('PANNo');
    if (panControl?.errors?.['duplicate']) {
      const errors = { ...(panControl.errors || {}) };
      delete errors['duplicate'];
      panControl.setErrors(Object.keys(errors).length ? errors : null);
    }
    if (this.panData?.panCard) {
      this.panForm.get('PanCardFile')?.clearValidators();
      this.panForm.get('PanCardFile')?.updateValueAndValidity();
    }
  }

  loadPanDetails() {
    this.kycService.Get_Pan_ById(this.pk_recId).subscribe({
      next: (res) => {
        if (res.isSuccess && res.data) {
          this.panData = res.data;
          if (res.data.pk_recId) {
            this.pk_recId = res.data.pk_recId;
          }
          if (res.data.panNo) {
            this.isVerified = true;
          }
          this.panForm.patchValue({
            PANNo: res.data.panNo || '',
            PANName: res.data.panName || '',
            PANDob: this.formatDateForInput(res.data.panDob)
          });

          const panControl = this.panForm.get('PANNo');
          if (panControl?.errors?.['duplicate']) {
            const errors = { ...(panControl.errors || {}) };
            delete errors['duplicate'];
            panControl.setErrors(Object.keys(errors).length ? errors : null);
          }

          if (res.data.panCard) {
            const fileStr = res.data.panCard.toString();
            this.fileName = fileStr.substring(fileStr.lastIndexOf('/') + 1) || 'Existing PAN Card';
            this.loadImageToView(this.panData.panCard);
            this.isViewMode = true;
            this.panForm.get('PanCardFile')?.clearValidators();
            this.panForm.get('PanCardFile')?.updateValueAndValidity();
          } else {
            this.isViewMode = false;
          }
        } else {
          this.isViewMode = false;
        }
      },
      error: () => {
        this.isViewMode = false;
      }
    });
  }
  get validate() {
    return this.panForm.controls;
  }

  // Verify PAN Number
 
  // Verify PAN Number
verifyPAN(): void {
  const panNo = this.panForm.get('PANNo')?.value.toUpperCase() || '';

  // if (!panNo || panNo.length !== 10) {
  //   this.toastrService.error('Please enter a valid 10-character PAN number!', 'Error');
  //   return;
  // }

   if (!this.validatePANFormat(panNo)) {
    this.toastrService.error('Please enter a valid 10-character PAN number!', 'Error');
    return;
  }


  this.isVerifying = true;  // Start loader
  // this.ngxUILoaderService.start();

  // Call API to verify PAN
  this.kycService.Verify_PAN(panNo, this.userId).subscribe({
    next: (res) => {
      if (res.isSuccess && res.data) {
        // Auto-fill form with API data
        this.panForm.patchValue({
          PANName: res.data.fullName || '',
          PANDob: this.formatDateForInput(res.data.dob)
        });

        this.isVerified = true;
        this.toastrService.success('PAN verified successfully!', 'Success');
      } else {
        this.isVerified = false;
        this.toastrService.error(res.message || 'Invalid PAN number', 'Error');
      }
      this.isVerifying = false;  // Stop loader
      // this.ngxUILoaderService.stop();
    },
    error: (error) => {
      this.isVerified = false;
      this.isVerifying = false;  // Stop loader
      this.toastrService.error('An error occurred while verifying PAN. Please try again.', 'Error');
      // this.ngxUILoaderService.stop();
    }
  });
}

  // Handle file selection
  // onFileSelected(event: Event): void {
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

  //     this.panForm.patchValue({
  //       PanCardFile: file
  //     });
  //     this.fileName = file.name;
  //   }
  // }

  onFileSelected(event: Event, fileType: string): void {
    const input = event.target as HTMLInputElement;

    if (input.files && input.files.length > 0) {
      const file = input.files[0];

      const allowedTypes = ['image/jpeg', 'image/jpg', 'image/png'];
      if (!allowedTypes.includes(file.type)) {
        this.toastrService.error('Only JPG, PNG files are allowed', 'Error');
        return;
      }

      if (file.size > 5 * 1024 * 1024) {
        this.toastrService.error('File size should not exceed 5MB', 'Error');
        return;
      }

      this.panForm.patchValue({
        [fileType]: file
      });

      this.fileName = file.name;

      // Preview image properly
      const reader = new FileReader();
      reader.onload = (e: any) => {
        this.previewPanImage = e.target.result;  // Preview for UI
      };
      reader.readAsDataURL(file);

      // Trigger OCR
      if (fileType === 'PanCardFile' && this.companyConfig?.panOcr) {
        this.processPanOCR(file);
      }
    }
  }

  /**
   * Clear PAN fields and reset upload on invalid document
   */
  clearPanFields(errorMessage?: string): void {
    this.panForm.patchValue({
      PanCardFile: null,
      PANNo: '',
      PANName: '',
      PANDob: ''
    });
    this.fileName = '';
    this.previewPanImage = null;
    if (errorMessage) {
      this.ocrError = errorMessage;
      this.toastrService.error(errorMessage, 'Invalid Document');
    }
    this.cdr.detectChanges();
  }

  /**
   * Process PAN card image with Tesseract OCR
   */
  async processPanOCR(file: File): Promise<void> {
    this.isScanning = true;
    this.ocrError = '';
    this.cdr.detectChanges();

    try {
      const result = await Tesseract.recognize(file, 'eng');

      this.zone.run(() => {
        const confidence = result.data.confidence;
        const rawText = result.data.text || '';
        const upperText = rawText.toUpperCase();

        console.log(`PAN OCR Confidence: ${confidence}%, Text length: ${rawText.length}`);
        console.log('Extracted Text:', rawText);

        // 1. Cross-document checks
        const hasAadhaarKeywords = /AADHAAR|आधार|MERA\s+AADHAAR|UNIQUE\s+IDENTIFICATION/i.test(upperText);
        const hasVoterKeywords = /ELECTION\s+COMMISSION|ELECTOR\s+PHOTO|निर्वाचन\s+आयोग|EPIC/i.test(upperText);
        const hasPanKeywords = /INCOME\s+TAX|PERMANENT\s+ACCOUNT|GOVT\.?\s+OF\s+INDIA|आयकर\s+विभाग/i.test(upperText);

        if (hasAadhaarKeywords) {
          this.clearPanFields('Wrong document uploaded! You uploaded an Aadhaar card instead of a PAN card.');
          return;
        }

        if (hasVoterKeywords) {
          this.clearPanFields('Wrong document uploaded! You uploaded a Voter ID card instead of a PAN card.');
          return;
        }

        // 2. Resilient PAN Number Extraction (5 letters, 4 digits, 1 letter)
        let panValue = '';

        // Strategy A: Standard regex allowing optional spaces/hyphens/dots
        const panRegex = /\b([A-Z]{5})[\s\-\.]*([0-9]{4})[\s\-\.]*([A-Z])\b/;
        const panMatch = upperText.match(panRegex);
        if (panMatch) {
          panValue = `${panMatch[1]}${panMatch[2]}${panMatch[3]}`;
        }

        // Strategy B: Scan stripped alphanumeric string (handles any intra-word spaces or punctuation)
        if (!panValue) {
          const stripped = upperText.replace(/[^A-Z0-9]/g, '');
          const strippedMatch = stripped.match(/[A-Z]{5}[0-9]{4}[A-Z]/);
          if (strippedMatch) {
            panValue = strippedMatch[0];
          }
        }

        // Strategy C: Check line following 'Permanent Account Number'
        if (!panValue) {
          const lines = upperText.split(/\r?\n/).map(l => l.trim());
          const panLabelIdx = lines.findIndex(l => /PERMANENT\s+ACCOUNT|ACCOUNT\s+NUMBER/i.test(l));
          if (panLabelIdx >= 0) {
            for (let k = panLabelIdx + 1; k <= Math.min(lines.length - 1, panLabelIdx + 2); k++) {
              const lineClean = lines[k].replace(/[^A-Z0-9]/g, '');
              const lm = lineClean.match(/[A-Z]{5}[0-9]{4}[A-Z]/);
              if (lm) {
                panValue = lm[0];
                break;
              }
            }
          }
        }

        // Strategy D: Word-by-word with common OCR letter/digit substitution correction
        if (!panValue) {
          const words = upperText.split(/\s+/);
          for (const w of words) {
            const clean = w.replace(/[^A-Z0-9]/g, '');
            if (clean.length === 10) {
              const chars = clean.split('');
              const d2l: { [k: string]: string } = { '0': 'O', '1': 'I', '5': 'S', '8': 'B', '2': 'Z' };
              const l2d: { [k: string]: string } = { 'O': '0', 'I': '1', 'L': '1', 'S': '5', 'B': '8', 'Z': '2' };
              for (let i = 0; i < 5; i++) if (/\d/.test(chars[i])) chars[i] = d2l[chars[i]] || chars[i];
              for (let i = 5; i < 9; i++) if (/[A-Z]/.test(chars[i])) chars[i] = l2d[chars[i]] || chars[i];
              if (/\d/.test(chars[9])) chars[9] = d2l[chars[9]] || chars[9];
              const fixed = chars.join('');
              if (/^[A-Z]{5}[0-9]{4}[A-Z]$/.test(fixed)) {
                panValue = fixed;
                break;
              }
            }
          }
        }

        // Validate document
        if (!panValue && !hasPanKeywords) {
          this.clearPanFields('Invalid document format. PAN Number not detected. Please upload a valid PAN card.');
          return;
        }

        if (panValue) {
          this.panForm.patchValue({ PANNo: panValue });
          this.panForm.get('PANNo')?.markAsDirty();
          this.panForm.get('PANNo')?.markAsTouched();
          this.toastrService.success(`PAN Number detected: ${panValue}`, 'OCR Success');
        } else if (hasPanKeywords) {
          this.toastrService.info('PAN Card detected. Please verify or enter PAN Number manually if needed.', 'OCR Info');
        }

        // 3. Extract Date of Birth (DD/MM/YYYY or DD-MM-YYYY or DD.MM.YYYY)
        const dateMatch = upperText.match(/\b([0-3]?[0-9])[\/\.\-]([0-1]?[0-9])[\/\.\-](19\d{2}|20\d{2})\b/);
        if (dateMatch) {
          const dd = dateMatch[1].padStart(2, '0');
          const mm = dateMatch[2].padStart(2, '0');
          const yyyy = dateMatch[3];
          this.panForm.patchValue({ PANDob: `${yyyy}-${mm}-${dd}` });
          this.panForm.get('PANDob')?.markAsDirty();
          this.panForm.get('PANDob')?.markAsTouched();
        } else {
          const isoDateMatch = upperText.match(/\b(19\d{2}|20\d{2})[\/\.\-]([0-1]?[0-9])[\/\.\-]([0-3]?[0-9])\b/);
          if (isoDateMatch) {
            const yyyy = isoDateMatch[1];
            const mm = isoDateMatch[2].padStart(2, '0');
            const dd = isoDateMatch[3].padStart(2, '0');
            this.panForm.patchValue({ PANDob: `${yyyy}-${mm}-${dd}` });
            this.panForm.get('PANDob')?.markAsDirty();
            this.panForm.get('PANDob')?.markAsTouched();
          }
        }

        // 3. Extract Name (strict validation: ignore dummy/placeholder strings like XXXX)
        const lines = rawText.split(/\r?\n/).map(l => l.trim()).filter(l => l.length > 1);

        const isValidName = (str: string) => {
          if (!str || str.length < 3 || str.length > 50) return false;
          const up = str.toUpperCase().trim();
          if (/^(?:NAME|ELECTOR|CARDHOLDER|HOLDER|APPLICANT|SIGNATURE|PHOTO)$/i.test(up)) return false;
          if (/INCOME|TAX|DEPARTMENT|GOVT|INDIA|PERMANENT|ACCOUNT|NUMBER|CARD|SIGNATURE|FATHER|DATE|BIRTH|DOB|MALE|FEMALE/i.test(up)) return false;
          if (/^[X\s]+$/i.test(up) || /^[0-9\s]+$/.test(up)) return false;
          const clean = str.replace(/[^A-Za-z]/g, '');
          if (clean.length < 3) return false;
          const distinct = new Set(clean.toUpperCase().split(''));
          if (distinct.size < 2) return false;
          return true;
        };

        let detectedName = '';

        // Tier 1: Check if line explicitly has 'Name : ...' or 'नाम : ...' with an actual person name (not father/husband/mother)
        for (const line of lines) {
          if (!/Father|पिता|Husband|पति|Mother|माता|Falher|Fathar|Faher/i.test(line)) {
            const match = line.match(/(?:^|[^\w])(?:Name|नाम)\s*[\:\.\-\/\s]+\s*([A-Za-z][A-Za-z\s\.\']{2,})/i);
            if (match && match[1]) {
              const cand = match[1].replace(/^(?:Name|नाम)[\:\.\-\/\s]*/i, '').replace(/[^A-Za-z\s\.]/g, '').trim();
              if (isValidName(cand)) {
                detectedName = cand.toUpperCase();
                break;
              }
            }
          }
        }

        // Tier 2: Check line immediately following a standalone 'Name' or 'नाम / Name' label line
        if (!detectedName) {
          for (let i = 0; i < lines.length - 1; i++) {
            const line = lines[i];
            if (/\b(?:Name|नाम)\b/i.test(line) && !/Father|पिता|Husband|पति|Mother|माता/i.test(line)) {
              const nextLine = lines[i + 1].replace(/.*(?:Name|नाम)[\:\.\-\/\s]*/i, '').replace(/[^A-Za-z\s\.]/g, '').trim();
              if (isValidName(nextLine)) {
                detectedName = nextLine.toUpperCase();
                break;
              }
            }
          }
        }

        // Tier 3: In standard PAN layout (Format A): Name is immediately above Father's Name line
        if (!detectedName) {
          const fatherIdx = lines.findIndex(l => /FATHER|पिता|FATHAR|FALHER|FAHER|FIINERS/i.test(l));
          if (fatherIdx > 0) {
            for (let k = fatherIdx - 1; k >= Math.max(0, fatherIdx - 2); k--) {
              const cand = lines[k].replace(/.*(?:Name|नाम)[\:\.\-\/\s]*/i, '').replace(/[^A-Za-z\s\.]/g, '').trim();
              if (isValidName(cand)) {
                detectedName = cand.toUpperCase();
                break;
              }
            }
          }
        }

        // Tier 4: In standard PAN layout: Name is after header lines and before DOB / PAN
        if (!detectedName) {
          const dobIdx = lines.findIndex(l => /\b([0-3]?[0-9])[\/\.\-]([0-1]?[0-9])[\/\.\-](19\d{2}|20\d{2})\b/.test(l));
          const panIdx = lines.findIndex(l => /[A-Z]{5}[0-9]{4}[A-Z]/.test(l));
          const endLimit = dobIdx >= 0 ? dobIdx : (panIdx >= 0 ? panIdx : lines.length);

          for (let i = 0; i < endLimit; i++) {
            if (/INCOME|TAX|DEPARTMENT|GOVT|INDIA|भारत|PERMANENT|ACCOUNT/i.test(lines[i])) continue;
            if (/Father|पिता|Husband|पति|Mother|माता|Falher|Fathar|Faher|Fiiners/i.test(lines[i])) continue;
            const cand = lines[i].replace(/.*(?:Name|नाम)[\:\.\-\/\s]*/i, '').replace(/[^A-Za-z\s\.]/g, '').trim();
            if (isValidName(cand)) {
              detectedName = cand.toUpperCase();
              break;
            }
          }
        }

        if (detectedName) {
          this.panForm.patchValue({ PANName: detectedName });
          this.panForm.get('PANName')?.markAsDirty();
          this.panForm.get('PANName')?.markAsTouched();
        }

        this.ocrError = '';
        this.toastrService.success('PAN details extracted successfully! Please review.', 'OCR Complete');
      });
    } catch (error) {
      console.error('PAN OCR Error:', error);
      this.zone.run(() => {
        this.clearPanFields('OCR processing failed. Please enter details manually.');
      });
    } finally {
      this.zone.run(() => {
        this.isScanning = false;
        this.cdr.detectChanges();
      });
    }
  }

  // Submit form and save to database
  OnSubmit(): void {
    this.submitted = true;

// Check verification requirement based on company config
    if (this.isPanVerificationRequired && !this.isVerified) {
      this.toastrService.warning('Please verify PAN number first', 'Warning');
      return;
    }
      // If verification NOT required, validate PAN format manually
  if (!this.isPanVerificationRequired) {
    const panNo = this.panForm.get('PANNo')?.value?.toUpperCase() || '';
    if (!this.validatePANFormat(panNo)) {
      this.toastrService.error('Please enter a valid PAN number', 'Error');
      return;
    }
  }



    if (this.panForm.invalid) {
      // this.toastrService.error('Please fill all required fields', 'Error');
      return;
    }

    const formData = new FormData();

    // Append all form data
       formData.append("pk_recId", this.pk_recId);
     formData.append('PANNo', this.panForm.get('PANNo')?.value?.toUpperCase() || '');
    formData.append('PANName', this.panForm.get('PANName')?.value);
    formData.append('PANDob', this.panForm.get('PANDob')?.value);

    // Append file
    const panFile = this.panForm.get('PanCardFile')?.value;
    if (panFile) {
      formData.append('PanCardFile', panFile);
    }

    this.ngxUILoaderService.start();

    // Save to database
    this.kycService.verifypan(formData).subscribe({
      next: (result) => {
        this.ngxUILoaderService.stop();
        if (result.isSuccess) {
          this.toastrService.success(result.message || 'PAN details saved successfully!', 'Success');
           this.loadPanDetails();   // Load data
         this.isViewMode = true;
         window.dispatchEvent(new Event('refresh-onboarding-status'));
        } else {
          this.toastrService.error(result.message || 'Failed to save PAN details', 'Error');
        }
      },
      error: (error) => {
        this.ngxUILoaderService.stop();       
        this.toastrService.error('An error occurred while saving PAN details', 'Error');
      }
    });
  }

  // Reset form
 

  // Navigate back
  goBack(): void {
    this.router.navigate(['/dash/setting']);
  }

  // Convert PAN to uppercase and manage verification status
  onPANInput(event: Event): void {
    const input = event.target as HTMLInputElement;
    input.value = input.value.toUpperCase();
    this.panForm.patchValue({ PANNo: input.value });

    const existingSavedPan = (this.panData?.panNo || '').trim().toUpperCase();
    if (existingSavedPan && input.value === existingSavedPan) {
      this.isVerified = true;
      const panControl = this.panForm.get('PANNo');
      if (panControl?.errors?.['duplicate']) {
        const errors = { ...(panControl.errors || {}) };
        delete errors['duplicate'];
        panControl.setErrors(Object.keys(errors).length ? errors : null);
      }
    } else if (existingSavedPan && input.value !== existingSavedPan) {
      this.isVerified = false;
    }
  }

 

downloadImage(filename: string) {
  this.kycService.getImageOnboard(filename).subscribe({
    next: (blob) => {
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = filename;
      a.click();
      window.URL.revokeObjectURL(url);
    },
    error: (err) => console.error('Failed to download image:', err)
  });
}


loadImageToView(filename: string,) {
  this.kycService.getImageOnboard(filename).subscribe({
    next: (blob) => {
      const reader = new FileReader();
      reader.onload = () => {
        if (!this.panData) this.panData = {};
          this.panData.panCard = reader.result as string;
          this.originalPanUrl = reader.result as string;
      };
      reader.readAsDataURL(blob);  // Convert blob → Base64 for <img>
    },
    error: () => {
     
    }
  });
}
}