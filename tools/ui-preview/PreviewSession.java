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

    private static final Map<Character, Character> S2T = Map.ofEntries(
        Map.entry('许', '許'), Map.entry('载', '載'), Map.entry('级', '級'), Map.entry('键', '鍵'),
        Map.entry('识', '識'), Map.entry('别', '別'), Map.entry('预', '預'), Map.entry('贴', '貼'),
        Map.entry('粘', '貼'), Map.entry('应', '應'), Map.entry('医', '醫'), Map.entry('药', '藥'),
        Map.entry('开', '開'), Map.entry('叠', '疊'), Map.entry('个', '個'), Map.entry('总', '總'),
        Map.entry('两', '兩'), Map.entry('关', '關'), Map.entry('单', '單'), Map.entry('体', '體'),
        Map.entry('数', '數'), Map.entry('据', '據'), Map.entry('联', '聯'), Map.entry('机', '機'),
        Map.entry('车', '車'), Map.entry('队', '隊'), Map.entry('给', '給'), Map.entry('还', '還'),
        Map.entry('动', '動'), Map.entry('态', '態'), Map.entry('画', '畫'), Map.entry('结', '結'),
        Map.entry('显', '顯'), Map.entry('进', '進'), Map.entry('选', '選'), Map.entry('择', '擇'),
        Map.entry('项', '項'), Map.entry('设', '設'), Map.entry('类', '類'), Map.entry('权', '權'),
        Map.entry('仓', '倉'), Map.entry('库', '庫'), Map.entry('这', '這'), Map.entry('无', '無'),
        Map.entry('写', '寫'), Map.entry('读', '讀'), Map.entry('档', '檔'), Map.entry('区', '區'),
        Map.entry('块', '塊'), Map.entry('划', '劃'), Map.entry('间', '間'), Map.entry('门', '門'),
        Map.entry('墙', '牆'), Map.entry('视', '視'), Map.entry('标', '標'), Map.entry('题', '題'),
        Map.entry('栏', '欄'), Map.entry('钮', '鈕'), Map.entry('紧', '緊'), Map.entry('凑', '湊'),
        Map.entry('现', '現'), Map.entry('构', '構'), Map.entry('顶', '頂'), Map.entry('胶', '膠'),
        Map.entry('树', '樹'), Map.entry('优', '優'), Map.entry('势', '勢'), Map.entry('层', '層'),
        Map.entry('双', '雙'), Map.entry('导', '導'), Map.entry('台', '臺'), Map.entry('观', '觀'),
        Map.entry('换', '換'), Map.entry('输', '輸'), Map.entry('纯', '純'), Map.entry('净', '淨'),
        Map.entry('质', '質'), Map.entry('彻', '徹'), Map.entry('极', '極'), Map.entry('创', '創'),
        Map.entry('调', '調'), Map.entry('虚', '虛'), Map.entry('图', '圖'), Map.entry('挡', '擋'),
        Map.entry('审', '審'), Map.entry('独', '獨'), Map.entry('复', '復'), Map.entry('余', '餘'),
        Map.entry('并', '併'), Map.entry('点', '點'), Map.entry('击', '擊'), Map.entry('觉', '覺'),
        Map.entry('资', '資'), Map.entry('备', '備'), Map.entry('条', '條'), Map.entry('认', '認'),
        Map.entry('军', '軍'), Map.entry('枪', '槍'), Map.entry('战', '戰'), Map.entry('疗', '療'),
        Map.entry('业', '業'), Map.entry('烬', '燼'), Map.entry('测', '測'),
        Map.entry('试', '試'), Map.entry('发', '發'), Map.entry('启', '啟'),
        Map.entry('败', '敗'), Map.entry('请', '請'), Map.entry('志', '誌')
    );

    private static String s2t(String input) {
        if (input == null || input.isEmpty()) return input;
        StringBuilder sb = new StringBuilder(input.length());
        for (int i = 0; i < input.length(); i++) {
            char c = input.charAt(i);
            sb.append(S2T.getOrDefault(c, c));
        }
        return sb.toString();
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
                    if ("CN".equals(language)) value = s2t(value);
                    return frame.push(value);
                }
                Object[] args=new Object[count];
                for (int i=0;i<count;i++) args[i]=frame.get(i);
                Object res = LuaManager.thread.call(nativeFunction,args);
                if (res instanceof String s && "CN".equals(language)) res = s2t(s);
                return frame.push(res);
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
                    Path candidateVehicles=base.resolve(dir).resolve("Vehicles").resolve(module+".lua").toAbsolutePath().normalize();
                    if (Files.isRegularFile(candidateVehicles)) { source=candidateVehicles; break; }
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
