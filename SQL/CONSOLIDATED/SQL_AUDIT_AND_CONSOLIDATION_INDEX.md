# SQL Files Redundancy & Consolidation Audit Report
Total SQL Files in repository: 67

## 1. Stored Procedures Modified Multiple Times (Repeated Patches)
| Stored Procedure | Times Modified | Sequential Files (Order of Modification) | Latest Authoritative File |
| :--- | :---: | :--- | :--- |
| **USP_REC_GETJOBREQUISITIONS** | 6 | 08_USP_REC_JobRequisition_Workflow.sql -> 15_CJ_DARCL_Job_Requisition_HiredCount_FilledStatus.sql -> 17_CJ_DARCL_Company_Mapping_All_Tables_Diversity_Null.sql -> 35_CJ_DARCL_JobRequisition_EmployeeMaster_Dropdowns_And_Save.sql -> 39_CJ_DARCL_Fix_GetJobRequisitions_Table_Joins.sql -> 41_Rejection_Resubmit_Workflow.sql | **41_Rejection_Resubmit_Workflow.sql** |
| **USP_REC_GETVENDORASSIGNEDJOBS** | 5 | 22_CJ_DARCL_Vendor_Portal_Architecture.sql -> 23_CJ_DARCL_Vendor_Only_Approved_Jobs.sql -> 25_CJ_DARCL_Fix_Vendor_Portal_Assigned_Jobs.sql -> 28_CJ_DARCL_Fix_Assigned_Jobs_Columns.sql -> 47_CJ_DARCL_Fix_Vendor_Portal_Metrics_And_Job_Counts.sql | **47_CJ_DARCL_Fix_Vendor_Portal_Metrics_And_Job_Counts.sql** |
| **USP_REC_GETVENDORSFORREQUISITIONMAPPING** | 5 | 10_CJ_DARCL_Full_Recruitment_Lifecycle_Steps4_to_16.sql -> 12_ALTER_REC_Requisition_Vendor_Mapping_Add_VendorType.sql -> 13_MAP_Vendors_To_Locations_And_Filter_By_Job_Location.sql -> 32_CJ_DARCL_Strict_Company_Scoped_Vendor_Allocation.sql -> 33_CJ_DARCL_Strict_Requisition_Company_Vendor_Scoping.sql | **33_CJ_DARCL_Strict_Requisition_Company_Vendor_Scoping.sql** |
| **USP_REC_ASSIGNBENCHCANDIDATESTOJOB** | 4 | 45_CJ_DARCL_Vendor_Pool_Bench_And_Rejected_Allocation.sql -> 46_CJ_DARCL_Pipeline_Company_Pool_Bench_And_Rejected_Allocation.sql -> 48_CJ_DARCL_Fix_AssignBenchCandidatesToJob_Schema.sql -> 49_CJ_DARCL_Reset_Reallocated_Candidate_State_As_New.sql | **49_CJ_DARCL_Reset_Reallocated_Candidate_State_As_New.sql** |
| **USP_REC_GETCANDIDATEPIPELINEROSTER** | 4 | 10_CJ_DARCL_Full_Recruitment_Lifecycle_Steps4_to_16.sql -> 13_CJ_DARCL_Candidate_Tagging_StageMovement_Rejection_Architecture.sql -> 18_CJ_DARCL_Rejected_Candidate_Stage_Lock.sql -> 51_CJ_DARCL_Retain_Hold_Candidates_In_Interview_Stage.sql | **51_CJ_DARCL_Retain_Hold_Candidates_In_Interview_Stage.sql** |
| **USP_REC_SAVEVENDORREQUISITIONMAPPING** | 4 | 10_CJ_DARCL_Full_Recruitment_Lifecycle_Steps4_to_16.sql -> 12_ALTER_REC_Requisition_Vendor_Mapping_Add_VendorType.sql -> 13_MAP_Vendors_To_Locations_And_Filter_By_Job_Location.sql -> 33_CJ_DARCL_Strict_Requisition_Company_Vendor_Scoping.sql | **33_CJ_DARCL_Strict_Requisition_Company_Vendor_Scoping.sql** |
| **USP_REC_GETVENDORPORTALMETRICS** | 4 | 22_CJ_DARCL_Vendor_Portal_Architecture.sql -> 23_CJ_DARCL_Vendor_Only_Approved_Jobs.sql -> 25_CJ_DARCL_Fix_Vendor_Portal_Assigned_Jobs.sql -> 47_CJ_DARCL_Fix_Vendor_Portal_Metrics_And_Job_Counts.sql | **47_CJ_DARCL_Fix_Vendor_Portal_Metrics_And_Job_Counts.sql** |
| **USP_REC_SAVEJOBREQUISITION** | 4 | 08_USP_REC_JobRequisition_Workflow.sql -> 17_CJ_DARCL_Company_Mapping_All_Tables_Diversity_Null.sql -> 35_CJ_DARCL_JobRequisition_EmployeeMaster_Dropdowns_And_Save.sql -> 38_CJ_DARCL_SaveJobRequisition_Approver_And_Team.sql | **38_CJ_DARCL_SaveJobRequisition_Approver_And_Team.sql** |
| **USP_REC_SUBMITINTERVIEWEVALUATION** | 3 | 10_CJ_DARCL_Full_Recruitment_Lifecycle_Steps4_to_16.sql -> 50_CJ_DARCL_Fix_SubmitInterviewEvaluation_Company_Scoping_And_Score_Persistence.sql -> 51_CJ_DARCL_Retain_Hold_Candidates_In_Interview_Stage.sql | **51_CJ_DARCL_Retain_Hold_Candidates_In_Interview_Stage.sql** |
| **USP_REC_MOVECANDIDATESTAGE** | 3 | 13_CJ_DARCL_Candidate_Tagging_StageMovement_Rejection_Architecture.sql -> 21_CJ_DARCL_Enforce_Docs_Verified_Before_Stage_Progression.sql -> 52_CJ_DARCL_Enhance_MoveCandidateStage_CompanyScoping_And_Hold_Progression.sql | **52_CJ_DARCL_Enhance_MoveCandidateStage_CompanyScoping_And_Hold_Progression.sql** |
| **USP_REC_GETVENDORLISTFORPORTAL** | 3 | 22_CJ_DARCL_Vendor_Portal_Architecture.sql -> 25_CJ_DARCL_Fix_Vendor_Portal_Assigned_Jobs.sql -> 32_CJ_DARCL_Strict_Company_Scoped_Vendor_Allocation.sql | **32_CJ_DARCL_Strict_Company_Scoped_Vendor_Allocation.sql** |
| **USP_REC_SUBMITVENDORCANDIDATE** | 3 | 22_CJ_DARCL_Vendor_Portal_Architecture.sql -> 29_CJ_DARCL_Vendor_Candidate_Aadhaar_Phone_Verification.sql -> 34_CJ_DARCL_Vendor_All_Candidates_And_Bench_Registration.sql | **34_CJ_DARCL_Vendor_All_Candidates_And_Bench_Registration.sql** |
| **USP_REC_REGISTERCANDIDATEAPPLICATION** | 3 | 10_CJ_DARCL_Full_Recruitment_Lifecycle_Steps4_to_16.sql -> 14_CJ_DARCL_Register_Aadhaar_Duplicate_Reject.sql -> 49_CJ_DARCL_Reset_Reallocated_Candidate_State_As_New.sql | **49_CJ_DARCL_Reset_Reallocated_Candidate_State_As_New.sql** |
| **USP_CANDIDATE_REPORT_GET** | 2 | 55_CJ_DARCL_Recruitment_Reports_USPs.sql -> USP_Candidate_Report_Get.sql | **USP_Candidate_Report_Get.sql** |
| **USP_REC_GETVENDORPOOLCANDIDATES** | 2 | 45_CJ_DARCL_Vendor_Pool_Bench_And_Rejected_Allocation.sql -> 46_CJ_DARCL_Pipeline_Company_Pool_Bench_And_Rejected_Allocation.sql | **46_CJ_DARCL_Pipeline_Company_Pool_Bench_And_Rejected_Allocation.sql** |
| **USP_MRF_REPORT_GET** | 2 | 55_CJ_DARCL_Recruitment_Reports_USPs.sql -> USP_MRF_Report_Get.sql | **USP_MRF_Report_Get.sql** |
| **USP_REPORT_MASTER_DATA_GET** | 2 | 55_CJ_DARCL_Recruitment_Reports_USPs.sql -> USP_Report_Master_Data_Get.sql | **USP_Report_Master_Data_Get.sql** |
| **USP_VENDOR_REPORT_GET** | 2 | 55_CJ_DARCL_Recruitment_Reports_USPs.sql -> USP_Vendor_Report_Get.sql | **USP_Vendor_Report_Get.sql** |
| **USP_LOCATION_WISE_JOBS_REPORT_GET** | 2 | 55_CJ_DARCL_Recruitment_Reports_USPs.sql -> USP_Location_Wise_Jobs_Report_Get.sql | **USP_Location_Wise_Jobs_Report_Get.sql** |
| **USP_JOB_REPORT_GET** | 2 | 55_CJ_DARCL_Recruitment_Reports_USPs.sql -> USP_Job_Report_Get.sql | **USP_Job_Report_Get.sql** |
| **USP_LOCATION_REPORT_GET** | 2 | 55_CJ_DARCL_Recruitment_Reports_USPs.sql -> USP_Location_Report_Get.sql | **USP_Location_Report_Get.sql** |
| **USP_VENDOR_WISE_REPORT_GET** | 2 | 55_CJ_DARCL_Recruitment_Reports_USPs.sql -> USP_Vendor_Wise_Report_Get.sql | **USP_Vendor_Wise_Report_Get.sql** |
| **USP_REC_UPDATEJOBREQUISITION** | 2 | 40_CJ_DARCL_JobRequisition_GetById_And_Update.sql -> 41_Rejection_Resubmit_Workflow.sql | **41_Rejection_Resubmit_Workflow.sql** |
| **USP_REC_REJECTREQUISITION** | 2 | 08_USP_REC_JobRequisition_Workflow.sql -> 09_USP_REC_Company_Scoped_Email_Approvals.sql | **09_USP_REC_Company_Scoped_Email_Approvals.sql** |
| **USP_REC_GETLOCATIONMANPOWERLIST** | 2 | 09_USP_REC_GetLocationManpowerList.sql -> 54_CJ_DARCL_Location_QR_Spot_Walkin_Hiring_And_Manpower.sql | **54_CJ_DARCL_Location_QR_Spot_Walkin_Hiring_And_Manpower.sql** |
| **USP_REC_APPROVEREQUISITION** | 2 | 08_USP_REC_JobRequisition_Workflow.sql -> 09_USP_REC_Company_Scoped_Email_Approvals.sql | **09_USP_REC_Company_Scoped_Email_Approvals.sql** |
| **LOCATION_UPDATE_MANPOWER_BUFFER** | 2 | 02_SP_Location_Update_Manpower_Buffer.sql -> 54_CJ_DARCL_Location_QR_Spot_Walkin_Hiring_And_Manpower.sql | **54_CJ_DARCL_Location_QR_Spot_Walkin_Hiring_And_Manpower.sql** |
| **USP_REC_GETREQUISITIONMASTERDATA** | 2 | 08_USP_REC_JobRequisition_Workflow.sql -> 37_CJ_DARCL_GetRequisitionMasterData_CompanySpecificEmployees.sql | **37_CJ_DARCL_GetRequisitionMasterData_CompanySpecificEmployees.sql** |
| **USP_REC_SAVECANDIDATEONBOARDINGDOSSIER** | 2 | 19_CJ_DARCL_Document_Review_Verification_Architecture.sql -> 31_CJ_DARCL_Allow_Editing_Prefilled_Candidate_Details_In_Dossier.sql | **31_CJ_DARCL_Allow_Editing_Prefilled_Candidate_Details_In_Dossier.sql** |
| **USP_REC_GETJOBREQUISITIONBYID** | 2 | 40_CJ_DARCL_JobRequisition_GetById_And_Update.sql -> 41_Rejection_Resubmit_Workflow.sql | **41_Rejection_Resubmit_Workflow.sql** |
| **USP_REC_REGISTERCANDIDATE** | 2 | 16_CJ_DARCL_Register_Candidate_Reject_Without_Save_And_Fix_Role.sql -> 17_CJ_DARCL_Company_Mapping_All_Tables_Diversity_Null.sql | **17_CJ_DARCL_Company_Mapping_All_Tables_Diversity_Null.sql** |
| **USP_REC_GETCANDIDATELIFECYCLEAUDIT** | 2 | 10_CJ_DARCL_Full_Recruitment_Lifecycle_Steps4_to_16.sql -> 20_CJ_DARCL_Candidate_Audit_Trail_Company_Scoping.sql | **20_CJ_DARCL_Candidate_Audit_Trail_Company_Scoping.sql** |
| **USP_REC_REJECTCANDIDATE** | 2 | 13_CJ_DARCL_Candidate_Tagging_StageMovement_Rejection_Architecture.sql -> 18_CJ_DARCL_Rejected_Candidate_Stage_Lock.sql | **18_CJ_DARCL_Rejected_Candidate_Stage_Lock.sql** |

