package emberroutes.probe;

import zombie.characters.IsoPlayer;
import zombie.iso.IsoGridSquare;
import zombie.pathfind.PolygonalMap2;

/** Navigation within an existing body grant. The NPC's native path/root-motion
 * pipeline remains the only displacement owner. No event handler or task runner.
 *
 * <p>Retargeting cancels the in-flight search (PathFindBehavior2.pathToLocationF
 * resets the request), so a segment is requested only when the previous one has
 * ended. Goals come from the leader's walked route, one shared trail per squad. */
final class CompanionNavigation {
    static final long THINK_NANOS = 100_000_000L;
    static final long LEADER_STILL_NANOS = 400_000_000L;
    static final float SLOT_BACK = 1.5f;
    static final float SLOT_SIDE = 0.9f;
    static final float COLUMN_STEP = 1.05f;
    static final float SEGMENT = 2.5f;
    static final float MAX_CROSS_FLOOR_RANGE_SQ = 256f;
    static final float LEADER_NEAR_SQ = 1.44f;
    static final float HOLD_ENTER_SQ = 0.3025f;
    static final float HOLD_EXIT_SQ = 0.9025f;
    /** Bounded grace before probing; elapsed time alone is not reachability evidence. */
    static final long SEARCH_GRACE_NANOS = 3_000_000_000L;
    static final long QUEUE_NANOS = 5_000_000_000L;

    private final ProbeNpc body;
    private final IsoPlayer leader;
    private final String npcId, key;
    private final int slot;
    private final LeaderTrail trail;
    private final FollowProgress progress = new FollowProgress();
    private final FollowLocomotion locomotion = new FollowLocomotion();
    private String status = "FOLLOW_ACTIVE";
    private boolean holding, terminal;
    private long nextThink, nextProbeAt, segmentAt, queuedAt, nextPosture;
    private int sideSign, yieldStage, segmentKind, leaderFloor;
    private float segmentX, segmentY;
    private boolean needsProbe;
    private float leaderX, leaderY;
    private long leaderSeenAt;
    private boolean leaderMoving = true;
    private long metricsAt;

    // Planning targets are field-scoped: a 10Hz planner must not allocate a
    // result object per follower per tick.
    private float plannedX, plannedY;

    CompanionNavigation(ProbeNpc body, IsoPlayer leader, String npcId, String key, int slot) {
        this.body = body; this.leader = leader; this.npcId = npcId; this.key = key; this.slot = slot;
        this.sideSign = slotSide(slot) < 0 ? -1 : 1;
        this.trail = SquadTrail.acquire(leader);
        this.metricsAt=System.nanoTime();
    }

    String status() { return status; }

    void pause(long now) {
        progress.pause(now); nextThink = 0; segmentAt = now;
        locomotion.pause(); nextPosture=0;
        metricsAt=0;
        if (queuedAt != 0) queuedAt = now;
        if (leaderSeenAt != 0) leaderSeenAt = now;
    }
    boolean yieldsTo(CompanionNavigation other) {
        return other != null && other.leader == leader && !other.terminal && other.slot < slot;
    }

    /** Releases the shared trail. Call exactly once when this session ends. */
    void close() { SquadTrail.release(leader, trail); }

    /** Normal segment end must not zero velocity: the next segment is requested
     * on the next update. Failures hold the body and start the bounded probe. */
    boolean ended(ProbeMovement.Outcome result, long now) {
        boolean success = result == ProbeMovement.Outcome.REACHED || result == ProbeMovement.Outcome.PATH_ENDED
                && FollowProgress.distance2(body.getX(),body.getY(),segmentX,segmentY)>=FollowProgress.PROBE_DISTANCE_SQ;
        progress.ended(success, now);
        if (success) {
            // A recovery step reaching its own endpoint does not prove the
            // original route is clear. Preserve the side/back probe stage.
            holding = false; needsProbe = false;
            if (segmentKind == 0) yieldStage = 0;
            status = "FOLLOW_ACTIVE";
            return false;
        }
        needsProbe = true;
        status = result == ProbeMovement.Outcome.TIMEOUT ? "FOLLOW_TIMEOUT" : "FOLLOW_PATH_FAILED";
        if (progress.blocked()) { status = "FOLLOW_PATH_BLOCKED"; terminal = true; }
        return true;
    }

