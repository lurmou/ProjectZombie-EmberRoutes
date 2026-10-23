package emberroutes.probe;

import java.util.UUID;
import me.zed_0xff.zombie_buddy.ZombieBuddy;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.characters.SurvivorFactory;
import zombie.core.Core;
import zombie.iso.IsoCamera;
import zombie.iso.IsoCell;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoWorld;
import zombie.network.GameClient;
import zombie.network.GameServer;

final class CarrierRuntime {
    private final ProbeSession<ProbeNpc> SESSION = new ProbeSession<>();
    private String probeId;
    private Thread worldThread;
    private IsoCell owningCell;
    private IsoWorld owningWorld;
    private boolean enabled;
    private boolean automaticFault;
    private final ProbeRetirement RETIREMENT = new ProbeRetirement();
    private final ProbeWorldLinks WORLD_LINKS = new ProbeWorldLinks();
    private long nextRetirementScan;
    private final ProbeRestoreGate RESTORE = new ProbeRestoreGate();
    private ProbeCheckpoint.Data restoredCheckpoint;

    private final ProbePersistence persistence;
    final String slot;
    CarrierRuntime(String slot) { this.slot = slot; this.persistence = new ProbePersistence(slot); }
    ProbeNpc body() { return SESSION.get(); }
    String id() { return probeId; }
    void rememberSavedId(String id) { if (SESSION.get()==null && id!=null) probeId=id; }
    public String begin(boolean enabled) { return begin(enabled, true); }
    public String version() { return BuildInfo.VERSION; }
    /** Read-only monotonic CPU diagnostics; never reads game or NPC state. */
    public double diagnosticTimeNanos() { return System.nanoTime(); }
    /** SP diagnostic access only; never exposes a multiplayer asset mutation path. */
    public IsoPlayer actionCarrier(IsoPlayer actor) {
        IsoPlayer npc = controlledCarrier(actor);
        return npc != null && carrierActive(npc) ? npc : null;
    }

    public IsoPlayer controlledCarrier(IsoPlayer actor) {
        ProbeNpc npc = SESSION.get();
        if (!carrierPresent(npc) || actor == null || actor instanceof ProbeNpc
                || !actor.isLocalPlayer() || actor.isDead() || actor.getCurrentSquare() == null) return null;
        double dx = actor.getX() - npc.getX(), dy = actor.getY() - npc.getY(), dz = actor.getZ() - npc.getZ();
        return dx * dx + dy * dy + dz * dz <= 256 ? npc : null;
    }

    public String carrierId(IsoPlayer expected) {
        return carrierPresent(expected) ? probeId : "";
    }

    /** Pause event advances retirement or freezes the path deadline; never steps simulation. */
    public void retirementTick() {
        if (Thread.currentThread() != worldThread || automaticFault) return;
        ProbeNpc npc = SESSION.get();
        if (npc != null && ownsCurrentWorld()) {
            if (npc.retiring()) advanceRetirement(npc);
            else npc.pauseMovementClock(System.nanoTime());
        }
    }

    public boolean carrierActive(IsoPlayer expected) {
        return carrierPresent(expected) && !SESSION.get().moving();
    }

    public boolean carrierPresent(IsoPlayer expected) {
        ProbeNpc npc = SESSION.get();
        return Thread.currentThread() == worldThread && enabled
                && ProbeRules.canSimulate(GameClient.client, GameServer.server)
                && npc != null && npc == expected && npc.attached() && !npc.failed()
                && !npc.retiring() && !npc.isDead()
                && ownsCurrentWorld() && npc.getCurrentSquare() != null && npc.getCell() == owningCell;
    }

    public String motionResult(IsoPlayer expected) {
        return carrierPresent(expected) ? SESSION.get().lastMoveResult() : "UNAVAILABLE";
    }

