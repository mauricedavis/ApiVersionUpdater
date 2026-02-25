List<BackupItem__c> items = [SELECT Id, ArtifactType__c, FullName__c, DeploymentRun__c FROM BackupItem__c LIMIT 1];
System.debug('Items found: ' + items.size());
if (!items.isEmpty()) {
    BackupItem__c item = items[0];
    System.debug('Item Id: ' + item.Id);
    System.debug('FullName: ' + item.FullName__c);
    System.debug('ArtifactType: ' + item.ArtifactType__c);
    
    String titlePattern = item.FullName__c + '_body';
    List<ContentVersion> cvs = [
        SELECT VersionData
        FROM ContentVersion
        WHERE Title = :titlePattern
        AND IsLatest = true
        ORDER BY CreatedDate DESC
        LIMIT 1
    ];
    
    if (cvs.isEmpty()) {
        System.debug('No backup content found');
    } else {
        System.debug('Backup content length: ' + cvs[0].VersionData.size());
    }
}