    void tick(long now) {
        // Rechecked at execution, not just at the Lua start call. Freeze may
        // happen before another Lua tick; old grants must not continue moving.
        if (!ProbeRuntime.followAllowed(body, npcId, key)) { body.stopProbe(); return; }
        advance(now);
        if (!terminal && body.companionNavigation()==this && now>=nextPosture) {
            nextPosture=now+THINK_NANOS;
            boolean sameFloor=floorOf(body.getZ())==floorOf(leader.getZ())
                    && Math.abs(body.getZ()-leader.getZ())<=0.2f;
            boolean precision=!"FOLLOW_ACTIVE".equals(status) || segmentKind!=0 || !sameFloor
                    || !body.moving() || !body.pathReady() || body.followPrecision();
            float dx=leader.getX()-body.getX(),dy=leader.getY()-body.getY();
            float dirX=body.getPathFindBehavior2().pathNextIsSet
                    ? body.getPathFindBehavior2().pathNextX-body.getX() : body.getForwardDirectionX();
            float dirY=body.getPathFindBehavior2().pathNextIsSet
                    ? body.getPathFindBehavior2().pathNextY-body.getY() : body.getForwardDirectionY();
            boolean sneak=leader.isSneaking();
            body.followPosture(locomotion.running(dx*dx+dy*dy,leader.isRunning() || leader.isSprinting(),
                    sneak,precision,dirX,dirY,now),sneak);
        }
    }

    private void advance(long now) {
        if (metricsAt!=0) FollowMetrics.sample(now-metricsAt,status,body.moving() && !body.pathReady());
        metricsAt=now;
        if (terminal) return;
        if (leader.isDead() || leader.getCell() != body.getCell() || leader.getCurrentSquare() == null) {
            block("FOLLOW_LEADER_LOST"); return;
        }
        if (!body.getCharacterActions().isEmpty()) { block("FOLLOW_ACTION_BUSY"); return; }
        float lx = leader.getX(), ly = leader.getY(), lz = leader.getZ();
        float x = body.getX(), y = body.getY(), z = body.getZ();
        if (!Float.isFinite(lx) || !Float.isFinite(ly) || !Float.isFinite(lz)
                || !Float.isFinite(x) || !Float.isFinite(y) || !Float.isFinite(z)) {
            block("FOLLOW_INVALID_POSITION"); return;
        }
        float distance2 = FollowProgress.distance2(x, y, lx, ly) + (lz - z) * (lz - z);
        // Loaded same-floor catch-up remains bounded by short local segments.
        // Long cross-floor routing belongs to the separate stair policy.
        if (floorOf(z)!=floorOf(lz) && distance2 > MAX_CROSS_FLOOR_RANGE_SQ) {
            block("FOLLOW_LEADER_TOO_FAR"); return;
        }
        // One record per frame per squad: LeaderTrail.record drops duplicate
        // positions, so three followers calling it costs one comparison each.
        if (trail != null) trail.record(lx, ly, floorOf(lz));
        trackLeader(now, lx, ly, floorOf(lz));
        if (leader.getVehicle() != null) {
            holdOnce(); progress.waiting(now); status = "FOLLOW_WAIT_VEHICLE"; return;
        }
        if (now < nextThink) return;
        nextThink = now + THINK_NANOS;
        IsoGridSquare square = body.getCurrentSquare();
        if (body.followTraversal() || (body.moving() && square != null && square.HasStairs())) {
            status = "FOLLOW_TRAVERSAL"; return;
        }
        int floor = floorOf(lz);
        boolean sameFloor = floorOf(z) == floor && Math.abs(z - lz) <= 0.2f;
        float tx = lx, ty = ly;
        boolean resolved = false;
        if (sameFloor) {
            // While the leader walks, the route decides the slot; once they stop,
            // settle into the geometric slot instead of freezing on the route.
            resolved = leaderMoving
                    ? planSlot(floor) || planColumn(floor) || planDirect(floor)
                    : planSlotDirect(floor) || planDirect(floor);
            if (resolved) { tx = plannedX; ty = plannedY; }
        }
        if (sameFloor && (FollowProgress.distance2(x, y, tx, ty) <= (holding ? HOLD_EXIT_SQ : HOLD_ENTER_SQ)
                && !blocked(x,y,tx,ty,floor)
                || !resolved && !leaderMoving && FollowProgress.distance2(x,y,lx,ly)<=LEADER_NEAR_SQ)) {
            holdOnce(); progress.waiting(now); status = "FOLLOW_WAITING"; return;
        }
        holding = false;
        if (queuedAt != 0) {
            if (ProbeRuntime.squadAhead(body,tx-x,ty-y)) {
                if (now-queuedAt<QUEUE_NANOS) { status="FOLLOW_QUEUED"; progress.waiting(now); return; }
                queuedAt=0;
                probe(now,tx,ty,false);
                return;
            }
            queuedAt=0; progress.waiting(now);
        }
        if (body.moving()) {
            // Never interrupt an in-flight search or a running path. A pending
            // search has no route yet, so it is not evidence of being blocked;
            // only a search older than SEARCH_GRACE is treated as stuck.
            boolean searching = !body.pathReady() && now - segmentAt < SEARCH_GRACE_NANOS;
            if (!searching && progress.stalled(x,y,now)) { block("FOLLOW_STALLED"); return; }
            if (!searching && now >= nextProbeAt && progress.probeDue(x, y, now)) probe(now, tx, ty,true);
            return;
        }
        if (!progress.canRequest(now)) return;
        if (needsProbe) { probe(now,tx,ty,true); return; }
        if (sameFloor && !walkable(tx, ty, floor)) {
            progress.ended(false, now);
            if (progress.blocked()) block("FOLLOW_PATH_BLOCKED");
            return;
        }
        if (submitSegment(tx, ty, floor, now,0)) status = "FOLLOW_ACTIVE";
    }

