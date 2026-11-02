package emberroutes.probe;

import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.KahluaTable;

/** Real Kahlua data structures; no game objects, replica scheduler or task simulation. */
public final class DispatchKernelTest {
    private static int checks;
    private static KahluaTable table() {return J2SEPlatform.getInstance().newTable();}
    private static void check(boolean ok,String why) {checks++;if(!ok)throw new AssertionError(why);}
    public static void main(String[] args) {
	var candidates=table();var a=table();a.rawset("key","b");a.rawset("category","work");a.rawset("allowed",true);
	var b=table();b.rawset("key","a");b.rawset("category","work");b.rawset("allowed",true);
	candidates.rawset(1,a);candidates.rawset(2,b);var priorities=table();priorities.rawset("work",2.0);
	check(DispatchSelection.choose(candidates,priorities)==b,"stable key breaks equal-score ties and returns original reference");
	priorities.rawset("work",0.0);check(DispatchSelection.choose(candidates,priorities)==null,"priority zero excluded");
	var window=DispatchSelection.window(2,16,3,i->new String[]{"a","b","c"}[i]);
	var rows=(KahluaTable)window.rawget("ids");check(rows.len()==3 && "c".equals(rows.rawget(1)) && "a".equals(rows.rawget(2)),"roster wraps after actual cursor");
	check(((KahluaTable)DispatchSelection.window(0,16,257,i->"x").rawget("ids")).len()==0,"roster admission bound retained");
	var wake=PlanningInvalidation.create();check(PlanningInvalidation.revision(wake)==0,"revision read has no world initialization");
	var world=table();PlanningInvalidation.load(wake,world);var ids=table();ids.rawset(1,"box");
	var token=PlanningInvalidation.capture(wake,"scope",ids);check(!PlanningInvalidation.changed(wake,token),"fresh observation valid");
	double revision=PlanningInvalidation.revision(wake);PlanningInvalidation.containerChanged(wake,"unobserved");
	check(PlanningInvalidation.revision(wake)==revision && !PlanningInvalidation.changed(wake,token),"unobserved container does not create wake traffic");
	PlanningInvalidation.containerChanged(wake,"box");check(PlanningInvalidation.changed(wake,token),"observed dependency invalidates");
	token=PlanningInvalidation.capture(wake,"scope",ids);PlanningInvalidation.scopeChanged(wake,"other");
	check(!PlanningInvalidation.changed(wake,token),"another scope leaves dependency valid");
	PlanningInvalidation.scopeChanged(wake,"scope");check(PlanningInvalidation.changed(wake,token),"own scope invalidates");
	token=PlanningInvalidation.capture(wake,"scope",ids);PlanningInvalidation.load(wake,table());
	check(PlanningInvalidation.changed(wake,token),"world change rejects old observation");
	var many=table();for(int i=1;i<=513;i++)many.rawset(i,"box-"+i);
	token=PlanningInvalidation.capture(wake,"scope",many);PlanningInvalidation.capture(wake,"scope",ids);
	check(PlanningInvalidation.changed(wake,token),"observation cap reset invalidates old dependencies");
	System.out.println("PASS "+checks+" native dispatch ordering/wake/window checks; game NOT RUN");
    }
}
