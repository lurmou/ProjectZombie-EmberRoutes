package emberroutes.probe;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaTableIterator;

/**
 * Pure yield-scan kernel: the 1s Production.tickPending filter+sort, sunk from Lua.
 * Mirrors shared/EmberRoutesProbe/Crafting/ProductionYield.lua assetFree/continuation
 * field for field. Read-only; no state, no game API, no side effects.
 *
 * <p>Lua Production.tickPending keeps only the 1s cadence and the resume wiring;
 * the scan itself is one bridge call per second over the in-progress craft map
 * (BusinessJobs.crafts(): npcId -&gt; record), returning the asset-free ids sorted
 * exactly as Lua table.sort would. npcIds are ASCII stable ids, so Java natural
 * string ordering is the Lua lexicographic order for every id this scan sees.
 *
 * <p>Divergence notes (fail-closed, malformed input only -- production records
 * always carry tables here): a non-table asset field (materials/tools/outputs/
 * held) makes Lua pairs() raise; Java treats the record as not asset-free
 * instead, so one bad record can never abort the whole scan. A non-table
 * crafts value or a non-string key is likewise skipped, never thrown.
 */
public final class ProductionYieldScan {
    private ProductionYieldScan() {}
    /** 2^53, the Lua integer() bound used by ProductionYield.continuation/goalValid. */
    private static final double MAX_EPOCH = 9007199254740000.0;
    private static final String[] ASSET_FIELDS = {"materials", "tools", "outputs", "held"};

    /** Sorted asset-free npcIds from a crafts map, as a 1-based Lua array table. */
    public static KahluaTable yieldIds(KahluaTable crafts) {
        KahluaTable result = J2SEPlatform.getInstance().newTable();
        if (crafts == null) return result;
        List<String> ids = new ArrayList<>();
        KahluaTableIterator it = crafts.iterator();
        while (it.advance()) {
            Object key = it.getKey();
            Object value = it.getValue();
            if (key instanceof String id && value instanceof KahluaTable record && assetFree(record)) ids.add(id);
        }
        ids.sort(Comparator.naturalOrder());
        for (int i = 0; i < ids.size(); i++) result.rawset(i + 1, ids.get(i));
        return result;
    }

    /** ProductionYield.assetFree, verbatim: format 4, not uncertain, MANUAL yield cleared,
     *  unit not made, no assets held, live continuation. */
    static boolean assetFree(KahluaTable r) {
        if (!isNumber(r.rawget("format"), 4)) return false;
        Object uncertain = r.rawget("uncertain");
        if (uncertain != null && !Boolean.FALSE.equals(uncertain)) return false;
        Object yield = r.rawget("activityYield");
        if (!(yield instanceof KahluaTable y)) return false;
        if (!"MANUAL".equals(y.rawget("kind"))) return false;
        if (!Boolean.TRUE.equals(y.rawget("cleared"))) return false;
        if (Boolean.TRUE.equals(r.rawget("unitMade"))) return false;
        for (String field : ASSET_FIELDS) {
            Object assets = r.rawget(field);
            if (assets == null) continue;
            if (!(assets instanceof KahluaTable table) || !table.isEmpty()) return false;
        }
        Object continuation = r.rawget("activityContinuation");
        return continuation != null && continuation(continuation);
    }

    /** ProductionYield.continuation, verbatim (assetFree already rules out nil). */
    private static boolean continuation(Object value) {
        if (!(value instanceof KahluaTable c)) return false;
        if (!isNumber(c.rawget("format"), 1)) return false;
        Object goal = c.rawget("goal");
        if (!goalValid(goal)) return false;
        double target = number(((KahluaTable) goal).rawget("target"));
        if (!integer(c.rawget("delivered"), target)) return false;
        if (!integer(c.rawget("resumeEpoch"), MAX_EPOCH)) return false;
        if (!integer(c.rawget("membershipRevision"), MAX_EPOCH)) return false;
        return number(c.rawget("membershipRevision")) > 0;
    }

    /** ProductionYield.goalValid, verbatim: four string fields, bounded integer goal numbers. */
    private static boolean goalValid(Object value) {
        if (!(value instanceof KahluaTable g)) return false;
        for (String key : new String[]{"recipeId", "recipeName", "product", "signature"}) {
            if (!(g.rawget(key) instanceof String)) return false;
        }
        if (!integer(g.rawget("requested"), 9999)) return false;
        if (!(number(g.rawget("requested")) > 0)) return false;
        if (!integer(g.rawget("target"), 10030)) return false;
        if (!(number(g.rawget("target")) >= number(g.rawget("requested")))) return false;
        if (!integer(g.rawget("unitYield"), 32)) return false;
        return number(g.rawget("unitYield")) > 0;
    }

    /** ProductionYield.integer: a Lua number, not NaN, 0..max, whole. */
    private static boolean integer(Object value, double max) {
        if (!(value instanceof Number)) return false;
        double n = ((Number) value).doubleValue();
        return n == n && n >= 0 && n <= max && n == Math.floor(n);
    }

    private static boolean isNumber(Object value, double expected) {
        return value instanceof Number && ((Number) value).doubleValue() == expected;
    }

    private static double number(Object value) {
        return ((Number) value).doubleValue();
    }
}
