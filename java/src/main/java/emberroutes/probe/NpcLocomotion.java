package emberroutes.probe;

import java.util.List;
import zombie.ai.AIBrainPlayerControlVars;
import zombie.characters.IsoPlayer;
import zombie.characters.component.AIComponent;
import zombie.pathfind.Path;
import zombie.pathfind.PathFindBehavior2;
import emberroutes.probe.nav.EmberPathfinder;
import emberroutes.probe.nav.NavRaycast;
import emberroutes.probe.ProbeMovement.MoveStatus;
import emberroutes.probe.ProbeMovement.PathStatus;

/** Per-body native movement adapter, owned and stepped only by ProbeNpc.
 * No task authority, event loop, persistence or asset ownership lives here.
 * ProbeNpc keeps engine overrides/super calls and whole-body stop ordering. */
final class NpcLocomotion {
    private final ProbeNpc body;
    private final ProbeMovement movement = new ProbeMovement();
    private CompanionNavigation companionNavigation;
    private PathStatus pathResult = PathStatus.IDLE;
    private MoveStatus moveResult = MoveStatus.IDLE;
    private long nextProgressLog;
    /** Throttle for MOVE_NOROOT: at most one line per second while the body
     *  reports active movement but no root-motion source consumes it. */
    private long nextNoRootLog;
    private float moveStartX, moveStartY;
    // Path failures are not free: every failed or timed-out request re-runs the
    // engine pathfinder. Back off exponentially so a stuck carrier cannot spin.
    private static final long MOVE_BACKOFF_BASE_NANOS = 1_500_000_000L;
    private static final long MOVE_BACKOFF_MAX_NANOS = 8_000_000_000L;
    private int moveFailureCount;
    private long moveBlockedUntilNanos;
    private long doorWaitStartedNanos;
    private zombie.iso.IsoObject requestedFurniture, reachedFurniture;
    private double furniturePathLimit;
    private boolean furniturePathChecked;
    private boolean advancingPath;
    private float currentSpeedScale = 1.0f;
    // Target of the interrupted move, re-issued on resume. The native path is
    // gone with the chunk, so resuming means re-requesting, not un-freezing.
    private boolean resumeMove;
    private float resumeX, resumeY, resumeZ;

    NpcLocomotion(ProbeNpc body) { this.body = body; }

    boolean active() { return movement.active(); }
    boolean advancingPath() { return advancingPath; }
    float speedScale() { return currentSpeedScale; }
    void markFailed() { moveResult = MoveStatus.FAILED; }
    void tickFollow() {
        if (companionNavigation!=null) companionNavigation.tick(System.nanoTime());
    }

    String lastMoveResult() { return companionNavigation!=null ? companionNavigation.status() : moveResult.name(); }

    void pauseMovementClock(long now) {
        movement.pause(now);
        if (companionNavigation!=null) companionNavigation.pause(now);
    }

    void beginFollow(IsoPlayer leader,String id,String key,int rank) {
        requestedFurniture=null; reachedFurniture=null;
        closeFollow();
        companionNavigation=new CompanionNavigation(body,this,leader,id,key,rank);
    }

    CompanionNavigation companionNavigation() { return companionNavigation; }

    /** True once the pathfinder has produced a route or already moved along one;
     *  a pending search is not a stall and must not be cancelled by the probe. */
    boolean pathReady() {
        return body.getPath2()!=null || body.getPathFindBehavior2().pathNextIsSet;
    }

    /** At most three loaded tiles; this is a posture brake, not a path search. */
    boolean followPrecision() {
        if (nativeTraversal() || !body.getPathFindBehavior2().shouldBeMoving()) return true;
        PathFindBehavior2 path=body.getPathFindBehavior2();
        float dx=path.pathNextX-body.getX(),dy=path.pathNextY-body.getY();
        float length=(float)Math.hypot(dx,dy);
        if (!path.pathNextIsSet || length<0.001f) return true;
        dx/=length; dy/=length;
        int floor=(int)Math.floor(body.getZ()+0.001f);
        for (int i=0;i<3;i++) {
            var square=body.getCell().getGridSquare((int)Math.floor(body.getX()+dx*i*0.4f),
                    (int)Math.floor(body.getY()+dy*i*0.4f),floor);
            if (square==null || square.HasStairs()) return true;
        }
        return false;
    }

