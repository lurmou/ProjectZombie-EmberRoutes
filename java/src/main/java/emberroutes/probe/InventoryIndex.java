package emberroutes.probe;

import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.KahluaTable;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;

/** Caller-owned transient view. No world cache, claims or inventory mutations. */
public final class InventoryIndex {
    private InventoryIndex() {}
    private static KahluaTable table() { return J2SEPlatform.getInstance().newTable(); }
    private static double number(Object value) { return ((Number)value).doubleValue(); }
    private static KahluaTable rejected(String reason) { KahluaTable r=table();r.rawset("reason",reason);return r; }
    public static KahluaTable begin(KahluaTable containers) {
	KahluaTable state=table(),lists=table(),sizes=table();
	state.rawset("containers",containers);state.rawset("lists",lists);state.rawset("sizes",sizes);
	state.rawset("index",table());state.rawset("location",1.0);state.rawset("position",0.0);
	for (int i=1;i<=containers.len();i++) {
	    ItemContainer c=(ItemContainer)containers.rawget(i);
	    lists.rawset(i,c.getItems());sizes.rawset(i,Double.valueOf(c.getItems().size()));
	}
	return state;
    }
    public static KahluaTable step(KahluaTable state,int budget) {
	KahluaTable containers=(KahluaTable)state.rawget("containers"),lists=(KahluaTable)state.rawget("lists"),
	    sizes=(KahluaTable)state.rawget("sizes"),index=(KahluaTable)state.rawget("index");
	for (int i=1;i<=containers.len();i++) {
	    ItemContainer c=(ItemContainer)containers.rawget(i);
	    int size=(int)number(sizes.rawget(i));
	    if (size>2000) return rejected("INVENTORY_SCAN_LIMIT");
	    if (c.getItems()!=lists.rawget(i) || c.getItems().size()!=size) return rejected("INVENTORY_CHANGED");
	}
	int location=(int)number(state.rawget("location")),position=(int)number(state.rawget("position")),reads=0;
	while (location<=containers.len()) {
	    int size=(int)number(sizes.rawget(location));
	    if (position>=size) {location++;position=0;}
	    else {
		if (reads>=budget) {
		    state.rawset("location",Double.valueOf(location));state.rawset("position",Double.valueOf(position));
		    return rejected("SCAN_PENDING");
		}
		ItemContainer c=(ItemContainer)containers.rawget(location);
		InventoryItem item=c.getItems().get(position);
		Double id=Double.valueOf(item.getID());
		KahluaTable entry=(KahluaTable)index.rawget(id);
		if (entry==null) {
		    entry=table();entry.rawset("item",item);entry.rawset("container",c);
		    entry.rawset("location",Double.valueOf(location));entry.rawset("count",1.0);index.rawset(id,entry);
		} else entry.rawset("count",number(entry.rawget("count"))+1);
		reads++;position++;
	    }
	}
	state.rawset("location",Double.valueOf(location));state.rawset("position",Double.valueOf(position));
	KahluaTable result=table();result.rawset("index",index);return result;
    }
    public static KahluaTable index(KahluaTable containers) {return step(begin(containers),Integer.MAX_VALUE);}
}
