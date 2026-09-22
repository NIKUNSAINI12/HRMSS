import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ActivatedRoute, Router } from '@angular/router';
import { CompanyConfigService } from '../../services/company-config.service';

@Component({
  selector: 'app-access-denied',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './access-denied.component.html',
  styleUrl: './access-denied.component.scss'
})
export class AccessDeniedComponent implements OnInit {
  reason: string = 'invalid-key';

  constructor(
    private route: ActivatedRoute,
    private router: Router,
    private configService: CompanyConfigService
  ) {}

  ngOnInit(): void {
    // Get reason from query params
    this.route.queryParams.subscribe(params => {
      this.reason = params['reason'] || 'invalid-key';
    });
  }

  goToAvailableForms(): void {
    const config = this.configService.getConfig();
    
    if (!config) {
      this.router.navigate(['/on_boarding']);
      return;
    }

    // Find first visible form
    const forms = [
      { visible: config.panVisible, route: '/on_boarding/pan' },
      { visible: config.aadhaarVisible, route: '/on_boarding/aadhaar' },
      { visible: config.basicInfoVisible, route: '/on_boarding/basicInfo' },
      { visible: config.qualificationVisible, route: '/on_boarding/education' },
      { visible: config.experienceVisible, route: '/on_boarding/previous_experience' },
      { visible: config.familyVisible, route: '/on_boarding/family_details' }
    ];

    const firstVisible = forms.find(f => f.visible);
    
    if (firstVisible) {
      this.router.navigate([firstVisible.route], {
        queryParamsHandling: 'preserve' // Keep candidate key
      });
    } else {
      this.router.navigate(['/on_boarding/final-submission'], {
        queryParamsHandling: 'preserve'
      });
    }
  }
}
// import { Component } from '@angular/core';

// @Component({
//   selector: 'app-access-denied',
//   standalone: true,
//   imports: [],
//   templateUrl: './access-denied.component.html',
//   styleUrl: './access-denied.component.scss'
// })
// export class AccessDeniedComponent {

// }