    public boolean stopCarrier(IsoPlayer expected) {
        if (Thread.currentThread() != worldThread || !ProbeRules.canSimulate(GameClient.client, GameServer.server)
                || expected == null || expected != SESSION.get() || !ownsCurrentWorld()) return false;
        SESSION.get().stopProbe();
        return true;
    }
    public void log(String text) { System.out.println(BuildInfo.PREFIX + " " + text); }

    /** Called on game start. Lua requests a single restore after the local player is ready. */
    public String begin(boolean enableProbe, boolean verifyBaseline) {
        releaseDisposedWorld();
        if (SESSION.get() != null) return result("RESET_REQUIRED", "remove previous carrier first");
        worldThread = Thread.currentThread();
        enabled = enableProbe;
        automaticFault = false;
        RESTORE.reset();
        restoredCheckpoint = null;
        if (verifyBaseline && enabled && ProbeRules.canSimulate(GameClient.client, GameServer.server)) {
            try {
                var baseline = ProbePersistence.runtimeBaseline();
                var source = IsoPlayer.class.getProtectionDomain().getCodeSource();
                log("BASELINE_CHECK gameJar=" + baseline.gameJar() + " sha256=" + baseline.hash()
                        + " IsoPlayerCodeSource=" + (source == null ? "unavailable" : source.getLocation()));
                if (!baseline.matches()) {
                    enabled = false;
                    return result("BASELINE_CHANGED", "gameJar=" + baseline.gameJar() + " sha256=" + baseline.hash() + "; re-review required");
                }
            } catch (Exception | LinkageError error) {
                enabled = false;
                return result("BASELINE_UNAVAILABLE", error.toString());
            }
        }
        try {
            IsoPlayer.class.getMethod("setNpc", boolean.class);
            IsoPlayer.class.getMethod("pathToLocationF", float.class, float.class, float.class);
            IsoPlayer.class.getMethod("setInstance", IsoPlayer.class);
            IsoCamera.class.getMethod("setCameraCharacter", IsoGameCharacter.class);
            IsoCell.class.getMethod("addMovingObject", zombie.iso.IsoMovingObject.class);
        } catch (ReflectiveOperationException | LinkageError error) {
            enabled = false;
            return result("API_INCOMPATIBLE", error.toString());
        }
        return result("READY", environment());
    }

    public String command(String command, IsoPlayer actor, double x, double y, double z) {
        return dispatch(command, actor, x, y, z, false);
    }
    public String workerCommand(String command, IsoPlayer actor, double x, double y, double z) {
        return dispatch(command, actor, x, y, z, true);
    }
    private String dispatch(String command, IsoPlayer actor, double x, double y, double z, boolean autonomous) {
        try { return execute(command, actor, x, y, z, autonomous); }
        catch (RuntimeException | LinkageError error) {
            ProbeNpc npc = SESSION.get();
            if (npc != null) npc.freeze("command " + error);
            return result("COMMAND_FAILED", error.toString());
        }
    }

