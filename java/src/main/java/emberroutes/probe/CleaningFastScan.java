package emberroutes.probe;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.Map;

import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.KahluaTable;
import zombie.core.Core;
import zombie.iso.IsoChunk;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoMovingObject;
import zombie.iso.IsoObject;
import zombie.iso.IsoWallBloodSplat;
import zombie.iso.objects.IsoDeadBody;
import zombie.iso.sprite.IsoSprite;
import zombie.iso.sprite.IsoSpriteInstance;
import zombie.util.list.PZArrayList;

/**
 * Java-native chunk scan for settlement cleaning and lumberjack work.
 *
 * <p>The vanilla predicate {@code IsoGridSquare.haveStains()} walks the square's
 * object list twice (blood, then grime) and, for grime, runs
 * {@code String.contains("overlay_grime")} on every attached sprite parent name.
 * A dense chunk repeats that string scan tens of thousands of times per pass.
 * {@link #stainsHere} walks the objects once and memoizes the name test, which
 * is the same predicate with far fewer string scans.
 */
public final class CleaningFastScan {
    private CleaningFastScan() {}

    /** Sprite name -> contains("overlay_grime"). Access-ordered, bounded LRU. */
    private static final Map<String, Boolean> GRIME_NAME = new LinkedHashMap<String, Boolean>(256, 0.75f, true) {
        @Override protected boolean removeEldestEntry(Map.Entry<String, Boolean> eldest) {
            return size() > 4096;
        }
    };

    private static KahluaTable table() {
        return J2SEPlatform.getInstance().newTable();
    }

    private static boolean grimeName(String name) {
        Boolean cached = GRIME_NAME.get(name);
        if (cached == null) {
            cached = name.contains("overlay_grime");
            GRIME_NAME.put(name, cached);
        }
        return cached;
    }

    private static boolean spriteIsGrime(IsoSpriteInstance instance) {
        if (instance == null) return false;
        IsoSprite parent = instance.getParentSprite();
        if (parent == null) return false;
        String name = parent.getName();
        return name != null && grimeName(name);
    }

    /**
     * Equivalent to {@code square.haveStains()} (blood decals OR grime), but a
     * single object pass and a memoized grime-name test.
     */
    private static boolean stainsHere(IsoGridSquare square, boolean bloodEnabled) {
        PZArrayList<IsoObject> objects = square.getObjects();
        int size = objects.size();
        for (int i = 0; i < size; i++) {
            IsoObject object = objects.get(i);
            if (object == null) continue;
            if (bloodEnabled) {
                ArrayList<IsoWallBloodSplat> splats = object.wallBloodSplats;
                if (splats != null && !splats.isEmpty()) return true;
            }
            ArrayList<IsoSpriteInstance> sprites = object.attachedAnimSprite;
            if (sprites != null) {
                int count = sprites.size();
                for (int s = 0; s < count; s++) {
                    if (spriteIsGrime(sprites.get(s))) return true;
                }
            }
        }
        return false;
    }

    private static void addPoint(KahluaTable list, int index, IsoGridSquare square) {
        KahluaTable point = table();
        point.rawset("x", Double.valueOf(square.getX()));
        point.rawset("y", Double.valueOf(square.getY()));
        point.rawset("z", Double.valueOf(square.getZ()));
        list.rawset(Double.valueOf(index), point);
    }

    private static void addCorpses(KahluaTable list, int[] count, int limit, IsoGridSquare square) {
        ArrayList<IsoMovingObject> moving = square.getStaticMovingObjects();
        if (moving == null) return;
        int size = moving.size();
        for (int i = 0; i < size; i++) {
            if (!(moving.get(i) instanceof IsoDeadBody body)) continue;
            KahluaTable entry = table();
            entry.rawset("x", Double.valueOf(square.getX()));
            entry.rawset("y", Double.valueOf(square.getY()));
            entry.rawset("z", Double.valueOf(square.getZ()));
            entry.rawset("body", body);
            list.rawset(Double.valueOf(++count[0]), entry);
            if (count[0] >= limit) return;
        }
    }

    public static KahluaTable scanChunkStains(IsoChunk chunk, int maxCount) {
        if (chunk == null) return null;
        int limit = maxCount > 0 ? maxCount : 64;
        KahluaTable list = table();
        int count = 0;
        boolean blood = Core.getInstance().getOptionBloodDecals() != 0;

        for (int z = 0; z < 8; z++) {
            IsoGridSquare[] squares;
            try {
                squares = chunk.getSquaresForLevel(z);
            } catch (RuntimeException ignored) {
                continue;
            }
            if (squares == null) continue;
            for (IsoGridSquare square : squares) {
                if (square == null || !stainsHere(square, blood)) continue;
                addPoint(list, ++count, square);
                if (count >= limit) return list;
            }
        }
        return list;
    }

