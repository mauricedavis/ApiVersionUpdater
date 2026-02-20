public with sharing class DeploymentService {
    
    public class ChangePlanDto {
        @AuraEnabled public String id;
        @AuraEnabled public String status;
        @AuraEnabled public String scanId;
        @AuraEnabled public String targetApiVersion;
        @AuraEnabled public String incrementPolicy;
        @AuraEnabled public Boolean validateOnly;
        @AuraEnabled public String testPolicy;
        @AuraEnabled public Integer totalItems;
        @AuraEnabled public Integer eligibleItems;
        @AuraEnabled public Integer blockedItems;
    }
    
    public class ChangeItemDto {
        @AuraEnabled public String id;
        @AuraEnabled public String changePlanId;
        @AuraEnabled public String artifactType;
        @AuraEnabled public String fullName;
        @AuraEnabled public Decimal currentApiVersion;
        @AuraEnabled public Decimal targetApiVersion;
        @AuraEnabled public String eligibility;
        @AuraEnabled public String blockReason;
        @AuraEnabled public Integer unitNumber;
        @AuraEnabled public String applyStatus;
        @AuraEnabled public String errorDetails;
    }
    
    @AuraEnabled
    public static String createChangePlan(String scanId, String targetApiVersion, 
                                           String incrementPolicy, Boolean validateOnly,
                                           String testPolicy) {
        List<ArtifactSnapshot__c> snapshots = [
            SELECT Id, ArtifactType__c, FullName__c, ApiVersion__c
            FROM ArtifactSnapshot__c
            WHERE Scan__c = :scanId
        ];
        
        if (snapshots.isEmpty()) {
            throw new AuraHandledException('No artifacts found in scan');
        }
        
        Decimal targetVersion = Decimal.valueOf(targetApiVersion);
        
        ChangePlan__c plan = new ChangePlan__c(
            Status__c = 'Draft',
            CreatedFromScan__c = scanId,
            TargetApiVersion__c = targetApiVersion,
            IncrementPolicy__c = incrementPolicy,
            ValidationMode__c = validateOnly ? 'ValidateOnly' : 'Deploy',
            TestPolicy__c = testPolicy
        );
        insert plan;
        
        List<ChangeItem__c> items = new List<ChangeItem__c>();
        Integer unitNumber = 1;
        
        for (ArtifactSnapshot__c snap : snapshots) {
            if (snap.ApiVersion__c >= targetVersion) {
                continue;
            }
            
            ChangeItem__c item = new ChangeItem__c(
                ChangePlan__c = plan.Id,
                ArtifactType__c = snap.ArtifactType__c,
                FullName__c = snap.FullName__c,
                CurrentApiVersion__c = snap.ApiVersion__c,
                TargetApiVersion__c = targetVersion,
                Eligibility__c = 'Eligible',
                UnitNumber__c = unitNumber++,
                ApplyStatus__c = 'Pending'
            );
            
            Decimal delta = targetVersion - snap.ApiVersion__c;
            if (incrementPolicy == 'IncrementalOnly' && delta > 6) {
                item.Eligibility__c = 'Blocked';
                item.BlockReason__c = 'Version jump exceeds incremental policy limit (max 6)';
            }
            
            Integer blockingFindings = [
                SELECT COUNT() 
                FROM Finding__c 
                WHERE ArtifactSnapshot__c = :snap.Id 
                AND IsBlocking__c = true
            ];
            
            if (blockingFindings > 0) {
                item.Eligibility__c = 'Blocked';
                item.BlockReason__c = 'Has ' + blockingFindings + ' blocking finding(s)';
            }
            
            items.add(item);
        }
        
        if (!items.isEmpty()) {
            insert items;
        }
        
        updatePlanSummary(plan.Id);
        
        logAuditEvent('ChangePlanCreated', new Map<String, Object>{
            'planId' => plan.Id,
            'scanId' => scanId,
            'targetVersion' => targetApiVersion,
            'itemCount' => items.size()
        });
        
        return plan.Id;
    }
    
    @AuraEnabled(cacheable=true)
    public static ChangePlanDto getChangePlan(String planId) {
        ChangePlan__c plan = [
            SELECT Id, Status__c, CreatedFromScan__c, TargetApiVersion__c,
                   IncrementPolicy__c, ValidationMode__c, TestPolicy__c, SummaryJson__c
            FROM ChangePlan__c 
            WHERE Id = :planId
        ];
        
        ChangePlanDto dto = new ChangePlanDto();
        dto.id = plan.Id;
        dto.status = plan.Status__c;
        dto.scanId = plan.CreatedFromScan__c;
        dto.targetApiVersion = plan.TargetApiVersion__c;
        dto.incrementPolicy = plan.IncrementPolicy__c;
        dto.validateOnly = plan.ValidationMode__c == 'ValidateOnly';
        dto.testPolicy = plan.TestPolicy__c;
        
        dto.totalItems = [SELECT COUNT() FROM ChangeItem__c WHERE ChangePlan__c = :planId];
        dto.eligibleItems = [
            SELECT COUNT() FROM ChangeItem__c 
            WHERE ChangePlan__c = :planId AND Eligibility__c = 'Eligible'
        ];
        dto.blockedItems = [
            SELECT COUNT() FROM ChangeItem__c 
            WHERE ChangePlan__c = :planId AND Eligibility__c = 'Blocked'
        ];
        
        return dto;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<ChangeItemDto> getChangeItems(String planId) {
        List<ChangeItemDto> dtos = new List<ChangeItemDto>();
        
        for (ChangeItem__c item : [
            SELECT Id, ChangePlan__c, ArtifactType__c, FullName__c,
                   CurrentApiVersion__c, TargetApiVersion__c, Eligibility__c,
                   BlockReason__c, UnitNumber__c, ApplyStatus__c, ErrorDetails__c
            FROM ChangeItem__c
            WHERE ChangePlan__c = :planId
            ORDER BY UnitNumber__c
        ]) {
            ChangeItemDto dto = new ChangeItemDto();
            dto.id = item.Id;
            dto.changePlanId = item.ChangePlan__c;
            dto.artifactType = item.ArtifactType__c;
            dto.fullName = item.FullName__c;
            dto.currentApiVersion = item.CurrentApiVersion__c;
            dto.targetApiVersion = item.TargetApiVersion__c;
            dto.eligibility = item.Eligibility__c;
            dto.blockReason = item.BlockReason__c;
            dto.unitNumber = Integer.valueOf(item.UnitNumber__c);
            dto.applyStatus = item.ApplyStatus__c;
            dto.errorDetails = item.ErrorDetails__c;
            dtos.add(dto);
        }
        
        return dtos;
    }
    
    @AuraEnabled
    public static String executePlan(String planId) {
        ChangePlan__c plan = [
            SELECT Id, Status__c, ValidationMode__c, TestPolicy__c, TargetApiVersion__c
            FROM ChangePlan__c 
            WHERE Id = :planId
        ];
        
        if (plan.Status__c != 'Draft' && plan.Status__c != 'Ready') {
            throw new AuraHandledException('Plan cannot be executed in status: ' + plan.Status__c);
        }
        
        Boolean validateOnly = plan.ValidationMode__c == 'ValidateOnly';
        
        DeploymentRun__c run = new DeploymentRun__c(
            ChangePlan__c = planId,
            Status__c = 'Queued',
            StartedAt__c = Datetime.now(),
            ValidateOnly__c = validateOnly,
            TestPolicy__c = plan.TestPolicy__c
        );
        insert run;
        
        plan.Status__c = 'Executing';
        update plan;
        
        logAuditEvent('DeploymentStarted', new Map<String, Object>{
            'planId' => planId,
            'runId' => run.Id,
            'validateOnly' => validateOnly
        });
        
        System.enqueueJob(new DeploymentQueueable(run.Id, planId));
        
        return run.Id;
    }
    
    private static void updatePlanSummary(String planId) {
        Map<String, Integer> summary = new Map<String, Integer>();
        
        List<AggregateResult> results = [
            SELECT Eligibility__c elig, COUNT(Id) cnt
            FROM ChangeItem__c
            WHERE ChangePlan__c = :planId
            GROUP BY Eligibility__c
        ];
        
        for (AggregateResult ar : results) {
            String eligibility = (String) ar.get('elig');
            Integer count = (Integer) ar.get('cnt');
            summary.put(eligibility, count);
        }
        
        ChangePlan__c plan = new ChangePlan__c(
            Id = planId,
            SummaryJson__c = JSON.serialize(summary)
        );
        update plan;
    }
    
    private static void logAuditEvent(String eventType, Map<String, Object> details) {
        AuditEvent__c event = new AuditEvent__c(
            EventType__c = eventType,
            Actor__c = UserInfo.getUserId(),
            Timestamp__c = Datetime.now(),
            DetailsJson__c = JSON.serialize(details)
        );
        insert event;
    }
    
    public class DeploymentQueueable implements Queueable, Database.AllowsCallouts {
        private String runId;
        private String planId;
        
        public DeploymentQueueable(String runId, String planId) {
            this.runId = runId;
            this.planId = planId;
        }
        
        public void execute(QueueableContext context) {
            try {
                processDeployment();
            } catch (Exception e) {
                DeploymentRun__c run = new DeploymentRun__c(
                    Id = runId,
                    Status__c = 'Failed',
                    FinishedAt__c = Datetime.now(),
                    ResultsJson__c = JSON.serialize(new Map<String, Object>{
                        'error' => e.getMessage(),
                        'stackTrace' => e.getStackTraceString()
                    })
                );
                update run;
                
                ChangePlan__c plan = new ChangePlan__c(
                    Id = planId,
                    Status__c = 'Failed'
                );
                update plan;
            }
        }
        
        private void processDeployment() {
            DeploymentRun__c run = new DeploymentRun__c(
                Id = runId,
                Status__c = 'Running'
            );
            update run;
            
            List<ChangeItem__c> eligibleItems = [
                SELECT Id, ArtifactType__c, FullName__c, CurrentApiVersion__c, 
                       TargetApiVersion__c, ApplyStatus__c
                FROM ChangeItem__c
                WHERE ChangePlan__c = :planId
                AND Eligibility__c = 'Eligible'
                ORDER BY UnitNumber__c
            ];
            
            Integer successCount = 0;
            Integer failCount = 0;
            
            for (ChangeItem__c item : eligibleItems) {
                try {
                    item.ApplyStatus__c = 'Applied';
                    successCount++;
                } catch (Exception e) {
                    item.ApplyStatus__c = 'Failed';
                    item.ErrorDetails__c = e.getMessage();
                    failCount++;
                }
            }
            
            update eligibleItems;
            
            run.Status__c = failCount == 0 ? 'Succeeded' : 'PartialSuccess';
            run.FinishedAt__c = Datetime.now();
            run.ResultsJson__c = JSON.serialize(new Map<String, Object>{
                'successCount' => successCount,
                'failCount' => failCount,
                'totalProcessed' => eligibleItems.size()
            });
            update run;
            
            ChangePlan__c plan = new ChangePlan__c(
                Id = planId,
                Status__c = failCount == 0 ? 'Completed' : 'PartiallyCompleted'
            );
            update plan;
        }
    }
}
