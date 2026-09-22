import { Component, OnInit } from '@angular/core';
import { FormBuilder, FormGroup, FormsModule, ReactiveFormsModule, Validators } from '@angular/forms';
import { AuthService } from '../service/auth.service';
import { CommonModule } from '@angular/common';
import { Router, RouterLink } from '@angular/router';
import { ToastrService } from 'ngx-toastr';
import { NgxUiLoaderService } from 'ngx-ui-loader';
import { NgSelectComponent } from '@ng-select/ng-select';

import { Capacitor } from '@capacitor/core';
import { Preferences } from '@capacitor/preferences';
import { DropdownService } from '../../shared/services/dropdown.service';
import { TokenManagerService } from '../../shared/services/token-manager.service';
import { MenuService } from '../../shared/services/menu.service';

@Component({
  selector: 'app-login',
  templateUrl: './login.component.html',
  styleUrls: ['./login.component.scss'],
  imports: [ReactiveFormsModule, FormsModule, CommonModule, RouterLink, NgSelectComponent, RouterLink],
  standalone: true
})
export class LoginComponent implements OnInit {
  submitted = false;
  showPassword: boolean = false;
  showError: boolean = false;

  public loginForm!: FormGroup;
  public EmploginForm!: FormGroup;
  companyId: string = '';

  companyname: string = '';
  officeTypes: Array<{ name: string; value: string | null }> = [];
  locations: Array<{ name: string; value: string | null }> = [];
  isCompanyCodeValid: boolean = false;
  isLoggingIn: boolean = false;

  constructor(
    private fb: FormBuilder,
    private authService: AuthService,
    private toastr: ToastrService,
    private router: Router,
    private ngxUILoaderService: NgxUiLoaderService,
    private dropdownService: DropdownService,
    private tokenManagerService: TokenManagerService,
    private menuService: MenuService,
    private toastrService: ToastrService,
  ) { }

  ngOnInit(): void {


    this.EmploginForm = this.fb.group({
      companyCode: ['', Validators.required],
      // password: [{ value: '', disabled: true }, Validators.required],
      username: ['', Validators.required],
      password: ['', Validators.required],

    });
  }

  //verify the company code
  validateCompanyCode(): void {
    const companyCode = this.EmploginForm.get('companyCode')?.value;

    if (companyCode) {
      this.authService.validateCompanyCode(companyCode).subscribe(
        response => {
          if (response.isSuccess) {
            const data = response.data;
            this.companyId = data.companyId;
              this.companyname = data.companyname;

            this.isCompanyCodeValid = true;
            //  this.EmploginForm.get('username')?.enable();     
            this.toastr.success('Company code verified!');
          } else {
            this.companyname='';
            this.isCompanyCodeValid = false;
            this.toastr.error(response.message || 'Invalid company code!', 'Error');
          }
        },
        error => {
          console.error('Validation failed:', error);
          this.isCompanyCodeValid = false;
          this.toastr.error(error.message || 'Something went wrong', 'Error');
        }
      );
    }
    else {
      this.showError = true;


    }
  }

  togglePasswordVisibility(): void {
    this.showPassword = !this.showPassword;
  }
  onSubmit(): void {
    this.submitted = true;

    if (this.isLoggingIn) return;

    if (!this.EmploginForm.valid) {
      // this.toastr.error('Please fill in all required fields');
      return;
    }

    if (!this.isCompanyCodeValid) {
      this.toastr.error('Please verify company code first');
      return;
    }

    this.isLoggingIn = true;

    const { username, password, companyCode } = this.EmploginForm.value;

    const payload = {
      loginId: username,
      password,
      companyCode
    };

    this.authService.login(payload).subscribe({
      next: (response) => {
        this.isLoggingIn = false;

        if (!response.isSuccess) {
          // this.toastr.error(response.message || 'Login failed');
          this.toastr.error(response.message);
          return;
        }

        //  CLEAR & STORE ONLY WHAT OTP NEEDS
        sessionStorage.clear();

        sessionStorage.setItem('loginId', response.documentId);
        sessionStorage.setItem('OTP', response.documentNo);
        sessionStorage.setItem('companyCode', companyCode);
        //  STORE LOGIN DECISION DATA
        sessionStorage.setItem('usertype', response.loginType);
        sessionStorage.setItem('contractor_LabelName', response.contractor_LabelName || 'Contractor Name');
        sessionStorage.setItem('isotprequired', response.isotprequired);
        
   sessionStorage.setItem('showclientdetails', response.showclientdetails);
  sessionStorage.setItem('vendor_Applicable', response.vendor_Applicable);

        //  sessionStorage.setItem('isotprequired', response.isotprequired);
        // sessionStorage.setItem(
        //   'showAdminSwitch',
        //   response.showAdminSwitch ? 'true' : 'false'
        // );

        sessionStorage.setItem(
          'showAdminSwitch',
          response.showAdminSwitch === true ? 'true' : 'false'
        );
        //  IMMEDIATE GET
        const usertype = sessionStorage.getItem('usertype');
        if (usertype === 'User') {
          sessionStorage.setItem('usertype', 'User');
          localStorage.setItem('usertype', 'User');
          sessionStorage.setItem('loginId', response.documentId);
          sessionStorage.setItem('fk_CompanyCode', payload.companyCode);
          //sessionStorage.setItem('locationID', payload.locationId);
          sessionStorage.setItem('fk_UserID', response.documentId);
          sessionStorage.setItem('UserId', response.documentId);
          sessionStorage.setItem('financialDate1', '01 Apr 2025');
          sessionStorage.setItem('financialDate2', '31 Mar 2026');
          sessionStorage.setItem('OTP', response.documentNo);
        }
        else {

          sessionStorage.setItem('usertype', 'Employee');
          localStorage.setItem('usertype', 'Employee'); //  SIRF YE ADD KARO
          sessionStorage.setItem('username', payload.loginId);
          //  Avoid storing password in production
          sessionStorage.setItem('password', payload.password);
          sessionStorage.setItem('loginId', response.documentId);
          sessionStorage.setItem('UserId', response.documentId);
          sessionStorage.setItem('OTP', response.documentNo);

        }

        // this.toastr.success(response.message);

        //added by PP
        if (response.isotprequired) {
          this.router.navigate(['auth/otp']);
        } else {
          //2 api call
          //redirect
          this.validate(response.documentNo, response.documentId, response.loginType);
        }



      },
      error: () => {
        this.isLoggingIn = false;
        this.toastr.error('Login error occurred');
      }
    });
  }


