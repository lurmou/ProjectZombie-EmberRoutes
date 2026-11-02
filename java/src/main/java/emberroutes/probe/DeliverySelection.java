package emberroutes.probe;

import java.util.HashMap;
import java.util.Map;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoGameCharacter;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;

/** Delivery-domain planning/projection only. Never grants resources or transfers originals. */
public final class DeliverySelection {
    private DeliverySelection() {}
    private static KahluaTable table() { return J2SEPlatform.getInstance().newTable(); }
    private static double number(Object value) { return value==null ? 0 : ((Number)value).doubleValue(); }
    private static KahluaTable child(KahluaTable value,String key) {return (KahluaTable)value.rawget(key);}
    private static KahluaTable result(int scanned) {KahluaTable r=table();r.rawset("scanned",Double.valueOf(scanned));return r;}
    private static final class RequestIndex {
	final Map<String,Map<String,Integer>> scoped=new HashMap<>();
	final Map<String,Integer> general=new HashMap<>();
	final KahluaTable rows;
	RequestIndex(KahluaTable rows) {
	    this.rows=rows;
	    for (int i=1;i<=rows.len();i++) {
		KahluaTable row=(KahluaTable)rows.rawget(i);
		String type=(String)row.rawget("fullType"),source=(String)row.rawget("sourceId");
		if (source==null) general.put(type,i);
		else scoped.computeIfAbsent(source,k->new HashMap<>()).put(type,i);
	    }
	}
	int match(String type,String source,KahluaTable counts,boolean planned) {
	    Map<String,Integer> byType=scoped.get(source);
	    Integer exact=byType==null ? null : byType.get(type);
	    if (available(exact,counts,planned)) return exact;
	    Integer any=general.get(type);
	    return available(any,counts,planned) ? any : 0;
	}
	boolean available(Integer id,KahluaTable counts,boolean planned) {
	    if (id==null) return false;
	    KahluaTable row=(KahluaTable)rows.rawget(id.intValue());
	    double limit=number(row.rawget("quantity"))-(planned ? number(row.rawget("delivered")) : 0);
	    return number(counts.rawget(id.intValue()))<limit;
	}
    }
    public static KahluaTable scan(ItemContainer source,IsoGameCharacter npc,String sourceId,
	    KahluaTable requests,KahluaTable owners,KahluaTable state,int budget) {
	if (source==null || npc==null || budget<1 || budget>256) throw new IllegalArgumentException("DELIVERY_SCAN_ARGUMENT");
	RequestIndex matcher=state.rawget("requestIndex") instanceof RequestIndex r && r.rows==requests ? r : new RequestIndex(requests);
	state.rawset("requestIndex",matcher); // Derived, transient; released with the caller's scan state.
	KahluaTable picks=child(state,"picks"),types=child(state,"types"),origins=child(state,"origins"),
	    counts=child(state,"counts"),seen=child(state,"seen"),virtual=child(state,"virtualEligibility");
	if (virtual==null) {virtual=table();state.rawset("virtualEligibility",virtual);}
	ItemContainer destination=npc.getInventory();
	int offset=(int)number(state.rawget("offset")),scanned=0;
	double used=number(state.rawget("used")),free=number(state.rawget("free"));
	var items=source.getItems();
	while (offset<items.size() && scanned<budget && picks.len()<256) {
	    InventoryItem item=items.get(offset);
	    int match=matcher.match(item.getFullType(),sourceId,counts,true);
	    int id=item.getID();Double key=Double.valueOf(id);
	    if (match!=0 && !InventoryReads.truthy(seen.rawget(key)) && !InventoryReads.truthy(owners.rawget("item:"+id))) {
		Boolean eligible=InventoryReads.eligible(item);
		if (eligible==null) {
		    Object decision=virtual.rawget(key);
		    if (decision==null) {
			state.rawset("offset",Double.valueOf(offset));state.rawset("used",used);
			KahluaTable response=result(scanned);response.rawset("virtualItem",item);return response;
		    }
		    eligible=InventoryReads.truthy(decision);
		}
		if (eligible) {
		    double weight=item.getUnequippedWeight();
		    if (weight>npc.getMaxWeight()) state.rawset("overweight",Boolean.TRUE);
		    else if (weight<=free-used && destination.hasRoomFor(npc,item)) {
			picks.rawset(picks.len()+1,key);types.rawset(Integer.toString(id),item.getFullType());
			origins.rawset(Integer.toString(id),sourceId);used+=weight;
			counts.rawset(match,Double.valueOf(number(counts.rawget(match))+1));seen.rawset(key,Boolean.TRUE);
		    }
		}
	    }
	    offset++;scanned++;
	}
	state.rawset("offset",Double.valueOf(offset));state.rawset("used",used);
	return result(scanned);
    }
    public static KahluaTable received(KahluaTable order,KahluaTable payload) {
	KahluaTable requests=child(order,"items"),counts=table(),manifest=child(payload,"manifest"),types=child(payload,"itemTypes");
	RequestIndex matcher=new RequestIndex(requests);
	for (int i=1;i<=requests.len();i++) counts.rawset(i,((KahluaTable)requests.rawget(i)).rawget("delivered"));
	String player="player:"+order.rawget("requesterId");
	for (int i=1;i<=manifest.len();i++) {
	    KahluaTable line=(KahluaTable)manifest.rawget(i),receipt=child(line,"deliveryReceipt");
	    if (receipt==null || !player.equals(receipt.rawget("destinationId"))) continue;
	    String itemId=Long.toString((long)number(line.rawget("itemId")));
	    int match=matcher.match((String)types.rawget(itemId),(String)line.rawget("sourceId"),counts,false);
	    if (match!=0) counts.rawset(match,Double.valueOf(number(counts.rawget(match))+1));
	}
	return counts;
    }
}
