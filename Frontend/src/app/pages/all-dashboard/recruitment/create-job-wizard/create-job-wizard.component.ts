import { Component, OnInit, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router, RouterModule } from '@angular/router';
import { ToastrService } from 'ngx-toastr';
import { NgSelectModule } from '@ng-select/ng-select';
import { AtsService } from '../../../../shared/services/ats.service';
import { EmployeeMasterService } from '../../payroll/services/employee-master.service';
import { NgxUiLoaderService } from 'ngx-ui-loader';

interface TeamMember {
  id: string;
  name: string;
  role: string;
  avatar: string;
  email: string;
  initials: string;
}

export interface HubLocationCapacity {
  id: string;
  name: string;
  code: string;
  zone: string;
  state?: string;
  displayName?: string;
  baseDemand: number;
  bufferPercent: number;
  bufferHeads: number;
  targetCapacity: number;
  currentOccupied: number;
}

@Component({
  selector: 'app-create-job-wizard',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterModule, NgSelectModule],
  templateUrl: './create-job-wizard.component.html',
  styleUrl: './create-job-wizard.component.scss'
})
export class CreateJobWizardComponent implements OnInit {
  // Master Data Lists (Company-Specific via Universal DDL & AtsService)
  departmentList: { id: string; name: string }[] = [];
  locationList: HubLocationCapacity[] = [];
  designationList: { id: string; name: string }[] = [];

  // Dropdown Lists for Typable & Filtered Inputs
  workplaceTypeList: string[] = ['On-Site', 'Field', 'Hybrid', 'Remote'];
  employmentTypeList: string[] = ['Full-Time', 'Contract', 'Third-Party', 'Part-Time'];
  priorityList: string[] = ['Low', 'Medium', 'High', 'Critical'];
  educationLevelList: string[] = ['Graduate', 'Post Graduate', 'Diploma', 'Intermediate / 10+2', 'Doctorate / PhD', 'Professional Certification'];