  //added starts
  validate(otp: any, userId: any, usertype: string) {



    const loginotpData = {
      userId: userId,
      otp: otp,
      usertype: usertype
    };

    const otpService =
      usertype == 'User'
        ? this.authService.verify_otp_login(loginotpData)
        : this.authService.verifyEmployeeOtp(loginotpData);

    otpService.subscribe({
      next: async (response) => {
        // this.isVerifying = false;
        if (response.isSuccess) {
          sessionStorage.removeItem('loginId');




          const accessToken = response.data.accessToken;
          const refreshToken = response.data.refreshToken;
          const username = response.data.userName || '';
          const userId = response.data.userId || '';
          const documentNo = response.documentNo || '';
          const contractorApplicable = response.data.contractorApplicable;
          sessionStorage.setItem('accessToken', accessToken);
          sessionStorage.setItem('refreshToken', refreshToken);
          sessionStorage.setItem('username', username);
          sessionStorage.setItem('userId', userId);
          sessionStorage.setItem('Otp', documentNo);

          const companyName = response.data.companyName || response.data.CompanyName || response.data.compname || '';
          sessionStorage.setItem('companyName', companyName);
          sessionStorage.setItem('financialDate1', response.data.financialDate1 || response.data.finStartDate || response.data.date1 || '01 Apr 2025');
          sessionStorage.setItem('financialDate2', response.data.financialDate2 || response.data.finEndDate || response.data.date2 || '31 Mar 2026');

          // Generate Financial Year string (e.g., FY 2025-26)
          const f1 = sessionStorage.getItem('financialDate1');
          const f2 = sessionStorage.getItem('financialDate2');
          if (f1 && f2) {
            const date1 = new Date(f1);
            const date2 = new Date(f2);
            if (!isNaN(date1.getTime()) && !isNaN(date2.getTime())) {
              const year1 = date1.getFullYear();
              const year2 = date2.getFullYear() % 100;
              sessionStorage.setItem('financialYear', `FY ${year1}-${year2}`);
            } else {
              sessionStorage.setItem('financialYear', 'FY 2025-26');
            }
          }

          sessionStorage.setItem('ContractApplicable', contractorApplicable);
          sessionStorage.setItem('contractor_LabelName', response.data.contractor_LabelName || 'Contractor Name');
          const usertype = sessionStorage.getItem('usertype');
          if (Capacitor.isNativePlatform()) {
            await Preferences.set({ key: 'accessToken', value: accessToken });
            await Preferences.set({ key: 'refreshToken', value: refreshToken });
            await Preferences.set({ key: 'username', value: username });
            await Preferences.set({ key: 'UserId', value: userId });
            await Preferences.set({ key: 'Otp', value: documentNo });

            // Optional — store flags if needed for restoring sessions
            await Preferences.set({ key: 'usertype', value: usertype || '' });
          }

          this.dropdownService.clearCache();

          if (usertype == 'User') {
            sessionStorage.removeItem('OTP');
            this.dropdownService.clearCache();
            this.getMenu();
            this.router.navigate(['/dash']);


          } else {
            sessionStorage.removeItem('OTP');
            this.dropdownService.clearCache();

            this.router.navigate(['/dash/employee-dashboard']); // Employee route
          }

          this.tokenManagerService.startTokenRefreshScheduler();
          this.toastrService.success(response.message);
        } else {

          this.toastrService.error(response.message);
          this.router.navigate(['/auth/otp']);
          this.dropdownService.clearCache();
        }
      },
      error: (error) => {

        this.toastrService.error(error.message || 'Verification failed');
      },
    });
  }

  getMenu() {

    this.menuService.getallMenubasedonUser().subscribe({
      next: (menuResponse) => {

        this.menuService.setMenu(menuResponse.data); //  Set menu here
      },
      error: (err) => {
        console.error('Error loading menu', err);
      }
    });
  }

  //added ends




}



