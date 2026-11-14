package emberroutes.probe;

import zombie.UpdateSchedulerSimulationLevel;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.characters.SurvivorDesc;
import zombie.characters.component.AIComponent;
import zombie.iso.IsoCamera;
import zombie.iso.IsoCell;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.pathfind.PathFindBehavior2;
import emberroutes.probe.BodyBridgeContract.StopSignal;
import static emberroutes.probe.BodyBridgeContract.STOPPED;

/** Owned single-player carrier experiment. No upstream NPC implementation is embedded. */
public final class ProbeNpc extends IsoPlayer {
    private boolean attached;
    private boolean failed;
    // A carrier whose chunk is unloaded is not broken: it is parked until the
    // world comes back. Only a real contract violation sets `failed`.
    private boolean suspended;
    private boolean retiring;
    private String failure = "";
    private long updates;
    private final NpcLocomotion locomotion = new NpcLocomotion(this);
    private final NpcPosture posture = new NpcPosture(this);
    private boolean consumingPathRootMotion;

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
    /** Parked because its chunk is unloaded; the body record is still intact. */
    boolean suspended() { return suspended; }
    long updates() { return updates; }
    String failure() { return failure; }
    boolean retiring() { return retiring; }
    NpcLocomotion locomotion() { return locomotion; }
    // IsoPlayer owns this protected input flag; only the owned movement adapter writes it.
    void setPathPlayerMoving(boolean moving) { isPlayerMoving = moving; }
    NpcPosture posture() { return posture; }
    int stopMask() {
        return (locomotion.companionNavigation()!=null ? StopSignal.FOLLOW.mask : STOPPED)
            | (locomotion.active() ? StopSignal.MOVEMENT.mask : STOPPED)
            | (isMoving() ? StopSignal.MOVING_FLAG.mask : STOPPED)
            | (!getCharacterActions().isEmpty() ? StopSignal.TIMED_ACTION.mask : STOPPED)
            | (getPath2() != null ? StopSignal.PATH.mask : STOPPED)
            | (!getPathFindBehavior2().isGoalNone() && !getPathFindBehavior2().getIsCancelled() ? StopSignal.PATH_GOAL.mask : STOPPED)
            | (getPathFindBehavior2().pathNextIsSet ? StopSignal.PATH_NEXT.mask : STOPPED)
            | (isAsleep() ? StopSignal.ASLEEP.mask : STOPPED)
            | (isResting() ? StopSignal.RESTING.mask : STOPPED)
            | (getBed()!=null ? StopSignal.BED.mask : STOPPED)
            | (isCurrentState(zombie.ai.states.FitnessState.instance()) || getFitness().getCurrentExe()!=null ? StopSignal.FITNESS.mask : STOPPED)
            | (isCurrentState(zombie.ai.states.PlayerEmoteState.instance()) ? StopSignal.EMOTE.mask : STOPPED)
            | (posture.blocksStop() ? StopSignal.POSTURE.mask : STOPPED)
            | (isDraggingCorpse() || isPerformingGrappleAnimation()
                || isCurrentState(zombie.ai.states.PlayerDraggingCorpse.instance()) ? StopSignal.CORPSE.mask : STOPPED);
    }
    void beginRetirement() {
        retiring = true;
        stopProbe();
        setGhostMode(true);
        setNoDamage(true);
        setInvisible(true);
        setCollidable(false);
        setDoRender(false);
    }

    void stopProbe() {
        locomotion.beginStop();
        posture.requestExit();
        StopAllActionQueue();
        setHeadLookAroundDirection(0,0); setHeadLookAround(false);
        // Requests only: stopMask keeps authority until the native state exits.
        if (isCurrentState(zombie.ai.states.FitnessState.instance()) || getFitness().getCurrentExe()!=null) {
            setVariable("ExerciseStarted",false); setVariable("ExerciseEnded",true);
            // The native exercise Out animation publishes FitnessFinished at
            // its end. stopMask retains authority while FitnessState exits.
            getFitness().setCurrentExercise(null);
        }
        if (isCurrentState(zombie.ai.states.PlayerEmoteState.instance())) {
            setVariable("EmotePlaying",false); clearVariable("emote");
        }
        posture.stop();
        locomotion.stop();
    }

    void freeze(String reason) {
        if (failed) return;
        failed = true;
        failure = reason;
        try { stopProbe(); }
        catch (RuntimeException | LinkageError error) {
            failure += "; stop failed: " + error;
        }
        locomotion.markFailed();
        ProbeRuntime.log("CARRIER_STOPPED " + failure + "; use remove");
    }