    /** Called only by this body's granted companion navigation or its close path. */
    void followPosture(boolean running,boolean sneaking) {
        AIComponent ai=body.getECSComponent(AIComponent.class);
        if (ai!=null) ai.getHumanControlVars().running=running;
        body.setRunning(running); body.setSprinting(false); body.setSneaking(sneaking);
    }

    /** Releases the shared squad trail and drops the session navigation. */
    private void closeFollow() {
        CompanionNavigation previous=companionNavigation;
        companionNavigation=null;
        if (previous!=null) {
            previous.close();
            followPosture(false,false);
        }
    }

    /** Same-session route update: never clear timed actions or exit furniture. */
    void retargetFollow(float x,float y,int z,long now) {
        body.getPathFindBehavior2().cancel();
        body.getPathFindBehavior2().pathNextIsSet=false;
        body.setPath2(null);
        movement.begin(x,y,z,now);
        moveStartX=body.getX(); moveStartY=body.getY(); nextProgressLog=now+1_000_000_000L;
        if (dispatchCustomRoute(x, y, z)) {
            moveResult = MoveStatus.MOVING; pathResult = PathStatus.FOUND;
        } else {
            moveResult = MoveStatus.BLOCKED; pathResult = PathStatus.NO_PATH;
        }
    }

    /** Locomotion-only halt while the follow session keeps its body grant. */
    void holdFollowMovement() {
        DoorwayArbiter.releaseByNpc(DoorwayArbiter.resolveNpcId(body));
        doorWaitStartedNanos = 0L;
        if (!movement.active() && body.getPath2()==null && !body.isMoving()) return;
        movement.cancel();
        body.getPathFindBehavior2().cancel(); body.getPathFindBehavior2().pathNextIsSet=false;
        body.setPath2(null); body.setVariable("bPathfind",false); body.setMoving(false);
        body.setPathPlayerMoving(false); body.playerMoveDir.set(0,0); body.setJustMoved(false);
        body.setRunning(false); body.setSprinting(false); body.discardRootMotion();
        currentSpeedScale = 1.0f;
        AIComponent ai=body.getECSComponent(AIComponent.class);
        if (ai!=null) {
            var vars=ai.getHumanControlVars(); vars.justMoved=false; vars.running=false;
            vars.strafeX=0; vars.strafeY=0;
        }
    }

    void moveTo(float x, float y, float z) {
        if (body.failed() || body.retiring() || !body.attached()) throw new IllegalStateException("carrier not active");
        if (body.suspended()) {
            pathResult = PathStatus.SUSPENDED; moveResult = MoveStatus.BLOCKED;
            return;
        }
        long now = System.nanoTime();
        if (now < moveBlockedUntilNanos) {
            pathResult = PathStatus.COOLDOWN; moveResult = MoveStatus.BLOCKED;
            ProbeRuntime.log("MOVE_BLOCKED " + motionStatus()
                    + " retryInMs=" + ((moveBlockedUntilNanos - now) / 1_000_000L));
            return;
        }
        body.stopProbe();
        requestedFurniture=null; reachedFurniture=null;
        moveStartX = body.getX(); moveStartY = body.getY();
        double distance=Math.hypot(Math.hypot(x-body.getX(),y-body.getY()),z-body.getZ());
        long timeout=(long)Math.min(180_000_000_000.0,10_000_000_000.0+distance*3_000_000_000.0);
        movement.begin(x,y,z,now,timeout);
        nextProgressLog = now + 1_000_000_000L;

        if (dispatchCustomRoute(x, y, z)) {
            pathResult = PathStatus.FOUND;
            moveResult = MoveStatus.MOVING;
            ProbeRuntime.log("MOVE_TARGET origin=" + body.getX() + "," + body.getY() + "," + body.getZ()
                    + " target=" + x + "," + y + "," + z + " distance=" + movement.distance(body.getX(), body.getY(), body.getZ()));
        } else {
            registerMoveFailure(now);
            pathResult = PathStatus.NO_PATH;
            moveResult = MoveStatus.BLOCKED;
            body.stopProbe();
            ProbeRuntime.log("MOVE_BLOCKED origin=" + body.getX() + "," + body.getY() + "," + body.getZ()
                    + " target=" + x + "," + y + "," + z + " (no path found or blocked)");
        }
    }

