public with sharing class ScanService {
    
    public class ScanRequestDto {
        @AuraEnabled public List<String> types;
        @AuraEnabled public String namespacePolicy;
        @AuraEnabled public Decimal minApiVersion;
        @AuraEnabled public Decimal maxApiVersion;
        @AuraEnabled public String targetApiVersion;
        @AuraEnabled public Map<String, String> perTypeTargets;
        @AuraEnabled public String baselineMode;
        @AuraEnabled public Boolean includeContent;
    }
    
    public class ScanStatusDto {
        @AuraEnabled public String scanId;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime startedAt;
        @AuraEnabled public Datetime finishedAt;
        @AuraEnabled public Integer totalArtifacts;
        @AuraEnabled public Integer processedArtifacts;
        @AuraEnabled public Integer findingsCount;
        @AuraEnabled public Integer alertsCount;
        @AuraEnabled public String targetApiVersion;
        @AuraEnabled public Map<String, Object> summary;
    }
    
    @AuraEnabled
    public static String startScan(String requestJson) {
        ScanRequestDto request = (ScanRequestDto) JSON.deserialize(
            requestJson, 
            ScanRequestDto.class
        );
        
        Scan__c scan = new Scan__c(
            Status__c = 'Queued',
            StartedAt__c = Datetime.now(),
            TargetApiVersion__c = request.targetApiVersion,
            BaselineMode__c = request.baselineMode,
            ScopeJson__c = JSON.serialize(new Map<String, Object>{
                'types' => request.types,
                'namespacePolicy' => request.namespacePolicy,
                'minApiVersion' => request.minApiVersion,
                'maxApiVersion' => request.maxApiVersion
            }),
            PerTypeTargetsJson__c = request.perTypeTargets != null ? 
                JSON.serialize(request.perTypeTargets) : null
        );
        insert scan;
        
        logAuditEvent('ScanStarted', new Map<String, Object>{
            'scanId' => scan.Id,
            'types' => request.types,
            'targetVersion' => request.targetApiVersion
        });
        
        System.enqueueJob(new ScanQueueable(scan.Id, request));
        
        return scan.Id;
    }
    
    @AuraEnabled
    public static ScanStatusDto getScanStatus(String scanId) {
        if (String.isBlank(scanId)) {
            return null;
        }
        
        List<Scan__c> scans = [
            SELECT Id, Name, Name__c, Status__c, StartedAt__c, FinishedAt__c, 
                   SummaryJson__c, TargetApiVersion__c, BaselineMode__c
            FROM Scan__c 
            WHERE Id = :scanId
            LIMIT 1
        ];
        
        if (scans.isEmpty()) {
            return null;
        }
        
        Scan__c scan = scans[0];
        
        ScanStatusDto status = new ScanStatusDto();
        status.scanId = scan.Id;
        status.name = String.isNotBlank(scan.Name__c) ? scan.Name__c : scan.Name;
        status.status = scan.Status__c;
        status.startedAt = scan.StartedAt__c;
        status.finishedAt = scan.FinishedAt__c;
        status.targetApiVersion = scan.TargetApiVersion__c;
        
        Integer totalArtifacts = [
            SELECT COUNT() 
            FROM ArtifactSnapshot__c 
            WHERE Scan__c = :scanId
        ];
        status.totalArtifacts = totalArtifacts;
        status.processedArtifacts = totalArtifacts;
        
        status.findingsCount = [
            SELECT COUNT() 
            FROM Finding__c 
            WHERE ArtifactSnapshot__r.Scan__c = :scanId
        ];
        
        // Count distinct artifacts (components) that have at least one finding
        status.alertsCount = [
            SELECT COUNT() 
            FROM ArtifactSnapshot__c 
            WHERE Scan__c = :scanId
              AND Id IN (SELECT ArtifactSnapshot__c FROM Finding__c WHERE ArtifactSnapshot__r.Scan__c = :scanId)
        ];
        
        if (String.isNotBlank(scan.SummaryJson__c)) {
            status.summary = (Map<String, Object>) JSON.deserializeUntyped(scan.SummaryJson__c);
        }
        
        return status;
    }
    
    @AuraEnabled
    public static void cancelScan(String scanId) {
        Scan__c scan = [SELECT Id, Status__c FROM Scan__c WHERE Id = :scanId];
        
        if (scan.Status__c == 'Running' || scan.Status__c == 'Queued') {
            scan.Status__c = 'Cancelled';
            scan.FinishedAt__c = Datetime.now();
            update scan;
            
            logAuditEvent('ScanCancelled', new Map<String, Object>{
                'scanId' => scanId
            });
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<ScanStatusDto> getRecentScans(Integer limitCount) {
        List<ScanStatusDto> scans = new List<ScanStatusDto>();
        
        List<Scan__c> scanRecords = [
            SELECT Id, Name, Name__c, Status__c, StartedAt__c, FinishedAt__c, 
                   SummaryJson__c, TargetApiVersion__c
            FROM Scan__c 
            ORDER BY StartedAt__c DESC
            LIMIT :limitCount
        ];
        
        Set<Id> scanIds = new Set<Id>();
        for (Scan__c s : scanRecords) {
            scanIds.add(s.Id);
        }
        
        Map<Id, Integer> findingsCountMap = new Map<Id, Integer>();
        Map<Id, Integer> alertsCountMap = new Map<Id, Integer>();
        
        for (AggregateResult ar : [
            SELECT ArtifactSnapshot__r.Scan__c scanId, COUNT(Id) cnt
            FROM Finding__c
            WHERE ArtifactSnapshot__r.Scan__c IN :scanIds
            GROUP BY ArtifactSnapshot__r.Scan__c
        ]) {
            Id scanId = (Id) ar.get('scanId');
            Integer count = (Integer) ar.get('cnt');
            findingsCountMap.put(scanId, count);
        }
        
        // Count distinct artifacts (components) that have at least one finding per scan
        for (AggregateResult ar : [
            SELECT Scan__c scanId, COUNT(Id) cnt
            FROM ArtifactSnapshot__c
            WHERE Scan__c IN :scanIds
              AND Id IN (SELECT ArtifactSnapshot__c FROM Finding__c)
            GROUP BY Scan__c
        ]) {
            Id scanId = (Id) ar.get('scanId');
            Integer count = (Integer) ar.get('cnt');
            alertsCountMap.put(scanId, count);
        }
        
        for (Scan__c scan : scanRecords) {
            ScanStatusDto status = new ScanStatusDto();
            status.scanId = scan.Id;
            status.name = String.isNotBlank(scan.Name__c) ? scan.Name__c : scan.Name;
            status.status = scan.Status__c;
            status.startedAt = scan.StartedAt__c;
            status.finishedAt = scan.FinishedAt__c;
            status.targetApiVersion = scan.TargetApiVersion__c;
            status.findingsCount = findingsCountMap.containsKey(scan.Id) ? findingsCountMap.get(scan.Id) : 0;
            status.alertsCount = alertsCountMap.containsKey(scan.Id) ? alertsCountMap.get(scan.Id) : 0;
            
            if (String.isNotBlank(scan.SummaryJson__c)) {
                status.summary = (Map<String, Object>) JSON.deserializeUntyped(scan.SummaryJson__c);
            }
            
            scans.add(status);
        }
        
        return scans;
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
    
    public class ScanQueueable implements Queueable {
        private String scanId;
        private ScanRequestDto request;
        
        public ScanQueueable(String scanId, ScanRequestDto request) {
            this.scanId = scanId;
            this.request = request;
        }
        
        public void execute(QueueableContext context) {
            try {
                processScan();
            } catch (Exception e) {
                Scan__c scan = new Scan__c(
                    Id = scanId,
                    Status__c = 'Failed',
                    FinishedAt__c = Datetime.now(),
                    SummaryJson__c = JSON.serialize(new Map<String, Object>{
                        'error' => e.getMessage(),
                        'stackTrace' => e.getStackTraceString()
                    })
                );
                update scan;
            }
        }
        
        private void processScan() {
            Scan__c scan = new Scan__c(Id = scanId, Status__c = 'Running');
            update scan;
            
            String filterJson = JSON.serialize(new Map<String, Object>{
                'types' => request.types,
                'namespacePolicy' => request.namespacePolicy,
                'minApiVersion' => request.minApiVersion,
                'maxApiVersion' => request.maxApiVersion,
                'pageSize' => 200
            });
            
            InventoryService.InventoryResultDto inventory = 
                InventoryService.queryArtifacts(filterJson);
            
            List<ArtifactSnapshot__c> snapshots = new List<ArtifactSnapshot__c>();
            
            for (InventoryService.ArtifactDto artifact : inventory.artifacts) {
                ArtifactSnapshot__c snapshot = new ArtifactSnapshot__c(
                    Scan__c = scanId,
                    ArtifactType__c = artifact.artifactType,
                    FullName__c = artifact.fullName,
                    DeveloperName__c = artifact.developerName,
                    NamespacePrefix__c = artifact.namespacePrefix,
                    ApiVersion__c = artifact.apiVersion,
                    Status__c = artifact.status,
                    LastModifiedDate__c = artifact.lastModifiedDate
                );
                snapshots.add(snapshot);
            }
            
            if (!snapshots.isEmpty()) {
                insert snapshots;
            }
            
            if (request.includeContent == true) {
                processContentHashes(snapshots);
            }
            
            List<String> snapshotIds = new List<String>();
            for (ArtifactSnapshot__c snap : snapshots) {
                snapshotIds.add(snap.Id);
            }
            
            Decimal targetVersion = Decimal.valueOf(request.targetApiVersion);
            
            String analysisRequest = JSON.serialize(new Map<String, Object>{
                'scanId' => scanId,
                'snapshotIds' => snapshotIds,
                'targetApiVersion' => targetVersion,
                'includeBreakingChanges' => true,
                'includeDeprecations' => true,
                'includeCodeSmells' => false
            });
            
            AnalysisService.analyzeSnapshots(analysisRequest);
        }
        
        private void processContentHashes(List<ArtifactSnapshot__c> snapshots) {
            Map<String, List<String>> idsByType = new Map<String, List<String>>();
            Map<String, ArtifactSnapshot__c> snapshotMap = new Map<String, ArtifactSnapshot__c>();
            
            for (ArtifactSnapshot__c snap : snapshots) {
                if (!idsByType.containsKey(snap.ArtifactType__c)) {
                    idsByType.put(snap.ArtifactType__c, new List<String>());
                }
                
                String artifactId = getArtifactIdFromSnapshot(snap);
                if (artifactId != null) {
                    idsByType.get(snap.ArtifactType__c).add(artifactId);
                    snapshotMap.put(artifactId, snap);
                }
            }
            
            for (String artifactType : idsByType.keySet()) {
                Map<String, String> hashes = ContentService.fetchContentBatch(
                    idsByType.get(artifactType), 
                    artifactType
                );
                
                for (String artifactId : hashes.keySet()) {
                    ArtifactSnapshot__c snap = snapshotMap.get(artifactId);
                    if (snap != null) {
                        snap.ContentHash__c = hashes.get(artifactId);
                    }
                }
            }
            
            update snapshots;
        }
        
        private String getArtifactIdFromSnapshot(ArtifactSnapshot__c snap) {
            String ns = snap.NamespacePrefix__c;
            String devName = snap.DeveloperName__c;
            
            switch on snap.ArtifactType__c {
                when 'ApexClass' {
                    List<ApexClass> classes;
                    if (String.isBlank(ns)) {
                        classes = [
                            SELECT Id FROM ApexClass 
                            WHERE Name = :devName 
                            AND NamespacePrefix = null
                            LIMIT 1
                        ];
                    } else {
                        classes = [
                            SELECT Id FROM ApexClass 
                            WHERE Name = :devName 
                            AND NamespacePrefix = :ns
                            LIMIT 1
                        ];
                    }
                    return classes.isEmpty() ? null : classes[0].Id;
                }
                when 'ApexTrigger' {
                    List<ApexTrigger> triggers = [
                        SELECT Id FROM ApexTrigger 
                        WHERE Name = :devName 
                        LIMIT 1
                    ];
                    return triggers.isEmpty() ? null : triggers[0].Id;
                }
                when else {
                    return null;
                }
            }
        }
    }
}
