package emberroutes.probe;
import java.util.*;
import se.krka.kahlua.vm.*;
import static emberroutes.probe.KernelValues.*;
/** Synchronous resource/record commit; policies are registered Lua domain contracts. */
public final class LaborCommitKernel {
    private LaborCommitKernel() {}
    private static Set<Object> keys(KahluaTable list) {
	Set<Object> r=new HashSet<>();if(list!=null)for(int i=1;i<=list.len();i++)r.add(list.rawget(i));return r;
    }
    private static boolean any(KahluaTable list) {return list!=null && list.len()>0;}
    private static void restore(KahluaTable claims,KahluaTable token,KahluaTable before) {
	ClaimsKernel.releaseCapacity(claims,token,null);
	if(yes(before.rawget("key"))) {
	    KahluaTableIterator it=t(before,"items").iterator();while(it.advance())
		require(ClaimsKernel.restore(claims,token,before.rawget("key"),it.getKey(),it.getValue()),"assertion failed!");
	}
    }
    private static KahluaTable unknown() {KahluaTable p=table();p.rawset("state","RECONCILE_REQUIRED");p.rawset("effects","UNKNOWN");return p;}
    private static void isolate(KahluaThread vm,KahluaTable owner,KahluaTable keys,String reason,Object id,Object rev,Object why) {
	for(int i=1;i<=keys.len();i++) {
	    KahluaTable evidence=table();evidence.rawset("jobId",id);evidence.rawset("rev",rev);evidence.rawset("why",text(why));
	    call(vm,owner.rawget("quarantineResource"),keys.rawget(i),reason,evidence);
	}
    }
    public static KahluaTable mutate(KahluaThread vm,KahluaTable store,KahluaTable owner,KahluaTable claims,KahluaTable contracts,Object cleanup,Object id,Object rev,Object payload,Object command) {
	Object record=first(method(vm,store,"get",id));
	KahluaTable job=yes(record)?t(record):null;
	if(job==null || !eq(job.rawget("revision"),rev))return result(false,"STALE_REVISION");
	Object runtimeToken=first(call(vm,owner.rawget("getToken"),id));
	KahluaTable token=yes(runtimeToken)?t(runtimeToken):null;
	if(token==null)return result(false,"NO_RUNTIME_TOKEN");
	if(!(payload instanceof KahluaTable proposed))return result(false,"PROPOSED_PAYLOAD_INVALID");
	KahluaTable mutation=yes(command)?t(command):null,add=t(mutation,"addKeys"),remove=t(mutation,"removeKeys");
	Set<Object> addSet=keys(add),removeSet=keys(remove),owned=keys(t(token,"resources"));
	if(add!=null && addSet.size()!=add.len())return result(false,"RESOURCE_DUPLICATED");
	for(Object key:addSet)if(removeSet.contains(key))return result(false,"MUTATION_KEYS_MUTUALLY_EXCLUSIVE_VIOLATION");
	for(Object key:addSet)if(owned.contains(key))return result(false,"ADD_KEYS_ALREADY_OWNED");
	if(proposed.rawget("claims")!=null) {
	    Set<Object> expected=new HashSet<>(owned);expected.removeAll(removeSet);expected.addAll(addSet);
	    KahluaTable list=t(proposed,"claims");Set<Object> actual=keys(list);
	    if(actual.size()!=list.len())return result(false,"RESOURCE_DUPLICATED");
	    if(!expected.equals(actual))return result(false,"CLAIMS_PAYLOAD_MISMATCH");
	}
	if(any(remove)) {String why=ClaimsKernel.canShrink(claims,token,remove);if(why!=null)return result(false,"SHRINK_FAILED:"+why);}
	Object cap=g(mutation,"capacity");
	if(cap!=null) {
	    KahluaTable rule=t(first(call(vm,contracts.rawget("get"),job.rawget("providerType"))));
	    if(!yes(g(rule,"capacityMutable")) || any(add) || !Boolean.FALSE.equals(cap) && !(cap instanceof KahluaTable))return result(false,"CAPACITY_MUTATION_UNSUPPORTED");
	    Object key=token.rawget("capacityKey");
	    KahluaTable prior=t(t(t(t(claims,"capacity"),key),"entries"),token.rawget("taskId")),expected=shallow(t(prior,"items"));
	    if(Boolean.FALSE.equals(cap)) {expected=table();key=null;}
	    else {
		KahluaTable c=t(cap);
		if(yes(c.rawget("releaseItemId")))expected.rawset(c.rawget("releaseItemId"),null);
		else {if(!(c.rawget("items") instanceof KahluaTable))return result(false,"CAPACITY_PAYLOAD_MISMATCH");expected=t(c,"items");key=c.rawget("key");}
	    }
	    KahluaTable reservation=yes(proposed.rawget("reservation"))?t(proposed,"reservation"):null;boolean any=false;KahluaTableIterator it=expected.iterator();
	    while(it.advance()) {
		any=true;
		if(reservation==null || !eq(reservation.rawget("key"),key) || !eq(g(t(reservation,"items"),it.getKey()),it.getValue()))return result(false,"CAPACITY_PAYLOAD_MISMATCH");
	    }
	    if(reservation!=null) {
		if(!any)return result(false,"CAPACITY_PAYLOAD_MISMATCH");
		KahluaTable items=t(reservation,"items");if(items!=null) {it=items.iterator();while(it.advance())if(!eq(expected.rawget(it.getKey()),it.getValue()))return result(false,"CAPACITY_PAYLOAD_MISMATCH");}
	    }
	}
	// Capacity commands reject addKeys above; no resource growth in this entry.
	KahluaTable before=null;
	if(cap!=null) {
	    Object key=token.rawget("capacityKey");KahluaTable previous=t(t(t(t(claims,"capacity"),key),"entries"),token.rawget("taskId"));
	    before=table();before.rawset("key",key);before.rawset("items",shallow(t(previous,"items")));
	    String why=null;
	    if(Boolean.FALSE.equals(cap))ClaimsKernel.releaseCapacity(claims,token,null);
	    else {
		KahluaTable c=t(cap);
		if(yes(c.rawget("releaseItemId")))ClaimsKernel.releaseCapacity(claims,token,c.rawget("releaseItemId"));
		else {
		    if(yes(key) && !eq(key,c.rawget("key")))ClaimsKernel.releaseCapacity(claims,token,null);
		    why=ClaimsKernel.reserveMany(claims,token,c.rawget("key"),t(c,"items"),c.rawget("free"));
		}
	    }
	    if(why!=null) {restore(claims,token,before);return result(false,why);}
	}
	KahluaTable patch=table();patch.rawset("payload",proposed);
	for(String f:new String[]{"state","effects","obligations"})if(yes(g(mutation,f)))patch.rawset(f,g(mutation,f));
	Object[] cas=method(vm,store,"update",id,rev,patch);Object next=cas.length>1?cas[1]:null;
	if(!yes(first(cas))) {
	    if(before!=null)restore(claims,token,before);
	    if(any(add))isolate(vm,owner,add,"CAS_FAILED",id,rev,next);
	    method(vm,store,"update",id,rev,unknown());return result(false,"CAS_FAILED_ISOLATED:"+text(next));
	}
	if(any(remove)) {
	    String why=ClaimsKernel.shrink(claims,token,remove);
	    if(why!=null) {isolate(vm,owner,remove,"SHRINK_POST_CAS_FAIL",id,next,why);method(vm,store,"update",id,next,unknown());return result(false,"SHRINK_FAILED_ISOLATED:"+why);}
	}
	if("DONE".equals(patch.rawget("state")) || "CANCELLED".equals(patch.rawget("state"))) {ClaimsKernel.release(claims,token);call(vm,cleanup,id);}
	return result(true,next);
    }
}
