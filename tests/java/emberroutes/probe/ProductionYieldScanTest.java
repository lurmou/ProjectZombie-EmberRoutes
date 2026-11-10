package emberroutes.probe;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.JavaFunction;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaThread;

/**
 * Differential parity: ProductionYieldScan.yieldIds against the real Lua
 * ProductionYield.assetFree, executed by the installed Kahlua on the real
 * Lua source. No game objects, no world, no save. Every case feeds the same
 * record table to both sides and requires the same boolean; the full scan
 * additionally requires the same sorted id list (Lua reference order is an
 * insertion sort over Kahlua's own {@code <}, since this harness has no
 * stdlib table.sort).
 */
public final class ProductionYieldScanTest {
    private static int checks;
    private static final J2SEPlatform P = J2SEPlatform.getInstance();
    private static KahluaThread thread;
    private static Object assetFreeFn;

    private static KahluaTable table() { return P.newTable(); }

    private static void check(boolean ok, String why) { checks++; if (!ok) throw new AssertionError(why); }

    /** Real Lua predicate result; null when Lua itself raises (malformed input). */
    private static String lastLuaError;
    private static Boolean luaAssetFree(KahluaTable record) throws Exception {
        Object[] result = thread.pcall(assetFreeFn, new Object[]{record});
        if (!Boolean.TRUE.equals(result[0])) { lastLuaError = String.valueOf(result[1]); return null; }
        return (Boolean) result[1];
    }

    private static void parity(KahluaTable record, String label) throws Exception {
        Boolean lua = luaAssetFree(record);
        boolean java = ProductionYieldScan.assetFree(record);
        check(lua != null, label + ": Lua raised unexpectedly: " + lastLuaError);
        check(lua.booleanValue() == java, label + ": Lua=" + lua + " Java=" + java);
    }

    /** One valid asset-free record; each case mutates a copy of this shape. */
    private static KahluaTable validRecord() {
        KahluaTable r = table();
        r.rawset("format", 4.0);
        KahluaTable yield = table();
        yield.rawset("kind", "MANUAL");
        yield.rawset("cleared", Boolean.TRUE);
        r.rawset("activityYield", yield);
        for (String field : new String[]{"materials", "tools", "outputs", "held"}) r.rawset(field, table());
        KahluaTable goal = table();
        goal.rawset("recipeId", "Base.SawLogs");
        goal.rawset("recipeName", "Saw Logs");
        goal.rawset("product", "Base.Plank");
        goal.rawset("signature", "sig");
        goal.rawset("requested", 9.0);
        goal.rawset("target", 9.0);
        goal.rawset("unitYield", 3.0);
        KahluaTable continuation = table();
        continuation.rawset("format", 1.0);
        continuation.rawset("goal", goal);
        continuation.rawset("delivered", 3.0);
        continuation.rawset("resumeEpoch", 7.0);
        continuation.rawset("membershipRevision", 2.0);
        r.rawset("activityContinuation", continuation);
        return r;
    }

    private static KahluaTable with(KahluaTable record, String key, Object value) {
        record.rawset(key, value);
        return record;
    }

