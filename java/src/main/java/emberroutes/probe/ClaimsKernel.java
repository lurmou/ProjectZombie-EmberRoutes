package emberroutes.probe;

import java.util.HashSet;
import java.util.Set;
import se.krka.kahlua.vm.*;
import static emberroutes.probe.KernelValues.*;

/** Live operations over the SAME owners/capacity/token tables as Lua recovery.
 *  No copied ledger, static cache, inventory mutation or independent ownership. */
final class ClaimsKernel {
    private ClaimsKernel() {}
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
    public static String reserveMany(KahluaTable self,KahluaTable token,Object key,KahluaTable weights,Object free) {
	if(token==null || !(key instanceof String s) || s.isEmpty() || yes(g(token,"capacityKey")) && !eq(token.rawget("capacityKey"),key) || !nonnegative(free))return "CAPACITY_UNAVAILABLE";
	KahluaTable b=t(t(self,"capacity"),key),old=t(t(b,"entries"),token.rawget("taskId"));
	double total=0;int count=0;KahluaTableIterator it=weights.iterator();
	while(it.advance()) {count++;Object id=it.getKey(),amount=it.getValue();if(count>30 || !valid(self,token,"item:"+text(id)) || !nonnegative(amount))return "STALE_CLAIM";total+=n(amount);}
	if(count==0 || zero(g(b,"total"))-zero(g(old,"amount"))+total>n(free))return "CAPACITY_RESERVED";
	if(old!=null) {it=t(old,"items").iterator();while(it.advance())if(weights.rawget(it.getKey())==null)return "RESOURCE_SET_CHANGED";}
	it=weights.iterator();while(it.advance())require(restore(self,token,key,it.getKey(),it.getValue()),"BATCH_RESERVATION_INVALID");return null;
    }
    private static void releaseQuarantineCapacity(KahluaTable self,Object key) {
	KahluaTable capacity=t(self,"capacity");KahluaTableIterator it=capacity.iterator();
	while(it.advance()) {
	    KahluaTable b=t(it.getValue()),q=t(b,"quarantine"),entry=t(q,key);
	    if(entry!=null) {
		b.rawset("total",Math.max(0,n(b.rawget("total"))-n(entry.rawget("amount"))));q.rawset(key,null);
		if(q.isEmpty() && n(b.rawget("count"))==0)capacity.rawset(it.getKey(),null);
		return;
	    }
	}
    }
}
