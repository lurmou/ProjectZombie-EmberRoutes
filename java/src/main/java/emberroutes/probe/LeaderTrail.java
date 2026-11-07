package emberroutes.probe;

/** Leader path history. Geometry only: no engine calls, no allocation per sample.
 * One instance per squad, shared by all followers of the same leader. */
final class LeaderTrail {
    static final int CAPACITY = 96;
    /** 0.25 tile sampling keeps sub-tile accuracy through door frames. */
    static final float SPACING_SQ = 0.0625f;
    /** A single jump this large is a teleport or vehicle move, not a walked path. */
    static final float JUMP_SQ = 6.25f;

    private final float[] xs = new float[CAPACITY];
    private final float[] ys = new float[CAPACITY];
    private final int[] zs = new int[CAPACITY];
    private int head = -1, count;
    private float lastX, lastY;
    private int lastZ;

    // Sample output: scalars so a 10Hz planner never allocates a result object.
    float outX, outY, outDirX, outDirY;
    int outFloor;
    boolean outValid;

    boolean empty() { return count == 0; }

    void reset() { head = -1; count = 0; outValid = false; }

    /** Break the segment: floor change and large jumps must not interpolate across. */
    void record(float x, float y, int floor) {
        if (count == 0) { push(x, y, floor); return; }
        float dx = x - lastX, dy = y - lastY;
        float distance2 = dx * dx + dy * dy;
        if (floor != lastZ || distance2 > JUMP_SQ) {
            count = 0;
            push(x, y, floor);
            return;
        }
        if (distance2 < SPACING_SQ) return;
        push(x, y, floor);
    }

    /** Walk back along the recorded route. False means the history is shorter than
     * requested; the caller must use its own geometric fallback instead of
     * extrapolating outside the walked route. */
    boolean sample(float backDistance) {
        outValid = false;
        if (count == 0) return false;
        float remaining = backDistance > 0 ? backDistance : 0;
        float currentX = xs[head], currentY = ys[head];
        if (remaining <= 0.0005f) {
            outX = currentX; outY = currentY; outFloor = zs[head];
            if (count > 1) {
                int previous = index(1);
                setDirection(currentX - xs[previous], currentY - ys[previous]);
            } else { outDirX = 0; outDirY = 0; }
            outValid = true;
            return true;
        }
        for (int i = 1; i < count; i++) {
            int older = index(i);
            float px = xs[older], py = ys[older];
            float dx = currentX - px, dy = currentY - py;
            float length = (float)Math.sqrt(dx * dx + dy * dy);
            if (length <= 0.001f) continue;
            if (remaining <= length) {
                float t = remaining / length;
                outX = currentX + (px - currentX) * t;
                outY = currentY + (py - currentY) * t;
                outFloor = zs[older];
                setDirection(dx / length, dy / length);
                outValid = true;
                return true;
            }
            remaining -= length;
            currentX = px; currentY = py;
        }
        return false;
    }

    private void setDirection(float dx, float dy) {
        float length = (float)Math.sqrt(dx * dx + dy * dy);
        if (length <= 0.001f) { outDirX = 0; outDirY = 0; return; }
        outDirX = dx / length; outDirY = dy / length;
    }

    private int index(int back) { return (head - back + CAPACITY) % CAPACITY; }

    private void push(float x, float y, int floor) {
        head = (head + 1) % CAPACITY;
        xs[head] = x; ys[head] = y; zs[head] = floor;
        if (count < CAPACITY) count++;
        lastX = x; lastY = y; lastZ = floor;
    }
}
