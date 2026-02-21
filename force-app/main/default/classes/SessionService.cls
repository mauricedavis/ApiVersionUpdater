public with sharing class SessionService {
    
    public class SessionDto {
        @AuraEnabled public String sessionId;
        @AuraEnabled public String currentScanId;
        @AuraEnabled public String currentScanName;
        @AuraEnabled public String currentScanStatus;
        @AuraEnabled public Datetime currentScanStartedAt;
        @AuraEnabled public String currentChangePlanId;
        @AuraEnabled public String currentChangePlanName;
        @AuraEnabled public String currentChangePlanStatus;
        @AuraEnabled public Integer currentChangePlanItemCount;
        @AuraEnabled public String currentChangePlanSourceScanName;
        @AuraEnabled public String currentDeploymentRunId;
        @AuraEnabled public String currentDeploymentRunStatus;
        @AuraEnabled public Datetime currentDeploymentRunFinishedAt;
        @AuraEnabled public Integer currentDeploymentSuccessCount;
        @AuraEnabled public Integer currentDeploymentFailCount;
        @AuraEnabled public Integer currentDeploymentTotalProcessed;
        @AuraEnabled public Datetime lastAccessedAt;
        @AuraEnabled public Integer workflowStep;
        @AuraEnabled public String workflowStepLabel;
    }
    
    public class ScanSummaryDto {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String displayName;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime startedAt;
        @AuraEnabled public Datetime finishedAt;
        @AuraEnabled public Integer findingsCount;
        @AuraEnabled public String targetApiVersion;
    }
    
    public class PlanSummaryDto {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String displayName;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime createdAt;
        @AuraEnabled public Integer itemCount;
        @AuraEnabled public String targetApiVersion;
        @AuraEnabled public String scanId;
    }
    
    @AuraEnabled
    public static SessionDto getCurrentSession() {
        String userId = UserInfo.getUserId();
        
        List<UserSession__c> sessions = [
            SELECT Id, CurrentScan__c, CurrentScan__r.Name, CurrentScan__r.Name__c, 
                   CurrentScan__r.Status__c, CurrentScan__r.StartedAt__c, 
                   CurrentChangePlan__c, CurrentChangePlan__r.Name, CurrentChangePlan__r.Name__c, 
                   CurrentChangePlan__r.Status__c,
                   CurrentChangePlan__r.CreatedFromScan__c, 
                   CurrentChangePlan__r.CreatedFromScan__r.Name, 
                   CurrentChangePlan__r.CreatedFromScan__r.Name__c,
                   CurrentDeploymentRun__c, CurrentDeploymentRun__r.Status__c,
                   CurrentDeploymentRun__r.FinishedAt__c, CurrentDeploymentRun__r.ResultsJson__c,
                   LastAccessedAt__c
            FROM UserSession__c
            WHERE User__c = :userId
            ORDER BY LastAccessedAt__c DESC
            LIMIT 1
        ];
        
        SessionDto dto = new SessionDto();
        
        if (!sessions.isEmpty()) {
            UserSession__c session = sessions[0];
            dto.sessionId = session.Id;
            dto.currentScanId = session.CurrentScan__c;
            dto.currentScanName = String.isNotBlank(session.CurrentScan__r?.Name__c) 
                ? session.CurrentScan__r.Name__c 
                : session.CurrentScan__r?.Name;
            dto.currentScanStatus = session.CurrentScan__r?.Status__c;
            dto.currentScanStartedAt = session.CurrentScan__r?.StartedAt__c;
            dto.currentChangePlanId = session.CurrentChangePlan__c;
            dto.currentChangePlanName = String.isNotBlank(session.CurrentChangePlan__r?.Name__c) 
                ? session.CurrentChangePlan__r.Name__c 
                : session.CurrentChangePlan__r?.Name;
            dto.currentChangePlanStatus = session.CurrentChangePlan__r?.Status__c;
            
            if (session.CurrentChangePlan__r?.CreatedFromScan__c != null) {
                dto.currentChangePlanSourceScanName = String.isNotBlank(session.CurrentChangePlan__r.CreatedFromScan__r?.Name__c)
                    ? session.CurrentChangePlan__r.CreatedFromScan__r.Name__c
                    : session.CurrentChangePlan__r.CreatedFromScan__r?.Name;
            }
            
            if (session.CurrentChangePlan__c != null) {
                dto.currentChangePlanItemCount = [
                    SELECT COUNT() FROM ChangeItem__c WHERE ChangePlan__c = :session.CurrentChangePlan__c
                ];
            }
            
            dto.currentDeploymentRunId = session.CurrentDeploymentRun__c;
            dto.currentDeploymentRunStatus = session.CurrentDeploymentRun__r?.Status__c;
            dto.currentDeploymentRunFinishedAt = session.CurrentDeploymentRun__r?.FinishedAt__c;
            
            if (String.isNotBlank(session.CurrentDeploymentRun__r?.ResultsJson__c)) {
                try {
                    Map<String, Object> results = (Map<String, Object>) JSON.deserializeUntyped(
                        session.CurrentDeploymentRun__r.ResultsJson__c
                    );
                    if (results.containsKey('successCount')) {
                        dto.currentDeploymentSuccessCount = (Integer) results.get('successCount');
                    }
                    if (results.containsKey('failCount')) {
                        dto.currentDeploymentFailCount = (Integer) results.get('failCount');
                    }
                    if (results.containsKey('totalProcessed')) {
                        dto.currentDeploymentTotalProcessed = (Integer) results.get('totalProcessed');
                    }
                } catch (Exception e) {
                    // Ignore JSON parse errors
                }
            }
            
            dto.lastAccessedAt = session.LastAccessedAt__c;
            
            session.LastAccessedAt__c = Datetime.now();
            update session;
        }
        
        dto.workflowStep = calculateWorkflowStep(dto);
        dto.workflowStepLabel = getWorkflowStepLabel(dto.workflowStep);
        
        return dto;
    }
    
    @AuraEnabled
    public static SessionDto updateSessionScan(String scanId) {
        UserSession__c session = getOrCreateSession();
        session.CurrentScan__c = scanId;
        session.CurrentChangePlan__c = null;
        session.CurrentDeploymentRun__c = null;
        session.LastAccessedAt__c = Datetime.now();
        update session;
        return getCurrentSession();
    }
    
    @AuraEnabled
    public static SessionDto updateSessionPlan(String planId) {
        UserSession__c session = getOrCreateSession();
        session.CurrentChangePlan__c = planId;
        session.CurrentDeploymentRun__c = null;
        session.LastAccessedAt__c = Datetime.now();
        update session;
        return getCurrentSession();
    }
    
    @AuraEnabled
    public static SessionDto updateSessionDeploymentRun(String deploymentRunId) {
        UserSession__c session = getOrCreateSession();
        session.CurrentDeploymentRun__c = deploymentRunId;
        session.LastAccessedAt__c = Datetime.now();
        update session;
        return getCurrentSession();
    }
    
    @AuraEnabled
    public static void clearSession() {
        String userId = UserInfo.getUserId();
        List<UserSession__c> sessions = [
            SELECT Id FROM UserSession__c WHERE User__c = :userId
        ];
        if (!sessions.isEmpty()) {
            delete sessions;
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<ScanSummaryDto> getScanHistory() {
        List<ScanSummaryDto> scans = new List<ScanSummaryDto>();
        
        for (Scan__c scan : [
            SELECT Id, Name, Name__c, Status__c, StartedAt__c, FinishedAt__c, 
                   TargetApiVersion__c
            FROM Scan__c
            ORDER BY StartedAt__c DESC
            LIMIT 20
        ]) {
            ScanSummaryDto dto = new ScanSummaryDto();
            dto.id = scan.Id;
            dto.name = scan.Name__c;
            dto.displayName = buildDisplayName(scan.Name__c, scan.Name, scan.StartedAt__c);
            dto.status = scan.Status__c;
            dto.startedAt = scan.StartedAt__c;
            dto.finishedAt = scan.FinishedAt__c;
            dto.findingsCount = 0;
            dto.targetApiVersion = scan.TargetApiVersion__c;
            scans.add(dto);
        }
        
        return scans;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<PlanSummaryDto> getPlanHistory() {
        List<PlanSummaryDto> plans = new List<PlanSummaryDto>();
        
        for (ChangePlan__c plan : [
            SELECT Id, Name, Name__c, Status__c, CreatedDate, TargetApiVersion__c,
                   CreatedFromScan__c,
                   (SELECT Id FROM ChangeItems__r)
            FROM ChangePlan__c
            ORDER BY CreatedDate DESC
            LIMIT 20
        ]) {
            PlanSummaryDto dto = new PlanSummaryDto();
            dto.id = plan.Id;
            dto.name = plan.Name__c;
            dto.displayName = buildDisplayName(plan.Name__c, plan.Name, plan.CreatedDate);
            dto.status = plan.Status__c;
            dto.createdAt = plan.CreatedDate;
            dto.itemCount = plan.ChangeItems__r != null ? plan.ChangeItems__r.size() : 0;
            dto.targetApiVersion = plan.TargetApiVersion__c;
            dto.scanId = plan.CreatedFromScan__c;
            plans.add(dto);
        }
        
        return plans;
    }
    
    private static UserSession__c getOrCreateSession() {
        String userId = UserInfo.getUserId();
        
        List<UserSession__c> sessions = [
            SELECT Id, CurrentScan__c, CurrentChangePlan__c, CurrentDeploymentRun__c
            FROM UserSession__c
            WHERE User__c = :userId
            LIMIT 1
        ];
        
        if (!sessions.isEmpty()) {
            return sessions[0];
        }
        
        UserSession__c newSession = new UserSession__c(
            User__c = userId,
            LastAccessedAt__c = Datetime.now()
        );
        insert newSession;
        return newSession;
    }
    
    private static String buildDisplayName(String customName, String recordName, Datetime timestamp) {
        String timePart = timestamp != null ? timestamp.format('MMM d, yyyy h:mm a') : '';
        
        if (String.isNotBlank(customName)) {
            return customName + ' (' + timePart + ')';
        }
        return recordName + ' - ' + timePart;
    }
    
    private static Integer calculateWorkflowStep(SessionDto dto) {
        if (dto.currentDeploymentRunId != null) {
            if (dto.currentDeploymentRunStatus == 'Completed') {
                return 5;
            }
            return 4;
        }
        if (dto.currentChangePlanId != null) {
            return 3;
        }
        if (dto.currentScanId != null) {
            if (dto.currentScanStatus == 'Completed') {
                return 2;
            }
            return 1;
        }
        return 0;
    }
    
    private static String getWorkflowStepLabel(Integer step) {
        Map<Integer, String> labels = new Map<Integer, String>{
            0 => 'Not Started',
            1 => 'Scanning',
            2 => 'Review Findings',
            3 => 'Plan Created',
            4 => 'Deploying',
            5 => 'Completed'
        };
        return labels.get(step);
    }
}
