public with sharing class MetadataUpdateService {
    
    private static final String API_VERSION = 'v65.0';
    
    public class UpdateResult {
        public String itemId;
        public String fullName;
        public String artifactType;
        public Boolean success;
        public String errorMessage;
        public Decimal originalVersion;
        public Decimal newVersion;
    }
    
    public class ContainerResult {
        public String containerId;
        public String asyncRequestId;
        public String status;
        public List<UpdateResult> results;
    }
    
    @AuraEnabled
    public static ContainerResult updateApiVersions(List<String> changeItemIds, Decimal targetApiVersion) {
        ContainerResult containerResult = new ContainerResult();
        containerResult.results = new List<UpdateResult>();
        
        if (changeItemIds == null || changeItemIds.isEmpty()) {
            return containerResult;
        }
        
        List<ChangeItem__c> items = [
            SELECT Id, ArtifactType__c, FullName__c, CurrentApiVersion__c, TargetApiVersion__c
            FROM ChangeItem__c
            WHERE Id IN :changeItemIds
        ];
        
        try {
            String containerId = createMetadataContainer();
            containerResult.containerId = containerId;
            
            for (ChangeItem__c item : items) {
                UpdateResult result = new UpdateResult();
                result.itemId = item.Id;
                result.fullName = item.FullName__c;
                result.artifactType = item.ArtifactType__c;
                result.originalVersion = item.CurrentApiVersion__c;
                result.newVersion = targetApiVersion;
                
                try {
                    addMemberToContainer(containerId, item.ArtifactType__c, item.FullName__c, targetApiVersion);
                    result.success = true;
                } catch (Exception e) {
                    result.success = false;
                    result.errorMessage = e.getMessage();
                }
                
                containerResult.results.add(result);
            }
            
            String asyncRequestId = deployContainer(containerId);
            containerResult.asyncRequestId = asyncRequestId;
            containerResult.status = 'Queued';
            
        } catch (Exception e) {
            containerResult.status = 'Failed';
            for (UpdateResult r : containerResult.results) {
                if (r.success) {
                    r.success = false;
                    r.errorMessage = 'Container deployment failed: ' + e.getMessage();
                }
            }
        }
        
        return containerResult;
    }
    
    @AuraEnabled
    public static String checkDeploymentStatus(String asyncRequestId) {
        String endpoint = URL.getOrgDomainUrl().toExternalForm() + 
            '/services/data/' + API_VERSION + '/tooling/sobjects/ContainerAsyncRequest/' + asyncRequestId;
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        req.setHeader('Content-Type', 'application/json');
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res.getStatusCode() == 200) {
            Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            return (String) result.get('State');
        }
        
        throw new AuraHandledException('Failed to check deployment status: ' + res.getBody());
    }
    
    @AuraEnabled
    public static Map<String, Object> getDeploymentDetails(String asyncRequestId) {
        String endpoint = URL.getOrgDomainUrl().toExternalForm() + 
            '/services/data/' + API_VERSION + '/tooling/sobjects/ContainerAsyncRequest/' + asyncRequestId;
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        req.setHeader('Content-Type', 'application/json');
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res.getStatusCode() == 200) {
            return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        }
        
        throw new AuraHandledException('Failed to get deployment details: ' + res.getBody());
    }
    
    private static String createMetadataContainer() {
        String endpoint = URL.getOrgDomainUrl().toExternalForm() + 
            '/services/data/' + API_VERSION + '/tooling/sobjects/MetadataContainer';
        
        Map<String, Object> container = new Map<String, Object>{
            'Name' => 'ApiVersionUpdate_' + System.currentTimeMillis()
        };
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(container));
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res.getStatusCode() == 201) {
            Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            return (String) result.get('id');
        }
        
        throw new AuraHandledException('Failed to create metadata container: ' + res.getBody());
    }
    
    private static void addMemberToContainer(String containerId, String artifactType, String fullName, Decimal targetApiVersion) {
        String memberType = getMemberType(artifactType);
        String contentEntityId = getContentEntityId(artifactType, fullName);
        
        if (String.isBlank(contentEntityId)) {
            throw new AuraHandledException('Could not find ' + artifactType + ': ' + fullName);
        }
        
        String currentBody = getComponentBody(artifactType, fullName);
        
        String endpoint = URL.getOrgDomainUrl().toExternalForm() + 
            '/services/data/' + API_VERSION + '/tooling/sobjects/' + memberType;
        
        Map<String, Object> metadata = new Map<String, Object>{
            'apiVersion' => targetApiVersion,
            'status' => 'Active'
        };
        
        Map<String, Object> member = new Map<String, Object>{
            'MetadataContainerId' => containerId,
            'ContentEntityId' => contentEntityId,
            'Body' => currentBody,
            'Metadata' => metadata
        };
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(member));
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res.getStatusCode() != 201) {
            String errorMsg = 'Failed to add member';
            
            try {
                Object parsedResponse = JSON.deserializeUntyped(res.getBody());
                
                if (parsedResponse instanceof List<Object>) {
                    List<Object> errors = (List<Object>) parsedResponse;
                    if (!errors.isEmpty()) {
                        Map<String, Object> firstError = (Map<String, Object>) errors[0];
                        if (firstError.containsKey('message')) {
                            errorMsg = (String) firstError.get('message');
                        }
                    }
                } else if (parsedResponse instanceof Map<String, Object>) {
                    Map<String, Object> errorResult = (Map<String, Object>) parsedResponse;
                    if (errorResult.containsKey('message')) {
                        errorMsg = (String) errorResult.get('message');
                    }
                }
            } catch (Exception e) {
                errorMsg = res.getBody();
            }
            
            throw new AuraHandledException(errorMsg);
        }
    }
    
    private static String deployContainer(String containerId) {
        String endpoint = URL.getOrgDomainUrl().toExternalForm() + 
            '/services/data/' + API_VERSION + '/tooling/sobjects/ContainerAsyncRequest';
        
        Map<String, Object> asyncRequest = new Map<String, Object>{
            'MetadataContainerId' => containerId,
            'IsCheckOnly' => false
        };
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(asyncRequest));
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res.getStatusCode() == 201) {
            Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            return (String) result.get('id');
        }
        
        throw new AuraHandledException('Failed to deploy container: ' + res.getBody());
    }
    
    private static String getMemberType(String artifactType) {
        switch on artifactType {
            when 'ApexClass' {
                return 'ApexClassMember';
            }
            when 'ApexTrigger' {
                return 'ApexTriggerMember';
            }
            when 'ApexPage' {
                return 'ApexPageMember';
            }
            when 'ApexComponent' {
                return 'ApexComponentMember';
            }
            when else {
                throw new AuraHandledException('Unsupported artifact type: ' + artifactType);
            }
        }
    }
    
    private static String getContentEntityId(String artifactType, String fullName) {
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
    
    private static String getComponentBody(String artifactType, String fullName) {
        switch on artifactType {
            when 'ApexClass' {
                List<ApexClass> items = [SELECT Body FROM ApexClass WHERE Name = :fullName LIMIT 1];
                return items.isEmpty() ? '' : items[0].Body;
            }
            when 'ApexTrigger' {
                List<ApexTrigger> items = [SELECT Body FROM ApexTrigger WHERE Name = :fullName LIMIT 1];
                return items.isEmpty() ? '' : items[0].Body;
            }
            when 'ApexPage' {
                List<ApexPage> items = [SELECT Markup FROM ApexPage WHERE Name = :fullName LIMIT 1];
                return items.isEmpty() ? '' : items[0].Markup;
            }
            when 'ApexComponent' {
                List<ApexComponent> items = [SELECT Markup FROM ApexComponent WHERE Name = :fullName LIMIT 1];
                return items.isEmpty() ? '' : items[0].Markup;
            }
            when else {
                return '';
            }
        }
    }
    
    @AuraEnabled
    public static UpdateResult updateSingleComponent(String artifactType, String fullName, Decimal targetApiVersion) {
        UpdateResult result = new UpdateResult();
        result.fullName = fullName;
        result.artifactType = artifactType;
        result.newVersion = targetApiVersion;
        
        try {
            String containerId = createMetadataContainer();
            addMemberToContainer(containerId, artifactType, fullName, targetApiVersion);
            String asyncRequestId = deployContainer(containerId);
            
            Integer maxPolls = 30;
            Integer pollCount = 0;
            String status = 'Queued';
            
            while (pollCount < maxPolls && (status == 'Queued' || status == 'Pending')) {
                status = checkDeploymentStatus(asyncRequestId);
                if (status == 'Queued' || status == 'Pending') {
                    pollCount++;
                }
            }
            
            if (status == 'Completed') {
                result.success = true;
            } else if (status == 'Failed' || status == 'Error') {
                Map<String, Object> details = getDeploymentDetails(asyncRequestId);
                result.success = false;
                result.errorMessage = details.containsKey('ErrorMsg') 
                    ? (String) details.get('ErrorMsg') 
                    : 'Deployment failed with status: ' + status;
            } else {
                result.success = false;
                result.errorMessage = 'Deployment timed out with status: ' + status;
            }
            
        } catch (Exception e) {
            result.success = false;
            result.errorMessage = e.getMessage();
        }
        
        return result;
    }
}