    /** Park the carrier until its chunk is loaded again. Not a failure. */
    private void suspendCarrier(String reason) {
        if (suspended) return;
        suspended = true;
        locomotion.captureResume();
        try { stopProbe(); }
        catch (RuntimeException | LinkageError error) {
            ProbeRuntime.log("CARRIER_SUSPEND_STOP_FAILED " + reason + ": " + error);
        }
        // stopProbe keeps its normal STOPPED result; parking is reported
        // separately through suspended(), not as a new motion result.
        ProbeRuntime.log("CARRIER_SUSPENDED " + reason + "; resumes when the world is available");
    }

    @Override public void update() {
        if (!attached || failed || retiring) return;
        if (suspended) {
            if (getCurrentSquare() == null) return;
            suspended = false;
            locomotion.resume();
            ProbeRuntime.log("CARRIER_RESUMED " + locomotion.motionStatus());
        }
        if (!ProbeRules.canSimulate(GameClient.client, GameServer.server)) {
            freeze("DRIVER_UNAVAILABLE multiplayer simulation not implemented");
            return;
        }
        if (isDead()) {
            freeze("CARRIER_DEAD");
            return;
        }
        // Unloaded chunk is a temporary condition, never a permanent failure.
        // The carrier stays attached and resumes when the square reappears.
        if (getCurrentSquare() == null) {
            suspendCarrier("WORLD_UNLOADED");
            return;
        }
        // IsoPlayer.updateInternal2 temporarily assigns both globals even for NPCs.
        // Restore in finally; no player slots are written or registered.
        IsoPlayer playerBefore = IsoPlayer.getInstance();
        IsoGameCharacter cameraBefore = IsoCamera.getCameraCharacter();
        try {
            AIComponent ai = getECSComponent(AIComponent.class);
            if (ai == null) throw new IllegalStateException("AIComponent disappeared");
            ai.getHumanControlVars().justMoved = locomotion.active() && getPath2() != null
                    && getPathFindBehavior2().shouldBeMoving();
            super.update();
            posture.tick();
            updates++;
            locomotion.logProgress();
        } catch (RuntimeException | LinkageError error) {
            freeze(error.toString());
        } finally {
            IsoPlayer.setInstance(playerBefore);
            if (cameraBefore == null) IsoCamera.clearCameraCharacter();
            else IsoCamera.setCameraCharacter(cameraBefore);
        }
    }

    /** PathFindBehavior2 still owns route progress, obstacle interaction and
     * facing. Only the native character root-motion consumer moves the body. */
    @Override protected void doDeferredMovement() {
        boolean nativeFurnitureMotion=false;
        try {
            if (!attached || failed || retiring || !ProbeRules.canSimulate(GameClient.client, GameServer.server)) return;
            if (posture.hasOwnedMotion()) return; // the captured seat anchor owns the sleep clip's displacement
            locomotion.tickFollow();
            // Furniture transitions use authored root motion after the native
            // approach has ended. Discarding it leaves the model beside the
            // chair. Never run this alongside the path follower.
            nativeFurnitureMotion=!locomotion.active() && posture.nativeRootMotion();
            if (nativeFurnitureMotion) {
                super.doDeferredMovement();
                return;
            }
            locomotion.tick();
        } finally {
            // Also discard pending/idle/stopped frames and any unconsumed
            // remainder; no displacement can leak into the next command.
            if (!nativeFurnitureMotion) discardRootMotion();
        }
    }

    /** Suppress only the path follower's synchronous direct displacement.
     * Native animation/physics calls outside that scope retain their behavior. */
    @Override public void moveUnmodded(float x,float y) {
        if (!locomotion.advancingPath()) super.moveUnmodded(x,y);
    }

    void consumePathRootMotion() {
        var route=getPath2();
        // The installed native consumer returns early when path2 is present:
        // it assumes the path follower already submitted the displacement.
        setPath2(null);
        consumingPathRootMotion=true;
        try { super.doDeferredMovement(); }
        finally {
            consumingPathRootMotion=false;
            if (locomotion.active() && !getPathFindBehavior2().getIsCancelled() && getPath2()==null)
                setPath2(route);
        }
    }

    @Override protected zombie.iso.Vector2 getDeferredMovement(zombie.iso.Vector2 result,boolean reset) {
        super.getDeferredMovement(result,reset);
        if (consumingPathRootMotion && !locomotion.nativeTraversal()) {
            PathFindBehavior2 path=getPathFindBehavior2();
            if (path.pathNextIsSet) {
                float scale=ProbeMovement.rootMotionScale(result.x,result.y,
                        path.pathNextX-getX(),path.pathNextY-getY());
                scale *= locomotion.speedScale();
                if (scale<=0.001f) result.set(0,0);
                else result.scale(scale);
            }
        }
        return result;
    }

    void discardRootMotion() {
        if (hasAnimationPlayer()) getAnimationPlayer().resetDeferredMovementAccum();
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
