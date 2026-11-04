import java.nio.file.*;
import java.util.*;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.*;

/** Installed PZ VM and stdlib, fake native bodies. Never initializes the game. */
class KahluaLaborTest {
    public static void main(String[] args) throws Exception {
        var files=args.length>0 ? Arrays.stream(args).filter(a->!a.startsWith("--")).toList() : List.of("labor-core-test.lua","sort-policy-test.lua","logistics-test.lua","multi-worker-test.lua","companion-test.lua","persistence-test.lua","boot-pause-test.lua");
	if (Arrays.asList(args).contains("--all")) {
	    try (var paths=Files.list(Path.of("tests/lua"))) {
		files=paths.map(p->p.getFileName().toString()).filter(n->n.endsWith("-test.lua")).sorted().toList();
	    }
	}
	var failures=new ArrayList<String>();
        for (String file:files) {
	    try {

            var platform=J2SEPlatform.getInstance(); var env=platform.newTable(); env.rawset("_G",env);
            se.krka.kahlua.stdlib.BaseLib.register(env);
            se.krka.kahlua.stdlib.StringLib.register(platform,env);
            se.krka.kahlua.stdlib.TableLib.register(platform,env);
            se.krka.kahlua.j2se.MathLib.register(platform,env);
            se.krka.kahlua.stdlib.CoroutineLib.register(platform,env);
            se.krka.kahlua.stdlib.OsLib.register(platform,env);
            var thread=new KahluaThread(platform,env); thread.debugOwnerThread=Thread.currentThread();
            KahluaUtil.setWorkerThread(env,thread);
            run(thread,env,Path.of("D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/stdlib.lua"));
	    if (Arrays.asList(args).contains("--evidence-userdata")) {
		var io=platform.newTable();io.rawset("stdout",new Object());env.rawset("io",io);
	    }
            env.rawset("next",null); // PZ gameplay does not expose the standard Lua next global.
	    for(String arg:args) if(arg.startsWith("--cost-width=")) env.rawset("ERCostWidth",Double.valueOf(arg.substring(13)));
            if (Arrays.asList(args).contains("--timing"))
                env.rawset("_ERTestNanos",(JavaFunction)(frame,n)->{frame.push((double)System.nanoTime());return 1;});
            for (String arg:args) if (arg.startsWith("--translations=")) {
                var translations=platform.newTable();
                for (String line:Files.readAllLines(Path.of(arg.substring("--translations=".length())))) {
                    String[] parts=line.split("\t",2);
                    translations.rawset(parts[0],new String(Base64.getDecoder().decode(parts[1]),java.nio.charset.StandardCharsets.UTF_8));
                }
                env.rawset("ERTestTranslations",translations);
            }
	    if (Arrays.asList(args).contains("--java-job-data")) {
		var bridge=platform.newTable();
		var method=Class.forName("emberroutes.probe.JobData").getMethod("copy",KahluaTable.class);
		bridge.rawset("jobDataCopy",(JavaFunction)(frame,n)->{
		    try { frame.push(method.invoke(null,frame.get(0))); return 1; }
		    catch (java.lang.reflect.InvocationTargetException e) { throw (RuntimeException)e.getCause(); }
		    catch (ReflectiveOperationException e) { throw new RuntimeException(e); }
		});
		env.rawset("EmberRoutesProbeJava",bridge);
	    }
	    if (Arrays.asList(args).contains("--java-labor")) {
		var bridge=platform.newTable();
		for(String[] binding:new String[][]{{"laborMutate","LaborCommitKernel","mutate"},{"laborCreate","LaborCommitKernel","create"},{"laborCancel","LaborCommitKernel","cancel"},{"jobDataCopy","JobData","copy"}}) {
		    var method=Arrays.stream(Class.forName("emberroutes.probe."+binding[1]).getMethods()).filter(m->m.getName().equals(binding[2])).findFirst().orElseThrow();
		    bridge.rawset(binding[0],(JavaFunction)(frame,n)->{
			Object[] values=new Object[method.getParameterCount()];int offset=method.getParameterTypes()[0]==KahluaThread.class?1:0;
			if(offset==1)values[0]=frame.getThread();
			for(int i=offset;i<values.length;i++)values[i]=frame.get(i-offset);
			try {frame.push(method.invoke(null,values));return 1;}
			catch(java.lang.reflect.InvocationTargetException e){throw (RuntimeException)e.getCause();}
			catch(ReflectiveOperationException e){throw new RuntimeException(e);}
		    });
		}
		env.rawset("ERLaborTestBridge",bridge);env.rawset("EmberRoutesProbeJava",bridge);
	    }
	    if (Arrays.asList(args).contains("--java-dispatch")) {
		var bridge=platform.newTable();
		for (String[] binding:new String[][]{
		    {"dispatchChoose","DispatchSelection","choose"},{"planningWakeNew","PlanningInvalidation","create"},
		    {"planningWakeLoad","PlanningInvalidation","load"},{"planningWakeRevision","PlanningInvalidation","revision"},
		    {"planningWakeCapture","PlanningInvalidation","capture"},{"planningWakeChanged","PlanningInvalidation","changed"},
		    {"planningWakeContainerChanged","PlanningInvalidation","containerChanged"},{"planningWakeScopeChanged","PlanningInvalidation","scopeChanged"}}) {
		    var method=Arrays.stream(Class.forName("emberroutes.probe."+binding[1]).getMethods())
			.filter(m->m.getName().equals(binding[2])).findFirst().orElseThrow();
		    bridge.rawset(binding[0],(JavaFunction)(frame,n)->{
			Object[] values=new Object[method.getParameterCount()];for(int i=0;i<values.length;i++) values[i]=frame.get(i);
			try {
			    Object result=method.invoke(null,values);
			    if (method.getReturnType()==void.class) return 0;
			    frame.push(result);return 1;
			} catch (java.lang.reflect.InvocationTargetException e) {throw (RuntimeException)e.getCause();}
			catch (ReflectiveOperationException e) {throw new RuntimeException(e);}
		    });
		}
		env.rawset("ERDispatchTestBridge",bridge);
	    }
            var pkg=platform.newTable(); var loaded=platform.newTable(); pkg.rawset("loaded",loaded); pkg.rawset("path",""); env.rawset("package",pkg);
            env.rawset("print",(JavaFunction)(frame,n)->{System.out.println(frame.get(0));return 0;});
            env.rawset("require",(JavaFunction)(frame,n)->{
                String name=(String)frame.get(0); Object value=loaded.rawget(name);
                if (value==null) {
                    Path path=Path.of("Contents/mods/EmberRoutesProbe/42/media/lua/client",name+".lua");
                    if (!Files.exists(path)) path=Path.of("Contents/mods/EmberRoutesProbe/42/media/lua/shared",name+".lua");
                    value=call(thread,env,path); if (value==null) value=true; loaded.rawset(name,value);
                }
                frame.push(value);return 1;
            });
            env.rawset("dofile",(JavaFunction)(frame,n)->{frame.push(call(thread,env,Path.of((String)frame.get(0))));return 1;});
            run(thread,env,Path.of("tests/lua",file));
            if (Arrays.asList(args).contains("--preview") && env.rawget("ERSettlementPreview")!=null)
                for (String tab:Arrays.stream(args).filter(a->a.startsWith("--preview-tabs=")).findFirst()
                    .map(a->List.of(a.substring("--preview-tabs=".length()).split(",")))
                    .orElse(List.of("warehouse","orders","logistics","crafting","publicOrder","priorities"))) preview(thread,env,tab,args);
            System.out.println("PASS installed Kahlua: "+file+"; native host mocked");
	    } catch (Throwable error) {
		if (!Arrays.asList(args).contains("--keep-going")) throw error;
		failures.add(file);
		System.out.println("FAIL installed Kahlua: "+file+" "+error);
	    }
	}
	if (Arrays.asList(args).contains("--keep-going")) {
	    System.out.println("REGRESSION total="+files.size()+" passed="+(files.size()-failures.size())+" failed="+failures.size()+" failures="+failures);
	    if (!failures.isEmpty()) System.exit(1);
        }
    }
    static Object call(KahluaThread thread,KahluaTable env,Path file) {
        try { return thread.call(LuaCompiler.loadstring(Files.readString(file,java.nio.charset.StandardCharsets.UTF_8),file.toString(),env),new Object[0]); }
        catch (Exception error) { throw new RuntimeException(file.toString(),error); }
    }
    static void run(KahluaThread thread,KahluaTable env,Path file) throws Exception {
        Object[] result=thread.pcall(LuaCompiler.loadstring(Files.readString(file,java.nio.charset.StandardCharsets.UTF_8),file.toString(),env),new Object[0]);
        if (!Boolean.TRUE.equals(result[0])) throw new AssertionError(file+" "+Arrays.toString(result));
    }
    static double number(Object value) { return ((Number)value).doubleValue(); }
    static void preview(KahluaThread thread,KahluaTable env,String tab,String[] args) throws Exception {
        var image=new java.awt.image.BufferedImage(1280,1000,java.awt.image.BufferedImage.TYPE_INT_RGB);
        var g=image.createGraphics();
        g.setRenderingHint(java.awt.RenderingHints.KEY_TEXT_ANTIALIASING,java.awt.RenderingHints.VALUE_TEXT_ANTIALIAS_ON);
        g.setFont(new java.awt.Font("Microsoft YaHei",java.awt.Font.PLAIN,18));
        var metrics=g.getFontMetrics();
        var smallFont=g.getFont();
        var mediumFont=smallFont.deriveFont(java.awt.Font.BOLD,26f);
        var largeFont=smallFont.deriveFont(java.awt.Font.BOLD,32f);
        java.util.function.Function<Object,java.awt.Font> fontFor=value->
            value instanceof Number number && number.intValue()==2 ? mediumFont
            : value instanceof Number number && number.intValue()==3 ? largeFont : smallFont;
        env.rawset("_fontHeight",(JavaFunction)(f,n)->{f.push((double)g.getFontMetrics(fontFor.apply(n>0?f.get(0):null)).getHeight());return 1;});
        env.rawset("_measure",(JavaFunction)(f,n)->{f.push((double)g.getFontMetrics(fontFor.apply(n>1?f.get(1):null)).stringWidth((String)f.get(0)));return 1;});
        env.rawset("_text",(JavaFunction)(f,n)->{
            g.setColor(new java.awt.Color((float)number(f.get(3)),(float)number(f.get(4)),(float)number(f.get(5))));
            g.setFont(fontFor.apply(n>6?f.get(6):null));
            g.drawString((String)f.get(0),(int)number(f.get(1)),(int)number(f.get(2))+g.getFontMetrics().getAscent());return 0;
        });
        env.rawset("_rect",(JavaFunction)(f,n)->{
            g.setColor(new java.awt.Color((float)number(f.get(5)),(float)number(f.get(6)),(float)number(f.get(7)),(float)number(f.get(4))));
            int x=(int)number(f.get(0)),y=(int)number(f.get(1)),w=(int)number(f.get(2)),h=(int)number(f.get(3));
            if (Boolean.TRUE.equals(f.get(8))) g.drawRect(x,y,w,h); else g.fillRect(x,y,w,h);return 0;
        });
        env.rawset("_clip",(JavaFunction)(f,n)->{
            if(n==0) g.setClip(null); else g.setClip((int)number(f.get(0)),(int)number(f.get(1)),(int)number(f.get(2)),(int)number(f.get(3)));return 0;
        });
        env.rawset("previewTab",tab); env.rawset("previewFontHeight",(double)metrics.getHeight());
        String source="""
            getTextManager=function() return {getFontHeight=function(_,font) return _fontHeight(font) end,
                MeasureStringX=function(_,font,value) return _measure(value,font) end} end
            PREVIEW=ERSettlementPreview(previewTab,previewFontHeight)
            local function paint(panel)
                if panel.visible==false then return end
                local ax,ay=panel:getAbsoluteX(),panel:getAbsoluteY()
                function panel:drawText(value,x,y,r,g,b,a,font) _text(value,x+ax,y+ay,r,g,b,font) end
                function panel:drawTextCentre(value,x,y,r,g,b) self:drawText(value,x-_measure(value)/2,y,r,g,b) end
                function panel:drawRect(x,y,w,h,a,r,g,b) _rect(x+ax,y+ay,w,h,a,r,g,b,false) end
                function panel:drawRectBorder(x,y,w,h,a,r,g,b) _rect(x+ax,y+ay,w,h,a,r,g,b,true) end
                function panel:drawTextureScaledAspect(texture,x,y,w,h,a,r,g,b) self:drawRect(x,y,w,h,a,r,g,b) end
                local bg=panel.backgroundColor
                if bg then panel:drawRect(0,0,panel.width,panel.height,bg.a,bg.r,bg.g,bg.b) end
                panel:prerender()
                if panel.doDrawItem then
                    _clip(ax,ay,panel.width,panel.height)
                    local y=0 for _,row in ipairs(panel.items) do y=panel:doDrawItem(y,row) end
                    _clip()
                else
                    local label=panel.title
                    if panel==PREVIEW then
                        panel:drawRect(0,0,panel.width,24,1,0.12,0.14,0.14)
                        panel:drawText(label,24,0,0.91,0.93,0.91) label=nil
                    end
                    if panel.options and type(panel.options[panel.selected or 1])=='string' then label=panel.options[panel.selected or 1] end
                    if panel.value~=nil then label=panel.value=='' and panel.placeholderText or panel.value end
                    if type(label)=='string' then panel:drawText(label,8,math.max(0,(panel.height-previewFontHeight)/2),0.91,0.93,0.91) end
                    if panel.selected and type(panel.selected)=='table' and panel.options then
                        for i,option in ipairs(panel.options) do
                            panel:drawRectBorder(0,0,previewFontHeight,previewFontHeight,1,0.6,0.7,0.7)
                            if panel.selected[i] then panel:drawRect(4,4,previewFontHeight-8,previewFontHeight-8,1,0.8,0.72,0.46) end
                            panel:drawText(option.text or option,previewFontHeight+8,0,0.91,0.93,0.91)
                        end
                    end
                    for _,child in ipairs(panel.children or {}) do paint(child) end
                end
            end
            paint(PREVIEW)
            """;
        Object[] result=thread.pcall(LuaCompiler.loadstring(source,"settlement-preview",env),new Object[0]);
        if(!Boolean.TRUE.equals(result[0])) throw new AssertionError(Arrays.toString(result));
        KahluaTable panel=(KahluaTable)env.rawget("PREVIEW");
        int width=(int)number(panel.rawget("width")),height=(int)number(panel.rawget("height"));
        g.setClip(null); g.setColor(java.awt.Color.GRAY); g.drawString("Layout preview / synthetic data / game renderer not run",12,height-5);g.dispose();
        String language=Arrays.stream(args).anyMatch(a->a.contains("ui-EN.tsv"))?"EN":"CN";
        Path output=Path.of("build/qa/settlement-visual-"+tab+"-"+language+".png");Files.createDirectories(output.getParent());
        javax.imageio.ImageIO.write(image.getSubimage(0,0,width,height),"png",output.toFile());
        System.out.println("PREVIEW "+output);
    }
}
