package emberroutes.probe;

import java.util.ArrayList;
import java.util.Collections;
import java.util.IdentityHashMap;
import java.util.Set;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoZombie;
import zombie.core.skinnedmodel.IGrappleable;
import zombie.iso.IsoCell;
import zombie.iso.IsoMovingObject;

/** Temporary retirement reverse links. Scanned only during bounded retirement,
 * at most 10 Hz; never reset unrelated zombies' targets or state machines. */
final class ProbeWorldLinks {
    private final Set<IsoZombie> attackers = Collections.newSetFromMap(new IdentityHashMap<>());
    private int clearedLinks;

    boolean releaseAndCheck(ProbeNpc npc, IsoCell cell) {
        boolean busy = false;
        if (npc.isGrappling()) npc.LetGoOfGrappled("Aborted");
        if (npc.isBeingGrappled()) {
            IGrappleable grappler = npc.getGrappledBy();
            if (grappler != null && grappler.isGrapplingTarget(npc))
                grappler.LetGoOfGrappled("Aborted");
        }
        if (cell != null) {
            Set<IsoGameCharacter> characters = Collections.newSetFromMap(new IdentityHashMap<>());
            characters.addAll(new ArrayList<>(cell.getZombieList()));
            for (IsoMovingObject object : new ArrayList<>(cell.getObjectList())) {
                if (object instanceof IsoGameCharacter character) characters.add(character);
            }
            for (IsoGameCharacter character : characters) {
                if (character == npc) continue;
                if (character.isGrapplingTarget(npc)) {
                    character.LetGoOfGrappled("Aborted");
                    clearedLinks++;
                }
                if (character.getFollowingTarget() == npc) {
                    character.setFollowingTarget(null);
                    clearedLinks++;
                }
                if (character instanceof IsoZombie zombie) {
                    if (zombie.getTarget() == npc) {
                        attackers.add(zombie);
                        zombie.setTarget(null);
                        zombie.getPathFindBehavior2().cancel();
                        zombie.setPath2(null);
                        clearedLinks++;
                    }
                    if (zombie.getEatBodyTarget() == npc) {
                        attackers.add(zombie);
                        zombie.setEatBodyTarget(null, false);
                        clearedLinks++;
                    }
                }
                if (character.isGrapplingTarget(npc) || character.isBeingGrappledBy(npc)) busy = true;
            }
        }
        // Keep the body's square valid while prior attackers finish their
        // current animation. A new unrelated target is not ours to interrupt.
        for (IsoZombie zombie : attackers) {
            if (zombie.getCurrentSquare() != null && zombie.isAttacking()
                    && (zombie.getTarget() == null || zombie.getTarget() == npc)) busy = true;
            if (zombie.getTarget() == npc || zombie.getEatBodyTarget() == npc) busy = true;
        }
        return busy || npc.isGrappling() || npc.isBeingGrappled();
    }

    int clearedLinks() { return clearedLinks; }
    int attackers() { return attackers.size(); }
    void clear() { attackers.clear(); clearedLinks = 0; }
}
