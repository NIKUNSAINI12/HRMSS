
import { Routes } from '@angular/router';

export const routes: Routes = [
  {
    path: '',
    data: {
      title: 'on_boarding',
    },
    children: [
      {
        path: 'on_boardingdashboard',
        loadComponent: () =>import('./on-boarding-dashboard/on-boarding-dashboard.component').then((m) => m.OnBoardingDashboardComponent),
        title: 'HRMS -OnBoarding Dashboard',
        children: [
          {
            path: '',
            loadComponent: () =>import('./on-boarding-dash/on-boarding-dash.component').then((m) => m.OnBoardingDashComponent),
            title: 'HRMS - OnBoarding  dash',
          },
            {
            path: 'OnboardCandidateView/:id',
            loadComponent: () =>import('./onboard-candidate-view/onboard-candidate-view.component').then((m) => m.OnboardCandidateViewComponent),
            title: 'HRMS - OnBoarding  Candidate View',
          },
      
           {
            path: 'OnboardCandidatelist',
            loadComponent: () =>import('./onboard-candidatelist/onboard-candidatelist.component').then((m) => m.OnboardCandidatelistComponent),
            title: 'HRMS - OnBoarding  Candidate List',
          },

              {
            path: 'onboardCandidateMasterList',
            loadComponent: () =>import('./ob-candidate-master-list/ob-candidate-master-list.component').then((m) => m.ObCandidateMasterListComponent),
            title: 'HRMS - OnBoarding Candidate Master List',
          },

             {
            path: 'onboardCandidateMaster',
            loadComponent: () =>import('./ob-candidate-master/ob-candidate-master.component').then((m) => m.ObCandidateMasterComponent),
            title: 'HRMS - OnBoarding Candidate Master View',
          },
      
      
              {
            path: 'onboardCandidateMaster/:pk_recId',
            loadComponent: () =>import('./ob-candidate-master/ob-candidate-master.component').then((m) => m.ObCandidateMasterComponent),
            title: 'HRMS - OnBoarding Candidate Master View',
          },
      
      




        ],
      },
    ],
  },
];
