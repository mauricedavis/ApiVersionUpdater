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
    
    @AuraEnabled(cacheable=true)
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
}
