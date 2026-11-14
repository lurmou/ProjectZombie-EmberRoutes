package emberroutes.probe;
import java.util.*;
import se.krka.kahlua.vm.*;
import static emberroutes.probe.KernelValues.*;

/** One synchronous commit sequence. Lua owns envelope/domain/transition policy.
 * No receipts, retry cache, persistent recovery queue or business rules. */
public final class LaborCommitKernel {
    private LaborCommitKernel() {}
    private static Set<Object> keys(KahluaTable list) {
        Set<Object> r=new HashSet<>();
        if(list!=null)for(int i=1;i<=list.len();i++)r.add(list.rawget(i));
        return r;
    }
    private static boolean any(KahluaTable list) {return list!=null && list.len()>0;}
    private static KahluaTable failure(String code,Object why) {
        KahluaTable r=result(false,code);r.rawset("evidence",text(why));return r;
    }
    /** Invocation-local resource snapshot; one restore attempt, no recovery authority. */
    private static final class Tx {
        final KahluaTable claims;
        KahluaTable token,before,resources;
        boolean touched,casReached,created;
        Object next,claimsRevision,generation;
        Tx(KahluaTable c) {claims=c;}
        void snapshot() {
            claimsRevision=g(claims,"revision");
            generation=g(token,"generation");
            resources=shallow(t(token,"resources"));
            Object key=g(token,"capacityKey");
            KahluaTable previous=t(t(t(t(claims,"capacity"),key),"entries"),g(token,"taskId"));
            before=table();before.rawset("key",key);before.rawset("items",shallow(t(previous,"items")));
            before.rawset("workExists",g(previous,"workAmount")!=null);
            before.rawset("workAmount",zero(g(previous,"workAmount")));
            before.rawset("workKey",key);
        }
        boolean restore() {
            try {
                if(created) {ClaimsKernel.release(claims,token);return true;}
                if(!touched)return true;
                KahluaTable owners=t(claims,"owners");
                // Never overwrite a foreign owner, even during the single restore.
                for(int i=1;i<=resources.len();i++) {
                    Object owner=g(owners,resources.rawget(i));
                    if(owner!=null && owner!=token)return false;
                }
                KahluaTable current=t(token,"resources");
                Set<Object> original=keys(resources);
                for(int i=1;i<=current.len();i++) {
                    Object key=current.rawget(i);
                    if(!original.contains(key) && g(owners,key)==token)owners.rawset(key,null);
                }
                for(int i=1;i<=resources.len();i++)owners.rawset(resources.rawget(i),token);
                token.rawset("resources",resources);
                token.rawset("generation",generation);
                ClaimsKernel.releaseCapacity(claims,token,null);
                KahluaTableIterator it=t(before,"items").iterator();
                while(it.advance())if(!ClaimsKernel.restore(claims,token,g(before,"key"),it.getKey(),it.getValue()))return false;
                if(yes(g(before,"workExists")) && ClaimsKernel.setWorkCapacity(claims,token,
                    g(before,"workKey"),g(before,"workAmount"))!=null)return false;
                claims.rawset("revision",claimsRevision);
                return true;
            } catch(RuntimeException error) {return false;}
        }
        KahluaTable fail(String code,Object why) {
            if(!casReached && !restore())return failure("ROLLBACK_FAILURE","RECONCILE_REQUIRED:PARTIAL_RESTORE:"+text(why));
            // CAS callbacks may throw after publishing. Never compensate or publish again.
            return failure(code,(casReached?"CAS_REACHED_RELOAD_FROM_SAVE:":"")+text(why));
        }
    }
    public static KahluaTable mutate(KahluaThread vm,KahluaTable store,KahluaTable owner,KahluaTable claims,KahluaTable contracts,Object cleanup,Object id,Object rev,Object payload,Object command) {
        return change(vm,store,owner,claims,contracts,cleanup,id,rev,payload,command,false);
    }
    public static KahluaTable cancel(KahluaThread vm,KahluaTable store,KahluaTable owner,KahluaTable claims,KahluaTable contracts,Object cleanup,Object id,Object rev,Object payload,Object command) {
        return change(vm,store,owner,claims,contracts,cleanup,id,rev,payload,command,true);
    }
    /** Rotate the exact cooking claim before publishing the new Job owner. */
    public static KahluaTable transfer(KahluaThread vm,KahluaTable store,KahluaTable state,Object id,Object rev,KahluaTable candidate,KahluaTable expected,Object obligationOps) {
        boolean published=false,rotated=false;
        KahluaTable claims=t(state,"claims"),owners=t(claims,"owners"),tokens=t(claims,"tokensByTaskId"),bucketTokens=t(state,"cookingTokens");
        KahluaTable replacement=null,capacityEntry=null; Object previousSequence=g(claims,"nextClaimSeq");
        try {
            KahluaTable job=t(first(method(vm,store,"get",id)));
            if(job==null || !eq(g(job,"revision"),rev))return failure("COOKING_JOB_CHANGED","JOB_CHANGED");
            if(expected==null || g(bucketTokens,id)!=expected || g(tokens,id)!=expected
                || !eq(g(expected,"taskId"),id) || !eq(g(expected,"claimId"),g(job,"claimId")))
                return failure("COOKING_JOB_CHANGED","STALE_CLAIM_IDENTITY");
            KahluaTable resources=t(expected,"resources");
            if(resources==null)return failure("COOKING_JOB_CHANGED","RESOURCE_SET_MISSING");
            for(int i=1;i<=resources.len();i++)if(g(owners,resources.rawget(i))!=expected)
                return failure("COOKING_JOB_CHANGED","STALE_CLAIM");
            Object capacityKey=g(expected,"capacityKey");
            if(capacityKey!=null) {
                capacityEntry=t(t(t(t(claims,"capacity"),capacityKey),"entries"),id);
                if(capacityEntry==null || g(capacityEntry,"token")!=expected)
                    return failure("COOKING_JOB_CHANGED","STALE_CAPACITY");
            }
            replacement=table();replacement.rawset("taskId",id);replacement.rawset("claimId",g(expected,"claimId"));
            replacement.rawset("generation",g(t(candidate,"payload"),"sequence"));
            replacement.rawset("resources",shallow(resources));
            rotated=true; // Any subsequent exception may have changed the claim graph.
            if(capacityEntry!=null) {replacement.rawset("capacityKey",capacityKey);capacityEntry.rawset("token",replacement);}
            for(int i=1;i<=resources.len();i++)owners.rawset(resources.rawget(i),replacement);
            tokens.rawset(id,replacement);bucketTokens.rawset(id,replacement);
            claims.rawset("nextClaimSeq",zero(previousSequence)+1);
            // The store validates the exact domain handoff and notifies only
            // after the replacement token is already authoritative.
            published=true;
            Object[] written=method(vm,store,"transferOwner",id,rev,candidate,obligationOps);
            if(!yes(first(written))) {
                published=false;
                for(int i=1;i<=resources.len();i++)if(g(owners,resources.rawget(i))!=replacement)
                    return failure("ROLLBACK_FAILURE","RECONCILE_REQUIRED:TRANSFER_OWNER_CHANGED");
                if(g(tokens,id)!=replacement || g(bucketTokens,id)!=replacement || capacityEntry!=null && g(capacityEntry,"token")!=replacement)
                    return failure("ROLLBACK_FAILURE","RECONCILE_REQUIRED:TRANSFER_TOKEN_CHANGED");
                for(int i=1;i<=resources.len();i++)owners.rawset(resources.rawget(i),expected);
                tokens.rawset(id,expected);bucketTokens.rawset(id,expected);
                if(capacityEntry!=null)capacityEntry.rawset("token",expected);
                claims.rawset("nextClaimSeq",previousSequence);rotated=false;
                return failure(written.length>1?text(written[1]):"COOKING_HANDOFF_CHANGED","TRANSFER_REJECTED");
            }
            return result(true,g(candidate,"revision"));
        } catch(RuntimeException error) {
            return failure(rotated && !published?"ROLLBACK_FAILURE":"TASK_WRITE_FAILURE",(published?"CAS_REACHED_RELOAD_FROM_SAVE:":rotated?"RECONCILE_REQUIRED:TRANSFER_ROTATION:":"")+text(error));
        }
    }
    /** Independent tool custody: one obligation candidate and its exact claim. */
    public static KahluaTable custody(KahluaThread vm,KahluaTable state,KahluaTable ledger,KahluaTable op,Object retirementVerifier) {
        KahluaTable root=t(state,"root"),claims=t(state,"claims"),cache=t(state,"custodyTokens");
        KahluaTable token=null; boolean acquired=false,released=false,published=false;
        Tx tx=new Tx(claims);
        try {
            Object id=g(op,"id"),action=g(op,"action");
            if(!(id instanceof String) || !(action instanceof String))return failure("INVALID_REQUEST","CUSTODY_INTENT_INVALID");
            KahluaTable before=t(root,"obligations"),old=t(t(before,"byId"),id);
            KahluaTable list=table();list.rawset(1.0,op);
            Object[] proposed=call(vm,g(ledger,"propose"),before,list,retirementVerifier);
            KahluaTable candidate=t(first(proposed));
            if(candidate==null)return failure("CUSTODY_REJECTED",proposed.length>1?proposed[1]:"OBLIGATION_REJECTED");
            if(g(root,"obligations")!=before)return failure("CUSTODY_REJECTED","OBLIGATION_CHANGED");
            KahluaTable record="CREATE".equals(action)?t(op,"record"):old;
            if(record==null || !"TOOL_CUSTODY".equals(g(record,"type")))return failure("INVALID_REQUEST","CUSTODY_TYPE_INVALID");
            KahluaTable data=t(record,"data"); Object itemId=g(data,"itemId"); String key="item:"+text(itemId);
            if("CREATE".equals(action)) {
                KahluaTable resources=table();resources.rawset(1.0,key);
                KahluaTable envelope=table();envelope.rawset("claimId",g(data,"claimId"));
                KahluaTable response=ClaimsKernel.acquireNew(claims,id,g(data,"sequence"),resources,envelope);
                if(!yes(g(response,"ok")))return failure("CLAIM_FAILURE",g(response,"result"));
                token=t(response,"result");acquired=true;cache.rawset(id,token);
            } else if("RETIRE".equals(action)) {
                KahluaTable itemOwner=t(t(claims,"owners"),key);
                if(!"SETTLED".equals(g(record,"state")) || g(cache,id)!=null || g(t(claims,"tokensByTaskId"),id)!=null
                    || itemOwner!=null && eq(g(itemOwner,"taskId"),id))return failure("CUSTODY_REJECTED","CUSTODY_RETIREMENT_UNPROVEN");
            } else {
                token=t(cache,id);
                if(!"RECONCILE".equals(action) && (token==null || g(t(claims,"tokensByTaskId"),id)!=token
                    || g(t(claims,"owners"),key)!=token || !eq(g(token,"claimId"),g(data,"claimId"))))
                    return failure("CLAIM_FAILURE","CUSTODY_CLAIM_CHANGED");
                if("SETTLE".equals(action)) {
                    tx.token=token;tx.snapshot();tx.touched=true;
                    released=true;ClaimsKernel.release(claims,token);cache.rawset(id,null);
                }
            }
            // No callback runs between claim/cache writes and this root swap.
            published=true;root.rawset("obligations",candidate);
            return result(true,id);
        } catch(RuntimeException error) {
            if(!published) {
                try {
                    if(acquired) {ClaimsKernel.release(claims,token);cache.rawset(g(op,"id"),null);}
                    if(released) {
                        if(!tx.restore())return failure("ROLLBACK_FAILURE","RECONCILE_REQUIRED:CUSTODY_RESTORE");
                        t(claims,"tokensByTaskId").rawset(g(op,"id"),token);cache.rawset(g(op,"id"),token);
                    }
                } catch(RuntimeException restore) {return failure("ROLLBACK_FAILURE","RECONCILE_REQUIRED:CUSTODY_RESTORE:"+text(restore));}
            }
            return failure("TASK_WRITE_FAILURE",(published?"CAS_REACHED_RELOAD_FROM_SAVE:":"")+text(error));
        }
    }
    private static KahluaTable change(KahluaThread vm,KahluaTable store,KahluaTable owner,KahluaTable claims,KahluaTable contracts,Object cleanup,Object id,Object rev,Object payload,Object command,boolean cancelling) {
        Tx tx=new Tx(claims);
        String stage="INVALID_REQUEST";
        try {
            KahluaTable job=t(first(method(vm,store,"get",id)));
            if(job==null || !eq(g(job,"revision"),rev))return failure("STALE_REVISION","JOB_CHANGED");
            if(!(payload instanceof KahluaTable proposed) || command!=null && !(command instanceof KahluaTable))return failure("INVALID_REQUEST","PAYLOAD_OR_COMMAND_INVALID");
            KahluaTable mutation=t(command),add=t(mutation,"addKeys"),remove=t(mutation,"removeKeys");
            cancelling=cancelling || "CANCELLED".equals(g(mutation,"state"));
            stage="CLAIM_FAILURE";
            tx.token=t(first(call(vm,g(owner,"getToken"),id)));
            KahluaTable token=tx.token;
            if(token!=null && (!eq(g(token,"taskId"),id) || !eq(g(token,"claimId"),g(job,"claimId"))))return failure("CLAIM_FAILURE","STALE_CLAIM_IDENTITY");
            Set<Object> owned=keys(token==null?t(t(job,"payload"),"claims"):t(token,"resources"));
            KahluaTable commitContract=t(first(call(vm,g(contracts,"get"),g(job,"providerType"))));
            if(g(mutation,"workCapacity")==null && token!=null)for(Object key:owned)
                if(g(t(claims,"owners"),key)!=token)return failure("CLAIM_FAILURE","STALE_CLAIM");
            Set<Object> addSet=keys(add),removeSet=keys(remove);
            if(add!=null && addSet.size()!=add.len())return failure("INVALID_REQUEST","RESOURCE_DUPLICATED");
            for(Object key:addSet)if(removeSet.contains(key) || owned.contains(key))return failure("INVALID_REQUEST","ADD_KEYS_OVERLAP");
            Object cap=g(mutation,"capacity"),work=g(mutation,"workCapacity");
            // A missing runtime token never authorizes resource commands.
            // Payload/domain validity remains Lua policy.
            if(token==null && (any(add)||any(remove)||cap!=null||work!=null))return failure("CLAIM_FAILURE","NO_RUNTIME_TOKEN");
            if(token!=null && g(t(claims,"tokensByTaskId"),id)!=token)return failure("CLAIM_FAILURE","STALE_RUNTIME_TOKEN");
            if(any(remove))for(int i=1;i<=remove.len();i++)
                if(g(t(claims,"owners"),remove.rawget(i))!=token)return failure("CLAIM_FAILURE","RESOURCE_NOT_OWNED");
            stage="CAPACITY_FAILURE";
            if(cap!=null) {
                KahluaTable rule=t(first(call(vm,g(contracts,"get"),g(job,"providerType"))));
                if(!yes(g(rule,"capacityMutable")) || !Boolean.FALSE.equals(cap) && !(cap instanceof KahluaTable))return failure("INVALID_REQUEST","CAPACITY_MUTATION_UNSUPPORTED");
                if(cap instanceof KahluaTable c && g(c,"releaseItemId")==null) {
                    if(!(g(c,"key") instanceof String) || !(g(c,"items") instanceof KahluaTable items)
                        || !(g(c,"free") instanceof Number))return failure("INVALID_REQUEST","CAPACITY_SHAPE_INVALID");
                    KahluaTableIterator it=items.iterator();
                    while(it.advance())if(!(it.getKey() instanceof Number) || !(it.getValue() instanceof Number))
                        return failure("INVALID_REQUEST","CAPACITY_SHAPE_INVALID");
                } else if(cap instanceof KahluaTable c && !(g(c,"releaseItemId") instanceof Number))
                    return failure("INVALID_REQUEST","CAPACITY_SHAPE_INVALID");
            }
            if(work!=null) {
                KahluaTable rule=t(first(call(vm,g(contracts,"get"),g(job,"providerType"))));
                if(!yes(g(rule,"capacityMutable")))return failure("INVALID_REQUEST","CAPACITY_MUTATION_UNSUPPORTED");
                if(!Boolean.FALSE.equals(work)) {
                    if(!(work instanceof KahluaTable w) || !(g(w,"key") instanceof String key) || key.isEmpty()
                        || !(g(w,"amount") instanceof Number amount) || !Double.isFinite(amount.doubleValue())
                        || amount.doubleValue()<=0)return failure("INVALID_REQUEST","CAPACITY_SHAPE_INVALID");
                    KahluaTableIterator fields=w.iterator();
                    while(fields.advance())if(!"key".equals(fields.getKey()) && !"amount".equals(fields.getKey()))
                        return failure("INVALID_REQUEST","CAPACITY_SHAPE_INVALID");
                }
                Object workKey=Boolean.FALSE.equals(work)?g(token,"capacityKey"):g(t(work),"key");
                if(yes(g(token,"capacityKey")) && !eq(g(token,"capacityKey"),workKey))
                    return failure("CAPACITY_FAILURE","CAPACITY_TARGET_CHANGED");
                KahluaTable entry=t(t(t(t(claims,"capacity"),workKey),"entries"),id);
                if(entry!=null && g(entry,"workAmount")!=null && !ClaimsKernel.validWorkEntry(claims,token,workKey,entry))
                    return failure("CAPACITY_FAILURE","CAPACITY_ENTRY_INVALID");
                if(entry!=null && (g(entry,"token")!=token || zero(g(entry,"count"))>0 || !t(entry,"items").isEmpty()))
                    return failure("CAPACITY_FAILURE","CAPACITY_UNAVAILABLE");
            }
            if(work!=null && token!=null)for(Object key:owned)
                if(g(t(claims,"owners"),key)!=token)return failure("CLAIM_FAILURE","STALE_CLAIM");
            stage="CLAIM_FAILURE";
            // Snapshot only when resources change; all resource writes precede CAS.
            if(any(add)||any(remove)||cap!=null||work!=null) {tx.snapshot();tx.touched=true;}
            if(any(add)) {String why=ClaimsKernel.extend(claims,token,add);if(why!=null)return tx.fail("CLAIM_FAILURE",why);}
            stage="CAPACITY_FAILURE";
            if(cap!=null) {
                String why=null;
                if(Boolean.FALSE.equals(cap))ClaimsKernel.releaseCapacity(claims,token,null);
                else {
                    KahluaTable c=t(cap);
                    if(yes(g(c,"releaseItemId")))ClaimsKernel.releaseCapacity(claims,token,g(c,"releaseItemId"));
                    else {
                        if(yes(g(token,"capacityKey")) && !eq(g(token,"capacityKey"),g(c,"key")))ClaimsKernel.releaseCapacity(claims,token,null);
                        why=ClaimsKernel.reserveMany(claims,token,g(c,"key"),t(c,"items"),g(c,"free"));
                    }
                }
                if(why!=null)return tx.fail("CAPACITY_FAILURE",why);
            }
            if(work!=null) {
                if(!(Boolean.FALSE.equals(work) && g(token,"capacityKey")==null)
                    && g(t(claims,"owners"),"cooking:capacity:"+text(id))!=token)
                    return tx.fail("CAPACITY_FAILURE","STALE_CLAIM");
                if(Boolean.FALSE.equals(work))ClaimsKernel.releaseCapacity(claims,token,null);
                else {
                    KahluaTable w=t(work);
                    String why=ClaimsKernel.setWorkCapacity(claims,token,g(w,"key"),g(w,"amount"));
                    if(why!=null)return tx.fail("CAPACITY_FAILURE",why);
                }
            }
            stage="CLAIM_FAILURE";
            if(any(remove)) {String why=ClaimsKernel.shrink(claims,token,remove);if(why!=null)return tx.fail("CLAIM_FAILURE",why);}
            // Any domain sequence is part of claim authority. Publish it before
            // synchronous Job observers; a rejected CAS restores the old value.
            if(token!=null && g(proposed,"sequence")!=null
                && !eq(g(token,"generation"),g(proposed,"sequence"))) {
                if(!tx.touched) {tx.snapshot();tx.touched=true;}
                token.rawset("generation",g(proposed,"sequence"));
            }
            KahluaTable patch=table();patch.rawset("payload",proposed);
            for(String f:new String[]{"state","effects","obligations"})if(g(mutation,f)!=null)patch.rawset(f,g(mutation,f));
            if(cancelling)patch.rawset("state","CANCELLED");
            stage="TASK_WRITE_FAILURE";tx.casReached=true;
            Object[] cas=method(vm,store,cancelling?"cancel":"update",id,rev,patch,g(mutation,"obligationOps"));
            if(!yes(first(cas))) {
                // Explicit rejection proves no publication; restore once.
                tx.casReached=false;
                return tx.fail("TASK_WRITE_FAILURE",cas.length>1?cas[1]:"CAS_REJECTED");
            }
            tx.next=cas.length>1?cas[1]:null;
            if("DONE".equals(g(patch,"state")) || "CANCELLED".equals(g(patch,"state"))) {
                if(token!=null)ClaimsKernel.release(claims,token);
                call(vm,cleanup,id);
            }
            return result(true,tx.next);
        } catch(RuntimeException error) {return tx.fail(stage,"CALLBACK_OR_KERNEL_THROW:"+text(error));}
    }
    public static KahluaTable create(KahluaThread vm,KahluaTable store,KahluaTable owner,KahluaTable state,KahluaTable contracts,Object allocate,KahluaTable job,Object obligationOps) {
        KahluaTable claims=t(state,"claims");Object id=g(job,"id");
        Tx tx=new Tx(claims);String stage="INVALID_REQUEST";
        try {
            // Lua validated the draft; allocation and acquisition execute inside
            // this transaction. claimId injection is overwritten unconditionally.
            job.rawset("claimId",first(call(vm,allocate,g(state,"root"),id)));
            claims.rawset("nextClaimSeq",Math.max(zero(g(claims,"nextClaimSeq")),zero(g(t(state,"root"),"nextClaimSeq"))+1));
            KahluaTable p=t(job,"payload");stage="CLAIM_FAILURE";
            Object generation=g(p,"sequence");if(generation==null)generation=g(job,"generation");if(generation==null)generation=0.0;
            KahluaTable resources=t(p,"claims");if(resources==null)resources=table();
            KahluaTable acquired=ClaimsKernel.acquireNew(claims,id,generation,resources,job);
            if(!yes(g(acquired,"ok")))return failure("CLAIM_FAILURE",g(acquired,"result"));
            tx.token=t(acquired,"result");tx.created=true;
            stage="CAPACITY_FAILURE";
            KahluaTable r=t(p,"reservation");
            if(r!=null) {
                KahluaTable items=t(r,"items");
                if(items==null && g(r,"itemId")!=null) {items=table();items.rawset(g(r,"itemId"),g(r,"amount"));}
                if(items==null)return tx.fail("INVALID_REQUEST","RESERVATION_ITEMS_REQUIRED");
                KahluaTableIterator it=items.iterator();
                while(it.advance()) {
                    String why=ClaimsKernel.reserve(claims,tx.token,g(r,"key"),it.getKey(),it.getValue(),g(r,"free"));
                    if(why!=null)return tx.fail("CAPACITY_FAILURE",why);
                }
            }
            // Resolve bucket before publication, so a throwing contract callback
            // can still release the new token without a half-published Job.
            KahluaTable rule=t(first(call(vm,g(contracts,"get"),g(job,"providerType"))));
            Object bucket=g(rule,"tokenBucket");
            KahluaTable bucketTokens=bucket==null?null:t(state,text(bucket)+"Tokens");
            KahluaTable genericTokens=t(state,"tokens");
            Object previousToken=g(genericTokens,id),previousBucketToken=g(bucketTokens,id);
            // JobStore.create notifies synchronously. Publish the acquired token
            // first, so every observer of the new Job sees its authority too.
            genericTokens.rawset(id,tx.token);
            if(bucketTokens!=null)bucketTokens.rawset(id,tx.token);
            stage="TASK_WRITE_FAILURE";tx.casReached=true;
            Object[] written=method(vm,store,"create",job,obligationOps);
            if(!yes(first(written))) {
                genericTokens.rawset(id,previousToken);
                if(bucketTokens!=null)bucketTokens.rawset(id,previousBucketToken);
                tx.casReached=false;return tx.fail(stage,written.length>1?written[1]:"CREATE_REJECTED");
            }
            return result(true,id);
        } catch(RuntimeException error) {
            return tx.fail(stage,"CALLBACK_OR_KERNEL_THROW:"+text(error));
        }
    }
}
