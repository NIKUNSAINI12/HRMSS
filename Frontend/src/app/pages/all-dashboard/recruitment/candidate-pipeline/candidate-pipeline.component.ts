import { Component, OnInit, OnDestroy, ElementRef, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterModule } from '@angular/router';
import { DomSanitizer, SafeResourceUrl } from '@angular/platform-browser';
import { ToastrService } from 'ngx-toastr';
import { AtsService } from '../../../../shared/services/ats.service';
import { JobMasterService } from '../RecruitServices/job-master.service';
import { NgxUiLoaderService } from 'ngx-ui-loader';
import { forkJoin, of } from 'rxjs';
import { catchError } from 'rxjs/operators';

@Component({
  selector: 'app-candidate-pipeline',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterModule],
  templateUrl: './candidate-pipeline.component.html',
  styleUrl: './candidate-pipeline.component.scss'
})
export class CandidatePipelineComponent implements OnInit, OnDestroy {
  // Navigation tabs: 'positions' | 'pipeline' | 'mis'
  activeTab: 'positions' | 'pipeline' | 'mis' = 'pipeline';

  // Positions & Requisitions
  jobList: any[] = [];
  selectedJob: any | null = null;
  jobSearchQuery: string = '';
  departmentFilter: string = 'ALL';

  // Pipeline Roster & Kanban
  candidateRoster: any[] = [];
  searchQuery: string = '';
  activeStageFilter: string = 'ALL';
  selectedCandidate: any | null = null;

  // Stages loaded dynamically from DB (company-wise enable/disable)
  stages: { code: string; label: string; color: string; icon: string; isEnabled: boolean; stageOrder: number }[] = [];

  // All stages (including disabled) — used in Stage Settings modal
  allStageConfigs: any[] = [];

  // Stage Settings modal
  showStageSettingsModal: boolean = false;

  // Modals & Drawers state
  showVendorModal: boolean = false;
  showRegisterModal: boolean = false;
  isRegisteringCandidate: boolean = false;
  showPoolModal: boolean = false;
  showInterviewModal: boolean = false;
  showEvaluationModal: boolean = false;
  showDocsModal: boolean = false;
  showOfferModal: boolean = false;
  showAuditDrawer: boolean = false;
  showQrModal: boolean = false;
  selectedCandidateIds: Set<number> = new Set<number>();
  isBatchMoving: boolean = false;

  // Existing Talent Pool (Bench & Previously Rejected Candidates) Allocation for Pipeline
  registerMode: 'NEW' | 'POOL' = 'NEW';
  poolCandidates: any[] = [];
  loadingPool: boolean = false;
  poolSearchQuery: string = '';
  poolFilterTab: 'ALL' | 'BENCH' | 'REJECTED' = 'ALL';
  selectedPoolVendor: string = 'ALL';
  selectedPoolAppIds: Set<number> = new Set();
  assigningPoolCandidates: boolean = false;

  // Vendor Mapping
  vendorMappingList: any[] = [];
  availableVendors: any[] = [];
  vendorForm = {
    reqId: 0,
    mrfCode: '',
    jobTitle: '',
    vendorId: '',
    vendorName: '',
    allocatedQuota: 10,
    commissionTerms: 'Standard (8.33%)',
    isActive: true
  };

  // Candidate Registration
  candidateForm = {
    reqId: 0,
    mrfCode: '',
    candidateName: '',
    mobile: '',
    email: '',
    gender: 'Male',
    dateOfBirth: '',
    fatherName: '',
    currentLocation: '',
    sourceType: 'Vendor',
    vendorId: '',
    vendorName: '',
    aadhaarNo: '',
    skillClassification: 'Semi-Skilled'
  };

  // Interview Scheduling
  interviewForm = {
    appId: 0,
    candidateName: '',
    interviewerId: '',
    interviewerName: '',
    interviewDate: '',
    interviewRound: 'Technical & Operations',
    remarks: ''
  };

  // Staffing Vendor Assignment Modal State (Company-wise & Location-wise)
  showAssignVendorModal: boolean = false;
  assignVendorCandidate: any = null;
  assignVendorList: any[] = [];
  selectedVendorForAssignment: string = '';
  assignVendorRemarks: string = '';
  isAssigningVendor: boolean = false;
  isLoadingVendors: boolean = false;
  pendingTargetStage: string | null = null;

  // Evaluation & Skill Grading
  evaluationForm = {
    appId: 0,
    candidateName: '',
    skillClassification: 'Semi-Skilled',
    decision: 'Selected',
    score: 85,
    remarks: 'Candidate demonstrated proficient domain understanding and physical fitness.'
  };

  // Onboarding Docs (Legacy compatibility & extended 22-point document review state)
  docsForm = {
    appId: 0,
    candidateName: '',
    aadhaarNo: '',
    aadhaarDocPath: '',
    panNo: '',
    panDocPath: '',
    bankAccNo: '',
    bankIfsc: '',
    bankName: '',
    photoDocPath: '',
    resumeDocPath: '',
    verificationRemarks: ''
  };

  // 22-Point Candidate Document Review & Verification Suite State
  docsCandidateHeader: any = null;
  candidateDocList: any[] = [];
  docsActiveFilter: string = 'ALL'; // 'ALL' | 'MANDATORY' | 'PENDING' | 'APPROVED' | 'REJECTED'
  docsActiveTab: 'documents' | 'statutory' | 'audit' = 'documents';
  docsAuditTrail: any[] = [];
  docsAuditLoading: boolean = false;
  docsMetrics = {
    totalMandatory: 0,
    approvedMandatory: 0,
    rejectedCount: 0,
    missingMandatory: 0
  };

  showDocRejectModal: boolean = false;
  selectedDocForReject: any = null;
  docRejectionRemark: string = '';

  dossierForm: any = {
    appId: 0,
    aadhaarNo: '',
    panNo: '',
    bankAccNo: '',
    bankIfsc: '',
    bankName: '',
    nomineeName: '',
    nomineeRelation: 'Spouse',
    nomineeDOB: '',
    nomineeContact: '',
    uanNo: '',
    esicNo: ''
  };

  isUploadingDoc: { [docTypeCode: string]: boolean } = {};
  isLoadingDocs: boolean = false;
  isSavingDossier: boolean = false;
  showDocPreviewModal: boolean = false;
  previewDocUrl: string = '';
  previewDocName: string = '';

  // Offer Letter
  offerForm = {
    appId: 0,
    candidateName: '',
    offeredCTC: 360000,
    expectedJoiningDate: ''
  };

  // QR Modal
  qrData = {
    mrfCode: '',
    jobTitle: '',
    directUrl: ''
  };

  // Tag Candidate Modal (Step 2, 7, 8)
  showTagModal: boolean = false;
  tagForm: any = {
    appId: 0,
    reqId: 0,
    candidateName: '',
    mrfCode: '',
    skillClassification: 'Semi-Skilled',
    isDiversityHiring: false,
    candidateTags: '',
    assignedReviewer: 'Site HR',
    remarks: ''
  };

  // Move Candidate Stage Modal (Steps 6-13)
  showStageMoveModal: boolean = false;
  stageMoveForm: any = {
    appId: 0,
    candidateName: '',
    currentStage: '',
    targetStage: '',
    remarks: ''
  };

  // Reject Candidate Modal (Step 9 & 15)
  showRejectModal: boolean = false;
  rejectForm: any = {
    appId: 0,
    candidateName: '',
    applicationNo: '',
    currentStage: '',
    rejectionReason: 'Skill Mismatch / Assessment Failed',
    remarks: '',
    cooloffPolicy: '90_Days',
    notifyCandidate: true
  };

  // Audit Trail
  auditTrail: any[] = [];

  // Candidate Full Details Modal
  showCandidateDetailsModal: boolean = false;
  selectedCandidateDetails: any = null;

  // Recruitment MIS Analytics
  misData: any = {
    funnel: {
      totalApplications: 0,
      appliedCount: 0,
      interviewCount: 0,
      selectedCount: 0,
      docVerifiedCount: 0,
      offerIssuedCount: 0,
      hiredCount: 0,
      rejectedCount: 0
    },
    locationDemand: [],
    skillDistribution: []
  };

  constructor(
    private atsService: AtsService,
    private jobMasterService: JobMasterService,
    private route: ActivatedRoute,
    private router: Router,
    private toastr: ToastrService,
    private sanitizer: DomSanitizer,
    private cdr: ChangeDetectorRef,
    private el: ElementRef,
    private loaderService: NgxUiLoaderService
  ) {}

  updateSectionZIndex(elevate: boolean): void {
    try {
      const section = (this.el?.nativeElement as HTMLElement)?.closest('.section') as HTMLElement;
      if (section) {
        section.style.zIndex = elevate ? '10000' : '';
      }
    } catch (e) {}
  }

  ngOnDestroy(): void {
    this.updateSectionZIndex(false);
  }

  assignedLocationIds: string[] = [];

  ngOnInit(): void {
    this.jobViewMode = 'table';
    this.loadUserAccessRights();
    this.loadStageConfig();
    this.loadJobs(); // Load approved jobs for the job selector
    // NOTE: loadPipelineRoster() is NOT called here.
    // Pipeline only loads AFTER the user selects an approved job.

    this.route.queryParams.subscribe(params => {
      if (params['tab']) {
        this.activeTab = params['tab'] as any;
      }
      // If a jobId is passed via query params, auto-select it
      if (params['reqId']) {
        this.activeTab = 'pipeline';
        // Auto-select job if reqId matches one in our list
        this.route.queryParams.subscribe(() => {
          const match = this.jobList.find(j => String(j.reqId) === String(params['reqId']));
          if (match) this.selectJobForPipeline(match);
        });
      }
    });
  }

  get userId(): string {
    return sessionStorage.getItem('userId') || 
           localStorage.getItem('userId') || 
           sessionStorage.getItem('fk_userId') || 
           localStorage.getItem('fk_userId') || '';
  }

  get companyId(): string {
    return sessionStorage.getItem('companyId') || 
           localStorage.getItem('fk_companyId') || 
           localStorage.getItem('companyId') || 
           sessionStorage.getItem('fk_companyId') || 'GU-1';
  }

  get currentUserName(): string {
    return sessionStorage.getItem('userName') || 
           localStorage.getItem('userName') || 'Site HR Admin';
  }

  loadUserAccessRights(): void {
    if (this.userId) {
      this.atsService.getUserAccessRights(this.userId, 5).subscribe({
        next: (res) => {
          if (res?.isSuccess && res.data) {
            this.assignedLocationIds = res.data.assignedLocationIds || res.data.AssignedLocationIds || [];
            this.cdr.detectChanges();
          }
        },
        error: () => {}
      });
    }
  }

  isLocationAllowed(job: any): boolean {
    if (!this.assignedLocationIds || this.assignedLocationIds.length === 0) {
      return true;
    }
    const jobLocId = String(job.fk_locid || job.locId || job.locationId || (job.rawJob && (job.rawJob.fk_locid || job.rawJob.fk_locId)) || '').trim();
    if (!jobLocId) return true;

    const cleanJobLoc = jobLocId.replace(/^GU-/i, '');

    return this.assignedLocationIds.some(assignedLoc => {
      const assignedStr = String(assignedLoc || '').trim();
      const cleanAssigned = assignedStr.replace(/^GU-/i, '');
      return assignedStr.toLowerCase() === jobLocId.toLowerCase() || 
             (cleanJobLoc && cleanAssigned && cleanJobLoc === cleanAssigned);
    });
  }