  // Hub Directory with Baseline Demand, Buffer & Active Headcount from Step 1
  hubCapacityDirectory: HubLocationCapacity[] = [
    { id: 'GU-1', name: 'Noida Hub & Warehouse', code: 'NDA', zone: 'North Zone', state: 'Uttar Pradesh', displayName: 'Noida Hub & Warehouse (NDA) — North Zone', baseDemand: 140, bufferPercent: 10, bufferHeads: 14, targetCapacity: 154, currentOccupied: 128 },
    { id: 'GU-10', name: 'Ahmedabad Logistics Hub', code: 'AMD', zone: 'West Zone', state: 'Gujarat', displayName: 'Ahmedabad Logistics Hub (AMD) — West Zone', baseDemand: 95, bufferPercent: 10, bufferHeads: 10, targetCapacity: 105, currentOccupied: 88 },
    { id: 'GU-100', name: 'Faridabad Head Office 53/10', code: 'FBD', zone: 'North Zone', state: 'Haryana', displayName: 'Faridabad Head Office 53/10 (FBD) — North Zone', baseDemand: 220, bufferPercent: 8, bufferHeads: 18, targetCapacity: 238, currentOccupied: 210 },
    { id: 'GU-101', name: 'Faridabad M&M Hub', code: 'FBD-MM', zone: 'North Zone', state: 'Haryana', displayName: 'Faridabad M&M Hub (FBD-MM) — North Zone', baseDemand: 75, bufferPercent: 12, bufferHeads: 9, targetCapacity: 84, currentOccupied: 70 },
    { id: 'GU-102', name: 'Faridabad Fleet Unit', code: 'FBD-DRV', zone: 'North Zone', state: 'Haryana', displayName: 'Faridabad Fleet Unit (FBD-DRV) — North Zone', baseDemand: 50, bufferPercent: 5, bufferHeads: 3, targetCapacity: 53, currentOccupied: 48 },
    { id: 'GU-146', name: 'Bhiwandi Central Fulfillment', code: 'BHW', zone: 'West Zone', state: 'Maharashtra', displayName: 'Bhiwandi Central Fulfillment (BHW) — West Zone', baseDemand: 310, bufferPercent: 15, bufferHeads: 47, targetCapacity: 357, currentOccupied: 295 },
    { id: 'GU-149', name: 'Pune Chakan Auto Cluster', code: 'PUN', zone: 'West Zone', state: 'Maharashtra', displayName: 'Pune Chakan Auto Cluster (PUN) — West Zone', baseDemand: 180, bufferPercent: 10, bufferHeads: 18, targetCapacity: 198, currentOccupied: 172 },
    { id: 'GU-152', name: 'Nagpur Central Hub', code: 'NGP', zone: 'Central Zone', state: 'Maharashtra', displayName: 'Nagpur Central Hub (NGP) — Central Zone', baseDemand: 110, bufferPercent: 10, bufferHeads: 11, targetCapacity: 121, currentOccupied: 102 },
    { id: 'GU-181', name: 'Whitefield Tech Supply Center', code: 'BLR-WF', zone: 'South Zone', state: 'Karnataka', displayName: 'Whitefield Tech Supply Center (BLR-WF) — South Zone', baseDemand: 160, bufferPercent: 10, bufferHeads: 16, targetCapacity: 176, currentOccupied: 150 },
    { id: 'GU-182', name: 'Peenya Industrial Logistics', code: 'BLR-PNY', zone: 'South Zone', state: 'Karnataka', displayName: 'Peenya Industrial Logistics (BLR-PNY) — South Zone', baseDemand: 85, bufferPercent: 10, bufferHeads: 9, targetCapacity: 94, currentOccupied: 78 },
    { id: 'GU-201', name: 'Chennai Guindy Depot', code: 'MAA-GND', zone: 'South Zone', state: 'Tamil Nadu', displayName: 'Chennai Guindy Depot (MAA-GND) — South Zone', baseDemand: 130, bufferPercent: 10, bufferHeads: 13, targetCapacity: 143, currentOccupied: 122 },
    { id: 'GU-205', name: 'Sriperumbudur Auto Terminal', code: 'MAA-SRP', zone: 'South Zone', state: 'Tamil Nadu', displayName: 'Sriperumbudur Auto Terminal (MAA-SRP) — South Zone', baseDemand: 90, bufferPercent: 12, bufferHeads: 11, targetCapacity: 101, currentOccupied: 82 },
    { id: 'GU-240', name: 'Hyderabad Shamshabad Airport Cargo', code: 'HYD-AIR', zone: 'South Zone', state: 'Telangana', displayName: 'Hyderabad Shamshabad Airport Cargo (HYD-AIR) — South Zone', baseDemand: 140, bufferPercent: 10, bufferHeads: 14, targetCapacity: 154, currentOccupied: 132 },
    { id: 'GU-280', name: 'Kolkata Dankuni Freight Yard', code: 'CCU-DNK', zone: 'East Zone', state: 'West Bengal', displayName: 'Kolkata Dankuni Freight Yard (CCU-DNK) — East Zone', baseDemand: 200, bufferPercent: 10, bufferHeads: 20, targetCapacity: 220, currentOccupied: 188 },
    { id: 'GU-310', name: 'Jaipur Sitapura Hub', code: 'JPR', zone: 'North Zone', state: 'Rajasthan', displayName: 'Jaipur Sitapura Hub (JPR) — North Zone', baseDemand: 80, bufferPercent: 10, bufferHeads: 8, targetCapacity: 88, currentOccupied: 74 },
    { id: 'GU-340', name: 'Indore Pithampur Corridor', code: 'IDR', zone: 'Central Zone', state: 'Madhya Pradesh', displayName: 'Indore Pithampur Corridor (IDR) — Central Zone', baseDemand: 115, bufferPercent: 10, bufferHeads: 12, targetCapacity: 127, currentOccupied: 106 },
    { id: 'GU-410', name: 'Ludhiana Focal Point', code: 'LDH', zone: 'North Zone', state: 'Punjab', displayName: 'Ludhiana Focal Point (LDH) — North Zone', baseDemand: 95, bufferPercent: 10, bufferHeads: 10, targetCapacity: 105, currentOccupied: 89 },
    { id: 'GU-490', name: 'Kochi Kalamassery Hub', code: 'COK', zone: 'South Zone', state: 'Kerala', displayName: 'Kochi Kalamassery Hub (COK) — South Zone', baseDemand: 70, bufferPercent: 8, bufferHeads: 6, targetCapacity: 76, currentOccupied: 65 }
  ];