## 2. Stored Procedures Defined Once
| Stored Procedure | Defined In File |
| :--- | :--- |
| **UM_SP_GETUSERACCESSRIGHTS** | 43_CJ_DARCL_L1L2L3_USPs.sql |
| **UM_SP_GETWEBPAGESONUSERMODID** | 43_CJ_DARCL_L1L2L3_USPs.sql |
| **UM_SP_INSERTUSERPAGERIGHTS** | 43_CJ_DARCL_L1L2L3_USPs.sql |
| **USP_REC_CHECKCANDIDATEAADHAARSTATUS** | 54_CJ_DARCL_Location_QR_Spot_Walkin_Hiring_And_Manpower.sql |
| **USP_REC_DEALLOCATEVENDORREQUISITIONMAPPING** | 13_MAP_Vendors_To_Locations_And_Filter_By_Job_Location.sql |
| **USP_REC_GENERATEOFFERLETTER** | 10_CJ_DARCL_Full_Recruitment_Lifecycle_Steps4_to_16.sql |
| **USP_REC_GETAPPROVALHISTORY** | 08_USP_REC_JobRequisition_Workflow.sql |
| **USP_REC_GETCANDIDATEDOCUMENTFILE** | 27_CJ_DARCL_USP_GetCandidateDocumentFile.sql |
| **USP_REC_GETCANDIDATEDOCUMENTS** | 19_CJ_DARCL_Document_Review_Verification_Architecture.sql |
| **USP_REC_GETMYAPPROVALLEVEL** | 08_USP_REC_JobRequisition_Workflow.sql |
| **USP_REC_GETPENDINGAPPROVALS** | 08_USP_REC_JobRequisition_Workflow.sql |
| **USP_REC_GETPIPELINESTAGECONFIG** | 10_REC_PipelineStageConfig.sql |
| **USP_REC_GETPUBLICLOCATIONJOBSANDVENDORS** | 54_CJ_DARCL_Location_QR_Spot_Walkin_Hiring_And_Manpower.sql |
| **USP_REC_GETRECRUITMENTMISREPORT** | 10_CJ_DARCL_Full_Recruitment_Lifecycle_Steps4_to_16.sql |
| **USP_REC_GETVENDORALLCANDIDATES** | 34_CJ_DARCL_Vendor_All_Candidates_And_Bench_Registration.sql |
| **USP_REC_GETVENDORJOBSUBMISSIONS** | 30_CJ_DARCL_USP_GetVendorJobSubmissions.sql |
| **USP_REC_GETVENDORSELECTEDCANDIDATES** | 22_CJ_DARCL_Vendor_Portal_Architecture.sql |
| **USP_REC_HIREANDTRANSFERTOEMPLOYEEMASTER** | 10_CJ_DARCL_Full_Recruitment_Lifecycle_Steps4_to_16.sql |
| **USP_REC_SAVECANDIDATEONBOARDINGDOCS** | 10_CJ_DARCL_Full_Recruitment_Lifecycle_Steps4_to_16.sql |
| **USP_REC_SCHEDULECANDIDATEINTERVIEW** | 10_CJ_DARCL_Full_Recruitment_Lifecycle_Steps4_to_16.sql |
| **USP_REC_SEEDCANDIDATEDOCUMENTS** | 22_CJ_DARCL_Vendor_Portal_Architecture.sql |
| **USP_REC_SUBMITWALKINCANDIDATE** | 54_CJ_DARCL_Location_QR_Spot_Walkin_Hiring_And_Manpower.sql |
| **USP_REC_TAGCANDIDATE** | 13_CJ_DARCL_Candidate_Tagging_StageMovement_Rejection_Architecture.sql |
| **USP_REC_UPLOADCANDIDATEDOCUMENTITEM** | 19_CJ_DARCL_Document_Review_Verification_Architecture.sql |
| **USP_REC_UPSERTPIPELINESTAGECONFIG** | 10_REC_PipelineStageConfig.sql |
| **USP_REC_VERIFYCANDIDATEDOCUMENTITEM** | 19_CJ_DARCL_Document_Review_Verification_Architecture.sql |
| **USP_REC_VERIFYCANDIDATEDOCUMENTS** | 10_CJ_DARCL_Full_Recruitment_Lifecycle_Steps4_to_16.sql |
| **USP_UM_GETUSERVENDORPROFILE** | 26_CJ_DARCL_USP_GetUserVendorProfile.sql |
| **USP_UM_RESOLVEUSERNAME** | 40_CJ_DARCL_JobRequisition_GetById_And_Update.sql |