  // =========================================================================
  // STAGE CONFIG LOADER (Company-wise enable/disable from DB)
  // =========================================================================

  loadStageConfig(): void {
    this.atsService.getPipelineStageConfig(this.companyId).subscribe({
      next: (configs) => {
        const all = configs || this.atsService.getDefaultStageConfig();
        this.allStageConfigs = all;
        // Only expose enabled stages to the kanban board
        this.stages = all
          .filter((s: any) => s.isEnabled || s.IsEnabled)
          .sort((a: any, b: any) => (a.stageOrder ?? a.StageOrder ?? 0) - (b.stageOrder ?? b.StageOrder ?? 0))
          .map((s: any) => ({
            code:       s.stageCode  ?? s.StageCode,
            label:      s.stageLabel ?? s.StageLabel,
            icon:       s.stageIcon  ?? s.StageIcon,
            color:      s.stageColor ?? s.StageColor,
            isEnabled:  !!(s.isEnabled ?? s.IsEnabled),
            stageOrder: s.stageOrder ?? s.StageOrder ?? 0
          }));
      },
      error: () => {
        // Graceful fallback — use service defaults
        const defaults = this.atsService.getDefaultStageConfig();
        this.allStageConfigs = defaults;
        this.stages = defaults.map(s => ({
          code: s.stageCode, label: s.stageLabel, icon: s.stageIcon,
          color: s.stageColor, isEnabled: true, stageOrder: s.stageOrder
        }));
      }
    });
  }

  /** Toggle a stage enabled/disabled and persist to DB */
  toggleStage(config: any): void {
    const newEnabled = !(config.isEnabled ?? config.IsEnabled);
    const payload = {
      companyId:  this.companyId,
      stageCode:  config.stageCode  ?? config.StageCode,
      stageLabel: config.stageLabel ?? config.StageLabel,
      stageIcon:  config.stageIcon  ?? config.StageIcon,
      stageColor: config.stageColor ?? config.StageColor,
      stageOrder: config.stageOrder ?? config.StageOrder ?? 0,
      isEnabled:  newEnabled,
      modifiedBy: this.currentUserName
    };

    this.atsService.upsertPipelineStageConfig(payload).subscribe({
      next: () => {
        // Update local allStageConfigs
        config.isEnabled = newEnabled;
        config.IsEnabled = newEnabled;
        // Recompute active stages
        this.stages = this.allStageConfigs
          .filter((s: any) => s.isEnabled || s.IsEnabled)
          .sort((a: any, b: any) => (a.stageOrder ?? a.StageOrder ?? 0) - (b.stageOrder ?? b.StageOrder ?? 0))
          .map((s: any) => ({
            code:       s.stageCode  ?? s.StageCode,
            label:      s.stageLabel ?? s.StageLabel,
            icon:       s.stageIcon  ?? s.StageIcon,
            color:      s.stageColor ?? s.StageColor,
            isEnabled:  !!(s.isEnabled ?? s.IsEnabled),
            stageOrder: s.stageOrder ?? s.StageOrder ?? 0
          }));
        const stageName = config.stageLabel ?? config.StageLabel;
        this.toastr.success(
          `Stage "${stageName}" ${newEnabled ? 'enabled' : 'disabled'} for this company.`,
          'Stage Config Saved'
        );
      },
      error: () => this.toastr.error('Failed to update stage configuration.')
    });
  }

  // =========================================================================
  // DATA LOADERS
  // =========================================================================

  loadJobs(): void {
    this.loaderService.start();
    forkJoin({
      jobMasterRes: this.jobMasterService.getAllJobMasters(0, 1000).pipe(
        catchError(() => of({ isSuccess: false, data: [] }))
      ),
      requisitionsRes: this.atsService.getJobRequisitions(this.companyId).pipe(
        catchError(() => of([]))
      )
    }).subscribe({
      next: ({ jobMasterRes, requisitionsRes }) => {
        this.loaderService.stop();
        const jobs: any[] = [];
        const seenIds = new Set<string>();

        // Requisitions
        const reqList = (requisitionsRes || []);
        for (const r of reqList) {
          const rId = (r.reqId ? `REQ-${r.reqId}` : r.jobId || '').toString();
          if (rId && !seenIds.has(rId)) {
            seenIds.add(rId);
            jobs.push({
              jobId: rId,
              reqId: r.reqId,
              fk_locid: r.fk_locid,
              mrfCode: r.mrfCode || `MRF/2026/${r.reqId}`,
              jobTitle: r.jobTitle || 'Requisition Position',
              department: r.department || 'Operations',
              location: r.location || 'Headquarters',
              employmentType: r.employmentType || 'Full-time',
              openingsCount: r.openingsCount || r.no_of_post || 1,
              hiredCount: r.hiredCount || 0,
              isFilled: !!r.isFilled,
              hiringManagerName: r.hiringManagerName || '',
              workflowStatus: r.workflowStatus || r.status || 'Active',
              source: 'Requisition',
              rawJob: r
            });
          }
        }

        // Job Master
        const jmList = (jobMasterRes && (jobMasterRes.data || jobMasterRes.Data)) || [];
        for (const j of jmList) {
          const jId = (j.pk_JobId || j.jobId || '').toString();
          if (jId && !seenIds.has(jId)) {
            seenIds.add(jId);
            jobs.push({
              jobId: jId,
              reqId: j.pk_JobId,
              mrfCode: `JM-${jId}`,
              jobTitle: j.job_title || j.jobTitle || 'Position',
              department: j.department || 'Operations',
              location: j.forlocation || j.location || 'Hub',
              employmentType: j.forRequirement || 'Full-time',
              openingsCount: j.no_of_post || 1,
              hiredCount: j.hiredCount || 0,
              isFilled: !!j.isFilled,
              hiringManagerName: j.remarks || '',
              workflowStatus: j.job_closed ? 'Closed' : 'Active',
              source: 'Job Master',
              rawJob: j
            });
          }
        }

        this.jobList = jobs;
        const reqIdParam = this.route.snapshot.queryParams['reqId'];
        if (reqIdParam && !this.selectedJob) {
          const match = jobs.find(j => String(j.reqId) === String(reqIdParam) || String(j.jobId) === String(reqIdParam));
          if (match) {
            this.selectJob(match);
          }
        }
      },
      error: () => {
        this.loaderService.stop();
      }
    });
  }

  loadPipelineRoster(): void {
    this.loaderService.start();
    const reqId = this.selectedJob ? this.selectedJob.reqId : undefined;
    this.atsService.getCandidatePipelineRoster(reqId, this.activeStageFilter, this.searchQuery, this.companyId).subscribe({
      next: (data) => {
        this.loaderService.stop();
        this.candidateRoster = data || [];
      },
      error: (err) => {
        this.loaderService.stop();
        console.warn('Error loading candidate roster:', err);
      }
    });
  }

  loadMisReport(): void {
    this.loaderService.start();
    this.atsService.getRecruitmentMIS(this.companyId).subscribe({
      next: (data) => {
        this.loaderService.stop();
        if (data) {
          this.misData = {
            funnel: data.funnel || this.misData.funnel,
            locationDemand: data.locationDemand || [],
            skillDistribution: data.skillDistribution || []
          };
        }
      },
      error: () => {
        this.loaderService.stop();
      }
    });
  }

  // Switch Tabs
  setTab(tab: 'positions' | 'pipeline' | 'mis'): void {
    this.activeTab = tab;
    if (tab === 'pipeline') {
      if (this.selectedJob) {
        this.loadPipelineRoster();
      }
    } else if (tab === 'mis') {
      this.loadMisReport();
    }
  }

  isCandidateRejected(c: any): boolean {
    if (!c) return false;
    // An actively allocated or applied candidate whose isRejected flag is explicitly 0/false is NEVER rejected
    if (c.isRejected === 0 || c.isRejected === false || c.isRejected === '0') return false;
    return c.isRejected === 1 || c.isRejected === true || c.isRejected === '1' || c.stage === 'Rejected' || c.status === 'Rejected' || c.interviewStatus === 'Rejected';
  }

  // Filter Pipeline Roster by Kanban Stage (Keeps rejected candidates and Hold candidates visible at their respective stage)
  getCandidatesForStage(stageCode: string): any[] {
    if (!this.candidateRoster) return [];
    if (stageCode === 'Docs_Submitted') {
      return this.candidateRoster.filter(c => 
        c.stage === 'Docs_Submitted' || c.stage === 'Docs_Verified' ||
        (this.isCandidateRejected(c) && (c.rejectionStage === 'Docs_Submitted' || c.rejectionStage === 'Docs_Verified'))
      );
    }
    if (stageCode === 'Interview_Scheduled') {
      return this.candidateRoster.filter(c => 
        c.stage === 'Interview_Scheduled' || c.stage === 'Hold' || c.stage === 'Interview_Completed' ||
        c.interviewStatus === 'Hold' ||
        (this.isCandidateRejected(c) && (c.rejectionStage === 'Interview_Scheduled' || c.rejectionStage === 'Interview_Completed' || c.rejectionStage === 'Hold'))
      );
    }
    return this.candidateRoster.filter(c => 
      c.stage === stageCode || 
      (this.isCandidateRejected(c) && c.rejectionStage === stageCode)
    );
  }

  // Search filter
  getFilteredRoster(): any[] {
    if (!this.candidateRoster) return [];
    if (!this.searchQuery.trim()) return this.candidateRoster;
    const q = this.searchQuery.toLowerCase();
    return this.candidateRoster.filter(c =>
      (c.candidateName && c.candidateName.toLowerCase().includes(q)) ||
      (c.applicationNo && c.applicationNo.toLowerCase().includes(q)) ||
      (c.mobile && c.mobile.includes(q)) ||
      (c.mrfCode && c.mrfCode.toLowerCase().includes(q)) ||
      (c.vendorName && c.vendorName.toLowerCase().includes(q))
    );
  }

  getFilteredJobList(): any[] {
    let list = this.jobList.filter(j => this.isLocationAllowed(j));
    if (this.departmentFilter !== 'ALL') {
      list = list.filter(j => j.department === this.departmentFilter);
    }
    if (this.jobSearchQuery.trim()) {
      const q = this.jobSearchQuery.toLowerCase();
      list = list.filter(j =>
        (j.jobTitle && j.jobTitle.toLowerCase().includes(q)) ||
        (j.department && j.department.toLowerCase().includes(q)) ||
        (j.location && j.location.toLowerCase().includes(q)) ||
        (j.mrfCode && j.mrfCode.toLowerCase().includes(q))
      );
    }
    return list;
  }

  getUniqueDepartments(): string[] {
    const depts = new Set<string>();
    this.jobList.filter(j => this.isLocationAllowed(j)).forEach(j => { if (j.department) depts.add(j.department); });
    return Array.from(depts);
  }

  // =========================================================================
  // APPROVED JOB SELECTION FOR PIPELINE (OATS JOB LIST ARCHITECTURE)
  // =========================================================================

