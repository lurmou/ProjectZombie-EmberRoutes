import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.*;
import java.util.*;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.*;
import zombie.Lua.*;
import zombie.ui.*;

/** One disposable Lua generation. No world/bootstrap code is loaded. */
final class PreviewSession implements AutoCloseable {
    final Map<Path, PreviewLiveControl.Stamp> sources = new LinkedHashMap<>();
    final Map<UIElement, String> origins = new IdentityHashMap<>();
    final Path repo, output, sceneFile;
    final int generation;
    UIElement root;
    KahluaTable scene;
    Throwable error;
    private Object guard;
    private boolean closed;
    private final Set<UIElement> guarded = Collections.newSetFromMap(new IdentityHashMap<>());

    PreviewSession(Path repo, Path output, Path sceneFile, int generation) {
        this.repo=repo; this.output=output; this.sceneFile=sceneFile; this.generation=generation;
    }

    void load(String language, boolean smoke) throws Exception {
        UIManager.clearArrays();
        LuaEventManager.Reset();
        LuaHookManager.Reset();
        LuaManager.init();
        LuaManager.env.rawset("PreviewServices", LuaManager.platform.newTable());
        LuaManager.env.rawset("PreviewChineseText", "中文 / Native text");
        LuaManager.env.rawset("PreviewReportFailure", (JavaFunction)(frame,count) -> {
            if (error==null) error=new IllegalStateException(String.valueOf(frame.get(0)));
            return 0;
        });
        installTranslations(language);
        installLoader();
        call(LuaCompiler.loadstring("require 'env'; require 'ISUI/Gamepad/JoyPadSetup'; "
            + "require 'ISUI/ISRichTextPanel'; require 'ISUI/ISToolTip'","preview-native-preloads",LuaManager.env));
        execute(sceneFile);
        Object value=LuaManager.env.rawget("NativePreview");
        if (!(value instanceof KahluaTable table) || !(table.rawget("javaObject") instanceof UIElement element))
            throw new IllegalStateException("Scene must provide NativePreview with a native UIElement");
        scene=table; root=element;
        if (!UIManager.getUI().contains(root)) UIManager.getUI().add(root);
        guard=call(LuaCompiler.loadstring("return function(widget) "
            + "for _,name in ipairs({'prerender','render','update'}) do local original=widget[name]; "
            + "if type(original)=='function' then widget[name]=function(self,...) "
            + "local ok,err,trace=pcall(original,self,...); if not ok then PreviewReportFailure(tostring(self.Type)..'.'..name..': '..tostring(err)..' '..tostring(trace)) end end end end end",
            "preview-callback-guard",LuaManager.env))[1];
        guardTree(root);
        if (smoke) {
            Object check=scene.rawget("smoke");
            if (check!=null) call(check,scene);
            System.out.println("PASS scene smoke: " + Objects.toString(scene.rawget("smokeSummary"),"native fixture checks"));
        }
    }

    void draw() {
        if (error!=null || root==null) return;
        guardTree(root);
        root.update(); root.render();
        // Native buttons enqueue tooltips in UIManager, outside the scene's child tree.
        PreviewFrame.flushPendingUI();
        for (var widget : new ArrayList<>(UIManager.getUI())) {
            if (widget==root || !widget.isVisible()) continue;
            if (widget instanceof UIElement element) guardTree(element);
            widget.update(); widget.render();
        }
    }

    private void guardTree(UIElement element) {
        KahluaTable table=element.getTable();
        if (guarded.add(element) && table!=null) {
            String type=Objects.toString(LuaManager.thread.tableget(table,"Type"),"");
            int best=-1;
            for (String method : List.of("createChildren","initialise","prerender","render","update","onMouseDown")) {
                Object callback=LuaManager.thread.tableget(table,method);
                if (callback instanceof LuaClosure closure && closure.prototype.filename!=null) {
                    String source=closure.prototype.filename;
                    String base=Path.of(source).getFileName().toString().replace(".lua","");
                    int score=(source.contains("EmberRoutesProbe")?1000:0)
                        +(type.equals(base)||type.equals("EmberRoutes"+base)?100:0)+(method.equals("initialise")?10:0);
                    if (score>best) { best=score; origins.put(element,source); }
                }
            }
            call(guard,table);
        }
        for (UIElement child:element.getControls()) guardTree(child);
    }

