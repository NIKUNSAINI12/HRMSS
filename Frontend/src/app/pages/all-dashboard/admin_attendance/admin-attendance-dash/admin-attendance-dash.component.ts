import { Component, AfterViewInit, OnDestroy, OnInit, PLATFORM_ID, Inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { CommonModule, isPlatformBrowser } from '@angular/common';
import { FormBuilder, FormGroup, FormsModule, ReactiveFormsModule } from '@angular/forms';
import { Chart, DoughnutController, ArcElement, Tooltip, Legend } from 'chart.js';
import { ToastrService } from 'ngx-toastr';
import { NgxUiLoaderService } from 'ngx-ui-loader';
import { MonthlyRentDetailService } from '../../payroll/services/monthly-rent-detail.service';
import { PayrollService } from '../../payroll/services/payroll.service';
import { NgSelectComponent } from '@ng-select/ng-select';
import { forkJoin } from 'rxjs';

Chart.register(DoughnutController, ArcElement, Tooltip, Legend);

@Component({
  selector: 'app-admin-attendance-dash',
  standalone: true,
  imports: [RouterLink, CommonModule, FormsModule,ReactiveFormsModule,NgSelectComponent],
  templateUrl: './admin-attendance-dash.component.html',
  styleUrl: './admin-attendance-dash.component.scss'
})
export class AdminAttendanceDashComponent implements OnInit, AfterViewInit, OnDestroy {


  form!: FormGroup;
      months: any[] = [];
      years: any[] = [];
       dashboardSummary: any = {};

  // processed =185;
  // unprocess =28;
  // locked = 22;
  // latecomming =15;
  // absent =10;
  // missedpunch =10;
  get totalEmployee() {
  return this.dashboardSummary?.TotalEmployee || 0;
}
get processed() {
  return this.dashboardSummary?.AttendanceProcess || 0;
}
get unprocess() {
  return this.dashboardSummary?.AttendanceUnprocess || 0;
}
get locked() {
  return this.dashboardSummary?.SalaryProcess || 0;
}
get latecomming() {
  return this.dashboardSummary?.LateComing_Count || 0;
}
get absent() {
  return this.dashboardSummary?.Absent_Count || 0;
}

get missedpunch() {
  return this.dashboardSummary?.Absent_Count || 0;
}

  searchText   = '';
  filterStatus = '';
  showAll      = false;
  selectedMonth = '';
  selectedYear  = '';

  attendanceList: any[] = [];

  private chart!: Chart;

  constructor(@Inject(PLATFORM_ID) private platformId: Object,private httpService: MonthlyRentDetailService,  // For month/year list
        private payrollService: PayrollService, private toastrService: ToastrService,private Loader: NgxUiLoaderService,   private fb: FormBuilder) {}

  ngOnInit(): void {
    this.form = this.fb.group({
        month: [null],
        year: [null]
      });
     
    this.loadDropdowns();
  }
   loadDropdowns(): void {
        forkJoin([
          this.httpService.getCommanList('Month'),
          this.httpService.getCommanList('Year')
        ]).subscribe({
          next: ([monthRes, yearRes]) => {
            // Assuming API returns fields like { name, value }
            this.months = monthRes.data.slice(1);
            this.years = yearRes.data.slice(1);
    
            const currentMonth = new Date().getMonth() + 1;
            const currentYear = new Date().getFullYear();
    
            const monthMatch = this.months.find((m: any) => +m.value === currentMonth);
            const yearMatch = this.years.find((y: any) => +y.value === currentYear);
    
            if (monthMatch && yearMatch) {
              this.form.patchValue({
                month: monthMatch.value,
                year: yearMatch.value
              });
              this.loadAttendanceData(monthMatch.value, yearMatch.value);
            }
          },
          error: () => {
            this.toastrService.error('Failed to load month/year data');
          }
        });
      }


  ngAfterViewInit(): void {
    if (isPlatformBrowser(this.platformId)) {
      setTimeout(() => this.initChart(), 300);
    }
  }

  
  loadAttendanceData(month: number, year: number): void {
      this.Loader.start();
  
      this.payrollService.Attendancedash(month, year).subscribe({
        next: (res) => {
          this.Loader.stop();
            this.dashboardSummary = res.data?.summary || {};
             // Map API response fields to match your table's expected fields
      this.attendanceList = (res.data?.leave || []).map((emp: any) => ({
  name: emp.empname,
  empCode: emp.empcode,
  date: emp.dated,
  leave_type: emp.LeaveType,
  status: emp.Status
}));
           
      setTimeout(() => {
        if (isPlatformBrowser(this.platformId)) {
          this.initChart();
        }
      }, 100);
    },
        error: (err) => {
          this.Loader.stop();
          this.toastrService.error('Failed to load dashboard data');
          console.error(err);
             this.dashboardSummary = {};
       
        
        }
      });
    }
  // Filtered + paginated
  get filteredAttendance(): any[] {
    const s = this.searchText.toLowerCase();
    const filtered = this.attendanceList.filter(att => {
      const matchSearch =
        att.name.toLowerCase().includes(s)       ||
        att.empCode.toLowerCase().includes(s)    ||
      
        att.date.toLowerCase().includes(s) ||
        att.leave_type.toLowerCase().includes(s); 
      const matchStatus = this.filterStatus ? att.leave_type === this.filterStatus : true;
      return matchSearch && matchStatus;
    });
    return this.showAll ? filtered : filtered.slice(0, 4);
  }

  toggleViewAll(): void {
    this.showAll = !this.showAll;
  }

  // Chart.js Donut
  initChart(): void {
    const canvas = document.getElementById('attChartDiv') as HTMLCanvasElement;
    if (!canvas) return;
    if (this.chart) this.chart.destroy();

    const data  = [this.processed, this.unprocess, this.locked, this.latecomming, this.absent, this.missedpunch];
    const total = data.reduce((s, v) => s + v, 0);
    const THRESHOLD = 0.04;

    const datalabelsPlugin = {
      id: 'customDatalabels',
      afterDatasetDraw(chart: any) {
        const { ctx, data: chartData } = chart;
        const meta   = chart.getDatasetMeta(0);
        const values: number[] = chartData.datasets[0].data;
        const sum    = values.reduce((a: number, b: number) => a + b, 0);
        meta.data.forEach((arc: any, i: number) => {
          const pct = sum > 0 ? values[i] / sum : 0;
          if (pct < THRESHOLD) return;
          const { x, y } = arc.tooltipPosition();
          ctx.save();
          ctx.fillStyle    = '#ffffff';
          ctx.font         = 'bold 11px sans-serif';
          ctx.textAlign    = 'center';
          ctx.textBaseline = 'middle';
          ctx.shadowColor  = 'rgba(0,0,0,0.3)';
          ctx.shadowBlur   = 3;
          ctx.fillText(`${Math.round(pct * 100)}%`, x, y);
          ctx.restore();
        });
      }
    };

    this.chart = new Chart(canvas, {
      type: 'doughnut',
      data: {
        labels: ['Process', 'UnProcessed', 'Locked', 'Late Coming','Absent', 'Missed Punch'],
        datasets: [{
          data,
          backgroundColor: ['#54ca68','#3080e8','#20c9d8','#ffa446', '#e35b5d', '#cdd3d8'  ],
          borderColor: '#ffffff',
          borderWidth: 4,
          hoverOffset: 8
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        cutout: '60%',
        plugins: {
          legend: { display: false },
          tooltip: {
            callbacks: {
              label: (ctx) => {
                const pct = total > 0 ? ((ctx.parsed / total) * 100).toFixed(1) : '0';
                return ` ${ctx.label}: ${ctx.parsed} (${pct}%)`;
              }
            }
          }
        },
        animation: { animateRotate: true, duration: 1000 }
      },
      plugins: [datalabelsPlugin]
    });
  }

  onSelectionChange(): void {
      const { month, year } = this.form.value;
      if (month && year) {
        this.loadAttendanceData(month, year);
      }
    }
  ngOnDestroy(): void {
    if (this.chart) this.chart.destroy();
  }
}