public with sharing class ContentService {
    
    public class ContentDto {
        @AuraEnabled public String artifactId;
        @AuraEnabled public String artifactType;
        @AuraEnabled public String fullName;
        @AuraEnabled public String content;
        @AuraEnabled public String contentHash;
        @AuraEnabled public Integer contentLength;
        @AuraEnabled public String normalizedContent;
        @AuraEnabled public String normalizedHash;
    }
    
    @AuraEnabled
    public static ContentDto fetchContent(String artifactId, String artifactType) {
        ContentDto dto = new ContentDto();
        dto.artifactId = artifactId;
        dto.artifactType = artifactType;
        
        String content = '';
        
        switch on artifactType {
            when 'ApexClass' {
                ApexClass cls = [SELECT Name, NamespacePrefix, Body FROM ApexClass WHERE Id = :artifactId];
                content = cls.Body != null ? cls.Body : '';
                dto.fullName = cls.NamespacePrefix != null ? cls.NamespacePrefix + '.' + cls.Name : cls.Name;
            }
            when 'ApexTrigger' {
                ApexTrigger trg = [SELECT Name, NamespacePrefix, Body FROM ApexTrigger WHERE Id = :artifactId];
                content = trg.Body != null ? trg.Body : '';
                dto.fullName = trg.NamespacePrefix != null ? trg.NamespacePrefix + '.' + trg.Name : trg.Name;
            }
            when 'ApexPage' {
                ApexPage pg = [SELECT Name, NamespacePrefix, Markup FROM ApexPage WHERE Id = :artifactId];
                content = pg.Markup != null ? pg.Markup : '';
                dto.fullName = pg.NamespacePrefix != null ? pg.NamespacePrefix + '.' + pg.Name : pg.Name;
            }
            when 'ApexComponent' {
                ApexComponent cmp = [SELECT Name, NamespacePrefix, Markup FROM ApexComponent WHERE Id = :artifactId];
                content = cmp.Markup != null ? cmp.Markup : '';
                dto.fullName = cmp.NamespacePrefix != null ? cmp.NamespacePrefix + '.' + cmp.Name : cmp.Name;
            }
            when else {
                throw new AuraHandledException('Unsupported artifact type: ' + artifactType);
            }
        }
        
        dto.content = content;
        dto.contentLength = content.length();
        dto.contentHash = computeHash(content);
        
        String normalized = normalizeContent(content, artifactType);
        dto.normalizedContent = normalized;
        dto.normalizedHash = computeHash(normalized);
        
        return dto;
    }
    
    @AuraEnabled
    public static String computeHash(String content) {
        if (String.isBlank(content)) {
            return 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
        }
        
        Blob contentBlob = Blob.valueOf(content);
        Blob hashBlob = Crypto.generateDigest('SHA-256', contentBlob);
        return EncodingUtil.convertToHex(hashBlob);
    }
    
    public static String normalizeContent(String content, String artifactType) {
        if (String.isBlank(content)) {
            return '';
        }
        
        String normalized = content;
        
        normalized = normalized.replaceAll('//[^\n]*', '');
        
        normalized = normalized.replaceAll('/\\*[\\s\\S]*?\\*/', '');
        
        normalized = normalized.replaceAll('\\s+', ' ');
        
        normalized = normalized.trim();
        
        return normalized;
    }
    
    @AuraEnabled
    public static Map<String, String> fetchContentBatch(List<String> artifactIds, String artifactType) {
        Map<String, String> hashes = new Map<String, String>();
        
        switch on artifactType {
            when 'ApexClass' {
                for (ApexClass cls : [SELECT Id, Body FROM ApexClass WHERE Id IN :artifactIds]) {
                    String content = cls.Body != null ? cls.Body : '';
                    hashes.put(cls.Id, computeHash(content));
                }
            }
            when 'ApexTrigger' {
                for (ApexTrigger trg : [SELECT Id, Body FROM ApexTrigger WHERE Id IN :artifactIds]) {
                    String content = trg.Body != null ? trg.Body : '';
                    hashes.put(trg.Id, computeHash(content));
                }
            }
            when 'ApexPage' {
                for (ApexPage pg : [SELECT Id, Markup FROM ApexPage WHERE Id IN :artifactIds]) {
                    String content = pg.Markup != null ? pg.Markup : '';
                    hashes.put(pg.Id, computeHash(content));
                }
            }
            when 'ApexComponent' {
                for (ApexComponent cmp : [SELECT Id, Markup FROM ApexComponent WHERE Id IN :artifactIds]) {
                    String content = cmp.Markup != null ? cmp.Markup : '';
                    hashes.put(cmp.Id, computeHash(content));
                }
            }
        }
        
        return hashes;
    }
    
    public static String getContentExcerpt(String content, Integer maxLength) {
        if (String.isBlank(content)) {
            return '';
        }
        
        if (content.length() <= maxLength) {
            return content;
        }
        
        String excerpt = content.substring(0, maxLength);
        Integer lastNewline = excerpt.lastIndexOf('\n');
        if (lastNewline > maxLength / 2) {
            excerpt = excerpt.substring(0, lastNewline);
        }
        
        return excerpt + '\n... [truncated]';
    }
    
    public class DiffResultDto {
        @AuraEnabled public Boolean hasChanges;
        @AuraEnabled public Integer linesAdded;
        @AuraEnabled public Integer linesRemoved;
        @AuraEnabled public Integer linesChanged;
        @AuraEnabled public String diffSummary;
        @AuraEnabled public List<String> changedSections;
    }
    
    @AuraEnabled
    public static DiffResultDto compareDiff(String oldContent, String newContent) {
        DiffResultDto result = new DiffResultDto();
        result.changedSections = new List<String>();
        
        if (oldContent == newContent) {
            result.hasChanges = false;
            result.linesAdded = 0;
            result.linesRemoved = 0;
            result.linesChanged = 0;
            result.diffSummary = 'No changes';
            return result;
        }
        
        result.hasChanges = true;
        
        List<String> oldLines = oldContent.split('\n');
        List<String> newLines = newContent.split('\n');
        
        Set<String> oldLineSet = new Set<String>(oldLines);
        Set<String> newLineSet = new Set<String>(newLines);
        
        result.linesAdded = 0;
        result.linesRemoved = 0;
        
        for (String line : newLines) {
            if (!oldLineSet.contains(line)) {
                result.linesAdded++;
            }
        }
        
        for (String line : oldLines) {
            if (!newLineSet.contains(line)) {
                result.linesRemoved++;
            }
        }
        
        result.linesChanged = Math.min(result.linesAdded, result.linesRemoved);
        result.linesAdded = result.linesAdded - result.linesChanged;
        result.linesRemoved = result.linesRemoved - result.linesChanged;
        
        result.diffSummary = String.format(
            '+{0} -{1} ~{2}',
            new List<Object>{result.linesAdded, result.linesRemoved, result.linesChanged}
        );
        
        return result;
    }
}
