package emberroutes.probe;

import java.lang.reflect.Modifier;
import java.util.Arrays;
import java.util.Set;
import java.util.TreeSet;

/** Metadata only: does not initialize the runtime, spawn bodies or start a world. */
public final class ProbeBridgeSurfaceTest {
    /**
     * Frozen Lua bridge: name | declared return type | ordered parameter types.
     * Every public static ProbeRuntime method is pinned here; the field names,
     * overload count and internal logging visibility are checked as well.
     */
    private static final String SIGNATURES = """
        acquireBodyControl|java.lang.String|zombie.characters.IsoPlayer|java.lang.String|double
        actionCarrier|zombie.characters.IsoPlayer|zombie.characters.IsoPlayer
        armSaveReceipt|boolean
        bedPoseReady|boolean|zombie.characters.IsoPlayer|java.lang.String
        begin|java.lang.String|boolean
        bindingValid|boolean|zombie.characters.IsoPlayer|java.lang.String
        blockAllCheckpoints|java.lang.String|java.lang.String
        blockCheckpoint|java.lang.String|java.lang.String
        bodyStopMask|int|zombie.characters.IsoPlayer|java.lang.String
        cachedModData|se.krka.kahlua.vm.KahluaTable|java.lang.String
        cadenceIs15Hz|boolean
        cadenceIs1Hz|boolean
        cadenceIs5Hz|boolean
        cadenceIs60Hz|boolean
        captureCheckpointFor|java.lang.String|java.lang.String|java.lang.String|boolean|double|double|double
        carrierActive|boolean|zombie.characters.IsoPlayer
        carrierFor|zombie.characters.IsoPlayer|java.lang.String|zombie.characters.IsoPlayer
        carrierId|java.lang.String|zombie.characters.IsoPlayer
        carrierPresent|boolean|zombie.characters.IsoPlayer
        checkpointHasHome|boolean
        checkpointHomeX|double
        checkpointHomeY|double
        checkpointHomeZ|double
        checkpointMode|java.lang.String
        claimsCommand|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable|java.lang.String|se.krka.kahlua.vm.KahluaTable
        cleaningScanCorpses|se.krka.kahlua.vm.KahluaTable|zombie.iso.IsoChunk|int
        cleaningScanStains|se.krka.kahlua.vm.KahluaTable|zombie.iso.IsoChunk|int
        cleaningScanTargets|se.krka.kahlua.vm.KahluaTable|zombie.iso.IsoChunk|int|int
        cleaningScanTargetsSlice|se.krka.kahlua.vm.KahluaTable|zombie.iso.IsoChunk|int|int|int|int
        cleaningSquareHasStains|boolean|zombie.iso.IsoGridSquare
        clearForSave|java.lang.String
        command|java.lang.String|java.lang.String|zombie.characters.IsoPlayer|double|double|double
        commandFor|java.lang.String|java.lang.String|java.lang.String|zombie.characters.IsoPlayer|double|double|double
        controlledCarrier|zombie.characters.IsoPlayer|zombie.characters.IsoPlayer
        deliveryReceived|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable
        deliverySelectSlice|se.krka.kahlua.vm.KahluaTable|zombie.inventory.ItemContainer|zombie.characters.IsoGameCharacter|java.lang.String|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable|int
        diagnosticTimeNanos|double
        dispatchChoose|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable
        floorSleepSafe|boolean|zombie.characters.IsoPlayer|int|int|int
        followMetrics|se.krka.kahlua.vm.KahluaTable
        followWithControl|java.lang.String|zombie.characters.IsoPlayer|java.lang.String|zombie.characters.IsoPlayer|double
        freezeBodyControl|boolean
        furniturePoseWithControl|boolean|zombie.characters.IsoPlayer|java.lang.String|zombie.iso.IsoObject|java.lang.String
        getPortraitTexture|zombie.core.textures.Texture|zombie.characters.IsoGameCharacter
        inventoryIndex|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable
        inventoryIndexBegin|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable
        inventoryIndexStep|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable|int
        inventoryReadSlice|se.krka.kahlua.vm.KahluaTable|zombie.inventory.ItemContainer|java.util.ArrayList|int|int|int
        jobDataCopy|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable
        laborCancel|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable|java.lang.Object|java.lang.Object|java.lang.Object|java.lang.Object|java.lang.Object
        laborCreate|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable|java.lang.Object|se.krka.kahlua.vm.KahluaTable|java.lang.Object
        laborCustody|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable|java.lang.Object
        laborMutate|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable|java.lang.Object|java.lang.Object|java.lang.Object|java.lang.Object|java.lang.Object
        laborTransfer|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable|java.lang.Object|java.lang.Object|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable|java.lang.Object
        lumberjackScanTrees|se.krka.kahlua.vm.KahluaTable|zombie.iso.IsoChunk|int
        macroReachable|boolean|zombie.iso.IsoGridSquare|zombie.iso.IsoGridSquare
        motionResult|java.lang.String|zombie.characters.IsoPlayer
        moveBedWithControl|java.lang.String|zombie.characters.IsoPlayer|java.lang.String|zombie.iso.IsoObject|se.krka.kahlua.vm.KahluaTable
        moveCorpseWithControl|java.lang.String|zombie.characters.IsoPlayer|java.lang.String|zombie.iso.objects.IsoDeadBody
        moveSeatWithControl|java.lang.String|zombie.characters.IsoPlayer|java.lang.String|zombie.iso.IsoObject|double
        moveSleepSeatWithControl|java.lang.String|zombie.characters.IsoPlayer|java.lang.String|zombie.iso.IsoObject
        moveWithControl|java.lang.String|zombie.characters.IsoPlayer|java.lang.String|zombie.characters.IsoPlayer|double|double|double
        nativeActionFinished|boolean|zombie.characters.IsoPlayer
        nativeActionRunning|boolean|zombie.characters.IsoPlayer
        nativeActionStart|boolean|zombie.characters.IsoPlayer|java.lang.String|int|boolean
        nativeActionStop|void|zombie.characters.IsoPlayer
        observerSample|se.krka.kahlua.vm.KahluaTable|zombie.characters.IsoPlayer
        ownedCarrierId|java.lang.String|zombie.characters.IsoPlayer
        planningWakeCapture|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable|java.lang.Object|se.krka.kahlua.vm.KahluaTable
        planningWakeChanged|boolean|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable
        planningWakeContainerChanged|void|se.krka.kahlua.vm.KahluaTable|java.lang.Object
        planningWakeLoad|void|se.krka.kahlua.vm.KahluaTable|java.lang.Object
        planningWakeNew|se.krka.kahlua.vm.KahluaTable
        planningWakeRevision|double|se.krka.kahlua.vm.KahluaTable
        planningWakeScopeChanged|void|se.krka.kahlua.vm.KahluaTable|java.lang.Object
        productionYieldIds|se.krka.kahlua.vm.KahluaTable|se.krka.kahlua.vm.KahluaTable
        reachedSeat|zombie.iso.IsoObject|zombie.characters.IsoPlayer
        recipeHasCallbacks|boolean|zombie.scripting.entity.components.crafting.CraftRecipe
        recipeHasSpecialOutputs|boolean|zombie.scripting.entity.components.crafting.CraftRecipe
        recipeKey|java.lang.String|zombie.scripting.entity.components.crafting.CraftRecipe
        releaseBodyControl|boolean|zombie.characters.IsoPlayer|java.lang.String
        removeIdleCarrier|java.lang.String|java.lang.String|zombie.characters.IsoPlayer|zombie.characters.IsoPlayer
        reportCheckpoint|java.lang.String
        reposeAtWithControl|boolean|zombie.characters.IsoPlayer|java.lang.String|java.lang.String|zombie.iso.IsoObject|java.lang.String
        reposeWithControl|boolean|zombie.characters.IsoPlayer|java.lang.String|java.lang.String|boolean
        reset|java.lang.String
        resolveInteractionTile|se.krka.kahlua.vm.KahluaTable|zombie.iso.IsoGridSquare|zombie.characters.IsoPlayer|se.krka.kahlua.vm.KahluaTable
        restoreCheckpoint|java.lang.String|zombie.characters.IsoPlayer
        restoreCheckpointFor|java.lang.String|java.lang.String|zombie.characters.IsoPlayer
        retireBodyControl|boolean
        retirementTick|void
        retryStandExitWithControl|boolean|zombie.characters.IsoPlayer|java.lang.String
        saveBodyReady|boolean|java.lang.String|zombie.characters.IsoPlayer
        saveCheckpoint|java.lang.String|java.lang.String|boolean|double|double|double
        saveCheckpointFor|java.lang.String|java.lang.String|java.lang.String|boolean|double|double|double
        selectCarrier|boolean|java.lang.String
        selectedId|java.lang.String
        socialVisible|boolean|zombie.characters.IsoPlayer|zombie.characters.IsoPlayer
        spawnAdditional|java.lang.String|zombie.characters.IsoPlayer|double|double|double
        stopCarrier|boolean|zombie.characters.IsoPlayer
        stopWithControl|boolean|zombie.characters.IsoPlayer|java.lang.String
        thawBodyControl|boolean
        tick|void
        verifySaveReceipt|boolean
        version|java.lang.String
        warehouseApplyContainer|se.krka.kahlua.vm.KahluaTable|java.lang.String|se.krka.kahlua.vm.KahluaTable
        warehouseFastScan|se.krka.kahlua.vm.KahluaTable|java.lang.String|se.krka.kahlua.vm.KahluaTable|boolean
        warehouseHasType|boolean|java.lang.String|java.lang.String
        warehouseMountSettlement|se.krka.kahlua.vm.KahluaTable|java.lang.String|se.krka.kahlua.vm.KahluaTable
        warehouseResetCache|void|java.lang.String
        warehouseTickDue|boolean|java.lang.String|boolean
        warehouseTypeCount|double|java.lang.String|java.lang.String
        warehouseUnmountContainer|se.krka.kahlua.vm.KahluaTable|java.lang.String|java.lang.String
        waterSourceBacking|se.krka.kahlua.vm.KahluaTable|zombie.iso.IsoObject
        workFreeCarry|double|zombie.characters.IsoGameCharacter
        workItemEligible|java.lang.Boolean|zombie.inventory.InventoryItem
        workerCount|int
        workerDecisionWindow|se.krka.kahlua.vm.KahluaTable|int|int
        workerIdAt|java.lang.String|int
        """;