    Object[] execute(Path file) throws IOException {
        Path path=file.toAbsolutePath().normalize();
        sources.put(path,PreviewLiveControl.Stamp.read(path)); // keep failed/missing files observable
        byte[] bytes=Files.readAllBytes(path);
        try (Reader reader=new InputStreamReader(new ByteArrayInputStream(bytes),StandardCharsets.UTF_8)) {
            org.luaj.kahluafork.compiler.FuncState.currentFile=path.getFileName().toString();
            org.luaj.kahluafork.compiler.FuncState.currentfullFile=path.toString();
            Object[] result=call(LuaCompiler.loadis(reader,path.toString(),LuaManager.env));
            String hash;
            try { hash=HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes)); }
            catch (NoSuchAlgorithmException impossible) { throw new AssertionError(impossible); }
            Files.writeString(output.resolve("module-sources-r"+generation+".tsv"),path+"\t"+hash+"\n",
                StandardOpenOption.CREATE,StandardOpenOption.APPEND);
            return result;
        }
    }

    static Object[] call(Object function,Object... arguments) {
        Object[] result=LuaManager.thread.pcall(function,arguments);
        if (!Boolean.TRUE.equals(result[0]))
            throw new IllegalStateException(Objects.toString(result.length>1?result[1]:null,"Lua execution failed")
                +(result.length>2?"\n"+Objects.toString(result[2],""):""));
        return result;
    }

    private void installTranslations(String language) throws IOException {
        Path path=repo.resolve("Contents/mods/EmberRoutesProbe/42/media/lua/shared/Translate/"+language+"/IG_UI.json");
        sources.put(path,PreviewLiveControl.Stamp.read(path));
        org.json.JSONObject dictionary=new org.json.JSONObject(Files.readString(path));
        for (String global:List.of("getText","getTextOrNull")) {
            Object nativeFunction=LuaManager.env.rawget(global);
            LuaManager.env.rawset(global,(JavaFunction)(frame,count)->{
                String key=(String)frame.get(0);
                if (dictionary.has(key)) {
                    String value=dictionary.getString(key);
                    for (int i=1;i<count;i++) value=value.replace("%"+i,String.valueOf(frame.get(i)));
                    return frame.push(value);
                }
                Object[] args=new Object[count];
                for (int i=0;i<count;i++) args[i]=frame.get(i);
                return frame.push(LuaManager.thread.call(nativeFunction,args));
            });
        }
    }

    private void installLoader() {
        Map<String,Object> loaded=new HashMap<>();
        Set<String> loading=new HashSet<>();
        LuaManager.env.rawset("require",(JavaFunction)(frame,count)->{
            String module=(String)frame.get(0);
            if (module.contains("..") || module.startsWith("/") || module.contains(":"))
                throw new IllegalArgumentException("Invalid module: "+module);
            KahluaTable services=(KahluaTable)LuaManager.env.rawget("PreviewServices");
            Object fixture=services.rawget(module);
            if (fixture!=null) {
                if (!module.startsWith("EmberRoutesProbe/") || module.startsWith("EmberRoutesProbe/UI/"))
                    throw new IllegalArgumentException("Only business modules may use fixtures: "+module);
                return frame.push(fixture);
            }
            if (loaded.containsKey(module)) return frame.push(loaded.get(module));
            if (!loading.add(module)) throw new IllegalArgumentException("Recursive UI module: "+module);
            try {
                Path source=null;
                if (module.startsWith("preview/")) source=repo.resolve("tools/ui-preview/"+module.substring(8)+".lua");
                else for (String dir:List.of("shared","client")) {
                    Path base=module.startsWith("EmberRoutesProbe/")
                        ? repo.resolve("Contents/mods/EmberRoutesProbe/42/media/lua") : Path.of("media/lua");
                    Path candidate=base.resolve(dir).resolve(module+".lua").toAbsolutePath().normalize();
                    sources.put(candidate,PreviewLiveControl.Stamp.read(candidate));
                    if (Files.isRegularFile(candidate)) { source=candidate; break; }
                }
                if (source==null) throw new IllegalArgumentException("Missing UI module: "+module);
                Object[] result=execute(source);
                Object value=result.length>1?result[1]:null;
                loaded.put(module,value);
                return frame.push(value);
            } catch (IOException failure) { throw new UncheckedIOException(failure); }
            finally { loading.remove(module); }
        });
    }

    @Override public void close() {
        if (closed) return;
        closed=true;
        try {
            if (root!=null) releaseNativeTree(root);
            if (LuaManager.env!=null) {
                Object disposer=LuaManager.env.rawget("PreviewDispose");
                if (disposer!=null) call(disposer);
            }
        } finally {
            // This JVM owns all of these UI/Events; it never joins a running game.
            UIManager.clearArrays(); LuaEventManager.Reset(); LuaHookManager.Reset();
            guarded.clear(); origins.clear(); root=null; scene=null;
            System.out.println("DISPOSE generation "+generation);
        }
    }
    private static void releaseNativeTree(UIElement element) {
        for (UIElement child:new ArrayList<>(element.getControls())) releaseNativeTree(child);
        if (element instanceof UITextBox2 entry) entry.unfocus();
        element.setCapture(false);
    }
}
