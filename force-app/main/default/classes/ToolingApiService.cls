public with sharing class ToolingApiService {
    
    public class ToolingApiException extends Exception {}
    
    private static final String NAMED_CREDENTIAL_NAME = 'API_Version_Updater_Tooling';
    private static final String API_VERSION = 'v65.0';
    
    public class ApiResponse {
        public Integer statusCode;
        public String body;
        public Boolean isSuccess;
        public String errorMessage;
        
        public ApiResponse(HttpResponse res) {
            this.statusCode = res.getStatusCode();
            this.body = res.getBody();
            this.isSuccess = res.getStatusCode() >= 200 && res.getStatusCode() < 300;
            
            if (!this.isSuccess) {
                this.errorMessage = parseErrorMessage(res.getBody());
            }
        }
        
        private String parseErrorMessage(String responseBody) {
            try {
                Object parsed = JSON.deserializeUntyped(responseBody);
                if (parsed instanceof List<Object>) {
                    List<Object> errors = (List<Object>) parsed;
                    if (!errors.isEmpty()) {
                        Map<String, Object> firstError = (Map<String, Object>) errors[0];
                        if (firstError.containsKey('message')) {
                            return (String) firstError.get('message');
                        }
                    }
                } else if (parsed instanceof Map<String, Object>) {
                    Map<String, Object> errorMap = (Map<String, Object>) parsed;
                    if (errorMap.containsKey('message')) {
                        return (String) errorMap.get('message');
                    }
                }
            } catch (Exception e) {
                // Fall through
            }
            return responseBody;
        }
    }
    
    public class SetupStatus {
        @AuraEnabled public Boolean isConfigured;
        @AuraEnabled public Boolean hasNamedCredential;
        @AuraEnabled public Boolean hasExternalCredential;
        @AuraEnabled public Boolean hasUserAuthenticated;
        @AuraEnabled public String setupMessage;
        @AuraEnabled public List<String> missingSteps;
        
        public SetupStatus() {
            this.isConfigured = false;
            this.hasNamedCredential = false;
            this.hasExternalCredential = false;
            this.hasUserAuthenticated = false;
            this.missingSteps = new List<String>();
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static SetupStatus checkSetupStatus() {
        SetupStatus status = new SetupStatus();
        
        // Check if Named Credential exists by attempting to query it
        try {
            List<NamedCredential> namedCreds = [
                SELECT Id, DeveloperName, Endpoint 
                FROM NamedCredential 
                WHERE DeveloperName = :NAMED_CREDENTIAL_NAME
                LIMIT 1
            ];
            status.hasNamedCredential = !namedCreds.isEmpty();
        } catch (Exception e) {
            status.hasNamedCredential = false;
        }
        
        // We can't query ExternalCredential directly via SOQL
        // Instead, we'll check if the Named Credential exists and if auth works
        // The External Credential is assumed to exist if Named Credential is configured
        status.hasExternalCredential = status.hasNamedCredential;
        
        // Check if current user has authenticated (test with a simple API call)
        if (status.hasNamedCredential) {
            status.hasUserAuthenticated = testUserAuthentication();
        }
        
        // Build missing steps
        if (!status.hasNamedCredential) {
            status.missingSteps.add('Create Connected App and configure Named Credential');
        }
        if (status.hasNamedCredential && !status.hasUserAuthenticated) {
            status.missingSteps.add('Authenticate your user with the Named Credential');
        }
        
        status.isConfigured = status.hasNamedCredential && status.hasUserAuthenticated;
        
        if (status.isConfigured) {
            status.setupMessage = 'API Version Updater is fully configured and ready to use.';
        } else if (status.missingSteps.isEmpty()) {
            status.setupMessage = 'Setup verification in progress...';
        } else {
            status.setupMessage = 'Setup required: ' + status.missingSteps.size() + ' step(s) remaining.';
        }
        
        return status;
    }
    
    private static Boolean testUserAuthentication() {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:' + NAMED_CREDENTIAL_NAME + '/services/data/' + API_VERSION + '/tooling/');
            req.setMethod('GET');
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(10000);
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            return res.getStatusCode() == 200;
        } catch (Exception e) {
            System.debug('Authentication test failed: ' + e.getMessage());
            return false;
        }
    }
    
    public static String getToolingEndpoint() {
        return 'callout:' + NAMED_CREDENTIAL_NAME + '/services/data/' + API_VERSION + '/tooling';
    }
    
    public static ApiResponse doGet(String path) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(getToolingEndpoint() + path);
        req.setMethod('GET');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(120000);
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        System.debug('ToolingAPI GET ' + path + ' -> ' + res.getStatusCode());
        
        return new ApiResponse(res);
    }
    
    public static ApiResponse doPost(String path, Object body) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(getToolingEndpoint() + path);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(body));
        req.setTimeout(120000);
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        System.debug('ToolingAPI POST ' + path + ' -> ' + res.getStatusCode());
        
        return new ApiResponse(res);
    }
    
    public static ApiResponse doPatch(String path, Object body) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(getToolingEndpoint() + path);
        req.setMethod('PATCH');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(body));
        req.setTimeout(120000);
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        System.debug('ToolingAPI PATCH ' + path + ' -> ' + res.getStatusCode());
        
        return new ApiResponse(res);
    }
    
    public static ApiResponse doDelete(String path) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(getToolingEndpoint() + path);
        req.setMethod('DELETE');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(120000);
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        System.debug('ToolingAPI DELETE ' + path + ' -> ' + res.getStatusCode());
        
        return new ApiResponse(res);
    }
    
    public static ApiResponse doQuery(String soql) {
        String encodedQuery = EncodingUtil.urlEncode(soql, 'UTF-8');
        return doGet('/query/?q=' + encodedQuery);
    }
    
    // Convenience methods for common operations
    
    public static String createMetadataContainer(String containerName) {
        Map<String, Object> container = new Map<String, Object>{
            'Name' => containerName
        };
        
        ApiResponse res = doPost('/sobjects/MetadataContainer', container);
        
        if (res.isSuccess) {
            Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.body);
            return (String) result.get('id');
        }
        
        throw new ToolingApiException('Failed to create metadata container: ' + res.errorMessage);
    }
    
    public static String deployContainer(String containerId, Boolean isCheckOnly, Boolean runTests) {
        Map<String, Object> asyncRequest = new Map<String, Object>{
            'MetadataContainerId' => containerId,
            'IsCheckOnly' => isCheckOnly,
            'IsRunTests' => runTests
        };
        
        ApiResponse res = doPost('/sobjects/ContainerAsyncRequest', asyncRequest);
        
        if (res.isSuccess) {
            Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.body);
            return (String) result.get('id');
        }
        
        throw new ToolingApiException('Failed to deploy container: ' + res.errorMessage);
    }
    
    public static Map<String, Object> getContainerAsyncRequestStatus(String asyncRequestId) {
        ApiResponse res = doGet('/sobjects/ContainerAsyncRequest/' + asyncRequestId);
        
        if (res.isSuccess) {
            return (Map<String, Object>) JSON.deserializeUntyped(res.body);
        }
        
        throw new ToolingApiException('Failed to get container status: ' + res.errorMessage);
    }
    
    public static void addClassMember(String containerId, String contentEntityId, String body, Map<String, Object> metadata) {
        Map<String, Object> member = new Map<String, Object>{
            'MetadataContainerId' => containerId,
            'ContentEntityId' => contentEntityId,
            'Body' => body,
            'Metadata' => metadata
        };
        
        ApiResponse res = doPost('/sobjects/ApexClassMember', member);
        
        if (!res.isSuccess) {
            throw new ToolingApiException('Failed to add class member: ' + res.errorMessage);
        }
    }
    
    public static void addTriggerMember(String containerId, String contentEntityId, String body, Map<String, Object> metadata) {
        Map<String, Object> member = new Map<String, Object>{
            'MetadataContainerId' => containerId,
            'ContentEntityId' => contentEntityId,
            'Body' => body,
            'Metadata' => metadata
        };
        
        ApiResponse res = doPost('/sobjects/ApexTriggerMember', member);
        
        if (!res.isSuccess) {
            throw new ToolingApiException('Failed to add trigger member: ' + res.errorMessage);
        }
    }
    
    public static void addPageMember(String containerId, String contentEntityId, String markup, Map<String, Object> metadata) {
        Map<String, Object> member = new Map<String, Object>{
            'MetadataContainerId' => containerId,
            'ContentEntityId' => contentEntityId,
            'Markup' => markup,
            'Metadata' => metadata
        };
        
        ApiResponse res = doPost('/sobjects/ApexPageMember', member);
        
        if (!res.isSuccess) {
            throw new ToolingApiException('Failed to add page member: ' + res.errorMessage);
        }
    }
    
    public static void addComponentMember(String containerId, String contentEntityId, String markup, Map<String, Object> metadata) {
        Map<String, Object> member = new Map<String, Object>{
            'MetadataContainerId' => containerId,
            'ContentEntityId' => contentEntityId,
            'Markup' => markup,
            'Metadata' => metadata
        };
        
        ApiResponse res = doPost('/sobjects/ApexComponentMember', member);
        
        if (!res.isSuccess) {
            throw new ToolingApiException('Failed to add component member: ' + res.errorMessage);
        }
    }
    
    public static String pollForCompletion(String asyncRequestId, Integer maxAttempts) {
        Integer attempt = 0;
        String status = 'Queued';
        
        while (attempt < maxAttempts && (status == 'Queued' || status == 'Pending')) {
            Map<String, Object> result = getContainerAsyncRequestStatus(asyncRequestId);
            status = (String) result.get('State');
            
            if (status == 'Completed' || status == 'Failed' || status == 'Error') {
                return status;
            }
            
            attempt++;
        }
        
        return status;
    }
    
    public static String getContainerErrorDetails(String asyncRequestId) {
        try {
            Map<String, Object> result = getContainerAsyncRequestStatus(asyncRequestId);
            String errorMsg = (String) result.get('ErrorMsg');
            
            if (String.isNotBlank(errorMsg)) {
                return errorMsg;
            }
            
            // Try to get detailed compile errors from members
            String soql = 'SELECT ContentEntity.Name, CompilerErrors FROM ApexClassMember ' +
                         'WHERE MetadataContainerId IN (SELECT MetadataContainerId FROM ContainerAsyncRequest WHERE Id = \'' + asyncRequestId + '\')';
            
            ApiResponse queryRes = doQuery(soql);
            
            if (queryRes.isSuccess) {
                Map<String, Object> queryResult = (Map<String, Object>) JSON.deserializeUntyped(queryRes.body);
                List<Object> records = (List<Object>) queryResult.get('records');
                
                List<String> errors = new List<String>();
                if (records != null) {
                    for (Object record : records) {
                        Map<String, Object> rec = (Map<String, Object>) record;
                        String compilerErrors = (String) rec.get('CompilerErrors');
                        
                        if (String.isNotBlank(compilerErrors) && compilerErrors != '[]' && compilerErrors != 'null') {
                            Map<String, Object> contentEntity = (Map<String, Object>) rec.get('ContentEntity');
                            String componentName = contentEntity != null ? (String) contentEntity.get('Name') : 'Unknown';
                            errors.add(componentName + ': ' + compilerErrors);
                        }
                    }
                }
                
                if (!errors.isEmpty()) {
                    return String.join(errors, '\n');
                }
            }
            
            return 'Deployment failed without detailed error message';
            
        } catch (Exception e) {
            return 'Error retrieving error details: ' + e.getMessage();
        }
    }
}