    private String execute(String command, IsoPlayer actor, double x, double y, double z, boolean autonomous) {
        if (!ProbeRules.isCommand(command)) return result("INVALID_COMMAND", String.valueOf(command));
        if (Thread.currentThread() != worldThread) return result("WRONG_THREAD", "begin required on world thread");
        if ("inspect".equals(command)) return result("INSPECT", environment() + " " + inspect());
        // Cleanup remains available if the operator dies or disables the probe.
        if ("remove".equals(command)) {
            if (ProbeRules.canSimulate(GameClient.client, GameServer.server)) RESTORE.removed();
            return requestRemoval(true);
        }
        if (!enabled) return result("DISABLED", "enable CarrierProbe in sandbox options");
        if (!ProbeRules.canSimulate(GameClient.client, GameServer.server)) {
            return result("DRIVER_UNAVAILABLE", "MP carrier not implemented; no entity created");
        }
        if (actor == null || actor instanceof ProbeNpc || !actor.isLocalPlayer() || actor.isDead()) {
            return result("INVALID_ACTOR", "living local player required");
        }
        IsoCell cell = IsoWorld.instance == null ? null : IsoWorld.instance.currentCell;
        if (cell == null) return result("WORLD_UNAVAILABLE", "no current cell");
        ProbeNpc npc = SESSION.get();
        if (npc != null && !ownsCurrentWorld()) return result("WORLD_CHANGED", "old carrier cannot be commanded in new world");
        if (npc != null && npc.retiring() && ("move".equals(command) || "stop".equals(command)))
            return result("CARRIER_RETIRING", inspect());
        if ("stop".equals(command)) {
            if (npc == null) return result("ABSENT", "no carrier");
            npc.stopProbe();
            return result("STOPPED", inspect());
        }
        if ("spawn".equals(command) && npc != null) return result("EXISTS", inspect());
        if ("spawn".equals(command)) {
            try {
                if (!RESTORE.canSpawn(false, !"EMPTY".equals(persistence.state())))
                    return result("CHECKPOINT_PENDING", "restore or explicitly remove saved NPC first; state=" + RESTORE.state());
            } catch (java.io.IOException error) {
                return result("CHECKPOINT_BLOCKED", error.toString());
            }
        }
        IsoPlayer origin = autonomous && npc != null ? npc : actor;
        boolean allowed=autonomous ? ProbeRules.allowedWorkerPoint(origin.getX(),origin.getY(),origin.getZ(),x,y,z)
            : ProbeRules.allowedPoint(origin.getX(),origin.getY(),origin.getZ(),x,y,z);
        if (!allowed) {
            return result("INVALID_POINT", autonomous ? "finite integral-floor point within 256 tiles in 3D required"
                : "finite integral-floor point within 16 tiles in 3D required");
        }
        IsoGridSquare square = cell.getGridSquare((int)Math.floor(x), (int)Math.floor(y), (int)z);
        if (square == null || !square.TreatAsSolidFloor() || square.isSolid() || square.isSolidTrans()) {
            return result("INVALID_TILE", "loaded walkable floor required");
        }
        if ("move".equals(command)) {
            if (npc == null) return result("ABSENT", "no carrier");
            if (npc.failed() || !npc.attached()) return result("CARRIER_FAILED", inspect());
            if (!(autonomous ? ProbeRules.allowedWorkerPoint(npc.getX(),npc.getY(),npc.getZ(),x,y,z)
                    : ProbeRules.allowedPoint(npc.getX(),npc.getY(),npc.getZ(),x,y,z))) {
                return result("INVALID_POINT", "target too far from carrier");
            }
            npc.moveTo((float)x, (float)y, (float)z);
            return result("MOVE_REQUESTED", inspect());
        }
        if (!square.isFree(false)) return result("INVALID_TILE", "birth square occupied");
        IsoPlayer playerBefore = IsoPlayer.getInstance();
        IsoGameCharacter cameraBefore = IsoCamera.getCameraCharacter();
        try {
            ProbeNpc created = SESSION.spawn(() -> new ProbeNpc(cell, SurvivorFactory.CreateSurvivor()));
            probeId = slot.equals("legacy") ? UUID.randomUUID().toString() : slot;
            owningCell = cell;
            owningWorld = IsoWorld.instance;
            RESTORE.attached();
            attach(created, cell, square, (float)x, (float)y, (float)z);
            return result("SPAWNED", inspect());
        } catch (RuntimeException | LinkageError error) {
            log("SPAWN_FAILED " + error);
            try { remove(); } catch (RuntimeException | LinkageError cleanup) {
                log("CLEANUP_FAILED retained ownership: " + cleanup);
            }
            return result("SPAWN_FAILED", error.toString());
        } finally {
            IsoPlayer.setInstance(playerBefore);
            if (cameraBefore == null) IsoCamera.clearCameraCharacter();
            else IsoCamera.setCameraCharacter(cameraBefore);
        }
    }

