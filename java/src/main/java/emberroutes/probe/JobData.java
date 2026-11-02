package emberroutes.probe;

import java.util.IdentityHashMap;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaTableIterator;

/** Bounded detached facts. No world state, callbacks, native handles or retained cache. */
public final class JobData {
    private JobData() {}
    public static KahluaTable copy(KahluaTable source) {
	return (KahluaTable)copyValue(source,new IdentityHashMap<>(),new int[1],0);
    }
    private static Object copyValue(Object value,IdentityHashMap<KahluaTable,Boolean> path,int[] budget,int depth) {
	if (++budget[0]>8192 || depth>16) throw new IllegalArgumentException("JOB_DATA_LIMIT");
	// Installed Kahlua uses Java String.length for Lua #string (UTF-16 units).
	if (value instanceof String text) {
	    if (text.length()>16384) throw new IllegalArgumentException("JOB_DATA_LIMIT");
	    return text;
	}
	if (value==null || value instanceof Boolean) return value;
	if (value instanceof Double number && Double.isFinite(number)) return number;
	if (!(value instanceof KahluaTable table) || path.containsKey(table))
	    throw new IllegalArgumentException("JOB_DATA_UNSERIALIZABLE");
	path.put(table,Boolean.TRUE);
	KahluaTable result=J2SEPlatform.getInstance().newTable();
	KahluaTableIterator entries=table.iterator();
	while (entries.advance()) {
	    Object key=entries.getKey();
	    if (!(key instanceof String) && !(key instanceof Double n && Double.isFinite(n) && n>=0 && n==Math.floor(n)))
		throw new IllegalArgumentException("JOB_KEY_INVALID");
	    result.rawset(key,copyValue(entries.getValue(),path,budget,depth+1));
	}
	path.remove(table);
	return result;
    }
}