## 3. Tables Altered Multiple Times Across Incremental Files
| Table Name | Files With ALTER TABLE Statements |
| :--- | :--- |
| **REC_JOBREQUISITION_MST** | 04_ALTER_REC_JobRequisition_Mst_Add_CJ_DARCL_Fields.sql, 05_ALTER_REC_JobRequisition_Mst_Add_All_Wizard_Fields.sql, 06_ALTER_REC_JobRequisition_Mst_Add_Workflow_Cols.sql, 10_CJ_DARCL_Full_Recruitment_Lifecycle_Steps4_to_16.sql, 17_CJ_DARCL_Company_Mapping_All_Tables_Diversity_Null.sql, 18_CJ_DARCL_Rejected_Candidate_Stage_Lock.sql, 35_CJ_DARCL_JobRequisition_EmployeeMaster_Dropdowns_And_Save.sql, 40_CJ_DARCL_JobRequisition_GetById_And_Update.sql, 41_Rejection_Resubmit_Workflow.sql |
| **REC_CANDIDATE_APPLICATIONS** | 12_ALTER_REC_Requisition_Vendor_Mapping_Add_VendorType.sql, 13_CJ_DARCL_Candidate_Tagging_StageMovement_Rejection_Architecture.sql, 17_CJ_DARCL_Company_Mapping_All_Tables_Diversity_Null.sql, 18_CJ_DARCL_Rejected_Candidate_Stage_Lock.sql, 19_CJ_DARCL_Document_Review_Verification_Architecture.sql, 36_CJ_DARCL_Allow_Null_ReqId_For_Bench_Candidates.sql |
| **REC_OPEN_NEWJOB** | 18_CJ_DARCL_Rejected_Candidate_Stage_Lock.sql |
| **UM_USERS_MST** | 24_CJ_DARCL_Add_User_Vendor_Columns_And_Seed_User.sql |
| **UM_USERPAGERIGHTS** | 42_CJ_DARCL_L1L2L3_Rights_Schema.sql |
| **DBO** | 17_CJ_DARCL_Company_Mapping_All_Tables_Diversity_Null.sql |
| **REC_JOBREQUISITION_MST_APPROVAL** | 07_REC_Approval_Workflow_Log_And_Config.sql |
| **REC_REQUISITION_VENDOR_MAPPING** | 12_ALTER_REC_Requisition_Vendor_Mapping_Add_VendorType.sql |
| **LOCATION_MST** | 01_ALTER_Location_Mst_Add_Manpower_Buffer.sql |

## 4. Tables Created Across Scripts
| Table Name | Created In File |
| :--- | :--- |
| **REC_APPROVALLEVEL_CONFIG** | 07_REC_Approval_Workflow_Log_And_Config.sql |
| **REC_CANDIDATE_APPLICATIONS** | 10_CJ_DARCL_Full_Recruitment_Lifecycle_Steps4_to_16.sql |
| **REC_CANDIDATE_DOCUMENTS** | 19_CJ_DARCL_Document_Review_Verification_Architecture.sql, 19_CJ_DARCL_Document_Review_Verification_Architecture.sql |
| **REC_CANDIDATE_LIFECYCLE_AUDIT** | 10_CJ_DARCL_Full_Recruitment_Lifecycle_Steps4_to_16.sql |
| **REC_PIPELINE_STAGE_CONFIG** | 10_REC_PipelineStageConfig.sql, 10_REC_PipelineStageConfig.sql |
| **REC_REQUISITION_VENDOR_MAPPING** | 10_CJ_DARCL_Full_Recruitment_Lifecycle_Steps4_to_16.sql |