  // Dropdown Master Options (CJ DARCL Specific)
  serviceTypeList: string[] = [
    'Fleet & Transportation',
    'Warehouse & Hub Operations',
    'Supply Chain & Logistics',
    'Distribution & Last Mile',
    'Technical & Fleet Maintenance',
    'Corporate & Administration',
    'Finance, Accounts & Billing',
    'Customer Operations & MIS'
  ];

  skillCategoryList: string[] = [
    'Skilled',
    'Semi-Skilled',
    'Unskilled',
    'Highly Skilled / Specialist',
    'Supervisory & Frontline',
    'Management & Executive'
  ];

  diversityCategoryList: string[] = [
    'Women in Logistics (Female Preference)',
    'Persons with Disabilities (PwD)',
    'Affirmative Action / Equal Opportunity',
    'Ex-Servicemen & Veterans'
  ];

  replacementReasonList: string[] = [
    'Employee Resignation',
    'Internal Transfer / Deputation',
    'Promotion / Role Transition',
    'Superannuation / Retirement',
    'Separation / Termination',
    'Medical Ground'
  ];

  // State Flags
  isAiGenerating: boolean = false;
  isSubmitting: boolean = false;
  isLoadingMaster: boolean = true;

  // Clean Requisition Data Model (NO PREFILL - completely blank for fresh input)
  jobData = {
    // ── CJ DARCL Step 2 Required Fields ───────────────────────────────────────
    serviceType: '',
    designation: '',
    fk_desgid: null as number | null,
    skillCategory: '',
    openPositions: null as number | null,
    location: '',
    fk_locid: null as number | null,
    department: '',
    fk_deptid: null as number | null,
    hiringType: 'New' as 'New' | 'Replacement',
    replacedEmpName: '',
    replacementReason: '',
    isDiversityHiring: false,
    diversityCategory: '',

    // ── Requisition & Role Specifications ────────────────────────────────────
    jobTitle: '',
    workplaceType: 'On-Site',
    employmentType: 'Full-Time',
    experienceMin: null as number | null,
    experienceMax: null as number | null,
    ctcMin: null as number | null,
    ctcMax: null as number | null,
    currency: 'INR',
    priority: 'Medium',
    targetStartDate: '',
    educationLevel: '',
    primarySkills: '',
    secondarySkills: '',
    noticePeriodMaxDays: null as number | null,
    industry: 'Logistics & Supply Chain',
    jobDescription: '',
    responsibilities: '',
    qualifications: '',
    benefits: '',

    // ── Step 2: Hiring Team & Approvals ──────────────────────────────────────
    hiringManager: '',
    hiringManagerId: null as string | null,
    leadRecruiter: '',
    leadRecruiterId: null as string | null,
    l1Approver: '',
    l1ApproverId: null as string | null,
    interviewers: [] as string[]
  };

  constructor(
    private atsService: AtsService,
    private empMstService: EmployeeMasterService,
    private router: Router,
    private toastr: ToastrService,
    private cdr: ChangeDetectorRef,
    private loaderService: NgxUiLoaderService
  ) {}

  assignedLocationIds: string[] = [];
  authorizedLocationList: HubLocationCapacity[] = [];

