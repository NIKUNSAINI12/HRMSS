import { Injectable } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';

@Injectable({
  providedIn: 'root'
})
export class FinalSubmissionService {

  constructor(private http: HttpClient) {}

  private getHeaders(): HttpHeaders {
    const candidateKey = sessionStorage.getItem('candidateKey') || '';
    return new HttpHeaders({ 'X-Candidate-Key': candidateKey });
  }

  // ✅ Get candidate final summary
  getCandidateFinalSummary(): Observable<any> {
    return this.http.get<any>(
      `${environment.baseURL1}/CandidateExperienceDetails/final-summary`,
      { headers: this.getHeaders() }
    );
  }

  // Submit onboarding
  submitOnboarding(): Observable<any> {
    return this.http.post<any>(
      `${environment.baseURL1}/CandidateExperienceDetails/submit-onboarding`,
      {},
      { headers: this.getHeaders() }
    );
  }

  getImageOnboard(filename: string): Observable<Blob> {
    const candidateKey = sessionStorage.getItem('candidateKey') || '';
    const url = `${environment.baseURL1}/CandidateExperienceDetails/images/${filename}`;
    return this.http.get(url, { 
      headers: this.getHeaders(),
      responseType: 'blob' 
    });
  }
}