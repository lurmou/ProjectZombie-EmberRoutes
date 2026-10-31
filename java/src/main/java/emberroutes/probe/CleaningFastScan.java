package emberroutes.probe;

import java.util.List;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.KahluaTable;
import zombie.iso.IsoChunk;
import zombie.iso.IsoGridSquare;
import zombie.iso.objects.IsoDeadBody;

/**
 * High-performance Java-native chunk scan for settlement cleaning and lumberjack operations.
 * Sinks square stain checks, dead body queries, and tree lookups to avoid crossing the
 * Lua-Kahlua JNI bridge per tile.
 */
public final class CleaningFastScan {
    private CleaningFastScan() {}

    private static KahluaTable table() {
        return J2SEPlatform.getInstance().newTable();
    }

    public static KahluaTable scanChunkStains(IsoChunk chunk, int maxCount) {
        if (chunk == null) return null;
        int limit = maxCount > 0 ? maxCount : 64;
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
                if (square != null && square.haveStains()) {
                    KahluaTable point = table();
                    point.rawset("x", Double.valueOf(square.getX()));
                    point.rawset("y", Double.valueOf(square.getY()));
                    point.rawset("z", Double.valueOf(square.getZ()));
                    count++;
                    list.rawset(Double.valueOf(count), point);
                    if (count >= limit) {
                        return list;
                    }
                }
            }
        }
        return list;
    }

    public static KahluaTable scanChunkCorpses(IsoChunk chunk, int maxCount) {
        if (chunk == null) return null;
        int limit = maxCount > 0 ? maxCount : 16;
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
                if (square == null) continue;
                List<IsoDeadBody> bodies = square.getDeadBodys();
                if (bodies != null && !bodies.isEmpty()) {
                    for (IsoDeadBody body : bodies) {
                        if (body != null) {
                            KahluaTable entry = table();
                            entry.rawset("x", Double.valueOf(square.getX()));
                            entry.rawset("y", Double.valueOf(square.getY()));
                            entry.rawset("z", Double.valueOf(square.getZ()));
                            entry.rawset("body", body);
                            count++;
                            list.rawset(Double.valueOf(count), entry);
                            if (count >= limit) {
                                return list;
                            }
                        }
                    }
                }
            }
        }
        return list;
    }

    public static boolean squareHasStains(IsoGridSquare square) {
        return square != null && square.haveStains();
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
                if (square != null && square.getTree() != null) {
                    KahluaTable point = table();
                    point.rawset("x", Double.valueOf(square.getX()));
                    point.rawset("y", Double.valueOf(square.getY()));
                    point.rawset("z", Double.valueOf(square.getZ()));
                    count++;
                    list.rawset(Double.valueOf(count), point);
                    if (count >= limit) {
                        return list;
                    }
                }
            }
        }
        return list;
    }

    public static boolean squareHasTree(IsoGridSquare square) {
        return square != null && square.getTree() != null;
    }
}
