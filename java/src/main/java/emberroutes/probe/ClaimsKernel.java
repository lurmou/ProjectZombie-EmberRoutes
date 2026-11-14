package emberroutes.probe;

import java.util.HashSet;
import java.util.Set;
import se.krka.kahlua.vm.*;
import static emberroutes.probe.KernelValues.*;

/** Live operations over the SAME owners/capacity/token tables as Lua recovery.
 *  No copied ledger, static cache, inventory mutation or independent ownership. */
public final class ClaimsKernel {
    private ClaimsKernel() {}
    /** Fixed bridge operations; no Lua mutation fallback or second graph. */
    public static KahluaTable command(KahluaTable self,String operation,KahluaTable args) {
        if ("NEW".equals(operation)) {
            KahluaTable state=table();
            for (String key:new String[]{"owners","capacity","tokensByTaskId"}) state.rawset(key,table());
            state.rawset("revision",0.0);state.rawset("nextClaimSeq",g(args,"nextClaimSeq")==null?1.0:g(args,"nextClaimSeq"));
            return result(true,state);
        }
        KahluaTable token=t(args,"token");Object key=g(args,"key"),item=g(args,"itemId");
        return switch(operation) {
            case "ACQUIRE_NEW" -> acquireNew(self,g(args,"taskId"),g(args,"generation"),t(args,"resources"),t(args,"envelope"));
            case "ACQUIRE" -> acquire(self,g(args,"taskId"),g(args,"generation"),t(args,"resources"),t(args,"envelope"));
            case "QUARANTINE" -> ClaimsRecovery.quarantine(self,key);
            case "RESTORE_QUARANTINE" -> ClaimsRecovery.restore(self,key,t(args,"record"));
            case "UNQUARANTINE" -> ClaimsRecovery.resolve(self,key,t(args,"resolution"));
            case "RELEASE_QUARANTINE_CAPACITY" -> releaseQuarantineCapacity(self,key);
            case "CAN_SHRINK" -> status(canShrink(self,token,g(args,"resources")));
            case "SHRINK" -> status(shrink(self,token,t(args,"resources")));
            case "REPLACE" -> status(replace(self,token,t(args,"resources")));
            case "EXTEND" -> status(append(self,token,t(args,"resources"),false));
            case "RESERVE" -> status(reserve(self,token,key,item,g(args,"amount"),g(args,"free")));
            case "RESERVE_MANY" -> status(reserveMany(self,token,key,t(args,"weights"),g(args,"free")));
            case "RESTORE" -> result(restore(self,token,key,item,g(args,"amount")),null);
            case "RESTORE_WORK" -> result(setWorkCapacity(self,token,key,g(args,"amount"))==null,null);
            case "RELEASE" -> {release(self,token);yield result(true,null);}
            case "RELEASE_CAPACITY" -> {releaseCapacity(self,token,item);yield result(true,null);}
            case "FORGET_TOKEN" -> {t(self,"tokensByTaskId").rawset(g(args,"taskId"),null);yield result(true,null);}
            default -> result(false,"CLAIMS_OPERATION_INVALID");
        };
    }
    private static KahluaTable status(String reason) {return result(reason==null,reason);}
    private static Object claimId(KahluaTable self,Object id,KahluaTable envelope,KahluaTable previous) {
        Object supplied=g(envelope,"claimId");
        if(yes(supplied))return supplied;
        Object existing=g(previous,"claimId");
        return yes(existing)?existing:text(id)+":c"+text(g(self,"nextClaimSeq"));
    }
    static KahluaTable acquire(KahluaTable self,Object id,Object generation,KahluaTable resources,KahluaTable envelope) {
        KahluaTable owners=t(self,"owners"),previous=null;Set<Object> seen=new HashSet<>();
        for(int i=1;i<=resources.len();i++) {
            Object key=resources.rawget(i);
            if(!seen.add(key))return result(false,"RESOURCE_DUPLICATED");
            KahluaTable owner=t(owners,key);
            if(owner!=null) {
                if(quarantine(owner))return result(false,"RESOURCE_SYSTEM_QUARANTINED");
                if(!eq(g(owner,"taskId"),id))return result(false,"ITEM_RESERVED");
            }
            if(previous==null)previous=owner;
        }
        if(previous!=null) {
            KahluaTable before=t(previous,"resources");
            for(int i=1;i<=before.len();i++)if(!seen.contains(before.rawget(i)))return result(false,"RESOURCE_SET_CHANGED");
            for(int i=1;i<=resources.len();i++)if(g(owners,resources.rawget(i))!=previous)return result(false,"RESOURCE_SET_CHANGED");
        }
        KahluaTable token=table();token.rawset("taskId",id);token.rawset("generation",generation);
        token.rawset("claimId",claimId(self,id,envelope,previous));token.rawset("resources",resources);add(self,"nextClaimSeq",1);
        for(int i=1;i<=resources.len();i++)owners.rawset(resources.rawget(i),token);
        t(self,"tokensByTaskId").rawset(id,token);
        if(previous==null && resources.len()>0)add(self,"revision",1);
        Object capacityKey=g(previous,"capacityKey");KahluaTable entry=t(t(t(t(self,"capacity"),capacityKey),"entries"),id);
        if(yes(capacityKey) && entry!=null && g(entry,"token")==previous) {
            entry.rawset("token",token);token.rawset("capacityKey",capacityKey);
        }
        return result(true,token);
    }
    private static boolean valid(KahluaTable self,KahluaTable token,Object key) {return token!=null && g(t(self,"owners"),key)==token;}
    private static boolean quarantine(KahluaTable owner) {return "SYSTEM_QUARANTINE".equals(g(owner,"kind"));}
    private static boolean mine(KahluaTable owner,KahluaTable token) {
	return g(owner,"originalToken")==token || g(owner,"originalClaimId")!=null && g(token,"claimId")!=null
	    && eq(g(owner,"originalClaimId"),g(token,"claimId"));
    }
    private static KahluaTable bucket() {KahluaTable b=table();b.rawset("entries",table());b.rawset("total",0.0);b.rawset("count",0.0);return b;}
    private static KahluaTable allocation(KahluaTable token) {
	KahluaTable c=table();c.rawset("token",token);c.rawset("items",table());c.rawset("amount",0.0);c.rawset("count",0.0);return c;
    }
    public static KahluaTable acquireNew(KahluaTable self,Object id,Object generation,KahluaTable resources,KahluaTable envelope) {
        KahluaTable owners=t(self,"owners"),tokens=t(self,"tokensByTaskId");
        if(g(tokens,id)!=null)return result(false,"TASK_ALREADY_HAS_CLAIMS");
        KahluaTableIterator it=owners.iterator();
        while(it.advance())if(eq(g(t(it.getValue()),"taskId"),id))return result(false,"TASK_ALREADY_HAS_CLAIMS");
        Set<Object> seen=new HashSet<>();
        for(int i=1;i<=resources.len();i++) {
            Object key=resources.rawget(i);
            if(!(key instanceof String) || !seen.add(key))return result(false,"RESOURCE_DUPLICATED");
            KahluaTable owner=t(owners,key);
            if(owner!=null)return result(false,quarantine(owner)?"RESOURCE_SYSTEM_QUARANTINED":"ITEM_RESERVED");
        }
        KahluaTable token=table();token.rawset("taskId",id);token.rawset("generation",generation);
        token.rawset("resources",shallow(resources));token.rawset("claimId",claimId(self,id,envelope,null));
        add(self,"nextClaimSeq",1);
        for(int i=1;i<=resources.len();i++)owners.rawset(resources.rawget(i),token);
        tokens.rawset(id,token);if(resources.len()>0)add(self,"revision",1);
        return result(true,token);
    }
    public static String extend(KahluaTable self,KahluaTable token,KahluaTable additions) {
        return append(self,token,additions,true);
    }
    /** Commit additions must be disjoint; domain append is idempotent. */
    private static String append(KahluaTable self,KahluaTable token,KahluaTable additions,boolean strict) {
        if(token==null)return "STALE_CLAIM";
        KahluaTable owners=t(self,"owners"),resources=t(token,"resources");
        Set<Object> seen=new HashSet<>();
        for(int i=1;i<=resources.len();i++) {
            Object key=resources.rawget(i);if(g(owners,key)!=token)return "STALE_CLAIM";seen.add(key);
        }
        KahluaTable added=table();
        for(int i=1;i<=additions.len();i++) {
            Object key=additions.rawget(i);
            if(strict && (!(key instanceof String) || seen.contains(key)))return "RESOURCE_DUPLICATED";
            if(!seen.add(key))continue;
            KahluaTable owner=t(owners,key);
            if(owner!=null && (strict || owner!=token))return !strict && quarantine(owner)?"RESOURCE_SYSTEM_QUARANTINED":"ITEM_RESERVED";
            added.rawset(added.len()+1,key);
        }
        if(strict) {resources=shallow(resources);token.rawset("resources",resources);}
        for(int i=1;i<=added.len();i++) {
            Object key=added.rawget(i);resources.rawset(resources.len()+1,key);owners.rawset(key,token);
        }
        if(added.len()>0)add(self,"revision",1);
        return null;
    }
    private static String replace(KahluaTable self,KahluaTable token,KahluaTable resources) {
        if(token==null)return "STALE_CLAIM";
        Object cap=g(token,"capacityKey");KahluaTable entry=t(t(t(t(self,"capacity"),cap),"entries"),g(token,"taskId"));
        if(yes(cap) && (entry==null || g(entry,"token")!=token))return "STALE_CLAIM";
        KahluaTable owners=t(self,"owners"),before=t(token,"resources");Set<Object> seen=new HashSet<>();
        for(int i=1;i<=before.len();i++)if(g(owners,before.rawget(i))!=token)return "STALE_CLAIM";
        for(int i=1;i<=resources.len();i++) {
            Object key=resources.rawget(i);if(!seen.add(key))return "RESOURCE_DUPLICATED";
            KahluaTable owner=t(owners,key);
            if(owner!=null && owner!=token)return quarantine(owner)?"RESOURCE_SYSTEM_QUARANTINED":"ITEM_RESERVED";
        }
        boolean changed=false;
        for(int i=1;i<=before.len();i++)if(!seen.contains(before.rawget(i))) {owners.rawset(before.rawget(i),null);changed=true;}
        for(int i=1;i<=resources.len();i++) {Object key=resources.rawget(i);if(g(owners,key)==null)changed=true;owners.rawset(key,token);}
        token.rawset("resources",resources);if(changed)add(self,"revision",1);return null;
    }
    public static String canShrink(KahluaTable self,KahluaTable token,Object released) {
	if(token==null || !(released instanceof KahluaTable keys))return "STALE_CLAIM";
	KahluaTable owners=t(self,"owners"),resources=t(token,"resources");Set<Object> owned=new HashSet<>(),drop=new HashSet<>();
	for(int i=1;i<=resources.len();i++) {Object k=resources.rawget(i);if(owners.rawget(k)!=token)return "STALE_CLAIM";owned.add(k);}
	for(int i=1;i<=keys.len();i++) {
	    Object k=keys.rawget(i);if(!drop.add(k))return "RESOURCE_SET_CHANGED";
	    if(!owned.contains(k)) {KahluaTable o=t(owners,k);if(o==null || !quarantine(o) || !mine(o,token))return "RESOURCE_SET_CHANGED";}
	}
	Object cap=token.rawget("capacityKey");KahluaTable c=t(t(t(t(self,"capacity"),cap),"entries"),token.rawget("taskId"));
	if(yes(cap) && (c==null || c.rawget("token")!=token))return "STALE_CLAIM";
	return null;
    }
    public static String shrink(KahluaTable self,KahluaTable token,KahluaTable keys) {
	String reason=canShrink(self,token,keys);if(reason!=null)return reason;
	Set<Object> drop=new HashSet<>();for(int i=1;i<=keys.len();i++)drop.add(keys.rawget(i));
	KahluaTable keep=table(),resources=t(token,"resources"),owners=t(self,"owners");
	for(int i=1;i<=resources.len();i++)if(!drop.contains(resources.rawget(i)))keep.rawset(keep.len()+1,resources.rawget(i));
	for(int i=1;i<=keys.len();i++) {
	    Object key=keys.rawget(i);String s=(String)key;
	    if(s.startsWith("item:"))releaseCapacity(self,token,se.krka.kahlua.vm.KahluaUtil.tonumber(s.substring(5),10));
	    KahluaTable owner=t(owners,key);
	    if(owner==token)owners.rawset(key,null);
	    else if(owner!=null && quarantine(owner) && mine(owner,token)) {
		for(String f:new String[]{"originalTaskId","originalToken","originalClaimId","originalGeneration"})owner.rawset(f,null);
		if(s.startsWith("item:"))releaseQuarantineCapacity(self,key);
	    }
	}
	token.rawset("resources",keep);if(keys.len()>0)add(self,"revision",1);return null;
    }
    public static void releaseCapacity(KahluaTable self,KahluaTable token,Object itemId) {
	Object key=g(token,"capacityKey");KahluaTable capacity=t(self,"capacity"),b=t(capacity,key),entries=t(b,"entries"),c=t(entries,g(token,"taskId"));
	if(c==null || c.rawget("token")!=token)return;
	KahluaTable items=t(c,"items");Object amount=yes(itemId)?items.rawget(itemId):c.rawget("amount");if(amount==null)return;
	if(yes(itemId)) {items.rawset(itemId,null);add(c,"count",-1);}else c.rawset("count",0.0);
	c.rawset("amount",Math.max(0,n(c.rawget("amount"))-n(amount)));b.rawset("total",Math.max(0,n(b.rawget("total"))-n(amount)));
	if(n(c.rawget("count"))==0) {
	    entries.rawset(token.rawget("taskId"),null);token.rawset("capacityKey",null);add(b,"count",-1);
	    if(n(b.rawget("count"))==0 && (t(b,"quarantine")==null || t(b,"quarantine").isEmpty()))capacity.rawset(key,null);
	}
    }
    public static void release(KahluaTable self,KahluaTable token) {
	if(token==null)return;KahluaTable owners=t(self,"owners"),keys=t(token,"resources");boolean changed=false;
	for(int i=1;i<=keys.len();i++)if(owners.rawget(keys.rawget(i))==token) {owners.rawset(keys.rawget(i),null);changed=true;}
	KahluaTable tokens=t(self,"tokensByTaskId");if(tokens!=null && g(token,"taskId")!=null && tokens.rawget(token.rawget("taskId"))==token)tokens.rawset(token.rawget("taskId"),null);
	if(changed)add(self,"revision",1);releaseCapacity(self,token,null);
    }
    public static boolean restore(KahluaTable self,KahluaTable token,Object key,Object itemId,Object amount) {
	if(!valid(self,token,"item:"+text(itemId)) || !(key instanceof String s) || s.isEmpty() || !nonnegative(amount))return false;
	if(yes(g(token,"capacityKey")) && !eq(token.rawget("capacityKey"),key))return false;
	KahluaTable capacity=t(self,"capacity"),b=t(capacity,key);if(b==null)b=bucket();
	KahluaTable entries=t(b,"entries"),c=t(entries,token.rawget("taskId"));if(c==null) {add(b,"count",1);c=allocation(token);}
	KahluaTable items=t(c,"items");double old=zero(items.rawget(itemId));if(items.rawget(itemId)==null)add(c,"count",1);
	items.rawset(itemId,amount);c.rawset("amount",n(c.rawget("amount"))-old+n(amount));b.rawset("total",n(b.rawget("total"))-old+n(amount));
	entries.rawset(token.rawget("taskId"),c);capacity.rawset(key,b);token.rawset("capacityKey",key);return true;
    }
    static boolean validWorkEntry(KahluaTable self,KahluaTable token,Object key,KahluaTable entry) {
        return g(entry,"workAmount")!=null && g(entry,"token")==token
            && g(entry,"items") instanceof KahluaTable items && items.isEmpty()
            && g(entry,"count") instanceof Number count && count.doubleValue()==0
            && valid(self,token,"cooking:capacity:"+text(g(token,"taskId")))
            && eq(key,g(token,"capacityKey"));
    }
    /** Stable batch promise in the same bucket as item allocations; Lua restoreWork. */
    public static String setWorkCapacity(KahluaTable self,KahluaTable token,Object key,Object amount) {
        if(token==null || !valid(self,token,"cooking:capacity:"+text(g(token,"taskId"))))return "STALE_CLAIM";
        if(!(key instanceof String s) || s.isEmpty() || !(amount instanceof Number value)
            || !Double.isFinite(value.doubleValue()) || value.doubleValue()<=0)return "CAPACITY_UNAVAILABLE";
        if(yes(g(token,"capacityKey")) && !eq(g(token,"capacityKey"),key))return "CAPACITY_TARGET_CHANGED";
        KahluaTable capacity=t(self,"capacity"),b=t(capacity,key);if(b==null)b=bucket();
        KahluaTable entries=t(b,"entries"),claim=t(entries,g(token,"taskId"));
        if(claim!=null && (g(claim,"token")!=token || !(g(claim,"count") instanceof Number count) || count.doubleValue()!=0
            || !(g(claim,"items") instanceof KahluaTable items) || !items.isEmpty()
            || g(claim,"workAmount")!=null && !validWorkEntry(self,token,key,claim)))return "CAPACITY_UNAVAILABLE";
        if(claim==null) {add(b,"count",1);claim=allocation(token);}
        b.rawset("total",n(g(b,"total"))-n(g(claim,"amount"))+value.doubleValue());
        claim.rawset("amount",amount);claim.rawset("workAmount",amount);claim.rawset("token",token);
        entries.rawset(g(token,"taskId"),claim);capacity.rawset(key,b);token.rawset("capacityKey",key);
        return null;
    }
    /** Single reservation, matching Lua reserve; creation is not batch-limited. */
    public static String reserve(KahluaTable self,KahluaTable token,Object key,Object itemId,Object amount,Object free) {
        if(!valid(self,token,"item:"+text(itemId)))return "STALE_CLAIM";
        if(!nonnegative(amount) || !nonnegative(free))return "CAPACITY_UNAVAILABLE";
        if(yes(g(token,"capacityKey")) && !eq(g(token,"capacityKey"),key))return "CAPACITY_TARGET_CHANGED";
        KahluaTable b=t(t(self,"capacity"),key),old=t(t(b,"entries"),g(token,"taskId"));
        double before=zero(g(t(old,"items"),itemId));
        if(zero(g(b,"total"))-before+n(amount)>n(free))return "CAPACITY_RESERVED";
        return restore(self,token,key,itemId,amount)?null:"CAPACITY_UNAVAILABLE";
    }
    public static String reserveMany(KahluaTable self,KahluaTable token,Object key,KahluaTable weights,Object free) {
	if(token==null || !(key instanceof String s) || s.isEmpty() || yes(g(token,"capacityKey")) && !eq(token.rawget("capacityKey"),key) || !nonnegative(free))return "CAPACITY_UNAVAILABLE";
	KahluaTable b=t(t(self,"capacity"),key),old=t(t(b,"entries"),token.rawget("taskId"));
	double total=0;int count=0;KahluaTableIterator it=weights.iterator();
	while(it.advance()) {count++;Object id=it.getKey(),amount=it.getValue();if(count>30 || !valid(self,token,"item:"+text(id)) || !nonnegative(amount))return "STALE_CLAIM";total+=n(amount);}
	if(count==0 || zero(g(b,"total"))-zero(g(old,"amount"))+total>n(free))return "CAPACITY_RESERVED";
	if(old!=null) {it=t(old,"items").iterator();while(it.advance())if(weights.rawget(it.getKey())==null)return "RESOURCE_SET_CHANGED";}
	it=weights.iterator();while(it.advance())require(restore(self,token,key,it.getKey(),it.getValue()),"BATCH_RESERVATION_INVALID");return null;
    }
    static KahluaTable releaseQuarantineCapacity(KahluaTable self,Object key) {
	KahluaTable capacity=t(self,"capacity");KahluaTableIterator it=capacity.iterator();
	while(it.advance()) {
	    KahluaTable b=t(it.getValue()),q=t(b,"quarantine"),entry=t(q,key);
	    if(entry!=null) {
		b.rawset("total",Math.max(0,n(b.rawget("total"))-n(entry.rawget("amount"))));q.rawset(key,null);
		if(q.isEmpty() && n(b.rawget("count"))==0)capacity.rawset(it.getKey(),null);
		return result(true,g(entry,"amount"));
	    }
	}
        return result(false,null);
    }
}
