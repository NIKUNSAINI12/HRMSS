import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { ActivatedRoute, Router } from '@angular/router';
import { ToastrService } from 'ngx-toastr';
import { environment } from '../../../../../environments/environment';

import { OnboardingService } from '../Onboarding.service';
import { CandidateMasterService } from '../../recruitment/RecruitServices/candidate-master.service';
import { CompanyConfig, CompanyConfigService } from '../../../../on_boarding/services/company-config.service';
import { EncryptionService } from '../../../../shared/services/encryption.service';

// Define proper interfaces
interface BasicInfo {
  pk_recId: string;
  candidate_name: string;
  email: string;
  mobile: string;
  stateId?: string;
  stateName?: string;
  cityId?: string;
  cityName?: string;
  pincode?: string;
  address?: string;
  photo?: string;
  isVendor?: boolean | number;
  vendor_Code?: string;
  vendor_Status?: string;
  onboardFormStatusName?: string;
  OnboardFormStatusName?: string;
  onboardformstatusname?: string;
  onboardFormStatus?: string;
  onboardFormStatusId?: number;
  dlNo?: string;
  dlPhoto?: string;
  eshram_UAN?: string;
  eshram_Photo?: string;
  ayushman_PMJAY_ID?: string;
  ayushman_Photo?: string;
}

interface AadhaarDetails {
  pk_recId: string;
  aadhaarNo?: string;
  aadhaarName?: string;
  aadhaarDob?: string;
  aadhaarAddress?: string;
  aadhaarFront?: string;
  aadhaarBack?: string;
  fatherAadhaarFront?: string;
  fatherAadhaarBack?: string;
  entryDate?: string;
}

interface PANDetails {
  pk_recId: string;
  panNo?: string;
  panName?: string;
  panDob?: string;
  panCard?: string;
  entryDate?: string;
}

interface QualificationDetails {
  pk_cqualid: number;
  qualification: string;
  subject?: string;
  institute: string;
  passyear: number;
  marks: number;
  division: string;
  documentupload?: string;
}

interface ExperienceDetails {
  pk_cpjobid: number;
  compname: string;
  designation: string;
  department?: string;
  fromdate: string;
  todate: string;
  ctc: number;
  documentupload?: string;
  profile?: string;
  leavingreason?: string;
}

interface FamilyDetails {
  fk_recId: string;
  membername: string;
  relation: string;
  dob: string;
  qualification?: string;
  occupation?: string;
}

interface BankDetails {
  bankName: string;
  accountNo: string;
  ifscCode: string;
  branchName: string;
  passbookPhoto: string;
}

interface VoterDetails {
  pk_recId: string;
  voterNo: string;
  voterName: string;
  voterAddress: string;
  voterDOB: string;
  voterFrontPhoto: string;
  voterBackPhoto: string;
}

interface CandidateSummary {
  basicInfo: BasicInfo | null;
  aadhaarDetails: AadhaarDetails | null;
  panDetails: PANDetails | null;
  qualifications: QualificationDetails[];
  experience: ExperienceDetails[];
  family: FamilyDetails[];
  bankDetails: BankDetails | null;
  voterDetails: VoterDetails | null;
  vendorGstDetails?: any;
  vendorAgreement?: any;
  vendorActiveRateCards?: any[];
  drivingLicenceData?: any;
}

@Component({
  selector: 'app-onboard-candidate-view',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './onboard-candidate-view.component.html',
  styleUrl: './onboard-candidate-view.component.scss'
})
export class OnboardCandidateViewComponent implements OnInit {
  isLoading: boolean = true;
  candidateId: string = '';
  candidateName: string = '';
  currentStatusName: string = '';
  isDownloading: boolean = false;
  isVendor: boolean = false;
  todayDateFormatted: string = '';

  // Status Confirmation Modals
  showVerifyConfirmModal: boolean = false;
  isVerifyingStatus: boolean = false;
  showReInitiateConfirmModal: boolean = false;
  isReInitiatingStatus: boolean = false;

  // Dynamic Progress Calculation
  progressPercentage: number = 0;
  completedStepsCount: number = 0;
  totalVisibleStepsCount: number = 0;