    public static void main(String[] args) throws Exception {
        Class<?> runtime = Class.forName("emberroutes.probe.ProbeRuntime", false,
                ClassLoader.getSystemClassLoader());
        Set<String> expected = new TreeSet<>();
        String[] signatures = SIGNATURES.strip().split("\\R");
        if (signatures.length != 119)
            throw new AssertionError("invalid contract fixture: " + signatures.length + " signatures");
        for (String signature : signatures) {
            String[] parts = signature.trim().split("\\|");
            if (parts.length < 2 || !expected.add(parts[0]))
                throw new AssertionError("invalid/duplicate fixture signature: " + signature);
            Class<?>[] parameters = new Class<?>[parts.length - 2];
            for (int i = 2; i < parts.length; i++) parameters[i - 2] = type(parts[i], runtime);
            var method = method(runtime, parts[0], parameters, signature);
            if (!Modifier.isPublic(method.getModifiers()) || !Modifier.isStatic(method.getModifiers()))
                throw new AssertionError("bridge entry must remain public static: " + method);
            if (!method.getReturnType().getName().equals(parts[1]))
                throw new AssertionError("bridge return type changed: " + method + "; expected " + parts[1]);
        }
        Set<String> actual = new TreeSet<>();
        for (var method : runtime.getDeclaredMethods()) {
            if (Modifier.isPublic(method.getModifiers()) && Modifier.isStatic(method.getModifiers())) {
                if (!actual.add(method.getName())) throw new AssertionError("unexpected bridge overload: " + method);
            }
        }
        if (!actual.equals(expected)) {
            Set<String> missing = new TreeSet<>(expected); missing.removeAll(actual);
            Set<String> extra = new TreeSet<>(actual); extra.removeAll(expected);
            throw new AssertionError("bridge contract changed: missing=" + missing + "; extra=" + extra);
        }
        var log = runtime.getDeclaredMethod("log", String.class);
        if (Modifier.isPublic(log.getModifiers()) || Modifier.isPrivate(log.getModifiers())
                || Modifier.isProtected(log.getModifiers()) || !Modifier.isStatic(log.getModifiers()))
            throw new AssertionError("internal Java logging must remain package-visible static");
        for (var method : runtime.getDeclaredMethods())
            if (method.getName().equals("lumberjackSquareHasTree"))
                throw new AssertionError("unused bridge forwarding method retained");
        System.out.println("PASS " + expected.size()
                + " complete Lua bridge signatures; metadata only, game NOT RUN");
    }

    private static java.lang.reflect.Method method(Class<?> runtime, String name,
                                                   Class<?>[] parameters, String signature) {
        try {
            return runtime.getDeclaredMethod(name, parameters);
        } catch (NoSuchMethodException e) {
            throw new AssertionError("bridge signature changed or removed: " + signature, e);
        }
    }

    private static Class<?> type(String name, Class<?> runtime) throws ClassNotFoundException {
        return switch (name) {
            case "boolean" -> boolean.class;
            case "byte" -> byte.class;
            case "char" -> char.class;
            case "short" -> short.class;
            case "int" -> int.class;
            case "long" -> long.class;
            case "float" -> float.class;
            case "double" -> double.class;
            default -> Class.forName(name, false, runtime.getClassLoader());
        };
    }
}
