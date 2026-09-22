import { CommonModule } from '@angular/common';
import { Component } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';

@Component({
    selector: 'app-recruitment-dash',
     standalone: true,
    imports: [CommonModule, FormsModule, RouterLink],
    templateUrl: './recruitment-dash.component.html',
    styleUrls: ['./recruitment-dash.component.scss']
})
export class RecruitmentDashComponent {
  searchText: string = '';
  showAll: boolean = false;


  candidatePipelineList = [
    {
      id: 1,
      name: 'Aarohi Sharma',
      position: 'Frontend Developer',
      interviewDate: '2025-05-10',
      plateform: 'Naukri.com',
      managerStatus: 'Pending',
      todoAction: 'Schedule Technical Round'
    },
    {
      id: 2,
      name: 'Isha Verma',
      position: 'Backend Developer',
      interviewDate: '2025-05-08',
      plateform: 'LinkedIn',
      managerStatus: 'Approved',
      todoAction: 'Send HR Feedback'
    },
    {
      id: 3,
      name: 'Sneha Nair',
      position: 'UI/UX Designer',
      interviewDate: '2025-05-12',
      plateform: 'Indeed',
      managerStatus: 'Rejected',
      todoAction: 'Archive Resume'
    },
    {
      id: 4,
      name: 'Priya Reddy',
      position: 'QA Engineer',
      interviewDate: '2025-05-15',
      plateform: 'Shine.com',
      managerStatus: 'Pending',
      todoAction: 'Schedule Final Round'
    },
    {
      id: 5,
      name: 'Kritika Das',
      position: 'Data Analyst',
      interviewDate: '2025-05-11',
      plateform: 'MonsterIndia.com',
      managerStatus: 'Approved',
      todoAction: 'Prepare Offer Letter'
    },
    {
      id: 6,
      name: 'Ritika Mehta',
      position: 'HR Executive',
      interviewDate: '2025-05-13',
      plateform: 'TimesJobs',
      managerStatus: 'Rejected',
      todoAction: 'Send Rejection Email'
    },
    {
      id: 7,
      name: 'Ananya Joshi',
      position: 'Product Manager',
      interviewDate: '2025-05-14',
      plateform: 'Internshala',
      managerStatus: 'Approved',
      todoAction: 'Initiate Onboarding'
    }
  ];
  
 

    get filteredCandidates() {
      const search = this.searchText.toLowerCase();
      let filtered = this.candidatePipelineList.filter(c =>
        c.name.toLowerCase().includes(search) ||
        c.position.toLowerCase().includes(search) ||
        c.interviewDate.toLowerCase().includes(search) ||
        c.managerStatus.toLowerCase().includes(search) ||
        c.todoAction.toLowerCase().includes(search) ||
        c.plateform.toLowerCase().includes(search)
      );

      return this.showAll ? filtered : filtered.slice(0, 3); // show only 3 by default
  
  }
  

  getBadgeClass(status: string): string {
    switch (status) {
      case 'Approved':
        return 'badge bg-success';
      case 'Pending':
        return 'badge bg-warning';
      case 'Rejected':
        return 'badge bg-danger';
      default:
        return 'badge bg-secondary';
    }
  }



  toggleViewAll() {
    this.showAll = !this.showAll;
  }

  
}
