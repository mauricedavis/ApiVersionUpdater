public with sharing class AnalysisService {
    
    public class AnalysisRequestDto {
        @AuraEnabled public String scanId;
        @AuraEnabled public List<String> snapshotIds;
        @AuraEnabled public Decimal targetApiVersion;
        @AuraEnabled public Boolean includeBreakingChanges;
        @AuraEnabled public Boolean includeDeprecations;
        @AuraEnabled public Boolean includeCodeSmells;
    }
    
    public class AnalysisResultDto {
        @AuraEnabled public String scanId;
        @AuraEnabled public Integer totalAnalyzed;
        @AuraEnabled public Integer findingsCount;
        @AuraEnabled public Integer criticalCount;
        @AuraEnabled public Integer warningCount;
        @AuraEnabled public Integer infoCount;
        @AuraEnabled public Integer blockingCount;
        @AuraEnabled public List<FindingDto> findings;
    }
    
    public class FindingDto {
        @AuraEnabled public String id;
        @AuraEnabled public String snapshotId;
        @AuraEnabled public String artifactName;
        @AuraEnabled public String severity;
        @AuraEnabled public String category;
        @AuraEnabled public String ruleId;
        @AuraEnabled public String summary;
        @AuraEnabled public String details;
        @AuraEnabled public String evidence;
        @AuraEnabled public String suggestedAction;
        @AuraEnabled public String versionDelta;
        @AuraEnabled public Boolean isBlocking;
    }
    
    @AuraEnabled
    public static AnalysisResultDto analyzeSnapshots(String requestJson) {
        AnalysisRequestDto request = (AnalysisRequestDto) JSON.deserialize(
            requestJson, 
            AnalysisRequestDto.class
        );
        
        AnalysisResultDto result = new AnalysisResultDto();
        result.scanId = request.scanId;
        result.findings = new List<FindingDto>();
        result.criticalCount = 0;
        result.warningCount = 0;
        result.infoCount = 0;
        result.blockingCount = 0;
        
        List<ArtifactSnapshot__c> snapshots = [
            SELECT Id, ArtifactType__c, FullName__c, DeveloperName__c, 
                   ApiVersion__c, ContentHash__c, BaselineHash__c, 
                   ChangedFromBaseline__c, ContentExcerpt__c
            FROM ArtifactSnapshot__c
            WHERE Id IN :request.snapshotIds
        ];
        
        result.totalAnalyzed = snapshots.size();
        
        List<Rule__mdt> rules = getActiveRules(request.targetApiVersion);
        
        List<Finding__c> findingsToInsert = new List<Finding__c>();
        
        for (ArtifactSnapshot__c snapshot : snapshots) {
            List<Finding__c> snapshotFindings = analyzeSnapshot(
                snapshot, 
                rules, 
                request.targetApiVersion
            );
            
            for (Finding__c finding : snapshotFindings) {
                findingsToInsert.add(finding);
                
                FindingDto dto = findingToDto(finding, snapshot.FullName__c);
                result.findings.add(dto);
                
                switch on finding.Severity__c {
                    when 'Critical' {
                        result.criticalCount++;
                    }
                    when 'Warning' {
                        result.warningCount++;
                    }
                    when 'Info' {
                        result.infoCount++;
                    }
                }
                
                if (finding.IsBlocking__c) {
                    result.blockingCount++;
                }
            }
        }
        
        if (!findingsToInsert.isEmpty()) {
            insert findingsToInsert;
            
            for (Integer i = 0; i < findingsToInsert.size(); i++) {
                result.findings[i].id = findingsToInsert[i].Id;
            }
        }
        
        result.findingsCount = result.findings.size();
        
        updateScanSummary(request.scanId, result);
        
        return result;
    }
    
    private static List<Rule__mdt> getActiveRules(Decimal targetVersion) {
        return [
            SELECT Id, RuleId__c, Severity__c, Category__c, AppliesToType__c,
                   PatternType__c, Pattern__c, Description__c, SuggestedAction__c,
                   Blocking__c, VersionDeltaMin__c, VersionDeltaMax__c,
                   Pack__r.DeveloperName, Pack__r.Enabled__c
            FROM Rule__mdt
            WHERE Pack__r.Enabled__c = true
            AND (Pack__r.MaxApiVersion__c = null OR Pack__r.MaxApiVersion__c >= :targetVersion)
            AND (Pack__r.MinApiVersion__c = null OR Pack__r.MinApiVersion__c <= :targetVersion)
        ];
    }
    
    private static List<Finding__c> analyzeSnapshot(ArtifactSnapshot__c snapshot, 
                                                     List<Rule__mdt> rules,
                                                     Decimal targetVersion) {
        List<Finding__c> findings = new List<Finding__c>();
        
        Decimal versionDelta = targetVersion - snapshot.ApiVersion__c;
        
        if (versionDelta > 10) {
            findings.add(createVersionJumpFinding(snapshot, versionDelta));
        }
        
        if (snapshot.ChangedFromBaseline__c == true) {
            findings.add(createDriftFinding(snapshot));
        }
        
        for (Rule__mdt rule : rules) {
            if (rule.AppliesToType__c != null && 
                rule.AppliesToType__c != 'All' &&
                rule.AppliesToType__c != snapshot.ArtifactType__c) {
                continue;
            }
            
            if (rule.VersionDeltaMin__c != null && versionDelta < rule.VersionDeltaMin__c) {
                continue;
            }
            if (rule.VersionDeltaMax__c != null && versionDelta > rule.VersionDeltaMax__c) {
                continue;
            }
            
            Finding__c finding = applyRule(snapshot, rule, versionDelta);
            if (finding != null) {
                findings.add(finding);
            }
        }
        
        return findings;
    }
    
    private static Finding__c applyRule(ArtifactSnapshot__c snapshot, 
                                        Rule__mdt rule, 
                                        Decimal versionDelta) {
        if (String.isBlank(rule.Pattern__c)) {
            return null;
        }
        
        String content = snapshot.ContentExcerpt__c;
        if (String.isBlank(content)) {
            return null;
        }
        
        Boolean matches = false;
        String evidence = '';
        
        switch on rule.PatternType__c {
            when 'Regex' {
                Pattern p = Pattern.compile(rule.Pattern__c);
                Matcher m = p.matcher(content);
                if (m.find()) {
                    matches = true;
                    evidence = m.group();
                }
            }
            when 'Contains' {
                if (content.containsIgnoreCase(rule.Pattern__c)) {
                    matches = true;
                    evidence = extractContext(content, rule.Pattern__c);
                }
            }
            when 'StartsWith' {
                if (content.trim().startsWithIgnoreCase(rule.Pattern__c)) {
                    matches = true;
                    evidence = content.substring(0, Math.min(200, content.length()));
                }
            }
        }
        
        if (!matches) {
            return null;
        }
        
        Finding__c finding = new Finding__c(
            ArtifactSnapshot__c = snapshot.Id,
            Severity__c = rule.Severity__c,
            Category__c = rule.Category__c,
            RuleId__c = rule.RuleId__c,
            Summary__c = rule.Description__c,
            Details__c = 'Pattern matched: ' + rule.Pattern__c,
            Evidence__c = evidence,
            SuggestedAction__c = rule.SuggestedAction__c,
            VersionDelta__c = String.valueOf(versionDelta),
            IsBlocking__c = rule.Blocking__c
        );
        
        return finding;
    }
    
    private static Finding__c createVersionJumpFinding(ArtifactSnapshot__c snapshot, 
                                                        Decimal versionDelta) {
        return new Finding__c(
            ArtifactSnapshot__c = snapshot.Id,
            Severity__c = 'Warning',
            Category__c = 'VersionRisk',
            RuleId__c = 'VERSION_JUMP_LARGE',
            Summary__c = 'Large API version jump detected',
            Details__c = String.format(
                'Upgrading from {0} spans {1} major versions. Review release notes for breaking changes.',
                new List<Object>{snapshot.ApiVersion__c, versionDelta}
            ),
            SuggestedAction__c = 'Consider incremental upgrades or thorough testing',
            VersionDelta__c = String.valueOf(versionDelta),
            IsBlocking__c = false
        );
    }
    
    private static Finding__c createDriftFinding(ArtifactSnapshot__c snapshot) {
        return new Finding__c(
            ArtifactSnapshot__c = snapshot.Id,
            Severity__c = 'Info',
            Category__c = 'Drift',
            RuleId__c = 'BASELINE_DRIFT',
            Summary__c = 'Component has changed since baseline',
            Details__c = 'Content hash differs from baseline. Review changes before upgrade.',
            SuggestedAction__c = 'Review recent changes to this component',
            IsBlocking__c = false
        );
    }
    
    private static String extractContext(String content, String pattern) {
        Integer idx = content.toLowerCase().indexOf(pattern.toLowerCase());
        if (idx < 0) {
            return '';
        }
        
        Integer start = Math.max(0, idx - 50);
        Integer endIdx = Math.min(content.length(), idx + pattern.length() + 50);
        
        return (start > 0 ? '...' : '') + 
               content.substring(start, endIdx) + 
               (endIdx < content.length() ? '...' : '');
    }
    
    private static FindingDto findingToDto(Finding__c finding, String artifactName) {
        FindingDto dto = new FindingDto();
        dto.id = finding.Id;
        dto.snapshotId = finding.ArtifactSnapshot__c;
        dto.artifactName = artifactName;
        dto.severity = finding.Severity__c;
        dto.category = finding.Category__c;
        dto.ruleId = finding.RuleId__c;
        dto.summary = finding.Summary__c;
        dto.details = finding.Details__c;
        dto.evidence = finding.Evidence__c;
        dto.suggestedAction = finding.SuggestedAction__c;
        dto.versionDelta = finding.VersionDelta__c;
        dto.isBlocking = finding.IsBlocking__c;
        return dto;
    }
    
    private static void updateScanSummary(String scanId, AnalysisResultDto result) {
        Map<String, Object> summary = new Map<String, Object>{
            'totalAnalyzed' => result.totalAnalyzed,
            'findingsCount' => result.findingsCount,
            'criticalCount' => result.criticalCount,
            'warningCount' => result.warningCount,
            'infoCount' => result.infoCount,
            'blockingCount' => result.blockingCount,
            'completedAt' => Datetime.now()
        };
        
        Scan__c scan = new Scan__c(
            Id = scanId,
            Status__c = 'Completed',
            FinishedAt__c = Datetime.now(),
            SummaryJson__c = JSON.serialize(summary)
        );
        update scan;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<FindingDto> getFindingsByScan(String scanId) {
        List<FindingDto> dtos = new List<FindingDto>();
        
        List<Finding__c> findings = [
            SELECT Id, ArtifactSnapshot__c, ArtifactSnapshot__r.FullName__c,
                   Severity__c, Category__c, RuleId__c, Summary__c, Details__c,
                   Evidence__c, SuggestedAction__c, VersionDelta__c, IsBlocking__c
            FROM Finding__c
            WHERE ArtifactSnapshot__r.Scan__c = :scanId
            ORDER BY Severity__c, Category__c
        ];
        
        for (Finding__c f : findings) {
            dtos.add(findingToDto(f, f.ArtifactSnapshot__r.FullName__c));
        }
        
        return dtos;
    }
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getFindingsSummary(String scanId) {
        Map<String, Integer> summary = new Map<String, Integer>();
        
        List<AggregateResult> results = [
            SELECT Severity__c sev, COUNT(Id) cnt
            FROM Finding__c
            WHERE ArtifactSnapshot__r.Scan__c = :scanId
            GROUP BY Severity__c
        ];
        
        for (AggregateResult ar : results) {
            String severity = (String) ar.get('sev');
            Integer count = (Integer) ar.get('cnt');
            summary.put(severity, count);
        }
        
        return summary;
    }
}
