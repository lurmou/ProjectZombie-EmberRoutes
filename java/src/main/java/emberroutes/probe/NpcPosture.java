package emberroutes.probe;

import zombie.ai.sadisticAIDirector.SleepingEvent;
import emberroutes.probe.BodyBridgeContract.ReposeKind;
import emberroutes.probe.BodyBridgeContract.FurniturePhase;
import emberroutes.probe.BodyBridgeContract.StopSignal;
import static emberroutes.probe.BodyBridgeContract.STOPPED;

/** Per-body posture adapter. Owns transient anchors and physical exit evidence,
 * never task authority, asset claims or a second movement/scheduling loop.
 * Entry and exit run inside ProbeNpc's existing engine and stop lifecycle. */
final class NpcPosture {
    private final ProbeNpc body;
    private boolean bedExitRequested;
    private BedPoseMotion bedMotion;
    private boolean floorPose;
    private long floorSeatRequest;
    private float bedEntryDirX,bedEntryDirY,bedLieDirX,bedLieDirY;
    private long bedPoseObserveAt;
    private boolean bedPoseOutsideLogged;
    private final FurnitureExitState furnitureExit=new FurnitureExitState();
    private zombie.iso.IsoObject poseFurniture;
    private final java.util.ArrayList<zombie.iso.IsoGridSquare> poseTiles=new java.util.ArrayList<>();
    private float approachX,approachY;
    private int approachZ;
    private long nextExitCheck,nextExitLog;
    private static final java.util.List<String> SLEEP_QUALITIES=java.util.List.of(
            "floor","goodBed","averageBed","badBed","goodBedPillow","averageBedPillow","badBedPillow");
    private static final zombie.iso.IsoDirections[] EXIT_DIRECTIONS={
            zombie.iso.IsoDirections.N,zombie.iso.IsoDirections.S,zombie.iso.IsoDirections.E,zombie.iso.IsoDirections.W};

    NpcPosture(ProbeNpc body) { this.body = body; }

    boolean furniturePoseOwned() { return furnitureExit.active(); }
    boolean hasOwnedMotion() { return bedMotion!=null; }
    void requestExit() { furnitureExit.request(); }
    boolean blocksStop() {
        return furnitureExit.exiting() || body.isSittingOnFurniture() || body.isSitOnGround() || body.isOnBed()
                || body.isCurrentState(zombie.ai.states.PlayerOnBedState.instance()) || body.getSitOnFurnitureObject()!=null
                || body.isCurrentState(zombie.ai.states.PlayerGetUpState.instance());
    }

    boolean nativeRootMotion() {
        // Keep short-circuit order: furnitureRootTrack also observes an exit request.
        return body.isDraggingCorpse() || body.isPerformingGrappleAnimation()
                || body.isCurrentState(zombie.ai.states.PlayerDraggingCorpse.instance())
                || body.isSitOnGround() || body.isCurrentState(zombie.ai.states.PlayerGetUpState.instance())
                || (furnitureExit.active() && (furnitureNativePose() || furnitureRootTrack()))
                || body.getSitOnFurnitureObject()!=null && furnitureNativePose();
    }

    void stop() {
        if (bedMotion==null && (body.isSittingOnFurniture() || body.isSitOnGround())) body.setVariable("forceGetUp",true);
        else if (!body.isOnBed() && !body.isCurrentState(zombie.ai.states.PlayerOnBedState.instance())
                && !body.isCurrentState(zombie.ai.states.PlayerGetUpState.instance()) && body.getSitOnFurnitureObject()!=null) {
            body.getSitOnFurnitureObject().setSatChair(false); body.setSitOnFurnitureObject(null);
        }
        endRepose();
    }

    // Called only for the current STOPPING ticket after an unchanged posture
    // mask; retries vanilla get-up without clearing animation or claiming exit.
    boolean retryStandExit() {
        boolean bed=bedMotion!=null || bedExitRequested || body.isOnBed()
                || body.isCurrentState(zombie.ai.states.PlayerOnBedState.instance());
        boolean gettingUp=body.isCurrentState(zombie.ai.states.PlayerGetUpState.instance());
        boolean corpse=body.isDraggingCorpse() || body.isPerformingGrappleAnimation()
                || body.isCurrentState(zombie.ai.states.PlayerDraggingCorpse.instance());
        boolean seated=body.isSittingOnFurniture() && body.getVariableBoolean("SitOnFurnitureStarted")
                && body.isCurrentState(zombie.ai.states.PlayerSitOnFurnitureState.instance());
        boolean floor=body.isSitOnGround() && body.getVariableBoolean("SitGroundStarted");
        if (!StandExitPolicy.allows(bed,gettingUp,corpse,!body.getCharacterActions().isEmpty(),
                body.getVariableBoolean("forceGetUp"),seated || floor)) return false;
        body.setVariable("forceGetUp",true);
        return true;
    }

