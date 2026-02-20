public with sharing class BackupNotificationSchedulable implements Schedulable {
    
    public void execute(SchedulableContext sc) {
        checkExpiringBackups();
    }
    
    @future
    public static void checkExpiringBackups() {
        Date today = Date.today();
        
        List<DeploymentRun__c> expiringRuns = [
            SELECT Id, Name, BackupOwner__c, BackupOwner__r.Email, BackupOwner__r.Name,
                   BackupCreatedAt__c, BackupExpirationDate__c, BackupItemCount__c,
                   ChangePlan__r.Name, ChangePlan__r.TargetApiVersion__c
            FROM DeploymentRun__c
            WHERE BackupExpirationDate__c <= :today
            AND BackupNotificationSent__c = false
            AND BackupCleanedUp__c = false
            AND BackupOwner__c != null
            LIMIT 50
        ];
        
        if (expiringRuns.isEmpty()) {
            return;
        }
        
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<DeploymentRun__c> runsToUpdate = new List<DeploymentRun__c>();
        
        for (DeploymentRun__c run : expiringRuns) {
            Messaging.SingleEmailMessage email = createNotificationEmail(run);
            if (email != null) {
                emails.add(email);
            }
            
            run.BackupNotificationSent__c = true;
            runsToUpdate.add(run);
        }
        
        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails);
            } catch (Exception e) {
                System.debug('Error sending backup notification emails: ' + e.getMessage());
            }
        }
        
        update runsToUpdate;
        
        logAuditEvent('BackupExpirationNotificationsSent', new Map<String, Object>{
            'count' => expiringRuns.size()
        });
    }
    
    private static Messaging.SingleEmailMessage createNotificationEmail(DeploymentRun__c run) {
        if (String.isBlank(run.BackupOwner__r.Email)) {
            return null;
        }
        
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ run.BackupOwner__r.Email });
        email.setSubject('API Version Updater: Backup Expiration Notice');
        
        String body = 'Hello ' + run.BackupOwner__r.Name + ',\n\n';
        body += 'This is a notification that a backup created by the API Version Updater tool has reached its 90-day retention period.\n\n';
        body += 'Backup Details:\n';
        body += '- Deployment Run: ' + run.Name + '\n';
        body += '- Change Plan: ' + (run.ChangePlan__r != null ? run.ChangePlan__r.Name : 'N/A') + '\n';
        body += '- Target API Version: ' + (run.ChangePlan__r != null ? run.ChangePlan__r.TargetApiVersion__c : 'N/A') + '\n';
        body += '- Backup Created: ' + run.BackupCreatedAt__c.format() + '\n';
        body += '- Items Backed Up: ' + run.BackupItemCount__c + '\n';
        body += '- Expiration Date: ' + run.BackupExpirationDate__c.format() + '\n\n';
        body += 'Action Required:\n';
        body += 'Please review this backup and either:\n';
        body += '1. Manually clean up the backup if it is no longer needed\n';
        body += '2. Download the backup files if you need to retain them longer\n\n';
        body += 'The backup will remain until manually cleaned up, but this notification serves as a reminder to review your backup storage.\n\n';
        body += 'Thank you,\n';
        body += 'API Version Updater';
        
        email.setPlainTextBody(body);
        
        return email;
    }
    
    public static String scheduleDaily() {
        String jobName = 'API Version Updater - Backup Notification Check';
        
        List<CronTrigger> existingJobs = [
            SELECT Id FROM CronTrigger 
            WHERE CronJobDetail.Name = :jobName
            LIMIT 1
        ];
        
        if (!existingJobs.isEmpty()) {
            System.abortJob(existingJobs[0].Id);
        }
        
        String cronExpression = '0 0 8 * * ?';
        
        return System.schedule(jobName, cronExpression, new BackupNotificationSchedulable());
    }
    
    public static void unschedule() {
        String jobName = 'API Version Updater - Backup Notification Check';
        
        List<CronTrigger> jobs = [
            SELECT Id FROM CronTrigger 
            WHERE CronJobDetail.Name = :jobName
        ];
        
        for (CronTrigger job : jobs) {
            System.abortJob(job.Id);
        }
    }
    
    @AuraEnabled
    public static Map<String, Object> getScheduleStatus() {
        String jobName = 'API Version Updater - Backup Notification Check';
        
        List<CronTrigger> jobs = [
            SELECT Id, CronExpression, NextFireTime, State
            FROM CronTrigger 
            WHERE CronJobDetail.Name = :jobName
            LIMIT 1
        ];
        
        Map<String, Object> status = new Map<String, Object>();
        
        if (jobs.isEmpty()) {
            status.put('scheduled', false);
        } else {
            status.put('scheduled', true);
            status.put('nextFireTime', jobs[0].NextFireTime);
            status.put('state', jobs[0].State);
            status.put('cronExpression', jobs[0].CronExpression);
        }
        
        return status;
    }
    
    @AuraEnabled
    public static void toggleSchedule(Boolean enable) {
        if (enable) {
            scheduleDaily();
        } else {
            unschedule();
        }
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
}