  // Company Config
  companyConfig: CompanyConfig | null = null;

  imageUrls = {
    profilePhoto: '',
    aadhaarFront: '',
    aadhaarBack: '',
    fatherAadhaarFront: '',
    fatherAadhaarBack: '',
    panCard: '',
    voterFrontPhoto: '',
    voterBackPhoto: '',
    passbookPhoto: '',
    dlPhoto: '',
    gstPhoto: '',
    signaturePhoto: '',
    recentPhoto: '',
    eshramPhoto: '',
    ayushmanPhoto: '',
    vehicleInsurancePhoto: '',
    vehicleRCPhoto: '',
  };

  drivingLicenceData: any = null;
  vendorGstData: any = null;
  vendorAgreement: any = null;
  vendorActiveRateCards: any[] = [];

  candidateSummary: CandidateSummary = {
    basicInfo: null,
    aadhaarDetails: null,
    panDetails: null,
    qualifications: [],
    experience: [],
    family: [],
    bankDetails: null,
    voterDetails: null,
    vendorGstDetails: null,
    vendorAgreement: null,
    vendorActiveRateCards: []
  };

  // Image Modal State
  modalOpen: boolean = false;
  modalImageUrl: string = '';
  modalImageTitle: string = '';

  constructor(
    private route: ActivatedRoute,
    private router: Router,
    private onboardingService: OnboardingService,
    private Service: CandidateMasterService,
    private toastrService: ToastrService,
    private companyConfigService: CompanyConfigService,
    private encryptionService: EncryptionService,
    private http: HttpClient
  ) {}

  ngOnInit(): void {
    const today = new Date();
    const day = String(today.getDate()).padStart(2, '0');
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    this.todayDateFormatted = `${day}-${months[today.getMonth()]}-${today.getFullYear()}`;

    this.route.params.subscribe(params => {
      this.candidateId = this.encryptionService.decryptText(this.route.snapshot.params['id'].toString());
      if (this.candidateId) {
        this.loadCandidateData();
        this.loadCompanyConfig();
      } else {
        this.toastrService.error('No candidate ID provided');
        this.goBack();
      }
    });
  }

  loadCompanyConfig(): void {
    this.companyConfig = this.companyConfigService.getConfig();

    if (!this.companyConfig) {
      this.onboardingService.getOnboardingMandatoryDetails(this.candidateId).subscribe({
        next: (res) => {
          if (res.isSuccess && res.data) {
            this.companyConfig = res.data;
            this.companyConfigService.setConfig(res.data);
          } else {
            this.companyConfig = this.companyConfigService.getDefaultConfig();
          }
          this.calculateProgress();
        },
        error: () => {
          this.companyConfig = this.companyConfigService.getDefaultConfig();
          this.calculateProgress();
        },
      });
    } else {
      this.calculateProgress();
    }
  }

