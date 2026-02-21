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
        Map<String, BackupItem__c> itemsByKey = new Map<String, BackupItem__c>();
        
        for (ChangeItem__c item : changeItems) {
            BackupItem__c backupItem = new BackupItem__c(
                DeploymentRun__c = deploymentRunId,
                ChangeItem__c = item.Id,
                ArtifactType__c = item.ArtifactType__c,
                FullName__c = item.FullName__c,
                OriginalApiVersion__c = item.CurrentApiVersion__c,
                RestoreStatus__c = 'NotRestored',
                BackupCreatedAt__c = Datetime.now()
            );
            backupItems.add(backupItem);
            itemsByKey.put(item.ArtifactType__c + ':' + item.FullName__c, backupItem);
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
        Map<String, BackupItem__c> cvToBackupItem = new Map<String, BackupItem__c>();
        
        for (BackupItem__c item : backupItems) {
            ContentResult result = fetchAndCreateContentVersion(item);
            if (result.contentVersion != null) {
                contentVersions.add(result.contentVersion);
                cvToBackupItem.put(item.FullName__c + '_body', item);
            }
            if (result.metadataVersion != null) {
                contentVersions.add(result.metadataVersion);
                cvToBackupItem.put(item.FullName__c + '_meta', item);
            }
            item.ContentHash__c = result.contentHash;
            item.RelatedTestClassesJson__c = result.relatedTestClassesJson;
        }
        
        if (!contentVersions.isEmpty()) {
            insert contentVersions;
            
            Set<Id> cvIds = new Set<Id>();
            for (ContentVersion cv : contentVersions) {
                cvIds.add(cv.Id);
            }
            
            Map<Id, ContentVersion> insertedCVs = new Map<Id, ContentVersion>([
                SELECT Id, ContentDocumentId, Title
                FROM ContentVersion
                WHERE Id IN :cvIds
            ]);
            
            for (ContentVersion cv : insertedCVs.values()) {
                String title = cv.Title;
                if (title.endsWith('_body')) {
                    String fullName = title.substringBefore('_body');
                    for (BackupItem__c item : backupItems) {
                        if (item.FullName__c == fullName) {
                            item.ContentDocumentId__c = cv.ContentDocumentId;
                            break;
                        }
                    }
                } else if (title.endsWith('_meta')) {
                    String fullName = title.substringBefore('_meta');
                    for (BackupItem__c item : backupItems) {
                        if (item.FullName__c == fullName) {
                            item.MetadataDocumentId__c = cv.ContentDocumentId;
                            break;
                        }
                    }
                }
            }
            
            update backupItems;
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
        
        List<AggregateResult> statusCounts = [
            SELECT RestoreStatus__c status, COUNT(Id) cnt
            FROM BackupItem__c
            WHERE DeploymentRun__c = :deploymentRunId
            GROUP BY RestoreStatus__c
        ];
        
        summary.restoredCount = 0;
        summary.pendingCount = 0;
        
        for (AggregateResult ar : statusCounts) {
            String status = (String) ar.get('status');
            Integer count = (Integer) ar.get('cnt');
            if (status == 'Restored') {
                summary.restoredCount = count;
            } else if (status == 'NotRestored') {
                summary.pendingCount = count;
            }
        }
        
        return summary;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<BackupItemDto> getBackupItems(String deploymentRunId) {
        List<BackupItemDto> items = new List<BackupItemDto>();
        
        for (BackupItem__c item : [
            SELECT Id, DeploymentRun__c, ChangeItem__c, ArtifactType__c, FullName__c,
                   OriginalApiVersion__c, ContentDocumentId__c, MetadataDocumentId__c,
                   RestoreStatus__c, BackupCreatedAt__c, RestoredAt__c, ContentHash__c,
                   RelatedTestClassesJson__c
            FROM BackupItem__c
            WHERE DeploymentRun__c = :deploymentRunId
            ORDER BY FullName__c
        ]) {
            BackupItemDto dto = new BackupItemDto();
            dto.id = item.Id;
            dto.deploymentRunId = item.DeploymentRun__c;
            dto.changeItemId = item.ChangeItem__c;
            dto.artifactType = item.ArtifactType__c;
            dto.fullName = item.FullName__c;
            dto.originalApiVersion = item.OriginalApiVersion__c;
            dto.contentDocumentId = item.ContentDocumentId__c;
            dto.metadataDocumentId = item.MetadataDocumentId__c;
            dto.restoreStatus = item.RestoreStatus__c;
            dto.backupCreatedAt = item.BackupCreatedAt__c;
            dto.restoredAt = item.RestoredAt__c;
            dto.contentHash = item.ContentHash__c;
            
            if (String.isNotBlank(item.RelatedTestClassesJson__c)) {
                dto.relatedTestClasses = (List<String>) JSON.deserialize(
                    item.RelatedTestClassesJson__c, 
                    List<String>.class
                );
            }
            
            items.add(dto);
        }
        
        return items;
    }
    
    @AuraEnabled
    public static String getBackupContent(String backupItemId) {
        BackupItem__c item = [
            SELECT ContentDocumentId__c
            FROM BackupItem__c
            WHERE Id = :backupItemId
        ];
        
        if (String.isBlank(item.ContentDocumentId__c)) {
            return '';
        }
        
        ContentVersion cv = [
            SELECT VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :item.ContentDocumentId__c
            AND IsLatest = true
            LIMIT 1
        ];
        
        return cv.VersionData.toString();
    }
    
    @AuraEnabled
    public static String getBackupMetadata(String backupItemId) {
        BackupItem__c item = [
            SELECT MetadataDocumentId__c
            FROM BackupItem__c
            WHERE Id = :backupItemId
        ];
        
        if (String.isBlank(item.MetadataDocumentId__c)) {
            return '';
        }
        
        ContentVersion cv = [
            SELECT VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :item.MetadataDocumentId__c
            AND IsLatest = true
            LIMIT 1
        ];
        
        return cv.VersionData.toString();
    }
    
    @AuraEnabled
    public static void cleanupBackup(String deploymentRunId) {
        List<BackupItem__c> items = [
            SELECT Id, ContentDocumentId__c, MetadataDocumentId__c
            FROM BackupItem__c
            WHERE DeploymentRun__c = :deploymentRunId
        ];
        
        Set<Id> documentIds = new Set<Id>();
        for (BackupItem__c item : items) {
            if (String.isNotBlank(item.ContentDocumentId__c)) {
                documentIds.add(item.ContentDocumentId__c);
            }
            if (String.isNotBlank(item.MetadataDocumentId__c)) {
                documentIds.add(item.MetadataDocumentId__c);
            }
        }
        
        if (!documentIds.isEmpty()) {
            List<ContentDocument> docs = [
                SELECT Id FROM ContentDocument WHERE Id IN :documentIds
            ];
            delete docs;
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
