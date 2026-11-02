package emberroutes.probe;

import java.util.HashMap;
import java.util.Map;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaTableIterator;

/** World-owned observation versions only. No event callbacks, scheduling or resource mutations. */
public final class PlanningInvalidation {
    private Object world;
    private final Map<Object,Double> containers=new HashMap<>(),scopes=new HashMap<>();
    private double unknown,revision;
    private PlanningInvalidation() {}
    private static PlanningInvalidation owner(KahluaTable state) {return (PlanningInvalidation)state.rawget("invalidation");}
    private static double value(Object v) {return v==null ? 0 : ((Number)v).doubleValue();}
    private static double get(Map<Object,Double> map,Object key) {return map.getOrDefault(key,0.0);}
    public static KahluaTable create() {
	KahluaTable state=J2SEPlatform.getInstance().newTable();state.rawset("invalidation",new PlanningInvalidation());return state;
    }
    public static void load(KahluaTable state,Object root) {
	PlanningInvalidation s=owner(state);
	if (s.world!=root) {s.world=root;s.containers.clear();s.scopes.clear();s.unknown=0;s.revision++;}
    }
    public static double revision(KahluaTable state) {return owner(state).revision;}
    public static KahluaTable capture(KahluaTable state,Object scope,KahluaTable ids) {
	PlanningInvalidation s=owner(state);
	if (s.containers.size()>512) {s.containers.clear();s.unknown++;}
	KahluaTable token=J2SEPlatform.getInstance().newTable(),versions=J2SEPlatform.getInstance().newTable();
	token.rawset("world",s.world);token.rawset("scope",scope);token.rawset("scopeRevision",get(s.scopes,scope));
	token.rawset("unknown",s.unknown);token.rawset("ids",versions);
	if (ids!=null) for (int i=1;;i++) {
	    Object id=ids.rawget(i);if (id==null) break;
	    double v=get(s.containers,id);s.containers.putIfAbsent(id,v);versions.rawset(id,v);
	}
	return token;
    }
    public static boolean changed(KahluaTable state,KahluaTable token) {
	PlanningInvalidation s=owner(state);
	if (token.rawget("world")!=s.world || value(token.rawget("unknown"))!=s.unknown
	    || value(token.rawget("scopeRevision"))!=get(s.scopes,token.rawget("scope"))) return true;
	KahluaTableIterator ids=((KahluaTable)token.rawget("ids")).iterator();
	while (ids.advance()) if (value(ids.getValue())!=get(s.containers,ids.getKey())) return true;
	return false;
    }
    public static void containerChanged(KahluaTable state,Object id) {
	PlanningInvalidation s=owner(state);
	if (id==null || Boolean.FALSE.equals(id)) {s.unknown++;s.revision++;}
	else if (s.containers.containsKey(id)) {s.containers.put(id,get(s.containers,id)+1);s.revision++;}
    }
    public static void scopeChanged(KahluaTable state,Object id) {
	PlanningInvalidation s=owner(state);s.scopes.put(id,get(s.scopes,id)+1);s.revision++;
    }
}
