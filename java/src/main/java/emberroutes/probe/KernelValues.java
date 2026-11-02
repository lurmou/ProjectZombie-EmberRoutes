package emberroutes.probe;

import java.util.Arrays;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.*;

/** Internal value/VM plumbing, never an authority or a fallback implementation. */
final class KernelValues {
    private KernelValues() {}
    static KahluaTable table() {return J2SEPlatform.getInstance().newTable();}
    static Object g(KahluaTable p,Object key) {return p==null ? null : p.rawget(key);}
    static KahluaTable t(Object v) {return (KahluaTable)v;}
    static KahluaTable t(KahluaTable p,Object key) {return t(g(p,key));}
    static boolean yes(Object v) {return v!=null && !Boolean.FALSE.equals(v);}
    static double n(Object v) {return ((Number)v).doubleValue();}
    static double zero(Object v) {return yes(v) ? n(v) : 0;}
    static void add(KahluaTable p,Object key,double delta) {p.rawset(key,Double.valueOf(n(p.rawget(key))+delta));}
    static String text(Object v) {return v==null?"nil":v instanceof Double d?KahluaUtil.numberToString(d):String.valueOf(v);}
    static boolean eq(Object a,Object b) {
	if(a instanceof Number x && b instanceof Number y)return x.doubleValue()==y.doubleValue();
	return a==b || a!=null && a.equals(b);
    }
    static boolean nonnegative(Object v) {return v instanceof Double d && d==d && d>=0 && d!=Double.POSITIVE_INFINITY;}
    static KahluaTable result(boolean ok,Object value) {KahluaTable r=table();r.rawset("ok",ok);r.rawset("result",value);return r;}
    static KahluaTable shallow(KahluaTable source) {KahluaTable r=table();if(source!=null){KahluaTableIterator it=source.iterator();while(it.advance())r.rawset(it.getKey(),it.getValue());}return r;}
    static Object[] call(KahluaThread vm,Object function,Object... args) {
	Object[] r=vm.pcall(function,args);
	if(!Boolean.TRUE.equals(r[0]))throw new KahluaException(r.length>1?r[1]:"KERNEL_CALLBACK_FAILED");
	return Arrays.copyOfRange(r,1,r.length);
    }
    static Object first(Object[] r) {return r.length==0 ? null : r[0];}
    static Object[] method(KahluaThread vm,KahluaTable target,String name,Object... args) {
	Object[] values=new Object[args.length+1];values[0]=target;System.arraycopy(args,0,values,1,args.length);
	return call(vm,target.rawget(name),values);
    }
    static void require(boolean condition,String reason) {if(!condition)throw new KahluaException(reason);}
}
