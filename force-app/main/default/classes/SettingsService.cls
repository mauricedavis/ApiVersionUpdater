public with sharing class SettingsService {
    
    private static final String SETTINGS_KEY = 'ApiVersionUpdater_Settings';
    
    public class SettingsDto {
        @AuraEnabled public List<String> includedTypes;
        @AuraEnabled public String scopePolicy;
        @AuraEnabled public String targetApiVersion;
        @AuraEnabled public Map<String, String> perTypeTargets;
        @AuraEnabled public String incrementPolicy;
        @AuraEnabled public Integer maxDeltaPerDeploy;
        @AuraEnabled public String baselineMode;
        @AuraEnabled public String contentRetention;
        @AuraEnabled public Boolean validateOnlyDefault;
        @AuraEnabled public String testPolicy;
        @AuraEnabled public Integer maxComponentsPerUnit;
        @AuraEnabled public Boolean enableRollbackStorage;
        
        public SettingsDto() {
            this.includedTypes = new List<String>{'ApexClass', 'ApexTrigger', 'ApexPage', 'ApexComponent'};
            this.scopePolicy = 'CustomOnly';
            this.targetApiVersion = '65.0';
            this.perTypeTargets = new Map<String, String>();
            this.incrementPolicy = 'IncrementalOnly';
            this.maxDeltaPerDeploy = 6;
            this.baselineMode = 'InstallTime';
            this.contentRetention = 'HashOnly';
            this.validateOnlyDefault = true;
            this.testPolicy = 'RunSpecifiedTests';
            this.maxComponentsPerUnit = 50;
            this.enableRollbackStorage = false;
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static SettingsDto getSettings() {
        List<AuditEvent__c> settingsEvents = [
            SELECT DetailsJson__c 
            FROM AuditEvent__c 
            WHERE EventType__c = 'SettingsChanged'
            ORDER BY Timestamp__c DESC 
            LIMIT 1
        ];
        
        if (settingsEvents.isEmpty()) {
            return new SettingsDto();
        }
        
        try {
            return (SettingsDto) JSON.deserialize(
                settingsEvents[0].DetailsJson__c, 
                SettingsDto.class
            );
        } catch (Exception e) {
            return new SettingsDto();
        }
    }
    
    @AuraEnabled
    public static SettingsDto saveSettings(String settingsJson) {
        SettingsDto settings = (SettingsDto) JSON.deserialize(settingsJson, SettingsDto.class);
        
        validateSettings(settings);
        
        AuditEvent__c event = new AuditEvent__c(
            EventType__c = 'SettingsChanged',
            Actor__c = UserInfo.getUserId(),
            Timestamp__c = Datetime.now(),
            DetailsJson__c = JSON.serialize(settings)
        );
        insert event;
        
        return settings;
    }
    
    private static void validateSettings(SettingsDto settings) {
        if (settings.includedTypes == null || settings.includedTypes.isEmpty()) {
            throw new AuraHandledException('At least one component type must be selected');
        }
        
        if (String.isBlank(settings.targetApiVersion)) {
            throw new AuraHandledException('Target API version is required');
        }
        
        Decimal targetVersion;
        try {
            targetVersion = Decimal.valueOf(settings.targetApiVersion);
        } catch (Exception e) {
            throw new AuraHandledException('Invalid target API version format');
        }
        
        if (targetVersion < 30.0 || targetVersion > 70.0) {
            throw new AuraHandledException('Target API version must be between 30.0 and 70.0');
        }
        
        Set<String> validTypes = new Set<String>{
            'ApexClass', 'ApexTrigger', 'ApexPage', 'ApexComponent', 
            'Flow', 'AuraBundle', 'LWC'
        };
        for (String t : settings.includedTypes) {
            if (!validTypes.contains(t)) {
                throw new AuraHandledException('Invalid component type: ' + t);
            }
        }
        
        Set<String> validScopes = new Set<String>{'PackageOnly', 'CustomOnly', 'All'};
        if (!validScopes.contains(settings.scopePolicy)) {
            throw new AuraHandledException('Invalid scope policy');
        }
        
        Set<String> validIncrementPolicies = new Set<String>{'IncrementalOnly', 'AllowJumps'};
        if (!validIncrementPolicies.contains(settings.incrementPolicy)) {
            throw new AuraHandledException('Invalid increment policy');
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<String> getSupportedComponentTypes() {
        return new List<String>{
            'ApexClass',
            'ApexTrigger',
            'ApexPage',
            'ApexComponent',
            'Flow',
            'AuraBundle',
            'LWC'
        };
    }
    
    @AuraEnabled(cacheable=true)
    public static List<String> getAvailableApiVersions() {
        List<String> versions = new List<String>();
        for (Integer i = 65; i >= 45; i--) {
            versions.add(String.valueOf(i) + '.0');
        }
        return versions;
    }
}
