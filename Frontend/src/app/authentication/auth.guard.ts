import { Injectable } from '@angular/core';
import {
  CanActivate,
  CanActivateChild,
  CanMatch,
  ActivatedRouteSnapshot,
  RouterStateSnapshot,
  Route,
  UrlSegment,
  Router,
  UrlTree
} from '@angular/router';
import { AuthService } from './service/auth.service';
import { MenuService } from '../shared/services/menu.service';
import { Observable, of } from 'rxjs';
import { filter, take, map, catchError } from 'rxjs/operators';

@Injectable({
  providedIn: 'root',
})
export class AuthGuard implements CanActivate, CanActivateChild, CanMatch {
  constructor(
    private auth: AuthService,
    private router: Router,
    private menuService: MenuService
  ) { }

  canActivate(route: ActivatedRouteSnapshot, state: RouterStateSnapshot): Observable<boolean | UrlTree> {
    return this.checkAccess(state.url);
  }

  canActivateChild(route: ActivatedRouteSnapshot, state: RouterStateSnapshot): Observable<boolean | UrlTree> {
    return this.checkAccess(state.url);
  }

  canMatch(route: Route, segments: UrlSegment[]): Observable<boolean | UrlTree> {
    const fullPath = segments.map(s => s.path).join('/');
    return this.checkAccess(`/${fullPath}`);
  }

  private checkAccess(url: string): Observable<boolean | UrlTree> {
    const token = sessionStorage.getItem('accessToken');
    if (!token || !this.auth.loggedIn()) {
      console.warn('🔐 No token or not logged in, redirecting to login.');
      return of(this.router.createUrlTree(['/auth/login']));
    }

    return this.menuService.menu$.pipe(
      filter(menu => Array.isArray(menu) && menu.length > 0), // ✅ Wait for non-empty menu
      take(1),
      map(menu => {


        const normalizedUrl = url.replace(/^\/dash\//, '').toLowerCase();

        const hasAccess = menu.some(item => {
          const menuPath = (item.pagepath || '').toLowerCase();



          // return normalizedUrl.startsWith(menuPath);
             // ✅ Direct match
        if (normalizedUrl.startsWith(menuPath)) return true;

        // ✅ Auto-map: if user has *_list, allow base route and edit
        if (menuPath.endsWith('_list')) {
          const basePath = menuPath.replace('_list', '');
          if (normalizedUrl.startsWith(basePath)) {
            return true;
          }

            // ✅ Special case: if user has employee_list, allow stepper routes
            if (basePath === 'Employee') {
              const employeeSubPaths = [
                'EmployeeMst',
                'EmployeeAttendance',
                'EmployeeOtherDetails',
                'EmployeeHead'
              ];
              return employeeSubPaths.some(p => normalizedUrl.startsWith(p));
            }
        //end here    // ✅ Special case: if user has employee_list, allow stepper routes
        }
        return false;
    });
        


       


        if (!hasAccess) {
          console.warn('🚫 Access denied for URL:', url);
          return this.router.createUrlTree(['/dash/dashboard'], {
            queryParams: { alert: 'no-access' }
          });
        }

        return true;
      }),
      catchError(err => {
        console.error('AuthGuard error:', err);
        return of(this.router.createUrlTree(['/auth/login']));
      })
    );
  }
}