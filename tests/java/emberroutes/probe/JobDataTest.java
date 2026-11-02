package emberroutes.probe;

import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.*;

/** Installed Kahlua data contract; never starts the game or allocates an NPC. */
public final class JobDataTest {
    private static int count;
    private static final J2SEPlatform P=J2SEPlatform.getInstance();
    public static void main(String[] args) throws Exception {
	KahluaTable source=P.newTable(),shared=P.newTable(); shared.rawset("value",2.0);
	source.rawset("a",shared); source.rawset("b",shared); source.rawset("flag",false);
	source.rawset(0,"zero"); source.rawset("text","中文😀");
	KahluaTable result=JobData.copy(source);
	check(result!=source && result.rawget("a")!=shared,"detached tables");
	check(result.rawget("a")!=result.rawget("b"),"shared children are copied separately, as Lua did");
	check(Boolean.FALSE.equals(result.rawget("flag")) && "zero".equals(result.rawget(0)),"false and numeric zero key preserved");
	shared.rawset("value",3.0); check(Double.valueOf(2).equals(((KahluaTable)result.rawget("a")).rawget("value")),"caller mutation isolated");
	KahluaTable env=P.newTable(); env.rawset("text","中文😀"); KahluaThread thread=new KahluaThread(P,env);
	Object len=thread.call(LuaCompiler.loadstring("return #text","length",env),new Object[0]);
	check(Double.valueOf(4).equals(len),"installed Lua string length is Java UTF-16 length");
	source.rawset("text","中".repeat(16384)); JobData.copy(source); count++;
	source.rawset("text","中".repeat(16385)); rejects(source,"JOB_DATA_LIMIT"); source.rawset("text",null);
	for (Object value:new Object[]{Double.NaN,Double.POSITIVE_INFINITY,new Object(),(JavaFunction)(f,n)->0}) {
	    source.rawset("bad",value); rejects(source,"JOB_DATA_UNSERIALIZABLE");
	}
	source.rawset("bad",source); rejects(source,"JOB_DATA_UNSERIALIZABLE"); source.rawset("bad",null);
	for (Object key:new Object[]{true,-1.0,0.5}) {
	    KahluaTable bad=P.newTable(); bad.rawset(key,"x"); rejects(bad,"JOB_KEY_INVALID");
	}
	KahluaTable depth=P.newTable(),cursor=depth;
	for (int i=0;i<16;i++) { KahluaTable child=P.newTable();cursor.rawset("child",child);cursor=child; }
	JobData.copy(depth);count++;cursor.rawset("overflow",true);rejects(depth,"JOB_DATA_LIMIT");
	KahluaTable width=P.newTable(); for (int i=1;i<=8191;i++) width.rawset(i,Boolean.TRUE);
	JobData.copy(width);count++;width.rawset(8192,Boolean.TRUE);rejects(width,"JOB_DATA_LIMIT");
	System.out.println("PASS "+count+" installed Kahlua JobData contract checks; game NOT RUN");
    }
    private static void check(boolean value,String label) { count++;if (!value) throw new AssertionError(label); }
    private static void rejects(KahluaTable source,String reason) {
	try {JobData.copy(source);} catch (IllegalArgumentException expected) {
	    check(reason.equals(expected.getMessage()),reason);return;
	}
	throw new AssertionError("expected "+reason);
    }
}
