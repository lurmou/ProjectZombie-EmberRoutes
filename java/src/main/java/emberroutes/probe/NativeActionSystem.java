package emberroutes.probe;

import java.util.IdentityHashMap;
import java.util.Map;
import zombie.characters.CharacterTimedActions.BaseAction;
import zombie.characters.IsoPlayer;

/**
 * Native action presenter using engine-level BaseAction.
 * Separates presentation (animation, progress bar, hand models) from business onTick logic.
 * Bypasses Kahlua Lua TimedAction per-frame callback overhead completely.
 */
public final class NativeActionSystem {
    private static final class ActionState {
        BaseAction action;
        int durationTicks;
        int elapsedTicks;
        boolean finished;

        void reset(BaseAction action, int durationTicks) {
            this.action = action;
            this.durationTicks = durationTicks;
            this.elapsedTicks = 0;
            this.finished = false;
        }
    }

    private static final Map<IsoPlayer, ActionState> ACTIVE_ACTIONS = new IdentityHashMap<>();
    private static final ActionState[] POOL = new ActionState[16];
    private static int poolSize = 0;

    static {
        for (int i = 0; i < POOL.length; i++) {
            POOL[i] = new ActionState();
        }
        poolSize = POOL.length;
    }

    private NativeActionSystem() {}

    private static ActionState obtain(BaseAction action, int durationTicks) {
        ActionState state;
        if (poolSize > 0) {
            state = POOL[--poolSize];
        } else {
            state = new ActionState();
        }
        state.reset(action, durationTicks);
        return state;
    }

    private static void recycle(ActionState state) {
        state.action = null;
        if (poolSize < POOL.length) {
            POOL[poolSize++] = state;
        }
    }

    public static boolean startAction(IsoPlayer character, String anim, int durationTicks, boolean blockMovement) {
        if (character == null || character.isDead()) return false;
        stopAction(character);
        try {
            BaseAction action = new BaseAction(character);
            // Vanilla sentinel: BaseAction.finished() never ends on time when
            // maxTime == -1, so a negative duration means "unbounded" here.
            // durationTicks == 0 is passed through as maxTime == 0, which the
            // engine ends immediately (time spent >= maxTime), never hangs.
            action.maxTime = durationTicks < 0 ? -1 : durationTicks;
            action.stopOnWalk = blockMovement;
            action.stopOnRun = true;
            action.stopOnAim = true;
            action.forceProgressBar = true;
            action.setUseProgressBar(true);
            action.setBlockMovementEtc(blockMovement);
            action.setLoopedAction(true);
            character.StartAction(action);
            if (anim != null && !anim.isEmpty()) {
                action.setActionAnim(anim);
            }
            try {
                character.setPerformingAnAction(true);
            } catch (Throwable ignored) {}

            ActionState state = obtain(action, durationTicks);
            ACTIVE_ACTIONS.put(character, state);
            return true;
        } catch (Throwable t) {
            return false;
        }
    }

    public static boolean isActionFinished(IsoPlayer character) {
        if (character == null) return true;
        ActionState state = ACTIVE_ACTIONS.get(character);
        if (state == null) return true;
        if (state.finished) return true;
        if (state.action != null) {
            try {
                if (state.action.finished()) {
                    state.finished = true;
                    return true;
                }
            } catch (Throwable ignored) {}
        }
        return state.durationTicks > 0 && state.elapsedTicks >= state.durationTicks;
    }

    public static boolean isActionRunning(IsoPlayer character) {
        if (character == null || character.isDead()) return false;
        ActionState state = ACTIVE_ACTIONS.get(character);
        return state != null && !state.finished;
    }

    public static void stopAction(IsoPlayer character) {
        if (character == null) return;
        ActionState state = ACTIVE_ACTIONS.remove(character);
        if (state != null) {
            if (state.action != null) {
                try {
                    state.action.stopTimedActionAnim();
                    state.action.stop();
                } catch (Throwable ignored) {}
            }
            recycle(state);
        }
        try {
            character.StopAllActionQueue();
            var actions = character.getCharacterActions();
            if (actions != null && !actions.isEmpty()) {
                actions.clear();
            }
            character.StopTimedActionAnim();
            character.setPerformingAnAction(false);
        } catch (Throwable ignored) {}
    }

    public static void tick() {
        if (ACTIVE_ACTIONS.isEmpty()) return;
        var it = ACTIVE_ACTIONS.entrySet().iterator();
        while (it.hasNext()) {
            var entry = it.next();
            IsoPlayer character = entry.getKey();
            ActionState state = entry.getValue();
            if (character == null || character.isDead()) {
                recycle(state);
                it.remove();
                continue;
            }
            state.elapsedTicks++;
            if (!state.finished) {
                boolean done = false;
                if (state.durationTicks > 0 && state.elapsedTicks >= state.durationTicks) {
                    done = true;
                } else if (state.action != null) {
                    try {
                        done = state.action.finished();
                    } catch (Throwable ignored) {}
                }
                if (done) {
                    state.finished = true;
                }
            }
        }
    }

    public static void reset() {
        for (var entry : ACTIVE_ACTIONS.entrySet()) {
            IsoPlayer character = entry.getKey();
            ActionState state = entry.getValue();
            if (state.action != null) {
                try {
                    state.action.stopTimedActionAnim();
                    state.action.stop();
                } catch (Throwable ignored) {}
            }
            if (character != null) {
                try {
                    character.StopAllActionQueue();
                    var actions = character.getCharacterActions();
                    if (actions != null && !actions.isEmpty()) {
                        actions.clear();
                    }
                    character.StopTimedActionAnim();
                    character.setPerformingAnAction(false);
                } catch (Throwable ignored) {}
            }
            recycle(state);
        }
        ACTIVE_ACTIONS.clear();
    }
}
