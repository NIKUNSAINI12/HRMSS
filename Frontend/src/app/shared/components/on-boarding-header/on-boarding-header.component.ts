
import { Component, HostListener} from '@angular/core';

@Component({
  selector: 'app-on-boarding-header',
  standalone: true,
  imports: [],
  templateUrl: './on-boarding-header.component.html',
  styleUrl: './on-boarding-header.component.scss'
})
export class OnBoardingHeaderComponent {


  isMiniSidebarActive: boolean = false; // Track desktop mini sidebar toggle state
  private sidebarHovered: boolean = false; // Track whether the sidebar is being hovered/touched

  // Toggle sidebar on toggle button click
  onToggleBodyClass(): void {
    const isMobileView = window.innerWidth <= 768;
    const body = document.body;

    if (isMobileView) {
      const isGone = body.classList.contains('sidebar-gone');

      if (isGone) {
        // Open sidebar
        body.classList.remove('sidebar-gone');



      } else {
        // Sidebar already open, so close it immediately
        body.classList.add('sidebar-gone');

      }

    } else {
      // Desktop view: Toggle mini sidebar
      if (this.isMiniSidebarActive) {
        body.classList.remove('sidebar-mini');
      } else {
        body.classList.add('sidebar-mini');
      }
      this.isMiniSidebarActive = !this.isMiniSidebarActive;
    }
  }




  
    // Listen to mouse movement or touch on the page
    // Used to detect if user is interacting with the sidebar during the 2s window
    @HostListener('document:mousemove', ['$event'])
    @HostListener('document:touchstart', ['$event'])
    onUserInteract(event: Event): void {
      const isMobileView = window.innerWidth <= 768;
      const target = event.target as HTMLElement;
      const insideSidebar = target.closest('.main-sidebar');
  
      if (isMobileView) {
        if (insideSidebar) {
          this.sidebarHovered = true;
  
        } else {
          this.sidebarHovered = false;
        }
      }
    }
  
  
  
  
  
    @HostListener('document:click', ['$event'])
    onDocumentClick(event: MouseEvent): void {
      const isMobileView = window.innerWidth <= 768;
      const target = event.target as HTMLElement;
  
      const clickedInsideSidebar = target.closest('.main-sidebar');
      const clickedOnToggleButton = target.closest('.collapse-btn');
      const clickedSidebarAnchor = target.closest('.main-sidebar a');
      const isWithoutAnchorSidebar = clickedSidebarAnchor?.classList.contains('without-anchor-sidebar');
  
      if (isMobileView) {
        if (!clickedInsideSidebar && !clickedOnToggleButton) {
          // Clicked outside sidebar and toggle
          document.body.classList.add('sidebar-gone');
        } else if (clickedSidebarAnchor && !isWithoutAnchorSidebar) {
          // Clicked on an anchor inside sidebar that is NOT excluded
          setTimeout(() => {
            document.body.classList.add('sidebar-gone');
          }, 150); // small delay for route transition
        }
      }
    }
  
  

}