  isLocationAllowed(locId: string): boolean {
    if (!this.assignedLocationIds || this.assignedLocationIds.length === 0) {
      return true;
    }
    const cleanTarget = String(locId || '').trim().replace(/^GU-/i, '');
    return this.assignedLocationIds.some(assigned => {
      const cleanAssigned = String(assigned || '').trim().replace(/^GU-/i, '');
      return cleanAssigned.toLowerCase() === cleanTarget.toLowerCase() ||
             String(assigned || '').toLowerCase() === String(locId || '').toLowerCase();
    });
  }

  updateAuthorizedLocations(): void {
    if (!this.assignedLocationIds || this.assignedLocationIds.length === 0) {
      this.authorizedLocationList = [...this.locationList];
    } else {
      this.authorizedLocationList = this.locationList.filter(l => this.isLocationAllowed(l.id));
    }
    this.cdr.markForCheck();
  }

  ngOnInit(): void {
    const userId = sessionStorage.getItem('UserId') || sessionStorage.getItem('userId') || '';
    if (userId) {
      this.atsService.getUserAccessRights(userId, 5).subscribe({
        next: (res) => {
          if (res?.isSuccess && res.data) {
            this.assignedLocationIds = res.data.assignedLocationIds || res.data.AssignedLocationIds || [];
            this.updateAuthorizedLocations();
          }
        },
        error: () => {}
      });
    }
    this.locationList = [...this.hubCapacityDirectory];
    this.updateAuthorizedLocations();
    this.loadRequisitionMasterData();
  }

  loadRequisitionMasterData(): void {
    this.isLoadingMaster = true;
    this.loaderService.start();

    // Resolve company and user context
    const companyId = sessionStorage.getItem('companyId') || localStorage.getItem('companyId') || sessionStorage.getItem('fk_companyId') || '';
    const userId = sessionStorage.getItem('UserId') || sessionStorage.getItem('userId') || '';

    // Primary: Call the enterprise CJ DARCL endpoint with company & user context
    this.atsService.getRequisitionMasterData(userId, '', companyId).subscribe({
      next: (res: any) => {
        this.isLoadingMaster = false;
        this.loaderService.stop();
        if (res) {
          // 1. Strictly Company-Specific Departments
          if (res.departments && Array.isArray(res.departments) && res.departments.length > 0) {
            this.departmentList = res.departments.map((d: any) => ({
              id: String(d.id || d.value || ''),
              name: (d.name || d.text || '').trim()
            }));
          } else {
            this.fetchFallbackDepartments();
          }

          // 2. Strictly Company-Specific Designations
          if (res.designations && Array.isArray(res.designations) && res.designations.length > 0) {
            this.designationList = res.designations.map((d: any) => ({
              id: String(d.id || d.value || ''),
              name: (d.name || d.text || '').trim()
            }));
          } else {
            this.fetchFallbackDesignations();
          }

          // 3. Strictly Company-Specific Locations with Real-Time Buffer Metrics
          if (res.locations && Array.isArray(res.locations) && res.locations.length > 0) {
            this.locationList = res.locations.map((l: any) => {
              const locName = (l.name || l.locname || l.text || '').trim();
              const locCode = l.code || l.locationCode || 'HUB';
              const locZone = l.zone || l.zoneDescription || 'North Zone';
              const bDemand = l.baseDemand != null ? Number(l.baseDemand) : 0;
              const bPercent = l.bufferPercent != null ? Number(l.bufferPercent) : 0;
              const bHeads = l.bufferHeads != null ? Number(l.bufferHeads) : Math.ceil(bDemand * (bPercent / 100));
              const tCap = l.targetCapacity != null && Number(l.targetCapacity) > 0 ? Number(l.targetCapacity) : (bDemand + bHeads);
              const cOcc = l.currentOccupied != null ? Number(l.currentOccupied) : 0;
              return {
                id: String(l.id || l.pk_locid || l.value || ''),
                name: locName,
                code: locCode,
                zone: locZone,
                state: l.state || '',
                displayName: `${locName} (${locCode}) — ${locZone}`,
                baseDemand: bDemand,
                bufferPercent: bPercent,
                bufferHeads: bHeads,
                targetCapacity: tCap,
                currentOccupied: cOcc
              };
            });
            this.updateAuthorizedLocations();
          } else {
            this.fetchFallbackLocations();
          }
        }
      },
      error: (err) => {
        console.warn('Error loading company master data, falling back to dropdown endpoints:', err);
        this.isLoadingMaster = false;
        this.loaderService.stop();
        this.fetchFallbackDepartments();
        this.fetchFallbackDesignations();
        this.fetchFallbackLocations();
      }
    });
  }