  approvedJobSearchQuery: string = '';
  approvedJobDeptFilter: string = 'ALL';
  jobViewMode: 'table' | 'grid' = 'table';
  jobTimelineFilter: string = 'all';
  jobPage: number = 1;
  jobPageSize: number = 12;
  selectedJobCodes: Set<string | number> = new Set();

  setJobViewMode(mode: 'table' | 'grid'): void {
    this.jobViewMode = mode;
    localStorage.setItem('oats_pipeline_job_view_mode', mode);
  }

  getJobInitials(title: string): string {
    if (!title) return 'JB';
    const words = title.trim().split(/\s+/);
    if (words.length === 1) return words[0].substring(0, 2).toUpperCase();
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  getJobPriority(job: any): 'Critical' | 'High' | 'Medium' | 'Low' {
    if (job.priority) return job.priority;
    if (job.urgency === 'Immediate' || job.isUrgent) return 'Critical';
    if ((job.openingsCount || job.openPositions || 1) >= 5) return 'High';
    return 'Medium';
  }

  getJobPriorityColor(job: any): string {
    const p = this.getJobPriority(job);
    switch (p) {
      case 'Critical': return '#ef4444';
      case 'High': return '#dd7c06';
      case 'Medium': return '#16a34a';
      case 'Low': return '#eab308';
      default: return '#16a34a';
    }
  }

  getJobSubmissionsCount(job: any): number {
    return job.submissionCount || job.applicantsCount || 0;
  }

  getJobPipelineCount(job: any): number {
    return job.pipelineCount || (job.applicantsCount ? Math.max(1, job.applicantsCount) : 0);
  }

  getJobHiredCount(job: any): number {
    if (!job) return 0;
    const directCount = Number(job.hiredCount) || 0;
    const rosterHired = this.candidateRoster ? this.candidateRoster.filter(c =>
      (c.reqId == job.reqId || c.mrfCode === job.mrfCode) && (c.stage === 'Hired' || c.status === 'Hired')
    ).length : 0;
    return Math.max(directCount, rosterHired);
  }

  isJobFilled(job: any): boolean {
    if (!job) return false;
    const required = Number(job.openingsCount || job.no_of_post || job.openPositions) || 1;
    const filled = this.getJobHiredCount(job);
    return filled >= required;
  }

  getSelectedRegistrationJob(): any {
    if (!this.candidateForm.reqId) return this.selectedJob;
    return this.jobList.find(j => j.reqId == this.candidateForm.reqId) || this.selectedJob;
  }

  isJobApproved(job: any): boolean {
    if (!job) return false;
    const status = (job.workflowStatus || job.status || '').toLowerCase().trim();
    if (status === 'closed' || status === 'draft' || status.includes('pending') || status.includes('submitted') || status.includes('reject')) {
      return false;
    }
    return status === 'active' || status === 'approved' || status === 'sanctioned' || status === 'open';
  }

  getApprovedJobList(): any[] {
    // STRICTLY ONLY APPROVED JOBS ON THIS PIPELINE PAGE MATCHING LOCATION PERMISSIONS
    let list = this.jobList.filter(j => this.isJobApproved(j) && this.isLocationAllowed(j));

    if (this.approvedJobDeptFilter !== 'ALL') {
      list = list.filter(j => j.department === this.approvedJobDeptFilter);
    }

    // Timeline filter
    if (this.jobTimelineFilter !== 'all') {
      const now = new Date();
      list = list.filter(j => {
        const rawDate = j.createdAt || j.createdDate || j.creationDate;
        if (!rawDate) return true;
        const cDate = new Date(rawDate);
        if (isNaN(cDate.getTime())) return true;
        const diffDays = (now.getTime() - cDate.getTime()) / (1000 * 3600 * 24);
        if (this.jobTimelineFilter === 'today') return diffDays <= 1;
        if (this.jobTimelineFilter === 'last_7_days') return diffDays <= 7;
        if (this.jobTimelineFilter === 'last_30_days') return diffDays <= 30;
        if (this.jobTimelineFilter === 'this_year') return cDate.getFullYear() === now.getFullYear();
        return true;
      });
    }

    if (this.approvedJobSearchQuery.trim()) {
      const q = this.approvedJobSearchQuery.toLowerCase();
      list = list.filter(j =>
        (j.jobTitle && j.jobTitle.toLowerCase().includes(q)) ||
        (j.department && j.department.toLowerCase().includes(q)) ||
        (j.location && j.location.toLowerCase().includes(q)) ||
        (j.mrfCode && j.mrfCode.toLowerCase().includes(q))
      );
    }
    return list;
  }

  get paginatedApprovedJobs(): any[] {
    const list = this.getApprovedJobList();
    const start = (this.jobPage - 1) * this.jobPageSize;
    return list.slice(start, start + this.jobPageSize);
  }

  get totalApprovedJobPages(): number {
    return Math.ceil(this.getApprovedJobList().length / this.jobPageSize) || 1;
  }

  get approvedJobPagesArray(): number[] {
    const pages: number[] = [];
    for (let i = 1; i <= this.totalApprovedJobPages; i++) {
      pages.push(i);
    }
    return pages;
  }

  goToJobPage(page: number): void {
    if (page >= 1 && page <= this.totalApprovedJobPages) {
      this.jobPage = page;
    }
  }

  changeJobPageSize(size: number): void {
    this.jobPageSize = size;
    this.jobPage = 1;
  }

  toggleSelectAllJobs(event: any): void {
    const isChecked = event?.target?.checked ?? false;
    if (isChecked) {
      this.paginatedApprovedJobs.forEach(j => this.selectedJobCodes.add(j.reqId || j.jobId));
    } else {
      this.selectedJobCodes.clear();
    }
  }

  toggleSelectJob(job: any): void {
    const id = job.reqId || job.jobId;
    if (this.selectedJobCodes.has(id)) {
      this.selectedJobCodes.delete(id);
    } else {
      this.selectedJobCodes.add(id);
    }
  }

  isJobSelected(job: any): boolean {
    return this.selectedJobCodes.has(job.reqId || job.jobId);
  }

  isAllJobsSelected(): boolean {
    if (!this.paginatedApprovedJobs || this.paginatedApprovedJobs.length === 0) return false;
    return this.paginatedApprovedJobs.every(j => this.selectedJobCodes.has(j.reqId || j.jobId));
  }

  isIndeterminateSelected(): boolean {
    const count = this.paginatedApprovedJobs.filter(j => this.selectedJobCodes.has(j.reqId || j.jobId)).length;
    return count > 0 && count < this.paginatedApprovedJobs.length;
  }

  selectJob(job: any): void {
    this.selectedJob = job;
    this.activeTab = 'pipeline';
    this.selectedStageCode = this.stages.length > 0 ? this.stages[0].code : 'Applied';
    this.activeStageFilter = 'ALL';
    this.candidateRoster = [];
    this.loadPipelineRoster();
  }

  selectJobForPipeline(job: any): void {
    this.selectJob(job);
  }

  clearJobFilter(): void {
    this.selectedJob = null;
    this.selectedStageCode = null;
    this.candidateRoster = [];
    this.activeStageFilter = 'ALL';
  }

  // =========================================================================
  // OATS-STYLE STAGE TABS INTERACTION
  // =========================================================================

  selectedStageCode: string | null = null;

  onSelectStage(stageCode: string): void {
    this.selectedStageCode = stageCode;
    this.searchQuery = '';
  }

  getSelectedStage(): any {
    return this.stages.find(s => s.code === this.selectedStageCode);
  }

  getSelectedStageIndex(): number {
    return this.stages.findIndex(s => s.code === this.selectedStageCode);
  }

  getCandidatesForSelectedStage(): any[] {
    if (!this.selectedStageCode) return [];
    let list = this.getCandidatesForStage(this.selectedStageCode);
    if (this.searchQuery && this.searchQuery.trim()) {
      const q = this.searchQuery.toLowerCase();
      list = list.filter(c =>
        (c.candidateName && c.candidateName.toLowerCase().includes(q)) ||
        (c.applicationNo && c.applicationNo.toLowerCase().includes(q)) ||
        (c.mobile && c.mobile.includes(q)) ||
        (c.vendorName && c.vendorName.toLowerCase().includes(q)) ||
        (c.candidateCode && c.candidateCode.toLowerCase().includes(q))
      );
    }
    return list;
  }

  // =========================================================================
  // STEP 4 & 5: VENDOR TO REQUISITION ALLOCATION
  // =========================================================================

  openVendorModal(job: any): void {
    this.selectedJob = job;
    this.vendorForm.reqId = job.reqId || 1;
    this.vendorForm.mrfCode = job.mrfCode || '';
    this.vendorForm.jobTitle = job.jobTitle || '';
    const targetCompId = job?.fk_companyId || job?.companyId || this.companyId;

    this.atsService.getVendorsForMapping(this.vendorForm.reqId, targetCompId).subscribe({
      next: (vendors) => {
        this.vendorMappingList = vendors || [];
        this.showVendorModal = true;
      },
      error: () => {
        this.toastr.error('Failed to load vendors for mapping.');
      }
    });
  }

  saveVendorMapping(v: any): void {
    const targetCompId = this.selectedJob?.fk_companyId || this.selectedJob?.companyId || this.companyId;
    const payload = {
      reqId: this.vendorForm.reqId,
      vendorId: v.vendorId.toString(),
      vendorName: v.vendorName,
      allocatedQuota: v.allocatedQuota || 10,
      commissionTerms: v.commissionTerms || 'Standard (8.33%)',
      isActive: true,
      assignedBy: this.currentUserName,
      companyId: targetCompId
    };

    this.atsService.saveVendorMapping(payload).subscribe({
      next: () => {
        v.isMapped = 1;
        this.toastr.success(`Quota of ${v.allocatedQuota} heads allocated to ${v.vendorName}`, 'Vendor Quota Mapped');
      },
      error: () => this.toastr.error('Failed to update vendor quota.')
    });
  }

  closeVendorModal(): void {
    this.showVendorModal = false;
    this.updateSectionZIndex(false);
  }

  // =========================================================================
  // STEP 6: CANDIDATE REGISTRATION (Vendor App & QR Direct Mobile Site)
  // =========================================================================

  openRegisterModal(job?: any): void {
    this.updateSectionZIndex(true);
    if (job) this.selectedJob = job;
    const targetReqId = this.selectedJob ? this.selectedJob.reqId : (this.jobList[0]?.reqId || 1);
    const targetMrfCode = this.selectedJob ? this.selectedJob.mrfCode : (this.jobList[0]?.mrfCode || 'MRF/2026/01');
    const targetLoc = this.selectedJob ? this.selectedJob.location : 'Hub';
    const targetCompId = this.selectedJob?.fk_companyId || this.selectedJob?.companyId || this.companyId;

    this.candidateForm = {
      reqId: targetReqId,
      mrfCode: targetMrfCode,
      candidateName: '',
      mobile: '',
      email: '',
      gender: 'Male',
      dateOfBirth: '1995-01-01',
      fatherName: '',
      currentLocation: targetLoc,
      sourceType: 'Vendor',
      vendorId: '',
      vendorName: '',
      aadhaarNo: '',
      skillClassification: 'Semi-Skilled'
    };

    // Load staffing vendors from REC_Candidate_Details (IsVendor = 1)
    this.atsService.getVendorsForMapping(targetReqId, targetCompId).subscribe({
      next: (vendors) => {
        this.availableVendors = vendors || [];
        if (this.availableVendors.length > 0) {
          this.candidateForm.vendorId = this.availableVendors[0].vendorId;
          this.candidateForm.vendorName = this.availableVendors[0].vendorName;
        }
      }
    });

    this.registerMode = 'NEW';
    this.selectedPoolAppIds.clear();
    this.loadPoolCandidates();
    this.showRegisterModal = true;
  }

  onVendorSelected(): void {
    const found = this.availableVendors.find(v => v.vendorId === this.candidateForm.vendorId);
    if (found) {
      this.candidateForm.vendorName = found.vendorName;
    }
  }

  registerCandidate(): void {
    if (!this.candidateForm.candidateName.trim() || !this.candidateForm.mobile.trim()) {
      this.toastr.warning('Please enter candidate name and 10-digit mobile number.');
      return;
    }

    const targetJob = this.getSelectedRegistrationJob();
    if (this.isJobFilled(targetJob)) {
      this.toastr.warning(`This position (${targetJob?.jobTitle || 'Job'}) is 100% fulfilled (${this.getJobHiredCount(targetJob)}/${targetJob?.openingsCount} filled). Candidate intake is closed.`, 'Requisition Filled');
      return;
    }

    const payload = {
      reqId: this.candidateForm.reqId,
      candidateName: this.candidateForm.candidateName,
      mobile: this.candidateForm.mobile,
      email: this.candidateForm.email,
      gender: this.candidateForm.gender,
      dateOfBirth: this.candidateForm.dateOfBirth,
      fatherName: this.candidateForm.fatherName,
      currentLocation: this.candidateForm.currentLocation,
      sourceType: this.candidateForm.sourceType,
      vendorId: this.candidateForm.vendorId,
      vendorName: this.candidateForm.vendorName,
      aadhaarNo: this.candidateForm.aadhaarNo ? this.candidateForm.aadhaarNo.trim() : null,
      createdBy: this.currentUserName,
      companyId: this.companyId
    };

    this.isRegisteringCandidate = true;
    this.atsService.registerCandidate(payload).subscribe({
      next: (res) => {
        this.isRegisteringCandidate = false;
        if (res.success || res.Success) {
          this.toastr.success(`Application ${res.applicationNo || ''} created for ${this.candidateForm.candidateName}`, 'Candidate Registered');
          this.showRegisterModal = false;
          this.loadPipelineRoster();
        } else {
          // Both in case of duplicate Aadhaar, duplicate phone, or both:
          // STRICT RULE: Candidate is NOT registered and NOT created in DB. Keep modal open.
          const errMsg = res.message || res.Message || 'Duplicate profile detected. Candidate cannot be registered.';
          this.toastr.error(errMsg, 'Registration Blocked - Duplicate Details', { timeOut: 8000 });
        }
      },
      error: (err) => {
        this.isRegisteringCandidate = false;
        this.toastr.error(err?.error?.message || 'Error submitting candidate registration.');
      }
    });
  }

  closeRegisterModal(): void {
    this.showRegisterModal = false;
    this.updateSectionZIndex(false);
  }

  // =========================================================================
  // EXISTING TALENT POOL (BENCH & REJECTED) ALLOCATION FOR PIPELINE
  // =========================================================================

  setRegisterMode(mode: 'NEW' | 'POOL'): void {
    this.registerMode = mode;
    if (mode === 'POOL') {
      this.loadPoolCandidates();
    }
  }

  openPoolModal(): void {
    if (!this.selectedJob || !this.selectedJob.reqId) {
      this.toastr.warning('Please select an active Job Requisition to allocate pool candidates.', 'Job Required');
      return;
    }
    this.updateSectionZIndex(true);
    this.openRegisterModal(this.selectedJob);
    this.registerMode = 'POOL';
  }

  closePoolModal(): void {
    this.showPoolModal = false;
    this.showRegisterModal = false;
    this.selectedPoolAppIds.clear();
    this.updateSectionZIndex(false);
  }

  loadPoolCandidates(): void {
    this.loadingPool = true;
    const currentReqId = this.selectedJob?.reqId || null;

    // Passing empty vendorId fetches ALL pool candidates across all vendors and direct sources
    this.atsService.getVendorPoolCandidates(
      '',
      currentReqId,
      this.poolSearchQuery,
      this.poolFilterTab,
      this.companyId
    ).subscribe({
      next: (candidates: any[]) => {
        this.poolCandidates = candidates || [];
        this.loadingPool = false;
        this.cdr.detectChanges();
      },
      error: (err) => {
        this.loadingPool = false;
        console.error('Error loading pool candidates:', err);
      }
    });
  }

  get poolVendors(): string[] {
    const vSet = new Set<string>();
    this.poolCandidates.forEach(c => {
      if (c.vendorName && c.vendorName !== 'Direct / Internal') {
        vSet.add(c.vendorName);
      }
    });
    return Array.from(vSet).sort();
  }

  get filteredPoolCandidates(): any[] {
    // Only exclude ACTIVE in-process candidates on this job by unique ID/AppNo
    const activeCandidates = (this.candidateRoster || []).filter((c: any) => !c.isRejected && c.stage !== 'Rejected');
    const activeAppNos = new Set(activeCandidates.map((c: any) => c.applicationNo));
    const activeAppIds = new Set(activeCandidates.map((c: any) => c.appId || c.pk_appId));

    let list = this.poolCandidates.filter(c =>
      !activeAppNos.has(c.applicationNo) &&
      !activeAppIds.has(c.appId)
    );

    if (this.poolFilterTab === 'BENCH') {
      list = list.filter(c => c.poolType === 'BENCH');
    } else if (this.poolFilterTab === 'REJECTED') {
      list = list.filter(c => c.poolType === 'REJECTED');
    }

    if (this.selectedPoolVendor && this.selectedPoolVendor !== 'ALL') {
      list = list.filter(c => c.vendorName === this.selectedPoolVendor);
    }

    if (this.poolSearchQuery && this.poolSearchQuery.trim()) {
      const q = this.poolSearchQuery.toLowerCase().trim();
      list = list.filter(c =>
        (c.candidateName && c.candidateName.toLowerCase().includes(q)) ||
        (c.mobile && c.mobile.includes(q)) ||
        (c.aadhaarNo && c.aadhaarNo.includes(q)) ||
        (c.applicationNo && c.applicationNo.toLowerCase().includes(q)) ||
        (c.vendorName && c.vendorName.toLowerCase().includes(q)) ||
        (c.skillClassification && c.skillClassification.toLowerCase().includes(q))
      );
    }

    return list;
  }

  get poolBenchCount(): number {
    return this.poolCandidates.filter(c => c.poolType === 'BENCH').length;
  }

  get poolRejectedCount(): number {
    return this.poolCandidates.filter(c => c.poolType === 'REJECTED').length;
  }

  toggleSelectAllPool(event: any): void {
    if (event.target.checked) {
      this.filteredPoolCandidates.forEach(c => this.selectedPoolAppIds.add(c.appId));
    } else {
      this.selectedPoolAppIds.clear();
    }
  }

  toggleSelectPoolCandidate(appId: number): void {
    if (this.selectedPoolAppIds.has(appId)) {
      this.selectedPoolAppIds.delete(appId);
    } else {
      this.selectedPoolAppIds.add(appId);
    }
  }

  isPoolCandidateSelected(appId: number): boolean {
    return this.selectedPoolAppIds.has(appId);
  }

  isAllPoolSelected(): boolean {
    const list = this.filteredPoolCandidates;
    if (list.length === 0) return false;
    return list.every(c => this.selectedPoolAppIds.has(c.appId));
  }

  assignSelectedPoolCandidates(): void {
    if (this.selectedPoolAppIds.size === 0) {
      this.toastr.warning('Please select at least one candidate from the pool.', 'No Candidate Selected');
      return;
    }
    if (!this.selectedJob || !this.selectedJob.reqId) {
      this.toastr.error('No target Job Requisition selected.', 'Job Required');
      return;
    }

    const currentReqId = this.selectedJob.reqId;
    const appIdsToAssign = Array.from(this.selectedPoolAppIds);

    this.assigningPoolCandidates = true;
    const payload = {
      reqId: currentReqId,
      vendorId: '', // Empty for HR Pipeline company-wide allocation
      appIds: appIdsToAssign,
      companyId: this.companyId,
      assignedBy: this.currentUserName || sessionStorage.getItem('userName') || 'HR Pipeline'
    };

    this.atsService.assignBenchCandidatesToJob(payload).subscribe({
      next: (res: any) => {
        this.assigningPoolCandidates = false;
        if (res.success || res.Success) {
          this.toastr.success(res.message || `Successfully allocated ${appIdsToAssign.length} candidate(s) to pipeline!`, 'Candidates Allocated');
          this.selectedPoolAppIds.clear();
          this.showPoolModal = false;
          this.loadPipelineRoster();
        } else {
          this.toastr.error(res.message || 'Failed to allocate candidates.', 'Allocation Failed');
        }
      },
      error: (err: any) => {
        this.assigningPoolCandidates = false;
        this.toastr.error(err?.error?.message || 'Error allocating candidates to job.', 'Server Error');
      }
    });
  }

  // QR Code direct link modal
  openQrModal(job: any): void {
    const reqId = job.reqId || 1;
    this.qrData = {
      mrfCode: job.mrfCode || `MRF/${reqId}`,
      jobTitle: job.jobTitle || 'Open Position',
      directUrl: `${window.location.origin}/candidate-apply?mrf=${encodeURIComponent(job.mrfCode || reqId)}&cid=${encodeURIComponent(this.companyId)}`
    };
    this.showQrModal = true;
  }

  copyQrLink(): void {
    navigator.clipboard.writeText(this.qrData.directUrl);
    this.toastr.info('Direct candidate application link copied to clipboard!', 'Link Copied');
  }

  closeQrModal(): void {
    this.showQrModal = false;
  }

  // =========================================================================
  // STEP 7: INTERVIEW SCHEDULING
  // =========================================================================

  openInterviewModal(candidate: any): void {
    if (candidate.stage === 'Applied' && (!candidate.vendorId || !candidate.vendorId.toString().trim())) {
      this.toastr.warning(`Cannot schedule interview for candidate [${candidate.candidateName}]: A staffing vendor must be assigned first.`, 'Staffing Vendor Required');
      this.openAssignVendorModal(candidate, 'Interview_Scheduled');
      return;
    }

    this.selectedCandidate = candidate;
    this.interviewForm = {
      appId: candidate.appId,
      candidateName: candidate.candidateName,
      interviewerId: 'EMP-01',
      interviewerName: 'Anil Sharma (Operations Lead)',
      interviewDate: new Date(Date.now() + 86400000).toISOString().slice(0, 16),
      interviewRound: 'Technical & Operations',
      remarks: 'In-person technical fitness & driving competency assessment'
    };
    this.showInterviewModal = true;
  }

  scheduleInterview(): void {
    if (!this.interviewForm.interviewerName.trim() || !this.interviewForm.interviewDate) {
      this.toastr.warning('Please enter interviewer name and interview date/time.');
      return;
    }

    const payload = {
      appId: this.interviewForm.appId,
      interviewerId: this.interviewForm.interviewerId,
      interviewerName: this.interviewForm.interviewerName,
      interviewDate: this.interviewForm.interviewDate,
      interviewRound: this.interviewForm.interviewRound,
      remarks: this.interviewForm.remarks,
      scheduledBy: this.currentUserName,
      companyId: this.companyId
    };

    this.atsService.scheduleCandidateInterview(payload).subscribe({
      next: (res) => {
        this.toastr.success(`Interview scheduled for ${this.interviewForm.candidateName}`, 'Interview Allocated');
        this.showInterviewModal = false;
        this.loadPipelineRoster();
      },
      error: () => this.toastr.error('Failed to schedule interview.')
    });
  }

  closeInterviewModal(): void {
    this.showInterviewModal = false;
  }

  // =========================================================================
  // STEPS 8 & 9: INTERVIEW EVALUATION & SKILL CLASSIFICATION
  // =========================================================================

  openEvaluationModal(candidate: any): void {
    this.selectedCandidate = candidate;
    this.evaluationForm = {
      appId: candidate.appId,
      candidateName: candidate.candidateName,
      skillClassification: candidate.skillClassification || 'Semi-Skilled',
      decision: candidate.interviewStatus || 'Selected',
      score: candidate.interviewScore || 85,
      remarks: candidate.interviewRemarks || (candidate.interviewStatus === 'Hold' ? 'Candidate placed on hold pending second review.' : 'Candidate cleared technical and operational checks with flying colors.')
    };
    this.showEvaluationModal = true;
  }

  submitEvaluation(): void {
    const payload = {
      appId: this.evaluationForm.appId,
      skillClassification: this.evaluationForm.skillClassification,
      decision: this.evaluationForm.decision,
      score: this.evaluationForm.score,
      remarks: this.evaluationForm.remarks,
      evaluatorName: this.currentUserName,
      companyId: this.companyId
    };

    this.atsService.submitInterviewEvaluation(payload).subscribe({
      next: () => {
        this.toastr.success(`Evaluation recorded as ${this.evaluationForm.decision} (${this.evaluationForm.skillClassification})`, 'Assessment Completed');
        
        // Immediately synchronize candidate in local roster so any modal click displays the evaluation
        const cand = this.candidateRoster?.find(c => c.appId === this.evaluationForm.appId) || this.selectedCandidate;
        if (cand) {
          cand.skillClassification = this.evaluationForm.skillClassification;
          cand.interviewStatus = this.evaluationForm.decision;
          cand.interviewScore = this.evaluationForm.score;
          cand.interviewRemarks = this.evaluationForm.remarks;
          cand.interviewerName = this.currentUserName;
          cand.evaluatedBy = this.currentUserName;
          cand.interviewDate = new Date().toISOString();
          if (this.evaluationForm.decision === 'Selected') cand.stage = 'Selected';
          if (this.evaluationForm.decision === 'Hold') {
            cand.stage = 'Interview_Scheduled';
            cand.interviewStatus = 'Hold';
          }
          if (this.evaluationForm.decision === 'Rejected') cand.stage = 'Rejected';
        }

        this.showEvaluationModal = false;
        this.loadPipelineRoster();
      },
      error: () => this.toastr.error('Failed to submit interview evaluation.')
    });
  }

  closeEvaluationModal(): void {
    this.showEvaluationModal = false;
  }

  // =========================================================================
  // STEPS 10 & 11: 22-POINT ONBOARDING DOCUMENT REVIEW & VERIFICATION SUITE
  // =========================================================================

  openDocsModal(candidate: any): void {
    this.selectedCandidate = candidate;
    this.showDocsModal = true;
    this.docsActiveTab = 'documents';
    this.docsActiveFilter = 'ALL';
    this.docsCandidateHeader = candidate;
    this.docsAuditTrail = [];
    this.loadCandidateDocs(candidate.appId);
    this.loadDocsAuditTrail();
  }

  loadDocsAuditTrail(): void {
    const appId = this.docsCandidateHeader?.appId || this.selectedCandidate?.appId;
    if (!appId) return;
    this.docsAuditLoading = true;
    this.atsService.getCandidateAuditTrail(appId, this.companyId).subscribe({
      next: (logs: any) => {
        this.docsAuditLoading = false;
        this.docsAuditTrail = logs || [];
      },
      error: () => {
        this.docsAuditLoading = false;
        this.docsAuditTrail = [];
        this.toastr.error('Failed to load candidate audit trail');
      }
    });
  }

  openDocsAuditFromHeader(): void {
    const candidate = this.docsCandidateHeader || this.selectedCandidate;
    if (candidate) {
      this.openAuditDrawer(candidate);
    } else {
      this.docsActiveTab = 'audit';
      this.loadDocsAuditTrail();
    }
  }

  loadCandidateDocs(appId: number | string): void {
    this.isLoadingDocs = true;
    this.atsService.getCandidateDocuments(appId, this.companyId).subscribe({
      next: (res: any) => {
        this.isLoadingDocs = false;
        if (res && res.success) {
          this.docsCandidateHeader = res.candidate || this.selectedCandidate;
          this.candidateDocList = res.documents || [];
          this.docsMetrics = {
            totalMandatory: Number(this.docsCandidateHeader.totalMandatory || 0),
            approvedMandatory: Number(this.docsCandidateHeader.approvedMandatory || 0),
            rejectedCount: Number(this.docsCandidateHeader.rejectedCount || 0),
            missingMandatory: Number(this.docsCandidateHeader.missingMandatory || 0)
          };
          this.dossierForm = {
            appId: this.docsCandidateHeader.appId || appId,
            aadhaarNo: this.docsCandidateHeader.aadhaarNo || '',
            panNo: this.docsCandidateHeader.panNo || '',
            bankAccNo: this.docsCandidateHeader.bankAccNo || '',
            bankIfsc: this.docsCandidateHeader.bankIfsc || '',
            bankName: this.docsCandidateHeader.bankName || '',
            nomineeName: this.docsCandidateHeader.nomineeName || '',
            nomineeRelation: this.docsCandidateHeader.nomineeRelation || 'Spouse',
            nomineeDOB: this.docsCandidateHeader.nomineeDOB ? new Date(this.docsCandidateHeader.nomineeDOB).toISOString().slice(0, 10) : '',
            nomineeContact: this.docsCandidateHeader.nomineeContact || '',
            uanNo: this.docsCandidateHeader.uanNo || '',
            esicNo: this.docsCandidateHeader.esicNo || ''
          };
          this.docsForm = {
            appId: this.docsCandidateHeader.appId,
            candidateName: this.docsCandidateHeader.candidateName,
            aadhaarNo: this.docsCandidateHeader.aadhaarNo || '',
            aadhaarDocPath: '/uploads/docs/aadhaar.pdf',
            panNo: this.docsCandidateHeader.panNo || '',
            panDocPath: '/uploads/docs/pan.pdf',
            bankAccNo: this.docsCandidateHeader.bankAccNo || '',
            bankIfsc: this.docsCandidateHeader.bankIfsc || '',
            bankName: this.docsCandidateHeader.bankName || '',
            photoDocPath: '/uploads/docs/passport_photo.jpg',
            resumeDocPath: '/uploads/docs/resume.pdf',
            verificationRemarks: this.docsCandidateHeader.deficiencyRemarks || 'Verified against physical records'
          };
        }
      },
      error: () => {
        this.isLoadingDocs = false;
        this.toastr.error('Failed to load candidate document dossier.', 'Error');
      }
    });
  }

  onDocFileSelected(event: any, docTypeCode: string): void {
    const file: File = event.target.files?.[0];
    if (!file) return;

    // Point o: Validate format (PDF/JPG/JPEG/PNG) and size (<= 5MB)
    const allowedExtensions = ['.pdf', '.jpg', '.jpeg', '.png'];
    const ext = file.name.substring(file.name.lastIndexOf('.')).toLowerCase();
    if (!allowedExtensions.includes(ext)) {
      this.toastr.error('Invalid file format. Only PDF, JPG, JPEG, and PNG files are allowed.', 'Format Validation');
      event.target.value = '';
      return;
    }

    const maxSizeInBytes = 5 * 1024 * 1024; // 5 MB
    if (file.size > maxSizeInBytes) {
      this.toastr.error('File size exceeds the 5 MB limit. Please select a smaller file.', 'Size Validation');
      event.target.value = '';
      return;
    }

    const formData = new FormData();
    const appId = String(this.docsCandidateHeader?.appId || this.selectedCandidate?.appId);
    formData.append('appId', appId);
    formData.append('docTypeCode', docTypeCode);
    formData.append('companyId', this.companyId);
    formData.append('file', file);

    this.isUploadingDoc[docTypeCode] = true;
    this.atsService.uploadCandidateDocument(formData).subscribe({
      next: () => {
        this.isUploadingDoc[docTypeCode] = false;
        event.target.value = '';
        this.toastr.success(`Document uploaded successfully for verification.`, 'Upload Complete');
        this.loadCandidateDocs(appId);
        this.loadPipelineRoster();
      },
      error: () => {
        this.isUploadingDoc[docTypeCode] = false;
        event.target.value = '';
        this.toastr.error('Failed to upload document. Please retry.', 'Upload Error');
      }
    });
  }

  verifyDocItem(doc: any, status: 'Approved' | 'Rejected'): void {
    if (status === 'Rejected') {
      this.selectedDocForReject = doc;
      this.docRejectionRemark = doc.rejectionRemarks || '';
      this.showDocRejectModal = true;
      return;
    }

    const payload = {
      appId: doc.appId || this.docsCandidateHeader?.appId,
      docTypeCode: doc.docTypeCode,
      status: 'Approved',
      rejectionRemarks: '',
      verifiedBy: this.currentUserName,
      companyId: this.companyId
    };

    this.atsService.verifyCandidateDocumentItem(payload).subscribe({
      next: () => {
        this.toastr.success(`${doc.docTypeName} approved successfully.`, 'Verified');
        this.loadCandidateDocs(doc.appId || this.docsCandidateHeader?.appId);
        this.loadPipelineRoster();
      },
      error: () => this.toastr.error('Failed to approve document.')
    });
  }

  submitDocRejection(): void {
    if (!this.docRejectionRemark || !this.docRejectionRemark.trim()) {
      this.toastr.warning('Please state the deficiency or rejection reason.', 'Remarks Required');
      return;
    }

    const payload = {
      appId: this.selectedDocForReject.appId || this.docsCandidateHeader?.appId,
      docTypeCode: this.selectedDocForReject.docTypeCode,
      status: 'Rejected',
      rejectionRemarks: this.docRejectionRemark.trim(),
      verifiedBy: this.currentUserName,
      companyId: this.companyId
    };

    this.atsService.verifyCandidateDocumentItem(payload).subscribe({
      next: () => {
        this.toastr.warning(`Document rejected. Vendor/Candidate notified to re-upload.`, 'Deficiency Alert');
        this.showDocRejectModal = false;
        this.selectedDocForReject = null;
        this.docRejectionRemark = '';
        this.loadCandidateDocs(this.docsCandidateHeader?.appId);
        this.loadPipelineRoster();
      },
      error: () => this.toastr.error('Failed to reject document.')
    });
  }

  closeDocRejectModal(): void {
    this.showDocRejectModal = false;
    this.selectedDocForReject = null;
    this.docRejectionRemark = '';
  }

  approveAllPendingDocs(): void {
    const eligibleDocs = this.candidateDocList.filter(d => d.fileName && d.verificationStatus !== 'Approved');
    if (eligibleDocs.length === 0) {
      this.toastr.info('No pending uploaded documents awaiting approval.', 'Up to Date');
      return;
    }

    let count = 0;
    eligibleDocs.forEach(doc => {
      const payload = {
        appId: doc.appId || this.docsCandidateHeader?.appId,
        docTypeCode: doc.docTypeCode,
        status: 'Approved',
        rejectionRemarks: '',
        verifiedBy: this.currentUserName,
        companyId: this.companyId
      };
      this.atsService.verifyCandidateDocumentItem(payload).subscribe({
        next: () => {
          count++;
          if (count === eligibleDocs.length) {
            this.toastr.success(`All ${count} pending documents have been verified and approved.`, 'Batch Approval');
            this.loadCandidateDocs(this.docsCandidateHeader?.appId);
            this.loadPipelineRoster();
          }
        }
      });
    });
  }

  saveCandidateDossier(): void {
    this.isSavingDossier = true;
    const payload = {
      ...this.dossierForm,
      companyId: this.companyId,
      submittedBy: this.currentUserName
    };

    this.atsService.saveCandidateOnboardingDossier(payload).subscribe({
      next: () => {
        this.isSavingDossier = false;
        this.toastr.success('Statutory, Bank, and Nominee details saved.', 'Dossier Saved');
        this.loadCandidateDocs(this.dossierForm.appId);
        this.loadPipelineRoster();
      },
      error: () => {
        this.isSavingDossier = false;
        this.toastr.error('Failed to save dossier details.');
      }
    });
  }

  // =========================================================================
  // SEND CANDIDATE FROM 'SELECTED' TO 'DOCS REVIEW' (STAGE TRANSITION WITH DOCS)
  // =========================================================================
  sendCandidateToDocsReview(): void {
    const appId = this.docsCandidateHeader?.appId || this.selectedCandidate?.appId;
    if (!appId) return;

    // Check how many documents have been attached
    const uploadedDocs = this.candidateDocList.filter(d => d.fileName && d.fileName.trim() !== '');
    if (uploadedDocs.length === 0) {
      this.toastr.warning('Please upload at least one mandatory document (e.g. Aadhaar, Photo, or Resume) before sending to Docs Review.', 'Upload Required');
      return;
    }

    this.isSavingDossier = true;
    const dossierPayload = {
      ...this.dossierForm,
      companyId: this.companyId,
      submittedBy: this.currentUserName
    };

    this.atsService.saveCandidateOnboardingDossier(dossierPayload).subscribe({
      next: () => {
        this.isSavingDossier = false;
        // Advance candidate stage from Selected -> Docs_Submitted (Docs Review)
        const stagePayload = {
          appId: appId,
          targetStage: 'Docs_Submitted',
          remarks: `Onboarding documents collected (${uploadedDocs.length} uploaded) and forwarded to Docs Review for HR verification.`,
          movedBy: this.currentUserName,
          companyId: this.companyId
        };

        this.atsService.moveCandidateStage(stagePayload).subscribe({
          next: () => {
            this.toastr.success('Candidate documents submitted successfully! Candidate forwarded to Docs Review for HR verification.', 'Sent to Docs Review');
            this.closeDocsModal();
            this.loadPipelineRoster();
          },
          error: () => this.toastr.error('Failed to forward candidate to Docs Review.')
        });
      },
      error: () => {
        this.isSavingDossier = false;
        this.toastr.error('Failed to save candidate dossier.');
      }
    });
  }

  completeOnboarding(): void {
    const unapprovedMandatory = this.candidateDocList.filter(d => d.isMandatory && d.verificationStatus !== 'Approved');
    if (unapprovedMandatory.length > 0) {
      const names = unapprovedMandatory.map(d => d.docTypeName).join(', ');
      this.toastr.error(`Cannot complete onboarding: ${unapprovedMandatory.length} mandatory document(s) still require approval (${names}).`, 'Documents Verification Incomplete');
      return;
    }

    const payload = {
      appId: this.docsCandidateHeader?.appId || this.selectedCandidate?.appId,
      targetStage: 'Docs_Verified',
      remarks: 'All mandatory onboarding documents approved by Site HR.',
      movedBy: this.currentUserName,
      companyId: this.companyId
    };

    this.atsService.moveCandidateStage(payload).subscribe({
      next: (res: any) => {
        if (res && (res.success === false || res.Success === 0)) {
          this.toastr.error(res.message || res.Message || 'Failed to verify candidate documents.', 'Verification Alert');
          return;
        }
        this.toastr.success('Candidate documents successfully verified and approved! Moved to Docs Verified.', 'Onboarding Completed');
        this.closeDocsModal();
        this.loadPipelineRoster();
      },
      error: () => this.toastr.error('Failed to update candidate onboarding status.')
    });
  }

  getFilteredCandidateDocs(): any[] {
    if (!this.candidateDocList) return [];
    switch (this.docsActiveFilter) {
      case 'MANDATORY':
        return this.candidateDocList.filter(d => d.isMandatory);
      case 'PENDING':
        return this.candidateDocList.filter(d => d.verificationStatus === 'Pending' || (d.fileName && d.verificationStatus !== 'Approved'));
      case 'APPROVED':
        return this.candidateDocList.filter(d => d.verificationStatus === 'Approved');
      case 'REJECTED':
        return this.candidateDocList.filter(d => d.verificationStatus === 'Rejected' || d.verificationStatus === 'Missing');
      default:
        return this.candidateDocList;
    }
  }

  formatFileSize(bytes: number | null): string {
    if (!bytes || bytes === 0) return '—';
    if (bytes < 1024) return bytes + ' B';
    const kb = bytes / 1024;
    if (kb < 1024) return kb.toFixed(1) + ' KB';
    const mb = kb / 1024;
    return mb.toFixed(1) + ' MB';
  }

  getOnboardingProgressPercent(): number {
    if (!this.docsMetrics.totalMandatory || this.docsMetrics.totalMandatory === 0) return 0;
    return Math.min(100, Math.round((this.docsMetrics.approvedMandatory / this.docsMetrics.totalMandatory) * 100));
  }

  openDocFile(doc: any): void {
    if (!doc.fileName && !doc.filePath) {
      this.toastr.info('No document file attached to view.', 'Empty');
      return;
    }
    const appId = doc.appId || this.docsCandidateHeader?.appId;
    const viewUrl = this.atsService.getDocumentViewUrl(doc.docId, appId, doc.docTypeCode);
    this.previewDocUrl = viewUrl;
    this.previewDocName = doc.docTypeName || doc.fileName || doc.docTypeCode;
    this.showDocPreviewModal = true;
  }

  openDocInNewWindow(doc?: any): void {
    const appId = doc?.appId || this.docsCandidateHeader?.appId;
    const url = doc 
      ? this.atsService.getDocumentViewUrl(doc.docId, appId, doc.docTypeCode)
      : this.previewDocUrl;
    if (url) {
      window.open(url, '_blank');
    }
  }

  closeDocPreviewModal(): void {
    this.showDocPreviewModal = false;
    this.previewDocUrl = '';
    this.previewDocName = '';
  }

  getSafeUrl(url: string): SafeResourceUrl {
    return this.sanitizer.bypassSecurityTrustResourceUrl(url);
  }

  saveDocs(): void {
    this.saveCandidateDossier();
  }

  verifyDocs(isApproved: boolean): void {
    if (isApproved) {
      this.approveAllPendingDocs();
    } else {
      this.toastr.info('Please reject individual deficient documents using the reject button on each row.', 'Doc Rejection');
    }
  }

  closeDocsModal(): void {
    this.showDocsModal = false;
    this.docsCandidateHeader = null;
    this.candidateDocList = [];
    this.showDocRejectModal = false;
  }

  // =========================================================================
  // STEP 12: CANDIDATE ID & OFFER LETTER
  // =========================================================================

  openOfferModal(candidate: any): void {
    this.selectedCandidate = candidate;
    this.offerForm = {
      appId: candidate.appId,
      candidateName: candidate.candidateName,
      offeredCTC: candidate.offeredCTC || 380000,
      expectedJoiningDate: new Date(Date.now() + 14 * 86400000).toISOString().slice(0, 10)
    };
    this.showOfferModal = true;
  }

  generateOfferLetter(): void {
    if (!this.offerForm.offeredCTC || !this.offerForm.expectedJoiningDate) {
      this.toastr.warning('Please specify CTC and Expected Joining Date.');
      return;
    }

    const payload = {
      appId: this.offerForm.appId,
      offeredCTC: this.offerForm.offeredCTC,
      expectedJoiningDate: this.offerForm.expectedJoiningDate,
      issuedBy: this.currentUserName,
      companyId: this.companyId
    };

    this.atsService.generateOfferLetter(payload).subscribe({
      next: (res) => {
        this.toastr.success(`Offer generated: ${res.offerCode || ''} with Candidate Code ${res.candidateCode || ''}`, 'Offer Letter Issued');
        this.showOfferModal = false;
        this.loadPipelineRoster();
      },
      error: () => this.toastr.error('Failed to generate offer letter.')
    });
  }

  closeOfferModal(): void {
    this.showOfferModal = false;
  }

  // =========================================================================
  // STEP 13: 1-CLICK HIRE & TRANSFER TO EMPLOYEE MASTER
  // =========================================================================

  hireCandidate(candidate: any): void {
    if (!confirm(`Are you sure you want to finalize onboarding and transfer ${candidate.candidateName} to Employee Master (SAL_Employee_Mst)?`)) {
      return;
    }

    const payload = {
      appId: candidate.appId,
      hiredBy: this.currentUserName,
      companyId: this.companyId
    };

    this.atsService.hireAndTransferCandidate(payload).subscribe({
      next: (res) => {
        this.toastr.success(`Candidate onboarded as Employee ${res.employeeCode || ''} (ID: ${res.empId || ''})!`, 'Hired & Transferred');
        this.loadPipelineRoster();
      },
      error: () => this.toastr.error('Error during onboarding transfer.')
    });
  }

  // =========================================================================
  // STEPS 14 & 15: CANDIDATE LIFECYCLE AUDIT TRAIL TIMELINE
  // =========================================================================

  openAuditDrawer(candidate: any): void {
    if (!candidate) return;
    this.selectedCandidate = candidate;
    this.auditTrail = [];
    this.showAuditDrawer = true;
    this.cdr.detectChanges();

    const appId = candidate.appId || candidate.applicationId || candidate.id || this.selectedCandidate?.appId;
    if (!appId) {
      this.toastr.warning('Candidate application ID not found.');
      return;
    }

    this.atsService.getCandidateAuditTrail(appId, this.companyId).subscribe({
      next: (logs) => {
        this.auditTrail = logs || [];
        this.showAuditDrawer = true;
        this.cdr.detectChanges();
      },
      error: () => {
        this.toastr.error('Failed to load audit history.');
        this.cdr.detectChanges();
      }
    });
  }

  closeAuditDrawer(): void {
    this.showAuditDrawer = false;
    this.cdr.detectChanges();
  }

  openCandidateDetails(candidate: any): void {
    this.selectedCandidateDetails = candidate;
    this.showCandidateDetailsModal = true;
    this.cdr.detectChanges();
  }

  closeCandidateDetails(): void {
    this.showCandidateDetailsModal = false;
    this.selectedCandidateDetails = null;
    this.cdr.detectChanges();
  }

  // =========================================================================
  // ASSIGN STAFFING VENDOR (Company-wise & Location-wise)
  // =========================================================================
  openAssignVendorModal(candidate: any, pendingStage?: string): void {
    if (!candidate) return;
    this.assignVendorCandidate = candidate;
    this.selectedVendorForAssignment = candidate.vendorId || '';
    this.assignVendorRemarks = '';
    this.pendingTargetStage = pendingStage || null;
    this.showAssignVendorModal = true;
    this.isLoadingVendors = true;
    this.assignVendorList = [];

    const targetLoc = candidate.operatingHub || candidate.currentLocation || (this.selectedJob ? (this.selectedJob.locationName || this.selectedJob.locName) : '');
    const targetReqId = candidate.reqId || (this.selectedJob ? this.selectedJob.reqId : undefined);

    this.atsService.getVendorsByLocation(this.companyId, targetLoc, targetReqId).subscribe({
      next: (vendors) => {
        this.isLoadingVendors = false;
        this.assignVendorList = vendors || [];
        if (!this.selectedVendorForAssignment && this.assignVendorList.length > 0) {
          this.selectedVendorForAssignment = this.assignVendorList[0].vendorId;
        }
        this.cdr.detectChanges();
      },
      error: (err) => {
        this.isLoadingVendors = false;
        console.error('Error fetching vendors by location:', err);
        this.toastr.error('Failed to load empanelled staffing vendors.');
        this.cdr.detectChanges();
      }
    });
    this.cdr.detectChanges();
  }

  closeAssignVendorModal(): void {
    this.showAssignVendorModal = false;
    this.assignVendorCandidate = null;
    this.pendingTargetStage = null;
    this.cdr.detectChanges();
  }

  submitAssignVendor(): void {
    if (!this.assignVendorCandidate || !this.selectedVendorForAssignment) {
      this.toastr.warning('Please select a staffing vendor to assign.', 'Selection Required');
      return;
    }

    const selectedVendor = this.assignVendorList.find(v => v.vendorId === this.selectedVendorForAssignment);
    const vendorName = selectedVendor ? selectedVendor.vendorName : 'Staffing Partner';

    const payload = {
      appId: this.assignVendorCandidate.appId,
      vendorId: this.selectedVendorForAssignment,
      vendorName: vendorName,
      assignedBy: this.currentUserName,
      remarks: this.assignVendorRemarks,
      companyId: this.companyId
    };

    this.isAssigningVendor = true;
    this.atsService.assignVendorToCandidate(payload).subscribe({
      next: (res: any) => {
        this.isAssigningVendor = false;
        this.toastr.success(`Staffing vendor [${vendorName}] assigned to ${this.assignVendorCandidate.candidateName} successfully!`, 'Vendor Assigned');

        // Update in-memory candidate details
        if (this.assignVendorCandidate) {
          this.assignVendorCandidate.vendorId = this.selectedVendorForAssignment;
          this.assignVendorCandidate.vendorName = vendorName;
          this.assignVendorCandidate.sourceType = 'Vendor';
        }
        if (this.selectedCandidateDetails && this.selectedCandidateDetails.appId === this.assignVendorCandidate.appId) {
          this.selectedCandidateDetails.vendorId = this.selectedVendorForAssignment;
          this.selectedCandidateDetails.vendorName = vendorName;
          this.selectedCandidateDetails.sourceType = 'Vendor';
        }

        const nextStageToProceed = this.pendingTargetStage;
        const candidateToProceed = this.assignVendorCandidate;
        this.closeAssignVendorModal();
        this.loadPipelineRoster();

        // If there was a pending stage progression, proceed with it now!
        if (nextStageToProceed && candidateToProceed) {
          if (nextStageToProceed === 'Interview_Scheduled') {
            this.openInterviewModal(candidateToProceed);
          } else {
            this.quickMoveStage(candidateToProceed, nextStageToProceed);
          }
        }
      },
      error: (err: any) => {
        this.isAssigningVendor = false;
        const errMsg = err?.error?.message || err?.message || 'Failed to assign staffing vendor.';
        this.toastr.error(errMsg, 'Assignment Error');
      }
    });
  }

  // =========================================================================
  // JOB REQUISITION DETAILS SLIDE-OVER DRAWER (Mirroring MRF List)
  // =========================================================================
  showJobDetailDrawer: boolean = false;
  selectedJobForDetail: any = null;

  openJobDetail(job: any): void {
    if (!job) return;
    this.selectedJobForDetail = job;
    this.showJobDetailDrawer = true;
    this.cdr.detectChanges();
  }

  closeJobDetail(): void {
    this.showJobDetailDrawer = false;
    this.selectedJobForDetail = null;
    this.cdr.detectChanges();
  }

  // =========================================================================
  // CANDIDATE TAGGING & CLASSIFICATION (Step 2, 7, 8)
  // =========================================================================

  openTagModal(candidate: any): void {
    this.selectedCandidate = candidate;
    this.tagForm = {
      appId: candidate.appId,
      reqId: candidate.reqId || (this.selectedJob ? this.selectedJob.reqId : 0),
      candidateName: candidate.candidateName,
      mrfCode: candidate.mrfCode || (this.selectedJob ? this.selectedJob.mrfCode : ''),
      skillClassification: candidate.skillClassification || 'Semi-Skilled',
      isDiversityHiring: !!candidate.isDiversityHiring,
      candidateTags: candidate.candidateTags || '',
      assignedReviewer: candidate.assignedReviewer || 'Site HR',
      remarks: ''
    };
    this.showTagModal = true;
  }

  submitTagCandidate(): void {
    if (!this.tagForm.appId) return;

    const payload = {
      appId: this.tagForm.appId,
      reqId: this.tagForm.reqId,
      skillClassification: this.tagForm.skillClassification,
      candidateTags: this.tagForm.candidateTags,
      isDiversityHiring: this.tagForm.isDiversityHiring,
      assignedReviewer: this.tagForm.assignedReviewer,
      remarks: this.tagForm.remarks,
      taggedBy: this.currentUserName,
      companyId: this.companyId
    };

    this.atsService.tagCandidate(payload).subscribe({
      next: () => {
        this.toastr.success(`Candidate tagged successfully (${this.tagForm.skillClassification}).`, 'Tagging Updated');
        this.showTagModal = false;
        this.loadPipelineRoster();
      },
      error: () => this.toastr.error('Failed to update candidate tags.')
    });
  }

  closeTagModal(): void {
    this.showTagModal = false;
  }

  // =========================================================================
  // STAGE PROGRESSION - MOVE TO NEXT STAGES (Company-Configured DB Workflow)
  // =========================================================================

  /** Get the human-readable label for any stage code */
  getStageLabel(stageCode: string): string {
    if (!stageCode) return '';
    const s = this.stages.find(st => st.code === stageCode) || 
              this.allStageConfigs.find((st: any) => (st.stageCode || st.StageCode) === stageCode);
    return s ? (s.label || s.stageLabel || s.StageLabel) : stageCode.replace(/_/g, ' ');
  }

  /**
   * Find the exact next enabled stage configured in the database for this company.
   * Strictly enforces moving step-by-step according to company stage configurations.
   */
  getNextStageForCandidate(candidate: any): { code: string; label: string; icon: string; color: string } | null {
    if (!candidate || !this.stages || this.stages.length === 0) return null;
    const currentCode = (candidate.stage === 'Hold' || candidate.stage === 'Interview_Completed') ? 'Interview_Scheduled' : candidate.stage;
    if (currentCode === 'Hired' || currentCode === 'Rejected') return null;

    const currentIndex = this.stages.findIndex(s => s.code === currentCode);
    if (currentIndex >= 0 && currentIndex < this.stages.length - 1) {
      return this.stages[currentIndex + 1];
    }
    // If candidate's current stage is not found in active stages, fallback to the first active stage
    if (currentIndex === -1 && this.stages.length > 0) {
      return this.stages[0];
    }
    return null;
  }

  openStageMoveModal(candidate: any): void {
    if (!candidate) return;
    this.selectedCandidate = candidate;
    const nextStage = this.getNextStageForCandidate(candidate);
    if (!nextStage) {
      this.toastr.info(`Candidate is already at the final stage (${this.getStageLabel(candidate.stage)}) or no further stage is configured in DB.`, 'Final Stage');
      return;
    }

    // MANDATORY INTERCEPT: If moving from 'Selected' to 'Docs Review' (Docs_Submitted),
    // we must collect candidate documents first!
    if (candidate.stage === 'Selected' && (nextStage.code === 'Docs_Submitted' || nextStage.code === 'DOCS')) {
      this.openDocsModal(candidate);
      return;
    }

    // MANDATORY INTERCEPT: If candidate is currently in 'Docs_Submitted' (Docs Review),
    // ALL mandatory documents must be verified and approved before proceeding!
    if (candidate.stage === 'Docs_Submitted') {
      this.atsService.getCandidateDocuments(candidate.appId, this.companyId).subscribe({
        next: (res: any) => {
          if (res && res.success) {
            const docs: any[] = res.documents || [];
            const unapproved = docs.filter((d: any) => d.isMandatory && d.verificationStatus !== 'Approved');
            if (unapproved.length > 0) {
              const names = unapproved.map((d: any) => d.docTypeName).join(', ');
              this.toastr.warning(`Cannot advance past Docs Review: ${unapproved.length} mandatory document(s) still require approval (${names}). Opening Document Verification Suite...`, 'Verification Required');
              this.openDocsModal(candidate);
              return;
            }
          }
          this.proceedOpenStageMoveModal(candidate, nextStage);
        },
        error: () => this.proceedOpenStageMoveModal(candidate, nextStage)
      });
      return;
    }

    // MANDATORY INTERCEPT: If candidate is currently in 'Applied',
    // a staffing vendor MUST be assigned before advancing!
    if (candidate.stage === 'Applied' && (!candidate.vendorId || !candidate.vendorId.toString().trim())) {
      this.toastr.warning(`Cannot advance candidate [${candidate.candidateName}] from Applied stage: A staffing vendor must be assigned first.`, 'Staffing Vendor Required');
      this.openAssignVendorModal(candidate, nextStage.code);
      return;
    }

    this.proceedOpenStageMoveModal(candidate, nextStage);
  }

  proceedOpenStageMoveModal(candidate: any, nextStage: any): void {
    this.stageMoveForm = {
      appId: candidate.appId,
      candidateName: candidate.candidateName,
      applicationNo: candidate.applicationNo || ('APP-' + candidate.appId),
      jobTitle: candidate.jobTitle || this.selectedJob?.designationName || 'Position Candidate',
      currentStage: candidate.stage,
      currentStageLabel: this.getStageLabel(candidate.stage),
      recommendedStage: nextStage.code,
      targetStage: nextStage.code,
      targetStageLabel: nextStage.label,
      remarks: ''
    };
    this.showStageMoveModal = true;
    this.cdr.detectChanges();
  }

  onTargetStageChange(newStageCode: string): void {
    this.stageMoveForm.targetStage = newStageCode;
    this.stageMoveForm.targetStageLabel = this.getStageLabel(newStageCode);
  }

  setStageMoveRemark(preset: string): void {
    if (this.stageMoveForm.remarks) {
      this.stageMoveForm.remarks += ', ' + preset;
    } else {
      this.stageMoveForm.remarks = preset;
    }
  }

  quickMoveCandidateToNextStage(candidate: any): void {
    const nextStage = this.getNextStageForCandidate(candidate);
    if (!nextStage) {
      this.toastr.info('No subsequent step configured in DB for this candidate.');
      return;
    }
    // Intercept quick move from Applied if vendor is not assigned
    if (candidate.stage === 'Applied' && (!candidate.vendorId || !candidate.vendorId.toString().trim())) {
      this.toastr.warning(`Cannot advance candidate [${candidate.candidateName}] from Applied stage: A staffing vendor must be assigned first.`, 'Staffing Vendor Required');
      this.openAssignVendorModal(candidate, nextStage.code);
      return;
    }
    // Intercept quick move from Selected to Docs Review as well
    if (candidate.stage === 'Selected' && (nextStage.code === 'Docs_Submitted' || nextStage.code === 'DOCS')) {
      this.openDocsModal(candidate);
      return;
    }
    // Intercept quick move from Docs Review to ensure all documents are approved
    if (candidate.stage === 'Docs_Submitted') {
      this.openStageMoveModal(candidate);
      return;
    }
    this.quickMoveStage(candidate, nextStage.code);
  }

  quickMoveStage(candidate: any, targetStage: string): void {
    // Intercept quick move from Applied if vendor is not assigned
    if (candidate.stage === 'Applied' && targetStage !== 'Applied' && targetStage !== 'Rejected') {
      if (!candidate.vendorId || !candidate.vendorId.toString().trim()) {
        this.toastr.warning(`Cannot advance candidate [${candidate.candidateName}] from Applied stage: A staffing vendor must be assigned first.`, 'Staffing Vendor Required');
        this.openAssignVendorModal(candidate, targetStage);
        return;
      }
    }

    const targetLabel = this.getStageLabel(targetStage);
    const payload = {
      appId: candidate.appId,
      targetStage: targetStage,
      remarks: `Quick transition to ${targetLabel} stage confirmed by recruiter`,
      movedBy: this.currentUserName,
      companyId: this.companyId
    };

    this.atsService.moveCandidateStage(payload).subscribe({
      next: (res: any) => {
        if (res && (res.success === false || res.Success === 0)) {
          this.toastr.error(res.message || res.Message || 'Failed to move candidate stage.', 'Validation Alert');
          return;
        }
        this.toastr.success(`Candidate advanced to ${targetLabel} stage!`, 'Stage Updated');
        this.loadPipelineRoster();
      },
      error: () => this.toastr.error('Failed to transition candidate stage.')
    });
  }

  submitStageMove(): void {
    if (!this.stageMoveForm.targetStage) {
      this.toastr.warning('Target stage is missing.');
      return;
    }

    // Intercept moving from Applied without vendor
    if (this.stageMoveForm.currentStage === 'Applied' && this.stageMoveForm.targetStage !== 'Applied' && this.stageMoveForm.targetStage !== 'Rejected') {
      const cand = this.candidateRoster.find(c => c.appId === this.stageMoveForm.appId) || this.selectedCandidate;
      if (!cand?.vendorId || !cand.vendorId.toString().trim()) {
        this.toastr.warning(`Cannot advance candidate [${this.stageMoveForm.candidateName}] from Applied stage: A staffing vendor must be assigned first.`, 'Staffing Vendor Required');
        this.showStageMoveModal = false;
        this.openAssignVendorModal(cand, this.stageMoveForm.targetStage);
        return;
      }
    }

    // If moving to Hired stage, trigger official onboarding transfer to Employee Master
    if (this.stageMoveForm.targetStage === 'Hired' || this.stageMoveForm.targetStage === 'HIRED') {
      const candidate = this.selectedCandidate;
      this.showStageMoveModal = false;
      this.hireCandidate(candidate);
      return;
    }

    const payload = {
      appId: this.stageMoveForm.appId,
      targetStage: this.stageMoveForm.targetStage,
      remarks: this.stageMoveForm.remarks || `Moved to ${this.stageMoveForm.targetStageLabel || this.stageMoveForm.targetStage}`,
      movedBy: this.currentUserName,
      companyId: this.companyId
    };

    this.loaderService.start();
    this.atsService.moveCandidateStage(payload).subscribe({
      next: (res: any) => {
        this.loaderService.stop();
        if (res && (res.success === false || res.Success === 0)) {
          this.toastr.error(res.message || res.Message || 'Failed to move candidate stage.', 'Validation Alert');
          return;
        }
        const label = this.stageMoveForm.targetStageLabel || this.getStageLabel(this.stageMoveForm.targetStage);
        this.toastr.success(`Candidate moved to ${label} stage.`, 'Stage Progression');
        this.showStageMoveModal = false;
        this.cdr.detectChanges();
        this.loadPipelineRoster();
      },
      error: () => {
        this.loaderService.stop();
        this.toastr.error('Failed to move candidate stage.');
      }
    });
  }

  closeStageMoveModal(): void {
    this.showStageMoveModal = false;
    this.cdr.detectChanges();
  }

  // =========================================================================
  // MULTI-CANDIDATE SELECTION & BATCH STAGE PROGRESSION
  // =========================================================================

  isCandidateSelected(candidate: any): boolean {
    if (!candidate || !candidate.appId) return false;
    return this.selectedCandidateIds.has(Number(candidate.appId));
  }

  toggleCandidateSelection(candidate: any, event?: Event): void {
    if (event) {
      event.stopPropagation();
    }
    if (!candidate || !candidate.appId) return;

    if (this.isCandidateRejected(candidate)) {
      this.toastr.warning('Rejected candidate is locked and cannot be selected for stage progression.', 'Locked Candidate');
      return;
    }
    if (candidate.stage === 'Hired') {
      this.toastr.info('Candidate is already hired and completed the lifecycle.', 'Joined');
      return;
    }

    const appId = Number(candidate.appId);
    const newSet = new Set(this.selectedCandidateIds);
    if (newSet.has(appId)) {
      newSet.delete(appId);
    } else {
      newSet.add(appId);
    }
    this.selectedCandidateIds = newSet;
  }

  getActiveCandidatesInCurrentStage(): any[] {
    return this.getCandidatesForSelectedStage().filter(
      c => !this.isCandidateRejected(c) && c.stage !== 'Hired'
    );
  }

  areAllInSelectedStageSelected(): boolean {
    const active = this.getActiveCandidatesInCurrentStage();
    if (active.length === 0) return false;
    return active.every(c => this.selectedCandidateIds.has(Number(c.appId)));
  }

  isSomeInSelectedStageSelected(): boolean {
    if (this.areAllInSelectedStageSelected()) return false;
    const active = this.getActiveCandidatesInCurrentStage();
    return active.some(c => this.selectedCandidateIds.has(Number(c.appId)));
  }

  toggleSelectAllInStage(event?: any): void {
    if (event) {
      event.stopPropagation();
    }
    const active = this.getActiveCandidatesInCurrentStage();
    if (active.length === 0) return;

    const newSet = new Set(this.selectedCandidateIds);
    if (this.areAllInSelectedStageSelected()) {
      active.forEach(c => newSet.delete(Number(c.appId)));
    } else {
      active.forEach(c => newSet.add(Number(c.appId)));
    }
    this.selectedCandidateIds = newSet;
  }

  clearSelection(): void {
    this.selectedCandidateIds = new Set<number>();
  }

  getSelectedCandidatesCount(): number {
    return this.selectedCandidateIds.size;
  }

  getSelectedCandidates(): any[] {
    return this.candidateRoster.filter(c => this.selectedCandidateIds.has(Number(c.appId)));
  }

  batchMoveSelectedToNextStage(): void {
    const candidates = this.getSelectedCandidates().filter(c => !this.isCandidateRejected(c) && c.stage !== 'Hired');
    if (candidates.length === 0) {
      this.toastr.warning('Please select at least one active candidate to advance.', 'No Selection');
      return;
    }

    const eligibleCandidates = candidates.filter(c => this.getNextStageForCandidate(c) !== null);
    if (eligibleCandidates.length === 0) {
      this.toastr.info('Selected candidates are already at their final configured stage.', 'Final Stage');
      return;
    }

    this.isBatchMoving = true;
    this.loaderService.start();
    const moveObservables = eligibleCandidates.map(c => {
      const nextStage = this.getNextStageForCandidate(c)!;
      const payload = {
        appId: c.appId,
        targetStage: nextStage.code,
        remarks: `Bulk stage transition to ${nextStage.label} confirmed by recruiter`,
        movedBy: this.currentUserName,
        companyId: this.companyId
      };
      return this.atsService.moveCandidateStage(payload).pipe(
        catchError(err => of({ error: true, candidate: c, err }))
      );
    });

    forkJoin(moveObservables).subscribe({
      next: (results: any[]) => {
        this.loaderService.stop();
        this.isBatchMoving = false;
        const failed = results.filter(r => r && r.error).length;
        const successful = results.length - failed;

        if (successful > 0) {
          this.toastr.success(`Advanced ${successful} candidate(s) to their next stage successfully!`, 'Batch Movement Complete');
        }
        if (failed > 0) {
          this.toastr.error(`Failed to transition ${failed} candidate(s).`, 'Partial Failure');
        }

        this.clearSelection();
        this.loadPipelineRoster();
      },
      error: () => {
        this.loaderService.stop();
        this.isBatchMoving = false;
        this.toastr.error('Encountered an error during batch movement.');
      }
    });
  }

  // =========================================================================
  // REJECT CANDIDATE WITH MANDATORY REMARKS & REASON (Step 9 & 15)
  // =========================================================================

  openRejectModal(candidate: any): void {
    this.selectedCandidate = candidate;
    this.rejectForm = {
      appId: candidate.appId,
      candidateName: candidate.candidateName,
      applicationNo: candidate.applicationNo || `APP-${candidate.appId}`,
      currentStage: candidate.stage,
      rejectionReason: 'Skill Mismatch / Assessment Failed',
      remarks: '',
      cooloffPolicy: '90_Days',
      notifyCandidate: true
    };
    this.showRejectModal = true;
  }

  submitRejectCandidate(): void {
    if (!this.rejectForm.remarks || !this.rejectForm.remarks.trim()) {
      this.toastr.warning('Please enter rejection remarks.', 'Remarks Required');
      return;
    }

    const payload = {
      appId: this.rejectForm.appId,
      rejectionReason: this.rejectForm.remarks.trim(),
      remarks: this.rejectForm.remarks.trim(),
      cooloffPolicy: '90_Days',
      notifyCandidate: true,
      rejectedBy: this.currentUserName,
      companyId: this.companyId
    };

    this.atsService.rejectCandidate(payload).subscribe({
      next: () => {
        this.toastr.warning(`Candidate ${this.rejectForm.candidateName} marked as Rejected.`, 'Candidate Rejected');
        this.showRejectModal = false;
        this.loadPipelineRoster();
      },
      error: () => this.toastr.error('Failed to record candidate rejection.')
    });
  }

  closeRejectModal(): void {
    this.showRejectModal = false;
  }
}