    private boolean dispatchCustomRoute(float x, float y, float z) {
        List<NavRaycast.Waypoint> waypoints = EmberPathfinder.findPath(
                body,
                (int) Math.floor(body.getX()), (int) Math.floor(body.getY()), (int) body.getZ(),
                (int) Math.floor(x), (int) Math.floor(y), (int) z,
                EmberPathfinder.DEFAULT_MAX_NODES
        );

        if (waypoints != null && !waypoints.isEmpty()) {
            Path nativePath = new Path();
            for (int i = 0; i < waypoints.size(); i++) {
                NavRaycast.Waypoint wp = waypoints.get(i);
                nativePath.addNode(wp.x, wp.y, wp.z);
            }
            var pathBehavior = body.getPathFindBehavior2();
            pathBehavior.cancel();
            pathBehavior.setData(x, y, z);
            pathBehavior.Succeeded(nativePath, body);
            return true;
        }
        return false;
    }

    /** Exponential path-request backoff: 1.5s, 3s, 6s, capped at 8s. */
    private void registerMoveFailure(long now) {
        moveFailureCount = Math.min(moveFailureCount + 1, 6);
        long backoff = MOVE_BACKOFF_BASE_NANOS << Math.min(moveFailureCount - 1, 3);
        moveBlockedUntilNanos = now + Math.min(backoff, MOVE_BACKOFF_MAX_NANOS);
        ProbeRuntime.log("MOVE_BACKOFF count=" + moveFailureCount
                + " waitMs=" + ((moveBlockedUntilNanos - now) / 1_000_000L));
    }

    String moveToCorpse(zombie.iso.objects.IsoDeadBody corpse) {
        if (body.failed() || body.retiring() || !body.attached() || corpse==null || corpse.getSquare()==null
                || corpse.getStaticMovingObjectIndex()<0 || body.isDraggingCorpse()) return "CORPSE_UNAVAILABLE";
        body.stopProbe();
        requestedFurniture=null; reachedFurniture=null;
        moveStartX=body.getX(); moveStartY=body.getY();
        var path=body.getPathFindBehavior2();
        path.pathToGrabCorpse(corpse);
        if (path.getIsCancelled() || path.isGoalNone()) return "CORPSE_NO_APPROACH";
        // Head/legs are sub-tile native goals, not the corpse square's centre.
        movement.beginNative(corpse.getX(),corpse.getY(),corpse.getZ(),System.nanoTime(),180_000_000_000L);
        moveResult = MoveStatus.MOVING; pathResult = PathStatus.REQUESTED;
        return "MOVE_REQUESTED_CORPSE";
    }

    String moveToFurniture(zombie.iso.IsoObject object,double maxPathLength,boolean sleep) {
        if (body.failed() || body.retiring() || !body.attached() || object==null || object.getSquare()==null
                || object.getObjectIndex()<0 || object.isFurnitureOccupied(body)) return "SEAT_UNAVAILABLE";
        body.stopProbe();
        requestedFurniture=object; reachedFurniture=null;
        furniturePathLimit=maxPathLength; furniturePathChecked=false;
        moveStartX=body.getX(); moveStartY=body.getY();
        double distance=Math.hypot(object.getSquare().getX()+0.5-body.getX(),object.getSquare().getY()+0.5-body.getY());
        long timeout=sleep ? 180_000_000_000L : (long)Math.min(180_000_000_000.0,35_000_000_000.0+distance*3_000_000_000.0);
        movement.beginNative(object.getSquare().getX()+0.5,object.getSquare().getY()+0.5,
                object.getSquare().getZ(),System.nanoTime(),timeout);
        moveResult = MoveStatus.MOVING; pathResult = PathStatus.REQUESTED;
        body.getPathFindBehavior2().pathNextIsSet=false;
        // Vanilla uses this planner. Keep the exact reserved sprite-grid part;
        // choosing another part would require a new resource reservation.
        body.getPathFindBehavior2().pathToSitOnFurniture(object,false);
        return "MOVE_REQUESTED_SEAT";
    }

    zombie.iso.IsoObject reachedFurniture() { return reachedFurniture; }

