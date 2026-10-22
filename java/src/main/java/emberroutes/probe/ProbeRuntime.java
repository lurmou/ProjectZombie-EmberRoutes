package emberroutes.probe;

import java.util.*;
import zombie.characters.IsoPlayer;

/** Authority facade. Selection is UI state; execution always resolves an explicit identity. */
public final class ProbeRuntime {
    private static final LinkedHashMap<String,CarrierRuntime> slots=new LinkedHashMap<>();
    private static final Map<String,CarrierRuntime> ids=new HashMap<>();
    private static final IdentityHashMap<IsoPlayer,CarrierRuntime> handles=new IdentityHashMap<>();
    private static final WorkerRoster<CarrierRuntime> active=new WorkerRoster<>();
    private static final IdentityHashMap<CarrierRuntime,IsoPlayer> ownedHandles=new IdentityHashMap<>();
    private static final ArrayList<CarrierRuntime> catalogue=new ArrayList<>();
    private static zombie.iso.IsoWorld owner;
    private static zombie.iso.IsoCell ownerCell;
    private static CarrierRuntime selected;
    private static boolean enabled;
    private static Thread thread;
    private ProbeRuntime() {}
    public static String version() { return BuildInfo.VERSION; }
    public static double diagnosticTimeNanos() { return System.nanoTime(); }
    /** CraftRecipe.LuaCall is not exported to Lua in the pinned engine. Read metadata only. */
    public static boolean recipeHasCallbacks(zombie.scripting.entity.components.crafting.CraftRecipe recipe) {
        if (recipe == null) return true;
        for (var call : zombie.scripting.entity.components.crafting.CraftRecipe.LuaCall.values())
            if (recipe.hasLuaCall(call)) return true;
        return false;
    }
    public static String recipeKey(zombie.scripting.entity.components.crafting.CraftRecipe recipe) {
        if (recipe == null || recipe.getModule() == null) return "";
        String name=recipe.getName(), module=recipe.getModule().getName();
        return name.startsWith(module+".") ? name : module+"."+name;
    }
    public static boolean recipeHasSpecialOutputs(zombie.scripting.entity.components.crafting.CraftRecipe recipe) {
        if (recipe == null) return true;
        for (var output : recipe.getOutputs()) {
            var mapper=output.getOutputMapper();
            // Even a fixed item has a mapper. Only input-dependent alternatives are special.
            if (mapper != null && !mapper.getEntrees().isEmpty()) return true;
        }
        return false;
    }
    public static void log(String text) { System.out.println(BuildInfo.PREFIX+" "+text); }
    private static CarrierRuntime current() {
        if (selected==null) { selected=new CarrierRuntime("legacy"); slots.put("legacy",selected); catalogue.add(selected); }
        return selected;
    }
    private static void refresh(CarrierRuntime runtime) {
        IsoPlayer old=ownedHandles.get(runtime), body=runtime.body();
        if (old!=null && old!=body) { handles.remove(old); ownedHandles.remove(runtime); }
        if (body!=null) ownedHandles.put(runtime,body);
        if (runtime.id()!=null) ids.put(runtime.id(),runtime);
        if (runtime.body()!=null) {
            handles.put(runtime.body(),runtime); active.put(runtime.slot,runtime);
        } else active.remove(runtime.slot);
    }
    private static CarrierRuntime find(String id) {
        CarrierRuntime runtime=ids.get(id);
        return runtime!=null ? runtime : slots.get(id);
    }
    public static String selectedId() { return current().id()==null ? "" : current().id(); }
    public static int workerCount() { return catalogue.size(); }
    public static String workerIdAt(int index) {
        if (index<0 || index>=catalogue.size()) return "";
        CarrierRuntime runtime=catalogue.get(index); return runtime.id()==null ? runtime.slot : runtime.id();
    }
    public static boolean selectCarrier(String id) {
        if (Thread.currentThread()!=thread) return false;
        CarrierRuntime runtime=find(id); if (runtime==null) return false;
        selected=runtime; return true;
    }
    public static IsoPlayer carrierFor(String id,IsoPlayer actor) {
        CarrierRuntime runtime=find(id);
        if (runtime==null || actor==null || actor.isDead() || !actor.isLocalPlayer()) return null;
        return runtime.carrierPresent(runtime.body()) ? runtime.body() : null;
    }
    public static IsoPlayer controlledCarrier(IsoPlayer actor) { return current().controlledCarrier(actor); }
    public static IsoPlayer actionCarrier(IsoPlayer actor) { return current().actionCarrier(actor); }
    public static boolean carrierPresent(IsoPlayer body) {
        CarrierRuntime runtime=handles.get(body); return runtime!=null && runtime.carrierPresent(body);
    }
    public static boolean carrierActive(IsoPlayer body) {
        CarrierRuntime runtime=handles.get(body); return runtime!=null && runtime.carrierActive(body);
    }
    public static String carrierId(IsoPlayer body) {
        CarrierRuntime runtime=handles.get(body); return runtime==null ? "" : runtime.carrierId(body);
    }
    public static String motionResult(IsoPlayer body) {
        CarrierRuntime runtime=handles.get(body); return runtime==null ? "UNAVAILABLE" : runtime.motionResult(body);
    }
    public static boolean stopCarrier(IsoPlayer body) {
        CarrierRuntime runtime=handles.get(body); return runtime!=null && runtime.stopCarrier(body);
    }
    public static String begin(boolean enable) {
        thread=Thread.currentThread(); enabled=enable;
        var world=zombie.iso.IsoWorld.instance;
        var cell=world==null ? null : world.currentCell;
        if (owner!=null && (owner!=world || ownerCell!=cell)) {
            for (CarrierRuntime runtime:slots.values()) {
                runtime.begin(false,false);
                if (runtime.body()!=null) { enabled=false; return "RESET_REQUIRED old world disposal pending"; }
            }
            slots.clear(); catalogue.clear(); ids.clear(); handles.clear(); ownedHandles.clear(); active.clear(); selected=null;
            ProbePersistence.invalidateVerification();
        }
        owner=world; ownerCell=cell;
        CarrierRuntime first=current();
        String result=first.begin(enable,true);
        if (!result.startsWith("READY") && !result.startsWith("RESET_REQUIRED")) { enabled=false; return result; }
        if (!enable || !ProbeRules.canSimulate(zombie.network.GameClient.client,zombie.network.GameServer.server)) {
            enabled=false; return result;
        }
        try {
            ProbePersistence.verifyStore();
            for (String slot:ProbePersistence.slots()) slots.computeIfAbsent(slot,CarrierRuntime::new);
            catalogue.clear(); catalogue.addAll(slots.values());
            ids.clear(); handles.clear(); ownedHandles.clear(); active.clear();
            for (CarrierRuntime runtime:slots.values()) {
                if (runtime!=first) runtime.begin(enable,false);
                runtime.rememberSavedId(ProbePersistence.savedId(runtime.slot));
                refresh(runtime);
            }
            return result;
        } catch (java.io.IOException | RuntimeException error) { enabled=false; return "CHECKPOINT_BLOCKED "+error; }
    }
    public static String command(String command,IsoPlayer actor,double x,double y,double z) {
        CarrierRuntime runtime=current();
        if ("spawn".equals(command) && runtime.id()!=null && runtime.body()==null)
            return spawnAdditional(actor,x,y,z);
        String result=runtime.command(command,actor,x,y,z); refresh(runtime); return result;
    }
    public static String commandFor(String id,String command,IsoPlayer actor,double x,double y,double z) {
        if (Thread.currentThread()!=thread) return "WRONG_THREAD";
        if (!enabled) return "DRIVER_UNAVAILABLE";
        CarrierRuntime runtime=find(id);
        if (runtime==null || "spawn".equals(command)) return "STALE_NPC";
        String result=runtime.workerCommand(command,actor,x,y,z); refresh(runtime); return result;
    }
    public static String spawnAdditional(IsoPlayer actor,double x,double y,double z) {
        if (Thread.currentThread()!=thread || !enabled) return "DRIVER_UNAVAILABLE";
        String id=UUID.randomUUID().toString(); CarrierRuntime runtime=new CarrierRuntime(id);
        runtime.begin(enabled,false);
        String result=runtime.command("spawn",actor,x,y,z);
        if (runtime.body()!=null) { slots.put(id,runtime); catalogue.add(runtime); selected=runtime; refresh(runtime); }
        return result;
    }
    public static void tick() {
        if (Thread.currentThread()!=thread) return;
        active.advance(8,runtime->{ runtime.tick(); refresh(runtime); });
    }
    public static void retirementTick() {
        if (Thread.currentThread()!=thread) return;
        active.advance(8,runtime->{ runtime.retirementTick(); refresh(runtime); });
    }
    public static String reset() {
        if (thread!=null && Thread.currentThread()!=thread) return "WRONG_THREAD";
        String result="ABSENT";
        boolean pending=false,failed=false;
        for (CarrierRuntime runtime:slots.values()) {
            result=runtime.reset(); refresh(runtime);
            pending|=runtime.body()!=null; failed|=result.startsWith("CLEANUP_FAILED");
        }
        if (failed) result="CLEANUP_FAILED one or more carriers retained";
        else if (pending) result="REMOVAL_PENDING one or more carriers retained";
        ProbePersistence.invalidateVerification();
        enabled=false; return result;
    }
    public static String clearForSave() { return current().clearForSave(); }
    public static String saveCheckpoint(String mode,boolean home,double x,double y,double z) {
        return current().saveCheckpoint(mode,home,x,y,z);
    }
    public static String saveCheckpointFor(String id,String mode,boolean home,double x,double y,double z) {
        CarrierRuntime runtime=find(id); return runtime==null ? "STALE_NPC" : runtime.saveCheckpoint(mode,home,x,y,z);
    }
    public static String blockCheckpoint(String reason) { return current().blockCheckpoint(reason); }
    public static String blockAllCheckpoints(String reason) {
        boolean failed=false;
        for (CarrierRuntime runtime:slots.values())
            failed|=!runtime.blockCheckpoint(reason).startsWith("CHECKPOINT_BLOCKED");
        if (failed) return "SAVE_UNAVAILABLE could not block every checkpoint: "+reason;
        return "CHECKPOINT_BLOCKED "+reason;
    }
    public static String restoreCheckpoint(IsoPlayer actor) {
        try { ProbePersistence.verifyStore(); }
        catch (java.io.IOException | RuntimeException error) { return "RESTORE_BLOCKED "+error; }
        String result=current().restoreCheckpoint(actor); refresh(current()); return result;
    }
    public static String reportCheckpoint() { return current().reportCheckpoint(); }
    public static String checkpointMode() { return current().checkpointMode(); }
    public static boolean checkpointHasHome() { return current().checkpointHasHome(); }
    public static double checkpointHomeX() { return current().checkpointHomeX(); }
    public static double checkpointHomeY() { return current().checkpointHomeY(); }
    public static double checkpointHomeZ() { return current().checkpointHomeZ(); }
}
