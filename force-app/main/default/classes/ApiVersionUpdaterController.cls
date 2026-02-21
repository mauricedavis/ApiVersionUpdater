public with sharing class ApiVersionUpdaterController {
    
    @AuraEnabled(cacheable=true)
    public static OrgContextService.OrgContextDto getOrgContext() {
        return OrgContextService.getOrgContext();
    }
    
    @AuraEnabled(cacheable=true)
    public static SettingsService.SettingsDto getSettings() {
        return SettingsService.getSettings();
    }
    
    @AuraEnabled
    public static SettingsService.SettingsDto saveSettings(String settingsJson) {
        return SettingsService.saveSettings(settingsJson);
    }
    
    @AuraEnabled(cacheable=true)
    public static List<String> getSupportedComponentTypes() {
        return SettingsService.getSupportedComponentTypes();
    }
    
    @AuraEnabled(cacheable=true)
    public static List<String> getAvailableApiVersions() {
        return SettingsService.getAvailableApiVersions();
    }
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getInventoryCounts() {
        return InventoryService.getInventoryCounts();
    }
    
    @AuraEnabled
    public static InventoryService.InventoryResultDto queryArtifacts(String filterJson) {
        return InventoryService.queryArtifacts(filterJson);
    }
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getVersionDistribution(String artifactType) {
        return InventoryService.getVersionDistribution(artifactType);
    }
    
    @AuraEnabled
    public static InventoryService.ComplianceMetricsDto getComplianceMetrics(Decimal targetApiVersion, String scopePolicy) {
        return InventoryService.getComplianceMetrics(targetApiVersion, scopePolicy);
    }
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Map<String, Integer>> getVersionDistributionAllTypes(String scopePolicy) {
        return InventoryService.getVersionDistributionAllTypes(scopePolicy);
    }
    
    @AuraEnabled
    public static InventoryService.ArtifactDto getArtifactDetails(String artifactId, String artifactType) {
        return InventoryService.getArtifactDetails(artifactId, artifactType);
    }
    
    @AuraEnabled
    public static InventoryService.NonCompliantComponentsDto getNonCompliantComponents(Decimal targetApiVersion, String scopePolicy) {
        return InventoryService.getNonCompliantComponents(targetApiVersion, scopePolicy);
    }
    
    @AuraEnabled
    public static ContentService.ContentDto fetchContent(String artifactId, String artifactType) {
        return ContentService.fetchContent(artifactId, artifactType);
    }
    
    @AuraEnabled
    public static String startScan(String requestJson) {
        return ScanService.startScan(requestJson);
    }
    
    @AuraEnabled
    public static ScanService.ScanStatusDto getScanStatus(String scanId) {
        return ScanService.getScanStatus(scanId);
    }
    
    @AuraEnabled
    public static void cancelScan(String scanId) {
        ScanService.cancelScan(scanId);
    }
    
    @AuraEnabled(cacheable=true)
    public static List<ScanService.ScanStatusDto> getRecentScans(Integer limitCount) {
        return ScanService.getRecentScans(limitCount);
    }
    
    @AuraEnabled(cacheable=true)
    public static List<AnalysisService.FindingDto> getFindingsByScan(String scanId) {
        return AnalysisService.getFindingsByScan(scanId);
    }
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getFindingsSummary(String scanId) {
        return AnalysisService.getFindingsSummary(scanId);
    }
    
    @AuraEnabled
    public static String createChangePlan(String scanId, String targetApiVersion, 
                                           String incrementPolicy, Boolean validateOnly,
                                           String testPolicy) {
        return DeploymentService.createChangePlan(scanId, targetApiVersion, 
                                                   incrementPolicy, validateOnly, testPolicy);
    }
    
    @AuraEnabled(cacheable=true)
    public static DeploymentService.ChangePlanDto getChangePlan(String planId) {
        return DeploymentService.getChangePlan(planId);
    }
    
    @AuraEnabled(cacheable=true)
    public static List<DeploymentService.ChangeItemDto> getChangeItems(String planId) {
        return DeploymentService.getChangeItems(planId);
    }
    
    @AuraEnabled
    public static String executePlan(String planId) {
        return DeploymentService.executePlan(planId);
    }
    
    @AuraEnabled
    public static String executePlanWithBackup(String planId, Boolean createBackup, List<String> selectedItemIds) {
        return DeploymentService.executePlanWithBackup(planId, createBackup, selectedItemIds);
    }
    
    @AuraEnabled
    public static void resetPlanForRetry(String planId) {
        DeploymentService.resetPlanForRetry(planId);
    }
    
    @AuraEnabled
    public static void setWriteModeEnabled(Boolean enabled) {
        OrgContextService.setWriteModeEnabled(enabled);
    }
    
    // Backup Service Methods
    
    @AuraEnabled
    public static String createBackupForDeployment(String deploymentRunId) {
        return BackupService.createBackupForDeployment(deploymentRunId);
    }
    
    @AuraEnabled(cacheable=true)
    public static BackupService.BackupSummaryDto getBackupSummary(String deploymentRunId) {
        return BackupService.getBackupSummary(deploymentRunId);
    }
    
    @AuraEnabled(cacheable=true)
    public static List<BackupService.BackupItemDto> getBackupItems(String deploymentRunId) {
        return BackupService.getBackupItems(deploymentRunId);
    }
    
    @AuraEnabled
    public static String getBackupContent(String backupItemId) {
        return BackupService.getBackupContent(backupItemId);
    }
    
    @AuraEnabled
    public static String getBackupMetadata(String backupItemId) {
        return BackupService.getBackupMetadata(backupItemId);
    }
    
    @AuraEnabled
    public static void cleanupBackup(String deploymentRunId) {
        BackupService.cleanupBackup(deploymentRunId);
    }
    
    // Restore Service Methods
    
    @AuraEnabled
    public static List<RestoreService.RestoreResultDto> restoreAll(String deploymentRunId) {
        return RestoreService.restoreAll(deploymentRunId);
    }
    
    @AuraEnabled
    public static RestoreService.RestoreResultDto restoreItem(String backupItemId) {
        return RestoreService.restoreItem(backupItemId);
    }
    
    @AuraEnabled
    public static String previewBackupContent(String backupItemId) {
        return RestoreService.previewBackupContent(backupItemId);
    }
    
    @AuraEnabled
    public static RestoreService.DiffResultDto getDiff(String backupItemId) {
        return RestoreService.getDiff(backupItemId);
    }
    
    // Backup Notification Schedule Methods
    
    @AuraEnabled
    public static Map<String, Object> getBackupScheduleStatus() {
        return BackupNotificationSchedulable.getScheduleStatus();
    }
    
    @AuraEnabled
    public static void toggleBackupSchedule(Boolean enable) {
        BackupNotificationSchedulable.toggleSchedule(enable);
    }
    
    // Session Service Methods
    
    @AuraEnabled
    public static SessionService.SessionDto getCurrentSession() {
        return SessionService.getCurrentSession();
    }
    
    @AuraEnabled
    public static SessionService.SessionDto updateSessionScan(String scanId) {
        return SessionService.updateSessionScan(scanId);
    }
    
    @AuraEnabled
    public static SessionService.SessionDto updateSessionPlan(String planId) {
        return SessionService.updateSessionPlan(planId);
    }
    
    @AuraEnabled
    public static SessionService.SessionDto updateSessionDeploymentRun(String deploymentRunId) {
        return SessionService.updateSessionDeploymentRun(deploymentRunId);
    }
    
    @AuraEnabled
    public static void clearSession() {
        SessionService.clearSession();
    }
    
    @AuraEnabled(cacheable=true)
    public static List<SessionService.ScanSummaryDto> getScanHistory() {
        return SessionService.getScanHistory();
    }
    
    @AuraEnabled(cacheable=true)
    public static List<SessionService.PlanSummaryDto> getPlanHistory() {
        return SessionService.getPlanHistory();
    }
    
    @AuraEnabled
    public static Map<String, Object> getDeploymentRunDetails(String runId) {
        if (String.isBlank(runId)) {
            return null;
        }
        
        List<DeploymentRun__c> runs = [
            SELECT Id, Name, Status__c, StartedAt__c, FinishedAt__c, 
                   ResultsJson__c, ValidateOnly__c, ChangePlan__c,
                   ChangePlan__r.Name, ChangePlan__r.Status__c
            FROM DeploymentRun__c
            WHERE Id = :runId
            LIMIT 1
        ];
        
        if (runs.isEmpty()) {
            return null;
        }
        
        DeploymentRun__c run = runs[0];
        
        Map<String, Object> result = new Map<String, Object>{
            'runId' => run.Id,
            'name' => run.Name,
            'status' => run.Status__c,
            'startedAt' => run.StartedAt__c,
            'finishedAt' => run.FinishedAt__c,
            'validateOnly' => run.ValidateOnly__c,
            'planId' => run.ChangePlan__c,
            'planName' => run.ChangePlan__r?.Name,
            'planStatus' => run.ChangePlan__r?.Status__c
        };
        
        if (String.isNotBlank(run.ResultsJson__c)) {
            try {
                Map<String, Object> resultsData = (Map<String, Object>) JSON.deserializeUntyped(run.ResultsJson__c);
                result.put('results', resultsData);
                
                if (resultsData.containsKey('error')) {
                    result.put('errorMessage', resultsData.get('error'));
                }
                if (resultsData.containsKey('stackTrace')) {
                    result.put('errorStackTrace', resultsData.get('stackTrace'));
                }
            } catch (Exception e) {
                result.put('resultsParseError', e.getMessage());
            }
        }
        
        return result;
    }

    @AuraEnabled
    public static Map<String, Object> getDeploymentErrorsForPlan(String planId) {
        if (String.isBlank(planId)) {
            return null;
        }
        
        Map<String, Object> result = new Map<String, Object>();
        
        List<DeploymentRun__c> runs = [
            SELECT Id, Name, Status__c, StartedAt__c, FinishedAt__c, 
                   ResultsJson__c, ValidateOnly__c
            FROM DeploymentRun__c
            WHERE ChangePlan__c = :planId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        
        if (!runs.isEmpty()) {
            DeploymentRun__c run = runs[0];
            result.put('runId', run.Id);
            result.put('runName', run.Name);
            result.put('runStatus', run.Status__c);
            result.put('runStartedAt', run.StartedAt__c);
            result.put('runFinishedAt', run.FinishedAt__c);
            
            if (String.isNotBlank(run.ResultsJson__c)) {
                try {
                    Map<String, Object> resultsData = (Map<String, Object>) JSON.deserializeUntyped(run.ResultsJson__c);
                    if (resultsData.containsKey('error')) {
                        result.put('runError', resultsData.get('error'));
                    }
                    if (resultsData.containsKey('stackTrace')) {
                        result.put('runStackTrace', resultsData.get('stackTrace'));
                    }
                } catch (Exception e) {
                    // Ignore parse errors
                }
            }
        }
        
        List<ChangeItem__c> failedItems = [
            SELECT Id, FullName__c, ArtifactType__c, ErrorDetails__c, ApplyStatus__c
            FROM ChangeItem__c
            WHERE ChangePlan__c = :planId
            AND ApplyStatus__c = 'Failed'
            ORDER BY UnitNumber__c
            LIMIT 50
        ];
        
        List<Map<String, Object>> itemErrors = new List<Map<String, Object>>();
        for (ChangeItem__c item : failedItems) {
            itemErrors.add(new Map<String, Object>{
                'id' => item.Id,
                'fullName' => item.FullName__c,
                'artifactType' => item.ArtifactType__c,
                'errorDetails' => item.ErrorDetails__c,
                'applyStatus' => item.ApplyStatus__c
            });
        }
        result.put('failedItems', itemErrors);
        result.put('failedItemCount', failedItems.size());
        
        return result;
    }

    @AuraEnabled
    public static List<Map<String, Object>> getDeploymentHistory(String planId) {
        List<Map<String, Object>> historyItems = new List<Map<String, Object>>();
        
        if (String.isBlank(planId)) {
            return historyItems;
        }
        
        List<ChangeItem__c> items = [
            SELECT Id, FullName__c, ArtifactType__c, CurrentApiVersion__c, 
                   TargetApiVersion__c, ApplyStatus__c, ErrorDetails__c,
                   LastModifiedDate
            FROM ChangeItem__c
            WHERE ChangePlan__c = :planId
            AND ApplyStatus__c = 'Applied'
            ORDER BY LastModifiedDate DESC
            LIMIT 200
        ];
        
        for (ChangeItem__c item : items) {
            historyItems.add(new Map<String, Object>{
                'id' => item.Id,
                'fullName' => item.FullName__c,
                'artifactType' => item.ArtifactType__c,
                'fromVersion' => item.CurrentApiVersion__c,
                'toVersion' => item.TargetApiVersion__c,
                'status' => item.ApplyStatus__c,
                'deployedAt' => item.LastModifiedDate
            });
        }
        
        return historyItems;
    }
}