    String moveToBed(zombie.iso.IsoObject object,se.krka.kahlua.vm.KahluaTable locations) {
        if (body.failed() || body.retiring() || !body.attached() || object.getSquare()==null || object.getObjectIndex()<0
                || object.isFurnitureOccupied(body) || locations.len()!=12) return "BED_UNAVAILABLE";
        int bedZ=object.getSquare().getZ();
        float bedX=object.getSquare().getX(), bedY=object.getSquare().getY();
        for (int i=1;i<=12;i++) {
            if (!(locations.rawget(i) instanceof Number number) || !Double.isFinite(number.doubleValue()))
                return "BED_UNAVAILABLE";
            double value=number.doubleValue();
            if (i%3==0 && value!=bedZ) return "BED_UNAVAILABLE";
            if (i%3!=0 && Math.abs(value-(i%3==1 ? bedX : bedY))>3) return "BED_UNAVAILABLE";
        }
        body.stopProbe();
        requestedFurniture=null; reachedFurniture=null;
        moveStartX=body.getX(); moveStartY=body.getY();
        movement.beginNative(object.getSquare().getX()+0.5,object.getSquare().getY()+0.5,
                object.getSquare().getZ(),System.nanoTime(),180_000_000_000L);
        moveResult = MoveStatus.MOVING; pathResult = PathStatus.REQUESTED;
        body.getPathFindBehavior2().pathNextIsSet=false;
        body.getPathFindBehavior2().pathToNearestTable(locations);
        return "MOVE_REQUESTED_BED";
    }

    private void updateLocomotionSteering(PathFindBehavior2 path) {
        if (!path.pathNextIsSet || nativeTraversal()) {
            currentSpeedScale = 1.0f;
            body.playerMoveDir.set(body.getForwardDirectionX(), body.getForwardDirectionY());
            return;
        }

        var route = body.getPath2();
        float w0X = path.pathNextX;
        float w0Y = path.pathNextY;
        boolean hasW1 = false;
        float w1X = w0X;
        float w1Y = w0Y;

        if (route != null && !route.isEmpty()) {
            int nodeCount = route.size();
            for (int i = 0; i < nodeCount; i++) {
                var node = route.getNode(i);
                if (Math.abs(node.x - w0X) < 0.05f && Math.abs(node.y - w0Y) < 0.05f) {
                    if (i + 1 < nodeCount) {
                        var nextNode = route.getNode(i + 1);
                        hasW1 = true;
                        w1X = nextNode.x;
                        w1Y = nextNode.y;
                    }
                    break;
                }
            }
        }

        LocomotionSteering.Plan plan = LocomotionSteering.compute(
                body.getX(), body.getY(),
                body.getForwardDirectionX(), body.getForwardDirectionY(),
                w0X, w0Y,
                hasW1, w1X, w1Y,
                LocomotionSteering.DEFAULT_LOOKAHEAD,
                body.isAnimatingBackwards(),
                nativeTraversal()
        );

        currentSpeedScale = plan.speedScale;
        float dirLen = (float) Math.hypot(plan.dirX, plan.dirY);
        if (dirLen > 0.001f) {
            if (!body.isAnimatingBackwards() && !body.isStrafing() && !body.isAiming()) {
                body.setForwardDirection(plan.dirX, plan.dirY);
            }
            body.playerMoveDir.set(plan.dirX, plan.dirY);
        } else {
            body.playerMoveDir.set(body.getForwardDirectionX(), body.getForwardDirectionY());
        }
    }

