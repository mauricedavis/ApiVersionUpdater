public with sharing class RestoreService {
    
    public class RestoreResultDto {
        @AuraEnabled public String backupItemId;
        @AuraEnabled public String fullName;
        @AuraEnabled public Boolean success;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public Datetime restoredAt;
    }
    
    public class DiffResultDto {
        @AuraEnabled public String backupItemId;
        @AuraEnabled public String fullName;
        @AuraEnabled public String backupContent;
        @AuraEnabled public String currentContent;
        @AuraEnabled public String backupMetadata;
        @AuraEnabled public String currentMetadata;
        @AuraEnabled public Integer linesAdded;
        @AuraEnabled public Integer linesRemoved;
        @AuraEnabled public Integer linesChanged;
        @AuraEnabled public Boolean hasContentChanges;
        @AuraEnabled public Boolean hasMetadataChanges;
    }
    
    @AuraEnabled
    public static List<RestoreResultDto> restoreAll(String deploymentRunId) {
        List<BackupItem__c> items = [
            SELECT Id, ArtifactType__c, FullName__c, ContentDocumentId__c, 
                   MetadataDocumentId__c, OriginalApiVersion__c, RestoreStatus__c
            FROM BackupItem__c
            WHERE DeploymentRun__c = :deploymentRunId
            AND RestoreStatus__c = 'NotRestored'
        ];
        
        List<RestoreResultDto> results = new List<RestoreResultDto>();
        
        for (BackupItem__c item : items) {
            RestoreResultDto result = restoreItemInternal(item);
            results.add(result);
        }
        
        logAuditEvent('RestoreAllCompleted', new Map<String, Object>{
            'deploymentRunId' => deploymentRunId,
            'itemCount' => items.size(),
            'successCount' => countSuccesses(results)
        });
        
        return results;
    }
    
    @AuraEnabled
    public static RestoreResultDto restoreItem(String backupItemId) {
        BackupItem__c item = [
            SELECT Id, ArtifactType__c, FullName__c, ContentDocumentId__c, 
                   MetadataDocumentId__c, OriginalApiVersion__c, RestoreStatus__c,
                   DeploymentRun__c
            FROM BackupItem__c
            WHERE Id = :backupItemId
        ];
        
        RestoreResultDto result = restoreItemInternal(item);
        
        logAuditEvent('RestoreItemCompleted', new Map<String, Object>{
            'backupItemId' => backupItemId,
            'fullName' => item.FullName__c,
            'success' => result.success
        });
        
        return result;
    }
    
    private static RestoreResultDto restoreItemInternal(BackupItem__c item) {
        RestoreResultDto result = new RestoreResultDto();
        result.backupItemId = item.Id;
        result.fullName = item.FullName__c;
        
        try {
            item.RestoreStatus__c = 'Restoring';
            update item;
            
            String backupContent = getBackupContent(item.ContentDocumentId__c);
            
            if (String.isBlank(backupContent)) {
                throw new AuraHandledException('No backup content found');
            }
            
            restoreContent(item.ArtifactType__c, item.FullName__c, backupContent);
            
            item.RestoreStatus__c = 'Restored';
            item.RestoredAt__c = Datetime.now();
            item.RestoreErrorDetails__c = null;
            update item;
            
            result.success = true;
            result.restoredAt = Datetime.now();
            
        } catch (Exception e) {
            item.RestoreStatus__c = 'Failed';
            item.RestoreErrorDetails__c = e.getMessage() + '\n' + e.getStackTraceString();
            update item;
            
            result.success = false;
            result.errorMessage = e.getMessage();
        }
        
        return result;
    }
    
    private static String getBackupContent(String contentDocumentId) {
        if (String.isBlank(contentDocumentId)) {
            return '';
        }
        
        List<ContentVersion> cvs = [
            SELECT VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            AND IsLatest = true
            LIMIT 1
        ];
        
        if (cvs.isEmpty()) {
            return '';
        }
        
        return cvs[0].VersionData.toString();
    }
    
    private static void restoreContent(String artifactType, String fullName, String content) {
        String artifactId = getArtifactId(artifactType, fullName);
        
        if (String.isBlank(artifactId)) {
            throw new AuraHandledException('Could not find ' + artifactType + ': ' + fullName);
        }
        
        String endpoint = getToolingApiEndpoint(artifactType, artifactId);
        String bodyField = getBodyFieldName(artifactType);
        
        Map<String, Object> requestBody = new Map<String, Object>{
            bodyField => content
        };
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(URL.getOrgDomainUrl().toExternalForm() + endpoint);
        req.setMethod('PATCH');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(requestBody));
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res.getStatusCode() != 200 && res.getStatusCode() != 204) {
            throw new AuraHandledException('Failed to restore: ' + res.getBody());
        }
    }
    
    private static String getArtifactId(String artifactType, String fullName) {
        switch on artifactType {
            when 'ApexClass' {
                List<ApexClass> items = [SELECT Id FROM ApexClass WHERE Name = :fullName LIMIT 1];
                return items.isEmpty() ? null : items[0].Id;
            }
            when 'ApexTrigger' {
                List<ApexTrigger> items = [SELECT Id FROM ApexTrigger WHERE Name = :fullName LIMIT 1];
                return items.isEmpty() ? null : items[0].Id;
            }
            when 'ApexPage' {
                List<ApexPage> items = [SELECT Id FROM ApexPage WHERE Name = :fullName LIMIT 1];
                return items.isEmpty() ? null : items[0].Id;
            }
            when 'ApexComponent' {
                List<ApexComponent> items = [SELECT Id FROM ApexComponent WHERE Name = :fullName LIMIT 1];
                return items.isEmpty() ? null : items[0].Id;
            }
            when else {
                return null;
            }
        }
    }
    
    private static String getToolingApiEndpoint(String artifactType, String artifactId) {
        return '/services/data/v65.0/tooling/sobjects/' + artifactType + '/' + artifactId;
    }
    
    private static String getBodyFieldName(String artifactType) {
        switch on artifactType {
            when 'ApexClass', 'ApexTrigger' {
                return 'Body';
            }
            when 'ApexPage', 'ApexComponent' {
                return 'Markup';
            }
            when else {
                return 'Body';
            }
        }
    }
    
    @AuraEnabled
    public static String previewBackupContent(String backupItemId) {
        BackupItem__c item = [
            SELECT ContentDocumentId__c
            FROM BackupItem__c
            WHERE Id = :backupItemId
        ];
        
        return getBackupContent(item.ContentDocumentId__c);
    }
    
    @AuraEnabled
    public static DiffResultDto getDiff(String backupItemId) {
        BackupItem__c item = [
            SELECT Id, ArtifactType__c, FullName__c, ContentDocumentId__c, MetadataDocumentId__c
            FROM BackupItem__c
            WHERE Id = :backupItemId
        ];
        
        DiffResultDto diff = new DiffResultDto();
        diff.backupItemId = item.Id;
        diff.fullName = item.FullName__c;
        
        diff.backupContent = getBackupContent(item.ContentDocumentId__c);
        diff.backupMetadata = getBackupContent(item.MetadataDocumentId__c);
        
        Map<String, String> current = getCurrentContent(item.ArtifactType__c, item.FullName__c);
        diff.currentContent = current.get('content');
        diff.currentMetadata = current.get('metadata');
        
        ContentService.DiffResultDto contentDiff = ContentService.compareDiff(
            diff.backupContent, 
            diff.currentContent
        );
        
        diff.linesAdded = contentDiff.linesAdded;
        diff.linesRemoved = contentDiff.linesRemoved;
        diff.linesChanged = contentDiff.linesChanged;
        diff.hasContentChanges = contentDiff.hasChanges;
        diff.hasMetadataChanges = diff.backupMetadata != diff.currentMetadata;
        
        return diff;
    }
    
    private static Map<String, String> getCurrentContent(String artifactType, String fullName) {
        Map<String, String> result = new Map<String, String>();
        
        switch on artifactType {
            when 'ApexClass' {
                ApexClass cls = [
                    SELECT Body, ApiVersion, Status 
                    FROM ApexClass 
                    WHERE Name = :fullName 
                    LIMIT 1
                ];
                result.put('content', cls.Body);
                result.put('metadata', generateApexClassMetadata(cls));
            }
            when 'ApexTrigger' {
                ApexTrigger trg = [
                    SELECT Body, ApiVersion, Status 
                    FROM ApexTrigger 
                    WHERE Name = :fullName 
                    LIMIT 1
                ];
                result.put('content', trg.Body);
                result.put('metadata', generateApexTriggerMetadata(trg));
            }
            when 'ApexPage' {
                ApexPage pg = [
                    SELECT Markup, ApiVersion 
                    FROM ApexPage 
                    WHERE Name = :fullName 
                    LIMIT 1
                ];
                result.put('content', pg.Markup);
                result.put('metadata', generateApexPageMetadata(pg));
            }
            when 'ApexComponent' {
                ApexComponent cmp = [
                    SELECT Markup, ApiVersion 
                    FROM ApexComponent 
                    WHERE Name = :fullName 
                    LIMIT 1
                ];
                result.put('content', cmp.Markup);
                result.put('metadata', generateApexComponentMetadata(cmp));
            }
        }
        
        return result;
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
               '</ApexPage>';
    }
    
    private static String generateApexComponentMetadata(ApexComponent cmp) {
        return '<?xml version="1.0" encoding="UTF-8"?>\n' +
               '<ApexComponent xmlns="http://soap.sforce.com/2006/04/metadata">\n' +
               '    <apiVersion>' + cmp.ApiVersion + '</apiVersion>\n' +
               '</ApexComponent>';
    }
    
    @AuraEnabled(cacheable=true)
    public static List<BackupService.BackupItemDto> getRestorableItems(String deploymentRunId) {
        return BackupService.getBackupItems(deploymentRunId);
    }
    
    private static Integer countSuccesses(List<RestoreResultDto> results) {
        Integer count = 0;
        for (RestoreResultDto r : results) {
            if (r.success) count++;
        }
        return count;
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
