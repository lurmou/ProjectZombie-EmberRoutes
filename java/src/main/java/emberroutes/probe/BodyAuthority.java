package emberroutes.probe;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

/** World-local capability registry; no engine or inventory dependencies. */
public final class BodyAuthority {
    private record Grant(String job, long generation, String key) {}
    private final Map<String, Grant> grants = new HashMap<>();
    private final Map<String, Long> generations = new HashMap<>();
    private boolean frozen;
    private boolean retired;
    public String acquire(String npc, String job, long generation) {
        if (frozen || retired || npc == null || npc.isEmpty() || job == null || job.isEmpty()
                || generation <= generations.getOrDefault(npc, 0L) || grants.containsKey(npc)) return "";
        String key = UUID.randomUUID().toString();
        grants.put(npc, new Grant(job, generation, key)); generations.put(npc, generation);
        return key;
    }
    public boolean managed(String npc) { return generations.containsKey(npc); }
    public boolean legacyAllowed(String npc) { return !frozen && !retired && !managed(npc); }
    public boolean lifecycleIdle(String npc) {
        return !frozen && !retired && npc != null && !npc.isEmpty() && !grants.containsKey(npc);
    }
    /** Save-only system access. Never authorizes a task, movement or removal. */
    public boolean saveIdle(String npc) {
        return frozen && !retired && npc != null && !npc.isEmpty() && !grants.containsKey(npc);
    }
    public boolean saveDrained() { return frozen && !retired && grants.isEmpty(); }
    public boolean allows(String npc, String key, boolean stopping) {
        Grant grant = grants.get(npc);
        return grant != null && grant.key.equals(key) && (stopping || (!frozen && !retired));
    }
    public boolean release(String npc, String key, boolean stopped) {
        Grant grant = grants.get(npc);
        if (grant == null || !grant.key.equals(key) || !stopped) return false;
        grants.remove(npc); return true;
    }
    public void freeze() { frozen = true; }
    public boolean thaw() {
        if (retired || !grants.isEmpty()) return false;
        frozen = false; return true;
    }
    public void retire() { retired = true; frozen = true; }
    public boolean retired() { return retired; }
}
