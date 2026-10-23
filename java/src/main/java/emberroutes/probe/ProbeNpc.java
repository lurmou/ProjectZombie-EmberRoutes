package emberroutes.probe;

import zombie.UpdateSchedulerSimulationLevel;
import zombie.ai.AIBrainPlayerControlVars;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.characters.SurvivorDesc;
import zombie.characters.component.AIComponent;
import zombie.iso.IsoCamera;
import zombie.iso.IsoCell;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.pathfind.PathFindBehavior2;

/** Owned single-player carrier experiment. No upstream NPC implementation is embedded. */
public final class ProbeNpc extends IsoPlayer {
    private boolean attached;
    private boolean failed;
    private boolean retiring;
    private String failure = "";
    private long updates;
    private final ProbeMovement movement = new ProbeMovement();
    private String pathResult = "IDLE";
    private String moveResult = "IDLE";
    private long nextProgressLog;
    private float moveStartX, moveStartY;

    ProbeNpc(IsoCell cell, SurvivorDesc desc) {
        // Current IsoGameCharacter only auto-registers nonzero constructor coordinates.
        // Construct at origin, acquire ownership, then explicitly attach at a checked tile.
        super(cell, desc, 0, 0, 0);
        setNpc(true);
        setUsername("EmberRoutes Probe");
        setCollidable(true);
        setGhostMode(false);
        setGodMod(false);
        setInvisible(false);
        setNoDamage(false);
    }

    @Override public boolean isLocalPlayer() { return false; }
    // Keep fluid changes attributable to the whitelisted native timed action.
    @Override public void autoDrink() { }
    @Override public UpdateSchedulerSimulationLevel getMinimumSimulationLevel() {
        return UpdateSchedulerSimulationLevel.FULL;
    }

    void markAttached() { attached = true; }
    void markDetached() { attached = false; }
    boolean attached() { return attached; }
    boolean failed() { return failed; }
    long updates() { return updates; }
    String failure() { return failure; }
    boolean retiring() { return retiring; }
    boolean moving() { return movement.active(); }
    int stopMask() {
        return (movement.active() ? 1 : 0) | (isMoving() ? 2 : 0)
            | (!getCharacterActions().isEmpty() ? 4 : 0) | (getPath2() != null ? 8 : 0)
            | (!getPathFindBehavior2().isGoalNone() && !getPathFindBehavior2().getIsCancelled() ? 16 : 0)
            | (getPathFindBehavior2().pathNextIsSet ? 32 : 0);
    }
    String lastMoveResult() { return moveResult; }
    void pauseMovementClock(long now) { movement.pause(now); }

    void beginRetirement() {
        retiring = true;
        stopProbe();
        setGhostMode(true);
        setNoDamage(true);
        setInvisible(true);
        setCollidable(false);
        setDoRender(false);
    }

    void moveTo(float x, float y, float z) {
        if (failed || retiring || !attached) throw new IllegalStateException("carrier not active");
        stopProbe();
        moveStartX = getX(); moveStartY = getY();
        long now = System.nanoTime();
        double distance=Math.hypot(Math.hypot(x-getX(),y-getY()),z-getZ());
        long timeout=(long)Math.min(180_000_000_000.0,10_000_000_000.0+distance*3_000_000_000.0);
        movement.begin(x,y,z,now,timeout);
        nextProgressLog = now + 1_000_000_000L;
        pathResult = "REQUESTED";
        moveResult = "MOVING";
        // The player action group has no PathFindState. Set only the native
        // request here; doDeferredMovement below must advance it every update.
        getPathFindBehavior2().pathNextIsSet = false;
        getPathFindBehavior2().pathToLocationF(x, y, z);
        ProbeRuntime.log("MOVE_TARGET origin=" + getX() + "," + getY() + "," + getZ()
                + " target=" + x + "," + y + "," + z + " distance=" + movement.distance(getX(), getY(), getZ()));
    }

    void stopProbe() {
        StopAllActionQueue();
        movement.cancel();
        moveResult = "STOPPED";
        getPathFindBehavior2().cancel();
        getPathFindBehavior2().pathNextIsSet = false;
        setPath2(null);
        setVariable("bPathfind", false);
        setMoving(false);
        isPlayerMoving = false;
        playerMoveDir.set(0, 0);
        setJustMoved(false);
        setRunning(false);
        setSprinting(false);
        discardRootMotion();
        AIComponent ai = getECSComponent(AIComponent.class);
        if (ai != null) {
            AIBrainPlayerControlVars vars = ai.getHumanControlVars();
            vars.justMoved = false; vars.running = false;
            vars.strafeX = 0; vars.strafeY = 0;
        }
    }

    void freeze(String reason) {
        if (failed) return;
        failed = true;
        failure = reason;
        try { stopProbe(); }
        catch (RuntimeException | LinkageError error) {
            failure += "; stop failed: " + error;
        }
        moveResult = "FAILED";
        ProbeRuntime.log("CARRIER_STOPPED " + failure + "; use remove");
    }