  loadCandidateData(): void {
    this.isLoading = true;

    this.onboardingService.getCandidateFinalSummary(this.candidateId).subscribe({
      next: (res) => {
        if (res.isSuccess && res.data) {
          this.candidateSummary = {
            basicInfo: res.data.basicInfo || null,
            aadhaarDetails: res.data.aadhaarDetails || null,
            panDetails: res.data.panDetails || null,
            qualifications: res.data.qualifications || [],
            experience: res.data.experience || [],
            family: res.data.family || [],
            bankDetails: res.data.bankDetails || null,
            voterDetails: res.data.voterDetails || null,
            vendorGstDetails: res.data.vendorGstDetails || null,
            vendorAgreement: res.data.vendorAgreement || null,
            vendorActiveRateCards: res.data.vendorActiveRateCards || [],
            drivingLicenceData: res.data.drivingLicenceData || null
          };

          this.candidateName = res.data.basicInfo?.candidate_name || 'Candidate';
          this.currentStatusName = res.data.basicInfo?.vendor_Status 
            || res.data.basicInfo?.onboardFormStatusName 
            || res.data.basicInfo?.OnboardFormStatusName 
            || res.data.basicInfo?.onboardformstatusname 
            || res.data.basicInfo?.onboardFormStatus 
            || '';
            
          this.isVendor = !!res.data.basicInfo?.vendor_Code 
            || !!res.data.basicInfo?.vendor_Status 
            || (res.data.basicInfo?.type?.toLowerCase() === 'vendor')
            || !!(res.data.basicInfo?.isVendor);

          // Map GST Data
          if (res.data.vendorGstDetails) {
            this.vendorGstData = res.data.vendorGstDetails;
            const gstImg = this.vendorGstData.vendor_GstPhoto || this.vendorGstData.gstPhoto;
            if (gstImg) {
              this.loadImage(gstImg, 'gstPhoto');
            }
          }

          // Map Agreement Data
          if (res.data.vendorAgreement) {
            this.vendorAgreement = res.data.vendorAgreement;
            if (res.data.vendorAgreement.isVendor) {
              this.isVendor = true;
            }
            const sigImg = this.vendorAgreement.signaturePhoto || this.vendorAgreement.vendor_SignaturePhoto;
            if (sigImg) {
              this.loadImage(sigImg, 'signaturePhoto');
            }
          }

          // Map Active Rate Cards
          if (res.data.vendorActiveRateCards && res.data.vendorActiveRateCards.length > 0) {
            this.vendorActiveRateCards = this.mapAgreementActiveRateCards(res.data.vendorActiveRateCards);
          } else if (res.data.vendorAgreement && (res.data.vendorAgreement.fhrid || res.data.vendorAgreement.vendor_HFRID)) {
            this.vendorActiveRateCards = this.mapAgreementActiveRateCards([res.data.vendorAgreement]);
          } else {
            this.vendorActiveRateCards = [];
          }

          // Map Driving Licence Data
          if (res.data.drivingLicenceData) {
            this.drivingLicenceData = res.data.drivingLicenceData;
            if (this.drivingLicenceData.dlPhoto) {
              this.loadImage(this.drivingLicenceData.dlPhoto, 'dlPhoto');
            }
            if (this.drivingLicenceData.vehicle_Insurance_Photo) {
              this.loadImage(this.drivingLicenceData.vehicle_Insurance_Photo, 'vehicleInsurancePhoto');
            }
            if (this.drivingLicenceData.vehicle_RC_Photo) {
              this.loadImage(this.drivingLicenceData.vehicle_RC_Photo, 'vehicleRCPhoto');
            }
          }

          this.loadImages();
          this.calculateProgress();
        } else {
          this.toastrService.error(res.message || 'Failed to load candidate data');
        }
        this.isLoading = false;
      },
      error: (error) => {
        this.toastrService.error('Failed to load candidate data');
        this.isLoading = false;
        console.error('Error loading candidate:', error);
      }
    });
  }

  getAgreementProp(obj: any, key: string): any {
    if (!obj) return null;
    const lowerKey = key.toLowerCase();
    for (const k of Object.keys(obj)) {
      if (k.toLowerCase() === lowerKey) return obj[k];
    }
    return null;
  }

  getAgreementRateConfig(item: any, label: string, prefix: string, valKey: string = prefix + '_Rate'): any {
    const type = this.getAgreementProp(item, prefix + '_RateType');
    if (!type) return null;

    const isSlab = (type || '').toString().toLowerCase() === 'slab';
    const isFixed = (type || '').toString().toLowerCase() === 'fixed';

    let val = '';
    if (isSlab) {
      val = this.getAgreementProp(item, prefix + '_SlabExpr');
    } else {
      val = this.getAgreementProp(item, valKey);
    }

    return {
      label: label,
      type: type,
      isFixed: isFixed,
      isSlab: isSlab,
      value: val
    };
  }

