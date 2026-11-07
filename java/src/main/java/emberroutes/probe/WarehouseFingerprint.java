package emberroutes.probe;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Objects;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;

/**
 * Slot-level container fingerprint.
 *
 * <p>The former four scalar fingerprint (size, head id, tail id, weight)
 * silently missed same-size replacements in the middle of a container:
 * swapping two items of the same type left head, tail, size and weight
 * untouched. Item ids are unique in PZ, so comparing every slot id is exact
 * for content identity. One linear pass, no string work, no per-item objects.
 */
public final class WarehouseFingerprint {
    private final int[] slotIds;
    private final long weightBits;

    public WarehouseFingerprint(int[] slotIds, double weight) {
        this.slotIds = slotIds;
        // Quantize weight to 0.01 kg to avoid floating point precision differences.
        this.weightBits = Double.doubleToLongBits(Math.round(weight * 100.0) / 100.0);
    }

    public static WarehouseFingerprint of(ItemContainer container) {
        if (container == null) return null;
        ArrayList<InventoryItem> items = container.getItems();
        if (items == null) return null;
        int sz = items.size();
        int[] ids = new int[sz];
        for (int i = 0; i < sz; i++) {
            InventoryItem it = items.get(i);
            ids[i] = it == null ? 0 : it.getID();
        }
        return new WarehouseFingerprint(ids, container.getContentsWeight());
    }

    /** True only if every slot still holds the same item. */
    public boolean matches(WarehouseFingerprint other) {
        if (other == null) return false;
        return this.weightBits == other.weightBits && Arrays.equals(this.slotIds, other.slotIds);
    }

    public int size() {
        return slotIds.length;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof WarehouseFingerprint that)) return false;
        return matches(that);
    }

    @Override
    public int hashCode() {
        return Objects.hash(Arrays.hashCode(slotIds), weightBits);
    }
}