    /** Formation slot from the walked route. */
    private boolean planSlot(int floor) {
        if (trail == null || !trail.sample(slotBack(slot))) return false;
        float dirX = trail.outDirX, dirY = trail.outDirY;
        if (dirX * dirX + dirY * dirY < 0.0001f) {
            dirX = leader.getForwardDirectionX(); dirY = leader.getForwardDirectionY();
            float length = (float)Math.sqrt(dirX * dirX + dirY * dirY);
            if (length < 0.001f) return false;
            dirX /= length; dirY /= length;
        }
        return slotAt(trail.outX, trail.outY, dirX, dirY, floor);
    }

    /** Same slot relative to a stationary leader: the route contribution decays
     * instead of leaving the follower on a stale point around the corner. */
    private boolean planSlotDirect(int floor) {
        float dirX = leader.getForwardDirectionX(), dirY = leader.getForwardDirectionY();
        float length = (float)Math.sqrt(dirX * dirX + dirY * dirY);
        if (length < 0.001f) return false;
        dirX/=length; dirY/=length;
        return accept(slotX(slot,leader.getX(),dirX,dirY),slotY(slot,leader.getY(),dirX,dirY),floor,slotBack(slot));
    }

    private boolean slotAt(float baseX, float baseY, float dirX, float dirY, int floor) {
        float side = slotSide(slot);
        float tx = baseX - dirY * side;
        float ty = baseY + dirX * side;
        return accept(tx, ty, floor, slotBack(slot));
    }

    /** Slot lattice: 0 centred, then pairs at the same distance alternating
     * left/right; further pairs step back one body. Rank 0..2 keep the original
     * three-person layout, and any rank stays inside the trail budget. */
    static float slotBack(int rank) {
        if (rank <= 0) return SLOT_BACK;
        return SLOT_BACK + ((rank + 1) / 2 - 1) * COLUMN_STEP;
    }

    static float slotSide(int rank) {
        if (rank <= 0) return 0;
        return (rank & 1) == 1 ? -SLOT_SIDE : SLOT_SIDE;
    }
    static float slotX(int rank,float leaderX,float forwardX,float forwardY) {
        return leaderX-forwardX*slotBack(rank)-forwardY*slotSide(rank);
    }
    static float slotY(int rank,float leaderY,float forwardX,float forwardY) {
        return leaderY-forwardY*slotBack(rank)+forwardX*slotSide(rank);
    }

    /** Narrow passage: stagger along the walked route, no lateral offset. */
    private boolean planColumn(int floor) {
        float back = SLOT_BACK + slot * COLUMN_STEP;
        if (trail == null || !trail.sample(back)) return false;
        return accept(trail.outX, trail.outY, floor, back);
    }

    private boolean planDirect(int floor) {
        float fx = leader.getForwardDirectionX(), fy = leader.getForwardDirectionY();
        float length = (float)Math.sqrt(fx * fx + fy * fy);
        if (length < 0.001f) return false;
        float back = SLOT_BACK + slot * COLUMN_STEP;
        float tx = leader.getX() - fx / length * back;
        float ty = leader.getY() - fy / length * back;
        return accept(tx, ty, floor, back);
    }

    /** Keep each segment short: a long straight target to a corner would cut it.
     *  When the slot is farther than one segment, aim at the point one segment
     *  ahead along the walked route instead (larger back distance). */
    private boolean accept(float tx, float ty, int floor, float back) {
        float x = body.getX(), y = body.getY();
        float distance = (float)Math.sqrt(FollowProgress.distance2(x, y, tx, ty));
        if (distance > SEGMENT && trail != null && trail.sample(back + distance - SEGMENT)) {
            tx = trail.outX; ty = trail.outY;
        }
        distance=(float)Math.sqrt(FollowProgress.distance2(x,y,tx,ty));
        if (distance>SEGMENT) {
            tx=x+(tx-x)*SEGMENT/distance; ty=y+(ty-y)*SEGMENT/distance;
        }
        if (!walkable(tx, ty, floor)) return false;
        if (blocked(x, y, tx, ty, floor)) return false;
        plannedX = tx; plannedY = ty;
        return true;
    }