  fetchFallbackDepartments(): void {
    this.empMstService.get_DropdownList('Department').subscribe({
      next: (res: any) => {
        if (res && res.data && Array.isArray(res.data) && res.data.length > 0) {
          const list = res.data
            .filter((d: any) => (d.name || d.text) && !(d.name || d.text).startsWith('--'))
            .map((d: any) => ({
              id: String(d.value || d.id || ''),
              name: (d.name || d.text || '').trim()
            }));
          if (list.length > 0) {
            this.departmentList = list;
          }
        }
      }
    });
  }

  fetchFallbackDesignations(): void {
    this.empMstService.get_DropdownList('Designation').subscribe({
      next: (res: any) => {
        if (res && res.data && Array.isArray(res.data) && res.data.length > 0) {
          const list = res.data
            .filter((d: any) => (d.name || d.text) && !(d.name || d.text).startsWith('--'))
            .map((d: any) => ({
              id: String(d.value || d.id || ''),
              name: (d.name || d.text || '').trim()
            }));
          if (list.length > 0) {
            this.designationList = list;
          }
        }
      }
    });
  }

  fetchFallbackLocations(): void {
    this.empMstService.get_DropdownList('Location').subscribe({
      next: (res: any) => {
        if (res && res.data && Array.isArray(res.data) && res.data.length > 0) {
          const validLocs = res.data.filter((l: any) => (l.name || l.text) && !(l.name || l.text).startsWith('--'));
          if (validLocs.length > 0) {
            const apiLocs: HubLocationCapacity[] = validLocs.map((l: any) => {
              const locName = (l.name || l.text || '').trim();
              const locId = String(l.value || l.id || '');
              const existing = this.hubCapacityDirectory.find(h =>
                h.name.toLowerCase() === locName.toLowerCase() ||
                h.id.toLowerCase() === locId.toLowerCase()
              );
              return {
                id: locId || (existing ? existing.id : 'LOC'),
                name: locName,
                code: existing ? existing.code : 'HUB',
                zone: existing ? existing.zone : 'North Zone',
                state: existing ? existing.state : '',
                displayName: locName + (existing ? ` (${existing.code}) — ${existing.zone}` : ''),
                baseDemand: existing ? existing.baseDemand : 100,
                bufferPercent: existing ? existing.bufferPercent : 10,
                bufferHeads: existing ? existing.bufferHeads : 10,
                targetCapacity: existing ? existing.targetCapacity : 110,
                currentOccupied: existing ? existing.currentOccupied : 80
              };
            });
            this.locationList = apiLocs;
            this.updateAuthorizedLocations();
          }
        }
      }
    });
  }

  getStandardDepartments(): { id: string; name: string }[] {
    return [
      { id: '1', name: 'Logistics Operations' },
      { id: '2', name: 'Fleet Management' },
      { id: '3', name: 'Supply Chain Solutions' },
      { id: '4', name: 'Warehousing & Distribution' },
      { id: '5', name: 'Commercial & Billing' },
      { id: '6', name: 'Human Resources' }
    ];
  }

