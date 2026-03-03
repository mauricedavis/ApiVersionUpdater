public with sharing class DeploymentService {
    
    public class DeploymentException extends Exception {}
    
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
        
        Set<Id> snapshotIds = new Set<Id>();
        for (ArtifactSnapshot__c snap : snapshots) {
            snapshotIds.add(snap.Id);
        }
        
        Map<Id, Integer> blockingFindingsMap = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT ArtifactSnapshot__c snapId, COUNT(Id) cnt
            FROM Finding__c
            WHERE ArtifactSnapshot__c IN :snapshotIds
            AND IsBlocking__c = true
            GROUP BY ArtifactSnapshot__c
        ]) {
            Id snapId = (Id) ar.get('snapId');
            Integer count = (Integer) ar.get('cnt');
            blockingFindingsMap.put(snapId, count);
        }
        
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
            
            Integer blockingFindings = blockingFindingsMap.containsKey(snap.Id) 
                ? blockingFindingsMap.get(snap.Id) 
                : 0;
            
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
        return executePlanWithBackup(planId, false, new List<String>(), 'NoTestRun');
    }
    
    @AuraEnabled
    public static String executePlanWithBackup(String planId, Boolean createBackup, List<String> selectedItemIds, String testLevel) {
        return executePlanWithOptions(planId, createBackup, selectedItemIds, testLevel, null);
    }
    
    @AuraEnabled
    public static String executePlanWithOptions(String planId, Boolean createBackup, List<String> selectedItemIds, String testLevel, Boolean validateOnlyOverride) {
        ChangePlan__c plan = [
            SELECT Id, Status__c, ValidationMode__c, TestPolicy__c, TargetApiVersion__c
            FROM ChangePlan__c 
            WHERE Id = :planId
        ];
        
        if (plan.Status__c != 'Draft' && plan.Status__c != 'Ready' && plan.Status__c != 'Validated') {
            throw new AuraHandledException('Plan cannot be executed in status: ' + plan.Status__c);
        }
        
        Boolean validateOnly;
        if (validateOnlyOverride != null) {
            validateOnly = validateOnlyOverride;
            if (plan.ValidationMode__c != (validateOnly ? 'ValidateOnly' : 'Deploy')) {
                plan.ValidationMode__c = validateOnly ? 'ValidateOnly' : 'Deploy';
                update plan;
            }
        } else {
            validateOnly = plan.ValidationMode__c == 'ValidateOnly';
        }
        
        String effectiveTestLevel = String.isBlank(testLevel) ? 'NoTestRun' : testLevel;
        
        DeploymentRun__c run = new DeploymentRun__c(
            ChangePlan__c = planId,
            Status__c = 'Queued',
            StartedAt__c = Datetime.now(),
            ValidateOnly__c = validateOnly,
            TestPolicy__c = effectiveTestLevel
        );
        insert run;
        
        if (createBackup) {
            if (selectedItemIds == null || selectedItemIds.isEmpty()) {
                throw new AuraHandledException('Backup requested but no items were selected. Please select items and validate before deploying.');
            }
            try {
                BackupService.createBackupForSelectedItems(run.Id, selectedItemIds);
            } catch (Exception e) {
                throw new AuraHandledException('Backup creation failed: ' + e.getMessage());
            }
        }
        
        plan.Status__c = 'Executing';
        update plan;
        
        logAuditEvent('DeploymentStarted', new Map<String, Object>{
            'planId' => planId,
            'runId' => run.Id,
            'validateOnly' => validateOnly,
            'backupCreated' => createBackup,
            'selectedItemCount' => selectedItemIds != null ? selectedItemIds.size() : 0,
            'testLevel' => effectiveTestLevel
        });
        
        System.enqueueJob(new DeploymentQueueable(run.Id, planId, selectedItemIds, effectiveTestLevel));
        
        return run.Id;
    }
    
    @AuraEnabled
    public static void resetPlanForRetry(String planId) {
        ChangePlan__c plan = [
            SELECT Id, Status__c FROM ChangePlan__c WHERE Id = :planId
        ];
        
        // Allow reset from any non-Draft status
        if (plan.Status__c != 'Draft') {
            plan.Status__c = 'Draft';
            update plan;
        }
        
        // Always reset all items to Pending
        List<ChangeItem__c> items = [
            SELECT Id, ApplyStatus__c, ErrorDetails__c
            FROM ChangeItem__c
            WHERE ChangePlan__c = :planId
        ];
        
        for (ChangeItem__c item : items) {
            item.ApplyStatus__c = 'Pending';
            item.ErrorDetails__c = null;
        }
        
        if (!items.isEmpty()) {
            update items;
        }
    }
    
    @AuraEnabled
    public static Map<String, Object> validateSelectedItems(String planId, List<String> selectedItemIds) {
        Map<String, Object> result = new Map<String, Object>{
            'success' => false,
            'validatedIds' => new List<String>(),
            'errors' => new Map<String, String>(),
            'message' => ''
        };
        
        if (selectedItemIds == null || selectedItemIds.isEmpty()) {
            result.put('message', 'No items selected for validation');
            return result;
        }
        
        ChangePlan__c plan = [
            SELECT Id, TargetApiVersion__c
            FROM ChangePlan__c
            WHERE Id = :planId
        ];
        
        Decimal targetVersion = Decimal.valueOf(plan.TargetApiVersion__c);
        
        List<ChangeItem__c> itemsToValidate = [
            SELECT Id, ArtifactType__c, FullName__c, CurrentApiVersion__c, TargetApiVersion__c
            FROM ChangeItem__c
            WHERE Id IN :selectedItemIds
            AND Eligibility__c = 'Eligible'
            ORDER BY UnitNumber__c
        ];
        
        if (itemsToValidate.isEmpty()) {
            result.put('message', 'No eligible items found for validation');
            return result;
        }
        
        Map<String, List<ChangeItem__c>> itemsByType = new Map<String, List<ChangeItem__c>>();
        for (ChangeItem__c item : itemsToValidate) {
            if (!itemsByType.containsKey(item.ArtifactType__c)) {
                itemsByType.put(item.ArtifactType__c, new List<ChangeItem__c>());
            }
            itemsByType.get(item.ArtifactType__c).add(item);
        }
        
        List<String> validatedIds = new List<String>();
        Map<String, String> errorMap = new Map<String, String>();
        
        ValidationHelper helper = new ValidationHelper();
        
        for (String artifactType : itemsByType.keySet()) {
            List<ChangeItem__c> typeItems = itemsByType.get(artifactType);
            
            if (!helper.isSupportedType(artifactType)) {
                for (ChangeItem__c item : typeItems) {
                    errorMap.put(item.Id, 'Unsupported artifact type: ' + artifactType);
                }
                continue;
            }
            
            try {
                String containerId = helper.createContainer();
                Map<String, String> addErrors = new Map<String, String>();
                
                for (ChangeItem__c item : typeItems) {
                    try {
                        helper.addMember(containerId, artifactType, item.FullName__c, targetVersion);
                    } catch (Exception e) {
                        addErrors.put(item.Id, e.getMessage());
                    }
                }
                
                errorMap.putAll(addErrors);
                
                List<ChangeItem__c> pendingItems = new List<ChangeItem__c>();
                for (ChangeItem__c item : typeItems) {
                    if (!addErrors.containsKey(item.Id)) {
                        pendingItems.add(item);
                    }
                }
                
                if (!pendingItems.isEmpty()) {
                    String asyncRequestId = helper.deployForValidation(containerId);
                    Map<String, Object> deployResult = helper.pollAndGetResults(asyncRequestId);
                    
                    String status = (String) deployResult.get('status');
                    
                    if (status == 'Completed') {
                        for (ChangeItem__c item : pendingItems) {
                            validatedIds.add(item.Id);
                        }
                    } else if (status == 'Failed' || status == 'Error') {
                        String errorDetail = (String) deployResult.get('errorDetail');
                        Map<String, String> componentErrors = helper.parseComponentErrors(asyncRequestId);
                        
                        for (ChangeItem__c item : pendingItems) {
                            String componentError = componentErrors.get(item.FullName__c);
                            if (String.isNotBlank(componentError)) {
                                errorMap.put(item.Id, componentError);
                            } else if (String.isNotBlank(errorDetail)) {
                                errorMap.put(item.Id, errorDetail);
                            } else {
                                errorMap.put(item.Id, 'Validation failed');
                            }
                        }
                    } else {
                        for (ChangeItem__c item : pendingItems) {
                            errorMap.put(item.Id, 'Validation timed out. Status: ' + status);
                        }
                    }
                }
                
            } catch (Exception e) {
                for (ChangeItem__c item : typeItems) {
                    if (!errorMap.containsKey(item.Id)) {
                        errorMap.put(item.Id, e.getMessage());
                    }
                }
            }
        }
        
        result.put('success', errorMap.isEmpty());
        result.put('validatedIds', validatedIds);
        result.put('errors', errorMap);
        result.put('message', errorMap.isEmpty() 
            ? 'All ' + validatedIds.size() + ' items validated successfully' 
            : validatedIds.size() + ' validated, ' + errorMap.size() + ' with errors');
        
        return result;
    }
    
    public class ValidationHelper {
        
        public Boolean isSupportedType(String artifactType) {
            return artifactType == 'ApexClass' || 
                   artifactType == 'ApexTrigger' || 
                   artifactType == 'ApexPage' || 
                   artifactType == 'ApexComponent';
        }
        
        public String createContainer() {
            String endpoint = URL.getOrgDomainUrl().toExternalForm() + 
                '/services/data/v65.0/tooling/sobjects/MetadataContainer';
            
            Map<String, Object> container = new Map<String, Object>{
                'Name' => 'Validate_' + System.currentTimeMillis()
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
            
            throw new DeploymentException('Failed to create validation container: ' + res.getBody());
        }
        
        public void addMember(String containerId, String artifactType, String fullName, Decimal targetVersion) {
            String memberType = getMemberType(artifactType);
            String contentEntityId = getContentEntityId(artifactType, fullName);
            
            if (String.isBlank(contentEntityId)) {
                throw new DeploymentException('Component not found: ' + fullName);
            }
            
            String currentBody = getComponentBody(artifactType, fullName);
            
            if (String.isBlank(currentBody)) {
                throw new DeploymentException('Could not retrieve body for: ' + fullName);
            }
            
            String endpoint = URL.getOrgDomainUrl().toExternalForm() + 
                '/services/data/v65.0/tooling/sobjects/' + memberType;
            
            Map<String, Object> metadata = buildMetadataForType(artifactType, targetVersion, fullName);
            
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
                String errorMsg = parseErrorMessage(res.getBody());
                throw new DeploymentException('Add member failed: ' + errorMsg);
            }
        }
        
        private String getMemberType(String artifactType) {
            if (artifactType == 'ApexClass') return 'ApexClassMember';
            if (artifactType == 'ApexTrigger') return 'ApexTriggerMember';
            if (artifactType == 'ApexPage') return 'ApexPageMember';
            if (artifactType == 'ApexComponent') return 'ApexComponentMember';
            throw new DeploymentException('Unsupported artifact type: ' + artifactType);
        }
        
        private String getContentEntityId(String artifactType, String fullName) {
            if (artifactType == 'ApexClass') {
                List<ApexClass> classes = [SELECT Id FROM ApexClass WHERE Name = :fullName LIMIT 1];
                return classes.isEmpty() ? null : classes[0].Id;
            } else if (artifactType == 'ApexTrigger') {
                List<ApexTrigger> triggers = [SELECT Id FROM ApexTrigger WHERE Name = :fullName LIMIT 1];
                return triggers.isEmpty() ? null : triggers[0].Id;
            } else if (artifactType == 'ApexPage') {
                List<ApexPage> pages = [SELECT Id FROM ApexPage WHERE Name = :fullName LIMIT 1];
                return pages.isEmpty() ? null : pages[0].Id;
            } else if (artifactType == 'ApexComponent') {
                List<ApexComponent> components = [SELECT Id FROM ApexComponent WHERE Name = :fullName LIMIT 1];
                return components.isEmpty() ? null : components[0].Id;
            }
            return null;
        }
        
        private String getComponentBody(String artifactType, String fullName) {
            if (artifactType == 'ApexClass') {
                List<ApexClass> classes = [SELECT Body FROM ApexClass WHERE Name = :fullName LIMIT 1];
                return classes.isEmpty() ? null : classes[0].Body;
            } else if (artifactType == 'ApexTrigger') {
                List<ApexTrigger> triggers = [SELECT Body FROM ApexTrigger WHERE Name = :fullName LIMIT 1];
                return triggers.isEmpty() ? null : triggers[0].Body;
            } else if (artifactType == 'ApexPage') {
                List<ApexPage> pages = [SELECT Markup FROM ApexPage WHERE Name = :fullName LIMIT 1];
                return pages.isEmpty() ? null : pages[0].Markup;
            } else if (artifactType == 'ApexComponent') {
                List<ApexComponent> comps = [SELECT Markup FROM ApexComponent WHERE Name = :fullName LIMIT 1];
                return comps.isEmpty() ? null : comps[0].Markup;
            }
            return null;
        }
        
        private Map<String, Object> buildMetadataForType(String artifactType, Decimal targetVersion, String fullName) {
            Map<String, Object> metadata = new Map<String, Object>{
                'apiVersion' => targetVersion
            };
            
            if (artifactType == 'ApexClass') {
                List<ApexClass> classes = [SELECT Status FROM ApexClass WHERE Name = :fullName LIMIT 1];
                metadata.put('status', classes.isEmpty() ? 'Active' : classes[0].Status);
            } else if (artifactType == 'ApexTrigger') {
                List<ApexTrigger> triggers = [SELECT Status FROM ApexTrigger WHERE Name = :fullName LIMIT 1];
                metadata.put('status', triggers.isEmpty() ? 'Active' : triggers[0].Status);
            } else if (artifactType == 'ApexPage') {
                metadata.put('label', fullName);
            } else if (artifactType == 'ApexComponent') {
                metadata.put('label', fullName);
            }
            
            return metadata;
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
        
        public String deployForValidation(String containerId) {
            String endpoint = URL.getOrgDomainUrl().toExternalForm() + 
                '/services/data/v65.0/tooling/sobjects/ContainerAsyncRequest';
            
            Map<String, Object> asyncRequest = new Map<String, Object>{
                'MetadataContainerId' => containerId,
                'IsCheckOnly' => true,
                'IsRunTests' => false
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
            
            throw new DeploymentException('Failed to start validation: ' + res.getBody());
        }
        
        public Map<String, Object> pollAndGetResults(String asyncRequestId) {
            String endpoint = URL.getOrgDomainUrl().toExternalForm() + 
                '/services/data/v65.0/tooling/sobjects/ContainerAsyncRequest/' + asyncRequestId;
            
            Integer maxAttempts = 30;
            Integer attempt = 0;
            String status = 'Queued';
            String errorDetail = '';
            
            while (attempt < maxAttempts && (status == 'Queued' || status == 'Pending')) {
                HttpRequest req = new HttpRequest();
                req.setEndpoint(endpoint);
                req.setMethod('GET');
                req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
                req.setHeader('Content-Type', 'application/json');
                
                Http http = new Http();
                HttpResponse res = http.send(req);
                
                if (res.getStatusCode() == 200) {
                    Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                    status = (String) result.get('State');
                    
                    if (status == 'Failed' || status == 'Error') {
                        errorDetail = (String) result.get('ErrorMsg');
                        break;
                    }
                    
                    if (status == 'Completed') {
                        break;
                    }
                }
                
                attempt++;
            }
            
            return new Map<String, Object>{
                'status' => status,
                'errorDetail' => errorDetail
            };
        }
        
        public Map<String, String> parseComponentErrors(String asyncRequestId) {
            Map<String, String> componentErrors = new Map<String, String>();
            
            try {
                String endpoint = URL.getOrgDomainUrl().toExternalForm() + 
                    '/services/data/v65.0/tooling/query/?q=' +
                    EncodingUtil.urlEncode(
                        'SELECT ContentEntity.Name, CompilerErrors FROM ApexClassMember ' +
                        'WHERE MetadataContainerId IN (SELECT MetadataContainerId FROM ContainerAsyncRequest WHERE Id = \'' + asyncRequestId + '\')',
                        'UTF-8'
                    );
                
                HttpRequest req = new HttpRequest();
                req.setEndpoint(endpoint);
                req.setMethod('GET');
                req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
                req.setHeader('Content-Type', 'application/json');
                
                Http http = new Http();
                HttpResponse res = http.send(req);
                
                if (res.getStatusCode() == 200) {
                    Map<String, Object> queryResult = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                    List<Object> records = (List<Object>) queryResult.get('records');
                    
                    if (records != null) {
                        for (Object record : records) {
                            Map<String, Object> rec = (Map<String, Object>) record;
                            String compilerErrors = (String) rec.get('CompilerErrors');
                            
                            if (String.isNotBlank(compilerErrors) && compilerErrors != '[]' && compilerErrors != 'null') {
                                Map<String, Object> contentEntity = (Map<String, Object>) rec.get('ContentEntity');
                                if (contentEntity != null) {
                                    String componentName = (String) contentEntity.get('Name');
                                    String parsedError = parseCompilerError(compilerErrors);
                                    componentErrors.put(componentName, parsedError);
                                }
                            }
                        }
                    }
                }
            } catch (Exception e) {
                System.debug('Error parsing component errors: ' + e.getMessage());
            }
            
            return componentErrors;
        }
        
        private String parseCompilerError(String compilerErrorsJson) {
            try {
                List<Object> errors = (List<Object>) JSON.deserializeUntyped(compilerErrorsJson);
                if (!errors.isEmpty()) {
                    List<String> errorMessages = new List<String>();
                    for (Object err : errors) {
                        Map<String, Object> errorObj = (Map<String, Object>) err;
                        String problem = (String) errorObj.get('problem');
                        Object lineObj = errorObj.get('line');
                        if (String.isNotBlank(problem)) {
                            String msg = problem;
                            if (lineObj != null) {
                                msg = 'Line ' + String.valueOf(lineObj) + ': ' + problem;
                            }
                            errorMessages.add(msg);
                        }
                    }
                    return String.join(errorMessages, '; ');
                }
            } catch (Exception e) {
                return compilerErrorsJson;
            }
            return '';
        }
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
        private List<String> selectedItemIds;
        private String testLevel;
        
        public DeploymentQueueable(String runId, String planId, List<String> selectedItemIds, String testLevel) {
            this.runId = runId;
            this.planId = planId;
            this.selectedItemIds = selectedItemIds != null ? selectedItemIds : new List<String>();
            this.testLevel = String.isBlank(testLevel) ? 'NoTestRun' : testLevel;
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
            ChangePlan__c planRecord = [
                SELECT Id, TargetApiVersion__c, ValidationMode__c
                FROM ChangePlan__c
                WHERE Id = :planId
            ];
            
            Boolean isValidateOnly = planRecord.ValidationMode__c == 'ValidateOnly';
            Decimal targetVersion = Decimal.valueOf(planRecord.TargetApiVersion__c);
            
            System.debug('Processing Deployment - ValidationMode: ' + planRecord.ValidationMode__c + 
                        ', IsValidateOnly: ' + isValidateOnly + 
                        ', TargetVersion: ' + targetVersion);
            
            List<ChangeItem__c> itemsToProcess;
            
            // Only process explicitly selected items - never fall back to all items
            if (selectedItemIds != null && !selectedItemIds.isEmpty()) {
                itemsToProcess = [
                    SELECT Id, ArtifactType__c, FullName__c, CurrentApiVersion__c, 
                           TargetApiVersion__c, ApplyStatus__c
                    FROM ChangeItem__c
                    WHERE Id IN :selectedItemIds
                    AND Eligibility__c = 'Eligible'
                    ORDER BY UnitNumber__c
                ];
            } else {
                // No items selected - complete without processing
                itemsToProcess = new List<ChangeItem__c>();
            }
            
            // Handle empty case - no callouts so DML is safe
            if (itemsToProcess.isEmpty()) {
                DeploymentRun__c emptyRun = new DeploymentRun__c(
                    Id = runId,
                    Status__c = 'Completed',
                    FinishedAt__c = Datetime.now(),
                    ResultsJson__c = JSON.serialize(new Map<String, Object>{
                        'successCount' => 0,
                        'failCount' => 0,
                        'totalProcessed' => 0,
                        'message' => 'No eligible items to process'
                    })
                );
                update emptyRun;
                return;
            }
            
            Integer successCount = 0;
            Integer failCount = 0;
            List<String> errorMessages = new List<String>();
            
            Map<String, List<ChangeItem__c>> itemsByType = new Map<String, List<ChangeItem__c>>();
            for (ChangeItem__c item : itemsToProcess) {
                if (!itemsByType.containsKey(item.ArtifactType__c)) {
                    itemsByType.put(item.ArtifactType__c, new List<ChangeItem__c>());
                }
                itemsByType.get(item.ArtifactType__c).add(item);
            }
            
            for (String artifactType : itemsByType.keySet()) {
                List<ChangeItem__c> typeItems = itemsByType.get(artifactType);
                
                if (!isSupportedArtifactType(artifactType)) {
                    for (ChangeItem__c item : typeItems) {
                        item.ApplyStatus__c = 'Failed';
                        item.ErrorDetails__c = 'Unsupported artifact type: ' + artifactType;
                        failCount++;
                    }
                    continue;
                }
                
                try {
                    String containerId = createMetadataContainer();
                    
                    for (ChangeItem__c item : typeItems) {
                        try {
                            addMemberToContainer(containerId, item.ArtifactType__c, 
                                                 item.FullName__c, targetVersion);
                            item.ApplyStatus__c = 'Pending';
                        } catch (Exception e) {
                            item.ApplyStatus__c = 'Failed';
                            item.ErrorDetails__c = e.getMessage();
                            failCount++;
                            errorMessages.add(item.FullName__c + ': ' + e.getMessage());
                        }
                    }
                    
                    List<ChangeItem__c> pendingItems = new List<ChangeItem__c>();
                    for (ChangeItem__c item : typeItems) {
                        if (item.ApplyStatus__c == 'Pending') {
                            pendingItems.add(item);
                        }
                    }
                    
                    if (!pendingItems.isEmpty()) {
                        String asyncRequestId = deployContainer(containerId, isValidateOnly, this.testLevel);
                        
                        String status = pollForCompletion(asyncRequestId);
                        
                        if (status == 'Completed') {
                            for (ChangeItem__c item : pendingItems) {
                                Decimal actualVersion = verifyArtifactApiVersion(item.FullName__c, artifactType);
                                if (actualVersion != null && actualVersion == targetVersion) {
                                    item.ApplyStatus__c = 'Applied';
                                    successCount++;
                                } else if (actualVersion != null) {
                                    item.ApplyStatus__c = 'Failed';
                                    item.ErrorDetails__c = 'Deployment reported success but API version is still ' + actualVersion + ' (expected ' + targetVersion + ')';
                                    failCount++;
                                    errorMessages.add(item.FullName__c + ': Version not updated - still at ' + actualVersion);
                                } else {
                                    item.ApplyStatus__c = 'Applied';
                                    successCount++;
                                }
                            }
                        } else if (status == 'Failed' || status == 'Error') {
                            String errorDetail = getContainerErrorDetails(asyncRequestId);
                            for (ChangeItem__c item : pendingItems) {
                                item.ApplyStatus__c = 'Failed';
                                item.ErrorDetails__c = errorDetail;
                                failCount++;
                            }
                            errorMessages.add('Container deployment failed: ' + errorDetail);
                        } else {
                            for (ChangeItem__c item : pendingItems) {
                                item.ApplyStatus__c = 'Failed';
                                item.ErrorDetails__c = 'Deployment timed out. Status: ' + status;
                                failCount++;
                            }
                            errorMessages.add('Deployment timed out with status: ' + status);
                        }
                    }
                    
                } catch (Exception e) {
                    for (ChangeItem__c item : typeItems) {
                        if (item.ApplyStatus__c != 'Failed') {
                            item.ApplyStatus__c = 'Failed';
                            item.ErrorDetails__c = e.getMessage();
                            failCount++;
                        }
                    }
                    errorMessages.add('Container error for ' + artifactType + ': ' + e.getMessage());
                }
            }
            
            // ALL DML happens AFTER callouts to avoid "uncommitted work pending" error
            if (!itemsToProcess.isEmpty()) {
                update itemsToProcess;
            }
            
            Map<String, Object> resultsMap = new Map<String, Object>{
                'successCount' => successCount,
                'failCount' => failCount,
                'totalProcessed' => itemsToProcess.size(),
                'validationMode' => planRecord.ValidationMode__c,
                'wasValidateOnly' => isValidateOnly,
                'targetApiVersion' => targetVersion
            };
            
            if (!errorMessages.isEmpty()) {
                resultsMap.put('errors', errorMessages);
            }
            
            DeploymentRun__c run = new DeploymentRun__c(
                Id = runId,
                Status__c = failCount == 0 ? 'Completed' : 'Failed',
                FinishedAt__c = Datetime.now(),
                ResultsJson__c = JSON.serialize(resultsMap)
            );
            update run;
            
            ChangePlan__c plan = new ChangePlan__c(
                Id = planId,
                Status__c = failCount == 0 ? 'Deployed' : 'Failed'
            );
            update plan;
        }
        
        private Boolean isSupportedArtifactType(String artifactType) {
            return artifactType == 'ApexClass' || 
                   artifactType == 'ApexTrigger' || 
                   artifactType == 'ApexPage' || 
                   artifactType == 'ApexComponent';
        }
        
        private String createMetadataContainer() {
            String endpoint = URL.getOrgDomainUrl().toExternalForm() + 
                '/services/data/v65.0/tooling/sobjects/MetadataContainer';
            
            Map<String, Object> container = new Map<String, Object>{
                'Name' => 'ApiUpdate_' + System.currentTimeMillis()
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
            
            throw new DeploymentException('Failed to create metadata container: ' + res.getBody());
        }
        
        private void addMemberToContainer(String containerId, String artifactType, 
                                          String fullName, Decimal targetVersion) {
            String memberType = getMemberType(artifactType);
            String contentEntityId = getContentEntityId(artifactType, fullName);
            
            if (String.isBlank(contentEntityId)) {
                throw new DeploymentException('Component not found: ' + fullName);
            }
            
            String currentBody = getComponentBody(artifactType, fullName);
            
            if (String.isBlank(currentBody)) {
                throw new DeploymentException('Could not retrieve body for: ' + fullName);
            }
            
            // Get current API version for the header comment
            Decimal currentVersion = getCurrentApiVersion(artifactType, fullName);
            
            // Update the body with header comments documenting the API version change
            String updatedBody = updateHeaderComments(currentBody, currentVersion, targetVersion, artifactType);
            
            String endpoint = URL.getOrgDomainUrl().toExternalForm() + 
                '/services/data/v65.0/tooling/sobjects/' + memberType;
            
            Map<String, Object> metadata = buildMetadataForType(artifactType, targetVersion, fullName);
            
            Map<String, Object> member = new Map<String, Object>{
                'MetadataContainerId' => containerId,
                'ContentEntityId' => contentEntityId,
                'Body' => updatedBody,
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
            
            System.debug('AddMember Response: ' + res.getStatusCode() + ' - ' + res.getBody());
            
            if (res.getStatusCode() != 201) {
                String errorMsg = parseErrorMessage(res.getBody());
                throw new DeploymentException('Add member failed (' + res.getStatusCode() + '): ' + errorMsg);
            }
        }
        
        private Decimal getCurrentApiVersion(String artifactType, String fullName) {
            try {
                if (artifactType == 'ApexClass') {
                    List<ApexClass> classes = [SELECT ApiVersion FROM ApexClass WHERE Name = :fullName LIMIT 1];
                    return classes.isEmpty() ? null : classes[0].ApiVersion;
                } else if (artifactType == 'ApexTrigger') {
                    List<ApexTrigger> triggers = [SELECT ApiVersion FROM ApexTrigger WHERE Name = :fullName LIMIT 1];
                    return triggers.isEmpty() ? null : triggers[0].ApiVersion;
                } else if (artifactType == 'ApexPage') {
                    List<ApexPage> pages = [SELECT ApiVersion FROM ApexPage WHERE Name = :fullName LIMIT 1];
                    return pages.isEmpty() ? null : pages[0].ApiVersion;
                } else if (artifactType == 'ApexComponent') {
                    List<ApexComponent> comps = [SELECT ApiVersion FROM ApexComponent WHERE Name = :fullName LIMIT 1];
                    return comps.isEmpty() ? null : comps[0].ApiVersion;
                }
            } catch (Exception e) {
                System.debug('Error getting current API version: ' + e.getMessage());
            }
            return null;
        }
        
        private String updateHeaderComments(String body, Decimal fromVersion, Decimal toVersion, String artifactType) {
            if (String.isBlank(body)) {
                return body;
            }
            
            // Only update Apex code (classes, triggers) - not VF pages/components
            if (artifactType != 'ApexClass' && artifactType != 'ApexTrigger') {
                return body;
            }
            
            String currentDate = Date.today().format();
            String currentUser = UserInfo.getName();
            String versionUpdateNote = 'API version updated from ' + 
                (fromVersion != null ? String.valueOf(fromVersion) : 'unknown') + 
                ' to ' + String.valueOf(toVersion) + ' on ' + currentDate + ' by API Version Updater';
            
            // Check if there's an existing header comment block
            Pattern headerPattern = Pattern.compile('(?s)^\\s*/\\*\\*(.+?)\\*/');
            Matcher headerMatcher = headerPattern.matcher(body);
            
            if (headerMatcher.find()) {
                // Existing header found - update it
                String existingHeader = headerMatcher.group(0);
                String headerContent = headerMatcher.group(1);
                
                String updatedHeader = updateExistingHeader(headerContent, versionUpdateNote, currentDate, currentUser);
                return body.replaceFirst('(?s)^\\s*/\\*\\*(.+?)\\*/', '/**' + updatedHeader + '*/');
            } else {
                // No header found - add a new one
                String newHeader = '/**\n' +
                    ' * @description     : ' + versionUpdateNote + '\n' +
                    ' * @author          : ' + currentUser + '\n' +
                    ' * @last modified on  : ' + currentDate + '\n' +
                    ' * @last modified by  : ' + currentUser + '\n' +
                    ' */\n';
                return newHeader + body;
            }
        }
        
        private String updateExistingHeader(String headerContent, String versionUpdateNote, String currentDate, String currentUser) {
            List<String> lines = headerContent.split('\n');
            List<String> updatedLines = new List<String>();
            Boolean hasDescription = false;
            Boolean hasLastModifiedOn = false;
            Boolean hasLastModifiedBy = false;
            
            for (String line : lines) {
                String trimmedLine = line.trim();
                
                // Skip @group lines
                if (trimmedLine.contains('@group')) {
                    continue;
                }
                
                // Update @description
                if (trimmedLine.contains('@description')) {
                    hasDescription = true;
                    // Extract existing description and append version update
                    String existingDesc = '';
                    Integer colonIndex = trimmedLine.indexOf(':');
                    if (colonIndex > 0 && colonIndex < trimmedLine.length() - 1) {
                        existingDesc = trimmedLine.substring(colonIndex + 1).trim();
                    }
                    if (String.isNotBlank(existingDesc)) {
                        updatedLines.add(' * @description     : ' + existingDesc + '. ' + versionUpdateNote);
                    } else {
                        updatedLines.add(' * @description     : ' + versionUpdateNote);
                    }
                    continue;
                }
                
                // Update @last modified on
                if (trimmedLine.contains('@last modified on') || trimmedLine.contains('@lastmodifiedon')) {
                    hasLastModifiedOn = true;
                    updatedLines.add(' * @last modified on  : ' + currentDate);
                    continue;
                }
                
                // Update @last modified by
                if (trimmedLine.contains('@last modified by') || trimmedLine.contains('@lastmodifiedby')) {
                    hasLastModifiedBy = true;
                    updatedLines.add(' * @last modified by  : ' + currentUser);
                    continue;
                }
                
                // Keep other lines
                updatedLines.add(line);
            }
            
            // Add missing fields before the closing
            List<String> finalLines = new List<String>();
            for (Integer i = 0; i < updatedLines.size(); i++) {
                String line = updatedLines[i];
                finalLines.add(line);
                
                // If this is the last content line before closing, add missing fields
                if (i == updatedLines.size() - 1 || (i < updatedLines.size() - 1 && updatedLines[i + 1].trim() == '')) {
                    if (!hasDescription) {
                        finalLines.add(' * @description     : ' + versionUpdateNote);
                    }
                    if (!hasLastModifiedOn) {
                        finalLines.add(' * @last modified on  : ' + currentDate);
                    }
                    if (!hasLastModifiedBy) {
                        finalLines.add(' * @last modified by  : ' + currentUser);
                    }
                }
            }
            
            return String.join(finalLines, '\n');
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
                // Fall through to default
            }
            return responseBody;
        }
        
        private String deployContainer(String containerId, Boolean isCheckOnly, String testLevelParam) {
            String endpoint = URL.getOrgDomainUrl().toExternalForm() + 
                '/services/data/v65.0/tooling/sobjects/ContainerAsyncRequest';
            
            Boolean runTests = testLevelParam != 'NoTestRun';
            
            System.debug('DeployContainer - IsCheckOnly: ' + isCheckOnly + ', RunTests: ' + runTests);
            
            Map<String, Object> asyncRequest = new Map<String, Object>{
                'MetadataContainerId' => containerId,
                'IsCheckOnly' => isCheckOnly,
                'IsRunTests' => runTests
            };
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('POST');
            req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
            req.setHeader('Content-Type', 'application/json');
            req.setBody(JSON.serialize(asyncRequest));
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            System.debug('DeployContainer Response: ' + res.getStatusCode() + ' - ' + res.getBody());
            
            if (res.getStatusCode() == 201) {
                Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                return (String) result.get('id');
            }
            
            throw new DeploymentException('Failed to deploy container (' + res.getStatusCode() + '): ' + res.getBody());
        }
        
        private String pollForCompletion(String asyncRequestId) {
            String endpoint = URL.getOrgDomainUrl().toExternalForm() + 
                '/services/data/v65.0/tooling/sobjects/ContainerAsyncRequest/' + asyncRequestId;
            
            Integer maxAttempts = 60;
            Integer attempt = 0;
            String status = 'Queued';
            
            while (attempt < maxAttempts && (status == 'Queued' || status == 'Pending')) {
                HttpRequest req = new HttpRequest();
                req.setEndpoint(endpoint);
                req.setMethod('GET');
                req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
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
                    throw new DeploymentException('Failed to poll deployment status: ' + res.getBody());
                }
            }
            
            return status;
        }
        
        private String getContainerErrorDetails(String asyncRequestId) {
            String endpoint = URL.getOrgDomainUrl().toExternalForm() + 
                '/services/data/v65.0/tooling/sobjects/ContainerAsyncRequest/' + asyncRequestId;
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
            req.setHeader('Content-Type', 'application/json');
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                
                String errorMsg = (String) result.get('ErrorMsg');
                if (String.isNotBlank(errorMsg)) {
                    return errorMsg;
                }
                
                Object deployDetails = result.get('DeployDetails');
                if (deployDetails != null) {
                    return JSON.serialize(deployDetails);
                }
                
                return 'Deployment failed without details';
            }
            
            return 'Failed to retrieve error details';
        }
        
        private Map<String, Object> buildMetadataForType(String artifactType, Decimal targetVersion, String fullName) {
            Map<String, Object> metadata = new Map<String, Object>();
            metadata.put('apiVersion', Double.valueOf(targetVersion));
            
            switch on artifactType {
                when 'ApexClass', 'ApexTrigger' {
                    metadata.put('status', 'Active');
                }
                when 'ApexPage' {
                    List<ApexPage> pages = [SELECT Name, Description FROM ApexPage WHERE Name = :fullName LIMIT 1];
                    if (!pages.isEmpty()) {
                        metadata.put('label', pages[0].Name);
                        if (String.isNotBlank(pages[0].Description)) {
                            metadata.put('description', pages[0].Description);
                        }
                    } else {
                        metadata.put('label', fullName);
                    }
                }
                when 'ApexComponent' {
                    List<ApexComponent> components = [SELECT Name, Description FROM ApexComponent WHERE Name = :fullName LIMIT 1];
                    if (!components.isEmpty()) {
                        metadata.put('label', components[0].Name);
                        if (String.isNotBlank(components[0].Description)) {
                            metadata.put('description', components[0].Description);
                        }
                    } else {
                        metadata.put('label', fullName);
                    }
                }
            }
            
            return metadata;
        }
        
        private String getMemberType(String artifactType) {
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
                    throw new DeploymentException('Unsupported artifact type: ' + artifactType);
                }
            }
        }
        
        private String getContentEntityId(String artifactType, String fullName) {
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
        
        private String getComponentBody(String artifactType, String fullName) {
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
        
        private Decimal verifyArtifactApiVersion(String fullName, String artifactType) {
            String objectName;
            switch on artifactType {
                when 'ApexClass' {
                    objectName = 'ApexClass';
                }
                when 'ApexTrigger' {
                    objectName = 'ApexTrigger';
                }
                when 'ApexPage' {
                    objectName = 'ApexPage';
                }
                when 'ApexComponent' {
                    objectName = 'ApexComponent';
                }
                when else {
                    return null;
                }
            }
            
            String endpoint = URL.getOrgDomainUrl().toExternalForm() + 
                '/services/data/v65.0/tooling/query/?q=' +
                EncodingUtil.urlEncode('SELECT ApiVersion FROM ' + objectName + ' WHERE Name = \'' + fullName + '\' LIMIT 1', 'UTF-8');
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
            req.setHeader('Content-Type', 'application/json');
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            System.debug('VerifyApiVersion for ' + artifactType + ':' + fullName + ': ' + res.getStatusCode() + ' - ' + res.getBody());
            
            if (res.getStatusCode() == 200) {
                Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                List<Object> records = (List<Object>) response.get('records');
                if (!records.isEmpty()) {
                    Map<String, Object> record = (Map<String, Object>) records[0];
                    Object apiVersion = record.get('ApiVersion');
                    if (apiVersion != null) {
                        return Decimal.valueOf(String.valueOf(apiVersion));
                    }
                }
            }
            return null;
        }
    }
    
    public static void markItemsAsManuallyDeployed(List<Id> itemIds) {
        if (itemIds == null || itemIds.isEmpty()) {
            return;
        }
        
        List<ChangeItem__c> items = [
            SELECT Id, ApplyStatus__c, ErrorDetails__c, ChangePlan__c
            FROM ChangeItem__c
            WHERE Id IN :itemIds
        ];
        
        Set<Id> planIds = new Set<Id>();
        for (ChangeItem__c item : items) {
            item.ApplyStatus__c = 'Applied';
            item.ErrorDetails__c = 'Manually deployed by user';
            if (item.ChangePlan__c != null) {
                planIds.add(item.ChangePlan__c);
            }
        }
        
        if (!items.isEmpty()) {
            update items;
        }
        
        for (Id planId : planIds) {
            updatePlanStatusAfterDeployment(planId);
        }
    }
    
    private static void updatePlanStatusAfterDeployment(Id planId) {
        List<ChangeItem__c> allItems = [
            SELECT Id, ApplyStatus__c
            FROM ChangeItem__c
            WHERE ChangePlan__c = :planId
        ];
        
        Integer appliedCount = 0;
        Integer failedCount = 0;
        Integer totalCount = allItems.size();
        
        for (ChangeItem__c item : allItems) {
            if (item.ApplyStatus__c == 'Applied') {
                appliedCount++;
            } else if (item.ApplyStatus__c == 'Failed') {
                failedCount++;
            }
        }
        
        String newStatus;
        if (appliedCount == totalCount) {
            newStatus = 'Completed';
        } else if (appliedCount > 0) {
            newStatus = 'PartiallyCompleted';
        } else if (failedCount == totalCount) {
            newStatus = 'Failed';
        } else {
            newStatus = 'InProgress';
        }
        
        ChangePlan__c plan = new ChangePlan__c(
            Id = planId,
            Status__c = newStatus
        );
        update plan;
    }
}
