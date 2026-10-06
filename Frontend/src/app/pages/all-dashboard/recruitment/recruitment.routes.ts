


import { Routes } from '@angular/router';
import { AuthGuard } from '../../../authentication/auth.guard';

export const routes: Routes = [
  {
    path: '',
    data: {
      title: 'recruitment'
    },
    children: [


      {
        path: 'recruitmentdashboard',
        loadComponent: () => import('./recruitment-dashboard/recruitment-dashboard.component').then( (m) => m.RecruitmentDashboardComponent),
        title: 'HRMS - Recruitmentdashboard',
        children: [
          {
            path: '',
            loadComponent: () => import('./recruitment-dash/recruitment-dash.component').then( (m) => m.RecruitmentDashComponent),
            title: 'HRMS - recruitmentdash'
          },
            //Recruitment master
           {
            path: 'external-candidates-dashboard',
            loadComponent: () => import('./external-candidates-dashboard/external-candidates-dashboard.component').then((m) => m.ExternalCandidatesDashboardComponent),
            title: 'HRMS - External Candidates Dashboard'
          },
          {
            path: 'external-candidates-list',
            loadComponent: () => import('./external-candidates-list/external-candidates-list.component').then((m) => m.ExternalCandidatesListComponent),
            title: 'HRMS - External Candidates List'
          },
          {
            path: 'external-candidates-list/:jobId',
            loadComponent: () => import('./external-candidates-list/external-candidates-list.component').then((m) => m.ExternalCandidatesListComponent),
            title: 'HRMS - External Candidates List'
          },
          {
            path: 'external-candidate-details/:id',
            loadComponent: () => import('./external-candidate-details/external-candidate-details.component').then((m) => m.ExternalCandidateDetailsComponent),
            title: 'HRMS - External Candidate Details'
          },     
          {
            path: 'jobMaster_list',
              canActivate: [AuthGuard],
            loadComponent: () => import('./Master/job-master-list/job-master-list.component').then( (m) => m.JobMasterListComponent),
            title: 'HRMS - recruitmentdash'
          }, 
          {
            path: 'jobMaster',
             canActivate: [AuthGuard],
              loadComponent: () => import('./Master/job-master/job-master.component').then( (m) => m.JobMasterComponent),
            title: 'HRMS - recruitmentdash'
          }, 
          {
            path: 'jobMaster/:pk_JobId',
             canActivate: [AuthGuard],
            loadComponent: () => import('./Master/job-master/job-master.component').then( (m) => m.JobMasterComponent),
            title: 'HRMS - recruitmentdash'
          }, 

            {
            path: 'specialization-master',
             canActivate: [AuthGuard],
            loadComponent: () => import('./Master/specialization-master/specialization-master.component').then( (m) => m.SpecializationMasterComponent),
            title: 'HRMS - recruitmentdash'
          }, 
          {
            path: 'specialization-master/:pk_specializationId',
             canActivate: [AuthGuard],
            loadComponent: () => import('./Master/specialization-master/specialization-master.component').then( (m) => m.SpecializationMasterComponent),
            title: 'HRMS - recruitmentdash'
          }, 
          {
            path: 'specialization-master_list',
              canActivate: [AuthGuard],
            loadComponent: () => import('./Master/specialization-master-list/specialization-master-list.component').then( (m) => m.SpecializationMasterListComponent),
            title: 'HRMS - recruitmentdash'
          },

            {
            path: 'qualification-master',
             canActivate: [AuthGuard],
            loadComponent: () => import('./Master/qualification-master/qualification-master.component').then( (m) => m.QualificationMasterComponent),
            title: 'HRMS - recruitmentdash'
          },
          {
            path: 'qualification-master/:pk_qualiId',
             canActivate: [AuthGuard],
            loadComponent: () => import('./Master/qualification-master/qualification-master.component').then( (m) => m.QualificationMasterComponent),
            title: 'HRMS - recruitmentdash'
          },
          {
            path: 'qualification-master_list',
              canActivate: [AuthGuard],
            loadComponent: () => import('./Master/qualification-master-list/qualification-master-list.component').then( (m) => m.QualificationMasterListComponent),
            title: 'HRMS - recruitmentdash'
          },

           {
            path: 'recruitmentMode-master',
             canActivate: [AuthGuard],
            loadComponent: () => import('./recruitment-mode-master/recruitment-mode-master.component').then( (m) => m.RecruitmentModeMasterComponent),
            title: 'HRMS - recruitmentdash'
          }, 


          {
            path: 'recruitmentMode-master/:pk_recmodeid',
             canActivate: [AuthGuard],
            loadComponent: () => import('./recruitment-mode-master/recruitment-mode-master.component').then( (m) => m.RecruitmentModeMasterComponent),
            title: 'HRMS - recruitmentdash'
          }, 
          {
            path: 'recruitmentMode-master_list',
              canActivate: [AuthGuard],
            loadComponent: () => import('./recruitment-mode-master-list/recruitment-mode-master-list.component').then( (m) => m.RecruitmentModeMasterListComponent),
            title: 'HRMS - recruitmentdash'
          }, 
            {
            path: 'candidateMaster',
             canActivate: [AuthGuard],
            loadComponent: () => import('./Master/candidate-master/candidate-master.component').then( (m) => m.CandidateMasterComponent),
            title: 'HRMS - recruitmentdash'
          },
          
           {
            path: 'candidateMaster/:pk_recId',
             canActivate: [AuthGuard],
            loadComponent: () => import('./Master/candidate-master/candidate-master.component').then( (m) => m.CandidateMasterComponent),
            title: 'HRMS - recruitmentdash'
          }, 
          {
            path: 'candidateMaster_list',
              canActivate: [AuthGuard],
            loadComponent: () => import('./Master/candidate-master-list/candidate-master-list.component').then( (m) => m.CandidateMasterListComponent),
            title: 'HRMS - recruitmentdash'
          }, 

           {
            
            path: 'newsPaper-master_list',
              canActivate: [AuthGuard],
            loadComponent: () => import('./Master/news-paper-master-list/news-paper-master-list.component').then( (m) => m.NewsPaperMasterListComponent),
            title: 'HRMS - recruitmentdash'
          }, 
          {
            path: 'newsPaper-master/:id',
             canActivate: [AuthGuard],
            loadComponent: () => import('./Master/news-paper-master/news-paper-master.component').then( (m) => m.NewsPaperMasterComponent),
            title: 'HRMS - recruitmentdash'
          },
          {
            path: 'newsPaper-master',
             canActivate: [AuthGuard],
            loadComponent: () => import('./Master/news-paper-master/news-paper-master.component').then( (m) => m.NewsPaperMasterComponent),
            title: 'HRMS - recruitmentdash'
          },
          

          
          {
            path: 'ProjectMaster',
            canActivate: [AuthGuard],
            loadComponent: () => import('./Master/project-master/project-master.component').then( (m) => m.ProjectMasterComponent),
            title: 'HRMS - recruitmentdash'
          },
          {
            path: 'ProjectMaster/:pk_ProjectId',
            canActivate: [AuthGuard],
            loadComponent: () => import('./Master/project-master/project-master.component').then( (m) => m.ProjectMasterComponent),
            title: 'HRMS - recruitmentdash'
          },
          {
            path: 'ProjectMaster_list',
              canActivate: [AuthGuard],
            loadComponent: () => import('./Master/project-master-list/project-master-list.component').then( (m) => m.ProjectMasterListComponent),
            title: 'HRMS - recruitmentdash'
          },

           {
            path: 'externalMember',
             canActivate: [AuthGuard],
            loadComponent: () => import('./external-member/external-member.component').then( (m) => m.ExternalMemberComponent),
            title: 'HRMS - recruitmentdash'
          }, 


          {
            path: 'externalMember/:pk_exMemberId',
             canActivate: [AuthGuard],
            loadComponent: () => import('./external-member/external-member.component').then( (m) => m.ExternalMemberComponent),
            title: 'HRMS - recruitmentdash'
          }, 
          {
            path: 'externalMember_list',
              canActivate: [AuthGuard],
            loadComponent: () => import('./external-member-list/external-member-list.component').then( (m) => m.ExternalMemberListComponent),
            title: 'HRMS - recruitmentdash'
          }, 
          


          //Transation

      
          {
            path: 'Candidate-Salary',
             canActivate: [AuthGuard],
            loadComponent: () => import('./candidate-salary/candidate-salary.component').then( (m) => m.CandidateSalaryComponent),
            title: 'HRMS - recruitmentdash'
          }, 
          {
            path: 'Candidate-Salary/:pk_recId',
             canActivate: [AuthGuard],
            loadComponent: () => import('./candidate-salary/candidate-salary.component').then( (m) => m.CandidateSalaryComponent),
            title: 'HRMS - recruitmentdash'
          }, 

          {
            path: 'Candidate-Salary_list',
              canActivate: [AuthGuard],
            loadComponent: () => import('./candidate-salary-list/candidate-salary-list.component').then( (m) => m.CandidateSalaryListComponent),
            title: 'HRMS - recruitmentdash'
          }, 
           {
            path: 'SelectedCandidate',
            canActivate: [AuthGuard],
            loadComponent: () => import('./Master/selected-candidate/selected-candidate.component').then( (m) => m.SelectedCandidateComponent),
            title: 'HRMS - recruitmentdash'
          },
          
         
           {
            path: 'FreezeCandidate',
              canActivate: [AuthGuard],
            loadComponent: () => import('./Master/freeze-candidate/freeze-candidate.component').then( (m) => m.FreezeCandidateComponent),
            title: 'HRMS - recruitmentdash'
          },

           {
            path: 'ConductInterview',
              canActivate: [AuthGuard],
            loadComponent: () => import('./conduct-interview/conduct-interview.component').then( (m) => m.ConductInterviewComponent),
            title: 'HRMS - recruitmentdash'
          },
          {
            path: 'ConductInterview/:fk_recId',
              canActivate: [AuthGuard],
            loadComponent: () => import('./conduct-interview/conduct-interview.component').then( (m) => m.ConductInterviewComponent),
            title: 'HRMS - recruitmentdash'
          },
          {
            path: 'ConductInterview_list',
              canActivate: [AuthGuard],
            loadComponent: () => import('./conduct-interview-list/conduct-interview-list.component').then( (m) => m.ConductInterviewListComponent),
            title: 'HRMS - recruitmentdash'
          },
            {
            path: 'ScheduleInterview',
              canActivate: [AuthGuard],
            loadComponent: () => import('./Master/schedule-interview/schedule-interview.component').then( (m) => m.ScheduleInterviewComponent),
            title: 'HRMS - recruitmentdash'
          },
           {
            path: 'ScreeningApp',
             canActivate: [AuthGuard],
            loadComponent: () => import('./ScreeningApp/screening-application/screening-application.component').then( (m) => m.ScreeningApplicationComponent),
            title: 'HRMS - recruitmentdash'
          },


           {
            path: 'CandidateMedicalDetails',
             canActivate: [AuthGuard],
            loadComponent: () => import('./Transaction/Candidate Reference And Medical/candidate-medical-details/candidate-medical-details.component').then( (m) => m.CandidateMedicalDetailsComponent),
            title: 'HRMS - recruitmentdash'
          },
          {
            path: 'CandidateMedicalDetails/:pk_mtrnid',
             canActivate: [AuthGuard],
            loadComponent: () => import('./Transaction/Candidate Reference And Medical/candidate-medical-details/candidate-medical-details.component').then( (m) => m.CandidateMedicalDetailsComponent),
            title: 'HRMS - recruitmentdash'
          },


          {
            path: 'CandidateMedicalDetails_list',
              canActivate: [AuthGuard],
            loadComponent: () => import('./Transaction/Candidate Reference And Medical/candidate-medical-details-list/candidate-medical-details-list.component').then( (m) => m.CandidateMedicalDetailsListComponent),
            title: 'HRMS - recruitmentdash'
          },



           {
            path: 'CandidateRefrenceDetails',
             canActivate: [AuthGuard],
            loadComponent: () => import('./Transaction/Candidate Reference And Medical/candidate-ref-details/candidate-ref-details.component').then( (m) => m.CandidateRefDetailsComponent),
            title: 'HRMS - recruitmentdash'
          },
          {
            path: 'CandidateRefrenceDetails/:pk_rtrnid',
             canActivate: [AuthGuard],
            loadComponent: () => import('./Transaction/Candidate Reference And Medical/candidate-ref-details/candidate-ref-details.component').then( (m) => m.CandidateRefDetailsComponent),
            title: 'HRMS - recruitmentdash'
          },
          {
            path: 'CandidateRefrenceDetails_list',
              canActivate: [AuthGuard],
            loadComponent: () => import('./Transaction/Candidate Reference And Medical/candidate-ref-details-list/candidate-ref-details-list.component').then( (m) => m.CandidateRefDetailsListComponent),
            title: 'HRMS - recruitmentdash'
          },
         


          //NOt in used route--------------------------------------------------------------------------------------------------
          // {
          //   path: 'ScreeningCommittee',
          //   loadComponent: () => import('./screening-committee/screening-committee.component').then( (m) => m.ScreeningCommitteeComponent),
          //   title: 'HRMS - recruitmentdash'
          // }, 

          
          //  {
          //   path: 'ScreeningCommittee/:Pk_Screening_CommitteeId',
          //   loadComponent: () => import('./screening-committee/screening-committee.component').then( (m) => m.ScreeningCommitteeComponent),
          //   title: 'HRMS - recruitmentdash'
          // }, 

          //  {
          //   path: 'ScreeningCommittee-list',
          //     canActivate: [AuthGuard],
          //   loadComponent: () => import('./screening-committee-list/screening-committee-list.component').then( (m) => m.ScreeningCommitteeListComponent),
          //   title: 'HRMS - recruitmentdash'
          // },

          //not in used route end--------------------------------------------------------------------------------------------------------------------

      // {
          //   path: 'interviewPanel',
          //   loadComponent: () => import('./Master/interview-panel/interview-panel.component').then( (m) => m.InterviewPanelComponent),
          //   title: 'HRMS - recruitmentdash'
          // }, 
          // {
          //   path: 'interviewPanel-list',
          //   loadComponent: () => import('./Master/interview-panel-list/interview-panel-list.component').then( (m) => m.InterviewPanelListComponent),
          //   title: 'HRMS - recruitmentdash'
          // },
           //  {
          //   path: 'Rolewise-KRA-list',
          //   loadComponent: () => import('./rolewise-list/rolewise-list.component').then( (m) => m.RolewiseListComponent ),
          //   title: 'HRMS - emp-kpr'
          //  },

          //  {
          //   path: 'Rolewise-KRA',
          //   loadComponent: () => import('./rolewise-kra/rolewise-kra.component').then( (m) => m.RolewiseKraComponent ),
          //   title: 'HRMS - emp-kpr'
          //  },

          // {
          //   path: 'Rolewise-KRA/:roleid/:srno',
          //   loadComponent: () => import('./rolewise-kra/rolewise-kra.component').then( (m) => m.RolewiseKraComponent ),
          //   title: 'HRMS - emp-kpa'
          //  },

          //  {
          //   path: 'Empwise-KRA',
          //   loadComponent: () => import('./emp-kra/emp-kra.component').then( (m) => m.EmpKraComponent ),
          //   title: 'HRMS - emp-kra'
          //  },
          //  {
          //   path: 'Empwise-KRA/:fk_empid/:srno',
          //   loadComponent: () => import('./emp-kra/emp-kra.component').then( (m) => m.EmpKraComponent ),
          //   title: 'HRMS - emp-kra'
          //  },
          //  {
          //   path: 'Empwise-KRA-List',
          //   loadComponent: () => import('./emp-kra-list/emp-kra-list.component').then( (m) => m.EmpKraListComponent ),
          //   title: 'HRMS - emp-kra'
          //  },


          //  {
          //   path: 'Empwise-KRA-Assessment',
          //   loadComponent: () => import('./emp-assessment/emp-assessment.component').then( (m) => m.EmpAssessmentComponent ),
          //   title: 'HRMS - emp-kra'
          //  },
          //  {
          //   path: 'ScheduleInterview',
          //     canActivate: [AuthGuard],
          //   loadComponent: () => import('./Master/schedule-interview/schedule-interview.component').then( (m) => m.ScheduleInterviewComponent),
          //   title: 'HRMS - recruitmentdash'
          // },



          //from appraisal module Master

	         { path: 'Rolewise-KRA-Import',
              canActivate: [AuthGuard],
            loadComponent: () => import('./rolewise-kra-import/rolewise-kra-import.component').then( (m) => m.RolewiseKraImportComponent ),
            title: 'HRMS - emp-kpr'
           },
  
        
        {
            path: 'Empwise-KRA-Import',
              canActivate: [AuthGuard],
            loadComponent: () => import('./emp-kra-import/emp-kra-import.component').then( (m) => m.EmpKraImportComponent ),
            title: 'HRMS - emp-kra'
           },
        
        ]
      }
    
    ]
  }
];