  mapAgreementActiveRateCards(rateCards: any[]): any[] {
    if (!rateCards || rateCards.length === 0) return [];
    const mapped = rateCards.map((item: any) => {
      const rates = [];
      const normal = this.getAgreementRateConfig(item, 'Normal', 'Normal');
      if (normal) rates.push(normal);
      const pickup = this.getAgreementRateConfig(item, 'Pickup', 'Pickup');
      if (pickup) rates.push(pickup);
      const mfn = this.getAgreementRateConfig(item, 'MFN', 'MFN');
      if (mfn) rates.push(mfn);
      const van = this.getAgreementRateConfig(item, 'Van', 'Van');
      if (van) rates.push(van);
      const u2s = this.getAgreementRateConfig(item, 'U2S', 'U2S');
      if (u2s) rates.push(u2s);
      const shopsy = this.getAgreementRateConfig(item, 'Shopsy', 'Shopsy', 'Shopsy_Rate');
      if (shopsy) rates.push(shopsy);
      const prexo = this.getAgreementRateConfig(item, 'Prexo', 'Prexo');
      if (prexo) rates.push(prexo);
      const grocery = this.getAgreementRateConfig(item, 'Grocery', 'Grocery');
      if (grocery) rates.push(grocery);

      const fhrName = this.getAgreementProp(item, 'fhrid') || this.getAgreementProp(item, 'vendor_hfrid') || '';
      const clientName = this.getAgreementProp(item, 'clientname') || '';
      const modelName = this.getAgreementProp(item, 'modelname') || '';
      const location = this.getAgreementProp(item, 'locationname') || this.getAgreementProp(item, 'location') || '';
      const effFrom = this.getAgreementProp(item, 'effectivefrom') || '';
      const activeRaw = this.getAgreementProp(item, 'isactive');
      const isActive = activeRaw !== null && activeRaw !== undefined ? activeRaw : true;

      return {
        fhrid: fhrName,
        name: fhrName,
        clientName: clientName,
        modelName: modelName,
        location: location,
        effectiveFrom: effFrom,
        isActive: isActive,
        rates: rates
      };
    });

    const activeOnly = mapped.filter((x: any) => x.isActive);
    const grouped = new Map<string, any>();
    activeOnly.forEach((item: any) => {
      const key = `${item.clientName}_${item.modelName}_${item.location}_${item.fhrid}`;
      const effDate = new Date(item.effectiveFrom || 0).getTime();
      if (!grouped.has(key)) {
        grouped.set(key, item);
      } else {
        const existing = grouped.get(key);
        const existingEffDate = new Date(existing.effectiveFrom || 0).getTime();
        if (effDate > existingEffDate) {
          grouped.set(key, item);
        }
      }
    });

    return Array.from(grouped.values()).sort((a: any, b: any) => {
      const dateA = new Date(a.effectiveFrom || 0).getTime();
      const dateB = new Date(b.effectiveFrom || 0).getTime();
      return dateB - dateA;
    });
  }

  loadImages(): void {
    if (this.candidateSummary.basicInfo?.photo) {
      this.loadImage(this.candidateSummary.basicInfo.photo, 'profilePhoto');
    }

    if (this.candidateSummary.aadhaarDetails?.aadhaarFront) {
      this.loadImage(this.candidateSummary.aadhaarDetails.aadhaarFront, 'aadhaarFront');
    }

    if (this.candidateSummary.aadhaarDetails?.aadhaarBack) {
      this.loadImage(this.candidateSummary.aadhaarDetails.aadhaarBack, 'aadhaarBack');
    }

    if (this.candidateSummary.aadhaarDetails?.fatherAadhaarFront) {
      this.loadImage(this.candidateSummary.aadhaarDetails.fatherAadhaarFront, 'fatherAadhaarFront');
    }

    if (this.candidateSummary.aadhaarDetails?.fatherAadhaarBack) {
      this.loadImage(this.candidateSummary.aadhaarDetails.fatherAadhaarBack, 'fatherAadhaarBack');
    }

    if (this.candidateSummary.panDetails?.panCard) {
      this.loadImage(this.candidateSummary.panDetails.panCard, 'panCard');
    }

    if (this.candidateSummary.voterDetails?.voterFrontPhoto) {
      this.loadImage(this.candidateSummary.voterDetails.voterFrontPhoto, 'voterFrontPhoto');
    }

    if (this.candidateSummary.voterDetails?.voterBackPhoto) {
      this.loadImage(this.candidateSummary.voterDetails.voterBackPhoto, 'voterBackPhoto');
    }

    if (this.candidateSummary.bankDetails?.passbookPhoto) {
      this.loadImage(this.candidateSummary.bankDetails.passbookPhoto, 'passbookPhoto');
    }

    const gstImg = this.candidateSummary.vendorGstDetails?.vendor_GstPhoto || this.candidateSummary.vendorGstDetails?.gstPhoto;
    if (gstImg) {
      this.loadImage(gstImg, 'gstPhoto');
    }

    const dlImg = (this.candidateSummary.basicInfo as any)?.dlPhoto || this.drivingLicenceData?.dlPhoto;
    if (dlImg) {
      this.loadImage(dlImg, 'dlPhoto');
    }

    if (this.drivingLicenceData?.vehicle_Insurance_Photo) {
      this.loadImage(this.drivingLicenceData.vehicle_Insurance_Photo, 'vehicleInsurancePhoto');
    }

    if (this.drivingLicenceData?.vehicle_RC_Photo) {
      this.loadImage(this.drivingLicenceData.vehicle_RC_Photo, 'vehicleRCPhoto');
    }

    if (this.candidateSummary.basicInfo?.eshram_Photo) {
      this.loadImage(this.candidateSummary.basicInfo.eshram_Photo, 'eshramPhoto');
    }

    if (this.candidateSummary.basicInfo?.ayushman_Photo) {
      this.loadImage(this.candidateSummary.basicInfo.ayushman_Photo, 'ayushmanPhoto');
    }

    const sigImg = this.candidateSummary.vendorAgreement?.signaturePhoto 
      || this.candidateSummary.vendorAgreement?.vendor_SignaturePhoto
      || this.candidateSummary.vendorGstDetails?.vendor_SignaturePhoto;
    if (sigImg) {
      this.loadImage(sigImg, 'signaturePhoto');
    }
  }

