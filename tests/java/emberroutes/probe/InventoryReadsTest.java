package emberroutes.probe;

import java.util.ArrayList;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.KahluaTable;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;

/** Installed inventory classes and Kahlua tables; no loaded world or NPC body. */
public final class InventoryReadsTest {
    private static int checks;
    private static void check(boolean value,String why) { checks++; if (!value) throw new AssertionError(why); }
    public static void main(String[] args) {
        var data=J2SEPlatform.getInstance().newTable();
        for (Object value:new Object[]{false,true,0.0,"", "held"}) {
            data.rawset("EmberRoutesHaulFixture",value);
            check(InventoryReads.protectedData(data)==(!Boolean.FALSE.equals(value)),"Lua truthiness preserved: "+value);
        }
        data.rawset("EmberRoutesHaulFixture",null);
        check(!InventoryReads.protectedData(data),"nil does not protect");
        check(InventoryReads.carry(10,3,8)==7,"body weight restricts carry");
        check(InventoryReads.carry(10,3,2)==2,"container capacity restricts carry");
        check(InventoryReads.carry(10,11,8)==0,"overweight has no free carry");
        for (double value:new double[]{-1,Double.NaN,Double.POSITIVE_INFINITY,Double.NEGATIVE_INFINITY}) {
            check(InventoryReads.carry(value,0,10)==0 && InventoryReads.carry(10,value,10)==0,"invalid body weight rejected");
        }
        var container=new ItemContainer();
        for (int i=0;i<70;i++) {
            // Script metadata constructor avoids texture/filesystem startup.
            var item=new InventoryItem("Base","ReadTest","ReadTest",new zombie.scripting.objects.Item());
            item.setID(i+1); item.setContainer(container); container.getItems().add(item);
        }
        var items=container.getItems();
        var ordinary=items.get(0);
        check(InventoryReads.eligible(ordinary),"actual ordinary inventory item eligible");
        ordinary.getModData().rawset("EmberRoutesPersistenceSample",0.0);
        check(!InventoryReads.eligible(ordinary),"actual numeric marker protects original");
        ordinary.getModData().rawset("EmberRoutesPersistenceSample",false);
        check(InventoryReads.eligible(ordinary),"actual false marker permits original");
        ordinary.setFavorite(true);
        check(!InventoryReads.eligible(ordinary),"actual favorite item protected");
        ordinary.setFavorite(false);
        ordinary.getModData().setMetatable(J2SEPlatform.getInstance().newTable());
        check(InventoryReads.eligible(ordinary)==null,"virtual mod data delegates to Lua rather than bypassing metamethods");
        ordinary.getModData().setMetatable(null);
        KahluaTable first=InventoryReads.slice(container,items,70,0,32);
        var rows=(KahluaTable)first.rawget("rows");
        check(first.rawget("reason")==null && rows.len()==96,"32-item slice has flat triples");
        check(rows.rawget(1)==items.get(0) && rows.rawget(2).equals(1.0),"original item and numeric ID preserved");
        check(rows.rawget(3).equals(items.get(0).getFullType()),"type metadata preserved");
        check(((KahluaTable)InventoryReads.slice(container,items,70,64,32).rawget("rows")).len()==18,"last slice bounded by remaining items");
        check("INVENTORY_CHANGED".equals(InventoryReads.slice(container,new ArrayList<>(items),70,0,1).rawget("reason")),"same contents do not substitute collection identity");
        check("INVENTORY_CHANGED".equals(InventoryReads.slice(container,items,69,0,1).rawget("reason")),"size change rejected");
        for (int limit:new int[]{0,33,20000})
            check("SCAN_RANGE_INVALID".equals(InventoryReads.slice(container,items,70,0,limit).rawget("reason")),"unbounded slice rejected");
        items.get(0).setContainer(new ItemContainer());
        KahluaTable rejected=InventoryReads.slice(container,items,70,0,32);
        check("ITEM_LOCATION_CHANGED".equals(rejected.rawget("reason")) && rejected.rawget("rows")==null,"wrong location never publishes partial rows");
        check(items.size()==70,"read never removes originals");
        check(!ProbeRuntime.bindingValid(null,"missing") && !ProbeRuntime.bindingValid(null,null),"missing native body never validates");
	var sources=J2SEPlatform.getInstance().newTable();sources.rawset(1,container);
	var cursor=InventoryIndex.begin(sources);
	check("SCAN_PENDING".equals(InventoryIndex.step(cursor,32).rawget("reason")),"native index yields at the existing item budget");
	var indexed=(KahluaTable)InventoryIndex.step(cursor,38).rawget("index");
	var indexedItem=(KahluaTable)indexed.rawget(2.0);
	check(indexedItem.rawget("item")==items.get(1) && indexedItem.rawget("container")==container
	    && indexedItem.rawget("location").equals(1.0),"native index returns original identity and location");
	var stale=InventoryIndex.begin(sources);var removed=items.remove(items.size()-1);
	check("INVENTORY_CHANGED".equals(InventoryIndex.step(stale,32).rawget("reason")),"native cursor rejects a changed collection size");
	items.add(removed);
	var second=new ItemContainer();var duplicate=new InventoryItem("Base","ReadTest","ReadTest",new zombie.scripting.objects.Item());
	duplicate.setID(2);duplicate.setContainer(second);second.getItems().add(duplicate);sources.rawset(2,second);
	var duplicates=(KahluaTable)InventoryIndex.index(sources).rawget("index");
	check(((KahluaTable)duplicates.rawget(2.0)).rawget("count").equals(2.0),"native index preserves duplicate-ID detection across containers");
	var order=J2SEPlatform.getInstance().newTable();var requests=J2SEPlatform.getInstance().newTable();
	var general=J2SEPlatform.getInstance().newTable();general.rawset("fullType","Base.ReadTest");general.rawset("quantity",1.0);general.rawset("delivered",0.0);
	var scoped=J2SEPlatform.getInstance().newTable();scoped.rawset("fullType","Base.ReadTest");scoped.rawset("sourceId","box");scoped.rawset("quantity",1.0);scoped.rawset("delivered",0.0);
	requests.rawset(1,general);requests.rawset(2,scoped);order.rawset("items",requests);order.rawset("requesterId","owner");
	var payload=J2SEPlatform.getInstance().newTable();var manifest=J2SEPlatform.getInstance().newTable();var types=J2SEPlatform.getInstance().newTable();
	for (int i=1;i<=2;i++) {
	    var line=J2SEPlatform.getInstance().newTable();var receipt=J2SEPlatform.getInstance().newTable();
	    line.rawset("itemId",Double.valueOf(i));line.rawset("sourceId","box");receipt.rawset("destinationId","player:owner");line.rawset("deliveryReceipt",receipt);
	    manifest.rawset(i,line);types.rawset(Integer.toString(i),"Base.ReadTest");
	}
	payload.rawset("manifest",manifest);payload.rawset("itemTypes",types);
	var received=DeliverySelection.received(order,payload);
	check(received.rawget(1).equals(1.0) && received.rawget(2).equals(1.0),"Java receipts credit each original once with scoped demand first");
	manifest.rawset(2,(Object)null);received=DeliverySelection.received(order,payload);
	check(received.rawget(1).equals(0.0) && received.rawget(2).equals(1.0),"one receipt cannot satisfy both scoped and general requests");
        System.out.println("PASS "+checks+" installed inventory/Kahlua native-read checks; loaded world and live NPC NOT RUN");
    }
}
