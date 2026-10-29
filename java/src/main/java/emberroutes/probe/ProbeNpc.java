package emberroutes.probe;

import zombie.UpdateSchedulerSimulationLevel;
import zombie.ai.AIBrainPlayerControlVars;
import zombie.ai.sadisticAIDirector.SleepingEvent;
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
    private zombie.iso.IsoObject requestedFurniture, reachedFurniture;
    private double furniturePathLimit;
    private boolean furniturePathChecked;
    private static final java.util.List<String> SLEEP_QUALITIES=java.util.List.of(
            "floor","goodBed","averageBed","badBed","goodBedPillow","averageBedPillow","badBedPillow");
    private static final zombie.iso.IsoDirections[] EXIT_DIRECTIONS={
            zombie.iso.IsoDirections.N,zombie.iso.IsoDirections.S,zombie.iso.IsoDirections.E,zombie.iso.IsoDirections.W};

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
    boolean furniturePoseOwned() { return furnitureExit.active(); }
    int stopMask() {
        return (movement.active() ? 1 : 0) | (isMoving() ? 2 : 0)
            | (!getCharacterActions().isEmpty() ? 4 : 0) | (getPath2() != null ? 8 : 0)
            | (!getPathFindBehavior2().isGoalNone() && !getPathFindBehavior2().getIsCancelled() ? 16 : 0)
            | (getPathFindBehavior2().pathNextIsSet ? 32 : 0)
            | (isAsleep() ? 64 : 0) | (isResting() ? 128 : 0) | (getBed()!=null ? 256 : 0)
            | (isCurrentState(zombie.ai.states.FitnessState.instance()) || getFitness().getCurrentExe()!=null ? 512 : 0)
            | (isCurrentState(zombie.ai.states.PlayerEmoteState.instance()) ? 1024 : 0)
            | (furnitureExit.exiting() || isSittingOnFurniture() || isSitOnGround() || isOnBed() || isCurrentState(zombie.ai.states.PlayerOnBedState.instance()) || getSitOnFurnitureObject()!=null
                || isCurrentState(zombie.ai.states.PlayerGetUpState.instance()) ? 2048 : 0);
    }
    boolean beginRepose(String kind) {
        return beginRepose(kind,null,"floor");
    }
    boolean beginRepose(String kind,zombie.iso.IsoObject furniture,String quality) {
        boolean onSleepBed="SLEEP".equals(kind) && (bedMotion!=null || seatedSleepReady())
                && getSitOnFurnitureObject()==furniture && bedPoseReady("Asleep");
        if (failed || retiring || !attached || isDead() || (stopMask() & ~(onSleepBed ? 2048 : 0))!=0
                || getVehicle()!=null || isSittingOnFurniture() && !onSleepBed) return false;
        if (furniture!=null && (furniture.getSquare()==null || furniture.getObjectIndex()<0
                || furniture.isFurnitureOccupied(this) || furniture.getSquare().getZ()!=(int)getZ()
                || (!onSleepBed && Math.abs(furniture.getSquare().getX()-(int)Math.floor(getX()))
                    +Math.abs(furniture.getSquare().getY()-(int)Math.floor(getY()))>1))) return false;
        // Same native flags/bed reference as vanilla; never integrate Stats here.
        if ("REST".equals(kind)) {
            setBed(furniture); setIsResting(true); return true;
        }
        if (!"SLEEP".equals(kind)) return false;
        if (quality==null || !SLEEP_QUALITIES.contains(quality)) return false;
        if (onSleepBed) logBedPose("LYING_BEFORE_SLEEP",furniture);
        setBed(furniture); setBedType(quality); setAsleepTime(0.0f);
        setForceWakeUpTime(-1.0f); setAsleep(true);
        SleepingEvent.instance.setPlayerFallAsleep(this, 8);
        if (onSleepBed) {
            logBedPose("SLEEP_EFFECT_STARTED",furniture);
            bedPoseObserveAt=System.nanoTime()+1_000_000_000L;
        }
        return isAsleep();
    }
    boolean endRepose() {
        // SleepingEvent's player UI/speed/save branch requires isLocalPlayer(),
        // which this carrier always rejects. Preserve native waking effects.
        if (isAsleep()) SleepingEvent.instance.wakeUp(this);
        setIsResting(false); setBed(null);
        if (bedMotion!=null) {
            if (!floorPose) furnitureExit.request();
            bedMotion.exit(System.nanoTime());
            clearVariable("forceGetUp");
            advanceOwnedBedPose();
            return false;
        }
        if (furnitureExit.active() && !isSittingOnFurniture()) furnitureExit.request();
        if (isOnBed() || isCurrentState(zombie.ai.states.PlayerOnBedState.instance())) bedExitRequested=true;
        advanceBedExit();
        return !isAsleep() && !isResting() && getBed()==null && !bedExitRequested && !furnitureExit.exiting();
    }
    boolean bedPoseReady(String pose) {
        if ("Asleep".equals(pose) && seatedSleepReady()) return true;
        if (bedMotion!=null) {
            return "Asleep".equals(pose) && bedMotion.phase==BedPoseMotion.Phase.LYING
                    && (floorPose ? isSitOnGround() : isSittingOnFurniture() && getSitOnFurnitureObject()==poseFurniture)
                    && Math.hypot(getX()-bedMotion.x(System.nanoTime()),getY()-bedMotion.y(System.nanoTime()))<0.03
                    && nativePoseNodeReady(floorPose ? "ERFloorLyingIdle" : "ERBedLyingIdle");
        }
        if ("Asleep".equals(pose) && !bedAnchorInside()) return false;
        if (!isCurrentState(zombie.ai.states.PlayerOnBedState.instance()) || !getVariableBoolean("OnBedStarted")
                || (stopMask() & ~2048)!=0 || !("Awake".equals(pose) || "Asleep".equals(pose))
                || getAdvancedAnimator()==null) return false;
        var layer=getAdvancedAnimator().getRootLayer();
        if (layer==null) return false;
        for (var node:layer.getLiveAnimNodes()) {
            if (node.isActive() && ("OnBed"+pose).equals(node.getName()) && !node.isTransitioningIn()
                    && !node.isBlendingIn() && node.getWeight()>=0.99f) return true;
        }
        return false;
    }
    private boolean seatedSleepReady() {
        var object=getSitOnFurnitureObject();
        if (bedMotion!=null || object==null || object!=poseFurniture || !furnitureExit.active()
                || furnitureExit.exiting() || object.getObjectIndex()<0 || !isSittingOnFurniture()
                || !getVariableBoolean("SitOnFurnitureStarted")
                || !isCurrentState(zombie.ai.states.PlayerSitOnFurnitureState.instance())
                || object.getProperties().has(zombie.iso.SpriteDetails.IsoFlagType.bed)) return false;
        var sprite=object.getSprite(); var grid=sprite==null ? null : sprite.getSpriteGrid();
        // A single chair has no bed-length axis. Preserve vanilla sitting,
        // rather than retrying a lying adapter that requires connected parts.
        return (grid==null || grid.getSpriteCount()==1) && nativePoseNodeReady("SitOnFurnitureIdle");
    }
    private boolean nativePoseNodeReady(String name) {
        if (getAdvancedAnimator()==null || getAdvancedAnimator().getRootLayer()==null) return false;
        if (poseLayerReady(getAdvancedAnimator().getRootLayer(),name)) return true;
        for (int i=0;i<Math.min(16,getAdvancedAnimator().getSubLayerCount());i++) {
            if (poseLayerReady(getAdvancedAnimator().getSubLayerAt(i),name)) return true;
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
        if (getAdvancedAnimator()==null) return false;
        for (int i=-1;i<Math.min(16,getAdvancedAnimator().getSubLayerCount());i++) {
            var layer=i<0 ? getAdvancedAnimator().getRootLayer() : getAdvancedAnimator().getSubLayerAt(i);
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
    boolean beginOwnedBedPose(zombie.iso.IsoObject object) {
        if (bedMotion!=null || object!=poseFurniture || !furnitureExit.active() || furnitureExit.exiting()
                || movement.active() || !getCharacterActions().isEmpty() || !isSittingOnFurniture()
                || getSitOnFurnitureObject()!=object || !getVariableBoolean("SitOnFurnitureStarted")
                || !isCurrentState(zombie.ai.states.PlayerSitOnFurnitureState.instance())) return false;
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
            float[] offset=BedPoseMotion.bedOffset(getX(),getY(),minX,minY,maxX,maxY,facing);
            if (offset==null) return false;
            dx=offset[0]; dy=offset[1];
        } else if (object.getTextureName()!=null && object.getTextureName().startsWith("furniture_bedding_")
                && getSitOnFurnitureDirection()==zombie.iso.IsoDirections.N && gy==0
                && ("E".equals(lie) || "W".equals(lie))) { dx=0.2f; dy="E".equals(lie) ? 0.4f : 0.3f; }
        var anchor=getCell().getGridSquare((int)Math.floor(getX()),(int)Math.floor(getY()),(int)getZ());
        var surface=getCell().getGridSquare((int)Math.floor(getX()+dx),(int)Math.floor(getY()+dy),(int)getZ());
        if (!sameFurnitureRoom(anchor,object.getSquare()) || !sameFurnitureRoom(surface,object.getSquare())) return false;
        var previous=anchor;
        for (int i=1;i<=16;i++) {
            var step=getCell().getGridSquare((int)Math.floor(getX()+dx*i/16f),(int)Math.floor(getY()+dy*i/16f),(int)getZ());
            if (step==null || step!=anchor && !poseTiles.contains(step)
                    || step!=previous && (previous.isWindowTo(step) || previous.isWallTo(step) || previous.isDoorTo(step))) return false;
            previous=step;
        }
        bedEntryDirX=getForwardDirectionX(); bedEntryDirY=getForwardDirectionY();
        // Bed Facing identifies its head; NPCFW's bedFootFacing is explicitly
        // its opposite. Bob_Asleep's observed head follows the model direction.
        // Keep this independent of the selected seating part and its offset.
        // A couch's Facing describes its front, not a bed head. Preserve its
        // connected-part layout direction rather than rotating a working couch.
        var vector=zombie.iso.IsoDirections.fromString(bed ? facing : lie).ToVector();
        bedLieDirX=vector.x; bedLieDirY=vector.y;
        clearVariable("forceGetUp");
        floorPose=false; bedMotion=new BedPoseMotion(getX(),getY(),getZ(),dx,dy,System.nanoTime());
        setVariable("ERBedPose","Awake");
        logBedPose("SEATED_ANCHOR_CAPTURED",object);
        return true;
    }
    boolean floorSleepSafe(int x,int y,int z) {
        var square=getCell().getGridSquare(x,y,z);
        if (z!=(int)getZ() || square==null || !square.TreatAsSolidFloor() || square.isSolid() || square.isSolidTrans()
                || square.HasStairs() || square.isOutside() || square.getFire()!=null || square.getDeadBody()!=null
                || !canStandAt(x+0.5f,y+0.5f,z)) return false;
        var objects=square.getObjects();
        if (objects.size()>64 || square.getMovingObjects().size()>64) return false;
        for (var obj:objects) if (obj instanceof zombie.iso.objects.IsoDoor || obj instanceof zombie.iso.objects.IsoWindow
                || obj.getProperties().has(zombie.iso.SpriteDetails.IsoFlagType.bed)
                || zombie.seating.SeatingManager.getInstance().getTilePositionCount(obj)>0) return false;
        for (var obj:square.getMovingObjects()) if (obj!=this) return false;
        return true;
    }
    boolean beginOwnedFloorPose() {
        if (bedMotion!=null) return floorPose;
        if (!floorSleepSafe((int)Math.floor(getX()),(int)Math.floor(getY()),(int)getZ())
                || movement.active() || !getCharacterActions().isEmpty() || furnitureExit.active() || isSittingOnFurniture()) return false;
        long now=System.nanoTime();
        if (!isSitOnGround()) {
            if (stopMask()!=0) return false;
            if (now-floorSeatRequest>=500_000_000L) {
                clearVariable("forceGetUp"); reportEvent("EventSitOnGround"); floorSeatRequest=now;
            }
            return false;
        }
        if (!getVariableBoolean("SitGroundStarted") || !nativePoseNodeReady("sit_loop*")) return false;
        floorPose=true;
        bedEntryDirX=bedLieDirX=getForwardDirectionX(); bedEntryDirY=bedLieDirY=getForwardDirectionY();
        bedMotion=new BedPoseMotion(getX(),getY(),getZ(),0,0,now);
        clearVariable("forceGetUp"); setVariable("ERFloorPose","Awake");
        return true;
    }
    private void placeOwnedBedPose(float x,float y,float z) {
        setX(x); setY(y); setZ(z); setNextX(x); setNextY(y); setLastX(x); setLastY(y);
        setCurrentSquareFromPosition(); setMovingSquareNow();
    }
    private void advanceOwnedBedPose() {
        if (bedMotion==null) return;
        boolean seated=floorPose ? isSitOnGround() && isCurrentState(zombie.ai.states.PlayerSitOnGroundState.instance())
                : isSittingOnFurniture() && isCurrentState(zombie.ai.states.PlayerSitOnFurnitureState.instance());
        String variable=floorPose ? "ERFloorPose" : "ERBedPose";
        String prefix=floorPose ? "ERFloor" : "ERBed";
        if (!seated) {
            // An external native reaction owns its displacement. Never pin it
            // back into a sleep anchor; retain the normal exit/collision gate.
            clearVariable(variable); bedMotion=null;
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
        setTargetAndCurrentDirection((float)Math.cos(angle),(float)Math.sin(angle));
        clearVariable("forceGetUp");
        switch (bedMotion.phase) {
            case AWAKE -> setVariable(variable,"Awake");
            case ENTER -> setVariable(variable,"Enter");
            case LYING -> setVariable(variable,"Lying");
            case EXIT -> setVariable(variable,"Exit");
            case SEATED -> {
                clearVariable(variable);
                if (nativePoseNodeReady(floorPose ? "sit_loop*" : "SitOnFurnitureIdle")) {
                    bedMotion=null; floorPose=false;
                    setVariable("forceGetUp",true);
                    ProbeRuntime.log("BED_SEATED_ANCHOR_RESTORED npc="+ProbeRuntime.carrierId(this));
                }
            }
        }
    }
    private void advanceBedExit() {
        if (!bedExitRequested) return;
        if (isCurrentState(zombie.ai.states.PlayerOnBedState.instance())) {
            if (getVariableBoolean("OnBedStarted")) {
                setVariable("OnBedAnim","Awake");
                if (bedPoseReady("Awake")) setVariable("forceGetUp",true);
            }
            return;
        }
        if (isOnBed() || isCurrentState(zombie.ai.states.PlayerGetUpState.instance())) return;
        if (getSitOnFurnitureObject()!=null) {
            getSitOnFurnitureObject().setSatChair(false); setSitOnFurnitureObject(null);
        }
        if (!furnitureExit.active()) bedExitRequested=false;
    }
    boolean prepareFurniturePose(zombie.iso.IsoObject object) {
        if (object==null || object.getSquare()==null || object.getObjectIndex()<0 || movement.active()
                || !getCharacterActions().isEmpty() || isOnBed() || isSittingOnFurniture()) return false;
        if (furnitureExit.active()) return poseFurniture==object && !furnitureExit.exiting();
        var parts=new java.util.ArrayList<zombie.iso.IsoObject>();
        if (object.hasSpriteGrid()) object.getSpriteGridObjectsIncludingSelf(parts); else parts.add(object);
        if (parts.isEmpty() || parts.size()>16) return false;
        poseTiles.clear(); bedPoseOutsideLogged=false;
        for (var part:parts) {
            var square=part.getSquare();
            if (square==null || square.getZ()!=(int)getZ()) { poseTiles.clear(); return false; }
            if (!poseTiles.contains(square)) poseTiles.add(square);
        }
        poseFurniture=object; approachX=getX(); approachY=getY(); approachZ=(int)getZ();
        nextExitCheck=nextExitLog=0; furnitureExit.begin();
        return true;
    }
    boolean captureFurnitureStand(zombie.iso.IsoObject object) {
        if (object!=poseFurniture || !furnitureExit.active() || furnitureExit.exiting()) return false;
        var direction=getSitOnFurnitureDirection();
        String side=getVariableString("SitOnFurnitureDirection");
        if (direction==null || side==null || side.isEmpty()) return true;
        var point=new org.joml.Vector3f();
        if (zombie.seating.SeatingManager.getInstance().getAdjacentPosition(this,object,direction.name(),side,
                "sitonfurniture","SitOnFurniture"+side,point)
                && Float.isFinite(point.x) && Float.isFinite(point.y)
                && Math.hypot(point.x-getX(),point.y-getY())<=3.5
                && freeFurnitureExit(point.x,point.y,(int)getZ())) {
            approachX=point.x; approachY=point.y; approachZ=(int)getZ();
        }
        return true;
    }
    boolean alignBedPose(zombie.iso.IsoObject object) {
        if (poseFurniture!=object || !furnitureExit.active() || furnitureExit.exiting()
                || isAsleep() || !bedPoseReady("Awake") || !hasAnimationPlayer()) return false;
        String facing=zombie.seating.SeatingManager.getInstance().getFacingDirection(object);
        if (!("N".equals(facing) || "S".equals(facing) || "E".equals(facing) || "W".equals(facing))) return false;
        // The four vanilla GetOnBed branches own deferred rotation. Facing
        // is the action's turn target, not a replacement for its final root
        // orientation. Never overwrite that orientation between native clips.
        // Keep the existing bridge phase for callers, but only admit the pose
        // after the entry animation (including its blended tail) has gone.
        for (var node:getAdvancedAnimator().getRootLayer().getLiveAnimNodes()) {
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
            if (square.getX()==(int)Math.floor(getX()) && square.getY()==(int)Math.floor(getY())
                    && square.getZ()==(int)Math.floor(getZ())) return true;
        }
        return false;
    }
    private void logBedPose(String phase,zombie.iso.IsoObject object) {
        if (object==null || !hasAnimationPlayer()) return;
        var sprite=object.getSprite();
        var grid=sprite==null ? null : sprite.getSpriteGrid();
        StringBuilder nodes=new StringBuilder();
        if (getAdvancedAnimator()!=null && getAdvancedAnimator().getRootLayer()!=null) {
            int count=0;
            for (var node:getAdvancedAnimator().getRootLayer().getLiveAnimNodes()) {
                if (node.getWeight()>0.001f && count++<8) nodes.append(node.getName()).append(':').append(node.getWeight()).append(',');
            }
        }
        ProbeRuntime.log("BED_POSE phase="+phase+" npc="+ProbeRuntime.carrierId(this)
                +" sprite="+(sprite==null ? "null" : sprite.getName())
                +" facing="+zombie.seating.SeatingManager.getInstance().getFacingDirection(object)
                +" propertyFacing="+object.getProperties().get("Facing")
                +" grid="+(grid==null ? "null" : grid.getSpriteGridPosX(sprite)+","+grid.getSpriteGridPosY(sprite))
                +" object="+object.getX()+","+object.getY()+","+object.getZ()
                +" branch="+getVariableString("OnBedDirection")+" pose="+getVariableString("OnBedAnim")
                +" ownedPose="+getVariableString("ERBedPose")
                +" angle="+getAnimAngleRadians()+" target="+getAnimationPlayer().getTargetAngle()
                +" pos="+getX()+","+getY()+" asleep="+isAsleep()+" nodes="+nodes);
    }
    private boolean furnitureNativePose() {
        return isOnBed() || isSittingOnFurniture() || isCurrentState(zombie.ai.states.PlayerOnBedState.instance())
                || isCurrentState(zombie.ai.states.PlayerSitOnFurnitureState.instance())
                || isCurrentState(zombie.ai.states.PlayerGetUpState.instance());
    }
    private boolean furnitureRootTrack() {
        if (!furnitureExit.active() || getAdvancedAnimator()==null || getAdvancedAnimator().getRootLayer()==null) return false;
        boolean active=false;
        for (var node:getAdvancedAnimator().getRootLayer().getLiveAnimNodes()) {
            String name=node.getName();
            if (name==null || node.getWeight()<=0.001f) continue;
            if (name.startsWith("fromSitOnFurniture") || name.startsWith("fromOnBed")) { furnitureExit.request(); active=true; }
            else if (name.startsWith("GetOnBed") || name.startsWith("OnBed") || name.startsWith("SitOnFurniture")) active=true;
        }
        return active;
    }
    private boolean freeFurnitureExit(float x,float y,int z) {
        var square=getCell().getGridSquare((int)Math.floor(x),(int)Math.floor(y),z);
        if (square==null || poseTiles.contains(square) || !square.TreatAsSolidFloor() || square.isSolid() || square.isSolidTrans()) return false;
        if (poseFurniture!=null && !sameFurnitureRoom(square,poseFurniture.getSquare())) return false;
        var moving=square.getMovingObjects();
        if (moving.size()>64) return false;
        for (var object:moving) if (object!=this) return false;
        return zombie.pathfind.PolygonalMap2.instance.canStandAt(x,y,z,this,false,false);
    }
    private boolean correctionAllowed(float x,float y) {
        if ((int)getZ()!=approachZ || Math.hypot(x-getX(),y-getY())>3.5 || !freeFurnitureExit(x,y,approachZ)) return false;
        var start=getCurrentSquare();
        if (start==null) return false;
        var sight=zombie.iso.LosUtil.lineClear(getCell(),(int)Math.floor(getX()),(int)Math.floor(getY()),approachZ,
                (int)Math.floor(x),(int)Math.floor(y),approachZ,false);
        if (sight!=zombie.iso.LosUtil.TestResults.Clear && sight!=zombie.iso.LosUtil.TestResults.ClearThroughOpenDoor) return false;
        var end=getCell().getGridSquare((int)Math.floor(x),(int)Math.floor(y),approachZ);
        // Restrict the correction to this furniture and its immediate exit;
        // never cross an intervening tile/room or an unloaded part of the map.
        var previous=start;
        for (int i=0;i<=16;i++) {
            float px=getX()+(x-getX())*i/16f,py=getY()+(y-getY())*i/16f;
            var square=getCell().getGridSquare((int)Math.floor(px),(int)Math.floor(py),approachZ);
            if (square==null || square!=start && square!=end && !poseTiles.contains(square)) return false;
            if (square!=previous && (previous.isWindowTo(square) || previous.isWallTo(square) || previous.isDoorTo(square))) return false;
            previous=square;
        }
        return true;
    }
    private boolean correctFurnitureExit(float x,float y) {
        if (!correctionAllowed(x,y)) return false;
        setX(x); setY(y); setNextX(x); setNextY(y); setLastX(x); setLastY(y);
        setCurrentSquareFromPosition(); setMovingSquareNow();
        ProbeRuntime.log("FURNITURE_EXIT_CORRECTED pos="+x+","+y+","+approachZ);
        return true;
    }
    private void settleFurnitureExit() {
        if (!furnitureExit.active()) return;
        long now=System.nanoTime();
        if (isCurrentState(zombie.ai.states.PlayerGetUpState.instance())) furnitureExit.request();
        furnitureExit.observe(furnitureNativePose(),furnitureRootTrack(),now);
        if (!furnitureExit.settled(now) || now<nextExitCheck) return;
        nextExitCheck=now+500_000_000L;
        boolean free=freeFurnitureExit(getX(),getY(),(int)getZ());
        if (!free) free=correctFurnitureExit(approachX,approachY);
        if (!free) {
            float best=Float.POSITIVE_INFINITY,bx=0,by=0;
            for (var square:poseTiles) for (var dir:EXIT_DIRECTIONS) {
                var target=square.getAdjacentSquare(dir);
                if (target==null) continue;
                float x=target.getX()+0.5f,y=target.getY()+0.5f;
                float distance=(x-getX())*(x-getX())+(y-getY())*(y-getY());
                if (distance<best && correctionAllowed(x,y)) { best=distance; bx=x; by=y; }
            }
            if (Float.isFinite(best)) free=correctFurnitureExit(bx,by);
        }
        if (!free) {
            if (now>=nextExitLog) { nextExitLog=now+5_000_000_000L; ProbeRuntime.log("FURNITURE_EXIT_BLOCKED pos="+getX()+","+getY()); }
            return;
        }
        setCollidable(true);
        if (getSitOnFurnitureObject()==poseFurniture) {
            poseFurniture.setSatChair(false); setSitOnFurnitureObject(null); setSitOnFurnitureDirection(null);
        }
        furnitureExit.finish(); poseFurniture=null; poseTiles.clear(); bedExitRequested=false;
        ProbeRuntime.log("FURNITURE_EXIT_READY pos="+getX()+","+getY()+","+getZ());
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
        requestedFurniture=null; reachedFurniture=null;
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

    String moveToFurniture(zombie.iso.IsoObject object,double maxPathLength) {
        return moveToFurniture(object,maxPathLength,false);
    }
    String moveToFurniture(zombie.iso.IsoObject object,double maxPathLength,boolean sleep) {
        if (failed || retiring || !attached || object==null || object.getSquare()==null
                || object.getObjectIndex()<0 || object.isFurnitureOccupied(this)) return "SEAT_UNAVAILABLE";
        stopProbe();
        requestedFurniture=object; reachedFurniture=null;
        furniturePathLimit=maxPathLength; furniturePathChecked=false;
        moveStartX=getX(); moveStartY=getY();
        double distance=Math.hypot(object.getSquare().getX()+0.5-getX(),object.getSquare().getY()+0.5-getY());
        long timeout=sleep ? 180_000_000_000L : (long)Math.min(180_000_000_000.0,35_000_000_000.0+distance*3_000_000_000.0);
        movement.beginNative(object.getSquare().getX()+0.5,object.getSquare().getY()+0.5,
                object.getSquare().getZ(),System.nanoTime(),timeout);
        moveResult="MOVING"; pathResult="REQUESTED";
        getPathFindBehavior2().pathNextIsSet=false;
        // Vanilla uses this planner. Keep the exact reserved sprite-grid part;
        // choosing another part would require a new resource reservation.
        getPathFindBehavior2().pathToSitOnFurniture(object,false);
        return "MOVE_REQUESTED_SEAT";
    }
    zombie.iso.IsoObject reachedFurniture() { return reachedFurniture; }
    String moveToBed(zombie.iso.IsoObject object,se.krka.kahlua.vm.KahluaTable locations) {
        if (failed || retiring || !attached || object.getSquare()==null || object.getObjectIndex()<0
                || object.isFurnitureOccupied(this) || locations.len()!=12) return "BED_UNAVAILABLE";
        int bedZ=object.getSquare().getZ();
        float bedX=object.getSquare().getX(), bedY=object.getSquare().getY();
        for (int i=1;i<=12;i++) {
            if (!(locations.rawget(i) instanceof Number number) || !Double.isFinite(number.doubleValue()))
                return "BED_UNAVAILABLE";
            double value=number.doubleValue();
            if (i%3==0 && value!=bedZ) return "BED_UNAVAILABLE";
            if (i%3!=0 && Math.abs(value-(i%3==1 ? bedX : bedY))>3) return "BED_UNAVAILABLE";
        }
        stopProbe();
        requestedFurniture=null; reachedFurniture=null;
        moveStartX=getX(); moveStartY=getY();
        movement.beginNative(object.getSquare().getX()+0.5,object.getSquare().getY()+0.5,
                object.getSquare().getZ(),System.nanoTime(),180_000_000_000L);
        moveResult="MOVING"; pathResult="REQUESTED";
        getPathFindBehavior2().pathNextIsSet=false;
        getPathFindBehavior2().pathToNearestTable(locations);
        return "MOVE_REQUESTED_BED";
    }

    void stopProbe() {
        furnitureExit.request();
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
        if (bedMotion==null && (isSittingOnFurniture() || isSitOnGround())) setVariable("forceGetUp",true);
        else if (!isOnBed() && !isCurrentState(zombie.ai.states.PlayerOnBedState.instance())
                && !isCurrentState(zombie.ai.states.PlayerGetUpState.instance()) && getSitOnFurnitureObject()!=null) {
            getSitOnFurnitureObject().setSatChair(false); setSitOnFurnitureObject(null);
        }
        endRepose();
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
            advanceOwnedBedPose();
            if (bedPoseObserveAt!=0 && System.nanoTime()>=bedPoseObserveAt) {
                bedPoseObserveAt=0;
                if ((bedMotion!=null || isOnBed()) && isAsleep()) logBedPose("SLEEP_EFFECT_SETTLED",getSitOnFurnitureObject());
            }
            advanceBedExit();
            settleFurnitureExit();
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
        boolean nativeFurnitureMotion=false;
        try {
            if (!attached || failed || retiring || !ProbeRules.canSimulate(GameClient.client, GameServer.server)) return;
            if (bedMotion!=null) return; // the captured seat anchor owns the sleep clip's displacement
            // Furniture transitions use authored root motion after the native
            // approach has ended. Discarding it leaves the model beside the
            // chair. Never run this alongside the path follower.
            nativeFurnitureMotion=!movement.active() && (isSitOnGround() || isCurrentState(zombie.ai.states.PlayerGetUpState.instance())
                    || (furnitureExit.active() && (furnitureNativePose() || furnitureRootTrack()))
                    || getSitOnFurnitureObject()!=null && furnitureNativePose());
            if (nativeFurnitureMotion) {
                super.doDeferredMovement();
                return;
            }
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
            if (!nativeFurnitureMotion) discardRootMotion();
        }
    }

    private ProbeMovement.PathResult advancePath() {
        PathFindBehavior2 path = getPathFindBehavior2();
        PathFindBehavior2.BehaviorResult result = path.update();
        if (requestedFurniture!=null && result==PathFindBehavior2.BehaviorResult.Succeeded) {
            zombie.iso.IsoObject goal=path.getGoalSitOnFurnitureObject();
            if (goal!=requestedFurniture) return ProbeMovement.PathResult.FAILED;
            reachedFurniture=goal;
        }
        if (requestedFurniture!=null && !furniturePathChecked && getPath2()!=null && !getPath2().isEmpty()) {
            furniturePathChecked=true;
            if (furniturePathLimit>0 && getPath2().length()>furniturePathLimit) return ProbeMovement.PathResult.FAILED;
        }
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
    private boolean sameFurnitureRoom(zombie.iso.IsoGridSquare a,zombie.iso.IsoGridSquare b) {
        return a!=null && b!=null && a.getZ()==b.getZ() && a.getRoom()==b.getRoom() && a.isOutside()==b.isOutside();
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
