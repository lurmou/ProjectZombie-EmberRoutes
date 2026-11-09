package emberroutes.probe.nav;

import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.inventory.InventoryItem;
import zombie.inventory.types.Key;
import zombie.iso.IsoDirections;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoObject;
import zombie.iso.objects.IsoDoor;
import zombie.iso.objects.IsoThumpable;
import zombie.iso.objects.IsoWindow;

/**
 * Pure evaluation of traversal costs and hazards across tile edges.
 * Cost convention:
 *   -1 : Impassable / strictly blocked.
 *    0 : Completely clear and unobstructed.
 *   >0 : Passable with dynamic soft penalty (e.g. doors, vaulting, hazard avoidance).
 */
public final class NavCost {
    public static final int BLOCKED = -1;
    public static final int CLEAR = 0;

    // Movement edge base costs
    public static final int CARDINAL_COST = 10;
    public static final int DIAGONAL_COST = 14;
    public static final int STAIR_COST = 50;

    // Soft obstacle penalties
    public static final int UNLOCKED_CLOSED_DOOR = 5;
    public static final int LOW_FENCE_VAULT = 25;
    public static final int TALL_FENCE_CLIMB = 120;
    public static final int SAFE_WINDOW_CLIMB = 35;
    public static final int GARAGE_DOOR_PASS = 40;

    // Environmental hazard penalties
    public static final int BROKEN_GLASS_SHOD_PENALTY = 50; // Detour preferred if wearing shoes

    private NavCost() {}

    /**
     * Checks whether an NPC possesses a key matching the given key ID.
     */
    public static boolean hasKey(IsoGameCharacter character, int keyId) {
        if (character == null || keyId < 0) return false;
        var inv = character.getInventory();
        if (inv == null) return false;
        var items = inv.getItems();
        if (items == null) return false;
        for (int i = 0; i < items.size(); i++) {
            InventoryItem it = items.get(i);
            if (it instanceof Key) {
                Key k = (Key) it;
                if (k.getKeyId() == keyId) return true;
            }
        }
        return false;
    }

    /**
     * Evaluates door passability between two adjacent squares.
     * Returns:
     *   CLEAR (0) if no door or door is already open.
     *   UNLOCKED_CLOSED_DOOR (5) if closed but unlocked or character holds key.
     *   BLOCKED (-1) if locked, barricaded, or obstructed.
     */
    public static int doorEdgeCost(IsoGameCharacter character, IsoGridSquare from, IsoGridSquare to) {
        if (from == null || to == null) return CLEAR;
        IsoObject obj = from.getDoorTo(to);
        if (obj == null) return CLEAR;

        if (obj instanceof IsoDoor) {
            IsoDoor door = (IsoDoor) obj;
            if (door.IsOpen()) return CLEAR;
            if (door.isDestroyed()) return CLEAR;
            if (door.isBarricaded() || door.isObstructed()) return BLOCKED;

            boolean exterior = from.isOutside();
            boolean forceLocked = door.getProperties() != null && door.getProperties().has("forceLocked");
            if (forceLocked || door.isLockedByKey()) {
                return hasKey(character, door.getKeyId()) ? UNLOCKED_CLOSED_DOOR : BLOCKED;
            }
            if (door.isLocked() && exterior) {
                return hasKey(character, door.getKeyId()) ? UNLOCKED_CLOSED_DOOR : BLOCKED;
            }
            return UNLOCKED_CLOSED_DOOR;
        }

        if (obj instanceof IsoThumpable) {
            IsoThumpable thump = (IsoThumpable) obj;
            if (!thump.isDoor()) return CLEAR;
            if (thump.IsOpen() || thump.isDestroyed()) return CLEAR;
            if (thump.isBarricaded() || thump.isObstructed()) return BLOCKED;
            if (thump.getLockedByCode() > 0) return BLOCKED;

            boolean exterior = from.isOutside();
            if (thump.isLockedByPadlock() || thump.isLockedByKey()) {
                return hasKey(character, thump.getKeyId()) ? UNLOCKED_CLOSED_DOOR : BLOCKED;
            }
            if (thump.isLocked() && exterior) {
                return hasKey(character, thump.getKeyId()) ? UNLOCKED_CLOSED_DOOR : BLOCKED;
            }
            return UNLOCKED_CLOSED_DOOR;
        }

        return UNLOCKED_CLOSED_DOOR;
    }

    /**
     * Evaluates window traversal between two adjacent squares.
     * Returns:
     *   CLEAR (0) if no window.
     *   SAFE_WINDOW_CLIMB (35) if open or clean broken window.
     *   BLOCKED (-1) if locked, barricaded, or window has unremoved smashed glass!
     */
    public static int windowEdgeCost(IsoGameCharacter character, IsoGridSquare from, IsoGridSquare to) {
        if (from == null || to == null) return CLEAR;
        IsoWindow win = from.getWindowTo(to);
        if (win == null) return CLEAR;

        if (win.isInvincible() || win.isBarricaded()) return BLOCKED;

        // Invariant: smashed windows with unremoved glass shards strictly forbid traversal!
        if (win.isSmashed() && !win.isGlassRemoved()) {
            return BLOCKED;
        }

        if (win.IsOpen() || win.isDestroyed()) {
            return SAFE_WINDOW_CLIMB;
        }

        // Closed window: can only climb if character can open it (not locked)
        if (win.isPermaLocked()) return BLOCKED;

        return SAFE_WINDOW_CLIMB + 10;
    }

    /**
     * Evaluates environmental hazard penalty on the destination square.
     * Returns:
     *   BLOCKED (-1) if fire or barefoot on broken glass.
     *   BROKEN_GLASS_SHOD_PENALTY (50) if wearing shoes over broken glass.
     *   CLEAR (0) if clean.
     */
    public static int groundHazardCost(IsoGameCharacter character, IsoGridSquare sq) {
        if (sq == null) return CLEAR;

        // Fire is strictly impassable
        if (sq.haveFire() || sq.hasFireObject() || sq.hasLitCampfire()) {
            return BLOCKED;
        }

        // Broken glass on floor
        if (sq.getBrokenGlass() != null) {
            boolean barefoot = isBarefoot(character);
            if (barefoot) {
                // Strict self-preservation: barefoot characters never step on broken glass!
                return BLOCKED;
            }
            return BROKEN_GLASS_SHOD_PENALTY;
        }

        return CLEAR;
    }

    /**
     * Helper to determine whether a character is barefoot or has completely worn shoes.
     */
    public static boolean isBarefoot(IsoGameCharacter character) {
        if (character == null) return false;
        var worn = character.getWornItems();
        if (worn == null) return false;
        var items = worn.getItems();
        if (items == null) return false;
        for (int i = 0; i < items.size(); i++) {
            var w = items.get(i);
            if (w != null && w.getLocation() != null) {
                String loc = String.valueOf(w.getLocation());
                if ("Shoes".equalsIgnoreCase(loc) || loc.contains("Shoes")) {
                    return false; // Shoes equipped
                }
            }
        }
        return true; // No shoes found
    }
}
