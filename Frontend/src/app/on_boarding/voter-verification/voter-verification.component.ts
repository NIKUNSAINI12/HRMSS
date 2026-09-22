import { Component, OnInit, ElementRef, ViewChild, NgZone, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormBuilder, FormGroup, FormsModule, ReactiveFormsModule, Validators } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { ToastrService } from 'ngx-toastr';
import { NgxUiLoaderService } from 'ngx-ui-loader';
import { CandidateExperienceDetailService } from '../services/candidate-experience-details.service';
import Tesseract from 'tesseract.js';
declare var bootstrap: any;

@Component({
  selector: 'app-voter-verification',
  standalone: true,
  imports: [CommonModule, FormsModule, ReactiveFormsModule],
  templateUrl: './voter-verification.component.html',
  styleUrl: './voter-verification.component.scss'
})
export class VoterVerificationComponent implements OnInit {
  @ViewChild('otpModal') otpModal!: ElementRef;

  voterForm!: FormGroup;
  submitted = false;
  pk_recId: string = '';
  isViewMode = false;
  voterData: any;
  Isverifyvoter = false;
  previewFrontImage: string | null = null;
  previewBackImage: string | null = null;
  originalFrontUrl: string = '';
  originalBackUrl: string = '';
  fileName: any = {};
  isVoterVerified = false;
  isVerifying: boolean = false;

  // OCR state properties
  isScanning: boolean = false;
  isScanningPerFile: { [key: string]: boolean } = {};
  ocrError: { [key: string]: string } = {};

  otp: string[] = ['', '', '', '', '', ''];
  companyConfig: any;

  constructor(
    private fb: FormBuilder,
    private toastr: ToastrService,
    private router: Router,
    private kycService: CandidateExperienceDetailService,
    private loader: NgxUiLoaderService,
    private route: ActivatedRoute,
    private zone: NgZone,
    private cdr: ChangeDetectorRef
  ) {}

  ngOnInit(): void {
    this.route.queryParams.subscribe((p) => {
      this.pk_recId = p['pk_recId'] ?? '';
    });
    this.getMandatoryDetails();
    this.initializeForm();
    this.loadVoterDetails();
  }

  editVoter() {
    this.isViewMode = false;
    const control = this.voterForm.get('VoterNo');
    if (control?.hasError('duplicate')) {
      const errors = { ...control.errors };
      delete errors['duplicate'];
      control.setErrors(Object.keys(errors).length > 0 ? errors : null);
    }
  }

  checkVoterDuplicate(): void {
    const voterNo = this.voterForm.get('VoterNo')?.value?.trim().toUpperCase() || '';
    if (!voterNo) return;

    const existingSavedVoter = (this.voterData?.voterNo || '').trim().toUpperCase();
    const control = this.voterForm.get('VoterNo');

    if (existingSavedVoter && voterNo === existingSavedVoter) {
      if (control?.hasError('duplicate')) {
        const errors = { ...control.errors };
        delete errors['duplicate'];
        control.setErrors(Object.keys(errors).length > 0 ? errors : null);
      }
      return;
    }

    this.kycService.CheckDuplicate('Voter ID', voterNo, this.pk_recId || undefined).subscribe({
      next: (res: any) => {
        if (!res.isSuccess) {
          control?.setErrors({
            ...(control.errors || {}),
            duplicate: res.message || 'Voter ID already exists.'
          });
        } else {
          if (control?.hasError('duplicate')) {
            const errors = { ...control.errors };
            delete errors['duplicate'];
            control.setErrors(Object.keys(errors).length > 0 ? errors : null);
          }
        }
      },
      error: (err) => console.error('Voter Duplicate Check Error:', err)
    });
  }

  initializeForm(): void {
    this.voterForm = this.fb.group({
      VoterNo: ['', Validators.required],
      VoterName: [''],
      VoterDOB: [''],
      VoterAddress: [''],
      VoterFrontPhotoFile: ['', Validators.required],
      VoterBackPhotoFile: ['']
    });
  }

  get validate() {
    return this.voterForm.controls;
  }

