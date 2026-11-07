import java.io.IOException;
import java.nio.file.Path;
import org.json.JSONObject;
import se.krka.kahlua.vm.*;
import zombie.Lua.LuaManager;
import zombie.core.SpriteRenderer;
import zombie.ui.UIElement;

/** Native widget picking plus scene-provided bounds for genuinely self-drawn regions. */
final class PreviewInspector {
    JSONObject selection;
    String caption="F8 inspect, then click an element";
    double x,y,width,height;

    void clear() { selection=null; caption="F8 inspect, then click an element"; }

    void pick(PreviewSession session,int px,int py) throws IOException {
        if (session==null || session.root==null || session.error!=null) return;
        UIElement element=hit(session.root,px,py);
        if (element==null) {
            clear();
            PreviewLiveControl.write(session.output.resolve("selection.json"),new JSONObject().put("format",1)
                .put("generation",session.generation).put("state","empty"));
            return;
        }
        KahluaTable table=element.getTable();
        String type=text(table,"Type"),label=text(table,"title");
        if (label.isBlank()) label=text(table,"titleText");
        String source=session.origins.getOrDefault(element,"");
        for (UIElement parent=element.getParent();parent!=null&&!source.contains("EmberRoutesProbe");parent=parent.getParent()) {
            String owner=session.origins.getOrDefault(parent,"");
            if (owner.contains("EmberRoutesProbe")) source=owner;
        }
        String id="";
        for (UIElement child=element;child.getParent()!=null;child=child.getParent())
            id="/"+child.getParent().getControls().indexOf(child)+id;
        id="root"+id;
        x=element.getAbsoluteX(); y=element.getAbsoluteY(); width=element.getWidth(); height=element.getHeight();
        if (element==session.root || type.contains("OverviewPage") || type.contains("ListBox")) {
            Object regions=LuaManager.env.rawget("PreviewRegions");
            if (regions!=null) {
                Object[] result=PreviewSession.call(regions);
                if (result.length>1 && result[1] instanceof KahluaTable list) {
                    double area=Double.MAX_VALUE;
                    for (int i=1;;i++) {
                        Object item=list.rawget((double)i);
                        if (!(item instanceof KahluaTable region)) break;
                        double rx=number(region,"x"),ry=number(region,"y"),rw=number(region,"width"),rh=number(region,"height");
                        if (rw>0 && rh>0 && px>=rx && py>=ry && px<rx+rw && py<ry+rh && rw*rh<area) {
                            area=rw*rh; x=rx; y=ry; width=rw; height=rh;
                            id=String.valueOf(region.rawget("id")); label=String.valueOf(region.rawget("label"));
                            source=String.valueOf(region.rawget("source")); type="drawn region";
                        }
                    }
                }
            }
        }
        if (!source.isBlank() && !source.equals("null") && !Path.of(source).isAbsolute()) source=session.repo.resolve(source).normalize().toString();
        selection=new JSONObject().put("format",1).put("generation",session.generation).put("id",id)
            .put("type",type).put("label",label).put("source",source)
            .put("x",x).put("y",y).put("width",width).put("height",height);
        caption=type+" | "+label+" | "+(int)x+","+(int)y+" "+(int)width+"x"+(int)height;
        PreviewLiveControl.write(session.output.resolve("selection.json"),selection);
        System.out.println("PICK "+selection);
    }

    private static UIElement hit(UIElement parent,int px,int py) {
        if (!parent.isReallyVisible() || px<parent.getAbsoluteX() || py<parent.getAbsoluteY()
                || px>=parent.getAbsoluteX()+parent.getWidth() || py>=parent.getAbsoluteY()+parent.getHeight()) return null;
        var children=parent.getControls();
        for (int i=children.size()-1;i>=0;i--) {
            UIElement child=hit(children.get(i),px,py);
            if (child!=null) return child;
        }
        return parent;
    }
    private static String text(KahluaTable table,String key) {
        Object value=table==null?null:LuaManager.thread.tableget(table,key);
        return value instanceof String s?s:"";
    }
    private static double number(KahluaTable table,String key) { return ((Number)table.rawget(key)).doubleValue(); }
    void draw() {
        if (selection==null) return;
        var renderer=SpriteRenderer.instance;
        renderer.renderRect((int)x,(int)y,(int)width,2,1,.8f,.15f,1);
        renderer.renderRect((int)x,(int)y,2,(int)height,1,.8f,.15f,1);
        renderer.renderRect((int)x,(int)(y+height-2),(int)width,2,1,.8f,.15f,1);
        renderer.renderRect((int)(x+width-2),(int)y,2,(int)height,1,.8f,.15f,1);
    }
}