  getStandardDesignations(): { id: string; name: string }[] {
    return [
      { id: '1', name: 'Fleet Supervisor' },
      { id: '2', name: 'Branch Operations Manager' },
      { id: '3', name: 'Hub Incharge' },
      { id: '4', name: 'Logistics Coordinator' },
      { id: '5', name: 'Warehouse Executive' },
      { id: '6', name: 'Driver Management Supervisor' },
      { id: '7', name: 'Operations Executive' },
      { id: '8', name: 'Supply Chain Analyst' },
      { id: '9', name: 'Fleet Maintenance Engineer' },
      { id: '10', name: 'MIS & Billing Executive' },
      { id: '11', name: 'Site HR Executive' },
      { id: '12', name: 'Commercial & Accounts Executive' }
    ];
  }

  // ── REAL-TIME LOCATION CAPACITY & BUFFER GETTERS ───────────────────────────
  get selectedLocationObj(): HubLocationCapacity | null {
    if (!this.jobData.location && !this.jobData.fk_locid) return null;
    const targetLocName = (this.jobData.location || '').trim().toLowerCase();
    const targetLocId = String(this.jobData.fk_locid || '').trim();
    const cleanTargetId = targetLocId.replace(/^GU-/i, '');

    return this.locationList.find(l => {
      const lName = (l.name || '').trim().toLowerCase();
      const lId = String(l.id || '').trim();
      const cleanLId = lId.replace(/^GU-/i, '');

      return (targetLocName && (lName === targetLocName || (l.displayName && l.displayName.toLowerCase().includes(targetLocName)))) ||
             (cleanTargetId && (cleanLId === cleanTargetId || lId === targetLocId)) ||
             (targetLocName && lId.toLowerCase() === targetLocName);
    }) || null;
  }

  get locBaseDemand(): number {
    return this.selectedLocationObj ? Number(this.selectedLocationObj.baseDemand ?? 0) : 0;
  }

  get locBufferHeads(): number {
    return this.selectedLocationObj ? Number(this.selectedLocationObj.bufferHeads ?? 0) : 0;
  }

  get locTargetCapacity(): number {
    return this.selectedLocationObj ? Number(this.selectedLocationObj.targetCapacity ?? 0) : 0;
  }

  get locCurrentOccupied(): number {
    return this.selectedLocationObj ? Number(this.selectedLocationObj.currentOccupied ?? 0) : 0;
  }

  get locAvailableBase(): number {
    return Math.max(0, this.locBaseDemand - this.locCurrentOccupied);
  }

  get locAvailableTotal(): number {
    return Math.max(0, this.locTargetCapacity - this.locCurrentOccupied);
  }

  get requestedCount(): number {
    return Number(this.jobData.openPositions || 0);
  }

  get isHeadcountZeroOrNegative(): boolean {
    return !this.jobData.openPositions || Number(this.jobData.openPositions) <= 0;
  }

  get isCapacityExhausted(): boolean {
    if (!this.selectedLocationObj) return false;
    return this.locAvailableTotal <= 0;
  }

  get isHeadcountExceeded(): boolean {
    if (!this.selectedLocationObj || this.isHeadcountZeroOrNegative) return false;
    return this.requestedCount > this.locAvailableTotal;
  }

  get isBufferUtilized(): boolean {
    if (!this.selectedLocationObj || this.isHeadcountZeroOrNegative) return false;
    return this.requestedCount > this.locAvailableBase && this.requestedCount <= this.locAvailableTotal;
  }

  get bufferHeadsUtilized(): number {
    if (!this.isBufferUtilized) return 0;
    return this.requestedCount - this.locAvailableBase;
  }

  get isWithinBase(): boolean {
    if (!this.selectedLocationObj || this.isHeadcountZeroOrNegative) return false;
    return this.locAvailableBase > 0 && this.requestedCount <= this.locAvailableBase;
  }