  loadVoterDetails() {
    this.kycService.Get_Voter_ById(this.pk_recId).subscribe({
      next: (res) => {
        if (!res.isSuccess || !res.data) {
          this.isViewMode = false;
          return;
        }

        this.voterData = res.data;
        if (res.data.pk_recId) {
          this.pk_recId = res.data.pk_recId;
        }

        const control = this.voterForm.get('VoterNo');
        if (control?.hasError('duplicate')) {
          const errors = { ...control.errors };
          delete errors['duplicate'];
          control.setErrors(Object.keys(errors).length > 0 ? errors : null);
        }

        this.voterForm.patchValue({
          VoterNo: res.data.voterNo || '',
          VoterName: res.data.voterName || '',
          VoterDOB: res.data.voterDOB ? res.data.voterDOB.split('T')[0] : '',
          VoterAddress: res.data.voterAddress || ''
        });

        if (this.voterData.voterFrontPhoto || this.voterData.voterBackPhoto) {
          this.isViewMode = true;
          if (this.voterData.voterFrontPhoto) {
            this.loadImageToView(this.voterData.voterFrontPhoto, 'front');
          }
          if (this.voterData.voterBackPhoto) {
            this.loadImageToView(this.voterData.voterBackPhoto, 'back');
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

  getMandatoryDetails() {
    this.kycService.getMandatoryDetails().subscribe({
      next: (res) => {
        if (res.isSuccess) {
          this.companyConfig = res.data;
          this.isVoterVerified = false;
        } else {
          this.isVoterVerified = true;
        }
      },
      error: () => {},
    });
  }

  verifyVoter(): void {
    const voterNo = this.voterForm.get('VoterNo')?.value;

    if (!voterNo) {
      this.toastr.error('Please enter Voter ID number!', 'Error');
      return;
    }

    this.isVerifying = true;

    // Call API to verify Voter ID
    // this.kycService.Verify_Voter(voterNo).subscribe({
    //   next: (res) => {
    //     if (res.isSuccess && res.data) {
    //       // Auto-fill form with API data
    //       this.voterForm.patchValue({
    //         VoterName: res.data.fullName || '',
    //         VoterDOB: res.data.dob || '',
    //         VoterAddress: res.data.address || ''
    //       });

    //       this.Isverifyvoter = true;
    //       this.toastr.success('Voter ID verified successfully!', 'Success');
    //     } else {
    //       this.Isverifyvoter = false;
    //       this.toastr.error(res.message || 'Invalid Voter ID', 'Error');
    //     }
    //     this.isVerifying = false;
    //   },
    //   error: (error) => {
    //     this.Isverifyvoter = false;
    //     this.isVerifying = false;
    //     this.toastr.error('An error occurred while verifying Voter ID. Please try again.', 'Error');
    //   }
    // });
  }

  OTPVoter() {
    const voterNo = this.voterForm.get('VoterNo')?.value || '';
    if (!voterNo) {
      this.toastr.error('Please enter Voter ID No', 'Error');
      return;
    }
    this.loader.start();
    // Uncomment when API is ready
    // this.kycService.Verify_Voter_OTP(voterNo).subscribe({
    //   next: res => {
    //     this.loader.stop();
    //     if (res.isSuccess) {
    //       sessionStorage.setItem('voter_client_id', res.data.client_id || '');
    //       this.open_OTP_Modal();
    //       this.toastr.success('OTP sent successfully!', 'Success');
    //     } else {
    //       this.toastr.error(res.message || 'Verification failed', 'Error');
    //     }
    //   },
    //   error: () => {
    //     this.loader.stop();
    //     this.toastr.error('Error verifying voter', 'Error');
    //   }
    // });
  }

  open_OTP_Modal() {
    const modal = new bootstrap.Modal(this.otpModal.nativeElement, {
      backdrop: 'static',
      keyboard: false,
    });
    modal.show();
  }

  close_OTP_Modal() {
    const modal = bootstrap.Modal.getInstance(this.otpModal.nativeElement);
    modal?.hide();
  }

  onKeyUp(event: KeyboardEvent, index: number) {
    const input = event.target as HTMLInputElement;
    if (/^\d$/.test(input.value)) {
      this.otp[index] = input.value;
      const nextInput = document.querySelector(
        `#otp input:nth-child(${index + 2}`
      ) as HTMLInputElement;
      if (nextInput) nextInput.focus();
    } else {
      input.value = '';
    }
    if (event.key === 'Backspace' && index > 0) {
      const prevInput = document.querySelector(
        `#otp input:nth-child(${index})`
      ) as HTMLInputElement;
      if (prevInput) prevInput.focus();
    }
  }

  isOtpComplete(): boolean {
    return this.otp.every((d) => d !== '');
  }

  SubmitOtpVoter() {
    const otpStr = this.otp.join('');
    if (otpStr.length !== 6) {
      this.toastr.error('Enter valid 6-digit OTP', 'Error');
      return;
    }
    const client_id = sessionStorage.getItem('voter_client_id') || '';
    // Uncomment when API is ready
    // this.kycService.Verify_Voter_Submit_OTP({ client_id, otp: otpStr }).subscribe({
    //   next: res => {
    //     if (res.isSuccess) {
    //       this.toastr.success(res.message || 'Voter verified successfully', 'Success');
    //       this.Isverifyvoter = true;
    //       this.close_OTP_Modal();
    //     } else { this.toastr.error(res.message || 'Invalid OTP', 'Error'); }
    //   },
    //   error: () => { this.toastr.error('Error submitting OTP', 'Error'); }
    // });
  }

  /**
   * Clear Voter fields and reset upload on invalid document
   */
  clearVoterFields(fileType: string, errorMessage?: string): void {
    if (fileType === 'VoterFrontPhotoFile') {
      this.voterForm.patchValue({
        VoterFrontPhotoFile: null,
        VoterNo: '',
        VoterName: '',
        VoterDOB: ''
      });
      delete this.fileName['VoterFrontPhotoFile'];
      this.previewFrontImage = null;
    } else if (fileType === 'VoterBackPhotoFile') {
      this.voterForm.patchValue({
        VoterBackPhotoFile: null,
        VoterAddress: ''
      });
      delete this.fileName['VoterBackPhotoFile'];
      this.previewBackImage = null;
    }
    if (errorMessage) {
      this.ocrError[fileType] = errorMessage;
      this.toastr.error(errorMessage, 'Invalid Document');
    }
    this.cdr.detectChanges();
  }

  /**
   * Process Voter ID image with Tesseract OCR
   */
  async processVoterOCR(file: File, fileType: string): Promise<void> {
    this.isScanning = true;
    this.isScanningPerFile[fileType] = true;
    this.ocrError[fileType] = '';
    this.cdr.detectChanges();

    try {
      const result = await Tesseract.recognize(file, 'eng');

      this.zone.run(() => {
        const rawText = result.data.text || '';
        const upperText = rawText.toUpperCase();

        console.log(`Voter OCR (${fileType}) Confidence: ${result.data.confidence}%, Text length: ${rawText.length}`);
        console.log('Extracted Text:', rawText);

        // Cross-document checks
        const isAadhaar = /AADHAAR|आधार|MERA\s+AADHAAR|UNIQUE\s+IDENTIFICATION/i.test(upperText);
        const isPan = /INCOME\s+TAX|PERMANENT\s+ACCOUNT/i.test(upperText);

        if (isAadhaar) {
          this.clearVoterFields(fileType, 'Wrong document uploaded! You uploaded an Aadhaar card instead of a Voter ID.');
          return;
        }

        if (isPan) {
          this.clearVoterFields(fileType, 'Wrong document uploaded! You uploaded a PAN card instead of a Voter ID.');
          return;
        }

        if (fileType === 'VoterFrontPhotoFile') {
          // 1. Voter ID / EPIC Number
          let voterNo = '';
          const epicRegex = /\b([A-Z]{3})[\s\-\.]*([0-9]{7})\b/;
          const match = upperText.match(epicRegex);
          if (match) {
            voterNo = `${match[1]}${match[2]}`;
          }

          if (!voterNo) {
            const stripped = upperText.replace(/[^A-Z0-9]/g, '');
            const sm = stripped.match(/[A-Z]{3}[0-9]{7}/);
            if (sm) voterNo = sm[0];
          }

          if (!voterNo) {
            // Check alternate voter ID formats: e.g., 2-4 letters followed by 6-8 numbers, or separated by slash
            const altRegex = /\b([A-Z]{2,4}[0-9]{6,8})\b|\b([A-Z]{2,3}\/[0-9]{2}\/[0-9]{2,3}\/[0-9]{4,6})\b/;
            const altMatch = upperText.match(altRegex);
            if (altMatch) {
              voterNo = altMatch[0];
            } else {
              // 10-char token fallback with character substitutions
              const words = upperText.split(/\s+/);
              for (const w of words) {
                const clean = w.replace(/[^A-Z0-9]/g, '');
                if (clean.length === 10) {
                  const chars = clean.split('');
                  const d2l: { [k: string]: string } = { '0': 'O', '1': 'I', '5': 'S', '8': 'B', '2': 'Z' };
                  const l2d: { [k: string]: string } = { 'O': '0', 'I': '1', 'L': '1', 'S': '5', 'B': '8', 'Z': '2' };
                  for (let i = 0; i < 3; i++) if (/\d/.test(chars[i])) chars[i] = d2l[chars[i]] || chars[i];
                  for (let i = 3; i < 10; i++) if (/[A-Z]/.test(chars[i])) chars[i] = l2d[chars[i]] || chars[i];
                  const fixed = chars.join('');
                  if (/^[A-Z]{3}[0-9]{7}$/.test(fixed)) {
                    voterNo = fixed;
                    break;
                  }
                }
              }
            }
          }

          const hasVoterKeywords = /ELECTION\s+COMMISSION|ELECTOR\s+PHOTO|IDENTITY\s+CARD|निर्वाचन\s+आयोग|पहचान\s+पत्र|EPIC/i.test(upperText);

          // Validation: If no voterNo and no voter keywords, reject
          if (!voterNo && !hasVoterKeywords) {
            this.clearVoterFields(fileType, 'Invalid document format. Voter ID Number not detected. Please upload a valid Voter ID card.');
            return;
          }

          if (voterNo) {
            this.voterForm.patchValue({ VoterNo: voterNo });
            this.voterForm.get('VoterNo')?.markAsDirty();
            this.voterForm.get('VoterNo')?.markAsTouched();
            this.toastr.success(`Voter ID Number detected: ${voterNo}`, 'OCR Success');
          } else if (hasVoterKeywords) {
            this.toastr.info('Voter ID detected. Please verify or enter Voter ID Number manually if needed.', 'OCR Info');
          }

          // 2. Name Extraction
          const lines = rawText.split(/\r?\n/).map(l => l.trim()).filter(l => l.length > 1);

          const isValidVoterName = (str: string) => {
            if (!str || str.length < 3 || str.length > 50) return false;
            const up = str.toUpperCase().trim();
            if (/^(?:NAME|ELECTOR|CARDHOLDER|HOLDER|APPLICANT|SIGNATURE|PHOTO)$/i.test(up)) return false;
            if (/ELECTION|COMMISSION|ELECTOR|IDENTITY|CARD|EPIC|INDIA|GOVT|FATHER|HUSBAND|MOTHER|DATE|BIRTH|DOB|SEX|MALE|FEMALE|ADDRESS/i.test(up)) return false;
            if (/^[X\s]+$/i.test(up) || /^[0-9\s]+$/.test(up)) return false;
            const clean = str.replace(/[^A-Za-z]/g, '');
            if (clean.length < 3) return false;
            const distinct = new Set(clean.toUpperCase().split(''));
            if (distinct.size < 2) return false;
            return true;
          };

          let detectedName = '';

          // Tier 1: Look for explicit 'Name : ...' or 'Elector\'s Name : ...' (skipping Father/Husband lines)
          for (const line of lines) {
            if (!/Father|पिता|Husband|पति|Mother|माता|Fiiners|Falher|Fathar/i.test(line)) {
              const match = line.match(/(?:^|[^\w])(?:Name|Elector\'?s?\s*Name)\s*[\:\.\-\/\s]+\s*([A-Za-z][A-Za-z\s\.\']{2,})/i);
              if (match && match[1]) {
                const cand = match[1].replace(/^(?:Name|Elector\'?s?\s*Name)[\:\.\-\/\s]*/i, '').replace(/[^A-Za-z\s\.]/g, '').trim();
                if (isValidVoterName(cand)) {
                  detectedName = cand.toUpperCase();
                  break;
                }
              }
            }
          }

          // Tier 2: Look for line immediately following a standalone 'Name' or 'Elector\'s Name' or 'नाम' line
          if (!detectedName) {
            for (let i = 0; i < lines.length - 1; i++) {
              const line = lines[i];
              if (/\b(?:Name|नाम|Elector\'?s?\s*Name)\b/i.test(line) && !/Father|पिता|Husband|पति|Mother|माता/i.test(line)) {
                const nextLine = lines[i + 1].replace(/.*(?:Name|नाम)[\:\.\-\/\s]*/i, '').replace(/[^A-Za-z\s\.]/g, '').trim();
                if (isValidVoterName(nextLine)) {
                  detectedName = nextLine.toUpperCase();
                  break;
                }
              }
            }
          }

          // Tier 3: Look above Father's Name / Husband's Name line
          if (!detectedName) {
            const fatherIdx = lines.findIndex(l => /FATHER|पिता|HUSBAND|पति|FIINERS|FALHER|FATHAR/i.test(l));
            if (fatherIdx > 0) {
              for (let k = fatherIdx - 1; k >= Math.max(0, fatherIdx - 3); k--) {
                if (/ELECTION|COMMISSION|ELECTOR|IDENTITY|CARD|EPIC|INDIA|भारत|निर्वाचन/i.test(lines[k])) continue;
                if (/[A-Z]{3}[0-9]{7}/.test(lines[k])) continue;
                const cand = lines[k].replace(/.*(?:Name|नाम)[\:\.\-\/\s]*/i, '').replace(/[^A-Za-z\s\.]/g, '').trim();
                if (isValidVoterName(cand)) {
                  detectedName = cand.toUpperCase();
                  break;
                }
              }
            }
          }

          // Tier 4: Look between EPIC/Header and Father/Sex/DOB lines
          if (!detectedName) {
            const epicIdx = lines.findIndex(l => /[A-Z]{3}[0-9]{7}/.test(l) || /EPIC|ELECTOR\s+PHOTO/i.test(l));
            const start = epicIdx >= 0 ? epicIdx + 1 : 0;
            for (let i = start; i < lines.length; i++) {
              if (/ELECTION|COMMISSION|ELECTOR|IDENTITY|CARD|EPIC|INDIA|भारत|निर्वाचन|MALE|FEMALE/i.test(lines[i])) continue;
              if (/Father|पिता|Husband|पति|Mother|माता|Fiiners|Falher/i.test(lines[i])) continue;
              const cand = lines[i].replace(/.*(?:Name|नाम)[\:\.\-\/\s]*/i, '').replace(/[^A-Za-z\s\.]/g, '').trim();
              if (isValidVoterName(cand)) {
                detectedName = cand.toUpperCase();
                break;
              }
            }
          }

          if (detectedName) {
            this.voterForm.patchValue({ VoterName: detectedName });
            this.voterForm.get('VoterName')?.markAsDirty();
            this.voterForm.get('VoterName')?.markAsTouched();
          }

          // 3. DOB Extraction
          const dobMatch = upperText.match(/\b([0-3]?[0-9])[\/\.\-]([0-1]?[0-9])[\/\.\-](19\d{2}|20\d{2})\b/);
          if (dobMatch) {
            const dd = dobMatch[1].padStart(2, '0');
            const mm = dobMatch[2].padStart(2, '0');
            const yyyy = dobMatch[3];
            this.voterForm.patchValue({ VoterDOB: `${yyyy}-${mm}-${dd}` });
          } else {
            const isoDobMatch = upperText.match(/\b(19\d{2}|20\d{2})[\/\.\-]([0-1]?[0-9])[\/\.\-]([0-3]?[0-9])\b/);
            if (isoDobMatch) {
              const yyyy = isoDobMatch[1];
              const mm = isoDobMatch[2].padStart(2, '0');
              const dd = isoDobMatch[3].padStart(2, '0');
              this.voterForm.patchValue({ VoterDOB: `${yyyy}-${mm}-${dd}` });
            }
          }

          this.ocrError[fileType] = '';
          this.toastr.success('Voter ID details extracted successfully! Please review.', 'OCR Complete');

        } else if (fileType === 'VoterBackPhotoFile') {
          // Back side processing - look for Address & PIN code
          const pinRegex = /\b[1-9][0-9]{5}\b/;
          const hasPin = pinRegex.test(rawText);
          const hasAddressKeyword = /ADDRESS|पता|ELECTORAL|REGISTRATION|ASSEMBLY|निर्वाचन|मतदाता/i.test(upperText);

          if (!hasPin && !hasAddressKeyword) {
            this.clearVoterFields(fileType, 'Invalid document format. Voter ID back side details not detected.');
            return;
          }

          // Extract Address
          let address = '';
          const addrMatch = rawText.match(/(?:Address|पता)\s*[\:\.\-]+\s*([\s\S]+?)(?:Date|दिनांक|Place|स्थान|Electoral|निर्वाचक|$)/i);
          if (addrMatch && addrMatch[1]) {
            address = addrMatch[1].replace(/[\r\n]+/g, ', ').replace(/\s+/g, ' ').trim();
          }

          if (!address && hasPin) {
            // Find lines leading to the PIN code
            const lines = rawText.split(/\r?\n/).map(l => l.trim()).filter(l => l.length > 3);
            const pinIdx = lines.findIndex(l => pinRegex.test(l));
            if (pinIdx >= 0) {
              const startIdx = Math.max(0, pinIdx - 3);
              address = lines.slice(startIdx, pinIdx + 1).join(', ').replace(/\s+/g, ' ').trim();
            }
          }

          if (address) {
            address = address.replace(/^[\,\.\-\:\s]+/, '').replace(/[\,\.\-\:\s]+$/, '');
            this.voterForm.patchValue({ VoterAddress: address });
            this.toastr.success('Address extracted from Voter ID back!', 'OCR Complete');
          }

          this.ocrError[fileType] = '';
        }
      });
    } catch (error) {
      console.error('Voter OCR Error:', error);
      this.zone.run(() => {
        this.clearVoterFields(fileType, 'OCR processing failed. Please enter details manually.');
      });
    } finally {
      this.zone.run(() => {
        this.isScanningPerFile[fileType] = false;
        this.isScanning = Object.values(this.isScanningPerFile).some(s => s === true);
        this.cdr.detectChanges();
      });
    }
  }

  onFileSelected(event: any, key: string) {
    const file = event.target.files[0];
    if (!file) return;

    if (!['image/jpeg', 'image/jpg', 'image/png'].includes(file.type)) {
      this.toastr.error('Only JPG/PNG allowed', 'Error');
      return;
    }

    if (file.size > 5 * 1024 * 1024) {
      this.toastr.error('Max size 5MB', 'Error');
      return;
    }

    this.voterForm.patchValue({ [key]: file });
    this.fileName[key] = file.name;

    const reader = new FileReader();
    reader.onload = () => {
      if (key === 'VoterFrontPhotoFile') {
        this.previewFrontImage = reader.result as string;
      } else if (key === 'VoterBackPhotoFile') {
        this.previewBackImage = reader.result as string;
      }
    };
    reader.readAsDataURL(file);

    // Trigger OCR scan if enabled
    if (this.companyConfig?.voterOcr) {
      this.processVoterOCR(file, key);
    }
  }

  loadImageToView(filename: string, type: 'front' | 'back') {
    this.kycService.getImageOnboard(filename).subscribe({
      next: (blob) => {
        const reader = new FileReader();
        reader.onload = () => {
          if (type === 'front') {
            this.originalFrontUrl = reader.result as string;
            this.voterData.voterFrontPhoto = this.originalFrontUrl;
          } else {
            this.originalBackUrl = reader.result as string;
            this.voterData.voterBackPhoto = this.originalBackUrl;
          }
        };
        reader.readAsDataURL(blob);
      },
    });
  }

  OnSubmit() {
    this.submitted = true;

    if (this.isVoterVerified) {
      if (!this.Isverifyvoter) {
        this.toastr.warning('Please verify Voter ID first', 'Warning');
        return;
      }
    }

    if (this.voterForm.invalid) return;

    const fd = new FormData();
    fd.append('pk_recId', this.pk_recId);
    fd.append('VoterNo', this.voterForm.get('VoterNo')?.value);
    fd.append('VoterName', this.voterForm.get('VoterName')?.value);
    fd.append('VoterDOB', this.voterForm.get('VoterDOB')?.value);
    fd.append('VoterAddress', this.voterForm.get('VoterAddress')?.value);

    const frontFile = this.voterForm.get('VoterFrontPhotoFile')?.value;
    const backFile = this.voterForm.get('VoterBackPhotoFile')?.value;
    
    if (frontFile) fd.append('VoterFrontPhotoFile', frontFile);
    if (backFile) fd.append('VoterBackPhotoFile', backFile);

    this.loader.start();
    this.kycService.verifyVoter(fd).subscribe({
      next: (res) => {
        this.loader.stop();
        if (res.isSuccess) {
          this.toastr.success(res.message || 'Voter details saved', 'Success');
          this.loadVoterDetails();
          this.isViewMode = true;
          
          window.dispatchEvent(new Event('refresh-onboarding-status'));
        } else {
          this.toastr.error(res.message || 'Failed to save', 'Error');
        }
      },
      error: () => {
        this.loader.stop();
        this.toastr.error('Error saving voter details', 'Error');
      },
    });
  }

  reset() {
    this.voterForm.reset();
    this.submitted = false;
    this.fileName = {};
    this.Isverifyvoter = false;
    this.previewFrontImage = null;
    this.previewBackImage = null;
    this.isScanning = false;
    this.isScanningPerFile = {};
    this.ocrError = {};
  }

  goBack() {
    this.router.navigate(['/dash/setting']);
  }
}