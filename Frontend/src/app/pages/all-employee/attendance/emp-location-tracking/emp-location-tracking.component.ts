import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ToastrService } from 'ngx-toastr';
import { NgxUiLoaderService } from 'ngx-ui-loader';
import { EmpLocationTrackingService, LocationRecord } from './emp-location-tracking.service';

@Component({
  selector: 'app-emp-location-tracking',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './emp-location-tracking.component.html',
  styleUrls: ['./emp-location-tracking.component.scss']
})
export class EmpLocationTrackingComponent implements OnInit {
  userId: string = '';
  userName: string = 'Employee';
  companyName: string = '';

  isTrackingEnabled: boolean = true;
  isLoading: boolean = false;
  isToggling: boolean = false;
  lastUpdated: string | null = null;

  liveLocation: LocationRecord | null = null;
  hasLocationData: boolean = false;

  constructor(
    private trackingService: EmpLocationTrackingService,
    private toastr: ToastrService,
    private loader: NgxUiLoaderService
  ) {}

  ngOnInit(): void {
    // 1. Resolve logged-in Employee ID and Username from sessionStorage / localStorage
    this.userId =
      sessionStorage.getItem('UserId') ||
      sessionStorage.getItem('userId') ||
      localStorage.getItem('UserId') ||
      localStorage.getItem('userId') ||
      sessionStorage.getItem('username') ||
      '';

    this.userName =
      sessionStorage.getItem('username') ||
      sessionStorage.getItem('UserName') ||
      'Employee';

    this.companyName =
      sessionStorage.getItem('companyName') ||
      'Enterprise HRMS';

    if (!this.userId) {
      this.toastr.warning('Could not detect logged-in Employee ID. Please re-login.', 'Session Notice');
      return;
    }

    this.fetchTrackingStatus();
    this.fetchLiveLocation();
  }

  fetchTrackingStatus(): void {
    if (!this.userId) return;
    this.isLoading = true;

    this.trackingService.getUserTrackingStatus(this.userId).subscribe({
      next: (res: any) => {
        this.isLoading = false;
        if (res?.isSuccess && res?.data) {
          this.isTrackingEnabled = res.data.isTrackingEnabled ?? true;
          this.lastUpdated = res.data.updatedAt || null;
        } else {
          // Default to ON if not set
          this.isTrackingEnabled = true;
        }
      },
      error: (err: any) => {
        this.isLoading = false;
        console.error('Error fetching user tracking status:', err);
      }
    });
  }

  fetchLiveLocation(): void {
    if (!this.userId) return;

    this.trackingService.getLiveLocation(this.userId).subscribe({
      next: (res: any) => {
        if (res?.isSuccess && res?.data) {
          this.liveLocation = res.data;
          this.hasLocationData = true;
        } else {
          this.liveLocation = null;
          this.hasLocationData = false;
        }
      },
      error: (err: any) => {
        console.error('Error fetching live location:', err);
      }
    });
  }

  toggleTracking(newState: boolean): void {
    if (!this.userId) {
      this.toastr.error('User ID not found.');
      return;
    }

    this.isToggling = true;
    this.loader.start();

    this.trackingService.toggleUserTrackingStatus(this.userId, newState).subscribe({
      next: (res: any) => {
        this.loader.stop();
        this.isToggling = false;

        if (res?.isSuccess) {
          this.isTrackingEnabled = newState;
          this.lastUpdated = new Date().toISOString();

          if (newState) {
            this.toastr.success('Location tracking ENABLED. Background sync is active.', 'Tracking On');
          } else {
            this.toastr.info('Location tracking DISABLED. Mobile app background service will halt.', 'Tracking Paused');
          }
        } else {
          this.toastr.error(res?.message || 'Failed to update tracking status.');
          // Revert UI toggle on error
          this.isTrackingEnabled = !newState;
        }
      },
      error: (err: any) => {
        this.loader.stop();
        this.isToggling = false;
        this.toastr.error('Error contacting server to update tracking status.');
        this.isTrackingEnabled = !newState;
      }
    });
  }

  onSwitchChange(event: Event): void {
    const input = event.target as HTMLInputElement;
    this.toggleTracking(input.checked);
  }

  refresh(): void {
    this.fetchTrackingStatus();
    this.fetchLiveLocation();
    this.toastr.info('Status refreshed.', 'Refreshed');
  }

  formatDate(dateStr: string | null | undefined): string {
    if (!dateStr) return 'Not available';
    try {
      return new Date(dateStr).toLocaleString('en-IN', {
        dateStyle: 'medium',
        timeStyle: 'medium'
      });
    } catch {
      return dateStr;
    }
  }
}
