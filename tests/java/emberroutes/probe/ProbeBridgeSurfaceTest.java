package emberroutes.probe;

import java.lang.reflect.Modifier;
import java.util.Arrays;
import java.util.Set;
import java.util.TreeSet;

/** Metadata only: does not initialize the runtime, spawn bodies or start a world. */
public final class ProbeBridgeSurfaceTest {
    private static final String CONTRACT = """
        acquireBodyControl actionCarrier armSaveReceipt bedPoseReady begin bindingValid
        blockAllCheckpoints blockCheckpoint bodyStopMask cachedModData captureCheckpointFor
        carrierActive carrierFor carrierId carrierPresent checkpointHasHome checkpointHomeX
        checkpointHomeY checkpointHomeZ checkpointMode cleaningScanCorpses cleaningScanStains
        cleaningSquareHasStains clearForSave command commandFor controlledCarrier deliveryReceived
        deliverySelectSlice diagnosticTimeNanos dispatchChoose floorSleepSafe freezeBodyControl
        furniturePoseWithControl getPortraitTexture inventoryIndex inventoryIndexBegin inventoryIndexStep
        inventoryReadSlice jobDataCopy laborCancel laborCreate laborMutate lumberjackScanTrees
        motionResult moveBedWithControl moveCorpseWithControl moveSeatWithControl moveSleepSeatWithControl
        moveWithControl observerSample ownedCarrierId planningWakeCapture planningWakeChanged
        planningWakeContainerChanged planningWakeLoad planningWakeNew planningWakeRevision
        planningWakeScopeChanged reachedSeat recipeHasCallbacks recipeHasSpecialOutputs recipeKey
        releaseBodyControl removeIdleCarrier reportCheckpoint reposeAtWithControl reposeWithControl
        reset restoreCheckpoint restoreCheckpointFor retireBodyControl retirementTick saveBodyReady
        saveCheckpoint saveCheckpointFor selectCarrier selectedId socialVisible spawnAdditional
        stopCarrier stopWithControl thawBodyControl tick verifySaveReceipt version warehouseFastScan
        warehouseResetCache waterSourceBacking workFreeCarry workItemEligible workerCount
        workerDecisionWindow workerIdAt
        """;

    public static void main(String[] args) throws Exception {
        Set<String> expected = new TreeSet<>(Arrays.asList(CONTRACT.trim().split("\\s+")));
        if (expected.size() != 94) throw new AssertionError("invalid contract fixture");
        Class<?> runtime = Class.forName("emberroutes.probe.ProbeRuntime", false,
                ClassLoader.getSystemClassLoader());
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
        System.out.println("PASS 94 public bridge methods; dynamic kernel entries retained; metadata only, game NOT RUN");
    }
}