    void tick() {
        advanceOwnedBedPose();
        if (bedPoseObserveAt!=0 && System.nanoTime()>=bedPoseObserveAt) {
            bedPoseObserveAt=0;
            if ((bedMotion!=null || body.isOnBed()) && body.isAsleep()) logBedPose("SLEEP_EFFECT_SETTLED",body.getSitOnFurnitureObject());
        }
        advanceBedExit();
        settleFurnitureExit();
    }

    boolean applyFurniturePhase(FurniturePhase phase,zombie.iso.IsoObject object) {
        if (phase==null) return false;
        return switch (phase) {
            case FLOOR -> object==null && beginOwnedFloorPose();
            case PREPARE -> prepareFurniturePose(object);
            case STAND_TARGET -> captureFurnitureStand(object);
            case ALIGN_BED -> alignBedPose(object);
            case LIE -> beginOwnedBedPose(object);
        };
    }

    boolean beginRepose(ReposeKind kind) {
        return beginRepose(kind,null,"floor");
    }
    boolean beginRepose(ReposeKind kind,zombie.iso.IsoObject furniture,String quality) {
        boolean onSleepBed=kind==ReposeKind.SLEEP && (bedMotion!=null || seatedSleepReady())
                && body.getSitOnFurnitureObject()==furniture && bedPoseReady("Asleep");
        if (body.failed() || body.retiring() || !body.attached() || body.isDead() || (body.stopMask() & ~(onSleepBed ? StopSignal.POSTURE.mask : STOPPED))!=STOPPED
                || body.getVehicle()!=null || body.isSittingOnFurniture() && !onSleepBed) return false;
        if (furniture!=null && (furniture.getSquare()==null || furniture.getObjectIndex()<0
                || furniture.isFurnitureOccupied(body) || furniture.getSquare().getZ()!=(int)body.getZ()
                || (!onSleepBed && Math.abs(furniture.getSquare().getX()-(int)Math.floor(body.getX()))
                    +Math.abs(furniture.getSquare().getY()-(int)Math.floor(body.getY()))>1))) return false;
        // Same native flags/bed reference as vanilla; never integrate Stats here.
        if (kind==ReposeKind.REST) {
            body.setBed(furniture); body.setIsResting(true); return true;
        }
        if (kind!=ReposeKind.SLEEP) return false;
        if (quality==null || !SLEEP_QUALITIES.contains(quality)) return false;
        if (onSleepBed) logBedPose("LYING_BEFORE_SLEEP",furniture);
        body.setBed(furniture); body.setBedType(quality); body.setAsleepTime(0.0f);
        body.setForceWakeUpTime(-1.0f); body.setAsleep(true);
        SleepingEvent.instance.setPlayerFallAsleep(body, 8);
        if (onSleepBed) {
            logBedPose("SLEEP_EFFECT_STARTED",furniture);
            bedPoseObserveAt=System.nanoTime()+1_000_000_000L;
        }
        return body.isAsleep();
    }
    boolean endRepose() {
        // SleepingEvent's player UI/speed/save branch requires isLocalPlayer(),
        // which this carrier always rejects. Preserve native waking effects.
        if (body.isAsleep()) SleepingEvent.instance.wakeUp(body);
        body.setIsResting(false); body.setBed(null);
        if (bedMotion!=null) {
            if (!floorPose) furnitureExit.request();
            bedMotion.exit(System.nanoTime());
            body.clearVariable("forceGetUp");
            advanceOwnedBedPose();
            return false;
        }
        if (furnitureExit.active() && !body.isSittingOnFurniture()) furnitureExit.request();
        if (body.isOnBed() || body.isCurrentState(zombie.ai.states.PlayerOnBedState.instance())) bedExitRequested=true;
        advanceBedExit();
        return !body.isAsleep() && !body.isResting() && body.getBed()==null && !bedExitRequested && !furnitureExit.exiting();
    }
    boolean bedPoseReady(String pose) {
        if ("Asleep".equals(pose) && seatedSleepReady()) return true;
        if (bedMotion!=null) {
            return "Asleep".equals(pose) && bedMotion.phase==BedPoseMotion.Phase.LYING
                    && (floorPose ? body.isSitOnGround() : body.isSittingOnFurniture() && body.getSitOnFurnitureObject()==poseFurniture)
                    && Math.hypot(body.getX()-bedMotion.x(System.nanoTime()),body.getY()-bedMotion.y(System.nanoTime()))<0.03
                    && nativePoseNodeReady(floorPose ? "ERFloorLyingIdle" : "ERBedLyingIdle");
        }
        if ("Asleep".equals(pose) && !bedAnchorInside()) return false;
        if (!body.isCurrentState(zombie.ai.states.PlayerOnBedState.instance()) || !body.getVariableBoolean("OnBedStarted")
                || (body.stopMask() & ~StopSignal.POSTURE.mask)!=STOPPED || !("Awake".equals(pose) || "Asleep".equals(pose))
                || body.getAdvancedAnimator()==null) return false;
        var layer=body.getAdvancedAnimator().getRootLayer();
        if (layer==null) return false;
        for (var node:layer.getLiveAnimNodes()) {
            if (node.isActive() && ("OnBed"+pose).equals(node.getName()) && !node.isTransitioningIn()
                    && !node.isBlendingIn() && node.getWeight()>=0.99f) return true;
        }
        return false;
    }
    private boolean seatedSleepReady() {
        var object=body.getSitOnFurnitureObject();
        if (bedMotion!=null || object==null || object!=poseFurniture || !furnitureExit.active()
                || furnitureExit.exiting() || object.getObjectIndex()<0 || !body.isSittingOnFurniture()
                || !body.getVariableBoolean("SitOnFurnitureStarted")
                || !body.isCurrentState(zombie.ai.states.PlayerSitOnFurnitureState.instance())
                || object.getProperties().has(zombie.iso.SpriteDetails.IsoFlagType.bed)) return false;
        var sprite=object.getSprite(); var grid=sprite==null ? null : sprite.getSpriteGrid();
        // A single chair has no bed-length axis. Preserve vanilla sitting,
        // rather than retrying a lying adapter that requires connected parts.
        return (grid==null || grid.getSpriteCount()==1) && nativePoseNodeReady("SitOnFurnitureIdle");
    }
    private boolean nativePoseNodeReady(String name) {
        if (body.getAdvancedAnimator()==null || body.getAdvancedAnimator().getRootLayer()==null) return false;
        if (poseLayerReady(body.getAdvancedAnimator().getRootLayer(),name)) return true;
        for (int i=0;i<Math.min(16,body.getAdvancedAnimator().getSubLayerCount());i++) {
            if (poseLayerReady(body.getAdvancedAnimator().getSubLayerAt(i),name)) return true;
        }
        return false;
    }
    private boolean poseLayerReady(zombie.core.skinnedmodel.advancedanimation.AnimLayer layer,String name) {
        for (var node:layer.getLiveAnimNodes()) {
            boolean match=name.endsWith("*") ? node.getName()!=null && node.getName().startsWith(name.substring(0,name.length()-1)) : name.equals(node.getName());
            if (node.isActive() && match && !node.isTransitioningIn()
                    && !node.isBlendingIn() && node.getWeight()>=0.99f) return true;
        }
        return false;
    }
    private boolean bedClipFinished(String name) {
        if (body.getAdvancedAnimator()==null) return false;
        for (int i=-1;i<Math.min(16,body.getAdvancedAnimator().getSubLayerCount());i++) {
            var layer=i<0 ? body.getAdvancedAnimator().getRootLayer() : body.getAdvancedAnimator().getSubLayerAt(i);
            if (layer==null) continue;
            for (var node:layer.getLiveAnimNodes()) if (name.equals(node.getName())) {
                for (int k=0;k<Math.min(4,node.getPlayingTrackCount());k++) {
                    var track=node.getPlayingTrackAt(k);
                    if (track.isFinished() || track.getCurrentTimeFraction()>=0.99f) return true;
                }
            }
        }
        return false;
    }
    private boolean beginOwnedBedPose(zombie.iso.IsoObject object) {
        if (bedMotion!=null || object!=poseFurniture || !furnitureExit.active() || furnitureExit.exiting()
                || body.locomotion().active() || !body.getCharacterActions().isEmpty() || !body.isSittingOnFurniture()
                || body.getSitOnFurnitureObject()!=object || !body.getVariableBoolean("SitOnFurnitureStarted")
                || !body.isCurrentState(zombie.ai.states.PlayerSitOnFurnitureState.instance())) return false;
        var sprite=object.getSprite(); var grid=sprite==null ? null : sprite.getSpriteGrid();
        if (seatedSleepReady()) return true;
        if (grid==null) return false;
        String facing=object.getProperties().get("Facing");
        int gx=grid.getSpriteGridPosX(sprite),gy=grid.getSpriteGridPosY(sprite);
        String lie=null;
        // Connected-part direction is local layout information for the small
        // seating offset below. It is not a stable head direction: choosing
        // the other half of the same bed reverses this vector.
        for (var square:poseTiles) {
            if (("E".equals(facing) || "W".equals(facing)) && square.getY()==object.getSquare().getY()) {
                if (square.getX()==object.getSquare().getX()+1) lie="E";
                else if (square.getX()==object.getSquare().getX()-1) lie="W";
            } else if (("N".equals(facing) || "S".equals(facing)) && square.getX()==object.getSquare().getX()) {
                if (square.getY()==object.getSquare().getY()+1) lie="S";
                else if (square.getY()==object.getSquare().getY()-1) lie="N";
            }
        }
        if (lie==null) {
            if ("E".equals(facing) || "W".equals(facing)) lie=gy==0 ? "S" : "N";
            else if ("N".equals(facing) || "S".equals(facing)) lie=gx==0 ? "E" : "W";
            else return false;
        }
        float dx=0,dy=0;
        boolean bed=object.getProperties().has(zombie.iso.SpriteDetails.IsoFlagType.bed)
                && (object.getTextureName()==null || !object.getTextureName().startsWith("furniture_seating_"));
        if (bed) {
            int minX=Integer.MAX_VALUE,minY=Integer.MAX_VALUE,maxX=Integer.MIN_VALUE,maxY=Integer.MIN_VALUE;
            for (var square:poseTiles) {
                minX=Math.min(minX,square.getX()); maxX=Math.max(maxX,square.getX());
                minY=Math.min(minY,square.getY()); maxY=Math.max(maxY,square.getY());
            }
            float[] offset=BedPoseMotion.bedOffset(body.getX(),body.getY(),minX,minY,maxX,maxY,facing);
            if (offset==null) return false;
            dx=offset[0]; dy=offset[1];
        } else if (object.getTextureName()!=null && object.getTextureName().startsWith("furniture_bedding_")
                && body.getSitOnFurnitureDirection()==zombie.iso.IsoDirections.N && gy==0
                && ("E".equals(lie) || "W".equals(lie))) { dx=0.2f; dy="E".equals(lie) ? 0.4f : 0.3f; }
        var anchor=body.getCell().getGridSquare((int)Math.floor(body.getX()),(int)Math.floor(body.getY()),(int)body.getZ());
        var surface=body.getCell().getGridSquare((int)Math.floor(body.getX()+dx),(int)Math.floor(body.getY()+dy),(int)body.getZ());
        if (!sameFurnitureRoom(anchor,object.getSquare()) || !sameFurnitureRoom(surface,object.getSquare())) return false;
        var previous=anchor;
        for (int i=1;i<=16;i++) {
            var step=body.getCell().getGridSquare((int)Math.floor(body.getX()+dx*i/16f),(int)Math.floor(body.getY()+dy*i/16f),(int)body.getZ());
            if (step==null || step!=anchor && !poseTiles.contains(step)
                    || step!=previous && (previous.isWindowTo(step) || previous.isWallTo(step) || previous.isDoorTo(step))) return false;
            previous=step;
        }
        bedEntryDirX=body.getForwardDirectionX(); bedEntryDirY=body.getForwardDirectionY();
        // Bed Facing identifies its head; NPCFW's bedFootFacing is explicitly
        // its opposite. Bob_Asleep's observed head follows the model direction.
        // Keep this independent of the selected seating part and its offset.
        // A couch's Facing describes its front, not a bed head. Preserve its
        // connected-part layout direction rather than rotating a working couch.
        var vector=zombie.iso.IsoDirections.fromString(bed ? facing : lie).ToVector();
        bedLieDirX=vector.x; bedLieDirY=vector.y;
        body.clearVariable("forceGetUp");
        floorPose=false; bedMotion=new BedPoseMotion(body.getX(),body.getY(),body.getZ(),dx,dy,System.nanoTime());
        body.setVariable("ERBedPose","Awake");
        logBedPose("SEATED_ANCHOR_CAPTURED",object);
        return true;
    }
    boolean floorSleepSafe(int x,int y,int z) {
        var square=body.getCell().getGridSquare(x,y,z);
        if (z!=(int)body.getZ() || square==null || !square.TreatAsSolidFloor() || square.isSolid() || square.isSolidTrans()
                || square.HasStairs() || square.isOutside() || square.getFire()!=null || square.getDeadBody()!=null
                || !body.canStandAt(x+0.5f,y+0.5f,z)) return false;
        var objects=square.getObjects();
        if (objects.size()>64 || square.getMovingObjects().size()>64) return false;
        for (int i=0;i<objects.size();i++) { var obj=objects.get(i); if (obj instanceof zombie.iso.objects.IsoDoor || obj instanceof zombie.iso.objects.IsoWindow
                || obj.getProperties().has(zombie.iso.SpriteDetails.IsoFlagType.bed)
                || zombie.seating.SeatingManager.getInstance().getTilePositionCount(obj)>0) return false; }
        for (int i=0;i<square.getMovingObjects().size();i++) if (square.getMovingObjects().get(i)!=body) return false;
        return true;
    }
    private boolean beginOwnedFloorPose() {
        if (bedMotion!=null) return floorPose;
        if (!floorSleepSafe((int)Math.floor(body.getX()),(int)Math.floor(body.getY()),(int)body.getZ())
                || body.locomotion().active() || !body.getCharacterActions().isEmpty() || furnitureExit.active() || body.isSittingOnFurniture()) return false;
        long now=System.nanoTime();
        if (!body.isSitOnGround()) {
            if (body.stopMask()!=STOPPED) return false;
            if (now-floorSeatRequest>=500_000_000L) {
                body.clearVariable("forceGetUp"); body.reportEvent("EventSitOnGround"); floorSeatRequest=now;
            }
            return false;
        }
        if (!body.getVariableBoolean("SitGroundStarted") || !nativePoseNodeReady("sit_loop*")) return false;
        floorPose=true;
        bedEntryDirX=bedLieDirX=body.getForwardDirectionX(); bedEntryDirY=bedLieDirY=body.getForwardDirectionY();
        bedMotion=new BedPoseMotion(body.getX(),body.getY(),body.getZ(),0,0,now);
        body.clearVariable("forceGetUp"); body.setVariable("ERFloorPose","Awake");
        return true;
    }
    private void placeOwnedBedPose(float x,float y,float z) {
        body.setX(x); body.setY(y); body.setZ(z); body.setNextX(x); body.setNextY(y); body.setLastX(x); body.setLastY(y);
        body.setCurrentSquareFromPosition(); body.setMovingSquareNow();
    }
    private void advanceOwnedBedPose() {
        if (bedMotion==null) return;
        boolean seated=floorPose ? body.isSitOnGround() && body.isCurrentState(zombie.ai.states.PlayerSitOnGroundState.instance())
                : body.isSittingOnFurniture() && body.isCurrentState(zombie.ai.states.PlayerSitOnFurnitureState.instance());
        String variable=floorPose ? "ERFloorPose" : "ERBedPose";
        String prefix=floorPose ? "ERFloor" : "ERBed";
        if (!seated) {
            // An external native reaction owns its displacement. Never pin it
            // back into a sleep anchor; retain the normal exit/collision gate.
            body.clearVariable(variable); bedMotion=null;
            if (!floorPose) furnitureExit.request();
            floorPose=false; return;
        }
        long now=System.nanoTime();
        boolean ready=switch(bedMotion.phase) {
            case AWAKE -> nativePoseNodeReady(prefix+"Awake");
            case ENTER -> bedClipFinished(prefix+"Enter");
            case EXIT -> bedClipFinished(prefix+"Exit");
            default -> true;
        };
        bedMotion.advance(now,ready);
        placeOwnedBedPose(bedMotion.x(now),bedMotion.y(now),bedMotion.z);
        double entryAngle=Math.atan2(bedEntryDirY,bedEntryDirX),lieAngle=Math.atan2(bedLieDirY,bedLieDirX);
        double delta=Math.atan2(Math.sin(lieAngle-entryAngle),Math.cos(lieAngle-entryAngle));
        double angle=entryAngle+delta*bedMotion.directionBlend(now);
        body.setTargetAndCurrentDirection((float)Math.cos(angle),(float)Math.sin(angle));
        body.clearVariable("forceGetUp");
        switch (bedMotion.phase) {
            case AWAKE -> body.setVariable(variable,"Awake");
            case ENTER -> body.setVariable(variable,"Enter");
            case LYING -> body.setVariable(variable,"Lying");
            case EXIT -> body.setVariable(variable,"Exit");
            case SEATED -> {
                body.clearVariable(variable);
                if (nativePoseNodeReady(floorPose ? "sit_loop*" : "SitOnFurnitureIdle")) {
                    bedMotion=null; floorPose=false;
                    body.setVariable("forceGetUp",true);
                    ProbeRuntime.log("BED_SEATED_ANCHOR_RESTORED npc="+ProbeRuntime.carrierId(body));
                }
            }
        }
    }
    private void advanceBedExit() {
        if (!bedExitRequested) return;
        if (body.isCurrentState(zombie.ai.states.PlayerOnBedState.instance())) {
            if (body.getVariableBoolean("OnBedStarted")) {
                body.setVariable("OnBedAnim","Awake");
                if (bedPoseReady("Awake")) body.setVariable("forceGetUp",true);
            }
            return;
        }
        if (body.isOnBed() || body.isCurrentState(zombie.ai.states.PlayerGetUpState.instance())) return;
        if (body.getSitOnFurnitureObject()!=null) {
            body.getSitOnFurnitureObject().setSatChair(false); body.setSitOnFurnitureObject(null);
        }
        if (!furnitureExit.active()) bedExitRequested=false;
    }
    private boolean prepareFurniturePose(zombie.iso.IsoObject object) {
        if (object==null || object.getSquare()==null || object.getObjectIndex()<0 || body.locomotion().active()
                || !body.getCharacterActions().isEmpty() || body.isOnBed() || body.isSittingOnFurniture()) return false;
        if (furnitureExit.active()) return poseFurniture==object && !furnitureExit.exiting();
        var parts=new java.util.ArrayList<zombie.iso.IsoObject>();
        if (object.hasSpriteGrid()) object.getSpriteGridObjectsIncludingSelf(parts); else parts.add(object);
        if (parts.isEmpty() || parts.size()>16) return false;
        poseTiles.clear(); bedPoseOutsideLogged=false;
        for (var part:parts) {
            var square=part.getSquare();
            if (square==null || square.getZ()!=(int)body.getZ()) { poseTiles.clear(); return false; }
            if (!poseTiles.contains(square)) poseTiles.add(square);
        }
        poseFurniture=object; approachX=body.getX(); approachY=body.getY(); approachZ=(int)body.getZ();
        nextExitCheck=nextExitLog=0; furnitureExit.begin();
        return true;
    }
    private boolean captureFurnitureStand(zombie.iso.IsoObject object) {
        if (object!=poseFurniture || !furnitureExit.active() || furnitureExit.exiting()) return false;
        var direction=body.getSitOnFurnitureDirection();
        String side=body.getVariableString("SitOnFurnitureDirection");
        if (direction==null || side==null || side.isEmpty()) return true;
        var point=new org.joml.Vector3f();
        if (zombie.seating.SeatingManager.getInstance().getAdjacentPosition(body,object,direction.name(),side,
                "sitonfurniture","SitOnFurniture"+side,point)
                && Float.isFinite(point.x) && Float.isFinite(point.y)
                && Math.hypot(point.x-body.getX(),point.y-body.getY())<=3.5
                && freeFurnitureExit(point.x,point.y,(int)body.getZ())) {
            approachX=point.x; approachY=point.y; approachZ=(int)body.getZ();
        }
        return true;
    }
    private boolean alignBedPose(zombie.iso.IsoObject object) {
        if (poseFurniture!=object || !furnitureExit.active() || furnitureExit.exiting()
                || body.isAsleep() || !bedPoseReady("Awake") || !body.hasAnimationPlayer()) return false;
        String facing=zombie.seating.SeatingManager.getInstance().getFacingDirection(object);
        if (!("N".equals(facing) || "S".equals(facing) || "E".equals(facing) || "W".equals(facing))) return false;
        // The four vanilla GetOnBed branches own deferred rotation. Facing
        // is the action's turn target, not a replacement for its final root
        // orientation. Never overwrite that orientation between native clips.
        // Keep the existing bridge phase for callers, but only admit the pose
        // after the entry animation (including its blended tail) has gone.
        for (var node:body.getAdvancedAnimator().getRootLayer().getLiveAnimNodes()) {
            String name=node.getName();
            if (name!=null && name.startsWith("GetOnBed") && node.getWeight()>0.001f) return false;
        }
        if (!bedAnchorInside()) {
            if (!bedPoseOutsideLogged) logBedPose("ENTRY_OUTSIDE_BED",object);
            bedPoseOutsideLogged=true;
            return false;
        }
        logBedPose("ENTRY_FINISHED",object);
        return true;
    }
    private boolean bedAnchorInside() {
        for (var square:poseTiles) {
            if (square.getX()==(int)Math.floor(body.getX()) && square.getY()==(int)Math.floor(body.getY())
                    && square.getZ()==(int)Math.floor(body.getZ())) return true;
        }
        return false;
    }
    private void logBedPose(String phase,zombie.iso.IsoObject object) {
        if (object==null || !body.hasAnimationPlayer()) return;
        var sprite=object.getSprite();
        var grid=sprite==null ? null : sprite.getSpriteGrid();
        StringBuilder nodes=new StringBuilder();
        if (body.getAdvancedAnimator()!=null && body.getAdvancedAnimator().getRootLayer()!=null) {
            int count=0;
            for (var node:body.getAdvancedAnimator().getRootLayer().getLiveAnimNodes()) {
                if (node.getWeight()>0.001f && count++<8) nodes.append(node.getName()).append(':').append(node.getWeight()).append(',');
            }
        }
        ProbeRuntime.log("BED_POSE phase="+phase+" npc="+ProbeRuntime.carrierId(body)
                +" sprite="+(sprite==null ? "null" : sprite.getName())
                +" facing="+zombie.seating.SeatingManager.getInstance().getFacingDirection(object)
                +" propertyFacing="+object.getProperties().get("Facing")
                +" grid="+(grid==null ? "null" : grid.getSpriteGridPosX(sprite)+","+grid.getSpriteGridPosY(sprite))
                +" object="+object.getX()+","+object.getY()+","+object.getZ()
                +" branch="+body.getVariableString("OnBedDirection")+" pose="+body.getVariableString("OnBedAnim")
                +" ownedPose="+body.getVariableString("ERBedPose")
                +" angle="+body.getAnimAngleRadians()+" target="+body.getAnimationPlayer().getTargetAngle()
                +" pos="+body.getX()+","+body.getY()+" asleep="+body.isAsleep()+" nodes="+nodes);
    }
    private boolean furnitureNativePose() {
        return body.isOnBed() || body.isSittingOnFurniture() || body.isCurrentState(zombie.ai.states.PlayerOnBedState.instance())
                || body.isCurrentState(zombie.ai.states.PlayerSitOnFurnitureState.instance())
                || body.isCurrentState(zombie.ai.states.PlayerGetUpState.instance());
    }
    private boolean furnitureRootTrack() {
        if (!furnitureExit.active() || body.getAdvancedAnimator()==null || body.getAdvancedAnimator().getRootLayer()==null) return false;
        boolean active=false;
        for (var node:body.getAdvancedAnimator().getRootLayer().getLiveAnimNodes()) {
            String name=node.getName();
            if (name==null || node.getWeight()<=0.001f) continue;
            if (name.startsWith("fromSitOnFurniture") || name.startsWith("fromOnBed")) { furnitureExit.request(); active=true; }
            else if (name.startsWith("GetOnBed") || name.startsWith("OnBed") || name.startsWith("SitOnFurniture")) active=true;
        }
        return active;
    }
    private boolean freeFurnitureExit(float x,float y,int z) {
        var square=body.getCell().getGridSquare((int)Math.floor(x),(int)Math.floor(y),z);
        if (square==null || poseTiles.contains(square) || !square.TreatAsSolidFloor() || square.isSolid() || square.isSolidTrans()) return false;
        if (poseFurniture!=null && !sameFurnitureRoom(square,poseFurniture.getSquare())) return false;
        var moving=square.getMovingObjects();
        if (moving.size()>64) return false;
        for (int i=0;i<moving.size();i++) if (moving.get(i)!=body) return false;
        return zombie.pathfind.PolygonalMap2.instance.canStandAt(x,y,z,body,false,false);
    }
    private boolean correctionAllowed(float x,float y) {
        if ((int)body.getZ()!=approachZ || Math.hypot(x-body.getX(),y-body.getY())>3.5 || !freeFurnitureExit(x,y,approachZ)) return false;
        var start=body.getCurrentSquare();
        if (start==null) return false;
        var sight=zombie.iso.LosUtil.lineClear(body.getCell(),(int)Math.floor(body.getX()),(int)Math.floor(body.getY()),approachZ,
                (int)Math.floor(x),(int)Math.floor(y),approachZ,false);
        if (sight!=zombie.iso.LosUtil.TestResults.Clear && sight!=zombie.iso.LosUtil.TestResults.ClearThroughOpenDoor) return false;
        var end=body.getCell().getGridSquare((int)Math.floor(x),(int)Math.floor(y),approachZ);
        // Restrict the correction to this furniture and its immediate exit;
        // never cross an intervening tile/room or an unloaded part of the map.
        var previous=start;
        for (int i=0;i<=16;i++) {
            float px=body.getX()+(x-body.getX())*i/16f,py=body.getY()+(y-body.getY())*i/16f;
            var square=body.getCell().getGridSquare((int)Math.floor(px),(int)Math.floor(py),approachZ);
            if (square==null || square!=start && square!=end && !poseTiles.contains(square)) return false;
            if (square!=previous && (previous.isWindowTo(square) || previous.isWallTo(square) || previous.isDoorTo(square))) return false;
            previous=square;
        }
        return true;
    }
    private boolean correctFurnitureExit(float x,float y) {
        if (!correctionAllowed(x,y)) return false;
        body.setX(x); body.setY(y); body.setNextX(x); body.setNextY(y); body.setLastX(x); body.setLastY(y);
        body.setCurrentSquareFromPosition(); body.setMovingSquareNow();
        ProbeRuntime.log("FURNITURE_EXIT_CORRECTED pos="+x+","+y+","+approachZ);
        return true;
    }
    private void settleFurnitureExit() {
        if (!furnitureExit.active()) return;
        long now=System.nanoTime();
        if (body.isCurrentState(zombie.ai.states.PlayerGetUpState.instance())) furnitureExit.request();
        furnitureExit.observe(furnitureNativePose(),furnitureRootTrack(),now);
        if (!furnitureExit.settled(now) || now<nextExitCheck) return;
        nextExitCheck=now+500_000_000L;
        boolean free=freeFurnitureExit(body.getX(),body.getY(),(int)body.getZ());
        if (!free) free=correctFurnitureExit(approachX,approachY);
        if (!free) {
            float best=Float.POSITIVE_INFINITY,bx=0,by=0;
            for (var square:poseTiles) for (var dir:EXIT_DIRECTIONS) {
                var target=square.getAdjacentSquare(dir);
                if (target==null) continue;
                float x=target.getX()+0.5f,y=target.getY()+0.5f;
                float distance=(x-body.getX())*(x-body.getX())+(y-body.getY())*(y-body.getY());
                if (distance<best && correctionAllowed(x,y)) { best=distance; bx=x; by=y; }
            }
            if (Float.isFinite(best)) free=correctFurnitureExit(bx,by);
        }
        if (!free) {
            if (now>=nextExitLog) { nextExitLog=now+5_000_000_000L; ProbeRuntime.log("FURNITURE_EXIT_BLOCKED pos="+body.getX()+","+body.getY()); }
            return;
        }
        body.setCollidable(true);
        if (body.getSitOnFurnitureObject()==poseFurniture) {
            poseFurniture.setSatChair(false); body.setSitOnFurnitureObject(null); body.setSitOnFurnitureDirection(null);
        }
        furnitureExit.finish(); poseFurniture=null; poseTiles.clear(); bedExitRequested=false;
        ProbeRuntime.log("FURNITURE_EXIT_READY pos="+body.getX()+","+body.getY()+","+body.getZ());
    }

    private boolean sameFurnitureRoom(zombie.iso.IsoGridSquare a,zombie.iso.IsoGridSquare b) {
        return a!=null && b!=null && a.getZ()==b.getZ() && a.getRoom()==b.getRoom() && a.isOutside()==b.isOutside();
    }
}
