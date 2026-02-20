public with sharing class InventoryService {
    
    public class ArtifactDto {
        @AuraEnabled public String id;
        @AuraEnabled public String artifactType;
        @AuraEnabled public String fullName;
        @AuraEnabled public String developerName;
        @AuraEnabled public String namespacePrefix;
        @AuraEnabled public Decimal apiVersion;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime lastModifiedDate;
        @AuraEnabled public String lastModifiedById;
        @AuraEnabled public String lastModifiedByName;
        @AuraEnabled public Integer bodyLength;
        @AuraEnabled public Boolean isManaged;
    }
    
    public class InventoryResultDto {
        @AuraEnabled public List<ArtifactDto> artifacts;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public String nextPageToken;
        @AuraEnabled public Map<String, Integer> countsByType;
    }
    
    public class FilterDto {
        @AuraEnabled public List<String> types;
        @AuraEnabled public String namespacePolicy;
        @AuraEnabled public Decimal minApiVersion;
        @AuraEnabled public Decimal maxApiVersion;
        @AuraEnabled public String searchText;
        @AuraEnabled public Integer pageSize;
        @AuraEnabled public Integer offset;
    }
    
    @AuraEnabled
    public static InventoryResultDto queryArtifacts(String filterJson) {
        FilterDto filter = (FilterDto) JSON.deserialize(filterJson, FilterDto.class);
        
        if (filter.pageSize == null || filter.pageSize <= 0) {
            filter.pageSize = 50;
        }
        if (filter.pageSize > 200) {
            filter.pageSize = 200;
        }
        if (filter.offset == null) {
            filter.offset = 0;
        }
        
        InventoryResultDto result = new InventoryResultDto();
        result.artifacts = new List<ArtifactDto>();
        result.countsByType = new Map<String, Integer>();
        
        if (filter.types == null || filter.types.isEmpty()) {
            filter.types = new List<String>{'ApexClass', 'ApexTrigger', 'ApexPage', 'ApexComponent'};
        }
        
        for (String artifactType : filter.types) {
            List<ArtifactDto> typeArtifacts = queryArtifactsByType(artifactType, filter);
            result.artifacts.addAll(typeArtifacts);
            result.countsByType.put(artifactType, typeArtifacts.size());
        }
        
        result.totalCount = result.artifacts.size();
        
        return result;
    }
    
    private static List<ArtifactDto> queryArtifactsByType(String artifactType, FilterDto filter) {
        List<ArtifactDto> artifacts = new List<ArtifactDto>();
        
        switch on artifactType {
            when 'ApexClass' {
                artifacts = queryApexClasses(filter);
            }
            when 'ApexTrigger' {
                artifacts = queryApexTriggers(filter);
            }
            when 'ApexPage' {
                artifacts = queryApexPages(filter);
            }
            when 'ApexComponent' {
                artifacts = queryApexComponents(filter);
            }
        }
        
        return artifacts;
    }
    
    private static List<ArtifactDto> queryApexClasses(FilterDto filter) {
        List<ArtifactDto> artifacts = new List<ArtifactDto>();
        
        String query = 'SELECT Id, Name, NamespacePrefix, ApiVersion, Status, ' +
                       'LastModifiedDate, LastModifiedById, LastModifiedBy.Name, LengthWithoutComments ' +
                       'FROM ApexClass';
        
        List<String> conditions = buildConditions(filter, 'Name');
        if (!conditions.isEmpty()) {
            query += ' WHERE ' + String.join(conditions, ' AND ');
        }
        
        query += ' ORDER BY Name LIMIT ' + filter.pageSize + ' OFFSET ' + filter.offset;
        
        for (ApexClass cls : Database.query(query)) {
            ArtifactDto dto = new ArtifactDto();
            dto.id = cls.Id;
            dto.artifactType = 'ApexClass';
            dto.fullName = cls.NamespacePrefix != null ? cls.NamespacePrefix + '.' + cls.Name : cls.Name;
            dto.developerName = cls.Name;
            dto.namespacePrefix = cls.NamespacePrefix;
            dto.apiVersion = cls.ApiVersion;
            dto.status = cls.Status;
            dto.lastModifiedDate = cls.LastModifiedDate;
            dto.lastModifiedById = cls.LastModifiedById;
            dto.lastModifiedByName = cls.LastModifiedBy?.Name;
            dto.bodyLength = cls.LengthWithoutComments;
            dto.isManaged = String.isNotBlank(cls.NamespacePrefix);
            artifacts.add(dto);
        }
        
        return artifacts;
    }
    
    private static List<ArtifactDto> queryApexTriggers(FilterDto filter) {
        List<ArtifactDto> artifacts = new List<ArtifactDto>();
        
        String query = 'SELECT Id, Name, NamespacePrefix, ApiVersion, Status, ' +
                       'LastModifiedDate, LastModifiedById, LastModifiedBy.Name, LengthWithoutComments, TableEnumOrId ' +
                       'FROM ApexTrigger';
        
        List<String> conditions = buildConditions(filter, 'Name');
        if (!conditions.isEmpty()) {
            query += ' WHERE ' + String.join(conditions, ' AND ');
        }
        
        query += ' ORDER BY Name LIMIT ' + filter.pageSize + ' OFFSET ' + filter.offset;
        
        for (ApexTrigger trg : Database.query(query)) {
            ArtifactDto dto = new ArtifactDto();
            dto.id = trg.Id;
            dto.artifactType = 'ApexTrigger';
            dto.fullName = trg.NamespacePrefix != null ? trg.NamespacePrefix + '.' + trg.Name : trg.Name;
            dto.developerName = trg.Name;
            dto.namespacePrefix = trg.NamespacePrefix;
            dto.apiVersion = trg.ApiVersion;
            dto.status = trg.Status;
            dto.lastModifiedDate = trg.LastModifiedDate;
            dto.lastModifiedById = trg.LastModifiedById;
            dto.lastModifiedByName = trg.LastModifiedBy?.Name;
            dto.bodyLength = trg.LengthWithoutComments;
            dto.isManaged = String.isNotBlank(trg.NamespacePrefix);
            artifacts.add(dto);
        }
        
        return artifacts;
    }
    
    private static List<ArtifactDto> queryApexPages(FilterDto filter) {
        List<ArtifactDto> artifacts = new List<ArtifactDto>();
        
        String query = 'SELECT Id, Name, NamespacePrefix, ApiVersion, ' +
                       'LastModifiedDate, LastModifiedById, LastModifiedBy.Name, ' +
                       'ControllerKey, ControllerType, Description ' +
                       'FROM ApexPage';
        
        List<String> conditions = buildConditions(filter, 'Name');
        if (!conditions.isEmpty()) {
            query += ' WHERE ' + String.join(conditions, ' AND ');
        }
        
        query += ' ORDER BY Name LIMIT ' + filter.pageSize + ' OFFSET ' + filter.offset;
        
        for (ApexPage pg : Database.query(query)) {
            ArtifactDto dto = new ArtifactDto();
            dto.id = pg.Id;
            dto.artifactType = 'ApexPage';
            dto.fullName = pg.NamespacePrefix != null ? pg.NamespacePrefix + '.' + pg.Name : pg.Name;
            dto.developerName = pg.Name;
            dto.namespacePrefix = pg.NamespacePrefix;
            dto.apiVersion = pg.ApiVersion;
            dto.status = 'Active';
            dto.lastModifiedDate = pg.LastModifiedDate;
            dto.lastModifiedById = pg.LastModifiedById;
            dto.lastModifiedByName = pg.LastModifiedBy?.Name;
            dto.isManaged = String.isNotBlank(pg.NamespacePrefix);
            artifacts.add(dto);
        }
        
        return artifacts;
    }
    
    private static List<ArtifactDto> queryApexComponents(FilterDto filter) {
        List<ArtifactDto> artifacts = new List<ArtifactDto>();
        
        String query = 'SELECT Id, Name, NamespacePrefix, ApiVersion, ' +
                       'LastModifiedDate, LastModifiedById, LastModifiedBy.Name, Description ' +
                       'FROM ApexComponent';
        
        List<String> conditions = buildConditions(filter, 'Name');
        if (!conditions.isEmpty()) {
            query += ' WHERE ' + String.join(conditions, ' AND ');
        }
        
        query += ' ORDER BY Name LIMIT ' + filter.pageSize + ' OFFSET ' + filter.offset;
        
        for (ApexComponent cmp : Database.query(query)) {
            ArtifactDto dto = new ArtifactDto();
            dto.id = cmp.Id;
            dto.artifactType = 'ApexComponent';
            dto.fullName = cmp.NamespacePrefix != null ? cmp.NamespacePrefix + '.' + cmp.Name : cmp.Name;
            dto.developerName = cmp.Name;
            dto.namespacePrefix = cmp.NamespacePrefix;
            dto.apiVersion = cmp.ApiVersion;
            dto.status = 'Active';
            dto.lastModifiedDate = cmp.LastModifiedDate;
            dto.lastModifiedById = cmp.LastModifiedById;
            dto.lastModifiedByName = cmp.LastModifiedBy?.Name;
            dto.isManaged = String.isNotBlank(cmp.NamespacePrefix);
            artifacts.add(dto);
        }
        
        return artifacts;
    }
    
    private static List<String> buildConditions(FilterDto filter, String nameField) {
        List<String> conditions = new List<String>();
        
        if (filter.namespacePolicy == 'CustomOnly') {
            conditions.add('NamespacePrefix = null');
        } else if (filter.namespacePolicy == 'PackageOnly') {
            conditions.add('NamespacePrefix != null');
        }
        
        if (filter.minApiVersion != null) {
            conditions.add('ApiVersion >= ' + filter.minApiVersion);
        }
        
        if (filter.maxApiVersion != null) {
            conditions.add('ApiVersion <= ' + filter.maxApiVersion);
        }
        
        if (String.isNotBlank(filter.searchText)) {
            String searchPattern = '%' + String.escapeSingleQuotes(filter.searchText) + '%';
            conditions.add(nameField + ' LIKE \'' + searchPattern + '\'');
        }
        
        return conditions;
    }
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getInventoryCounts() {
        Map<String, Integer> counts = new Map<String, Integer>();
        
        counts.put('ApexClass', [SELECT COUNT() FROM ApexClass WHERE NamespacePrefix = null]);
        counts.put('ApexTrigger', [SELECT COUNT() FROM ApexTrigger WHERE NamespacePrefix = null]);
        counts.put('ApexPage', [SELECT COUNT() FROM ApexPage WHERE NamespacePrefix = null]);
        counts.put('ApexComponent', [SELECT COUNT() FROM ApexComponent WHERE NamespacePrefix = null]);
        
        return counts;
    }
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getVersionDistribution(String artifactType) {
        Map<String, Integer> distribution = new Map<String, Integer>();
        
        String query = 'SELECT ApiVersion, COUNT(Id) cnt FROM ' + 
                       String.escapeSingleQuotes(artifactType) + 
                       ' WHERE NamespacePrefix = null GROUP BY ApiVersion ORDER BY ApiVersion DESC';
        
        for (AggregateResult ar : Database.query(query)) {
            Decimal version = (Decimal) ar.get('ApiVersion');
            Integer count = (Integer) ar.get('cnt');
            distribution.put(String.valueOf(version), count);
        }
        
        return distribution;
    }
    
    public class ComplianceMetricsDto {
        @AuraEnabled public Integer totalComponents;
        @AuraEnabled public Integer compliantComponents;
        @AuraEnabled public Integer nonCompliantComponents;
        @AuraEnabled public Decimal compliancePercentage;
        @AuraEnabled public Decimal targetApiVersion;
        @AuraEnabled public Map<String, TypeComplianceDto> byType;
        @AuraEnabled public Map<String, Integer> versionBreakdown;
        @AuraEnabled public Decimal oldestVersion;
        @AuraEnabled public Decimal newestVersion;
        @AuraEnabled public Integer versionsToUpgrade;
    }
    
    public class TypeComplianceDto {
        @AuraEnabled public String artifactType;
        @AuraEnabled public Integer total;
        @AuraEnabled public Integer compliant;
        @AuraEnabled public Integer nonCompliant;
        @AuraEnabled public Decimal compliancePercentage;
    }
    
    @AuraEnabled
    public static ComplianceMetricsDto getComplianceMetrics(Decimal targetApiVersion, String scopePolicy) {
        ComplianceMetricsDto metrics = new ComplianceMetricsDto();
        metrics.targetApiVersion = targetApiVersion;
        metrics.byType = new Map<String, TypeComplianceDto>();
        metrics.versionBreakdown = new Map<String, Integer>();
        metrics.totalComponents = 0;
        metrics.compliantComponents = 0;
        metrics.nonCompliantComponents = 0;
        metrics.oldestVersion = 999;
        metrics.newestVersion = 0;
        
        String namespaceCondition = '';
        if (scopePolicy == 'CustomOnly') {
            namespaceCondition = ' WHERE NamespacePrefix = null';
        } else if (scopePolicy == 'PackageOnly') {
            namespaceCondition = ' WHERE NamespacePrefix != null';
        }
        
        List<String> types = new List<String>{'ApexClass', 'ApexTrigger', 'ApexPage', 'ApexComponent'};
        
        for (String artifactType : types) {
            TypeComplianceDto typeMetrics = new TypeComplianceDto();
            typeMetrics.artifactType = artifactType;
            typeMetrics.total = 0;
            typeMetrics.compliant = 0;
            typeMetrics.nonCompliant = 0;
            
            String query = 'SELECT ApiVersion, COUNT(Id) cnt FROM ' + 
                           String.escapeSingleQuotes(artifactType) + 
                           namespaceCondition + 
                           ' GROUP BY ApiVersion';
            
            for (AggregateResult ar : Database.query(query)) {
                Decimal version = (Decimal) ar.get('ApiVersion');
                Integer count = (Integer) ar.get('cnt');
                
                typeMetrics.total += count;
                
                if (version >= targetApiVersion) {
                    typeMetrics.compliant += count;
                } else {
                    typeMetrics.nonCompliant += count;
                }
                
                if (version < metrics.oldestVersion) {
                    metrics.oldestVersion = version;
                }
                if (version > metrics.newestVersion) {
                    metrics.newestVersion = version;
                }
                
                String versionKey = String.valueOf(version);
                Integer existing = metrics.versionBreakdown.get(versionKey);
                metrics.versionBreakdown.put(versionKey, (existing != null ? existing : 0) + count);
            }
            
            typeMetrics.compliancePercentage = typeMetrics.total > 0 
                ? (typeMetrics.compliant * 100.0 / typeMetrics.total).setScale(1) 
                : 100;
            
            metrics.byType.put(artifactType, typeMetrics);
            metrics.totalComponents += typeMetrics.total;
            metrics.compliantComponents += typeMetrics.compliant;
            metrics.nonCompliantComponents += typeMetrics.nonCompliant;
        }
        
        metrics.compliancePercentage = metrics.totalComponents > 0 
            ? (metrics.compliantComponents * 100.0 / metrics.totalComponents).setScale(1) 
            : 100;
        
        if (metrics.oldestVersion == 999) metrics.oldestVersion = targetApiVersion;
        if (metrics.newestVersion == 0) metrics.newestVersion = targetApiVersion;
        
        metrics.versionsToUpgrade = (Integer)(targetApiVersion - metrics.oldestVersion);
        
        return metrics;
    }
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Map<String, Integer>> getVersionDistributionAllTypes(String scopePolicy) {
        Map<String, Map<String, Integer>> allDistributions = new Map<String, Map<String, Integer>>();
        
        String namespaceCondition = '';
        if (scopePolicy == 'CustomOnly') {
            namespaceCondition = ' WHERE NamespacePrefix = null';
        } else if (scopePolicy == 'PackageOnly') {
            namespaceCondition = ' WHERE NamespacePrefix != null';
        }
        
        List<String> types = new List<String>{'ApexClass', 'ApexTrigger', 'ApexPage', 'ApexComponent'};
        
        for (String artifactType : types) {
            Map<String, Integer> distribution = new Map<String, Integer>();
            
            String query = 'SELECT ApiVersion, COUNT(Id) cnt FROM ' + 
                           String.escapeSingleQuotes(artifactType) + 
                           namespaceCondition + 
                           ' GROUP BY ApiVersion ORDER BY ApiVersion DESC';
            
            for (AggregateResult ar : Database.query(query)) {
                Decimal version = (Decimal) ar.get('ApiVersion');
                Integer count = (Integer) ar.get('cnt');
                distribution.put(String.valueOf(version), count);
            }
            
            allDistributions.put(artifactType, distribution);
        }
        
        return allDistributions;
    }
    
    @AuraEnabled
    public static ArtifactDto getArtifactDetails(String artifactId, String artifactType) {
        switch on artifactType {
            when 'ApexClass' {
                ApexClass cls = [
                    SELECT Id, Name, NamespacePrefix, ApiVersion, Status,
                           LastModifiedDate, LastModifiedById, LastModifiedBy.Name, 
                           LengthWithoutComments, Body
                    FROM ApexClass 
                    WHERE Id = :artifactId
                ];
                ArtifactDto dto = new ArtifactDto();
                dto.id = cls.Id;
                dto.artifactType = 'ApexClass';
                dto.fullName = cls.NamespacePrefix != null ? cls.NamespacePrefix + '.' + cls.Name : cls.Name;
                dto.developerName = cls.Name;
                dto.namespacePrefix = cls.NamespacePrefix;
                dto.apiVersion = cls.ApiVersion;
                dto.status = cls.Status;
                dto.lastModifiedDate = cls.LastModifiedDate;
                dto.lastModifiedById = cls.LastModifiedById;
                dto.lastModifiedByName = cls.LastModifiedBy?.Name;
                dto.bodyLength = cls.LengthWithoutComments;
                dto.isManaged = String.isNotBlank(cls.NamespacePrefix);
                return dto;
            }
            when 'ApexTrigger' {
                ApexTrigger trg = [
                    SELECT Id, Name, NamespacePrefix, ApiVersion, Status,
                           LastModifiedDate, LastModifiedById, LastModifiedBy.Name, 
                           LengthWithoutComments, Body
                    FROM ApexTrigger 
                    WHERE Id = :artifactId
                ];
                ArtifactDto dto = new ArtifactDto();
                dto.id = trg.Id;
                dto.artifactType = 'ApexTrigger';
                dto.fullName = trg.NamespacePrefix != null ? trg.NamespacePrefix + '.' + trg.Name : trg.Name;
                dto.developerName = trg.Name;
                dto.namespacePrefix = trg.NamespacePrefix;
                dto.apiVersion = trg.ApiVersion;
                dto.status = trg.Status;
                dto.lastModifiedDate = trg.LastModifiedDate;
                dto.lastModifiedById = trg.LastModifiedById;
                dto.lastModifiedByName = trg.LastModifiedBy?.Name;
                dto.bodyLength = trg.LengthWithoutComments;
                dto.isManaged = String.isNotBlank(trg.NamespacePrefix);
                return dto;
            }
            when else {
                throw new AuraHandledException('Unsupported artifact type: ' + artifactType);
            }
        }
    }
}