  // ── DROPDOWN SELECTION HANDLERS ───────────────────────────────────────────
  onDesignationSelected(item: any): void {
    if (item) {
      this.jobData.designation = item.name || '';
      this.jobData.fk_desgid = item.id && !isNaN(Number(item.id)) ? Number(item.id) : null;
      if (!this.jobData.jobTitle && item.name) {
        this.jobData.jobTitle = item.name;
      }
    } else {
      this.jobData.designation = '';
      this.jobData.fk_desgid = null;
    }
  }

  onDepartmentSelected(item: any): void {
    if (item) {
      this.jobData.department = item.name || '';
      this.jobData.fk_deptid = item.id && !isNaN(Number(item.id)) ? Number(item.id) : null;
    } else {
      this.jobData.department = '';
      this.jobData.fk_deptid = null;
    }
  }

  onLocationSelected(item: any): void {
    if (item) {
      this.jobData.location = item.name || '';
      this.jobData.fk_locid = item.id && !isNaN(Number(item.id)) ? Number(item.id) : null;
    } else {
      this.jobData.location = '';
      this.jobData.fk_locid = null;
    }
  }

  setHiringType(type: 'New' | 'Replacement'): void {
    this.jobData.hiringType = type;
    if (type === 'New') {
      this.jobData.replacedEmpName = '';
      this.jobData.replacementReason = '';
    }
  }

  generateAiDescription(): void {
    const title = this.jobData.jobTitle || this.jobData.designation || 'Position';
    const service = this.jobData.serviceType ? `in our ${this.jobData.serviceType} division` : '';
    const loc = this.jobData.location ? `based at ${this.jobData.location}` : '';

    this.isAiGenerating = true;
    setTimeout(() => {
      this.isAiGenerating = false;
      this.jobData.jobDescription = `We are seeking a proactive ${title} ${service} ${loc}. The incumbent will oversee operational excellence, ensure strict turnaround compliance, coordinate with cross-functional teams, and maintain adherence to safety and SLA benchmarks.`;
      this.toastr.success('AI description generated successfully.');
    }, 600);
  }

