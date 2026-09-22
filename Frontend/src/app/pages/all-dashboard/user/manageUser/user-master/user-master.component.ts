import { CommonModule } from '@angular/common';
import { Component, inject } from '@angular/core';
import {
  FormBuilder,
  FormGroup,
  ReactiveFormsModule,
  Validators,
} from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { NgSelectModule } from '@ng-select/ng-select';
import { ToastrService } from 'ngx-toastr';
import { EncryptionService } from '../../../../../shared/services/encryption.service';
import { UserMasterService } from '../../services/user-master.service';

@Component({
  selector: 'app-user-master',
  standalone: true,
  imports: [ReactiveFormsModule, CommonModule, RouterLink, NgSelectModule],
  templateUrl: './user-master.component.html',
  styleUrl: './user-master.component.scss',
})
export class UserMasterComponent {
  UserMasterForm!: FormGroup;
  pk_userId: string = '';
  isEditMode: boolean = false;
  EmployeeList: { name: string; value: string }[] = [];
  RoleList: { name: string; value: string }[] = [];
  submitted = false;
  showError = false;
  router = inject(Router);
  route = inject(ActivatedRoute);
  oldPassword: string = '';

  constructor(
    private fb: FormBuilder,
    private userMasterService: UserMasterService,
    private toastrService: ToastrService,
    private encryptService: EncryptionService
  ) {}

  ngOnInit(): void {
    this.initializeForm();

    // Check if ID is provided in the route
    this.route.paramMap.subscribe((params) => {
      const id = params.get('pk_userId');
      if (id) {
        this.pk_userId = this.encryptService.decryptText(id.toString());
        this.isEditMode = true;
        this.getUserById(this.pk_userId);
      }
    });
    this.getEmployees('Employee');
    this.getRole('Role');
  }

  initializeForm(): void {
    this.UserMasterForm = this.fb.group({
      loginname: ['', Validators.required],
      password: ['', this.isEditMode ? [] : [Validators.required]], // Password not required in edit mode
      fk_empId: [null],
      fathername: [''],
      department: [''],
      designation: [''],
      email: ['', [Validators.email]],
      fk_roleId: [null],
      remarks: [''],
      name: ['', Validators.required],
      active: [true]
    });
  }



    //Check Duplicate value

    checkDesignationAvailability(loginname: string): void {
      const fieldName = 'LoginId'; 
      const fieldValue = loginname; 
      // const generalId = this.ShiftId; 
      const generalId = this.pk_userId ;
  
    
      this.userMasterService.CheckDuplicateValue(fieldName, fieldValue, generalId).subscribe({
        next: (response) => {
          if (response && response.isSuccess === false) {
            this.UserMasterForm.get('loginname')?.setErrors({ duplicate: response.message });
          } else {
            this.UserMasterForm.get('loginname')?.setErrors(null);
          }
        },
        error: (err) => {
          console.error('Duplicate Check API Error:', err);
          this.UserMasterForm.get('loginname')?.setErrors({ duplicate: 'Error checking designation availability.' });
        }
      });
    }
  getEmployees(feildName: string): void {
    this.userMasterService.getEmployee(feildName).subscribe({
      next: (res) => {
        if (res.isSuccess) {
          res.data = res.data.slice(1);
          this.EmployeeList = res.data.map((emp: any) => ({
            name: emp.name,
            value: emp.value,
          }));
        } else {
          this.EmployeeList = [];
          this.toastrService.error(res.message, 'Error');
        }
      },
      error: (error) => {
        this.EmployeeList = [];
        this.toastrService.error('Failed to retrieve employees', 'Error');
      },
    });
  }

  getRole(feildName: string): void {
    this.userMasterService.getEmployee(feildName).subscribe({
      next: (res) => {
        if (res.isSuccess) {
          // this.employeeList = res.data;
          res.data = res.data.slice(1);
          this.RoleList = res.data.map((emp: any) => ({
            name: emp.name,
            value: emp.value,
          }));
        } else {
          this.EmployeeList = [];
          this.toastrService.error(res.message, 'Error');
        }
      },
      error: (error) => {
        this.EmployeeList = [];
        this.toastrService.error('Failed to retrieve employees', 'Error');
      },
    });
  }

  getUserById(pk_userId: string) {
    this.userMasterService.get_UserById(pk_userId).subscribe(
      (response) => {
        if (response.isSuccess && response.data) {
          this.UserMasterForm.patchValue({
            loginname: response.data.loginname,
            password: response.data.password,
            fk_empId: response.data.fk_empId,
            fathername: response.data.fathername,
            department: response.data.department,
            designation: response.data.designation,
            email: response.data.email,
            fk_roleId:String(response.data.fk_roleId),
            remarks: response.data.remarks,
            name: response.data.name,
            active: response.data.active // Convert boolean to string for select
          });
          this.oldPassword = response.data.password; // Store the old password for comparison
        } else {
          this.toastrService.error(
            response.message || 'Failed to fetch user data'
          );
        }
      },
      (error) => {
        console.error('Error fetching user:', error);
        this.toastrService.error('Error fetching user data');
      }
    );
  }

  resetForm(): void {
    this.UserMasterForm.reset();
    this.submitted = false;
    this.showError = false;
  }

  onSubmit(): void {
    debugger;
    this.submitted = true;
    if (this.UserMasterForm.invalid) {
      this.showError = true;
      return;
    }
    // Convert Form Data to Expected Payload Format
    const payload = [
      {
        pk_userId: this.isEditMode ? this.pk_userId : '',
        ...this.UserMasterForm.value,
        oldPassword: this.isEditMode ? this.oldPassword : '', // Include old password only in edit mode
      },
    ];

    if (this.isEditMode && this.pk_userId) {
      // Update existing user
      this.userMasterService.update_User(payload).subscribe(
        (response) => {
          if (response.isSuccess) {
            this.toastrService.success(
              response.message || 'User updated successfully!'
            );
            this.router.navigate(['/dash/user/userdashboard/user-master_list']);
          } else {
            this.toastrService.error(
              response.message || 'Failed to update user'
            );
          }
        },
        (error) => {
          console.error('Update Error:', error);
          this.toastrService.error('Error updating user');
        }
      );
    } else {
      // Create new user
      this.userMasterService.add_User(payload).subscribe(
        (response) => {
          if (response.isSuccess) {
            this.toastrService.success(
              response.message || 'User created successfully!'
            );
            this.router.navigate(['/dash/user/userdashboard/user-master_list']);
          } else {
            this.toastrService.error(
              response.message || 'Failed to create user'
            );
          }
        },
        (error) => {
          console.error('Create Error:', error);
          this.toastrService.error('Error creating user');
        }
      );
    }
  }
}