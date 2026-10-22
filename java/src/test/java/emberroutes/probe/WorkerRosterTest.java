package emberroutes.probe;

import java.io.IOException;
import java.util.*;

/** Pure coordination tests. No native body creation or game save/load is simulated. */
public final class WorkerRosterTest {
    private static int checks;
    public static void main(String[] args) throws Exception {
        WorkerRoster<String> roster=new WorkerRoster<>();
        for (int i=0;i<100;i++) roster.put("id"+i,"id"+i);
        var visited=new ArrayList<String>();
        for (int i=0;i<25;i++) check(roster.advance(4,visited::add)==4,"shared four-worker budget");
        check(new HashSet<>(visited).size()==100,"all workers receive fair service");
        check(roster.advance(0,v->{throw new AssertionError();})==0,"zero budget");
        roster.clear(); roster.put("a","a"); roster.put("b","b"); roster.put("c","c");
        visited.clear(); roster.advance(2,v->{visited.add(v);roster.remove(v);});
        check(visited.equals(List.of("a","b")) && roster.size()==1,"remove current never skips next worker");
        roster.put("c","updated"); visited.clear();
        check(roster.advance(8,visited::add)==1 && visited.equals(List.of("updated")),"replacement does not duplicate roster");
        var first=new ProbeSession<String>(); var second=new ProbeSession<String>();
        first.spawn(()->"A"); second.spawn(()->"B"); first.remove(v->{});
        check(first.get()==null && "B".equals(second.get()),"retiring one session preserves another");
        var ownership=new CheckpointOwnership(); ownership.accept("legacy",data("a",1)); ownership.accept("b",data("b",2));
        rejects(()->ownership.accept("c",data("c",1)),"cross-NPC duplicate item rejected");
        rejects(()->new CheckpointOwnership().accept("wrong",data("a",3)),"slot identity mismatch rejected");
        var duplicate=new CheckpointOwnership(); duplicate.accept("legacy",data("a",1));
        rejects(()->duplicate.accept("a",data("a",2)),"legacy/new duplicate NPC rejected");
        check(ProbeRules.allowedWorkerPoint(0,0,0,64,0,0),"worker route may exceed diagnostic range");
        check(!ProbeRules.allowedPoint(0,0,0,64,0,0),"manual diagnostic range retained");
        check(!ProbeRules.allowedWorkerPoint(0,0,0,257,0,0),"worker route has bounded radius");
        check(!ProbeRules.allowedWorkerPoint(0,0,0,Double.NaN,0,0),"worker target rejects NaN");
        check(!ProbeRules.allowedWorkerPoint(0,0,0,1,0,0.5),"worker landing requires integral floor");
        var movement=new ProbeMovement();
        movement.begin(100,0,0,0,120_000_000_000L);
        check(movement.tick(()->ProbeMovement.PathResult.WORKING,0,0,0,30_000_000_000L)==ProbeMovement.Outcome.MOVING,
            "long valid path not cut off by 20 second diagnostic deadline");
        check(movement.tick(()->ProbeMovement.PathResult.WORKING,0,0,0,120_000_000_000L)==ProbeMovement.Outcome.TIMEOUT,
            "distance timeout remains bounded");
        movement.begin(100,0,0,0,Long.MAX_VALUE);
        check(movement.tick(()->ProbeMovement.PathResult.WORKING,0,0,0,180_000_000_000L)==ProbeMovement.Outcome.TIMEOUT,
            "untrusted timeout cannot exceed three minutes");
        System.out.println("PASS "+checks+" worker roster/session/checkpoint ownership checks; game runtime NOT RUN");
    }
    private static ProbeCheckpoint.Data data(String id,int item) {
        return new ProbeCheckpoint.Data("world","a".repeat(64),249,id,1,1,0,"HOLD",false,0,0,0,
            List.of(new ProbeCheckpoint.Item(item,0,"Base.Pencil",1)),Map.of(),new byte[]{1});
    }
    private static void check(boolean value,String message) { checks++; if (!value) throw new AssertionError(message); }
    private interface Checked { void run() throws IOException; }
    private static void rejects(Checked test,String message) throws IOException {
        try { test.run(); } catch (IOException expected) { check(true,message); return; }
        throw new AssertionError(message);
    }
}