    public static void main(String[] args) throws Exception {
        KahluaTable env = P.newTable();
        env.rawset("_G", env);
        se.krka.kahlua.stdlib.BaseLib.register(env);
        se.krka.kahlua.stdlib.StringLib.register(P, env);
        se.krka.kahlua.stdlib.TableLib.register(P, env);
        se.krka.kahlua.j2se.MathLib.register(P, env);
        // This Kahlua build leaves pairs/ipairs to stdlib.lua (as in the game);
        // the harness provides the same generic-for protocol on top of the
        // installed table iterator. Pairs order is unspecified on both sides
        // and no assertion below depends on it.
        env.rawset("pairs", (JavaFunction) (frame, n) -> {
            KahluaTable subject = (KahluaTable) frame.get(0);
            se.krka.kahlua.vm.KahluaTableIterator it = subject.iterator();
            JavaFunction next = (f2, n2) -> {
                if (!it.advance()) return 0;
                f2.push(it.getKey());
                f2.push(it.getValue());
                return 2;
            };
            frame.push(next);
            frame.push(subject);
            return 2;
        });
        env.rawset("ipairs", (JavaFunction) (frame, n) -> {
            KahluaTable subject = (KahluaTable) frame.get(0);
            JavaFunction iter = (f2, n2) -> {
                Object control = f2.get(1);
                int i = control == null ? 0 : (int) ((Number) control).doubleValue();
                Object value = subject.rawget(i + 1);
                if (value == null) return 0;
                f2.push((double) (i + 1));
                f2.push(value);
                return 2;
            };
            frame.push(iter);
            frame.push(subject);
            frame.push(0.0);
            return 3;
        });
        thread = new KahluaThread(P, env);
        thread.debugOwnerThread = Thread.currentThread();
        se.krka.kahlua.vm.KahluaUtil.setWorkerThread(env, thread);
        String source = Files.readString(Path.of(
                "Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/Crafting/ProductionYield.lua"),
                StandardCharsets.UTF_8);
        Object module = thread.call(LuaCompiler.loadstring(source, "ProductionYield", env), new Object[0]);
        assetFreeFn = ((KahluaTable) module).rawget("assetFree");

        parity(validRecord(), "valid record is asset-free");
        parity(with(validRecord(), "format", 3.0), "format 3 rejected");
        parity(with(validRecord(), "format", "4"), "format string rejected");
        parity(with(validRecord(), "uncertain", Boolean.TRUE), "uncertain rejected");
        parity(with(validRecord(), "uncertain", Boolean.FALSE), "uncertain false kept");
        parity(with(validRecord(), "uncertain", 0.0), "uncertain zero is truthy in Lua, rejected");
        parity(with(validRecord(), "activityYield", null), "missing yield rejected");
        parity(with(validRecord(), "activityYield", "MANUAL"), "non-table yield rejected");
        KahluaTable kind = validRecord();
        ((KahluaTable) kind.rawget("activityYield")).rawset("kind", "PUBLIC");
        parity(kind, "PUBLIC yield rejected");
        KahluaTable cleared = validRecord();
        ((KahluaTable) cleared.rawget("activityYield")).rawset("cleared", Boolean.FALSE);
        parity(cleared, "uncleared yield rejected");
        KahluaTable clearedNum = validRecord();
        ((KahluaTable) clearedNum.rawget("activityYield")).rawset("cleared", 1.0);
        parity(clearedNum, "cleared must be boolean true, not 1");
        parity(with(validRecord(), "unitMade", Boolean.TRUE), "unit made rejected");
        parity(with(validRecord(), "unitMade", 1.0), "unitMade 1 is not true, kept");
        KahluaTable busy = validRecord();
        KahluaTable materials = table();
        materials.rawset("log", 1.0);
        busy.rawset("materials", materials);
        parity(busy, "held materials rejected");
        KahluaTable busyTools = validRecord();
        KahluaTable tools = table();
        tools.rawset("saw", 1.0);
        busyTools.rawset("tools", tools);
        parity(busyTools, "held tools rejected");
        parity(with(validRecord(), "activityContinuation", null), "missing continuation rejected");
        KahluaTable contFormat = validRecord();
        ((KahluaTable) contFormat.rawget("activityContinuation")).rawset("format", 2.0);
        parity(contFormat, "continuation format 2 rejected");
        KahluaTable noGoal = validRecord();
        ((KahluaTable) noGoal.rawget("activityContinuation")).rawset("goal", null);
        parity(noGoal, "missing goal rejected");
        KahluaTable goalNum = validRecord();
        ((KahluaTable) ((KahluaTable) goalNum.rawget("activityContinuation")).rawget("goal")).rawset("recipeId", 123.0);
        parity(goalNum, "numeric recipeId rejected");
        KahluaTable goalReq0 = validRecord();
        ((KahluaTable) ((KahluaTable) goalReq0.rawget("activityContinuation")).rawget("goal")).rawset("requested", 0.0);
        parity(goalReq0, "requested zero rejected");
        KahluaTable goalReqBig = validRecord();
        ((KahluaTable) ((KahluaTable) goalReqBig.rawget("activityContinuation")).rawget("goal")).rawset("requested", 10000.0);
        parity(goalReqBig, "requested over 9999 rejected");
        KahluaTable goalTargetSmall = validRecord();
        ((KahluaTable) ((KahluaTable) goalTargetSmall.rawget("activityContinuation")).rawget("goal")).rawset("target", 8.0);
        parity(goalTargetSmall, "target below requested rejected");
        KahluaTable goalTargetBig = validRecord();
        ((KahluaTable) ((KahluaTable) goalTargetBig.rawget("activityContinuation")).rawget("goal")).rawset("target", 10031.0);
        parity(goalTargetBig, "target over 10030 rejected");
        KahluaTable goalYield0 = validRecord();
        ((KahluaTable) ((KahluaTable) goalYield0.rawget("activityContinuation")).rawget("goal")).rawset("unitYield", 0.0);
        parity(goalYield0, "unitYield zero rejected");
        KahluaTable goalYieldBig = validRecord();
        ((KahluaTable) ((KahluaTable) goalYieldBig.rawget("activityContinuation")).rawget("goal")).rawset("unitYield", 33.0);
        parity(goalYieldBig, "unitYield over 32 rejected");
        KahluaTable half = validRecord();
        ((KahluaTable) half.rawget("activityContinuation")).rawset("delivered", 3.5);
        parity(half, "fractional delivered rejected");
        KahluaTable over = validRecord();
        ((KahluaTable) over.rawget("activityContinuation")).rawset("delivered", 10.0);
        parity(over, "delivered over target rejected");
        KahluaTable nan = validRecord();
        ((KahluaTable) nan.rawget("activityContinuation")).rawset("delivered", Double.NaN);
        parity(nan, "NaN delivered rejected");
        KahluaTable epochFrac = validRecord();
        ((KahluaTable) epochFrac.rawget("activityContinuation")).rawset("resumeEpoch", 0.5);
        parity(epochFrac, "fractional epoch rejected");
        KahluaTable epochMax = validRecord();
        ((KahluaTable) epochMax.rawget("activityContinuation")).rawset("resumeEpoch", 9007199254740000.0);
        parity(epochMax, "epoch at 2^53 bound kept");
        KahluaTable epochOver = validRecord();
        ((KahluaTable) epochOver.rawget("activityContinuation")).rawset("resumeEpoch", 9007199254740992.0);
        parity(epochOver, "epoch over 2^53 bound rejected");
        KahluaTable member0 = validRecord();
        ((KahluaTable) member0.rawget("activityContinuation")).rawset("membershipRevision", 0.0);
        parity(member0, "membershipRevision zero rejected");
        KahluaTable memberStr = validRecord();
        ((KahluaTable) memberStr.rawget("activityContinuation")).rawset("membershipRevision", "2");
        parity(memberStr, "string membershipRevision rejected");

        // Malformed asset field: Lua pairs() raises; Java fails closed instead
        // of aborting the scan. Divergence is intentional and documented on
        // ProductionYieldScan; production records always carry tables here.
        KahluaTable malformed = validRecord();
        malformed.rawset("materials", "not-a-table");
        check(luaAssetFree(malformed) == null, "malformed assets raise in Lua");
        check(!ProductionYieldScan.assetFree(malformed), "malformed assets fail closed in Java");

        // Full scan: same mixed map through Java and through the Lua loop+sort.
        KahluaTable crafts = table();
        crafts.rawset("npc-2", validRecord());
        crafts.rawset("npc-10", validRecord());
        crafts.rawset("NPC-1", validRecord());
        crafts.rawset("npc-a", with(validRecord(), "uncertain", Boolean.TRUE));
        crafts.rawset("npc-A", validRecord());
        crafts.rawset("npc-1", validRecord());
        crafts.rawset("npc-", with(validRecord(), "format", 3.0));
        KahluaTable javaIds = ProductionYieldScan.yieldIds(crafts);
        String luaSort = """
                local Y, crafts = ...
                local ids = {}
                for id, r in pairs(crafts) do if Y.assetFree(r) then ids[#ids + 1] = id end end
                for i = 2, #ids do local v = ids[i] local j = i - 1
                    while j >= 1 and v < ids[j] do ids[j + 1] = ids[j] j = j - 1 end
                    ids[j + 1] = v end
                return ids
                """;
        Object[] luaResult = thread.pcall(
                LuaCompiler.loadstring(luaSort, "lua-yield-scan", env), new Object[]{module, crafts});
        check(Boolean.TRUE.equals(luaResult[0]), "Lua reference scan runs: " + luaResult[1]);
        KahluaTable luaIds = (KahluaTable) luaResult[1];
        check(javaIds.len() == luaIds.len(), "scan size matches: Java=" + javaIds.len() + " Lua=" + luaIds.len());
        for (int i = 1; i <= javaIds.len(); i++) {
            check(javaIds.rawget(i).equals(luaIds.rawget(i)),
                    "scan order matches at " + i + ": Java=" + javaIds.rawget(i) + " Lua=" + luaIds.rawget(i));
        }
        check(javaIds.len() == 5, "five asset-free ids expected");

        // Degenerate inputs never throw.
        check(ProductionYieldScan.yieldIds(null).len() == 0, "null crafts is an empty scan");
        check(ProductionYieldScan.yieldIds(table()).len() == 0, "empty crafts is an empty scan");
        KahluaTable weird = table();
        weird.rawset(1.0, validRecord());
        weird.rawset("npc-x", "not-a-record");
        check(ProductionYieldScan.yieldIds(weird).len() == 0, "non-string keys and non-table values skipped");

        // Bridge entry point forwards to the same kernel.
        KahluaTable bridged = ProbeRuntime.productionYieldIds(crafts);
        check(bridged.len() == javaIds.len() && bridged.rawget(1).equals(javaIds.rawget(1)),
                "productionYieldIds bridge returns the kernel result");
        System.out.println("PASS " + checks + " ProductionYieldScan parity checks; game NOT RUN");
    }
}