    private ProbeMovement.PathResult advancePath() {
        PathFindBehavior2 path = body.getPathFindBehavior2();
        PathFindBehavior2.BehaviorResult result;
        advancingPath=true;
        try { result=path.update(); }
        finally { advancingPath=false; }
        DoorwayArbiter.checkAndReleaseCleared(DoorwayArbiter.resolveNpcId(body), body.getX(), body.getY());
        if (requestedFurniture!=null && result==PathFindBehavior2.BehaviorResult.Succeeded) {
            zombie.iso.IsoObject goal=path.getGoalSitOnFurnitureObject();
            if (goal!=requestedFurniture) return ProbeMovement.PathResult.FAILED;
            reachedFurniture=goal;
        }
        if (requestedFurniture!=null && !furniturePathChecked && body.getPath2()!=null && !body.getPath2().isEmpty()) {
            furniturePathChecked=true;
            if (furniturePathLimit>0 && body.getPath2().length()>furniturePathLimit) return ProbeMovement.PathResult.FAILED;
        }
        pathResult = switch (result) {
            case Working -> PathStatus.WORKING;
            case Failed -> PathStatus.FAILED;
            case Succeeded -> PathStatus.SUCCEEDED;
        };
        if (result == PathFindBehavior2.BehaviorResult.Working) {
            // Native update() owns facing, including its body.isAnimatingBackwards()
            // branch. Facing the waypoint again would turn BwdDrag into pushing.
            boolean walking = body.getPath2() != null && path.shouldBeMoving();
            body.getECSComponent(AIComponent.class).getHumanControlVars().justMoved = walking;
            body.setMoving(walking);
            body.setPathPlayerMoving(walking);
            if (walking) {
                if (path.pathNextIsSet && !nativeTraversal()) {
                    EnvironmentInteraction.Result env = EnvironmentInteraction.interactAhead(
                            body, path.pathNextX, path.pathNextY, nativeTraversal()
                    );
                    if (env == EnvironmentInteraction.Result.BLOCKED) {
                        path.cancel();
                        doorWaitStartedNanos = 0L;
                        currentSpeedScale = 1.0f;
                        body.playerMoveDir.set(0, 0);
                        return ProbeMovement.PathResult.FAILED;
                    }
                    if (env == EnvironmentInteraction.Result.WAIT_DOORWAY) {
                        long now = System.nanoTime();
                        if (doorWaitStartedNanos == 0L) {
                            doorWaitStartedNanos = now;
                        } else if (now - doorWaitStartedNanos > DoorwayArbiter.ROUTE_FAILURE_NANOS) {
                            doorWaitStartedNanos = 0L;
                            path.cancel();
                            currentSpeedScale = 1.0f;
                            body.playerMoveDir.set(0, 0);
                            return ProbeMovement.PathResult.FAILED;
                        }
                        currentSpeedScale = 0.0f;
                        body.playerMoveDir.set(0, 0);
                        movement.pause(now);
                        return ProbeMovement.PathResult.WORKING;
                    } else {
                        doorWaitStartedNanos = 0L;
                    }
                }
                updateLocomotionSteering(path);
            } else {
                currentSpeedScale = 1.0f;
                body.playerMoveDir.set(0, 0);
            }
            return ProbeMovement.PathResult.WORKING;
        }
        currentSpeedScale = 1.0f;
        doorWaitStartedNanos = 0L;
        return result == PathFindBehavior2.BehaviorResult.Failed
                ? ProbeMovement.PathResult.FAILED : ProbeMovement.PathResult.SUCCEEDED;
    }

    boolean nativeTraversal() {
        return body.isCurrentState(zombie.ai.states.ClimbOverFenceState.instance())
                || body.isCurrentState(zombie.ai.states.ClimbThroughWindowState.instance())
                || body.isCurrentState(zombie.ai.states.ClimbOverWallState.instance());
    }

    String motionStatus() {
        PathFindBehavior2 path = body.getPathFindBehavior2();
        return "target=" + movement.targetX() + "," + movement.targetY() + "," + movement.targetZ()
                + " pos=" + body.getX() + "," + body.getY() + "," + body.getZ()
                + " remaining=" + movement.distance(body.getX(), body.getY(), body.getZ())
                + " moving=" + movement.active() + " path=" + pathResult + " result=" + moveResult
                + " pathSteps=" + movement.steps() + " hasPath=" + (body.getPath2() != null)
                + " nextSet=" + path.pathNextIsSet + " next=" + path.pathNextX + "," + path.pathNextY
                + " state=" + body.getCurrentStateName();
    }

    void beginStop() {
        DoorwayArbiter.releaseByNpc(DoorwayArbiter.resolveNpcId(body));
        doorWaitStartedNanos = 0L;
        closeFollow();
    }

    void stop() {
        movement.cancel();
        moveResult = MoveStatus.STOPPED;
        body.getPathFindBehavior2().cancel();
        body.getPathFindBehavior2().pathNextIsSet = false;
        body.setPath2(null);
        body.setVariable("bPathfind", false);
        body.setMoving(false);
        body.setPathPlayerMoving(false);
        body.playerMoveDir.set(0, 0);
        body.setJustMoved(false);
        body.setRunning(false);
        body.setSprinting(false);
        body.discardRootMotion();
        currentSpeedScale = 1.0f;
        AIComponent ai = body.getECSComponent(AIComponent.class);
        if (ai != null) {
            AIBrainPlayerControlVars vars = ai.getHumanControlVars();
            vars.justMoved = false; vars.running = false;
            vars.strafeX = 0; vars.strafeY = 0;
        }
    }

