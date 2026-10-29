import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.Base64;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaThread;

/** Runs the real installed PZ string runtime, without starting the game renderer. */
class KahluaUiTextTest {
    public static void main(String[] args) throws Exception {
        var platform = J2SEPlatform.getInstance();
        KahluaTable env = platform.newTable();
        env.rawset("_G", env);
        se.krka.kahlua.stdlib.BaseLib.register(env);
        se.krka.kahlua.stdlib.StringLib.register(platform, env);
        se.krka.kahlua.stdlib.TableLib.register(platform, env);
        se.krka.kahlua.j2se.MathLib.register(platform, env);
        se.krka.kahlua.stdlib.CoroutineLib.register(platform, env);
        se.krka.kahlua.stdlib.OsLib.register(platform, env);
        var thread = new KahluaThread(platform, env);
        thread.debugOwnerThread = Thread.currentThread();
        se.krka.kahlua.vm.KahluaUtil.setWorkerThread(env, thread);
        String stdlib = Files.readString(Path.of("D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/stdlib.lua"), StandardCharsets.UTF_8);
        Object[] setup = thread.pcall(LuaCompiler.loadstring(stdlib, "installed-stdlib", env), new Object[0]);
        if (!Boolean.TRUE.equals(setup[0])) throw new AssertionError(Arrays.toString(setup));
        String flow = Files.readString(Path.of("Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/Text.lua"), StandardCharsets.UTF_8);
        boolean legacy=Arrays.asList(args).contains("--legacy");
        if (legacy) flow = """
            local Flow={}
            function Flow.wrap(text,width,font)
                local lines,line={},""
                for char in text:gmatch("[%%z\\1-\\127\\194-\\244][\\128-\\191]*") do
                    local candidate=line..char
                    if line~="" and getTextManager():MeasureStringX(font,candidate)>width then
                        lines[#lines+1]=line line=char
                    else line=candidate end
                end
                if line~="" then lines[#lines+1]=line end
                return lines
            end
            return Flow
            """.replace("%%", "%");
        // Localized text enters the real game from Java Translator, not Lua source literals.
        env.rawset("original", "食物与工具 NPC 仓储中文名称");
        env.rawset("explicitText", "源箱\n目标箱");
        env.rawset("sourceName", "源箱");
        env.rawset("targetName", "目标箱");
        env.rawset("tinyText", "食品");
        String test = """
            getTextManager=function() return {MeasureStringX=function(self,font,text) return #text*10 end} end
            local Flow=(function()
            %s
            end)()
            local lines=Flow.wrap(original,50,1)
            assert(table.concat(lines,"")==original,"Chinese label characters were lost")
            assert(#lines>1,"Expected actual wrapping")
            local explicit=Flow.wrap(explicitText,500,1)
            assert(#explicit==2 and explicit[1]==sourceName and explicit[2]==targetName,"Explicit newline lost")
            local tiny=Flow.wrap(tinyText,0,1)
            assert(table.concat(tiny,"")==tinyText,"Narrow layout lost text")
            return "PASS installed PZ Kahlua Chinese text preservation, wrap, newline and narrow width; renderer NOT RUN"
            """.formatted(flow);
        Object[] result = thread.pcall(LuaCompiler.loadstring(test, "ui-text-regression", env), new Object[0]);
        if (!Boolean.TRUE.equals(result[0])) throw new AssertionError(Arrays.toString(result));
        System.out.println(result[1]);
        if (args.length>0 && !args[0].startsWith("--")) {
            KahluaTable translations=platform.newTable();
            for (String line:Files.readAllLines(Path.of(args[0]),StandardCharsets.UTF_8)) {
                String[] fields=line.split("\t",2);
                translations.rawset(fields[0],new String(Base64.getDecoder().decode(fields[1]),StandardCharsets.UTF_8));
            }
            env.rawset("ERTestTranslations",translations);
            env.rawset("ERTestRuntime",true);
            env.rawset("ERTestNanoTime",(se.krka.kahlua.vm.JavaFunction)(frame,n)->{frame.push((double)System.nanoTime());return 1;});
            KahluaTable pkg=platform.newTable(),loaded=platform.newTable();
            pkg.rawset("path",""); pkg.rawset("loaded",loaded); env.rawset("package",pkg);
            env.rawset("print",(se.krka.kahlua.vm.JavaFunction)(frame,n)->{System.out.println(frame.get(0));return 0;});
            env.rawset("require",(se.krka.kahlua.vm.JavaFunction)(frame,n)->{
                String name=(String)frame.get(0);
                Object module=loaded.rawget(name);
                if (module==null) {
                    Path file=Path.of("Contents/mods/EmberRoutesProbe/42/media/lua/client",name+".lua");
                    if (!Files.exists(file)) file=Path.of("Contents/mods/EmberRoutesProbe/42/media/lua/shared",name+".lua");
                    try {
                        module=thread.call(LuaCompiler.loadstring(Files.readString(file,StandardCharsets.UTF_8),name,env),new Object[0]);
                        if (module==null) module=true;
                        loaded.rawset(name,module);
                    } catch (Exception e) {throw new RuntimeException("Loading "+name,e);}
                }
                frame.push(module); return 1;
            });
            run(thread,env,Files.readString(Path.of("tests/lua/ui-foundation-test.lua"),StandardCharsets.UTF_8),"ui-foundation");
            run(thread,env,Files.readString(Path.of("tests/lua/settlement-storage-test.lua"),StandardCharsets.UTF_8),"settlement-storage");
            run(thread,env,Files.readString(Path.of("tests/lua/warehouse-query-test.lua"),StandardCharsets.UTF_8),"warehouse-query");
            run(thread,env,Files.readString(Path.of("tests/lua/warehouse-metrics-test.lua"),StandardCharsets.UTF_8),"warehouse-metrics");
            run(thread,env,Files.readString(Path.of("tests/lua/warehouse-locator-test.lua"),StandardCharsets.UTF_8),"warehouse-locator");
            run(thread,env,Files.readString(Path.of("tests/lua/storage-panel-test.lua"),StandardCharsets.UTF_8),"real-panel-fixture");
            run(thread,env,"""
                local resolutions={{1920,1080,16},{2560,1440,24},{3840,2160,32},{1280,720,28}}
                for _,r in ipairs(resolutions) do
                    local panel=UI_TEST_EXPORT.open(r[1],r[2],r[3])
                    assert(panel.list.height>panel.rowHeight,"List viewport collapsed")
                    assert(panel.buttons[1].y>=panel.statusY+panel.fontHeight*3,"Footer overlaps status")
                    local labels=0
                    for _,entry in ipairs(panel.list.items) do
                        local row=entry.item
                        assert(entry.height>=panel.fontHeight+panel.pad,"Checkbox rows overlap")
                        assert(#row.lines>0,"Empty rendered label")
                        if row.kind=="group" then
                            assert(table.concat(row.lines,"")==row.caption,"Translated category disappeared")
                            labels=labels+1
                        end
                    end
                    assert(labels>5,"Missing category rows")
                    panel:close()
                end
                print("PASS real Kahlua + actual translations: panel labels/heights at 1080p, 2K, 4K, 720p large font; ISUI host mocked")
                ""","chinese-panel-layout");
            preview(thread,env,Arrays.asList(args).contains("--language=EN")?"EN":"CN");
            run(thread,env,Files.readString(Path.of("tests/lua/storage-tabs-test.lua"),StandardCharsets.UTF_8),"real-tabs-fixture");
            run(thread,env,Files.readString(Path.of("tests/lua/settlement-ui-test.lua"),StandardCharsets.UTF_8),"settlement-ui");
            preview(thread,env,Arrays.asList(args).contains("--language=EN")?"EN":"CN","warehouse");
            preview(thread,env,Arrays.asList(args).contains("--language=EN")?"EN":"CN","selector");
        }
    }
    static void run(KahluaThread thread,KahluaTable env,String code,String name) throws Exception {
        Object[] result=thread.pcall(LuaCompiler.loadstring(code,name,env),new Object[0]);
        if (!Boolean.TRUE.equals(result[0])) throw new AssertionError(Arrays.toString(result));
    }
    static double number(Object value) { return ((Number)value).doubleValue(); }
    static void preview(KahluaThread thread,KahluaTable env,String language) throws Exception {
        preview(thread,env,language,"filter");
    }
    static void preview(KahluaThread thread,KahluaTable env,String language,String mode) throws Exception {
        var image=new java.awt.image.BufferedImage(1920,1080,java.awt.image.BufferedImage.TYPE_INT_RGB);
        var graphics=image.createGraphics();
        graphics.setColor(new java.awt.Color(20,25,29)); graphics.fillRect(0,0,1920,1080);
        graphics.setFont(new java.awt.Font("Microsoft YaHei",java.awt.Font.PLAIN,18));
        var metrics=graphics.getFontMetrics();
        env.rawset("previewFontHeight",(double)metrics.getHeight());
        env.rawset("previewMode",mode);
        env.rawset("_measure",(se.krka.kahlua.vm.JavaFunction)(f,n)->{f.push((double)metrics.stringWidth((String)f.get(0)));return 1;});
        env.rawset("_text",(se.krka.kahlua.vm.JavaFunction)(f,n)->{
            graphics.setColor(new java.awt.Color((float)number(f.get(3)),(float)number(f.get(4)),(float)number(f.get(5))));
            graphics.drawString((String)f.get(0),(int)number(f.get(1)),(int)number(f.get(2))+metrics.getAscent()); return 0;
        });
        env.rawset("_rect",(se.krka.kahlua.vm.JavaFunction)(f,n)->{
            graphics.setColor(new java.awt.Color((float)number(f.get(5)),(float)number(f.get(6)),(float)number(f.get(7)),(float)number(f.get(4))));
            int x=(int)number(f.get(0)),y=(int)number(f.get(1)),w=(int)number(f.get(2)),h=(int)number(f.get(3));
            if (Boolean.TRUE.equals(f.get(8))) graphics.drawRect(x,y,w,h); else graphics.fillRect(x,y,w,h);
            return 0;
        });
        run(thread,env,"""
            getTextManager=function() return {getFontHeight=function() return previewFontHeight end,
                MeasureStringX=function(_,font,text) return _measure(text) end} end
            if previewMode=="warehouse" then PREVIEW=WAREHOUSE_TEST_EXPORT.preview(1920,1080,previewFontHeight)
            elseif previewMode=="selector" then PREVIEW=WAREHOUSE_TEST_EXPORT.selector()
            else PREVIEW=UI_TEST_EXPORT.open(1920,1080,previewFontHeight) end
            local panel=PREVIEW
            if previewMode=="filter" then panel:edit(function(model) model.draft.private=false end) end
            function panel:drawText(text,x,y,r,g,b) _text(text,x,y,r,g,b) end
            function panel:drawRect(x,y,w,h,a,r,g,b) _rect(x,y,w,h,a,r,g,b,false) end
            function panel:drawRectBorder(x,y,w,h,a,r,g,b) _rect(x,y,w,h,a,r,g,b,true) end
            function panel:drawTextureScaledAspect(texture,x,y,w,h,a,r,g,b) self:drawRect(x,y,w,h,a,r,g,b) end
            local bg=panel.backgroundColor
            if bg then panel:drawRect(0,0,panel.width,panel.height,bg.a,bg.r,bg.g,bg.b) end
            panel:prerender()
            PREVIEW_LISTS=previewMode=="warehouse" and {panel.itemList,panel.sourceList} or (panel.list and {panel.list} or {})
            for _,list in ipairs(PREVIEW_LISTS) do
            function list:drawText(text,x,y,r,g,b) _text(text,x+list.x,y+list.y,r,g,b) end
            function list:drawRect(x,y,w,h,a,r,g,b) _rect(x+list.x,y+list.y,w,h,a,r,g,b,false) end
            function list:drawRectBorder(x,y,w,h,a,r,g,b) _rect(x+list.x,y+list.y,w,h,a,r,g,b,true) end
            function list:drawTextureScaledAspect(texture,x,y,w,h,a,r,g,b) self:drawRect(x,y,w,h,a,r,g,b) end
            end
            ""","preview-host");
        KahluaTable panel=(KahluaTable)env.rawget("PREVIEW"), lists=(KahluaTable)env.rawget("PREVIEW_LISTS");
        int width=(int)number(panel.rawget("width")),height=(int)number(panel.rawget("height"));
        for(int i=1;lists.rawget(i)!=null;i++) {
            KahluaTable list=(KahluaTable)lists.rawget(i);
            graphics.setClip((int)number(list.rawget("x")),(int)number(list.rawget("y")),(int)number(list.rawget("width")),(int)number(list.rawget("height")));
            env.rawset("_previewList",list);
            run(thread,env,"""
                local list=_previewList local bg=list.backgroundColor
                if bg then list:drawRect(0,0,list.width,list.height,bg.a,bg.r,bg.g,bg.b) end
                local y=0 for _,entry in ipairs(list.items) do y=list:doDrawItem(y,entry) end
                if #list.items==0 and list.render then list:render() end
                ""","preview-draw");
        }
        graphics.setClip(null);
        graphics.setColor(new java.awt.Color(40,44,48)); graphics.fillRect(0,0,width,24);
        graphics.setColor(java.awt.Color.WHITE); Object rawTitle=panel.rawget("title"); graphics.drawString(rawTitle!=null?rawTitle.toString():"",20,20);
        KahluaTable children=(KahluaTable)panel.rawget("children");
        for(int i=1;children.rawget(i)!=null;i++) {
            KahluaTable button=(KahluaTable)children.rawget(i);
            Object title=button.rawget("title");
            if (button.rawget("value") instanceof String value) title=value.isEmpty() && button.rawget("placeholderText")!=null?button.rawget("placeholderText"):value;
            if (button.rawget("options") instanceof KahluaTable options) title=options.rawget((int)number(button.rawget("selected")));
            if (!(title instanceof String label)) continue;
            int x=(int)number(button.rawget("x")),y=(int)number(button.rawget("y")),w=(int)number(button.rawget("width")),h=(int)number(button.rawget("height"));
            KahluaTable bg=(KahluaTable)button.rawget("backgroundColor");
            graphics.setColor(bg==null?new java.awt.Color(40,44,48):new java.awt.Color((float)number(bg.rawget("r")),(float)number(bg.rawget("g")),(float)number(bg.rawget("b")))); graphics.fillRect(x,y,w,h);
            graphics.setColor(java.awt.Color.LIGHT_GRAY); graphics.drawRect(x,y,w,h);
            graphics.drawString(label,x+(w-metrics.stringWidth(label))/2,y+(h-metrics.getHeight())/2+metrics.getAscent());
        }
        graphics.setColor(java.awt.Color.LIGHT_GRAY); graphics.drawString("Kahlua layout preview - ISUI host/GPU mocked",20,height-4);
        graphics.dispose();
        String name=mode.equals("filter")?"probe-ui-0.7.3":(mode.equals("warehouse")?"probe-0.11.0-":"probe-0.8.0-")+mode;
        Path output=Path.of("build/qa/"+name+"-"+language+".png"); Files.createDirectories(output.getParent());
        javax.imageio.ImageIO.write(image.getSubimage(0,0,width,height),"png",output.toFile());
        System.out.println("PREVIEW "+output+" (captured component layout; not a game screenshot)");
    }
}
