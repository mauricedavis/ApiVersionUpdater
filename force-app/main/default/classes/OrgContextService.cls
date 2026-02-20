public with sharing class OrgContextService {
    
    public class OrgContextDto {
        @AuraEnabled public String orgId;
        @AuraEnabled public String orgName;
        @AuraEnabled public String instanceName;
        @AuraEnabled public Boolean isSandbox;
        @AuraEnabled public String namespacePrefix;
        @AuraEnabled public String apiVersion;
        @AuraEnabled public String userId;
        @AuraEnabled public String userName;
        @AuraEnabled public Boolean hasAnalyzerAccess;
        @AuraEnabled public Boolean hasDeployerAccess;
        @AuraEnabled public Boolean isWriteModeEnabled;
    }
    
    @AuraEnabled(cacheable=true)
    public static OrgContextDto getOrgContext() {
        OrgContextDto ctx = new OrgContextDto();
        
        Organization org = [
            SELECT Id, Name, InstanceName, IsSandbox, NamespacePrefix 
            FROM Organization 
            LIMIT 1
        ];
        
        ctx.orgId = org.Id;
        ctx.orgName = org.Name;
        ctx.instanceName = org.InstanceName;
        ctx.isSandbox = org.IsSandbox;
        ctx.namespacePrefix = org.NamespacePrefix;
        ctx.apiVersion = getCurrentApiVersion();
        ctx.userId = UserInfo.getUserId();
        ctx.userName = UserInfo.getUserName();
        ctx.hasAnalyzerAccess = checkAnalyzerAccess();
        ctx.hasDeployerAccess = checkDeployerAccess();
        ctx.isWriteModeEnabled = getWriteModeEnabled();
        
        return ctx;
    }
    
    private static String getCurrentApiVersion() {
        return '65.0';
    }
    
    private static Boolean checkAnalyzerAccess() {
        return FeatureManagement.checkPermission('Analyzer') || 
               checkDeployerAccess();
    }
    
    private static Boolean checkDeployerAccess() {
        return FeatureManagement.checkPermission('Deployer_Admin') ||
               hasModifyMetadataPermission();
    }
    
    private static Boolean hasModifyMetadataPermission() {
        return [
            SELECT Id 
            FROM PermissionSetAssignment 
            WHERE AssigneeId = :UserInfo.getUserId() 
            AND PermissionSet.PermissionsModifyMetadata = true
            LIMIT 1
        ].size() > 0;
    }
    
    private static Boolean getWriteModeEnabled() {
        List<AuditEvent__c> events = [
            SELECT EventType__c 
            FROM AuditEvent__c 
            WHERE EventType__c IN ('WriteModeEnabled', 'WriteModeDisabled')
            ORDER BY Timestamp__c DESC 
            LIMIT 1
        ];
        
        if (events.isEmpty()) {
            return false;
        }
        return events[0].EventType__c == 'WriteModeEnabled';
    }
    
    @AuraEnabled
    public static void setWriteModeEnabled(Boolean enabled) {
        if (!checkDeployerAccess()) {
            throw new AuraHandledException('Insufficient permissions to change write mode');
        }
        
        AuditEvent__c event = new AuditEvent__c(
            EventType__c = enabled ? 'WriteModeEnabled' : 'WriteModeDisabled',
            Actor__c = UserInfo.getUserId(),
            Timestamp__c = Datetime.now(),
            DetailsJson__c = JSON.serialize(new Map<String, Object>{
                'enabled' => enabled,
                'userAgent' => 'API Version Updater'
            })
        );
        insert event;
    }
}