    void captureResume() {
        if (movement.active()) {
            resumeMove = true;
            resumeX = (float)movement.targetX();
            resumeY = (float)movement.targetY();
            resumeZ = (float)movement.targetZ();
        }
    }

    void resume() {
        // Re-issue the interrupted move: the native path died with the chunk.
        if (resumeMove) {
            resumeMove = false;
            // Parking is not a path failure; never let its backoff block recovery.
            moveFailureCount = 0;
            moveBlockedUntilNanos = 0L;
            try { moveTo(resumeX, resumeY, resumeZ); }
            catch (RuntimeException | LinkageError error) {
                ProbeRuntime.log("CARRIER_RESUME_MOVE_FAILED " + error);
            }
        }
    }

    void logProgress() {
        if (movement.active() && System.nanoTime() >= nextProgressLog) {
            nextProgressLog = System.nanoTime() + 1_000_000_000L;
            ProbeRuntime.log("MOVE_PROGRESS " + motionStatus());
        }
    }

    void tick() {
        ProbeMovement.Outcome outcome = movement.tick(this::advancePath,
                body.getX(), body.getY(), body.getZ(), System.nanoTime());
        boolean consumedRootMotion=false;
        if (outcome==ProbeMovement.Outcome.MOVING && body.getPath2()!=null) {
            PathFindBehavior2 path=body.getPathFindBehavior2();
            if ((path.pathNextIsSet && (path.shouldBeMoving() || path.stopping)) || nativeTraversal()) {
                body.consumePathRootMotion();
                consumedRootMotion=true;
            }
        }
        // Active movement that consumes no root motion leaves the body in
        // place while every upper layer believes it is walking. Name the
        // exact missing condition once per second instead of staying silent.
        if (outcome==ProbeMovement.Outcome.MOVING && !consumedRootMotion) {
            long nowNoRoot=System.nanoTime();
            if (nowNoRoot>=nextNoRootLog) {
                nextNoRootLog=nowNoRoot+1_000_000_000L;
                Path stalled=body.getPath2();
                ProbeRuntime.log("MOVE_NOROOT reason="
                        + (stalled==null ? "NO_PATH"
                            : (!body.getPathFindBehavior2().pathNextIsSet ? "NEXT_UNSET" : "STATE_NOT_MOVING"))
                        + " pathNodes=" + (stalled==null ? -1 : stalled.size())
                        + " " + motionStatus());
            }
        }
        if (outcome != ProbeMovement.Outcome.IDLE && outcome != ProbeMovement.Outcome.MOVING) {
            // Capture the path before body.stopProbe() clears it: the terminal
            // line must show how far the finished path actually reached.
            Path ended=body.getPath2();
            int endedNodes=ended==null ? -1 : ended.size();
            String endedAt="none";
            if (endedNodes>0) {
                zombie.pathfind.PathNode node=ended.getNode(endedNodes-1);
                endedAt=node.x+","+node.y+","+node.z;
            }
            if (companionNavigation!=null) {
                // A completed segment hands off to the next one without
                // clearing velocity; only a failed segment is held.
                if (companionNavigation.ended(outcome,System.nanoTime())) holdFollowMovement();
            } else body.stopProbe();
            moveResult = MoveStatus.from(outcome);
            ProbeRuntime.log("MOVE_END outcome=" + outcome.name()
                    + " target=" + movement.targetX() + "," + movement.targetY() + "," + movement.targetZ()
                    + " pos=" + body.getX() + "," + body.getY() + "," + body.getZ()
                    + " remaining=" + movement.distance(body.getX(), body.getY(), body.getZ())
                    + " pathNodes=" + endedNodes + " pathEnd=" + endedAt
                    + " nextSet=" + body.getPathFindBehavior2().pathNextIsSet);
            if (outcome == ProbeMovement.Outcome.FAILED || outcome == ProbeMovement.Outcome.TIMEOUT) {
                registerMoveFailure(System.nanoTime());
            } else {
                moveFailureCount = 0;
                moveBlockedUntilNanos = 0L;
            }
            ProbeRuntime.log("MOVE_" + outcome.name() + " " + motionStatus()
                    + " displacement=" + Math.hypot(body.getX() - moveStartX, body.getY() - moveStartY));
        }
    }
}
