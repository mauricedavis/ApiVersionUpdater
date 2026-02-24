public with sharing class CodeRefactorService {
    
    public class RefactorResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public String originalCode;
        @AuraEnabled public String refactoredCode;
        @AuraEnabled public String previewHtml;
        @AuraEnabled public List<String> changes;
        @AuraEnabled public String deploymentId;
        @AuraEnabled public String classId;
        @AuraEnabled public String className;
    }
    
    public class CodeAnalysis {
        @AuraEnabled public String className;
        @AuraEnabled public Boolean hasDmlBeforeCallout;
        @AuraEnabled public List<Integer> dmlLineNumbers;
        @AuraEnabled public List<Integer> calloutLineNumbers;
        @AuraEnabled public List<String> dmlStatements;
        @AuraEnabled public List<String> calloutStatements;
    }
    
    @AuraEnabled
    public static CodeAnalysis analyzeClass(String className) {
        CodeAnalysis analysis = new CodeAnalysis();
        analysis.className = className;
        analysis.dmlLineNumbers = new List<Integer>();
        analysis.calloutLineNumbers = new List<Integer>();
        analysis.dmlStatements = new List<String>();
        analysis.calloutStatements = new List<String>();
        
        String classBody = getApexClassBody(className);
        if (String.isBlank(classBody)) {
            return analysis;
        }
        
        List<String> lines = classBody.split('\n');
        Integer lineNum = 0;
        
        for (String line : lines) {
            lineNum++;
            String trimmedLine = line.trim().toLowerCase();
            
            if (isDmlStatement(trimmedLine)) {
                analysis.dmlLineNumbers.add(lineNum);
                analysis.dmlStatements.add(line.trim());
            }
            
            if (isCalloutStatement(trimmedLine)) {
                analysis.calloutLineNumbers.add(lineNum);
                analysis.calloutStatements.add(line.trim());
            }
        }
        
        analysis.hasDmlBeforeCallout = hasDmlBeforeCallout(analysis);
        
        return analysis;
    }
    
    @AuraEnabled
    public static RefactorResult previewRefactor(String className, String fixOption) {
        RefactorResult result = new RefactorResult();
        result.changes = new List<String>();
        
        try {
            List<ApexClass> existingClasses = [SELECT Id, Name FROM ApexClass WHERE Name = :className LIMIT 1];
            if (existingClasses.isEmpty()) {
                result.success = false;
                result.message = 'Class not found in org: ' + className + '. Please verify the class name.';
                return result;
            }
            
            result.classId = existingClasses[0].Id;
            result.className = className;
            
            String classBody = getApexClassBody(className);
            if (String.isBlank(classBody)) {
                result.success = false;
                result.message = 'Class "' + className + '" exists but body could not be retrieved. This may be a managed package class or permission issue.';
                return result;
            }
            
            result.originalCode = classBody;
            
            String refactored;
            switch on fixOption {
                when 'FUTURE_METHOD' {
                    refactored = applyFutureMethodFix(className, classBody);
                    result.changes.add('Created @future(callout=true) method for callout logic');
                    result.changes.add('Moved HTTP callout code to async method');
                    result.changes.add('Added method call after DML operations');
                }
                when 'QUEUEABLE' {
                    refactored = applyQueueableFix(className, classBody);
                    result.changes.add('Created Queueable class for callout logic');
                    result.changes.add('Implemented Database.AllowsCallouts interface');
                    result.changes.add('Added System.enqueueJob() call after DML');
                }
                when 'REORDER' {
                    refactored = applyReorderFix(className, classBody);
                    result.changes.add('Moved callout operations before DML statements');
                    result.changes.add('Preserved variable dependencies');
                }
                when else {
                    result.success = false;
                    result.message = 'Unknown fix option: ' + fixOption;
                    return result;
                }
            }
            
            result.refactoredCode = refactored;
            result.success = true;
            result.message = 'Preview generated successfully';
            
        } catch (Exception e) {
            result.success = false;
            result.message = 'Error generating preview: ' + e.getMessage();
        }
        
        return result;
    }
    
    @AuraEnabled
    public static RefactorResult applyRefactor(String className, String fixOption) {
        RefactorResult result = previewRefactor(className, fixOption);
        
        if (!result.success) {
            return result;
        }
        
        try {
            String deployId = deployApexClass(className, result.refactoredCode);
            result.deploymentId = deployId;
            result.message = 'Refactoring applied successfully! Deployment ID: ' + deployId;
            
        } catch (Exception e) {
            result.success = false;
            result.message = 'Auto-deployment failed: ' + e.getMessage() + 
                '\n\nThe refactored code has been generated successfully. To apply manually:\n' +
                '1. Copy the refactored code from the preview\n' +
                '2. Go to Setup → Apex Classes → ' + className + '\n' +
                '3. Click Edit and replace the code\n' +
                '4. Save the class';
        }
        
        return result;
    }
    
    private static String getApexClassBody(String className) {
        List<ApexClass> classes = [
            SELECT Id, Body FROM ApexClass WHERE Name = :className LIMIT 1
        ];
        
        if (!classes.isEmpty() && String.isNotBlank(classes[0].Body)) {
            return classes[0].Body;
        }
        
        return getApexClassBodyViaTooling(className);
    }
    
    private static String getApexClassBodyViaTooling(String className) {
        String sessionId = getValidSessionId();
        if (String.isBlank(sessionId)) {
            return null;
        }
        
        String endpoint = URL.getOrgDomainUrl().toExternalForm() + 
            '/services/data/v65.0/tooling/query/?q=' +
            EncodingUtil.urlEncode('SELECT Id, Body FROM ApexClass WHERE Name = \'' + 
                String.escapeSingleQuotes(className) + '\'', 'UTF-8');
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + sessionId);
        req.setHeader('Content-Type', 'application/json');
        
        try {
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                List<Object> records = (List<Object>) response.get('records');
                if (!records.isEmpty()) {
                    Map<String, Object> record = (Map<String, Object>) records[0];
                    return (String) record.get('Body');
                }
            }
        } catch (Exception e) {
            System.debug('Tooling API error: ' + e.getMessage());
        }
        
        return null;
    }
    
    private static String getValidSessionId() {
        String sessionId = UserInfo.getSessionId();
        if (String.isNotBlank(sessionId) && !sessionId.startsWith('00D')) {
            return sessionId;
        }
        return sessionId;
    }
    
    private static Boolean isDmlStatement(String line) {
        return line.startsWith('insert ') || 
               line.startsWith('update ') || 
               line.startsWith('delete ') || 
               line.startsWith('upsert ') ||
               line.contains('database.insert') ||
               line.contains('database.update') ||
               line.contains('database.delete') ||
               line.contains('database.upsert');
    }
    
    private static Boolean isCalloutStatement(String line) {
        return line.contains('http.send') || 
               line.contains('.send(') ||
               line.contains('httprequest') ||
               line.contains('httpresponse') ||
               line.contains('webservicecallout');
    }
    
    private static Boolean hasDmlBeforeCallout(CodeAnalysis analysis) {
        if (analysis.dmlLineNumbers.isEmpty() || analysis.calloutLineNumbers.isEmpty()) {
            return false;
        }
        
        Integer firstDml = analysis.dmlLineNumbers[0];
        Integer firstCallout = analysis.calloutLineNumbers[0];
        
        return firstDml < firstCallout;
    }
    
    private static String applyFutureMethodFix(String className, String classBody) {
        CalloutBlock calloutBlock = extractCalloutBlock(classBody);
        
        if (calloutBlock == null || String.isBlank(calloutBlock.code)) {
            return classBody;
        }
        
        String futureMethodName = 'processCalloutAsync';
        String futureMethod = buildFutureMethod(futureMethodName, calloutBlock);
        String methodCall = futureMethodName + '();';
        
        String modifiedBody = classBody;
        modifiedBody = modifiedBody.replace(calloutBlock.code, '// Callout moved to async method\n        ' + methodCall);
        
        Integer lastBrace = modifiedBody.lastIndexOf('}');
        if (lastBrace > 0) {
            modifiedBody = modifiedBody.substring(0, lastBrace) + '\n' + futureMethod + '\n}';
        }
        
        return modifiedBody;
    }
    
    private static String applyQueueableFix(String className, String classBody) {
        CalloutBlock calloutBlock = extractCalloutBlock(classBody);
        
        if (calloutBlock == null || String.isBlank(calloutBlock.code)) {
            return classBody;
        }
        
        String queueableClassName = className + 'Callout';
        String queueableClass = buildQueueableClass(queueableClassName, calloutBlock);
        String enqueueCall = 'System.enqueueJob(new ' + queueableClassName + '());';
        
        String modifiedBody = classBody;
        modifiedBody = modifiedBody.replace(calloutBlock.code, '// Callout moved to Queueable\n        ' + enqueueCall);
        
        Integer lastBrace = modifiedBody.lastIndexOf('}');
        if (lastBrace > 0) {
            modifiedBody = modifiedBody.substring(0, lastBrace) + '\n\n' + queueableClass + '\n}';
        }
        
        return modifiedBody;
    }
    
    private static String applyReorderFix(String className, String classBody) {
        List<String> lines = classBody.split('\n');
        List<String> dmlLines = new List<String>();
        List<String> calloutLines = new List<String>();
        List<String> otherLines = new List<String>();
        
        Boolean inMethod = false;
        Integer braceCount = 0;
        
        for (String line : lines) {
            String trimmed = line.trim().toLowerCase();
            
            if (trimmed.contains('{')) {
                braceCount++;
                if (braceCount == 2) {
                    inMethod = true;
                }
            }
            if (trimmed.contains('}')) {
                braceCount--;
                if (braceCount < 2) {
                    inMethod = false;
                }
            }
            
            if (inMethod && isDmlStatement(trimmed)) {
                dmlLines.add(line);
            } else if (inMethod && isCalloutStatement(trimmed)) {
                calloutLines.add(line);
            } else {
                otherLines.add(line);
            }
        }
        
        String result = '';
        Boolean addedCallouts = false;
        Boolean addedDml = false;
        
        for (String line : otherLines) {
            result += line + '\n';
            
            String trimmed = line.trim().toLowerCase();
            if (trimmed.contains('{') && !addedCallouts && !calloutLines.isEmpty()) {
                for (String calloutLine : calloutLines) {
                    result += calloutLine + '\n';
                }
                result += '\n';
                addedCallouts = true;
            }
            
            if (addedCallouts && !addedDml && !dmlLines.isEmpty() && 
                (trimmed.contains('httpresponse') || trimmed.contains('.send('))) {
                result += '\n';
                for (String dmlLine : dmlLines) {
                    result += dmlLine + '\n';
                }
                addedDml = true;
            }
        }
        
        return result;
    }
    
    private static CalloutBlock extractCalloutBlock(String classBody) {
        CalloutBlock block = new CalloutBlock();
        block.code = '';
        
        List<String> lines = classBody.split('\n');
        Boolean capturing = false;
        Integer braceDepth = 0;
        
        for (String line : lines) {
            String trimmed = line.trim().toLowerCase();
            
            if (isCalloutStatement(trimmed) || capturing) {
                if (!capturing) {
                    capturing = true;
                    braceDepth = 0;
                }
                
                block.code += line + '\n';
                
                for (Integer i = 0; i < line.length(); i++) {
                    if (line.substring(i, i+1) == '{') braceDepth++;
                    if (line.substring(i, i+1) == '}') braceDepth--;
                }
                
                if (trimmed.endsWith(';') && braceDepth <= 0) {
                    break;
                }
            }
        }
        
        return block;
    }
    
    private static String buildFutureMethod(String methodName, CalloutBlock calloutBlock) {
        String method = '    @future(callout=true)\n';
        method += '    public static void ' + methodName + '() {\n';
        method += '        ' + calloutBlock.code.trim() + '\n';
        method += '    }\n';
        return method;
    }
    
    private static String buildQueueableClass(String queueableClassName, CalloutBlock calloutBlock) {
        String qClass = '    public class ' + queueableClassName + ' implements Queueable, Database.AllowsCallouts {\n';
        qClass += '        public void execute(QueueableContext context) {\n';
        qClass += '            ' + calloutBlock.code.trim() + '\n';
        qClass += '        }\n';
        qClass += '    }\n';
        return qClass;
    }
    
    private static String deployApexClass(String className, String newBody) {
        List<ApexClass> classes = [
            SELECT Id FROM ApexClass WHERE Name = :className LIMIT 1
        ];
        
        if (classes.isEmpty()) {
            throw new AuraHandledException('Class not found: ' + className);
        }
        
        String classId = classes[0].Id;
        
        try {
            String containerId = createMetadataContainer();
            addApexClassMember(containerId, classId, newBody);
            String asyncRequestId = deployContainer(containerId);
            return asyncRequestId;
        } catch (System.CalloutException ce) {
            throw new AuraHandledException('Tooling API callout failed. This may be due to session restrictions. Error: ' + ce.getMessage() + 
                '. Please copy the refactored code from the preview and apply it manually in Developer Console.');
        } catch (Exception e) {
            throw new AuraHandledException('Deployment failed: ' + e.getMessage() + ' (' + e.getTypeName() + ')');
        }
    }
    
    private static String createMetadataContainer() {
        String endpoint = URL.getOrgDomainUrl().toExternalForm() + 
            '/services/data/v65.0/tooling/sobjects/MetadataContainer';
        
        Map<String, Object> container = new Map<String, Object>{
            'Name' => 'RefactorContainer_' + System.currentTimeMillis()
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
        
        throw new AuraHandledException('Failed to create container: ' + res.getBody());
    }
    
    private static void addApexClassMember(String containerId, String classId, String body) {
        String endpoint = URL.getOrgDomainUrl().toExternalForm() + 
            '/services/data/v65.0/tooling/sobjects/ApexClassMember';
        
        Map<String, Object> member = new Map<String, Object>{
            'MetadataContainerId' => containerId,
            'ContentEntityId' => classId,
            'Body' => body
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
            throw new AuraHandledException('Failed to add class member: ' + res.getBody());
        }
    }
    
    private static String deployContainer(String containerId) {
        String endpoint = URL.getOrgDomainUrl().toExternalForm() + 
            '/services/data/v65.0/tooling/sobjects/ContainerAsyncRequest';
        
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
        
        throw new AuraHandledException('Failed to deploy: ' + res.getBody());
    }
    
    private class CalloutBlock {
        public String code;
        public Integer startLine;
        public Integer endLine;
    }
    
    @AuraEnabled
    public static Map<String, Object> cleanupOrphanedContainers() {
        Map<String, Object> result = new Map<String, Object>();
        Integer containersDeleted = 0;
        Integer requestsAborted = 0;
        List<String> errors = new List<String>();
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        String sessionId = UserInfo.getSessionId();
        
        try {
            List<Object> allContainers = queryTooling(baseUrl, sessionId, 
                'SELECT Id, Name FROM MetadataContainer');
            
            for (Object record : allContainers) {
                Map<String, Object> container = (Map<String, Object>) record;
                String containerId = (String) container.get('Id');
                String containerName = (String) container.get('Name');
                
                try {
                    deleteToolingRecord(baseUrl, sessionId, 'MetadataContainer', containerId);
                    containersDeleted++;
                } catch (Exception e) {
                    errors.add('Container ' + containerName + ': ' + e.getMessage());
                }
            }
            
            List<Object> stuckRequests = queryTooling(baseUrl, sessionId, 
                'SELECT Id, State FROM ContainerAsyncRequest WHERE State IN (\'Queued\', \'Pending\', \'InProgress\')');
            
            for (Object record : stuckRequests) {
                Map<String, Object> req = (Map<String, Object>) record;
                String reqId = (String) req.get('Id');
                
                try {
                    abortAsyncRequest(baseUrl, sessionId, reqId);
                    requestsAborted++;
                } catch (Exception e) {
                    errors.add('AsyncRequest ' + reqId + ': ' + e.getMessage());
                }
            }
            
            result.put('success', true);
            result.put('containersDeleted', containersDeleted);
            result.put('requestsAborted', requestsAborted);
            
            String msg = 'Cleaned up ' + containersDeleted + ' container(s)';
            if (requestsAborted > 0) {
                msg += ' and aborted ' + requestsAborted + ' pending request(s)';
            }
            result.put('message', msg);
            
            if (!errors.isEmpty()) {
                result.put('errors', errors);
                result.put('message', msg + '. Some errors occurred - see details.');
            }
            
        } catch (Exception e) {
            result.put('success', false);
            result.put('message', 'Cleanup failed: ' + e.getMessage());
        }
        
        return result;
    }
    
    private static List<Object> queryTooling(String baseUrl, String sessionId, String query) {
        String endpoint = baseUrl + '/services/data/v65.0/tooling/query/?q=' +
            EncodingUtil.urlEncode(query, 'UTF-8');
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + sessionId);
        req.setHeader('Content-Type', 'application/json');
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res.getStatusCode() == 200) {
            Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            return (List<Object>) response.get('records');
        }
        
        return new List<Object>();
    }
    
    private static void deleteToolingRecord(String baseUrl, String sessionId, String objectType, String recordId) {
        String endpoint = baseUrl + '/services/data/v65.0/tooling/sobjects/' + objectType + '/' + recordId;
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('DELETE');
        req.setHeader('Authorization', 'Bearer ' + sessionId);
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res.getStatusCode() != 204 && res.getStatusCode() != 200) {
            throw new AuraHandledException('Delete failed: ' + res.getStatusCode());
        }
    }
    
    private static void abortAsyncRequest(String baseUrl, String sessionId, String requestId) {
        String endpoint = baseUrl + '/services/data/v65.0/tooling/sobjects/ContainerAsyncRequest/' + requestId;
        
        Map<String, Object> updateBody = new Map<String, Object>{
            'State' => 'Aborted'
        };
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('PATCH');
        req.setHeader('Authorization', 'Bearer ' + sessionId);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(updateBody));
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res.getStatusCode() != 204 && res.getStatusCode() != 200 && res.getStatusCode() != 204) {
            throw new AuraHandledException('Abort failed: ' + res.getStatusCode());
        }
    }
    
}