    /** Bounded response to a blocked body: queue, side-step, back off, report. */
    private void probe(long now, float goalX, float goalY,boolean allowQueue) {
        nextProbeAt = now + FollowProgress.PROBE_NANOS;
        needsProbe=false;
        float x = body.getX(), y = body.getY();
        int floor = floorOf(body.getZ());
        body.holdFollowMovement();
        if (allowQueue && ProbeRuntime.squadAhead(body, goalX - x, goalY - y)) {
            if (queuedAt==0) queuedAt=now;
            status = "FOLLOW_QUEUED"; progress.waiting(now); return;
        }
        float dx = goalX - x, dy = goalY - y;
        float length = (float)Math.sqrt(dx * dx + dy * dy);
        if (length <= 0.001f) { block("FOLLOW_BLOCKED"); return; }
        float px = -dy / length, py = dx / length;
        if (yieldStage == 0) {
            yieldStage=1;
            if (trySide(x, y, px, py, sideSign, floor, now)) return;
            if (trySide(x, y, px, py, -sideSign, floor, now)) { sideSign = -sideSign; return; }
        }
        if (yieldStage <= 1) {
            yieldStage=2;
            if (tryBack(x,y,dx/length,dy/length,floor,now)) return;
        }
        block("FOLLOW_BLOCKED");
    }

    private boolean trySide(float x, float y, float px, float py, int sign, int floor, long now) {
        float tx = x + px * SLOT_SIDE * sign, ty = y + py * SLOT_SIDE * sign;
        if (!walkable(tx, ty, floor) || blocked(x, y, tx, ty, floor)) return false;
        if (!submitSegment(tx, ty, floor, now,1)) return false;
        status = "FOLLOW_YIELD_SIDE";
        return true;
    }

    private boolean tryBack(float x, float y, float forwardX, float forwardY, int floor, long now) {
        // Back off from this body's attempted direction. A point behind the
        // leader can still lie ahead of a lagging follower and repeat the block.
        float tx = x - forwardX * SLOT_SIDE, ty = y - forwardY * SLOT_SIDE;
        if (!walkable(tx, ty, floor) || blocked(x, y, tx, ty, floor)) return false;
        if (!submitSegment(tx, ty, floor, now,2)) return false;
        status = "FOLLOW_YIELD_BACK";
        return true;
    }

    /** Single navigation-request submission point. Physical displacement and
     * executor handoff remain owned by ProbeNpc's native root-motion pipeline. */
    private boolean submitSegment(float x, float y, int floor, long now,int kind) {
        float distance=(float)Math.sqrt(FollowProgress.distance2(body.getX(),body.getY(),x,y));
        // Same-floor endpoints are bounded; cross-floor routing belongs to the
        // engine. Endpoint span is not a promise about the engine path length.
        if (floor==floorOf(body.getZ()) && distance>SEGMENT) {
            x=body.getX()+(x-body.getX())*SEGMENT/distance;
            y=body.getY()+(y-body.getY())*SEGMENT/distance;
        }
        if (!walkable(x,y,floor)) {
            progress.ended(false,now); needsProbe=true;
            if (progress.blocked()) block("FOLLOW_PATH_BLOCKED");
            else status="FOLLOW_PATH_FAILED";
            return false;
        }
        body.retargetFollow(x, y, floor, now);
        FollowMetrics.submitted();
        segmentX=body.getX(); segmentY=body.getY(); segmentKind=kind;
        segmentAt = now;
        progress.requested(now);
        return true;
    }

    private void trackLeader(long now, float lx, float ly,int floor) {
        if (leaderSeenAt == 0 || floor!=leaderFloor || FollowProgress.distance2(lx, ly, leaderX, leaderY) > 0.01f) {
            leaderX = lx; leaderY = ly; leaderFloor=floor; leaderSeenAt = now; leaderMoving = true;
        } else if (now - leaderSeenAt > LEADER_STILL_NANOS) leaderMoving = false;
    }

    private void holdOnce() { if (!holding || body.moving()) body.holdFollowMovement(); holding = true; }

    private void block(String reason) { body.holdFollowMovement(); status = reason; terminal = true; }

    private boolean walkable(float x, float y, int floor) {
        IsoGridSquare square = body.getCell().getGridSquare((int)Math.floor(x), (int)Math.floor(y), floor);
        return square != null && square.TreatAsSolidFloor() && !square.isSolid() && !square.isSolidTrans();
    }

    private static boolean blocked(float x, float y, float tx, float ty, int floor) {
        return PolygonalMap2.instance.lineClearCollide(x, y, tx, ty, floor, null, false, true);
    }

    private static int floorOf(float z) { return (int)Math.floor(z + 0.001f); }

}
