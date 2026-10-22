package emberroutes.probe;

import java.util.*;
import java.util.function.Consumer;

/** Game-thread roster; a single shared budget, fair cursor, no per-worker timer. */
public final class WorkerRoster<T> {
    private final LinkedHashMap<String,T> entries = new LinkedHashMap<>();
    private final ArrayList<String> order = new ArrayList<>();
    private int cursor;
    public void put(String id,T value) {
        if (id == null || id.isEmpty() || value == null) throw new IllegalArgumentException("identity required");
        if (!entries.containsKey(id)) order.add(id);
        entries.put(id,value);
    }
    public void remove(String id) {
        if (entries.remove(id)==null) return;
        int index=order.indexOf(id); order.remove(index);
        if (index<cursor) cursor--;
    }
    public int size() { return order.size(); }
    public void clear() { entries.clear(); order.clear(); cursor=0; }
    public int advance(int budget,Consumer<T> step) {
        int limit=Math.min(Math.max(0,budget),order.size()),spent=0;
        while (spent<limit && !order.isEmpty()) {
            cursor=Math.floorMod(cursor,order.size());
            T value=entries.get(order.get(cursor++)); spent++;
            step.accept(value);
        }
        return spent;
    }
}
