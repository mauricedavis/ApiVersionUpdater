List<BackupItem__c> items = [SELECT Id, FullName__c, ContentDocumentId__c FROM BackupItem__c LIMIT 1];
System.debug('Items found: ' + items.size());
if (!items.isEmpty()) {
    System.debug('First item Id: ' + items[0].Id);
    System.debug('First item FullName: ' + items[0].FullName__c);
    System.debug('First item ContentDocumentId: ' + items[0].ContentDocumentId__c);
}