    public void tick() {
        if (Thread.currentThread() != worldThread || automaticFault) return;
        ProbeNpc npc = SESSION.get();
        if (npc == null) return;
        if (!ownsCurrentWorld()) {
            RESTORE.lost(); automaticFault = true; enabled = false;
            log("WORLD_CHANGED old carrier retained until complete engine disposal; no native cleanup in new world");
            return;
        }
        if (npc.retiring()) {
            advanceRetirement(npc);
            return;
        }
        IsoCell cell = IsoWorld.instance == null ? null : IsoWorld.instance.currentCell;
        if (cell != owningCell || npc.getCurrentSquare() == null || npc.isDead()) {
            if (npc.isDead()) RESTORE.removed();
            else RESTORE.lost();
            try { remove(); }
            catch (RuntimeException | LinkageError error) {
                automaticFault = true;
                npc.freeze("automatic cleanup failed: " + error);
                log("AUTO_CLEANUP_STOPPED ownership retained; explicit remove required");
            }
        }
        // Deliberately does not call npc.update(): the world's scheduler owns updates.
    }

    public String reset() {
        releaseDisposedWorld();
        if (worldThread != null && Thread.currentThread() != worldThread) return result("WRONG_THREAD", "reset refused");
        try {
            String answer = remove();
            enabled = false;
            if (SESSION.get() == null) worldThread = null;
            return answer;
        } catch (RuntimeException | LinkageError error) {
            automaticFault = true;
            enabled = false;
            return result("CLEANUP_FAILED", "ownership retained: " + error);
        }
    }

    public String clearForSave() {
        if (Thread.currentThread() != worldThread) return result("WRONG_THREAD", "save cleanup refused");
        try { return remove(); }
        catch (RuntimeException | LinkageError error) {
            automaticFault = true;
            log("SAVE_CLEANUP_FAILED " + error);
            return "CLEANUP_FAILED " + error;
        }
    }

    private boolean persistenceReady() {
        return Thread.currentThread() == worldThread && enabled
                && ProbeRules.canSimulate(GameClient.client, GameServer.server)
                && IsoWorld.instance != null && IsoWorld.instance.currentCell != null
                && (SESSION.get() == null || ownsCurrentWorld());
    }

    private boolean ownsCurrentWorld() {
        return owningWorld != null && owningWorld == IsoWorld.instance && owningCell != null
                && owningCell == IsoWorld.instance.currentCell;
    }

    /** Called only from OnSave after all fixture owners have released their tasks. */
    public String saveCheckpoint(String mode, boolean home, double hx, double hy, double hz) {
        return captureCheckpoint(mode, home, hx, hy, hz, false);
    }
    String captureStoppedCheckpoint(String mode, boolean home, double hx, double hy, double hz) {
        return captureCheckpoint(mode, home, hx, hy, hz, true);
    }
    private String captureCheckpoint(String mode, boolean home, double hx, double hy, double hz, boolean stopped) {
        if (!persistenceReady()) return result("SAVE_UNAVAILABLE", "SP world-thread driver required");
        try {
            ProbeNpc npc = SESSION.get();
            if (RESTORE.state() == ProbeRestoreGate.State.REMOVED || (npc != null && npc.isDead())) {
                RESTORE.removed(); persistence.empty();
                return result("CHECKPOINT_EMPTY", "explicit removal/death committed with next world save");
            }
            if (npc == null && RESTORE.state() == ProbeRestoreGate.State.UNRESOLVED)
                return result("CHECKPOINT_RETAINED", "unresolved saved record left unchanged");
            if (!carrierPresent(npc)) return blockCheckpoint("CARRIER_UNAVAILABLE state=" + RESTORE.state());
            if (stopped) {
                if (npc.stopMask() != 0) return blockCheckpoint("BODY_NOT_STOPPED");
            } else npc.stopProbe();
            ProbeCheckpoint.Data data = ProbePersistence.capture(npc, probeId, mode, home, (float)hx, (float)hy, (float)hz);
            persistence.write(data);
            return result("CHECKPOINT_SAVED", "id=" + probeId + " items=" + data.items().size()
                    + " nativeBytes=" + data.nativeBytes().length + " mode=" + mode + " home=" + home);
        } catch (java.io.IOException | RuntimeException | LinkageError error) {
            return blockCheckpoint(error.toString());
        }
    }

