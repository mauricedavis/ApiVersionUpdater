public with sharing class BackupService {
    
    private static final Integer BACKUP_RETENTION_DAYS = 90;
    
    public class BackupItemDto {
        @AuraEnabled public String id;
        @AuraEnabled public String deploymentRunId;
        @AuraEnabled public String changeItemId;
        @AuraEnabled public String artifactType;
        @AuraEnabled public String fullName;
        @AuraEnabled public Decimal originalApiVersion;
        @AuraEnabled public String contentDocumentId;
        @AuraEnabled public String metadataDocumentId;
        @AuraEnabled public String restoreStatus;
        @AuraEnabled public Datetime backupCreatedAt;
        @AuraEnabled public Datetime restoredAt;
        @AuraEnabled public String contentHash;
        @AuraEnabled public List<String> relatedTestClasses;
    }
    
    public class BackupSummaryDto {
        @AuraEnabled public String deploymentRunId;
        @AuraEnabled public Integer totalItems;
        @AuraEnabled public Datetime backupCreatedAt;
        @AuraEnabled public Date expirationDate;
        @AuraEnabled public Boolean notificationSent;
        @AuraEnabled public Integer restoredCount;
        @AuraEnabled public Integer pendingCount;
    }
    
    @AuraEnabled
    public static String createBackupForDeployment(String deploymentRunId) {
        DeploymentRun__c run = [
            SELECT Id, ChangePlan__c, BackupCreatedAt__c
            FROM DeploymentRun__c 
            WHERE Id = :deploymentRunId
        ];
        
        if (run.BackupCreatedAt__c != null) {
            throw new AuraHandledException('Backup already exists for this deployment');
        }
        
        List<ChangeItem__c> changeItems = [
            SELECT Id, ArtifactType__c, FullName__c, CurrentApiVersion__c, Eligibility__c
            FROM ChangeItem__c
            WHERE ChangePlan__c = :run.ChangePlan__c
            AND Eligibility__c = 'Eligible'
        ];
        
        if (changeItems.isEmpty()) {
            throw new AuraHandledException('No eligible items to backup');
        }
        
        return createBackupForItems(deploymentRunId, changeItems);
    }
    
    @AuraEnabled
    public static String createBackupForSelectedItems(String deploymentRunId, List<String> selectedItemIds) {
        DeploymentRun__c run = [
            SELECT Id, ChangePlan__c, BackupCreatedAt__c
            FROM DeploymentRun__c 
            WHERE Id = :deploymentRunId
        ];
        
        if (run.BackupCreatedAt__c != null) {
            throw new AuraHandledException('Backup already exists for this deployment');
        }
        
        if (selectedItemIds == null || selectedItemIds.isEmpty()) {
            throw new AuraHandledException('No items selected for backup');
        }
        
        List<ChangeItem__c> changeItems = [
            SELECT Id, ArtifactType__c, FullName__c, CurrentApiVersion__c, Eligibility__c
            FROM ChangeItem__c
            WHERE Id IN :selectedItemIds
        ];
        
        if (changeItems.isEmpty()) {
            throw new AuraHandledException('No items found for backup');
        }
        
        return createBackupForItems(deploymentRunId, changeItems);
    }
    
    private static String createBackupForItems(String deploymentRunId, List<ChangeItem__c> changeItems) {
        List<BackupItem__c> backupItems = new List<BackupItem__c>();
        
        for (ChangeItem__c item : changeItems) {
            BackupItem__c backupItem = new BackupItem__c(
                DeploymentRun__c = deploymentRunId,
                ArtifactType__c = item.ArtifactType__c,
                FullName__c = item.FullName__c
            );
            backupItems.add(backupItem);
        }
        
        insert backupItems;
        
        createBackupFiles(backupItems);
        
        DeploymentRun__c run = new DeploymentRun__c(Id = deploymentRunId);
        run.BackupCreatedAt__c = Datetime.now();
        run.BackupExpirationDate__c = Date.today().addDays(BACKUP_RETENTION_DAYS);
        run.BackupOwner__c = UserInfo.getUserId();
        run.BackupItemCount__c = backupItems.size();
        update run;
        
        logAuditEvent('BackupCreated', new Map<String, Object>{
            'deploymentRunId' => deploymentRunId,
            'itemCount' => backupItems.size()
        });
        
        return deploymentRunId;
    }
    
    private static void createBackupFiles(List<BackupItem__c> backupItems) {
        List<ContentVersion> contentVersions = new List<ContentVersion>();
        
        for (BackupItem__c item : backupItems) {
            ContentResult result = fetchAndCreateContentVersion(item);
            if (result.contentVersion != null) {
                contentVersions.add(result.contentVersion);
            }
            if (result.metadataVersion != null) {
                contentVersions.add(result.metadataVersion);
            }
        }
        
        if (!contentVersions.isEmpty()) {
            insert contentVersions;
        }
    }
    
    private class ContentResult {
        ContentVersion contentVersion;
        ContentVersion metadataVersion;
        String contentHash;
        String relatedTestClassesJson;
    }
    
    private static ContentResult fetchAndCreateContentVersion(BackupItem__c item) {
        ContentResult result = new ContentResult();
        String content = '';
        String metadataXml = '';
        List<String> relatedTestClasses = new List<String>();
        
        switch on item.ArtifactType__c {
            when 'ApexClass' {
                ApexClass cls = [
                    SELECT Id, Name, Body, ApiVersion, Status
                    FROM ApexClass 
                    WHERE Name = :item.FullName__c
                    LIMIT 1
                ];
                content = cls.Body;
                metadataXml = generateApexClassMetadata(cls);
                relatedTestClasses = findRelatedTestClasses(cls.Name);
            }
            when 'ApexTrigger' {
                ApexTrigger trg = [
                    SELECT Id, Name, Body, ApiVersion, Status
                    FROM ApexTrigger 
                    WHERE Name = :item.FullName__c
                    LIMIT 1
                ];
                content = trg.Body;
                metadataXml = generateApexTriggerMetadata(trg);
            }
            when 'ApexPage' {
                ApexPage pg = [
                    SELECT Id, Name, Markup, ApiVersion
                    FROM ApexPage 
                    WHERE Name = :item.FullName__c
                    LIMIT 1
                ];
                content = pg.Markup;
                metadataXml = generateApexPageMetadata(pg);
            }
            when 'ApexComponent' {
                ApexComponent cmp = [
                    SELECT Id, Name, Markup, ApiVersion
                    FROM ApexComponent 
                    WHERE Name = :item.FullName__c
                    LIMIT 1
                ];
                content = cmp.Markup;
                metadataXml = generateApexComponentMetadata(cmp);
            }
        }
        
        if (String.isNotBlank(content)) {
            result.contentVersion = new ContentVersion(
                Title = item.FullName__c + '_body',
                PathOnClient = item.FullName__c + getFileExtension(item.ArtifactType__c),
                VersionData = Blob.valueOf(content),
                Description = 'Backup of ' + item.ArtifactType__c + ': ' + item.FullName__c
            );
            result.contentHash = ContentService.computeHash(content);
        }
        
        if (String.isNotBlank(metadataXml)) {
            result.metadataVersion = new ContentVersion(
                Title = item.FullName__c + '_meta',
                PathOnClient = item.FullName__c + '-meta.xml',
                VersionData = Blob.valueOf(metadataXml),
                Description = 'Metadata backup of ' + item.ArtifactType__c + ': ' + item.FullName__c
            );
        }
        
        result.relatedTestClassesJson = JSON.serialize(relatedTestClasses);
        
        return result;
    }
    
    private static String getFileExtension(String artifactType) {
        Map<String, String> extensions = new Map<String, String>{
            'ApexClass' => '.cls',
            'ApexTrigger' => '.trigger',
            'ApexPage' => '.page',
            'ApexComponent' => '.component'
        };
        return extensions.get(artifactType);
    }
    
    private static String generateApexClassMetadata(ApexClass cls) {
        return '<?xml version="1.0" encoding="UTF-8"?>\n' +
               '<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">\n' +
               '    <apiVersion>' + cls.ApiVersion + '</apiVersion>\n' +
               '    <status>' + cls.Status + '</status>\n' +
               '</ApexClass>';
    }
    
    private static String generateApexTriggerMetadata(ApexTrigger trg) {
        return '<?xml version="1.0" encoding="UTF-8"?>\n' +
               '<ApexTrigger xmlns="http://soap.sforce.com/2006/04/metadata">\n' +
               '    <apiVersion>' + trg.ApiVersion + '</apiVersion>\n' +
               '    <status>' + trg.Status + '</status>\n' +
               '</ApexTrigger>';
    }
    
    private static String generateApexPageMetadata(ApexPage pg) {
        return '<?xml version="1.0" encoding="UTF-8"?>\n' +
               '<ApexPage xmlns="http://soap.sforce.com/2006/04/metadata">\n' +
               '    <apiVersion>' + pg.ApiVersion + '</apiVersion>\n' +
               '    <availableInTouch>false</availableInTouch>\n' +
               '    <confirmationTokenRequired>false</confirmationTokenRequired>\n' +
               '</ApexPage>';
    }
    
    private static String generateApexComponentMetadata(ApexComponent cmp) {
        return '<?xml version="1.0" encoding="UTF-8"?>\n' +
               '<ApexComponent xmlns="http://soap.sforce.com/2006/04/metadata">\n' +
               '    <apiVersion>' + cmp.ApiVersion + '</apiVersion>\n' +
               '</ApexComponent>';
    }
    
    private static List<String> findRelatedTestClasses(String className) {
        List<String> testClasses = new List<String>();
        
        String searchPattern = '%' + className + '%';
        List<ApexClass> potentialTests = [
            SELECT Name, Body
            FROM ApexClass
            WHERE Name LIKE :searchPattern
            AND (Name LIKE '%Test%' OR Name LIKE '%_Test')
            LIMIT 10
        ];
        
        for (ApexClass testCls : potentialTests) {
            if (testCls.Body != null && testCls.Body.containsIgnoreCase('@isTest')) {
                testClasses.add(testCls.Name);
            }
        }
        
        return testClasses;
    }
    
    @AuraEnabled(cacheable=true)
    public static BackupSummaryDto getBackupSummary(String deploymentRunId) {
        DeploymentRun__c run = [
            SELECT Id, BackupCreatedAt__c, BackupExpirationDate__c, 
                   BackupNotificationSent__c, BackupItemCount__c
            FROM DeploymentRun__c 
            WHERE Id = :deploymentRunId
        ];
        
        BackupSummaryDto summary = new BackupSummaryDto();
        summary.deploymentRunId = run.Id;
        summary.backupCreatedAt = run.BackupCreatedAt__c;
        summary.expirationDate = run.BackupExpirationDate__c;
        summary.notificationSent = run.BackupNotificationSent__c;
        summary.totalItems = Integer.valueOf(run.BackupItemCount__c);
        
        Integer itemCount = [SELECT COUNT() FROM BackupItem__c WHERE DeploymentRun__c = :deploymentRunId];
        
        summary.restoredCount = 0;
        summary.pendingCount = itemCount;
        
        return summary;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<BackupItemDto> getBackupItems(String deploymentRunId) {
        List<BackupItemDto> items = new List<BackupItemDto>();
        
        for (BackupItem__c item : [
            SELECT Id, DeploymentRun__c, ArtifactType__c, FullName__c
            FROM BackupItem__c
            WHERE DeploymentRun__c = :deploymentRunId
            ORDER BY FullName__c
        ]) {
            BackupItemDto dto = new BackupItemDto();
            dto.id = item.Id;
            dto.deploymentRunId = item.DeploymentRun__c;
            dto.artifactType = item.ArtifactType__c;
            dto.fullName = item.FullName__c;
            dto.restoreStatus = 'NotRestored';
            
            items.add(dto);
        }
        
        return items;
    }
    
    @AuraEnabled
    public static BackupSummaryDto getBackupSummaryByPlan(String planId) {
        List<DeploymentRun__c> runs = [
            SELECT Id, BackupCreatedAt__c, BackupExpirationDate__c, 
                   BackupNotificationSent__c, BackupItemCount__c
            FROM DeploymentRun__c 
            WHERE ChangePlan__c = :planId
            AND BackupItemCount__c > 0
            ORDER BY CreatedDate DESC
        ];
        
        if (runs.isEmpty()) {
            return null;
        }
        
        BackupSummaryDto summary = new BackupSummaryDto();
        summary.deploymentRunId = runs[0].Id;
        summary.backupCreatedAt = runs[0].BackupCreatedAt__c;
        summary.expirationDate = runs[0].BackupExpirationDate__c;
        summary.notificationSent = runs[0].BackupNotificationSent__c;
        
        Set<Id> runIds = new Set<Id>();
        for (DeploymentRun__c run : runs) {
            runIds.add(run.Id);
        }
        
        Integer totalCount = [SELECT COUNT() FROM BackupItem__c WHERE DeploymentRun__c IN :runIds];
        
        summary.totalItems = totalCount;
        summary.restoredCount = 0;
        summary.pendingCount = totalCount;
        
        return summary;
    }
    
    @AuraEnabled
    public static List<BackupItemDto> getBackupItemsByPlan(String planId) {
        List<BackupItemDto> items = new List<BackupItemDto>();
        
        Set<Id> runIds = new Set<Id>();
        for (DeploymentRun__c run : [
            SELECT Id FROM DeploymentRun__c 
            WHERE ChangePlan__c = :planId
            AND BackupItemCount__c > 0
        ]) {
            runIds.add(run.Id);
        }
        
        if (runIds.isEmpty()) {
            return items;
        }
        
        for (BackupItem__c item : [
            SELECT Id, DeploymentRun__c, ArtifactType__c, FullName__c
            FROM BackupItem__c
            WHERE DeploymentRun__c IN :runIds
            ORDER BY FullName__c
        ]) {
            BackupItemDto dto = new BackupItemDto();
            dto.id = item.Id;
            dto.deploymentRunId = item.DeploymentRun__c;
            dto.artifactType = item.ArtifactType__c;
            dto.fullName = item.FullName__c;
            dto.restoreStatus = 'NotRestored';
            
            items.add(dto);
        }
        
        return items;
    }
    
    @AuraEnabled
    public static String getBackupContent(String backupItemId) {
        BackupItem__c item = [
            SELECT FullName__c
            FROM BackupItem__c
            WHERE Id = :backupItemId
        ];
        
        String titlePattern = item.FullName__c + '_body';
        
        List<ContentVersion> cvs = [
            SELECT VersionData
            FROM ContentVersion
            WHERE Title = :titlePattern
            AND IsLatest = true
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        
        if (cvs.isEmpty()) {
            return '';
        }
        
        return cvs[0].VersionData.toString();
    }
    
    @AuraEnabled
    public static String getBackupMetadata(String backupItemId) {
        BackupItem__c item = [
            SELECT FullName__c
            FROM BackupItem__c
            WHERE Id = :backupItemId
        ];
        
        String titlePattern = item.FullName__c + '_meta';
        
        List<ContentVersion> cvs = [
            SELECT VersionData
            FROM ContentVersion
            WHERE Title = :titlePattern
            AND IsLatest = true
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        
        if (cvs.isEmpty()) {
            return '';
        }
        
        return cvs[0].VersionData.toString();
    }
    
    @AuraEnabled
    public static void cleanupBackup(String deploymentRunId) {
        List<BackupItem__c> items = [
            SELECT Id, FullName__c
            FROM BackupItem__c
            WHERE DeploymentRun__c = :deploymentRunId
        ];
        
        Set<String> titlePatterns = new Set<String>();
        for (BackupItem__c item : items) {
            titlePatterns.add(item.FullName__c + '_body');
            titlePatterns.add(item.FullName__c + '_meta');
        }
        
        if (!titlePatterns.isEmpty()) {
            List<ContentVersion> versions = [
                SELECT ContentDocumentId 
                FROM ContentVersion 
                WHERE Title IN :titlePatterns
                AND IsLatest = true
            ];
            
            Set<Id> documentIds = new Set<Id>();
            for (ContentVersion cv : versions) {
                documentIds.add(cv.ContentDocumentId);
            }
            
            if (!documentIds.isEmpty()) {
                List<ContentDocument> docs = [
                    SELECT Id FROM ContentDocument WHERE Id IN :documentIds
                ];
                delete docs;
            }
        }
        
        delete items;
        
        DeploymentRun__c run = new DeploymentRun__c(
            Id = deploymentRunId,
            BackupCleanedUp__c = true
        );
        update run;
        
        logAuditEvent('BackupCleanedUp', new Map<String, Object>{
            'deploymentRunId' => deploymentRunId,
            'itemsDeleted' => items.size()
        });
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
}
