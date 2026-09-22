import { Component, inject, OnInit } from '@angular/core';
import { Router } from '@angular/router';

@Component({
  selector: 'app-redirect',
  standalone: true,
  template: '',
})
export class RedirectComponent implements OnInit {
  router = inject(Router);

  ngOnInit(): void {
    const isAdmin = !!sessionStorage.getItem('fk_CompanyCode');

    if (isAdmin) {
      this.router.navigate(['/dash/dashboard']);
    } else {
      this.router.navigate(['/dash/employee-dashboard']);
    }
  }
}