    public String blockCheckpoint(String reason) {
        if (!persistenceReady()) return result("SAVE_UNAVAILABLE", "cannot publish outside SP world thread");
        persistence.block(reason);
        return result("CHECKPOINT_BLOCKED", reason + "; old checkpoint will not be replayed");
    }

    public String restoreCheckpoint(IsoPlayer actor) {
        if (!persistenceReady()) return result("RESTORE_UNAVAILABLE", "SP world-thread driver required");
        if (!RESTORE.canRestore(SESSION.get() != null))
            return result("RESTORE_ALREADY_CONSUMED", "state=" + RESTORE.state() + " " + inspect());
        if (actor == null || actor instanceof ProbeNpc || !actor.isLocalPlayer() || actor.isDead()
                || actor.getCurrentSquare() == null) return result("RESTORE_INVALID_ACTOR", "living local player required");
        IsoPlayer playerBefore = IsoPlayer.getInstance();
        IsoGameCharacter cameraBefore = IsoCamera.getCameraCharacter();
        try {
            String state = persistence.state();
            if (state.equals("EMPTY")) return result("CHECKPOINT_EMPTY", "no saved NPC");
            ProbeCheckpoint.Data data = persistence.read();
            double dx = actor.getX() - data.x(), dy = actor.getY() - data.y(), dz = actor.getZ() - data.z();
            if (dx * dx + dy * dy + dz * dz > 256)
                return result("RESTORE_TOO_FAR", "saved pos=" + data.x() + "," + data.y() + "," + data.z()
                        + "; approach within 16 tiles then retry");
            IsoCell cell = IsoWorld.instance.currentCell;
            IsoGridSquare square = cell.getGridSquare((int)Math.floor(data.x()), (int)Math.floor(data.y()), (int)Math.floor(data.z()));
            if (square == null || !square.TreatAsSolidFloor() || square.isSolid() || square.isSolidTrans() || !square.isFree(false))
                return result("RESTORE_TILE_UNAVAILABLE", "saved pos=" + data.x() + "," + data.y() + "," + data.z()
                        + "; reach that area then retry; no relocation performed");
            ProbeNpc candidate = new ProbeNpc(cell, SurvivorFactory.CreateSurvivor());
            ProbePersistence.load(candidate, data);
            // Publish ownership before attaching, so partial attachment failures retain one owner.
            SESSION.spawn(() -> candidate);
            probeId = data.npcId(); owningCell = cell; owningWorld = IsoWorld.instance; RESTORE.attached();
            attach(candidate, cell, square, data.x(), data.y(), data.z());
            restoredCheckpoint = data;
            return result("CHECKPOINT_RESTORED", "items=" + data.items().size() + " mode=" + data.mode() + " " + inspect());
        } catch (java.io.IOException | RuntimeException | LinkageError error) {
            if (SESSION.get() != null) { RESTORE.lost(); SESSION.get().freeze("restore attach failure: " + error); }
            return result("RESTORE_BLOCKED", error.toString() + "; saved data retained, no fallback NPC");
        } finally {
            IsoPlayer.setInstance(playerBefore);
            if (cameraBefore == null) IsoCamera.clearCameraCharacter();
            else IsoCamera.setCameraCharacter(cameraBefore);
        }
    }

