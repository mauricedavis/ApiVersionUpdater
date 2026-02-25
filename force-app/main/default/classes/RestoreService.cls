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
                   MetadataDocumentId__c, OriginalApiVersion__c
            FROM BackupItem__c
            WHERE DeploymentRun__c = :deploymentRunId
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
                   MetadataDocumentId__c, OriginalApiVersion__c, DeploymentRun__c
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
            String backupContent = getBackupContent(item.ContentDocumentId__c);
            
            if (String.isBlank(backupContent)) {
                throw new AuraHandledException('No backup content found for ' + item.FullName__c);
            }
            
            restoreContent(item.ArtifactType__c, item.FullName__c, backupContent);
            
            result.success = true;
            result.restoredAt = Datetime.now();
            
        } catch (Exception e) {
            System.debug('Restore error for ' + item.FullName__c + ': ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            
            result.success = false;
            result.errorMessage = e.getMessage();
            
            if (String.isBlank(result.errorMessage)) {
                result.errorMessage = 'Restore failed: ' + e.getTypeName();
            }
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
        
        if (artifactType == 'ApexClass' || artifactType == 'ApexTrigger') {
            restoreViaMetadataContainer(artifactType, fullName, artifactId, content);
        } else {
            restoreViaPatch(artifactType, artifactId, content);
        }
    }
    
    private static void restoreViaMetadataContainer(String artifactType, String fullName, String artifactId, String content) {
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        String sessionId = UserInfo.getSessionId();
        
        String containerId = createMetadataContainer(baseUrl, sessionId);
        
        try {
            String memberType = artifactType == 'ApexClass' ? 'ApexClassMember' : 'ApexTriggerMember';
            Decimal currentApiVersion = getCurrentApiVersion(artifactType, fullName);
            
            addMemberToContainer(baseUrl, sessionId, containerId, memberType, artifactId, content, currentApiVersion);
            
            String asyncRequestId = deployContainer(baseUrl, sessionId, containerId);
            
            String status = pollForCompletion(baseUrl, sessionId, asyncRequestId);
            
            if (status != 'Completed') {
                String errorDetails = getContainerErrorDetails(baseUrl, sessionId, asyncRequestId);
                throw new AuraHandledException('Restore deployment failed: ' + errorDetails);
            }
        } finally {
            deleteContainer(baseUrl, sessionId, containerId);
        }
    }
    
    private static void restoreViaPatch(String artifactType, String artifactId, String content) {
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
    
    private static String createMetadataContainer(String baseUrl, String sessionId) {
        String endpoint = baseUrl + '/services/data/v65.0/tooling/sobjects/MetadataContainer';
        
        Map<String, Object> container = new Map<String, Object>{
            'Name' => 'Restore_' + String.valueOf(System.currentTimeMillis())
        };
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + sessionId);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(container));
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res.getStatusCode() == 201) {
            Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            return (String) result.get('id');
        }
        
        throw new AuraHandledException('Failed to create restore container: ' + res.getBody());
    }
    
    private static Decimal getCurrentApiVersion(String artifactType, String fullName) {
        if (artifactType == 'ApexClass') {
            List<ApexClass> items = [SELECT ApiVersion FROM ApexClass WHERE Name = :fullName LIMIT 1];
            return items.isEmpty() ? 56.0 : items[0].ApiVersion;
        } else {
            List<ApexTrigger> items = [SELECT ApiVersion FROM ApexTrigger WHERE Name = :fullName LIMIT 1];
            return items.isEmpty() ? 56.0 : items[0].ApiVersion;
        }
    }
    
    private static void addMemberToContainer(String baseUrl, String sessionId, String containerId, 
                                             String memberType, String contentEntityId, String body, 
                                             Decimal apiVersion) {
        String endpoint = baseUrl + '/services/data/v65.0/tooling/sobjects/' + memberType;
        
        Map<String, Object> metadata = new Map<String, Object>{
            'apiVersion' => Double.valueOf(apiVersion),
            'status' => 'Active'
        };
        
        Map<String, Object> member = new Map<String, Object>{
            'MetadataContainerId' => containerId,
            'ContentEntityId' => contentEntityId,
            'Body' => body,
            'Metadata' => metadata
        };
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + sessionId);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(member));
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res.getStatusCode() != 201) {
            throw new AuraHandledException('Failed to add member for restore: ' + res.getBody());
        }
    }
    
    private static String deployContainer(String baseUrl, String sessionId, String containerId) {
        String endpoint = baseUrl + '/services/data/v65.0/tooling/sobjects/ContainerAsyncRequest';
        
        Map<String, Object> asyncRequest = new Map<String, Object>{
            'MetadataContainerId' => containerId,
            'IsCheckOnly' => false,
            'IsRunTests' => false
        };
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + sessionId);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(asyncRequest));
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res.getStatusCode() == 201) {
            Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            return (String) result.get('id');
        }
        
        throw new AuraHandledException('Failed to deploy restore container: ' + res.getBody());
    }
    
    private static String pollForCompletion(String baseUrl, String sessionId, String asyncRequestId) {
        String endpoint = baseUrl + '/services/data/v65.0/tooling/sobjects/ContainerAsyncRequest/' + asyncRequestId;
        
        Integer maxAttempts = 30;
        Integer attempt = 0;
        String status = 'Queued';
        
        while (attempt < maxAttempts && (status == 'Queued' || status == 'Pending')) {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + sessionId);
            req.setHeader('Content-Type', 'application/json');
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                status = (String) result.get('State');
                
                if (status == 'Queued' || status == 'Pending') {
                    attempt++;
                }
            } else {
                throw new AuraHandledException('Failed to poll restore status: ' + res.getBody());
            }
        }
        
        return status;
    }
    
    private static String getContainerErrorDetails(String baseUrl, String sessionId, String asyncRequestId) {
        String endpoint = baseUrl + '/services/data/v65.0/tooling/sobjects/ContainerAsyncRequest/' + asyncRequestId;
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + sessionId);
        req.setHeader('Content-Type', 'application/json');
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res.getStatusCode() == 200) {
            Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            String state = (String) result.get('State');
            String errorMsg = (String) result.get('ErrorMsg');
            
            if (String.isNotBlank(errorMsg)) {
                return errorMsg;
            }
            return 'Deployment ended with state: ' + state;
        }
        
        return 'Failed to retrieve error details';
    }
    
    private static void deleteContainer(String baseUrl, String sessionId, String containerId) {
        try {
            String endpoint = baseUrl + '/services/data/v65.0/tooling/sobjects/MetadataContainer/' + containerId;
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('DELETE');
            req.setHeader('Authorization', 'Bearer ' + sessionId);
            
            Http http = new Http();
            http.send(req);
        } catch (Exception e) {
            System.debug('Failed to delete restore container: ' + e.getMessage());
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
