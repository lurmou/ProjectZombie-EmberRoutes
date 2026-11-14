package emberroutes.probe;

import se.krka.kahlua.vm.*;
import static emberroutes.probe.KernelValues.*;

/** Reconstruction/isolation operations on the same ClaimsKernel graph.
 * No Job, durable receipt, world loop or independent ownership authority. */
final class ClaimsRecovery {
    private ClaimsRecovery() {}
    private static KahluaTable bucket() {
        KahluaTable b=table();b.rawset("entries",table());b.rawset("total",0.0);b.rawset("count",0.0);return b;
    }
    private static KahluaTable quarantineEntries(KahluaTable b) {
        KahluaTable q=t(b,"quarantine");
        if(q==null) {q=table();b.rawset("quarantine",q);}
        return q;
    }
    private static KahluaTable owner(Object key,Object task,Object token,Object claim,Object generation,Object cap,Object item,Object amount) {
        KahluaTable o=table();
        for(String f:new String[]{"kind","ownerId","taskId"})o.rawset(f,"SYSTEM_QUARANTINE");
        o.rawset("resource",key);o.rawset("originalTaskId",task);o.rawset("originalToken",token);
        o.rawset("originalClaimId",claim);o.rawset("originalGeneration",generation);
        o.rawset("capacityKey",cap);o.rawset("capacityItemId",item);o.rawset("capacityAmount",amount);
        return o;
    }
    private static void addEntry(KahluaTable b,Object key,KahluaTable owner,boolean includeToken) {
        KahluaTable e=table();e.rawset("amount",g(owner,"capacityAmount"));e.rawset("capacityKey",g(owner,"capacityKey"));
        e.rawset("itemId",g(owner,"capacityItemId"));
        for(String f:new String[]{"originalTaskId","originalClaimId","originalGeneration"})e.rawset(f,g(owner,f));
        if(includeToken)e.rawset("originalToken",g(owner,"originalToken"));
        quarantineEntries(b).rawset(key,e);
    }
    static KahluaTable quarantine(KahluaTable self,Object key) {
        KahluaTable owners=t(self,"owners"),capacity=t(self,"capacity"),previous=t(owners,key);
        Object task=null,token=null,claim=null,generation=null,cap=null,item=null,amount=null;
        if(previous!=null && !"SYSTEM_QUARANTINE".equals(g(previous,"kind"))) {
            task=g(previous,"taskId");token=previous;generation=g(previous,"generation");claim=g(previous,"claimId");
            if(!yes(claim))claim=text(task)+":c"+text(yes(generation)?generation:0.0);
            KahluaTable resources=t(previous,"resources");
            if(resources!=null) {
                KahluaTable keep=table();
                for(int i=1;i<=resources.len();i++)if(!eq(resources.rawget(i),key))keep.rawset(keep.len()+1,resources.rawget(i));
                previous.rawset("resources",keep);
            }
            if(key instanceof String s && s.startsWith("item:") && yes(g(previous,"capacityKey"))) {
                item=KahluaUtil.tonumber(s.substring(5),10);cap=g(previous,"capacityKey");
                KahluaTable b=t(capacity,cap),entry=t(t(b,"entries"),task),items=t(entry,"items");
                if(yes(g(items,item))) {
                    amount=g(items,item);items.rawset(item,null);add(entry,"count",-1);
                    entry.rawset("amount",Math.max(0,n(g(entry,"amount"))-n(amount)));
                    if(n(g(entry,"count"))==0) {
                        t(b,"entries").rawset(task,null);previous.rawset("capacityKey",null);add(b,"count",-1);
                    }
                    addEntry(b,key,owner(key,task,token,claim,generation,cap,item,amount),true);
                }
            }
        } else if(previous!=null) {
            task=g(previous,"originalTaskId");token=g(previous,"originalToken");claim=g(previous,"originalClaimId");
            generation=g(previous,"originalGeneration");cap=g(previous,"capacityKey");
            item=g(previous,"capacityItemId");amount=g(previous,"capacityAmount");
            if(yes(cap) && yes(item) && yes(amount) && n(amount)>0) {
                KahluaTable b=t(capacity,cap);if(b==null)b=bucket();
                addEntry(b,key,owner(key,task,token,claim,generation,cap,item,amount),true);capacity.rawset(cap,b);
            }
        }
        KahluaTable next=owner(key,task,token,claim,generation,cap,item,amount);
        owners.rawset(key,next);add(self,"revision",1);return result(true,next);
    }
    private static Object or(Object a,Object b) {return yes(a)?a:b;}
    static KahluaTable restore(KahluaTable self,Object key,KahluaTable record) {
        Object task=or(g(record,"originalTaskId"),g(record,"taskId")),claim=g(record,"originalClaimId"),generation=g(record,"originalGeneration");
        Object cap=g(record,"capacityKey"),item=or(g(record,"capacityItemId"),g(record,"itemId")),amount=or(g(record,"capacityAmount"),g(record,"amount"));
        KahluaTable owners=t(self,"owners"),previous=t(owners,key),next=owner(key,task,null,claim,generation,cap,item,amount);
        if(previous!=null) {
            if(!"SYSTEM_QUARANTINE".equals(g(previous,"kind")))return result(false,"QUARANTINE_RESTORE_OWNER_CONFLICT");
            for(String f:new String[]{"originalTaskId","originalClaimId","originalGeneration","capacityKey","capacityItemId","capacityAmount"})
                if(!eq(g(previous,f),g(next,f)))return result(false,"QUARANTINE_RESTORE_CONFLICT");
            return result(true,previous);
        }
        owners.rawset(key,next);
        if(yes(cap) && yes(item) && yes(amount) && n(amount)>0) {
            KahluaTable capacity=t(self,"capacity"),b=t(capacity,cap);if(b==null)b=bucket();
            addEntry(b,key,next,false);add(b,"total",n(amount));capacity.rawset(cap,b);
        }
        add(self,"revision",1);return result(true,next);
    }
    static KahluaTable resolve(KahluaTable self,Object key,KahluaTable resolution) {
        KahluaTable owners=t(self,"owners"),current=t(owners,key);
        if(current==null || !"SYSTEM_QUARANTINE".equals(g(current,"kind")))return result(false,"NOT_QUARANTINED");
        if("RETAIN".equals(g(resolution,"capacityAction"))) {
            Object target=or(g(resolution,"targetToken"),g(resolution,"recipientToken"));
            if(!(target instanceof KahluaTable token) || !yes(g(token,"taskId")))return result(false,"CAPACITY_RETAIN_WITHOUT_RECIPIENT_REJECTED");
            if(g(t(self,"tokensByTaskId"),g(token,"taskId"))!=token)return result(false,"CAPACITY_RETAIN_RECIPIENT_TOKEN_INVALID");
            KahluaTable b=null,entry=null;Object cap=null;
            KahluaTableIterator it=t(self,"capacity").iterator();
            while(it.advance()) {KahluaTable candidate=t(it.getValue()),q=t(t(candidate,"quarantine"),key);if(q!=null){b=candidate;entry=q;cap=it.getKey();break;}}
            if(entry==null)return result(false,"QUARANTINE_CAPACITY_ENTRY_NOT_FOUND");
            if(yes(g(token,"capacityKey")) && !eq(g(token,"capacityKey"),cap))return result(false,"CAPACITY_TARGET_CHANGED");
            KahluaTable allocations=t(b,"entries"),allocation=t(allocations,g(token,"taskId"));
            if(allocation!=null && g(allocation,"token")!=token)return result(false,"CAPACITY_ENTRY_OCCUPIED_BY_ANOTHER_TOKEN");
            t(b,"quarantine").rawset(key,null);token.rawset("capacityKey",cap);
            if(allocation==null) {
                allocation=table();allocation.rawset("items",table());allocation.rawset("amount",0.0);allocation.rawset("count",0.0);
                allocations.rawset(g(token,"taskId"),allocation);add(b,"count",1);
            }
            Object item=g(entry,"itemId"),amount=g(entry,"amount");KahluaTable items=t(allocation,"items");
            if(g(items,item)==null)add(allocation,"count",1);
            items.rawset(item,zero(g(items,item))+n(amount));add(allocation,"amount",n(amount));allocation.rawset("token",token);
        } else ClaimsKernel.releaseQuarantineCapacity(self,key);
        owners.rawset(key,null);add(self,"revision",1);return result(true,null);
    }
}