    public String checkpointMode() { return restoredCheckpoint == null ? "HOLD" : restoredCheckpoint.mode(); }
    public boolean checkpointHasHome() { return restoredCheckpoint != null && restoredCheckpoint.hasHome(); }
    public double checkpointHomeX() { return restoredCheckpoint == null ? 0 : restoredCheckpoint.homeX(); }
    public double checkpointHomeY() { return restoredCheckpoint == null ? 0 : restoredCheckpoint.homeY(); }
    public double checkpointHomeZ() { return restoredCheckpoint == null ? 0 : restoredCheckpoint.homeZ(); }

    public String reportCheckpoint() {
        if (!persistenceReady()) return result("CHECKPOINT_UNAVAILABLE", "SP world-thread driver required");
        try {
            String state = persistence.state();
            if (state.equals("LIVE")) {
                var saved = persistence.read();
                log("CHECKPOINT_RECORD id=" + saved.npcId() + " pos=" + saved.x() + "," + saved.y() + "," + saved.z()
                        + " mode=" + saved.mode() + " home=" + saved.hasHome() + " items=" + saved.items().size()
                        + " bytes=" + saved.nativeBytes().length + " equipment=" + saved.equipment());
            }
            ProbeNpc npc = SESSION.get();
            if (carrierPresent(npc)) {
                var items = ProbePersistence.inventory(npc);
                for (int i = 0; i < Math.min(items.size(), 32); i++) log("CHECKPOINT_ITEM " + items.get(i));
            }
            return result("CHECKPOINT_REPORT", "record=" + state + " gate=" + RESTORE.state() + " " + inspect());
        } catch (java.io.IOException | RuntimeException | LinkageError error) {
            return result("CHECKPOINT_BLOCKED", error.toString());
        }
    }

    private void attach(ProbeNpc npc, IsoCell cell, IsoGridSquare square, float x, float y, float z) {
        npc.setX(x); npc.setY(y); npc.setZ(z);
        npc.setNextX(x); npc.setNextY(y); npc.setLastX(x); npc.setLastY(y); npc.setLastZ(z);
        npc.setCurrent(square); npc.square = square; npc.setMovingSquareNow();
        npc.setDoRender(true); npc.setSceneCulled(false); npc.setAlphaAndTarget(1.0f);
        npc.markAttached(); npc.addToWorld(); cell.addMovingObject(npc);
        if (!square.getMovingObjects().contains(npc)) square.getMovingObjects().add(npc);
        npc.resetModelNextFrame();
    }

    private void releaseDisposedWorld() {
        if (SESSION.get() == null || owningWorld == null || owningCell == null) return;
        boolean chunksDisposed = true;
        for (var map : owningCell.chunkMap) if (map != null) chunksDisposed = false;
        if (!ProbeRestoreGate.mayReleaseDisposedWorld(owningWorld != IsoWorld.instance,
                owningCell.getObjectList().isEmpty(), chunksDisposed)) return;
        // IngameState.exit -> KillCell -> Dispose has already stopped workers,
        // reset models, disposed every chunk map and replaced IsoWorld.instance.
        // Never call stop/removeFromWorld on an object from that destroyed world.
        SESSION.remove(npc -> npc.markDetached());
        probeId = null; owningCell = null; owningWorld = null; worldThread = null;
        automaticFault = false; enabled = false; restoredCheckpoint = null;
        RETIREMENT.clear(); WORLD_LINKS.clear(); RESTORE.reset();
        log("DISPOSED_WORLD_RELEASED engine world disposal confirmed; no live entity detached");
    }

    private String remove() {
        return requestRemoval(false);
    }