    @Override public void update() {
        if (!attached || failed || retiring) return;
        if (!ProbeRules.canSimulate(GameClient.client, GameServer.server)) {
            freeze("DRIVER_UNAVAILABLE multiplayer simulation not implemented");
            return;
        }
        if (getCurrentSquare() == null || isDead()) {
            freeze("WORLD_UNAVAILABLE_OR_DEAD");
            return;
        }
        // IsoPlayer.updateInternal2 temporarily assigns both globals even for NPCs.
        // Restore in finally; no player slots are written or registered.
        IsoPlayer playerBefore = IsoPlayer.getInstance();
        IsoGameCharacter cameraBefore = IsoCamera.getCameraCharacter();
        try {
            AIComponent ai = getECSComponent(AIComponent.class);
            if (ai == null) throw new IllegalStateException("AIComponent disappeared");
            ai.getHumanControlVars().justMoved = movement.active() && getPath2() != null
                    && getPathFindBehavior2().shouldBeMoving();
            super.update();
            updates++;
            if (movement.active() && System.nanoTime() >= nextProgressLog) {
                nextProgressLog = System.nanoTime() + 1_000_000_000L;
                ProbeRuntime.log("MOVE_PROGRESS " + motionStatus());
            }
        } catch (RuntimeException | LinkageError error) {
            freeze(error.toString());
        } finally {
            IsoPlayer.setInstance(playerBefore);
            if (cameraBefore == null) IsoCamera.clearCameraCharacter();
            else IsoCamera.setCameraCharacter(cameraBefore);
        }
    }

    /** Single root-motion owner: replace forward-only consumption with the
     * native path follower. Do not also call super.doDeferredMovement(), which
     * would submit a second displacement while a route is pending. */
    @Override protected void doDeferredMovement() {
        try {
            if (!attached || failed || retiring || !ProbeRules.canSimulate(GameClient.client, GameServer.server)) return;
            ProbeMovement.Outcome outcome = movement.tick(this::advancePath,
                    getX(), getY(), getZ(), System.nanoTime());
            if (outcome != ProbeMovement.Outcome.IDLE && outcome != ProbeMovement.Outcome.MOVING) {
                stopProbe();
                moveResult = outcome.name();
                ProbeRuntime.log("MOVE_" + outcome.name() + " " + motionStatus()
                        + " displacement=" + Math.hypot(getX() - moveStartX, getY() - moveStartY));
            }
        } finally {
            // PathFindBehavior2 reads deferred movement without consuming it.
            // Consume once, including idle/pending/stopped frames, to prevent
            // residual forward movement or accumulation across later commands.
            discardRootMotion();
        }
    }

    private ProbeMovement.PathResult advancePath() {
        PathFindBehavior2 path = getPathFindBehavior2();
        PathFindBehavior2.BehaviorResult result = path.update();
        pathResult = result.name();
        if (result == PathFindBehavior2.BehaviorResult.Working) {
            if (path.pathNextIsSet) faceLocationF(path.pathNextX, path.pathNextY);
            boolean walking = getPath2() != null && path.shouldBeMoving();
            getECSComponent(AIComponent.class).getHumanControlVars().justMoved = walking;
            setMoving(walking);
            isPlayerMoving = walking;
            return ProbeMovement.PathResult.WORKING;
        }
        return result == PathFindBehavior2.BehaviorResult.Failed
                ? ProbeMovement.PathResult.FAILED : ProbeMovement.PathResult.SUCCEEDED;
    }

    private void discardRootMotion() {
        if (hasAnimationPlayer()) getAnimationPlayer().resetDeferredMovementAccum();
    }

    String motionStatus() {
        PathFindBehavior2 path = getPathFindBehavior2();
        return "target=" + movement.targetX() + "," + movement.targetY() + "," + movement.targetZ()
                + " pos=" + getX() + "," + getY() + "," + getZ()
                + " remaining=" + movement.distance(getX(), getY(), getZ())
                + " moving=" + movement.active() + " path=" + pathResult + " result=" + moveResult
                + " pathSteps=" + movement.steps() + " hasPath=" + (getPath2() != null)
                + " nextSet=" + path.pathNextIsSet + " next=" + path.pathNextX + "," + path.pathNextY
                + " state=" + getCurrentStateName();
    }

    @Override public void preupdate() {
        if (attached && !failed && !retiring && ProbeRules.canSimulate(GameClient.client, GameServer.server)) {
            try { super.preupdate(); }
            catch (RuntimeException | LinkageError error) { freeze("preupdate " + error); }
        }
    }

    @Override public void postupdate() {
        if (attached && !failed && !retiring && ProbeRules.canSimulate(GameClient.client, GameServer.server)) {
            try { super.postupdate(); }
            catch (RuntimeException | LinkageError error) { freeze("postupdate " + error); }
        }
    }
}
