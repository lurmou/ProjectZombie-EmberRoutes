package emberroutes.probe;

import java.util.*;
import zombie.characters.IsoPlayer;

/** Authority facade. Selection is UI state; execution always resolves an explicit identity. */
public final class ProbeRuntime {
    /** Read-only, loaded-world evidence; no ownership or movement side effects. */
    public static boolean socialVisible(IsoPlayer first,IsoPlayer second) {
        if (first==null || second==null || first.isDead() || second.isDead()) return false;
        var firstSquare=first.getCurrentSquare(); var secondSquare=second.getCurrentSquare();
        if (firstSquare==null || secondSquare==null || firstSquare.getZ()!=secondSquare.getZ()
                || first.getCell()!=second.getCell()) return false;
        double dx=first.getX()-second.getX(), dy=first.getY()-second.getY();
        if (dx*dx+dy*dy>7.5625) return false;
        zombie.iso.LosUtil.TestResults result=zombie.iso.LosUtil.lineClear(first.getCell(),
                (int)Math.floor(first.getX()),(int)Math.floor(first.getY()),firstSquare.getZ(),
                (int)Math.floor(second.getX()),(int)Math.floor(second.getY()),secondSquare.getZ(),false);
        return result!=zombie.iso.LosUtil.TestResults.Blocked
                && result!=zombie.iso.LosUtil.TestResults.ClearThroughClosedDoor;
    }
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
    private static BodyAuthority authority = new BodyAuthority();
    private static final Set<String> controlCalls = new HashSet<>();
    private static Thread thread;
    private static ProbeSaveReceipt saveReceipt;
    private ProbeRuntime() {}
    public static String version() { return BuildInfo.VERSION; }
    public static double diagnosticTimeNanos() { return System.nanoTime(); }
    private static final Map<String,se.krka.kahlua.vm.KahluaTable> modDataCache=new HashMap<>();
    /** getOrCreate root handle cache for per-tick Lua read paths; each Lua call to
     *  ModData.getOrCreate is a bridge round-trip. Cleared on world lifecycle. */
    public static se.krka.kahlua.vm.KahluaTable cachedModData(String key) {
        if (key==null || key.isEmpty() || key.length()>256) return null;
        se.krka.kahlua.vm.KahluaTable root=modDataCache.get(key);
        if (root!=null) return root;
        root=zombie.world.moddata.GlobalModData.instance.getOrCreate(key);
        if (root==null) return null;
        modDataCache.put(key,root);
        return root;
    }
    /** One-shot need/safety observation; replaces ~10-70 per-NPC Lua bridge calls. */
    public static se.krka.kahlua.vm.KahluaTable observerSample(zombie.characters.IsoPlayer npc) {
        return ObserverReads.sample(npc);
    }
    public static Boolean workItemEligible(zombie.inventory.InventoryItem item) { return InventoryReads.eligible(item); }
    public static double workFreeCarry(zombie.characters.IsoGameCharacter npc) { return InventoryReads.freeCarry(npc); }
    /**
     * Bakes the character's actual 3D appearance into a single cached texture
     * (engine DeadBodyAtlas, same tech as ProjectRemnants party portraits).
     * UI draws this one image instead of a per-frame 3D viewport, so roster
     * render cost stays independent of NPC count. Returns null on any failure;
     * the caller falls back to a static profession icon / initials.
     */
    public static zombie.core.textures.Texture getPortraitTexture(zombie.characters.IsoGameCharacter character) {
        if (!(character instanceof zombie.core.skinnedmodel.visual.IHumanVisual visual)) return null;
        try {
            zombie.core.skinnedmodel.DeadBodyAtlas.BodyParams bp = new zombie.core.skinnedmodel.DeadBodyAtlas.BodyParams();
            bp.init(visual, zombie.iso.IsoDirections.S, "player", "idle", 0.0F);
            zombie.core.skinnedmodel.DeadBodyAtlas.BodyTexture bt = zombie.core.skinnedmodel.DeadBodyAtlas.instance.getBodyTexture(bp);
            return bt != null ? bt.getTexture() : null;
        } catch (RuntimeException | LinkageError e) {
            return null;
        }
    }
    public static se.krka.kahlua.vm.KahluaTable waterSourceBacking(zombie.iso.IsoObject tap) {
        return WaterReads.backing(tap);
    }
    public static se.krka.kahlua.vm.KahluaTable inventoryReadSlice(zombie.inventory.ItemContainer container,
            ArrayList<zombie.inventory.InventoryItem> items,int size,int offset,int limit) {
        return InventoryReads.slice(container,items,size,offset,limit);
    }
    public static se.krka.kahlua.vm.KahluaTable warehouseFastScan(String settlementId,
            se.krka.kahlua.vm.KahluaTable containers, boolean force) {
        return WarehouseFastIndex.scanSettlement(settlementId, containers, force);
    }
    public static void warehouseResetCache(String settlementId) {
        if (settlementId != null) {
            WarehouseFastIndex.invalidateSettlement(settlementId);
        } else {
            WarehouseFastIndex.reset();
        }
    }
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
    public static boolean bindingValid(IsoPlayer body,String id) {
        CarrierRuntime runtime=handles.get(body);
        // Same-thread read: carrierId would repeat the entire presence check.
        return runtime!=null && id!=null && runtime.carrierPresent(body) && id.equals(runtime.id());
    }
    public static boolean carrierActive(IsoPlayer body) {
        CarrierRuntime runtime=handles.get(body); return runtime!=null && runtime.carrierActive(body);
    }
    public static String carrierId(IsoPlayer body) {
        CarrierRuntime runtime=handles.get(body); return runtime==null ? "" : runtime.carrierId(body);
    }
    /** Lifecycle identity survives death; never a grant to move or access an unbound body. */
    public static String ownedCarrierId(IsoPlayer body) {
        if (!liveAuthority()) return "";
        CarrierRuntime runtime=handles.get(body);
        return runtime!=null && runtime.body()==body && runtime.id()!=null ? runtime.id() : "";
    }
    public static String motionResult(IsoPlayer body) {
        CarrierRuntime runtime=handles.get(body); return runtime==null ? "UNAVAILABLE" : runtime.motionResult(body);
    }
    public static boolean stopCarrier(IsoPlayer body) {
        CarrierRuntime runtime=handles.get(body);
        return runtime!=null && authority.legacyAllowed(runtime.id()) && runtime.stopCarrier(body);
    }
    private static boolean liveAuthority() {
        var world=zombie.iso.IsoWorld.instance;
        return enabled && Thread.currentThread()==thread && owner==world && world!=null
            && ownerCell==world.currentCell && ProbeRules.canSimulate(zombie.network.GameClient.client,zombie.network.GameServer.server);
    }
    public static String acquireBodyControl(IsoPlayer body,String job,double generation) {
        if (!liveAuthority() || !(body instanceof ProbeNpc npc) || !carrierPresent(body)
            || generation<1 || generation>9007199254740991d || generation!=Math.floor(generation)
            || npc.stopMask()!=0 || controlCalls.contains(carrierId(body))) return "";
        return authority.acquire(carrierId(body),job,(long)generation);
    }
    public static int bodyStopMask(IsoPlayer body,String key) {
        if (!liveAuthority() || !carrierPresent(body) || !(body instanceof ProbeNpc npc)
            || !authority.allows(carrierId(body),key,true) || controlCalls.contains(carrierId(body))) return -1;
        return npc.stopMask();
    }
    public static boolean releaseBodyControl(IsoPlayer body,String key) {
        return bodyStopMask(body,key)==0 && authority.release(carrierId(body),key,true);
    }
    public static String moveWithControl(IsoPlayer body,String key,IsoPlayer actor,double x,double y,double z) {
        String id=carrierId(body);
        if (!liveAuthority() || !carrierPresent(body) || !authority.allows(id,key,false)
            || !controlCalls.add(id)) return "CONTROL_DENIED";
        try {
            // moveTo clears native actions: do not silently interrupt an active action.
            if (!body.getCharacterActions().isEmpty()) return "NATIVE_ACTION_BUSY";
            if (body instanceof ProbeNpc npc && npc.furniturePoseOwned()) return "FURNITURE_EXIT_PENDING";
            CarrierRuntime runtime=handles.get(body);
            String result=runtime.workerCommand("move",actor,x,y,z); refresh(runtime); return result;
        } finally { controlCalls.remove(id); }
    }
    public static boolean stopWithControl(IsoPlayer body,String key) {
        String id=carrierId(body);
        if (!liveAuthority() || !carrierPresent(body) || !authority.allows(id,key,true)
            || !controlCalls.add(id)) return false;
        try { return handles.get(body).stopCarrier(body); }
        finally { controlCalls.remove(id); }
    }
    public static String moveSeatWithControl(IsoPlayer body,String key,zombie.iso.IsoObject object,double maxPathLength) {
        return moveSeatControlled(body,key,object,maxPathLength,false);
    }
    public static String moveSleepSeatWithControl(IsoPlayer body,String key,zombie.iso.IsoObject object) {
        return moveSeatControlled(body,key,object,0,true);
    }
    private static String moveSeatControlled(IsoPlayer body,String key,zombie.iso.IsoObject object,double maxPathLength,boolean sleep) {
        String id=carrierId(body);
        if (!liveAuthority() || !carrierPresent(body) || !(body instanceof ProbeNpc npc)
                || !authority.allows(id,key,false) || !controlCalls.add(id)) return "CONTROL_DENIED";
        try {
            if (!body.getCharacterActions().isEmpty()) return "NATIVE_ACTION_BUSY";
            if (npc.furniturePoseOwned()) return "FURNITURE_EXIT_PENDING";
            return npc.moveToFurniture(object,Double.isFinite(maxPathLength) ? Math.max(0,Math.min(100,maxPathLength)) : 0,sleep);
        } finally { controlCalls.remove(id); }
    }
    public static zombie.iso.IsoObject reachedSeat(IsoPlayer body) {
        return liveAuthority() && carrierPresent(body) && body instanceof ProbeNpc npc ? npc.reachedFurniture() : null;
    }
    public static boolean reposeWithControl(IsoPlayer body,String key,String kind,boolean enter) {
        String id=carrierId(body);
        if (!liveAuthority() || !(body instanceof ProbeNpc npc) || !carrierPresent(body)
            || !authority.allows(id,key,!enter) || !controlCalls.add(id)) return false;
        try { return enter ? npc.beginRepose(kind) : npc.endRepose(); }
        finally { controlCalls.remove(id); }
    }
    public static String moveBedWithControl(IsoPlayer body,String key,zombie.iso.IsoObject object,se.krka.kahlua.vm.KahluaTable locations) {
        String id=carrierId(body);
        if (!liveAuthority() || !(body instanceof ProbeNpc npc) || !carrierPresent(body) || object==null || locations==null
            || !authority.allows(id,key,false) || !controlCalls.add(id)) return "CONTROL_DENIED";
        try {
            if (!body.getCharacterActions().isEmpty()) return "NATIVE_ACTION_BUSY";
            if (npc.furniturePoseOwned()) return "FURNITURE_EXIT_PENDING";
            return npc.moveToBed(object,locations);
        } finally { controlCalls.remove(id); }
    }
    public static boolean bedPoseReady(IsoPlayer body,String pose) {
        return carrierPresent(body) && body instanceof ProbeNpc npc && npc.bedPoseReady(pose);
    }
    public static boolean furniturePoseWithControl(IsoPlayer body,String key,zombie.iso.IsoObject object,String phase) {
        String id=carrierId(body);
        if (!liveAuthority() || !(body instanceof ProbeNpc npc) || !carrierPresent(body) || object==null && !"FLOOR".equals(phase)
                || !authority.allows(id,key,false) || !controlCalls.add(id)) return false;
        try {
            if ("FLOOR".equals(phase)) return object==null && npc.beginOwnedFloorPose();
            if ("PREPARE".equals(phase)) return npc.prepareFurniturePose(object);
            if ("STAND_TARGET".equals(phase)) return npc.captureFurnitureStand(object);
            if ("ALIGN_BED".equals(phase)) return npc.alignBedPose(object);
            if ("LIE".equals(phase)) return npc.beginOwnedBedPose(object);
            return false;
        } finally { controlCalls.remove(id); }
    }
    public static boolean floorSleepSafe(IsoPlayer body,int x,int y,int z) {
        return carrierPresent(body) && body instanceof ProbeNpc npc && npc.floorSleepSafe(x,y,z);
    }
    public static boolean reposeAtWithControl(IsoPlayer body,String key,String kind,zombie.iso.IsoObject furniture,String quality) {
        String id=carrierId(body);
        if (!liveAuthority() || !(body instanceof ProbeNpc npc) || !carrierPresent(body) || furniture==null
            || !authority.allows(id,key,false) || !controlCalls.add(id)) return false;
        try { return npc.beginRepose(kind,furniture,quality); }
        finally { controlCalls.remove(id); }
    }
    public static boolean freezeBodyControl() {
        if (!liveAuthority()) return false;
        authority.freeze(); return true;
    }
    public static boolean thawBodyControl() { return liveAuthority() && authority.thaw(); }
    public static boolean retireBodyControl() {
        if (!liveAuthority()) return false;
        authority.retire(); return true;
    }
    public static String begin(boolean enable) {
        saveReceipt=null;
        modDataCache.clear();
        WarehouseFastIndex.reset(); // ModData reloads with the world; never reuse old roots.
        thread=Thread.currentThread(); enabled=enable;
        var world=zombie.iso.IsoWorld.instance;
        var cell=world==null ? null : world.currentCell;
        if (owner!=null && (owner!=world || ownerCell!=cell)) {
            for (CarrierRuntime runtime:slots.values()) {
                runtime.begin(false,false);
                if (runtime.body()!=null) { enabled=false; return "RESET_REQUIRED old world disposal pending"; }
            }
            slots.clear(); catalogue.clear(); ids.clear(); handles.clear(); ownedHandles.clear(); active.clear(); selected=null;
            authority.retire(); authority=new BodyAuthority(); controlCalls.clear();
            ProbePersistence.invalidateVerification();
        }
        owner=world; ownerCell=cell;
        if (authority.retired() && slots.values().stream().allMatch(r -> r.body()==null)) authority=new BodyAuthority();
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
        if (!authority.legacyAllowed(runtime.id()) && !"inspect".equals(command)) return "CONTROL_REQUIRED";
        if ("spawn".equals(command) && runtime.id()!=null && runtime.body()==null)
            return spawnAdditional(actor,x,y,z);
        String result=runtime.command(command,actor,x,y,z); refresh(runtime); return result;
    }
    public static String commandFor(String id,String command,IsoPlayer actor,double x,double y,double z) {
        if (Thread.currentThread()!=thread) return "WRONG_THREAD";
        if (!enabled) return "DRIVER_UNAVAILABLE";
        CarrierRuntime runtime=find(id);
        if (runtime==null || "spawn".equals(command)) return "STALE_NPC";
        if (!authority.legacyAllowed(runtime.id()) && !"inspect".equals(command)) return "CONTROL_REQUIRED";
        String result=runtime.workerCommand(command,actor,x,y,z); refresh(runtime); return result;
    }
    /** Explicit Debug lifecycle operation; never removes an actively granted body. */
    public static String removeIdleCarrier(String id,IsoPlayer expected,IsoPlayer actor) {
        CarrierRuntime runtime=find(id);
        if (!liveAuthority() || runtime==null || runtime.body()!=expected || !(expected instanceof ProbeNpc npc)) return "STALE_NPC";
        if (!authority.lifecycleIdle(id) || npc.stopMask()!=0 || !controlCalls.add(id)) return "CONTROL_RETAINED";
        try {
            String result=runtime.workerCommand("remove",actor,0,0,0); refresh(runtime); return result;
        } finally { controlCalls.remove(id); }
    }
    public static String spawnAdditional(IsoPlayer actor,double x,double y,double z) {
        if (Thread.currentThread()!=thread || !enabled) return "DRIVER_UNAVAILABLE";
        if (!authority.lifecycleIdle("spawn")) return "ADMISSION_CLOSED";
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
        authority.retire();
        saveReceipt=null;
        modDataCache.clear();
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
    public static String clearForSave() { return !authority.legacyAllowed(current().id()) ? "CONTROL_REQUIRED" : current().clearForSave(); }
    public static String saveCheckpoint(String mode,boolean home,double x,double y,double z) {
        return !authority.legacyAllowed(current().id()) ? "CONTROL_REQUIRED" : current().saveCheckpoint(mode,home,x,y,z);
    }
    public static String saveCheckpointFor(String id,String mode,boolean home,double x,double y,double z) {
        CarrierRuntime runtime=find(id); return runtime==null ? "STALE_NPC" : !authority.legacyAllowed(runtime.id()) ? "CONTROL_REQUIRED" : runtime.saveCheckpoint(mode,home,x,y,z);
    }
    public static boolean saveBodyReady(String id,IsoPlayer expected) {
        CarrierRuntime runtime=find(id);
        return liveAuthority() && runtime!=null && runtime.body()==expected && carrierPresent(expected)
            && expected instanceof ProbeNpc npc && authority.saveIdle(id) && npc.stopMask()==0 && !controlCalls.contains(id);
    }
    /** Pure capture after the Lua barrier has reconciled business and Lua queues. */
    public static String captureCheckpointFor(String id,String mode,boolean home,double x,double y,double z) {
        CarrierRuntime runtime=find(id);
        if (!liveAuthority() || runtime==null || !authority.saveIdle(id) || !controlCalls.add(id)) return "SAVE_CONTROL_RETAINED";
        try { return runtime.captureStoppedCheckpoint(mode,home,x,y,z); }
        finally { controlCalls.remove(id); }
    }
    private static java.nio.file.Path saveFile() {
        return java.nio.file.Path.of(zombie.ZomboidFileSystem.instance.getFileNameInCurrentSave("global_mod_data.bin"));
    }
    public static boolean armSaveReceipt() {
        saveReceipt=null;
        if (!liveAuthority() || !authority.saveDrained() || !controlCalls.isEmpty()) return false;
        try {
            var data=zombie.world.moddata.GlobalModData.instance;
            saveReceipt=new ProbeSaveReceipt(saveFile(),data.get(ProbeSaveReceipt.WORK),data.get(ProbeSaveReceipt.NPC));
            return true;
        } catch (java.io.IOException | RuntimeException error) { log("SAVE_RECEIPT_ARM_FAILED "+error); return false; }
    }
    public static boolean verifySaveReceipt() {
        if (!liveAuthority() || saveReceipt==null || !authority.saveDrained()) return false;
        try {
            var data=zombie.world.moddata.GlobalModData.instance;
            return saveReceipt.matches(saveFile(),data.get(ProbeSaveReceipt.WORK),data.get(ProbeSaveReceipt.NPC));
        } catch (java.io.IOException | RuntimeException error) { log("SAVE_RECEIPT_CHECK_FAILED "+error); return false; }
        finally { saveReceipt=null; } // One bounded read per save; no per-frame polling.
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
        if (!authority.legacyAllowed(current().id())) return "CONTROL_REQUIRED";
        try { ProbePersistence.verifyStore(); }
        catch (java.io.IOException | RuntimeException error) { return "RESTORE_BLOCKED "+error; }
        String result=current().restoreCheckpoint(actor); refresh(current()); return result;
    }
    /** Load lifecycle access by stable ID; selection and old task grants confer no authority. */
    public static String restoreCheckpointFor(String id,IsoPlayer actor) {
        CarrierRuntime runtime=find(id);
        if (!liveAuthority() || runtime==null || !authority.lifecycleIdle(id) || controlCalls.contains(id)) return "RESTORE_CONTROL_RETAINED";
        try { ProbePersistence.verifyStore(); }
        catch (java.io.IOException | RuntimeException error) { return "RESTORE_BLOCKED "+error; }
        if (!controlCalls.add(id)) return "RESTORE_CONTROL_RETAINED";
        try { String result=runtime.restoreCheckpoint(actor); refresh(runtime); return result; }
        finally { controlCalls.remove(id); }
    }
    public static String reportCheckpoint() { return current().reportCheckpoint(); }
    public static String checkpointMode() { return current().checkpointMode(); }
    public static boolean checkpointHasHome() { return current().checkpointHasHome(); }
    public static double checkpointHomeX() { return current().checkpointHomeX(); }
    public static double checkpointHomeY() { return current().checkpointHomeY(); }
    public static double checkpointHomeZ() { return current().checkpointHomeZ(); }
}
