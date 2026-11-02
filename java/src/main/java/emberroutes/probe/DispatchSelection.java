package emberroutes.probe;

import java.util.function.IntFunction;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.KahluaTable;

/** Pure common ordering/window math. No knowledge of a work category's strategy. */
public final class DispatchSelection {
    private DispatchSelection() {}
    public static KahluaTable choose(KahluaTable candidates,KahluaTable priorities) {
	KahluaTable best=null;double bestPriority=0,bestScore=0;
	for (int i=1;;i++) {
	    Object value=candidates.rawget(i);if (value==null) break;
	    KahluaTable candidate=(KahluaTable)value;
	    Object priority=priorities.rawget(candidate.rawget("category"));
	    if (priority==null || Boolean.FALSE.equals(priority)) continue;
	    double p=((Number)priority).doubleValue();
	    if (!(p>=1 && p<=4) || !Boolean.TRUE.equals(candidate.rawget("allowed"))) continue;
	    Object raw=candidate.rawget("score");double score=raw==null || Boolean.FALSE.equals(raw) ? 0 : ((Number)raw).doubleValue();
	    if (best==null || p<bestPriority || p==bestPriority && (score>bestScore || score==bestScore
		&& ((String)candidate.rawget("key")).compareTo((String)best.rawget("key"))<0)) {
		best=candidate;bestPriority=p;bestScore=score;
	    }
	}
	return best;
    }
    public static KahluaTable window(int cursor,int limit,int count,IntFunction<String> idAt) {
	KahluaTable result=J2SEPlatform.getInstance().newTable(),ids=J2SEPlatform.getInstance().newTable();
	result.rawset("count",Double.valueOf(count));result.rawset("ids",ids);
	if (count<1 || count>256) return result;
	int n=Math.min(Math.max(limit,0),Math.min(count,16));
	for (int i=1;i<=n;i++) {cursor=Math.floorMod(cursor,count)+1;ids.rawset(i,idAt.apply(cursor-1));}
	return result;
    }
}