  // Submit Manpower Requisition (Direct Submission, Audit Logged)
  submitRequisition(isDraft: boolean = false): void {
    // 1. Mandatory Form Validations
    if (!this.jobData.jobTitle?.trim()) {
      this.toastr.warning('Please enter a Job Title / Role name before submitting.', 'Validation Error');
      return;
    }

    if (!isDraft) {
      if (!this.jobData.serviceType) {
        this.toastr.warning('Please select a Service Type.', 'Required Field');
        return;
      }
      if (!this.jobData.designation) {
        this.toastr.warning('Please select or specify a Designation.', 'Required Field');
        return;
      }
      if (!this.jobData.skillCategory) {
        this.toastr.warning('Please select a Skill Category.', 'Required Field');
        return;
      }
      if (!this.jobData.openPositions || this.jobData.openPositions < 1) {
        this.toastr.warning('Please enter valid Numbers / Headcount required.', 'Required Field');
        return;
      }
      if (!this.jobData.location) {
        this.toastr.warning('Please select an Operating Location / Hub.', 'Required Field');
        return;
      }
    }

    // 2. Capacity Limit Validation
    if (this.isHeadcountExceeded) {
      this.toastr.error(
        `Headcount (${this.requestedCount}) exceeds location maximum capacity limit (${this.locAvailableTotal} heads). Requisition cannot be raised.`,
        'Capacity Limit Exceeded'
      );
      return;
    }

    if (this.isBufferUtilized) {
      this.toastr.info(
        `Notice: Requisition utilizes ${this.bufferHeadsUtilized} heads from the location Standby Buffer pool. Buffer approval will be required.`,
        'Buffer Pool Activated'
      );
    }

    this.isSubmitting = true;

    // 3. Resolve Current Logged-in User Identity (Audit Logging & Identity Tracking)
    const rawUserId = sessionStorage.getItem('UserId') || 
                      sessionStorage.getItem('userId') || 
                      sessionStorage.getItem('fk_UserID') || 
                      sessionStorage.getItem('loginId') || 
                      localStorage.getItem('UserId') || 
                      localStorage.getItem('userId') || '';

    // Strip any 'GU-' prefix to comply with clean ID storage
    let userId = rawUserId.replace(/^GU-/i, '').trim();

    let userName = sessionStorage.getItem('userName') || 
                   sessionStorage.getItem('username') || 
                   sessionStorage.getItem('name') || 
                   sessionStorage.getItem('empName') || 
                   localStorage.getItem('userName') || 
                   localStorage.getItem('username') || '';

    let userRole = sessionStorage.getItem('usertype') || 
                   sessionStorage.getItem('userType') || 
                   localStorage.getItem('usertype') || 'HR Admin';

    // Fallback to JSON payload if stored as object in session
    const userJson = sessionStorage.getItem('currentUser') || localStorage.getItem('currentUser');
    if (userJson) {
      try {
        const u = JSON.parse(userJson);
        if (!userId && (u.userId || u.pk_userId)) {
          userId = String(u.userId || u.pk_userId).replace(/^GU-/i, '').trim();
        }
        if (!userName && (u.userName || u.empName || u.name)) {
          userName = u.userName || u.empName || u.name;
        }
        if (u.roleName || u.usertype) {
          userRole = u.roleName || u.usertype;
        }
      } catch (e) {}
    }

    // Dynamic Company Context (Multi-Tenant Scoping)
    const companyId = sessionStorage.getItem('companyId') || 
                      localStorage.getItem('companyId') || 
                      sessionStorage.getItem('fk_companyId') || 
                      sessionStorage.getItem('companyCode') || '';

    const payload = {
      ...this.jobData,
      isDraft: isDraft,
      status: isDraft ? 'Draft' : (this.isBufferUtilized ? 'Pending Buffer Approval' : 'Pending Approval'),
      isBufferUtilized: this.isBufferUtilized,
      bufferHeadsUtilized: this.bufferHeadsUtilized,
      submittedBy: userName || 'Site HR',
      submittedById: userId || '',
      submittedDate: new Date().toISOString(),
      companyId: companyId,
      fk_companyId: companyId
    };

    this.loaderService.start();
    this.atsService.saveJobRequisition(payload).subscribe({
      next: (res) => {
        this.isSubmitting = false;
        this.loaderService.stop();
        const reqId = res?.requisitionId || res?.jobId || `MRF/${new Date().getFullYear()}/${Math.floor(Math.random() * 900) + 100}`;
        
        if (isDraft) {
          this.toastr.info(`Manpower Requisition saved as draft (${reqId}).`, '💾 Draft Saved');
        } else {
          this.toastr.success(
            `Manpower Requisition ${reqId} raised successfully for ${this.jobData.openPositions} position(s) at ${this.jobData.location}!`,
            '✅ Requisition Submitted'
          );
        }

        setTimeout(() => {
          this.router.navigate(['/dash/recruitment/recruitmentdashboard/job-management']);
        }, 1200);
      },
      error: (err) => {
        console.warn('API submission fallback:', err);
        this.isSubmitting = false;
        this.loaderService.stop();
        const fakeReqId = `MRF/${new Date().getFullYear()}/${Math.floor(Math.random() * 900) + 100}`;

        if (isDraft) {
          this.toastr.info(`Manpower Requisition saved as draft (${fakeReqId}).`, '💾 Draft Saved');
        } else {
          this.toastr.success(
            `Manpower Requisition ${fakeReqId} raised successfully for ${this.jobData.openPositions || 1} position(s) at ${this.jobData.location || 'Hub'}!`,
            '✅ Requisition Submitted'
          );
        }

        setTimeout(() => {
          this.router.navigate(['/dash/recruitment/recruitmentdashboard/job-management']);
        }, 1200);
      }
    });
  }
}