  loadImage(filename: string, imageType: keyof typeof this.imageUrls): void {
    if (!filename) return;
    this.Service.getImage(filename).subscribe({
      next: (blob) => {
        const reader = new FileReader();
        reader.onload = () => {
          this.imageUrls[imageType] = reader.result as string;
        };
        reader.readAsDataURL(blob);
      },
      error: (err: any) => {
        console.error(`Failed to load ${imageType}:`, err);
      }
    });
  }

  downloadPDF(): void {
    if (!this.candidateId) {
      this.toastrService.error('Candidate ID is missing', 'Error');
      return;
    }

    this.isDownloading = true;
    this.toastrService.info('Downloading PDF...', 'Please Wait');

    const url = `${environment.baseURL1}/CandidateExperienceDetails/download-onboarding-pdf/${encodeURIComponent(this.candidateId)}`;

    this.http.get(url, { responseType: 'blob', observe: 'response' }).subscribe({
      next: (response) => {
        this.isDownloading = false;
        const blob = response.body;
        if (!blob) {
          this.toastrService.error('Failed to download PDF: empty response', 'Error');
          return;
        }

        let fileName = `Onboarding_${(this.candidateName || 'Candidate').replace(/\s+/g, '_')}_${Date.now()}.pdf`;
        const contentDisposition = response.headers.get('content-disposition');
        if (contentDisposition) {
          const fileNameMatch = contentDisposition.match(/filename[^;=\n]*=((['"]).*?\2|[^;\n]*)/);
          if (fileNameMatch && fileNameMatch[1]) {
            fileName = fileNameMatch[1].replace(/['"]/g, '').trim();
          }
        }

        const downloadUrl = window.URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = downloadUrl;
        link.download = fileName;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        window.URL.revokeObjectURL(downloadUrl);

        this.toastrService.success('PDF downloaded successfully!', 'Success');
      },
      error: (err) => {
        this.isDownloading = false;
        console.error('Error downloading PDF:', err);
        this.toastrService.error('Failed to download PDF', 'Error');
      }
    });
  }

  goBack(): void {
    const source = this.route.snapshot.queryParams['source'];
    if (source === 'vendor_master') {
      this.router.navigate(['/dash/vendor_management/vendor_managementdashboard/vendor_master_form_list']);
    } else {
      this.router.navigate(['/dash/on_boarding/on_boardingdashboard'], { queryParams: { type: 'on_boarding' } });
    }
  }

  formatDate(date: string | Date | undefined | null): string {
    if (!date) return 'N/A';
    const d = new Date(date);
    if (isNaN(d.getTime())) return 'N/A';

    const day = String(d.getDate()).padStart(2, '0');
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return `${day} ${months[d.getMonth()]} ${d.getFullYear()}`;
  }

  maskAadhaar(aadhaar: string | undefined): string {
    if (!aadhaar || aadhaar.length < 4) return aadhaar || 'N/A';
    return `XXXX-XXXX-${aadhaar.slice(-4)}`;
  }

  maskPAN(pan: string | undefined): string {
    if (!pan || pan.length < 4) return pan || 'N/A';
    return `XXXXXX${pan.slice(-4)}`;
  }

  maskAccountNumber(accountNo: string | undefined): string {
    if (!accountNo || accountNo.length < 4) return accountNo || 'N/A';
    const visibleDigits = 4;
    const maskedPart = 'X'.repeat(accountNo.length - visibleDigits);
    return `${maskedPart}${accountNo.slice(-visibleDigits)}`;
  }

  formatIndianCurrency(amount: number): string {
    if (!amount) return '0';
    return amount.toLocaleString('en-IN', {
      minimumFractionDigits: 0,
      maximumFractionDigits: 0,
      useGrouping: true,
    });
  }

  updateVendorStatus(statusId: number, statusName: string): void {
    this.promptVerifyVendor();
  }

  promptVerifyVendor(): void {
    this.showVerifyConfirmModal = true;
  }

  closeVerifyConfirmModal(): void {
    if (this.isVerifyingStatus) return;
    this.showVerifyConfirmModal = false;
  }

  confirmAndProceedVerify(): void {
    if (!this.candidateId) return;
    this.isVerifyingStatus = true;

    this.onboardingService.updateVendorStatus(this.candidateId, 5).subscribe({
      next: (res) => {
        this.isVerifyingStatus = false;
        this.showVerifyConfirmModal = false;
        if (res.isSuccess) {
          this.toastrService.success('Vendor status updated to Verified successfully!');
          this.currentStatusName = 'Verified';

          // Automatically download the verified PDF
          this.downloadPDF();
        } else {
          this.toastrService.error(res.message || 'Failed to update status');
        }
      },
      error: () => {
        this.isVerifyingStatus = false;
        this.showVerifyConfirmModal = false;
        this.toastrService.error('An error occurred while updating status');
      }
    });
  }

  reInitiateVendor(): void {
    this.promptReInitiateVendor();
  }

  promptReInitiateVendor(): void {
    this.showReInitiateConfirmModal = true;
  }

  closeReInitiateConfirmModal(): void {
    if (this.isReInitiatingStatus) return;
    this.showReInitiateConfirmModal = false;
  }

  confirmAndProceedReInitiate(): void {
    if (!this.candidateId) return;
    this.isReInitiatingStatus = true;

    this.onboardingService.reInitiateVendorStatus(this.candidateId).subscribe({
      next: (res) => {
        this.isReInitiatingStatus = false;
        this.showReInitiateConfirmModal = false;
        if (res.isSuccess) {
          this.toastrService.success(res.message || 'Vendor Re-Initiated successfully!');
          this.currentStatusName = 'ReInitiated';
        } else {
          this.toastrService.error(res.message || 'Failed to Re-Initiate vendor');
        }
      },
      error: () => {
        this.isReInitiatingStatus = false;
        this.showReInitiateConfirmModal = false;
        this.toastrService.error('An error occurred while re-initiating vendor');
      }
    });
  }

  isVendorSource(): boolean {
    return this.route.snapshot.queryParams['source'] === 'vendor_master';
  }

  openModal(imageUrl: string, title: string): void {
    if (imageUrl) {
      this.modalImageUrl = imageUrl;
      this.modalImageTitle = title;
      this.modalOpen = true;
      document.body.style.overflow = 'hidden';
    }
  }

  closeModal(): void {
    this.modalOpen = false;
    this.modalImageUrl = '';
    this.modalImageTitle = '';
    document.body.style.overflow = '';
  }

  calculateProgress(): void {
    if (!this.companyConfig) {
      this.progressPercentage = 0;
      this.completedStepsCount = 0;
      this.totalVisibleStepsCount = 0;
      return;
    }

    let total = 0;
    let completed = 0;

    // PAN Details
    if (this.companyConfig.panVisible) {
      total++;
      if (this.candidateSummary?.panDetails?.panNo) completed++;
    }

    // Aadhaar Details
    if (this.companyConfig.aadhaarVisible) {
      total++;
      if (this.candidateSummary?.aadhaarDetails?.aadhaarNo) completed++;
    }

    // Basic Information
    if (this.companyConfig.basicInfoVisible) {
      total++;
      if (this.candidateSummary?.basicInfo && (this.candidateSummary.basicInfo.stateId || this.candidateSummary.basicInfo.address)) completed++;
    }

    // Qualification
    if (this.companyConfig.qualificationVisible) {
      total++;
      if (this.candidateSummary?.qualifications && this.candidateSummary.qualifications.length > 0) completed++;
    }

    // Experience
    if (this.companyConfig.experienceVisible) {
      total++;
      if (this.candidateSummary?.experience && this.candidateSummary.experience.length > 0) completed++;
    }

    // Family Details
    if (this.companyConfig.familyVisible) {
      total++;
      if (this.candidateSummary?.family && this.candidateSummary.family.length > 0) completed++;
    }

    // Cancelled Cheque / Bank
    if (this.companyConfig.bankAccountVisible) {
      total++;
      if (this.candidateSummary?.bankDetails?.accountNo) completed++;
    }

    // Driving Licence & Vehicle
    if (this.companyConfig.drivingLicenceVisible) {
      total++;
      if (this.drivingLicenceData?.dlNo || (this.candidateSummary?.basicInfo as any)?.dlNo) completed++;
    }

    // Voter ID
    if (this.companyConfig.voterVisible) {
      total++;
      if (this.candidateSummary?.voterDetails?.voterNo) completed++;
    }

    // Vendor GST Details
    if (this.companyConfig.vendorGstVisible) {
      total++;
      if (this.vendorGstData && (this.vendorGstData.pk_recId || (this.vendorGstData.vendor_IsGSTApplicable !== null && this.vendorGstData.vendor_IsGSTApplicable !== undefined))) {
        const isApp =
          this.vendorGstData.vendor_IsGSTApplicable === true ||
          this.vendorGstData.vendor_IsGSTApplicable === 1 ||
          this.vendorGstData.vendor_IsGSTApplicable === '1' ||
          this.vendorGstData.vendor_IsGSTApplicable === 'true' ||
          String(this.vendorGstData.vendor_IsGSTApplicable || '').toLowerCase() === 'yes';
        if (isApp) {
          const hasPhoto = !!(this.vendorGstData.gstPhoto || this.vendorGstData.GSTPhoto || this.vendorGstData.vendor_GstPhoto || this.imageUrls.gstPhoto);
          const gstNo = (this.vendorGstData.vendor_GSTNo || this.vendorGstData.Vendor_GSTNo || '').trim();
          if (hasPhoto && gstNo) completed++;
        } else {
          completed++;
        }
      }
    }

    // Signature Image
    if (this.companyConfig.signatureVisible) {
      total++;
      if (this.imageUrls.signaturePhoto || this.vendorAgreement?.signaturePhoto || this.vendorAgreement?.vendor_SignaturePhoto) completed++;
    }

    // Recent Photograph
    if (this.companyConfig.photographVisible) {
      total++;
      if (this.imageUrls.profilePhoto || this.candidateSummary?.basicInfo?.photo) completed++;
    }

    // E-Shram Card
    if (this.companyConfig.eshramVisible) {
      total++;
      if (this.candidateSummary?.basicInfo?.eshram_UAN || this.candidateSummary?.basicInfo?.eshram_Photo || this.imageUrls.eshramPhoto) completed++;
    }

    // Ayushman Card
    if (this.companyConfig.ayushmanVisible) {
      total++;
      if (this.candidateSummary?.basicInfo?.ayushman_PMJAY_ID || this.candidateSummary?.basicInfo?.ayushman_Photo || this.imageUrls.ayushmanPhoto) completed++;
    }

    this.totalVisibleStepsCount = total;
    this.completedStepsCount = completed;
    this.progressPercentage = total > 0 ? Math.round((completed / total) * 100) : 0;
  }
}
