package emberroutes.probe;

import java.util.ArrayList;
import java.util.Objects;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;

/**
 * Lightweight, allocation-free container fingerprint for zero-cost change detection.
 */
public final class WarehouseFingerprint {
    private final int size;
    private final int headId;
    private final int tailId;
    private final long weightBits;

    public WarehouseFingerprint(int size, int headId, int tailId, double weight) {
        this.size = size;
        this.headId = headId;
        this.tailId = tailId;
        // Quantize weight to 0.01 kg to avoid floating point precision differences
        this.weightBits = Double.doubleToLongBits(Math.round(weight * 100.0) / 100.0);
    }

    public static WarehouseFingerprint of(ItemContainer container) {
        if (container == null) return null;
        ArrayList<InventoryItem> items = container.getItems();
        if (items == null) return null;
        int sz = items.size();
        int head = 0, tail = 0;
        if (sz > 0) {
            InventoryItem h = items.get(0);
            InventoryItem t = items.get(sz - 1);
            if (h != null) head = h.getID();
            if (t != null) tail = t.getID();
        }
        double weight = container.getContentsWeight();
        return new WarehouseFingerprint(sz, head, tail, weight);
    }

    public boolean matches(WarehouseFingerprint other) {
        if (other == null) return false;
        return this.size == other.size
            && this.headId == other.headId
            && this.tailId == other.tailId
            && this.weightBits == other.weightBits;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof WarehouseFingerprint that)) return false;
        return matches(that);
    }

    @Override
    public int hashCode() {
        return Objects.hash(size, headId, tailId, weightBits);
    }
}
