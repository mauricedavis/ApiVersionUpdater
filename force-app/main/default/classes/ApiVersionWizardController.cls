public with sharing class ApiVersionWizardController {

    public class CountsDTO {
        @AuraEnabled public Integer apexClasses;
        @AuraEnabled public Integer apexTriggers;
        @AuraEnabled public Integer vfPages;
        @AuraEnabled public Integer vfComponents;
        @AuraEnabled public Integer auraBundles;
        @AuraEnabled public Integer lwcBundles;
        @AuraEnabled public Decimal threshold;
        @AuraEnabled public Decimal target;
        @AuraEnabled public Boolean excludeManaged;
    }

    public class ItemDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String type;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal apiVersion;
        @AuraEnabled public String namespacePrefix;
    }

    public class PageDTO {
        @AuraEnabled public List<ItemDTO> items;
        @AuraEnabled public Integer total;
        @AuraEnabled public Integer pageNumber;
        @AuraEnabled public Integer pageSize;
    }

    public class UpdateReq { @AuraEnabled public String id; @AuraEnabled public String type; }
    public class UpdateRes { @AuraEnabled public String id; @AuraEnabled public String type; @AuraEnabled public Boolean success; @AuraEnabled public String message; }
    public class UpdateBatchResult { @AuraEnabled public List<UpdateRes> results; }

    // ---- Public ----
    @AuraEnabled(cacheable=true)
    public static CountsDTO getCounts(Decimal threshold, Decimal target, Boolean excludeManaged) {
        validateTT(threshold, target);
        CountsDTO dto = new CountsDTO();
        dto.threshold = threshold; dto.target = target; dto.excludeManaged = excludeManaged;

        String ns = excludeManaged ? ' AND NamespacePrefix = null' : '';

        dto.apexClasses  = (Integer)Database.countQuery('SELECT COUNT() FROM ApexClass WHERE ApiVersion < :threshold' + ns);
        dto.apexTriggers = (Integer)Database.countQuery('SELECT COUNT() FROM ApexTrigger WHERE ApiVersion < :threshold' + ns);
        dto.vfPages      = (Integer)Database.countQuery('SELECT COUNT() FROM ApexPage WHERE ApiVersion < :threshold' + ns);
        dto.vfComponents = (Integer)Database.countQuery('SELECT COUNT() FROM ApexComponent WHERE ApiVersion < :threshold' + ns);

        dto.auraBundles = toolingCount('SELECT Id FROM AuraDefinitionBundle WHERE ApiVersion < ' + threshold + (excludeManaged ? ' AND NamespacePrefix = null' : ''));
        dto.lwcBundles  = toolingCount('SELECT Id FROM LightningComponentBundle WHERE ApiVersion < ' + threshold + (excludeManaged ? ' AND NamespacePrefix = null' : ''));

        return dto;
    }

    @AuraEnabled(cacheable=true)
    public static PageDTO getItems(Decimal threshold, Boolean excludeManaged, Integer pageNumber, Integer pageSize) {
        validateThreshold(threshold);
        Integer page = pageNumber == null || pageNumber < 1 ? 1 : pageNumber;
        Integer size = pageSize == null || pageSize < 1 ? 50 : Math.min(200, pageSize);

        List<ItemDTO> all = new List<ItemDTO>();
        String ns = excludeManaged ? ' AND NamespacePrefix = null' : '';

        // Use dynamic SOQL so we can append the namespace filter cleanly
        String q1 = 'SELECT Id, Name, ApiVersion, NamespacePrefix FROM ApexClass WHERE ApiVersion < :threshold' + ns + ' ORDER BY Name LIMIT 2000';
        for (ApexClass a : Database.query(q1)) all.add(item('ApexClass', a.Id, a.Name, a.ApiVersion, a.NamespacePrefix));

        String q2 = 'SELECT Id, Name, ApiVersion, NamespacePrefix FROM ApexTrigger WHERE ApiVersion < :threshold' + ns + ' ORDER BY Name LIMIT 2000';
        for (ApexTrigger t : Database.query(q2)) all.add(item('ApexTrigger', t.Id, t.Name, t.ApiVersion, t.NamespacePrefix));

        String q3 = 'SELECT Id, Name, ApiVersion, NamespacePrefix FROM ApexPage WHERE ApiVersion < :threshold' + ns + ' ORDER BY Name LIMIT 2000';
        for (ApexPage p : Database.query(q3)) all.add(item('ApexPage', p.Id, p.Name, p.ApiVersion, p.NamespacePrefix));

        String q4 = 'SELECT Id, Name, ApiVersion, NamespacePrefix FROM ApexComponent WHERE ApiVersion < :threshold' + ns + ' ORDER BY Name LIMIT 2000';
        for (ApexComponent c : Database.query(q4)) all.add(item('ApexComponent', c.Id, c.Name, c.ApiVersion, c.NamespacePrefix));

        all.addAll(toolingItems('AuraDefinitionBundle',
            'SELECT Id, DeveloperName, ApiVersion, NamespacePrefix FROM AuraDefinitionBundle WHERE ApiVersion < ' + threshold + (excludeManaged ? ' AND NamespacePrefix = null' : '') + ' ORDER BY DeveloperName LIMIT 2000'));

        all.addAll(toolingItems('LightningComponentBundle',
            'SELECT Id, DeveloperName, ApiVersion, NamespacePrefix FROM LightningComponentBundle WHERE ApiVersion < ' + threshold + (excludeManaged ? ' AND NamespacePrefix = null' : '') + ' ORDER BY DeveloperName LIMIT 2000'));

        all.sort(new Comparator());

        Integer total = all.size();
        Integer fromIdx = (page - 1) * size;
        Integer toIdx = Math.min(total, fromIdx + size);
        List<ItemDTO> pageItems = (fromIdx < total) ? all.subList(fromIdx, toIdx) : new List<ItemDTO>();

        PageDTO dto = new PageDTO();
        dto.items = pageItems; dto.total = total; dto.pageNumber = page; dto.pageSize = size;
        return dto;
    }

    @AuraEnabled
    public static UpdateBatchResult updateApiVersions(Decimal target, List<UpdateReq> items) {
        if (target == null || target <= 0) throw new AuraHandledException('Invalid target version.');
        UpdateBatchResult br = new UpdateBatchResult(); br.results = new List<UpdateRes>();
        if (items == null || items.isEmpty()) return br;

        for (UpdateReq req : items) {
            UpdateRes r = new UpdateRes(); r.id = req.id; r.type = req.type;
            try {
                Boolean ok = toolingUpdate(req.type, req.id, target);
                r.success = ok; r.message = ok ? 'OK' : 'Failed';
            } catch (Exception e) {
                r.success = false; r.message = e.getMessage();
            }
            br.results.add(r);
        }
        return br;
    }

    // ---- Helpers ----
    private static void validateTT(Decimal threshold, Decimal target) {
        validateThreshold(threshold);
        if (target == null || target <= 0) throw new AuraHandledException('Invalid target.');
        if (threshold >= target) throw new AuraHandledException('Threshold must be less than target.');
    }
    private static void validateThreshold(Decimal threshold) {
        if (threshold == null || threshold <= 0) throw new AuraHandledException('Invalid threshold.');
    }

    private static ItemDTO item(String type, Id id, String name, Decimal apiVersion, String ns) {
        ItemDTO i = new ItemDTO(); i.type = type; i.id = (String)id; i.name = name; i.apiVersion = apiVersion; i.namespacePrefix = ns; return i;
    }

    public class Comparator implements System.Comparator<ItemDTO> {
        public Integer compare(ItemDTO a, ItemDTO b) {
            Integer t = a.type.compareToIgnoreCase(b.type);
            if (t != 0) return t;
            return a.name.compareToIgnoreCase(b.name);
        }
    }

    private static String apiVer() { return 'v63.0'; }
    private static String baseUrl() { return URL.getSalesforceBaseUrl().toExternalForm(); }

    private static Map<String,Object> toolingQuery(String soql) {
        String endpoint = baseUrl() + '/services/data/' + apiVer() + '/tooling/query/?q=' + EncodingUtil.urlEncode(soql, 'UTF-8');
        HttpRequest req = new HttpRequest();
        req.setMethod('GET'); req.setEndpoint(endpoint);
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        req.setHeader('Content-Type', 'application/json');
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() > 299) {
            throw new AuraHandledException('Tooling query failed (' + res.getStatusCode() + '): ' + res.getStatus());
        }
        return (Map<String,Object>) JSON.deserializeUntyped(res.getBody());
    }

    private static Integer toolingCount(String soql) {
        Map<String,Object> json = toolingQuery(soql);
        Object total = json.get('totalSize');
        if (total == null) return 0;
        if (total instanceof Integer) return (Integer) total;
        return Integer.valueOf(String.valueOf(total));
    }

    private static List<ItemDTO> toolingItems(String type, String soql) {
        List<ItemDTO> out = new List<ItemDTO>();
        Map<String,Object> json = toolingQuery(soql);
        List<Object> recs = (List<Object>) json.get('records');
        if (recs != null) {
            for (Object o : recs) {
                Map<String,Object> m = (Map<String,Object>) o;
                String id = (String) m.get('Id');
                String name = (String) m.get('DeveloperName');
                Decimal ver = (m.get('ApiVersion') == null) ? 0 : Decimal.valueOf(String.valueOf(m.get('ApiVersion')));
                String ns = (String) m.get('NamespacePrefix');
                out.add(item(type, (Id) id, name, ver, ns));
            }
        }
        return out;
    }

    private static Boolean toolingUpdate(String type, String id, Decimal target) {
        String endpoint = baseUrl() + '/services/data/' + apiVer() + '/tooling/sobjects/' + type + '/' + id;
        HttpRequest req = new HttpRequest();
        req.setMethod('PATCH'); req.setEndpoint(endpoint);
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(new Map<String,Object>{ 'ApiVersion' => target }));
        HttpResponse res = new Http().send(req);
        Integer sc = res.getStatusCode();
        if (sc == 204 || sc == 200) return true;

        // Try parse common error format
        try {
            Object parsed = JSON.deserializeUntyped(res.getBody());
            if (parsed instanceof List<Object>) {
                List<Object> errs = (List<Object>) parsed;
                if (!errs.isEmpty()) {
                    Map<String,Object> e0 = (Map<String,Object>) errs[0];
                    String msg = (String) e0.get('message');
                    if (msg != null) throw new AuraHandledException(msg);
                }
            }
        } catch (Exception ignore) {}
        throw new AuraHandledException('Update failed (' + sc + '): ' + res.getStatus());
    }
}
