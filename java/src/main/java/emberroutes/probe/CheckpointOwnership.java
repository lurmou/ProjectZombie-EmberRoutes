package emberroutes.probe;

import java.io.IOException;
import java.util.HashSet;
import java.util.Set;

/** One-pass cross-record identity check; payloads can be released after each visit. */
final class CheckpointOwnership {
    private final Set<String> npcs=new HashSet<>();
    private final Set<Integer> items=new HashSet<>();
    void accept(String slot,ProbeCheckpoint.Data data) throws IOException {
        if ((!slot.equals("legacy") && !slot.equals(data.npcId())) || !npcs.add(data.npcId()))
            throw new IOException("CHECKPOINT_NPC_ID_DUPLICATED_OR_MISMATCH");
        for (var item:data.items()) if (!items.add(item.id())) throw new IOException("CHECKPOINT_ITEM_ID_DUPLICATED");
    }
}