    private String requestRemoval(boolean explicitRetry) {
        ProbeNpc npc = SESSION.get();
        if (npc == null) return result("ABSENT", "no carrier");
        if (owningWorld != null && !ownsCurrentWorld())
            return result("REMOVAL_BLOCKED", "old world not confirmed disposed; no native removal in another world");
        if (!npc.attached()) return detachBody();
        if (RETIREMENT.result() == ProbeRetirement.Result.WAITING)
            return result("REMOVAL_PENDING", "waiting for attack/animation quiescence; " + inspect());
        if (npc.retiring() && !explicitRetry)
            return result("REMOVAL_BLOCKED", "automatic retry disabled; " + inspect());
        boolean firstRequest = !npc.retiring();
        npc.beginRetirement();
        automaticFault = false;
        if (firstRequest) WORLD_LINKS.clear();
        RETIREMENT.begin(System.nanoTime());
        nextRetirementScan = 0;
        // Unlink immediately, before returning to engine animation callbacks.
        WORLD_LINKS.releaseAndCheck(npc, owningCell);
        return result("REMOVAL_PENDING", "body retained until safe; " + inspect());
    }

    private void advanceRetirement(ProbeNpc npc) {
        if (RETIREMENT.result() != ProbeRetirement.Result.WAITING) return;
        long now = System.nanoTime();
        if (now < nextRetirementScan) return;
        nextRetirementScan = now + ProbeRetirement.SCAN_INTERVAL_NANOS;
        try {
            boolean busy = WORLD_LINKS.releaseAndCheck(npc, owningCell);
            ProbeRetirement.Result state = RETIREMENT.poll(now, busy);
            if (state == ProbeRetirement.Result.READY) detachBody();
            else if (state == ProbeRetirement.Result.BLOCKED)
                result("REMOVAL_BLOCKED", "attack/animation not quiescent; body retained, retry remove explicitly; " + inspect());
        } catch (RuntimeException | LinkageError error) {
            automaticFault = true;
            log("REMOVAL_FAILED body retained: " + error);
        }
    }

    private String detachBody() {
        boolean removed = SESSION.remove(npc -> {
            npc.stopProbe();
            npc.markDetached();
            npc.removeFromWorld();
            npc.removeFromSquare();
            if (owningCell != null) {
                owningCell.getObjectList().remove(npc);
                owningCell.getAddList().remove(npc);
                owningCell.getRemoveList().remove(npc);
            }
        });
        owningCell = null;
        owningWorld = null;
        automaticFault = false;
        RETIREMENT.clear();
        WORLD_LINKS.clear();
        restoredCheckpoint = null;
        return result(removed ? "REMOVED" : "ABSENT", "owned carrier only; checkpoint gate=" + RESTORE.state());
    }

    private String inspect() {
        ProbeNpc npc = SESSION.get();
        if (npc == null) return "carrier=absent";
        boolean inWorld = owningCell != null && owningCell.getObjectList().contains(npc);
        boolean pending = owningCell != null && owningCell.getAddList().contains(npc);
        boolean onSquare = npc.getCurrentSquare() != null && npc.getCurrentSquare().getMovingObjects().contains(npc);
        return "id=" + probeId + " pos=" + npc.getX() + "," + npc.getY() + "," + npc.getZ()
                + " attached=" + npc.attached() + " world=" + inWorld + " pending=" + pending
                + " square=" + onSquare + " updates=" + npc.updates() + " state=" + npc.getCurrentStateName()
                + " " + npc.motionStatus()
                + " retiring=" + npc.retiring() + " retirement=" + RETIREMENT.result()
                + " clearedLinks=" + WORLD_LINKS.clearedLinks() + " attackers=" + WORLD_LINKS.attackers()
                + " health=" + npc.getBodyDamage().getOverallBodyHealth()
                + " failed=" + npc.failed() + " reason=" + npc.failure();
    }

    private String environment() {
        return "version=" + version() + " game=" + Core.getInstance().getVersion()
                + " zb=" + ZombieBuddy.getVersion() + " client=" + GameClient.client + " server=" + GameServer.server
                + " enabled=" + enabled + " driver=" + (ProbeRules.canSimulate(GameClient.client, GameServer.server)
                ? "SP_NATIVE_CANDIDATE" : "MP_UNAVAILABLE") + " buildGameSha256=" + BuildInfo.GAME_SHA256;
    }

    private String result(String code, String details) {
        String text = code + " " + details;
        log(text);
        return text;
    }
}
