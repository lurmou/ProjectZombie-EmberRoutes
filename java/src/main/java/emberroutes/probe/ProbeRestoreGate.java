package emberroutes.probe;

/** A checkpoint can be consumed once per world session, even after explicit removal. */
public final class ProbeRestoreGate {
    public enum State { UNRESOLVED, ACTIVE, REMOVED, LOST }
    private State state = State.UNRESOLVED;
    public State state() { return state; }
    public void reset() { state = State.UNRESOLVED; }
    public void attached() { state = State.ACTIVE; }
    public void removed() { state = State.REMOVED; }
    public void lost() { if (state == State.ACTIVE) state = State.LOST; }
    public static boolean mayReleaseDisposedWorld(boolean worldReplaced, boolean objectsEmpty, boolean allChunkMapsDisposed) {
        return worldReplaced && objectsEmpty && allChunkMapsDisposed;
    }
    public boolean canRestore(boolean bodyExists) { return !bodyExists && state == State.UNRESOLVED; }
    public boolean canSpawn(boolean bodyExists, boolean savedRecordExists) {
        return !bodyExists && (state == State.REMOVED || (state == State.UNRESOLVED && !savedRecordExists));
    }
}