    public static KahluaTable scanChunkCorpses(IsoChunk chunk, int maxCount) {
        if (chunk == null) return null;
        int limit = maxCount > 0 ? maxCount : 16;
        KahluaTable list = table();
        int[] count = {0};

        for (int z = 0; z < 8; z++) {
            IsoGridSquare[] squares;
            try {
                squares = chunk.getSquaresForLevel(z);
            } catch (RuntimeException ignored) {
                continue;
            }
            if (squares == null) continue;
            for (IsoGridSquare square : squares) {
                if (square == null) continue;
                addCorpses(list, count, limit, square);
                if (count[0] >= limit) return list;
            }
        }
        return list;
    }

    /**
     * One pass for both target kinds. corpseLimit<=0 skips corpse collection.
     * Both kinds share the square traversal instead of walking the chunk twice.
     */
    public static KahluaTable scanChunkTargets(IsoChunk chunk, int stainLimit, int corpseLimit) {
        if (chunk == null) return null;
        int sLimit = stainLimit > 0 ? stainLimit : 64;
        int cLimit = corpseLimit > 0 ? corpseLimit : 0;
        KahluaTable stains = table();
        KahluaTable corpses = table();
        int stainsFound = 0;
        int[] corpsesFound = {0};
        boolean blood = Core.getInstance().getOptionBloodDecals() != 0;

        for (int z = 0; z < 8; z++) {
            IsoGridSquare[] squares;
            try {
                squares = chunk.getSquaresForLevel(z);
            } catch (RuntimeException ignored) {
                continue;
            }
            if (squares == null) continue;
            for (IsoGridSquare square : squares) {
                if (square == null) continue;
                if (stainsFound < sLimit && stainsHere(square, blood)) {
                    addPoint(stains, ++stainsFound, square);
                }
                if (corpsesFound[0] < cLimit) addCorpses(corpses, corpsesFound, cLimit, square);
                if (stainsFound >= sLimit && corpsesFound[0] >= cLimit) {
                    KahluaTable done = table();
                    done.rawset("stains", stains);
                    done.rawset("corpses", corpses);
                    return done;
                }
            }
        }
        KahluaTable result = table();
        result.rawset("stains", stains);
        result.rawset("corpses", corpses);
        return result;
    }

    /**
     * Frame-bounded variant of scanChunkTargets: visits only [startLevel,
     * startLevel+levelCount) z-levels, i.e. at most 2*64 squares per call.
     * The Lua side pins the chunk and accumulates targets across slices.
     */
    public static KahluaTable scanChunkTargetsSlice(IsoChunk chunk, int startLevel,
            int levelCount, int stainLimit, int corpseLimit) {
        if (chunk == null) return null;
        KahluaTable stains = table();
        KahluaTable corpses = table();
        int sLimit = stainLimit > 0 ? stainLimit : 64;
        int cLimit = corpseLimit > 0 ? corpseLimit : 0;
        int stainsFound = 0;
        int[] corpsesFound = {0};
        boolean blood = Core.getInstance().getOptionBloodDecals() != 0;
        int levels = levelCount > 0 ? Math.min(levelCount, 8) : 2;
        int first = Math.max(0, startLevel);
        int end = Math.min(8, first + levels);

        for (int z = first; z < end; z++) {
            IsoGridSquare[] squares;
            try {
                squares = chunk.getSquaresForLevel(z);
            } catch (RuntimeException ignored) {
                continue;
            }
            if (squares == null) continue;
            for (IsoGridSquare square : squares) {
                if (square == null) continue;
                if (stainsFound < sLimit && stainsHere(square, blood)) {
                    addPoint(stains, ++stainsFound, square);
                }
                if (corpsesFound[0] < cLimit) addCorpses(corpses, corpsesFound, cLimit, square);
                if (stainsFound >= sLimit && corpsesFound[0] >= cLimit) break;
            }
            if (stainsFound >= sLimit && corpsesFound[0] >= cLimit) break;
        }

        KahluaTable result = table();
        result.rawset("stains", stains);
        result.rawset("corpses", corpses);
        return result;
    }

    public static boolean squareHasStains(IsoGridSquare square) {
        if (square == null) return false;
        return stainsHere(square, Core.getInstance().getOptionBloodDecals() != 0);
    }

    public static KahluaTable scanChunkTrees(IsoChunk chunk, int maxCount) {
        if (chunk == null) return null;
        int limit = maxCount > 0 ? maxCount : 32;
        KahluaTable list = table();
        int count = 0;

        for (int z = 0; z < 8; z++) {
            IsoGridSquare[] squares;
            try {
                squares = chunk.getSquaresForLevel(z);
            } catch (RuntimeException ignored) {
                continue;
            }
            if (squares == null) continue;
            for (IsoGridSquare square : squares) {
                if (square == null || square.getTree() == null) continue;
                addPoint(list, ++count, square);
                if (count >= limit) return list;
            }
        }
        return list;
    }

    public static boolean squareHasTree(IsoGridSquare square) {
        return square != null && square.getTree() != null;
    }
}
