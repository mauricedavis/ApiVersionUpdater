public with sharing class BaselineService {
    
    public class BaselineEntryDto {
        @AuraEnabled public String artifactType;
        @AuraEnabled public String fullName;
        @AuraEnabled public String contentHash;
        @AuraEnabled public Decimal apiVersion;
        @AuraEnabled public Datetime capturedAt;
        @AuraEnabled public String baselineMode;
    }
    
    @AuraEnabled
    public static Map<String, String> getBaselineHashes(List<String> fullNames, String artifactType, String baselineMode) {
        Map<String, String> hashes = new Map<String, String>();
        
        if (baselineMode == 'InstallTime' || baselineMode == 'LastScan') {
            List<ArtifactSnapshot__c> snapshots = [
                SELECT FullName__c, ContentHash__c
                FROM ArtifactSnapshot__c
                WHERE FullName__c IN :fullNames
                AND ArtifactType__c = :artifactType
                AND Scan__r.BaselineMode__c = :baselineMode
                ORDER BY Scan__r.FinishedAt__c DESC
            ];
            
            Set<String> foundNames = new Set<String>();
            for (ArtifactSnapshot__c snap : snapshots) {
                if (!foundNames.contains(snap.FullName__c)) {
                    hashes.put(snap.FullName__c, snap.ContentHash__c);
                    foundNames.add(snap.FullName__c);
                }
            }
        }
        
        return hashes;
    }
    
    @AuraEnabled
    public static String getBaselineHash(String fullName, String artifactType, String baselineMode) {
        Map<String, String> hashes = getBaselineHashes(
            new List<String>{fullName}, 
            artifactType, 
            baselineMode
        );
        return hashes.get(fullName);
    }
    
    @AuraEnabled
    public static void storeBaseline(String scanId, String artifactType, String fullName, 
                                      String contentHash, Decimal apiVersion) {
        List<ArtifactSnapshot__c> existing = [
            SELECT Id 
            FROM ArtifactSnapshot__c 
            WHERE Scan__c = :scanId 
            AND FullName__c = :fullName
            LIMIT 1
        ];
        
        if (existing.isEmpty()) {
            ArtifactSnapshot__c snapshot = new ArtifactSnapshot__c(
                Scan__c = scanId,
                ArtifactType__c = artifactType,
                FullName__c = fullName,
                ContentHash__c = contentHash,
                ApiVersion__c = apiVersion,
                ContentStoredMode__c = 'HashOnly',
                ChangedFromBaseline__c = false
            );
            insert snapshot;
        } else {
            existing[0].ContentHash__c = contentHash;
            existing[0].ApiVersion__c = apiVersion;
            update existing[0];
        }
    }
    
    @AuraEnabled
    public static void storeBaselineBatch(String scanId, List<BaselineEntryDto> entries) {
        List<ArtifactSnapshot__c> snapshots = new List<ArtifactSnapshot__c>();
        
        for (BaselineEntryDto entry : entries) {
            ArtifactSnapshot__c snapshot = new ArtifactSnapshot__c(
                Scan__c = scanId,
                ArtifactType__c = entry.artifactType,
                FullName__c = entry.fullName,
                ContentHash__c = entry.contentHash,
                ApiVersion__c = entry.apiVersion,
                ContentStoredMode__c = 'HashOnly',
                ChangedFromBaseline__c = false
            );
            snapshots.add(snapshot);
        }
        
        if (!snapshots.isEmpty()) {
            insert snapshots;
        }
    }
    
    @AuraEnabled
    public static Map<String, Boolean> checkDrift(String scanId, String baselineMode) {
        Map<String, Boolean> driftMap = new Map<String, Boolean>();
        
        List<ArtifactSnapshot__c> currentSnapshots = [
            SELECT FullName__c, ArtifactType__c, ContentHash__c
            FROM ArtifactSnapshot__c
            WHERE Scan__c = :scanId
        ];
        
        Map<String, String> artifactTypes = new Map<String, String>();
        List<String> fullNames = new List<String>();
        Map<String, String> currentHashes = new Map<String, String>();
        
        for (ArtifactSnapshot__c snap : currentSnapshots) {
            fullNames.add(snap.FullName__c);
            artifactTypes.put(snap.FullName__c, snap.ArtifactType__c);
            currentHashes.put(snap.FullName__c, snap.ContentHash__c);
        }
        
        for (String fullName : fullNames) {
            String artifactType = artifactTypes.get(fullName);
            String baselineHash = getBaselineHash(fullName, artifactType, baselineMode);
            String currentHash = currentHashes.get(fullName);
            
            if (baselineHash == null) {
                driftMap.put(fullName, false);
            } else {
                driftMap.put(fullName, baselineHash != currentHash);
            }
        }
        
        return driftMap;
    }
    
    @AuraEnabled
    public static void updateDriftFlags(String scanId, Map<String, Boolean> driftMap) {
        List<ArtifactSnapshot__c> snapshots = [
            SELECT Id, FullName__c, ChangedFromBaseline__c
            FROM ArtifactSnapshot__c
            WHERE Scan__c = :scanId
        ];
        
        List<ArtifactSnapshot__c> toUpdate = new List<ArtifactSnapshot__c>();
        
        for (ArtifactSnapshot__c snap : snapshots) {
            Boolean hasDrift = driftMap.get(snap.FullName__c);
            if (hasDrift != null && hasDrift != snap.ChangedFromBaseline__c) {
                snap.ChangedFromBaseline__c = hasDrift;
                toUpdate.add(snap);
            }
        }
        
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
    
    @AuraEnabled
    public static Scan__c createBaselineScan(String baselineMode) {
        Scan__c scan = new Scan__c(
            Status__c = 'Queued',
            StartedAt__c = Datetime.now(),
            BaselineMode__c = baselineMode,
            ScopeJson__c = JSON.serialize(new Map<String, Object>{
                'purpose' => 'baseline',
                'createdBy' => UserInfo.getUserId()
            })
        );
        insert scan;
        
        AuditEvent__c event = new AuditEvent__c(
            EventType__c = 'ScanStarted',
            Actor__c = UserInfo.getUserId(),
            Timestamp__c = Datetime.now(),
            DetailsJson__c = JSON.serialize(new Map<String, Object>{
                'scanId' => scan.Id,
                'baselineMode' => baselineMode
            })
        );
        insert event;
        
        return scan;
    }
    
    @AuraEnabled
    public static Integer getBaselineCount(String baselineMode) {
        return [
            SELECT COUNT()
            FROM ArtifactSnapshot__c
            WHERE Scan__r.BaselineMode__c = :baselineMode
        ];
    }
}
